import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:pencilai_whitebaord_app/features/whiteboard/models/stroke_element.dart';
import 'package:pencilai_whitebaord_app/features/whiteboard/models/text_element.dart';
import 'package:pencilai_whitebaord_app/features/whiteboard/services/ai_service.dart';
import 'package:pencilai_whitebaord_app/features/whiteboard/services/board_storage_service.dart';
import 'package:pencilai_whitebaord_app/features/whiteboard/services/smart_writing_service.dart';
import 'package:pencilai_whitebaord_app/features/whiteboard/state/whiteboard_provider.dart';
import 'package:pencilai_whitebaord_app/features/whiteboard/widgets/object_handles.dart';
import 'package:pencilai_whitebaord_app/features/whiteboard/widgets/whiteboard_canvas.dart';

Future<ui.Image> _decodePng(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

Future<bool> _hasDarkPixelInRegion(
  ui.Image image, {
  required int startX,
  required int endX,
}) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) return false;
  final bytes = data.buffer.asUint8List();
  final width = image.width;
  final height = image.height;
  final clampedStart = startX.clamp(0, width - 1);
  final clampedEnd = endX.clamp(0, width - 1);

  for (int y = 0; y < height; y++) {
    for (int x = clampedStart; x <= clampedEnd; x++) {
      final offset = (y * width + x) * 4;
      final r = bytes[offset];
      final g = bytes[offset + 1];
      final b = bytes[offset + 2];
      // Non-white ink pixel
      if (r < 200 || g < 200 || b < 200) {
        return true;
      }
    }
  }
  return false;
}

StrokeElement _makeHorizontalStroke({
  String id = 'stroke_1',
  Color color = Colors.black,
  double startX = 100,
  double endX = 240,
  double y = 120,
  double strokeWidth = 3.0,
  double scale = 1.0,
  double rotation = 0.0,
}) {
  return StrokeElement(
    id: id,
    position: Offset(startX, y),
    points: [
      Offset(startX, y),
      Offset((startX + endX) / 2, y + 25),
      Offset(endX, y),
    ],
    color: color,
    strokeWidth: strokeWidth,
    scale: scale,
    rotation: rotation,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AiService OCR resilience tests', () {
    test('uses sufficient maxOutputTokens, filters thought parts, and retries across 429/200-empty models', () async {
      final requestedModels = <String>[];
      int? capturedMaxTokens;

      final mockClient = MockClient((request) async {
        requestedModels.add(request.url.pathSegments.last.split(':').first);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        capturedMaxTokens = body['generationConfig']?['maxOutputTokens'] as int?;

        if (requestedModels.length == 1) {
          return http.Response('{"error":{"message":"rate limited"}}', 429);
        }
        if (requestedModels.length == 2) {
          // Simulates empty 200 response from candidate model
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'thought': true, 'text': 'internal thinking'},
                    ],
                  },
                },
              ],
            }),
            200,
          );
        }

        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'thought': true, 'text': 'analyzing image...'},
                    {'text': '```\nPhysics Notes\n```'},
                  ],
                },
              },
            ],
          }),
          200,
        );
      });

      final ai = AiService(client: mockClient, apiKey: 'AQ.test_key');
      final result = await ai.recognizeHandwriting(
        imageBytes: Uint8List.fromList([1, 2, 3]),
        language: 'English',
      );

      expect(capturedMaxTokens, equals(1024));
      expect(requestedModels.length, equals(3));
      expect(result, equals('Physics Notes'));
      expect(AiService.isErrorResponse(result), isFalse);
    });

    test('stops immediately on 401 auth failure and flags error response', () async {
      int calls = 0;
      final mockClient = MockClient((request) async {
        calls++;
        return http.Response('{"error":{"message":"unauthorized"}}', 401);
      });

      final ai = AiService(client: mockClient, apiKey: 'AQ.test_key');
      final result = await ai.recognizeHandwriting(
        imageBytes: Uint8List.fromList([1, 2, 3]),
      );

      expect(calls, equals(1));
      expect(AiService.isErrorResponse(result), isTrue);
    });

    test('times out hung requests instead of waiting indefinitely', () async {
      final mockClient = MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return http.Response('{}', 200);
      });

      final ai = AiService(
        client: mockClient,
        apiKey: 'AQ.test_key',
        requestTimeout: const Duration(milliseconds: 25),
      );
      final result = await ai.recognizeHandwriting(
        imageBytes: Uint8List.fromList([1, 2, 3]),
      );

      expect(AiService.isErrorResponse(result), isTrue);
      expect(result, contains('TimeoutException'));
    });
  });

  group('BoardStorageService OCR capture tests', () {
    final storage = BoardStorageService();

    test('renders white ink strokes as high-contrast dark pixels for both OCR paths', () async {
      final whiteStroke = _makeHorizontalStroke(
        color: Colors.white,
        startX: 50,
        endX: 250,
        y: 80,
      );

      final ocrBytes = await storage.captureStrokesForOcrBytes([whiteStroke]);
      final cloudBytes = await storage.captureSelectedElementsBytes([whiteStroke]);

      expect(ocrBytes, isNotNull);
      expect(cloudBytes, isNotNull);

      final ocrImage = await _decodePng(ocrBytes!);
      final cloudImage = await _decodePng(cloudBytes!);
      try {
        expect(
          await _hasDarkPixelInRegion(ocrImage, startX: 0, endX: ocrImage.width - 1),
          isTrue,
          reason: 'White stroke on dark board must render darkly for ML Kit OCR',
        );
        expect(
          await _hasDarkPixelInRegion(cloudImage, startX: 0, endX: cloudImage.width - 1),
          isTrue,
          reason: 'White stroke must render visibly for Cloud OCR fallback',
        );
      } finally {
        ocrImage.dispose();
        cloudImage.dispose();
      }
    });

    test('preserves full width of wide >1500px sentences without horizontal clipping', () async {
      final wideStroke = _makeHorizontalStroke(
        color: Colors.black,
        startX: 0,
        endX: 1800,
        y: 100,
        strokeWidth: 4.0,
      );

      final ocrBytes = await storage.captureStrokesForOcrBytes([wideStroke]);
      expect(ocrBytes, isNotNull);

      final image = await _decodePng(ocrBytes!);
      try {
        expect(image.width, lessThanOrEqualTo(2048));
        // Rightmost quarter must still contain the right end of the stroke
        final rightQuarterStart = (image.width * 0.75).floor();
        expect(
          await _hasDarkPixelInRegion(
            image,
            startX: rightQuarterStart,
            endX: image.width - 1,
          ),
          isTrue,
          reason: 'Wide strokes must scale proportionally instead of clipping past 1024px',
        );
      } finally {
        image.dispose();
      }
    });

    test('computes rotation- and scale-aware visual bounds', () {
      final stroke = _makeHorizontalStroke(
        startX: 100,
        endX: 300,
        y: 100,
        scale: 2.0,
        rotation: math.pi / 2,
      );

      final visualBounds = storage.getElementVisualBounds(stroke);
      expect(visualBounds.height, greaterThan(350));
    });
  });

  group('SmartWritingService hybrid OCR & validation tests', () {
    late WhiteboardProvider provider;

    setUp(() {
      provider = WhiteboardProvider();
    });

    test('cleanAndValidateRecognizedText keeps real words and all script alphabets while rejecting noise', () {
      final service = SmartWritingService.forTest();

      // Reject noise & empty OCR disclaimers
      expect(service.cleanAndValidateRecognizedText(''), isNull);
      expect(service.cleanAndValidateRecognizedText('|'), isNull);
      expect(service.cleanAndValidateRecognizedText('--- ... _ /'), isNull);
      expect(service.cleanAndValidateRecognizedText('No text visible'), isNull);
      expect(service.cleanAndValidateRecognizedText('N/A'), isNull);
      expect(service.cleanAndValidateRecognizedText('Error generating Handwriting OCR (500): err'), isNull);

      // Preserve legitimate chemistry / code / general words
      expect(service.cleanAndValidateRecognizedText('Na'), equals('Na'));
      expect(service.cleanAndValidateRecognizedText('None'), equals('None'));
      expect(service.cleanAndValidateRecognizedText('Null'), equals('Null'));
      expect(service.cleanAndValidateRecognizedText('Error'), equals('Error'));
      expect(service.cleanAndValidateRecognizedText('Error analysis'), equals('Error analysis'));

      // Support all configured Unicode scripts including Kannada, Punjabi, Russian, Arabic, CJK
      expect(service.cleanAndValidateRecognizedText('ಕನ್ನಡ'), equals('ಕನ್ನಡ'));
      expect(service.cleanAndValidateRecognizedText('हिन्दी'), equals('हिन्दी'));
      expect(service.cleanAndValidateRecognizedText('ਪੰਜਾਬੀ'), equals('ਪੰਜਾਬੀ'));
      expect(service.cleanAndValidateRecognizedText('Привет'), equals('Привет'));
      expect(service.cleanAndValidateRecognizedText('مرحبا'), equals('مرحبا'));
      expect(service.cleanAndValidateRecognizedText('你好'), equals('你好'));
      expect(service.cleanAndValidateRecognizedText('こんにちは'), equals('こんにちは'));
      expect(service.cleanAndValidateRecognizedText('안녕하세요'), equals('안녕하세요'));
    });

    test('falls back to Cloud OCR when on-device OCR returns punctuation noise like "|"', () async {
      bool cloudCalled = false;
      final stroke = _makeHorizontalStroke(
        id: 'white_stroke_1',
        color: Colors.white,
        startX: 100,
        endX: 280,
        y: 140,
      );
      provider.addElement(stroke);
      provider.selectElement(stroke.id);

      final service = SmartWritingService.forTest(
        digitalInkOcr: (_, _, _) async => null,
        onDeviceOcr: (bytes, lang) async => '|',
        cloudOcr: (bytes, lang) async {
          cloudCalled = true;
          expect(bytes.isNotEmpty, isTrue);
          return 'Photosynthesis';
        },
      );

      final ok = await service.convertSelectedStrokesToText(provider);

      expect(ok, isTrue);
      expect(cloudCalled, isTrue);
      expect(service.lastErrorMessage, isNull);
      expect(provider.currentPage.elements.length, equals(1));
      final converted = provider.currentPage.elements.first as TextElement;
      expect(converted.text, equals('Photosynthesis'));
      expect(converted.color, equals(Colors.white));
    });

    test('does not call Cloud OCR when on-device ML Kit returns valid Latin text', () async {
      bool cloudCalled = false;
      final stroke = _makeHorizontalStroke(id: 'latin_stroke_1');
      provider.addElement(stroke);
      provider.selectElement(stroke.id);

      final service = SmartWritingService.forTest(
        digitalInkOcr: (_, _, _) async => null,
        onDeviceOcr: (bytes, lang) async => 'Hello World',
        cloudOcr: (bytes, lang) async {
          cloudCalled = true;
          return 'Should not be needed';
        },
      );

      final ok = await service.convertSelectedStrokesToText(provider);

      expect(ok, isTrue);
      expect(cloudCalled, isFalse);
      final converted = provider.currentPage.elements.first as TextElement;
      expect(converted.text, equals('Hello World'));
    });

    test('skips ML Kit image OCR for unsupported scripts and uses Cloud OCR fallback', () async {
      bool mlKitCalled = false;
      String? capturedLanguage;
      final stroke = _makeHorizontalStroke(id: 'kn_stroke_1');
      provider.setSelectedHandwritingLanguage('Kannada');
      provider.addElement(stroke);
      provider.selectElement(stroke.id);

      final service = SmartWritingService.forTest(
        digitalInkOcr: (_, _, _) async => null,
        onDeviceOcr: (bytes, lang) async {
          mlKitCalled = true;
          return 'wrong latin guess';
        },
        cloudOcr: (bytes, lang) async {
          capturedLanguage = lang;
          return 'ನಮಸ್ಕಾರ';
        },
      );

      final ok = await service.convertSelectedStrokesToText(provider);

      expect(ok, isTrue);
      expect(mlKitCalled, isFalse);
      expect(capturedLanguage, equals('Kannada'));
      final converted = provider.currentPage.elements.first as TextElement;
      expect(converted.text, equals('ನಮಸ್ಕಾರ'));
    });

    test('resolves BCP-47 Digital Ink tags and bundled TextRecognizer scripts accurately', () {
      expect(SmartWritingService.resolveHandwritingBcpCode('Follow System (English)'), equals('en'));
      expect(SmartWritingService.resolveHandwritingBcpCode('Hindi'), equals('hi'));
      expect(SmartWritingService.resolveHandwritingBcpCode('हिन्दी'), equals('hi'));
      expect(SmartWritingService.resolveHandwritingBcpCode('Chinese'), equals('zh-Hani'));
      expect(SmartWritingService.resolveHandwritingBcpCode('Kannada'), equals('kn'));

      expect(SmartWritingService.textRecognitionScriptForBcp('hi')?.name, equals('devanagiri'));
      expect(SmartWritingService.textRecognitionScriptForBcp('mr')?.name, equals('devanagiri'));
      expect(SmartWritingService.textRecognitionScriptForBcp('en')?.name, equals('latin'));
      expect(SmartWritingService.textRecognitionScriptForBcp('kn'), isNull);
    });

    test('buildDigitalInk normalizes transformed stroke coordinates and monotonic timestamps', () {
      final service = SmartWritingService.forTest();
      final storage = BoardStorageService();
      final stroke = _makeHorizontalStroke(
        id: 'ink_1',
        startX: 200,
        endX: 300,
        y: 150,
        scale: 2.0,
      );
      final bounds = storage.getCombinedVisualBounds([stroke])!;
      final ink = service.buildDigitalInk([stroke], bounds);

      expect(ink.strokes.length, equals(1));
      expect(ink.strokes.first.points.length, equals(3));
      final pts = ink.strokes.first.points;
      expect(pts[0].x, greaterThanOrEqualTo(0));
      expect(pts[0].y, greaterThanOrEqualTo(0));
      expect(pts[1].t, greaterThan(pts[0].t));
      expect(pts[2].t, greaterThan(pts[1].t));
    });

    test('converts Hindi handwriting offline via Digital Ink primary recognizer', () async {
      bool cloudCalled = false;
      String? capturedBcp;
      final stroke = _makeHorizontalStroke(id: 'hi_digital_1');
      provider.setSelectedHandwritingLanguage('Hindi');
      provider.addElement(stroke);
      provider.selectElement(stroke.id);

      final service = SmartWritingService.forTest(
        digitalInkOcr: (strokes, bounds, bcpCode) async {
          capturedBcp = bcpCode;
          return 'नमस्ते';
        },
        cloudOcr: (bytes, lang) async {
          cloudCalled = true;
          return 'Should not call cloud';
        },
      );

      final ok = await service.convertSelectedStrokesToText(provider);

      expect(ok, isTrue);
      expect(capturedBcp, equals('hi'));
      expect(cloudCalled, isFalse);
      final converted = provider.currentPage.elements.first as TextElement;
      expect(converted.text, equals('नमस्ते'));
    });

    test('falls back to bundled Devanagari TextRecognizer for Hindi when Digital Ink misses', () async {
      bool imageOcrCalled = false;
      bool cloudCalled = false;
      final stroke = _makeHorizontalStroke(id: 'hi_img_1');
      provider.setSelectedHandwritingLanguage('Hindi');
      provider.addElement(stroke);
      provider.selectElement(stroke.id);

      final service = SmartWritingService.forTest(
        digitalInkOcr: (_, _, _) async => null,
        onDeviceOcr: (bytes, lang) async {
          imageOcrCalled = true;
          expect(lang, equals('Hindi'));
          return 'भारत';
        },
        cloudOcr: (bytes, lang) async {
          cloudCalled = true;
          return 'Should not call cloud';
        },
      );

      final ok = await service.convertSelectedStrokesToText(provider);

      expect(ok, isTrue);
      expect(imageOcrCalled, isTrue);
      expect(cloudCalled, isFalse);
      final converted = provider.currentPage.elements.first as TextElement;
      expect(converted.text, equals('भारत'));
    });

    test('surfaces actionable error message and keeps strokes untouched on Cloud API failure', () async {
      final stroke = _makeHorizontalStroke(id: 'fail_stroke_1');
      provider.addElement(stroke);
      provider.selectElement(stroke.id);

      final service = SmartWritingService.forTest(
        digitalInkOcr: (_, _, _) async => null,
        onDeviceOcr: (bytes, lang) async => '',
        cloudOcr: (bytes, lang) async =>
            'Error generating Handwriting OCR (429): Quota exceeded',
      );

      final ok = await service.convertSelectedStrokesToText(provider);

      expect(ok, isFalse);
      expect(service.lastErrorMessage, isNotNull);
      expect(service.lastErrorMessage, contains('busy'));
      expect(provider.currentPage.elements.length, equals(1));
      expect(provider.currentPage.elements.first, isA<StrokeElement>());
    });

    test('stops immediately on SocketException instead of retrying all models', () async {
      int calls = 0;
      final mockClient = MockClient((request) async {
        calls++;
        throw const SocketException('Failed host lookup');
      });

      final ai = AiService(client: mockClient, apiKey: 'AQ.test_key');
      final result = await ai.recognizeHandwriting(
        imageBytes: Uint8List.fromList([1, 2, 3]),
      );

      expect(calls, equals(1));
      expect(AiService.isErrorResponse(result), isTrue);
      expect(result, contains('SocketException'));
    });

    test('renders small strokes at upscaled height for legible Devanagari/Latin OCR', () async {
      final smallStroke = _makeHorizontalStroke(
        id: 'small_ocr_1',
        startX: 100,
        endX: 190,
        y: 100,
        strokeWidth: 4.0,
      );
      final storage = BoardStorageService();
      final bytes = await storage.captureStrokesForOcrBytes([smallStroke]);
      expect(bytes, isNotNull);

      final image = await _decodePng(bytes!);
      try {
        // Dynamically upscaled above 2x + padding so small strokes stay sharp.
        expect(image.height, greaterThanOrEqualTo(240));
        expect(image.width, greaterThanOrEqualTo(360));
        expect(
          await _hasDarkPixelInRegion(image, startX: 0, endX: image.width - 1),
          isTrue,
        );
      } finally {
        image.dispose();
      }
    });

    test('sorts out-of-order strokes spatially by line and x-position with attached accents', () {
      final service = SmartWritingService.forTest();
      final line2Word = StrokeElement(
        id: 'line2',
        position: const Offset(100, 220),
        points: const [Offset(100, 220), Offset(130, 260), Offset(160, 220)],
        color: Colors.black,
        strokeWidth: 3.0,
      );
      final line1Second = StrokeElement(
        id: 'line1_second',
        position: const Offset(200, 80),
        points: const [Offset(200, 80), Offset(220, 125), Offset(240, 80)],
        color: Colors.black,
        strokeWidth: 3.0,
      );
      final line1First = StrokeElement(
        id: 'line1_first',
        position: const Offset(90, 80),
        points: const [Offset(90, 80), Offset(110, 125), Offset(130, 80)],
        color: Colors.black,
        strokeWidth: 3.0,
      );
      final shirorekha = StrokeElement(
        id: 'shirorekha',
        position: const Offset(85, 76),
        points: const [Offset(85, 76), Offset(245, 76)],
        color: Colors.black,
        strokeWidth: 3.0,
      );

      final sorted = service.sortStrokesSpatiallyForOcr([
        line2Word,
        line1Second,
        line1First,
        shirorekha,
      ]);

      expect(
        sorted.map((s) => s.id).toList(),
        equals(['shirorekha', 'line1_first', 'line1_second', 'line2']),
      );
    });

    test('retries Cloud OCR when offline engine emits suspicious 1-char result for wide multi-stroke word', () async {
      bool cloudCalled = false;
      final strokes = List.generate(
        5,
        (i) => _makeHorizontalStroke(
          id: 'word_$i',
          startX: 100.0 + i * 45,
          endX: 135.0 + i * 45,
          y: 100.0,
        ),
      );
      for (final s in strokes) {
        provider.addElement(s);
        provider.selectElement(s.id, multi: true);
      }

      final service = SmartWritingService.forTest(
        digitalInkOcr: (_, _, _) async => null,
        onDeviceOcr: (_, _) async => 'I',
        cloudOcr: (_, _) async {
          cloudCalled = true;
          return 'India';
        },
      );

      final ok = await service.convertSelectedStrokesToText(provider);

      expect(ok, isTrue);
      expect(cloudCalled, isTrue);
      final converted = provider.currentPage.elements.first as TextElement;
      expect(converted.text, equals('India'));
    });

    test('keeps suspicious 1-char result instead of failing if Cloud OCR is offline', () async {
      final strokes = List.generate(
        4,
        (i) => _makeHorizontalStroke(
          id: 'fallback_$i',
          startX: 100.0 + i * 50,
          endX: 140.0 + i * 50,
          y: 100.0,
        ),
      );
      for (final s in strokes) {
        provider.addElement(s);
        provider.selectElement(s.id, multi: true);
      }

      final service = SmartWritingService.forTest(
        digitalInkOcr: (_, _, _) async => null,
        onDeviceOcr: (_, _) async => 'I',
        cloudOcr: (_, _) async => 'Error generating Handwriting OCR: SocketException',
      );

      final ok = await service.convertSelectedStrokesToText(provider);

      expect(ok, isTrue);
      final converted = provider.currentPage.elements.first as TextElement;
      expect(converted.text, equals('I'));
    });

    test('atomic single-step undo restores all replaced strokes and redo reapplies TextElement', () async {
      final s1 = _makeHorizontalStroke(id: 'u1', startX: 80, endX: 140);
      final s2 = _makeHorizontalStroke(id: 'u2', startX: 155, endX: 220);
      provider.addElement(s1);
      provider.addElement(s2);
      provider.selectElement(s1.id);
      provider.selectElement(s2.id, multi: true);

      final service = SmartWritingService.forTest(
        digitalInkOcr: (_, _, _) async => 'Hello World',
      );

      final ok = await service.convertSelectedStrokesToText(provider);
      expect(ok, isTrue);
      expect(provider.currentPage.elements.length, equals(1));
      expect(provider.currentPage.elements.first, isA<TextElement>());

      provider.undo();
      expect(provider.currentPage.elements.length, equals(2));
      expect(provider.currentPage.elements.every((e) => e is StrokeElement), isTrue);

      provider.redo();
      expect(provider.currentPage.elements.length, equals(1));
      expect(provider.currentPage.elements.first, isA<TextElement>());
    });

    test('computes per-line font size cleanly for multiline OCR results', () {
      const multilineBounds = Rect.fromLTWH(50, 50, 300, 240);
      final singleLineSize = SmartWritingService.computeOcrFontSize(
        const Rect.fromLTWH(50, 50, 200, 60),
        'Hello',
      );
      final threeLineSize = SmartWritingService.computeOcrFontSize(
        multilineBounds,
        'Line one\nLine two\nLine three',
      );
      expect(singleLineSize, closeTo(33.0, 0.1));
      expect(threeLineSize, equals(42.0));
    });

    test('lasso selection includes strokes with minor overhanging edges and excludes mostly outside strokes', () {
      final enclosedStroke = StrokeElement(
        id: 'mostly_in',
        position: const Offset(100, 100),
        points: const [
          Offset(100, 110),
          Offset(120, 110),
          Offset(140, 110),
          Offset(160, 110),
          Offset(180, 110),
          Offset(205, 110), // overhangs slightly past x=195
        ],
        color: Colors.black,
        strokeWidth: 3.0,
      );
      final neighborStroke = StrokeElement(
        id: 'mostly_out',
        position: const Offset(190, 110),
        points: const [
          Offset(190, 110), // barely inside
          Offset(210, 110),
          Offset(230, 110),
          Offset(250, 110),
          Offset(270, 110),
        ],
        color: Colors.black,
        strokeWidth: 3.0,
      );
      provider.addElement(enclosedStroke);
      provider.addElement(neighborStroke);

      final lasso = Path()..addRect(const Rect.fromLTWH(80, 80, 115, 80));
      provider.completeLassoSelection(lasso);

      expect(provider.selectedElementIds, contains('mostly_in'));
      expect(provider.selectedElementIds, isNot(contains('mostly_out')));
    });

    test('bundled offline languages (English, Hindi, Marathi) report ready immediately', () {
      expect(provider.isHandwritingLanguageReady('en'), isTrue);
      expect(provider.isHandwritingLanguageReady('Hindi'), isTrue);
      expect(provider.isHandwritingLanguageReady('hi'), isTrue);
      expect(provider.isHandwritingLanguageReady('mr'), isTrue);
      expect(provider.isHandwritingLanguageReady('Kannada'), isFalse);
      // Digital Ink download state is tracked independently of bundled OCR readiness.
      expect(provider.isHandwritingLanguageDownloaded('hi'), isFalse);
    });

    testWidgets('Select tool starts lasso even when pointer begins near an existing stroke', (tester) async {
      final s1 = _makeHorizontalStroke(id: 'canvas_s1', startX: 120, endX: 170, y: 120);
      final s2 = _makeHorizontalStroke(id: 'canvas_s2', startX: 220, endX: 270, y: 120);
      provider.addElement(s1);
      provider.addElement(s2);
      provider.setTool(WhiteboardTool.select);

      await tester.pumpWidget(
        ChangeNotifierProvider<WhiteboardProvider>.value(
          value: provider,
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600,
                height: 400,
                child: WhiteboardCanvas(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Start drag at (110, 120) — within the 25px hitTest threshold of s1!
      final gesture = await tester.startGesture(const Offset(110, 120));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveTo(const Offset(95, 95));
      await gesture.moveTo(const Offset(290, 95));
      await gesture.moveTo(const Offset(290, 170));
      await gesture.moveTo(const Offset(95, 170));
      await gesture.moveTo(const Offset(95, 95));
      await gesture.up();
      await tester.pump();

      expect(provider.selectedElementIds, containsAll(['canvas_s1', 'canvas_s2']));

      // Now verify a short tap near s1 still single-selects s1 cleanly.
      provider.clearSelection();
      final tapGesture = await tester.startGesture(const Offset(122, 120));
      await tester.pump(const Duration(milliseconds: 16));
      await tapGesture.up();
      await tester.pump();

      expect(provider.selectedElementIds, equals({'canvas_s1'}));

      // Dispose widget cleanly so canvas timers shut down before test end.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    test('sends AQ auth key via header without ?key= query param and iterates active fallback models', () async {
      final capturedRequests = <http.Request>[];
      final thinkingConfigs = <String, dynamic>{};

      final mockClient = MockClient((request) async {
        capturedRequests.add(request);
        final model = request.url.pathSegments.last.split(':').first;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        thinkingConfigs[model] = body['generationConfig']?['thinkingConfig'];

        if (capturedRequests.length < 3) {
          return http.Response('{"error":{"message":"overloaded"}}', 503);
        }
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'Homework OK'},
                  ],
                },
              },
            ],
          }),
          200,
        );
      });

      final ai = AiService(
        client: mockClient,
        apiKey: 'AQ.test_header_key',
      );
      final result = await ai.recognizeHandwriting(
        imageBytes: Uint8List.fromList([1, 2, 3]),
        language: 'English',
      );

      expect(result, equals('Homework OK'));
      expect(capturedRequests.length, equals(3));
      for (final req in capturedRequests) {
        expect(req.url.host, equals('generativelanguage.googleapis.com'));
        expect(req.url.queryParameters.containsKey('key'), isFalse);
        expect(req.headers['x-goog-api-key'], equals('AQ.test_header_key'));
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['contents']?[0]?['role'], equals('user'));
      }
      expect(
        capturedRequests.map((r) => r.url.pathSegments.last.split(':').first).toList(),
        equals([
          'gemini-3.5-flash-lite',
          'gemini-3.5-flash',
          'gemini-flash-latest',
        ]),
      );
      expect(thinkingConfigs['gemini-3.5-flash-lite'], equals({'thinkingLevel': 'minimal'}));
      expect(thinkingConfigs['gemini-3.5-flash'], equals({'thinkingLevel': 'minimal'}));
      expect(thinkingConfigs['gemini-flash-latest'], equals({'thinkingLevel': 'low'}));
    });

    test('sets minimal thinkingLevel for Gemini 3.5 OCR and stops on 400 API_KEY_INVALID', () async {
      Map<String, dynamic>? firstConfig;
      int calls = 0;

      final flashClient = MockClient((request) async {
        calls++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        firstConfig ??= body['generationConfig'] as Map<String, dynamic>?;
        return http.Response(
          '{"error":{"message":"API key not valid","status":"INVALID_ARGUMENT"}}',
          400,
        );
      });

      final ai = AiService(client: flashClient, apiKey: 'AQ.test_key');
      final res = await ai.recognizeHandwriting(
        imageBytes: Uint8List.fromList([1, 2, 3]),
        language: 'English',
      );

      expect(firstConfig?['maxOutputTokens'], equals(1024));
      expect(firstConfig?['thinkingConfig']?['thinkingLevel'], equals('minimal'));
      expect(calls, equals(1));
      expect(AiService.isErrorResponse(res), isTrue);

      final missingKeyAi = AiService(client: flashClient, apiKey: '');
      final missingRes = await missingKeyAi.recognizeHandwriting(
        imageBytes: Uint8List.fromList([1, 2, 3]),
      );
      expect(AiService.isErrorResponse(missingRes), isTrue);
      expect(missingRes, contains('Gemini API Key is missing'));
      expect(calls, equals(1));
    });

    test('aborts cleanly if selected strokes are deleted before OCR completes', () async {
      final firstCompleter = Completer<String?>();
      final s1 = _makeHorizontalStroke(id: 'deleted_mid_ocr', startX: 100, endX: 200);
      final s2 = _makeHorizontalStroke(id: 'new_word_after_delete', startX: 300, endX: 400);
      provider.addElement(s1);
      provider.selectElement(s1.id);

      final service = SmartWritingService.forTest(
        digitalInkOcr: (_, _, _) => firstCompleter.future,
      );

      final futureOk = service.convertSelectedStrokesToText(provider);
      await Future<void>.delayed(Duration.zero);

      // User deletes s1 and writes s2 before OCR returns.
      provider.removeSelectedElements();
      provider.addElement(s2);
      provider.selectElement(s2.id);

      firstCompleter.complete('Oldword');
      final ok = await futureOk;

      expect(ok, isFalse);
      expect(provider.currentPage.elements.length, equals(1));
      expect(provider.currentPage.elements.first.id, equals('new_word_after_delete'));
    });

    testWidgets('ObjectHandles resets SmartWrite loading state after Delete so second word converts normally', (tester) async {
      final firstCompleter = Completer<String?>();
      int callCount = 0;

      final service = SmartWritingService.forTest(
        digitalInkOcr: (_, _, _) {
          callCount++;
          if (callCount == 1) {
            return firstCompleter.future;
          }
          return Future.value('SecondWord');
        },
      );

      final s1 = _makeHorizontalStroke(
        id: 'word_1',
        startX: 350,
        endX: 470,
        y: 120,
      );
      provider.addElement(s1);
      provider.selectElement(s1.id);

      await tester.pumpWidget(
        ChangeNotifierProvider<WhiteboardProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 1024,
                height: 700,
                child: Stack(
                  children: [
                    ObjectHandles(smartWritingService: service),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Tap SmartWrite on first word -> enters loading state.
      await tester.tap(find.text('SmartWrite'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // User taps Delete while SmartWrite is still loading.
      await tester.tap(find.text('Delete'));
      await tester.pump();
      expect(provider.currentPage.elements, isEmpty);

      // User draws & selects a second word: SmartWrite must NOT be stuck loading.
      final s2 = _makeHorizontalStroke(
        id: 'word_2',
        startX: 360,
        endX: 480,
        y: 150,
      );
      provider.addElement(s2);
      provider.selectElement(s2.id);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Now tapping SmartWrite on second word converts it to TextElement cleanly.
      await tester.tap(find.text('SmartWrite'));
      await tester.pumpAndSettle();

      expect(provider.currentPage.elements.length, equals(1));
      expect(provider.currentPage.elements.first, isA<TextElement>());
      expect(
        (provider.currentPage.elements.first as TextElement).text,
        equals('SecondWord'),
      );

      // Complete stale first future cleanly so its timeout timers cancel before exit.
      firstCompleter.complete('Firstword');
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    test('detects Latin gibberish and Hindi shirorekha reliably without false-flagging English', () {
      expect(SmartWritingService.isLikelyLatinGibberish('ffda'), isTrue);
      expect(SmartWritingService.isLikelyLatinGibberish('fTald'), isTrue);
      expect(SmartWritingService.isLikelyLatinGibberish('kiTaB'), isTrue);
      expect(SmartWritingService.isLikelyLatinGibberish('chld'), isTrue);
      expect(SmartWritingService.isLikelyLatinGibberish('k1t@b'), isTrue);
      expect(SmartWritingService.isLikelyLatinGibberish('Text'), isFalse);
      expect(SmartWritingService.isLikelyLatinGibberish('SmartWrite'), isFalse);
      expect(SmartWritingService.isLikelyLatinGibberish('Book'), isFalse);
      expect(SmartWritingService.isLikelyLatinGibberish('Hello World'), isFalse);
      expect(SmartWritingService.isLikelyLatinGibberish('Class 10'), isFalse);

      final service = SmartWritingService.forTest();
      final storage = BoardStorageService();

      // Hindi-like "किताब": top shirorekha spanning multiple vertical/loop strokes below.
      final hindiStrokes = [
        StrokeElement(
          id: 'bar',
          position: const Offset(100, 90),
          points: const [Offset(100, 90), Offset(260, 90)],
          color: Colors.black,
          strokeWidth: 3.0,
        ),
        StrokeElement(
          id: 'ka',
          position: const Offset(115, 100),
          points: const [Offset(115, 100), Offset(135, 145), Offset(115, 145)],
          color: Colors.black,
          strokeWidth: 3.0,
        ),
        StrokeElement(
          id: 'ta',
          position: const Offset(175, 100),
          points: const [Offset(175, 100), Offset(185, 145)],
          color: Colors.black,
          strokeWidth: 3.0,
        ),
        StrokeElement(
          id: 'ba',
          position: const Offset(225, 100),
          points: const [Offset(225, 100), Offset(240, 145)],
          color: Colors.black,
          strokeWidth: 3.0,
        ),
      ];
      final hindiBounds = storage.getCombinedVisualBounds(hindiStrokes)!;
      expect(
        service.hasLikelyDevanagariShirorekha(hindiStrokes, hindiBounds),
        isTrue,
      );

      // English-like "Text": T bar covers only 1 stem stroke, t bar covers 1 stem stroke.
      final englishStrokes = [
        StrokeElement(
          id: 'T_bar',
          position: const Offset(100, 90),
          points: const [Offset(100, 90), Offset(140, 90)],
          color: Colors.black,
          strokeWidth: 3.0,
        ),
        StrokeElement(
          id: 'T_stem',
          position: const Offset(120, 92),
          points: const [Offset(120, 92), Offset(120, 145)],
          color: Colors.black,
          strokeWidth: 3.0,
        ),
        StrokeElement(
          id: 'e_loop',
          position: const Offset(155, 115),
          points: const [Offset(155, 125), Offset(175, 120), Offset(165, 145)],
          color: Colors.black,
          strokeWidth: 3.0,
        ),
      ];
      final englishBounds = storage.getCombinedVisualBounds(englishStrokes)!;
      expect(
        service.hasLikelyDevanagariShirorekha(englishStrokes, englishBounds),
        isFalse,
      );
    });

    test('converts Hindi word written in Follow System mode via Devanagari instead of Latin gibberish', () async {
      bool cloudCalled = false;
      final hindiStrokes = [
        StrokeElement(
          id: 'k_bar',
          position: const Offset(100, 90),
          points: const [Offset(100, 90), Offset(250, 90)],
          color: Colors.black,
          strokeWidth: 3.0,
        ),
        StrokeElement(
          id: 'k_1',
          position: const Offset(120, 100),
          points: const [Offset(120, 100), Offset(130, 145)],
          color: Colors.black,
          strokeWidth: 3.0,
        ),
        StrokeElement(
          id: 'k_2',
          position: const Offset(180, 100),
          points: const [Offset(180, 100), Offset(190, 145)],
          color: Colors.black,
          strokeWidth: 3.0,
        ),
      ];
      // Default language is "Follow System (English)"
      for (final s in hindiStrokes) {
        provider.addElement(s);
        provider.selectElement(s.id, multi: true);
      }

      final service = SmartWritingService.forTest(
        digitalInkOcr: (_, _, _) async => null,
        onDeviceOcr: (bytes, lang) async => lang == 'Hindi' ? 'किताब' : 'ffda',
        cloudOcr: (_, _) async {
          cloudCalled = true;
          return 'CloudShouldNotBeNeeded';
        },
      );

      final ok = await service.convertSelectedStrokesToText(provider);

      expect(ok, isTrue);
      expect(cloudCalled, isFalse);
      final converted = provider.currentPage.elements.first as TextElement;
      expect(converted.text, equals('किताब'));
    });

    test('falls back to Cloud OCR when Latin emits gibberish and local Devanagari finds no Hindi', () async {
      bool cloudCalled = false;
      final stroke = _makeHorizontalStroke(id: 'gib_stroke_1');
      provider.addElement(stroke);
      provider.selectElement(stroke.id);

      final service = SmartWritingService.forTest(
        digitalInkOcr: (_, _, _) async => null,
        onDeviceOcr: (bytes, lang) async => lang == 'Hindi' ? '' : 'fTald',
        cloudOcr: (_, _) async {
          cloudCalled = true;
          return 'किताब';
        },
      );

      final ok = await service.convertSelectedStrokesToText(provider);

      expect(ok, isTrue);
      expect(cloudCalled, isTrue);
      final converted = provider.currentPage.elements.first as TextElement;
      expect(converted.text, equals('किताब'));
    });

    test('escalates to Cloud OCR when Hindi is selected but offline recognizer only outputs fake English', () async {
      bool cloudCalled = false;
      final stroke = _makeHorizontalStroke(id: 'hi_fake_en_1');
      provider.setSelectedHandwritingLanguage('Hindi');
      provider.addElement(stroke);
      provider.selectElement(stroke.id);

      final service = SmartWritingService.forTest(
        digitalInkOcr: (_, _, _) async => null,
        onDeviceOcr: (bytes, lang) async => 'Ktab',
        cloudOcr: (_, _) async {
          cloudCalled = true;
          return 'किताब';
        },
      );

      final ok = await service.convertSelectedStrokesToText(provider);

      expect(ok, isTrue);
      expect(cloudCalled, isTrue);
      final converted = provider.currentPage.elements.first as TextElement;
      expect(converted.text, equals('किताब'));
    });

    test('silently preloads Hindi then English handwriting packs in background without progress UI jank', () async {
      final downloadedOrder = <String>[];

      await provider.ensureDefaultHandwritingPacksInBackground(
        downloadedChecker: (_) async => false,
        connectivityChecker: () async => true,
        downloader: (langId) async {
          downloadedOrder.add(langId);
          return true;
        },
      );

      expect(downloadedOrder, equals(['hi', 'en']));
      expect(provider.isHandwritingLanguageDownloaded('hi'), isTrue);
      expect(provider.isHandwritingLanguageDownloaded('en'), isTrue);
      expect(provider.isHandwritingLanguageDownloaded('follow_system'), isTrue);
      expect(provider.handwritingDownloadProgress, isEmpty);

      // Re-running skips already-downloaded packs with zero extra downloads.
      await provider.ensureDefaultHandwritingPacksInBackground(
        downloadedChecker: (_) async => true,
        connectivityChecker: () async => true,
        downloader: (langId) async {
          downloadedOrder.add('unexpected_$langId');
          return true;
        },
      );
      expect(downloadedOrder, equals(['hi', 'en']));
    });

    test('skips background Hindi pack download cleanly while offline and avoids overlap', () async {
      final downloadCalls = <String>[];

      await provider.ensureDefaultHandwritingPacksInBackground(
        downloadedChecker: (_) async => false,
        connectivityChecker: () async => false,
        downloader: (langId) async {
          downloadCalls.add(langId);
          return true;
        },
      );

      expect(downloadCalls, isEmpty);
      expect(provider.isHandwritingLanguageDownloaded('hi'), isFalse);

      // Once connectivity returns, concurrent preload triggers download only once per language.
      final hiGate = Completer<bool>();
      final firstRun = provider.ensureDefaultHandwritingPacksInBackground(
        downloadedChecker: (_) async => false,
        connectivityChecker: () async => true,
        downloader: (langId) {
          downloadCalls.add(langId);
          return langId == 'hi' ? hiGate.future : Future.value(true);
        },
      );
      final overlappingRun = provider.ensureDefaultHandwritingPacksInBackground(
        downloadedChecker: (_) async => false,
        connectivityChecker: () async => true,
        downloader: (langId) async {
          downloadCalls.add('dup_$langId');
          return true;
        },
      );

      await Future<void>.delayed(Duration.zero);
      hiGate.complete(true);
      await Future.wait([firstRun, overlappingRun]);

      expect(downloadCalls, equals(['hi', 'en']));
      expect(provider.isHandwritingLanguageDownloaded('hi'), isTrue);
    });

    test('TextPen pauses conversion while pointer is drawing and debounces full multi-stroke Hindi/English words', () async {
      expect(
        provider.textPenDebounceDelay.inMilliseconds,
        greaterThanOrEqualTo(1500),
      );

      int ocrCallCount = 0;
      List<StrokeElement>? capturedBatch;
      provider.setPenType(PenType.textPen);
      provider.textPenDebounceDelay = const Duration(milliseconds: 120);
      provider.textPenSmartWritingService = SmartWritingService.forTest(
        digitalInkOcr: (strokes, _, _) async {
          ocrCallCount++;
          capturedBatch = List<StrokeElement>.from(strokes);
          return 'विश्वविद्यालय';
        },
      );

      // Stroke 1 drawn & lifted
      provider.onTextPenPointerDown(1);
      final s1 = StrokeElement(
        id: 'tp_1',
        position: const Offset(100, 100),
        points: const [Offset(100, 100), Offset(130, 135)],
        color: Colors.black,
        strokeWidth: 3.0,
        penType: PenType.textPen,
      );
      provider.addElement(s1);
      provider.onTextPenPointerUp(1);

      // Pause 60ms (< 120ms), then user starts drawing a long continuous stroke for 200ms
      await Future<void>.delayed(const Duration(milliseconds: 60));
      provider.onTextPenPointerDown(2);
      await Future<void>.delayed(const Duration(milliseconds: 220));

      // Even though 220ms > 120ms, pointer #2 is STILL down drawing -> must NOT convert mid-word!
      expect(ocrCallCount, equals(0));
      expect(provider.currentPage.elements.length, equals(1));

      // Finish stroke 2 + stroke 3 (shirorekha)
      final s2 = StrokeElement(
        id: 'tp_2',
        position: const Offset(140, 100),
        points: const [Offset(140, 100), Offset(220, 135)],
        color: Colors.black,
        strokeWidth: 3.0,
        penType: PenType.textPen,
      );
      provider.addElement(s2);
      provider.onTextPenPointerUp(2);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      provider.onTextPenPointerDown(3);
      final s3 = StrokeElement(
        id: 'tp_3',
        position: const Offset(95, 92),
        points: const [Offset(95, 92), Offset(225, 92)],
        color: Colors.black,
        strokeWidth: 3.0,
        penType: PenType.textPen,
      );
      provider.addElement(s3);
      provider.onTextPenPointerUp(3);

      // Immediately after lift, conversion still waits for idle debounce
      expect(ocrCallCount, equals(0));

      // Wait past idle debounce -> all 3 strokes convert together atomically
      await Future<void>.delayed(const Duration(milliseconds: 180));

      expect(ocrCallCount, equals(1));
      expect(capturedBatch?.length, equals(3));
      expect(provider.currentPage.elements.length, equals(1));
      expect(provider.currentPage.elements.first, isA<TextElement>());
      expect(
        (provider.currentPage.elements.first as TextElement).text,
        equals('विश्वविद्यालय'),
      );

      // Single undo restores all 3 original handwritten strokes
      provider.undo();
      expect(provider.currentPage.elements.length, equals(3));
    });

    testWidgets('WhiteboardCanvas keeps TextPen single-tap dots and pauses conversion during active drag', (tester) async {
      int ocrCalls = 0;
      provider.setPenType(PenType.textPen);
      provider.textPenDebounceDelay = const Duration(milliseconds: 100);
      provider.textPenSmartWritingService = SmartWritingService.forTest(
        digitalInkOcr: (_, _, _) async {
          ocrCalls++;
          return 'हिंदी';
        },
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<WhiteboardProvider>.value(
          value: provider,
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600,
                height: 400,
                child: WhiteboardCanvas(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // 1. Tap a single anusvara/i-dot (no drag -> points.length == 1)
      final dot = await tester.startGesture(const Offset(180, 90));
      await tester.pump(const Duration(milliseconds: 25));
      await dot.up();
      await tester.pump(const Duration(milliseconds: 20));
      expect(provider.pendingTextPenStrokeCount, equals(1));

      // 2. Immediately hold down a long continuous stroke for 180ms (> 100ms debounce)
      final stem = await tester.startGesture(const Offset(150, 120));
      await tester.pump(const Duration(milliseconds: 180));
      await stem.moveTo(const Offset(240, 120));
      await tester.pump(const Duration(milliseconds: 20));
      // Still holding pen -> must NOT convert yet
      expect(ocrCalls, equals(0));

      await stem.up();
      await tester.pump(const Duration(milliseconds: 160));
      await tester.pumpAndSettle();

      expect(ocrCalls, equals(1));
      expect(provider.currentPage.elements.length, equals(1));
      expect(
        (provider.currentPage.elements.first as TextElement).text,
        equals('हिंदी'),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    test('buildDigitalInk decimates sub-2.5px dense points while preserving endpoints', () {
      final service = SmartWritingService.forTest();
      final storage = BoardStorageService();
      // Simulate 50 high-frequency 0.5px points along a 25px stroke
      final densePoints = List.generate(
        51,
        (i) => Offset(100.0 + i * 0.5, 100.0),
      );
      final stroke = StrokeElement(
        id: 'dense_1',
        position: const Offset(100, 100),
        points: densePoints,
        color: Colors.black,
        strokeWidth: 3.0,
      );
      final bounds = storage.getCombinedVisualBounds([stroke])!;
      final ink = service.buildDigitalInk([stroke], bounds);

      expect(ink.strokes.length, equals(1));
      expect(ink.strokes.first.points.length, lessThan(20));
      expect(ink.strokes.first.points.length, greaterThanOrEqualTo(5));
    });

    test('recovers cleanly if a TextPen pointer UP event is dropped', () async {
      int ocrCalls = 0;
      provider.setPenType(PenType.textPen);
      provider.textPenDebounceDelay = const Duration(milliseconds: 80);
      provider.textPenSmartWritingService = SmartWritingService.forTest(
        digitalInkOcr: (_, _, _) async {
          ocrCalls++;
          return 'Recovered';
        },
      );

      // Simulate pointer #9 down, stroke added, then pointer #9's UP dropped
      provider.onTextPenPointerDown(9);
      final s = StrokeElement(
        id: 'dropped_up_1',
        position: const Offset(100, 100),
        points: const [Offset(100, 100), Offset(180, 120)],
        color: Colors.black,
        strokeWidth: 3.0,
        penType: PenType.textPen,
      );
      provider.addElement(s);

      // Later sync shows pointer #9 is no longer live -> resumes debounce cleanly
      provider.syncActiveTextPenPointers(const {});
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(ocrCalls, equals(1));
      expect(provider.currentPage.elements.length, equals(1));
      expect(
        (provider.currentPage.elements.first as TextElement).text,
        equals('Recovered'),
      );
    });
  });
}

