import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart'
    as digital_ink;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart' hide TextElement;
import 'package:uuid/uuid.dart';
import '../models/stroke_element.dart';
import '../models/text_element.dart';
import '../state/whiteboard_provider.dart';
import 'ai_service.dart';
import 'board_storage_service.dart';

typedef DigitalInkOcrRunner =
    Future<String?> Function(
      List<StrokeElement> strokes,
      Rect visualBounds,
      String bcpCode,
    );
typedef OnDeviceOcrRunner =
    Future<String?> Function(Uint8List ocrBytes, String language);
typedef CloudOcrRunner =
    Future<String> Function(Uint8List ocrBytes, String language);

class SmartWritingService {
  static final SmartWritingService _instance = SmartWritingService._internal();
  factory SmartWritingService() => _instance;

  SmartWritingService._internal()
    : _storage = BoardStorageService(),
      _digitalInkOcrOverride = null,
      _onDeviceOcrOverride = null,
      _cloudOcrOverride = null;

  /// Creates an isolated instance with custom OCR runners for testing.
  @visibleForTesting
  SmartWritingService.forTest({
    BoardStorageService? storage,
    DigitalInkOcrRunner? digitalInkOcr,
    OnDeviceOcrRunner? onDeviceOcr,
    CloudOcrRunner? cloudOcr,
  }) : _storage = storage ?? BoardStorageService(),
       _digitalInkOcrOverride = digitalInkOcr,
       _onDeviceOcrOverride = onDeviceOcr,
       _cloudOcrOverride = cloudOcr;

  final BoardStorageService _storage;
  final DigitalInkOcrRunner? _digitalInkOcrOverride;
  final OnDeviceOcrRunner? _onDeviceOcrOverride;
  final CloudOcrRunner? _cloudOcrOverride;

  /// Human-readable reason for the most recent SmartWrite failure, or null on success.
  String? lastErrorMessage;
  DateTime? _digitalInkCooldownUntil;
  final Map<String, Future<bool>> _inFlightDownloads = {};

  /// Clears any temporary Digital Ink skip cooldown (e.g. after a model finishes downloading).
  void clearDigitalInkCooldown() {
    _digitalInkCooldownUntil = null;
  }

  // Genuine empty/placeholder OCR responses (exact match only so real words
  // such as "Na", "None", "Null", or "Error" are preserved).
  static const Set<String> _blacklistedPhrases = {
    'n/a',
    'no text',
    'no text visible',
    'no text found',
    'no text detected',
    'no text generated',
    'no handwriting ocr generated',
    'no handwriting ocr',
    'no ocr generated',
    'not applicable',
    '[blank]',
    '[empty]',
    'blank image',
    'empty image',
  };

  // ML Kit Digital Ink uses "zh-Hani" for Chinese Han script.
  static const Map<String, String> _digitalInkTagOverrides = {
    'follow_system': 'en',
    'zh': 'zh-Hani',
    'chinese': 'zh-Hani',
  };

  /// Maps a configured handwriting language name, id, native name, or BCP code
  /// to the ML Kit Digital Ink BCP-47 model tag.
  static String resolveHandwritingBcpCode(String language) {
    final trimmed = language.trim();
    if (trimmed.isEmpty) return 'en';

    final lower = trimmed.toLowerCase();
    final directOverride = _digitalInkTagOverrides[lower];
    if (directOverride != null) return directOverride;

    for (final item in WhiteboardProvider.kHandwritingLanguages) {
      if (item.id.toLowerCase() == lower ||
          item.name.toLowerCase() == lower ||
          item.nativeName.toLowerCase() == lower ||
          item.displayName.toLowerCase() == lower ||
          item.bcpCode.toLowerCase() == lower) {
        return _digitalInkTagOverrides[item.bcpCode.toLowerCase()] ??
            item.bcpCode;
      }
    }

    if (lower.contains('follow system') || lower.contains('english')) {
      return 'en';
    }
    return 'en';
  }

  /// Returns the bundled on-device ML Kit [TextRecognitionScript] for [bcpCode],
  /// or null when image OCR must rely on Digital Ink / Cloud AI instead.
  static TextRecognitionScript? textRecognitionScriptForBcp(String bcpCode) {
    switch (bcpCode) {
      case 'en':
      case 'es':
      case 'fr':
      case 'de':
        return TextRecognitionScript.latin;
      case 'hi':
      case 'mr':
        return TextRecognitionScript.devanagiri;
      default:
        return null;
    }
  }

  /// Returns true when [language] uses a Latin script supported by the
  /// bundled on-device ML Kit Latin text recognizer.
  static bool isLatinHandwritingLanguage(String language) {
    return textRecognitionScriptForBcp(resolveHandwritingBcpCode(language)) ==
        TextRecognitionScript.latin;
  }

  /// Checks whether the offline ML Kit Digital Ink model for [language] is downloaded.
  Future<bool> isHandwritingModelDownloaded(String language) async {
    try {
      final tag = resolveHandwritingBcpCode(language);
      return await digital_ink.DigitalInkRecognizerModelManager()
          .isModelDownloaded(tag)
          .timeout(const Duration(seconds: 2));
    } on MissingPluginException {
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Downloads the offline ML Kit Digital Ink model for [language] (works on Wi-Fi or mobile data),
  /// deduplicating concurrent requests for the same language tag.
  Future<bool> downloadHandwritingLanguageModel(
    String language, {
    Duration timeout = const Duration(seconds: 60),
  }) {
    final tag = resolveHandwritingBcpCode(language);
    final existing = _inFlightDownloads[tag];
    if (existing != null) return existing;

    final future = _downloadHandwritingModelImpl(tag, timeout);
    _inFlightDownloads[tag] = future;
    future.whenComplete(() => _inFlightDownloads.remove(tag));
    return future;
  }

  Future<bool> _downloadHandwritingModelImpl(
    String tag,
    Duration timeout,
  ) async {
    try {
      final manager = digital_ink.DigitalInkRecognizerModelManager();
      final already = await manager
          .isModelDownloaded(tag)
          .timeout(const Duration(seconds: 3));
      if (already) return true;

      final ok = await manager
          .downloadModel(tag, isWifiRequired: false)
          .timeout(timeout);
      if (ok) {
        clearDigitalInkCooldown();
      }
      return ok;
    } on MissingPluginException {
      return false;
    } on TimeoutException {
      return false;
    } catch (e) {
      debugPrint('Digital Ink model download note ($tag): $e');
      return false;
    }
  }

  double _minHorizontalGap(Rect target, List<Rect> lineRects) {
    double best = double.infinity;
    for (final r in lineRects) {
      final double dx;
      if (target.right < r.left) {
        dx = r.left - target.right;
      } else if (r.right < target.left) {
        dx = target.left - r.right;
      } else {
        dx = 0.0;
      }
      if (dx < best) best = dx;
    }
    return best.isFinite ? best : 0.0;
  }

  /// Orders [strokes] into top-to-bottom reading lines and left-to-right within
  /// each line so delayed diacritics (e.g. Hindi shirorekha, 'i' dots, 't' bars)
  /// stay grouped with their characters during handwriting segmentation.
  @visibleForTesting
  List<StrokeElement> sortStrokesSpatiallyForOcr(List<StrokeElement> strokes) {
    final nonEmpty = strokes.where((s) => s.points.isNotEmpty).toList();
    if (nonEmpty.length <= 1) return nonEmpty;

    final entries = <({StrokeElement stroke, Rect bounds, int index})>[];
    final heights = <double>[];
    for (int i = 0; i < nonEmpty.length; i++) {
      final b = _storage.getElementVisualBounds(nonEmpty[i]);
      entries.add((stroke: nonEmpty[i], bounds: b, index: i));
      if (b.height >= 8.0) heights.add(b.height);
    }
    heights.sort();
    final double medianHeight = heights.isEmpty
        ? entries
              .map((e) => e.bounds.height)
              .fold<double>(0.0, max)
              .clamp(16.0, 200.0)
        : heights[heights.length ~/ 2];
    final double lineTolerance = max(14.0, medianHeight * 0.65);

    final double coreMinHeight = medianHeight * 0.45;
    final coreEntries = entries
        .where((e) => e.bounds.height >= coreMinHeight)
        .toList();
    final smallEntries = entries
        .where((e) => e.bounds.height < coreMinHeight)
        .toList();
    final primary = coreEntries.isNotEmpty ? coreEntries : entries;
    final accents = coreEntries.isNotEmpty
        ? smallEntries
        : <({StrokeElement stroke, Rect bounds, int index})>[];

    primary.sort((a, b) => a.bounds.center.dy.compareTo(b.bounds.center.dy));

    final lines = <List<({StrokeElement stroke, Rect bounds, int index})>>[];
    final lineTops = <double>[];
    final lineBottoms = <double>[];
    final lineCenterYs = <double>[];

    for (final entry in primary) {
      int bestLine = -1;
      double bestDist = double.infinity;
      for (int i = 0; i < lines.length; i++) {
        final expandedTop = lineTops[i] - lineTolerance * 0.4;
        final expandedBottom = lineBottoms[i] + lineTolerance * 0.4;
        final withinBand =
            entry.bounds.center.dy >= expandedTop &&
            entry.bounds.center.dy <= expandedBottom;
        final dyDist = (entry.bounds.center.dy - lineCenterYs[i]).abs();
        if ((withinBand || dyDist <= lineTolerance) && dyDist < bestDist) {
          bestDist = dyDist;
          bestLine = i;
        }
      }
      if (bestLine == -1) {
        lines.add([entry]);
        lineTops.add(entry.bounds.top);
        lineBottoms.add(entry.bounds.bottom);
        lineCenterYs.add(entry.bounds.center.dy);
      } else {
        lines[bestLine].add(entry);
        lineTops[bestLine] = min(lineTops[bestLine], entry.bounds.top);
        lineBottoms[bestLine] = max(lineBottoms[bestLine], entry.bounds.bottom);
        final count = lines[bestLine].length;
        lineCenterYs[bestLine] =
            ((lineCenterYs[bestLine] * (count - 1)) + entry.bounds.center.dy) /
            count;
      }
    }

    final lineRectLists = lines
        .map((line) => line.map((e) => e.bounds).toList())
        .toList();
    for (final accent in accents) {
      int bestLine = 0;
      double bestScore = double.infinity;
      for (int i = 0; i < lines.length; i++) {
        final vDist = accent.bounds.center.dy < lineTops[i]
            ? (lineTops[i] - accent.bounds.center.dy)
            : (accent.bounds.center.dy > lineBottoms[i]
                  ? (accent.bounds.center.dy - lineBottoms[i])
                  : 0.0);
        final hGap = _minHorizontalGap(accent.bounds, lineRectLists[i]);
        final dyToCenter = (accent.bounds.center.dy - lineCenterYs[i]).abs();
        final score = vDist * 3.0 + dyToCenter + hGap * 0.4;
        if (score < bestScore) {
          bestScore = score;
          bestLine = i;
        }
      }
      lines[bestLine].add(accent);
    }

    final indexedLines = List.generate(
      lines.length,
      (i) => (centerY: lineCenterYs[i], items: lines[i]),
    )..sort((a, b) => a.centerY.compareTo(b.centerY));

    final ordered = <StrokeElement>[];
    for (final line in indexedLines) {
      line.items.sort((a, b) {
        final cmpX = a.bounds.left.compareTo(b.bounds.left);
        if (cmpX != 0) return cmpX;
        final cmpY = a.bounds.top.compareTo(b.bounds.top);
        if (cmpY != 0) return cmpY;
        return a.index.compareTo(b.index);
      });
      for (final item in line.items) {
        ordered.add(item.stroke);
      }
    }
    return ordered;
  }

  /// Builds a normalized ML Kit Digital Ink payload preserving rotation, scale,
  /// reading order, and monotonic timestamps for handwriting segmentation.
  digital_ink.Ink buildDigitalInk(
    List<StrokeElement> strokes,
    Rect visualBounds,
  ) {
    final orderedStrokes = sortStrokesSpatiallyForOcr(strokes);
    final ink = digital_ink.Ink();
    int timestampMs = 0;

    for (final stroke in orderedStrokes) {
      if (stroke.points.isEmpty) continue;
      final inkStroke = digital_ink.Stroke();
      Offset? lastAdded;
      final int count = stroke.points.length;
      for (int i = 0; i < count; i++) {
        final transformed = _storage.transformElementPoint(
          stroke,
          stroke.points[i],
        );
        final bool isEndpoint = i == 0 || i == count - 1;
        if (!isEndpoint &&
            lastAdded != null &&
            (transformed - lastAdded).distanceSquared < 6.25) {
          // Skip sub-2.5px high-frequency samples so long words recognize fast.
          continue;
        }
        inkStroke.points.add(
          digital_ink.StrokePoint(
            x: max(0.0, transformed.dx - visualBounds.left),
            y: max(0.0, transformed.dy - visualBounds.top),
            t: timestampMs,
          ),
        );
        lastAdded = transformed;
        timestampMs += 15;
      }
      if (inkStroke.points.isNotEmpty) {
        ink.strokes.add(inkStroke);
        timestampMs += 120;
      }
    }

    return ink;
  }

  /// Sanitizes raw OCR output and returns null if the text is invalid,
  /// placeholder noise, or contains no readable letters/digits in any script.
  String? cleanAndValidateRecognizedText(String rawText) {
    if (rawText.isEmpty) return null;

    String clean = rawText
        .trim()
        .replaceAll(RegExp(r'^```[a-zA-Z0-9_-]*\s*'), '')
        .replaceAll(RegExp(r'\s*```$'), '')
        .trim();

    if (clean.length >= 2 &&
        ((clean.startsWith('"') && clean.endsWith('"')) ||
            (clean.startsWith("'") && clean.endsWith("'")))) {
      clean = clean.substring(1, clean.length - 1).trim();
    }

    if (clean.isEmpty) return null;
    if (AiService.isErrorResponse(clean)) return null;

    final lower = clean.toLowerCase();
    if (_blacklistedPhrases.contains(lower)) return null;
    if (lower.startsWith('no ') && lower.contains('generated')) return null;
    if (lower.contains('handwriting ocr')) return null;

    // Require at least one Unicode letter or digit across all supported scripts
    // (Latin, Indic, Kannada, Punjabi, Cyrillic, Arabic, CJK) so standalone
    // stroke noise like "|", "---", or "." still triggers Cloud fallback.
    final RegExp letterOrDigitPattern = RegExp(r'[\p{L}\p{N}]', unicode: true);
    if (!letterOrDigitPattern.hasMatch(clean)) return null;

    return clean;
  }

  String _friendlyApiError(String errorText) {
    if (errorText.startsWith('⚠️')) {
      return 'Gemini API key is missing or not configured.';
    }
    if (errorText.contains('(429)')) {
      return 'AI handwriting service is busy right now. Please try again.';
    }
    if (errorText.contains('(401)') || errorText.contains('(403)')) {
      return 'AI server rejected the API key. Enable internet to download offline handwriting or update GEMINI_API_KEY.';
    }
    if (errorText.contains('SocketException') ||
        errorText.contains('TimeoutException') ||
        errorText.contains('Failed host lookup')) {
      return 'No internet connection or request timed out for SmartWrite.';
    }
    return 'Could not recognize handwriting right now. Please try again.';
  }

  String _normalizeMultilineOcrText(String raw) {
    return raw
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
  }

  Future<String?> _runDigitalInkOcr(
    List<StrokeElement> strokes,
    Rect visualBounds,
    String bcpCode,
  ) async {
    if (_digitalInkOcrOverride != null) {
      final raw = await _digitalInkOcrOverride(strokes, visualBounds, bcpCode);
      return raw == null ? null : cleanAndValidateRecognizedText(raw);
    }

    if (_digitalInkCooldownUntil != null &&
        DateTime.now().isBefore(_digitalInkCooldownUntil!)) {
      return null;
    }

    digital_ink.DigitalInkRecognizer? recognizer;
    try {
      final manager = digital_ink.DigitalInkRecognizerModelManager();
      final ready = await manager
          .isModelDownloaded(bcpCode)
          .timeout(const Duration(seconds: 2));
      if (!ready) {
        return null;
      }

      final ink = buildDigitalInk(strokes, visualBounds);
      if (ink.strokes.isEmpty) return null;

      final context = digital_ink.DigitalInkRecognitionContext(
        writingArea: digital_ink.WritingArea(
          width: max(1.0, visualBounds.width),
          height: max(1.0, visualBounds.height),
        ),
      );

      recognizer = digital_ink.DigitalInkRecognizer(languageCode: bcpCode);
      final candidates = await recognizer
          .recognize(ink, context: context)
          .timeout(const Duration(seconds: 4));
      for (final candidate in candidates) {
        final validated = cleanAndValidateRecognizedText(candidate.text);
        if (validated != null) return validated;
      }
      return null;
    } on MissingPluginException {
      return null;
    } on TimeoutException {
      _digitalInkCooldownUntil = DateTime.now().add(
        const Duration(seconds: 60),
      );
      debugPrint('On-device Digital Ink timed out ($bcpCode); skipping.');
      return null;
    } catch (e) {
      debugPrint('On-device Digital Ink note ($bcpCode): $e');
      return null;
    } finally {
      try {
        await recognizer?.close().timeout(const Duration(seconds: 1));
      } catch (_) {}
    }
  }

  double? _extractAverageConfidence(RecognizedText result) {
    double sum = 0.0;
    int count = 0;
    for (final block in result.blocks) {
      for (final line in block.lines) {
        final conf = line.confidence;
        if (conf != null && conf >= 0.0) {
          sum += conf;
          count++;
        }
      }
    }
    return count > 0 ? sum / count : null;
  }

  Future<({String? text, bool timedOut, double? avgConfidence})>
  _runOnDeviceMlKitOcr(
    Uint8List ocrBytes,
    String language, {
    required TextRecognitionScript script,
  }) async {
    if (_onDeviceOcrOverride != null) {
      final text = await _onDeviceOcrOverride(ocrBytes, language);
      return (text: text, timedOut: false, avgConfidence: null);
    }

    String? tempPath;
    TextRecognizer? textRecognizer;
    try {
      tempPath = await _storage.writeTempOcrImage(
        ocrBytes,
        prefix: 'ocr_bold',
      );
      if (tempPath == null) {
        return (text: null, timedOut: false, avgConfidence: null);
      }

      final inputImage = InputImage.fromFilePath(tempPath);
      textRecognizer = TextRecognizer(script: script);
      final result = await textRecognizer
          .processImage(inputImage)
          .timeout(const Duration(seconds: 5));
      return (
        text: _normalizeMultilineOcrText(result.text),
        timedOut: false,
        avgConfidence: _extractAverageConfidence(result),
      );
    } on MissingPluginException {
      return (text: null, timedOut: false, avgConfidence: null);
    } on TimeoutException {
      debugPrint('On-device ML Kit image OCR timed out ($language).');
      return (text: null, timedOut: true, avgConfidence: null);
    } finally {
      try {
        await textRecognizer?.close().timeout(const Duration(seconds: 1));
      } catch (_) {}
      if (tempPath != null) {
        try {
          final file = File(tempPath);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
  }

  Future<({String? text, bool timedOut, double? avgConfidence})>
  _tryValidatedMlKitOcr(
    Uint8List ocrBytes,
    String language, {
    required TextRecognitionScript script,
  }) async {
    try {
      final res = await _runOnDeviceMlKitOcr(
        ocrBytes,
        language,
        script: script,
      );
      final raw = res.text;
      if (raw == null || raw.isEmpty) {
        return (
          text: null,
          timedOut: res.timedOut,
          avgConfidence: res.avgConfidence,
        );
      }
      return (
        text: cleanAndValidateRecognizedText(raw),
        timedOut: res.timedOut,
        avgConfidence: res.avgConfidence,
      );
    } catch (e) {
      debugPrint('On-device ML Kit image OCR note ($language): $e');
      return (text: null, timedOut: false, avgConfidence: null);
    }
  }

  bool _isSuspiciousSingleCharResult(
    String text,
    List<StrokeElement> strokes,
    Rect visualBounds,
  ) {
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    if (compact.runes.length > 1) return false;
    return strokes.length >= 4 ||
        visualBounds.width > max(160.0, visualBounds.height * 2.4);
  }

  static final RegExp _devanagariRegex = RegExp(r'[\u0900-\u097F]');
  static final RegExp _numericOrPunctRegex = RegExp(r'^[\d\s.,:/+\-=%()]+$');

  /// Detects a Hindi/Devanagari top header bar (shirorekha) spanning multiple
  /// character strokes in the upper band of a handwritten word or line.
  @visibleForTesting
  bool hasLikelyDevanagariShirorekha(
    List<StrokeElement> strokes,
    Rect visualBounds,
  ) {
    if (strokes.length < 3 ||
        visualBounds.width < 40.0 ||
        visualBounds.height < 20.0) {
      return false;
    }

    final boundsList = strokes
        .map((s) => _storage.getElementVisualBounds(s))
        .toList();
    final heights =
        boundsList.map((b) => b.height).where((h) => h >= 12.0).toList()
          ..sort();
    final double approxCharHeight = heights.isEmpty
        ? visualBounds.height
        : heights[heights.length ~/ 2];

    for (int i = 0; i < boundsList.length; i++) {
      final bar = boundsList[i];
      final bool isFlatHorizontal =
          bar.width >= max(28.0, approxCharHeight * 0.6) &&
          bar.width >= bar.height * 2.5;
      if (!isFlatHorizontal) continue;

      int coveredStrokesBelow = 0;
      for (int j = 0; j < boundsList.length; j++) {
        if (i == j) continue;
        final child = boundsList[j];
        final bool horizontallyUnderBar =
            child.center.dx >= bar.left - 8.0 &&
            child.center.dx <= bar.right + 8.0;
        final double dyBelow = child.center.dy - bar.center.dy;
        final bool directlyBelow =
            dyBelow > 2.0 && dyBelow <= approxCharHeight * 1.8;
        if (horizontallyUnderBar && directlyBelow) {
          coveredStrokesBelow++;
        }
      }

      if (coveredStrokesBelow >= 2) {
        return true;
      }
    }
    return false;
  }

  /// Returns true when a Latin OCR guess shows strong signs of misread
  /// non-Latin strokes (e.g. Hindi "किताब" turned into "ffda", "fTald", "chld").
  @visibleForTesting
  static bool isLikelyLatinGibberish(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return true;

    final tokens = trimmed
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return true;

    int suspiciousTokens = 0;
    final letterOnly = RegExp(r'^[A-Za-z]+$');
    final vowel = RegExp(r'[aeiouyAEIOUY]');

    for (final rawToken in tokens) {
      final token = rawToken.replaceAll(
        RegExp(r'^[,."?!:;()]+|[,."?!:;()]+$'),
        '',
      );
      if (token.isEmpty) continue;

      // Mixed case anomalies typical of non-Latin OCR hallucinations ("fTald",
      // "dIda", "CHld", "kiTaB"), while allowing clean PascalCase like "SmartWrite".
      if (RegExp(r'^[a-z]{1,2}[A-Z]').hasMatch(token) ||
          RegExp(r'[A-Za-z][A-Z][a-z][A-Z]').hasMatch(token) ||
          RegExp(r'[a-z][A-Z]$').hasMatch(token) ||
          (token.length >= 4 && RegExp(r'^[A-Z]{2,}[a-z]').hasMatch(token))) {
        suspiciousTokens++;
        continue;
      }

      // Symbols or digits wedged inside alphabetic fragments ("k1tab", "f|da").
      if (RegExp(r'[A-Za-z][|/\\_\[\]{}~^*=]+[A-Za-z]').hasMatch(token) ||
          (RegExp(r'[A-Za-z]').hasMatch(token) &&
              RegExp(r'\d').hasMatch(token) &&
              token.length >= 3 &&
              !RegExp(
                r'^[A-Za-z]{1,2}\d+$|^\d+(st|nd|rd|th|px|cm|mm|kg|km)$',
                caseSensitive: false,
              ).hasMatch(token))) {
        suspiciousTokens++;
        continue;
      }

      if (letterOnly.hasMatch(token)) {
        if (token.length >= 3 && !vowel.hasMatch(token)) {
          suspiciousTokens++;
          continue;
        }
        if (token.length >= 4 &&
            RegExp(
              r'^(ff|tt|hh|jj|kk|pp|dd|gg|bb|mm|nn|rr|ss|vv|ww|zz)[a-z]',
              caseSensitive: false,
            ).hasMatch(token)) {
          suspiciousTokens++;
          continue;
        }
      }
    }

    return suspiciousTokens > 0 && suspiciousTokens * 2 >= tokens.length;
  }

  Future<String> _runCloudOcr(Uint8List ocrBytes, String language) {
    if (_cloudOcrOverride != null) {
      return _cloudOcrOverride(ocrBytes, language);
    }
    return AiService().recognizeHandwriting(
      imageBytes: ocrBytes,
      language: language,
    );
  }

  /// 3-tier hybrid handwriting recognition:
  /// 1. Instant on-device ML Kit Digital Ink when its model is already downloaded.
  /// 2. Bundled on-device ML Kit TextRecognizer for Latin & Devanagari scripts.
  /// 3. Cloud Gemini Vision OCR fallback on high-contrast black-on-white strokes.
  Future<String?> _recognizeStrokesText(
    List<StrokeElement> strokes,
    Rect visualBounds,
    WhiteboardProvider provider,
  ) async {
    lastErrorMessage = null;

    if (visualBounds.width < 10.0 && visualBounds.height < 10.0) {
      lastErrorMessage = 'Selected strokes are too small to recognize.';
      return null;
    }

    final language = provider.selectedHandwritingLanguage;
    final bcpCode = resolveHandwritingBcpCode(language);
    final bool isAutoBilingual =
        bcpCode == 'en' &&
        (language.toLowerCase().contains('follow system') ||
            language.trim().isEmpty);
    final bool expectsDevanagari = bcpCode == 'hi' || bcpCode == 'mr';
    final bool hasShirorekha = hasLikelyDevanagariShirorekha(
      strokes,
      visualBounds,
    );
    String? bestFallbackCandidate;

    bool shouldAcceptLatin(String candidate, {double? confidence}) {
      if (_isSuspiciousSingleCharResult(candidate, strokes, visualBounds)) {
        return false;
      }
      if (isLikelyLatinGibberish(candidate)) return false;
      if (isAutoBilingual && hasShirorekha) return false;
      if (confidence != null && confidence < 0.40) {
        return false;
      }
      return true;
    }

    bool shouldAcceptDevanagari(String candidate, {double? confidence}) {
      if (_isSuspiciousSingleCharResult(candidate, strokes, visualBounds)) {
        return false;
      }
      final hasDev = _devanagariRegex.hasMatch(candidate);
      final isNum = _numericOrPunctRegex.hasMatch(candidate);
      if (!hasDev && !isNum) return false;
      if (confidence != null && confidence < 0.30) return false;
      return true;
    }

    // 1. Primary: Digital Ink (instant when downloaded; strictly bounded timeout).
    final primaryInkBcp = (isAutoBilingual && hasShirorekha) ? 'hi' : bcpCode;
    final digitalInkText = await _runDigitalInkOcr(
      strokes,
      visualBounds,
      primaryInkBcp,
    );
    if (digitalInkText != null) {
      if (expectsDevanagari || primaryInkBcp == 'hi') {
        if (shouldAcceptDevanagari(digitalInkText)) return digitalInkText;
      } else if (shouldAcceptLatin(digitalInkText)) {
        return digitalInkText;
      }
      bestFallbackCandidate ??= digitalInkText;
    }

    // In bilingual auto mode, if primary English Digital Ink returned nothing or
    // gibberish, check Hindi Digital Ink if already downloaded on device.
    if (isAutoBilingual && primaryInkBcp != 'hi') {
      final hiInkText = await _runDigitalInkOcr(strokes, visualBounds, 'hi');
      if (hiInkText != null && shouldAcceptDevanagari(hiInkText)) {
        return hiInkText;
      }
    }

    // Capture high-contrast PNG once for image-based OCR tiers.
    final ocrBytes = await _storage.captureStrokesForOcrBytes(strokes);
    if (ocrBytes == null) {
      if (bestFallbackCandidate != null) return bestFallbackCandidate;
      lastErrorMessage = 'Selected strokes are too small to recognize.';
      return null;
    }

    // 2. Secondary: bundled on-device ML Kit image OCR (Latin & Devanagari).
    bool primaryMlKitTimedOut = false;
    final script = textRecognitionScriptForBcp(bcpCode);
    if (script != null) {
      final onDeviceRes = await _tryValidatedMlKitOcr(
        ocrBytes,
        language,
        script: script,
      );
      primaryMlKitTimedOut = onDeviceRes.timedOut;
      final onDeviceText = onDeviceRes.text;
      if (onDeviceText != null) {
        if (expectsDevanagari) {
          if (shouldAcceptDevanagari(
            onDeviceText,
            confidence: onDeviceRes.avgConfidence,
          )) {
            return onDeviceText;
          }
        } else {
          if (shouldAcceptLatin(
            onDeviceText,
            confidence: onDeviceRes.avgConfidence,
          )) {
            return onDeviceText;
          }
        }
        bestFallbackCandidate ??= onDeviceText;
      }
    }

    // 2b. If user kept default "Follow System (English)" and Latin missed or
    // looked suspicious (e.g. Hindi "किताब" read as fake English or with shirorekha),
    // verify with bundled offline Devanagari recognizer unless ML Kit timed out.
    if (!primaryMlKitTimedOut && isAutoBilingual) {
      final devRes = await _tryValidatedMlKitOcr(
        ocrBytes,
        'Hindi',
        script: TextRecognitionScript.devanagiri,
      );
      final devanagariText = devRes.text;
      if (devanagariText != null && _devanagariRegex.hasMatch(devanagariText)) {
        if (shouldAcceptDevanagari(
          devanagariText,
          confidence: devRes.avgConfidence,
        )) {
          return devanagariText;
        }
        // Prefer partial Devanagari over Latin gibberish if offline fallback needed.
        bestFallbackCandidate = devanagariText;
      }
    }

    // 3. Tertiary: Gemini Vision Cloud OCR fallback.
    try {
      final cloudRaw = await _runCloudOcr(ocrBytes, language);
      if (AiService.isErrorResponse(cloudRaw)) {
        if (bestFallbackCandidate != null) return bestFallbackCandidate;
        lastErrorMessage = _friendlyApiError(cloudRaw);
        return null;
      }

      final validated = cleanAndValidateRecognizedText(cloudRaw);
      if (validated != null) return validated;
      if (bestFallbackCandidate != null) return bestFallbackCandidate;

      lastErrorMessage =
          'Could not recognize readable text from the selected strokes.';
      return null;
    } catch (e) {
      debugPrint('Cloud handwriting OCR error: $e');
      if (bestFallbackCandidate != null) return bestFallbackCandidate;
      lastErrorMessage = 'SmartWrite failed to reach AI recognition service.';
      return null;
    }
  }

  /// Estimates an appropriate readable font size across single or multi-line strokes.
  @visibleForTesting
  static double computeOcrFontSize(Rect bounds, String text) {
    final lineCount = max(
      1,
      text.split('\n').where((l) => l.trim().isNotEmpty).length,
    );
    final double approxLineHeight = bounds.height / lineCount;
    return (approxLineHeight * 0.55).clamp(16.0, 42.0);
  }

  /// Converts selected handwritten strokes to a clean formatted [TextElement].
  Future<bool> convertSelectedStrokesToText(WhiteboardProvider provider) async {
    lastErrorMessage = null;
    final selectedIds = provider.selectedElementIds;
    if (selectedIds.isEmpty) {
      lastErrorMessage = 'Select handwritten strokes to convert to text.';
      return false;
    }

    final selectedStrokes = provider.currentPage.elements
        .where((e) => selectedIds.contains(e.id) && e is StrokeElement)
        .cast<StrokeElement>()
        .toList();

    if (selectedStrokes.isEmpty) {
      lastErrorMessage = 'Select handwritten strokes to convert to text.';
      return false;
    }

    return _convertStrokesCore(
      provider: provider,
      strokes: selectedStrokes,
      fontFamily: 'Poppins',
      fromSelection: true,
    );
  }

  /// Converts a specific list of handwritten strokes to a formatted [TextElement].
  Future<bool> convertStrokesToFormattedText(
    WhiteboardProvider provider,
    List<StrokeElement> strokes, {
    String fontFamily = 'Poppins',
  }) async {
    lastErrorMessage = null;
    if (strokes.isEmpty) {
      lastErrorMessage = 'No handwritten strokes to convert.';
      return false;
    }

    return _convertStrokesCore(
      provider: provider,
      strokes: strokes,
      fontFamily: fontFamily,
      fromSelection: false,
    );
  }

  Future<bool> _convertStrokesCore({
    required WhiteboardProvider provider,
    required List<StrokeElement> strokes,
    required String fontFamily,
    required bool fromSelection,
  }) async {
    final bounds = _storage.getCombinedVisualBounds(strokes);
    if (bounds == null) {
      lastErrorMessage = 'Selected strokes could not be measured.';
      return false;
    }
    final Color dominantColor = strokes[0].color;

    final cleanText = await _recognizeStrokesText(
      strokes,
      bounds,
      provider,
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        lastErrorMessage ??= 'SmartWrite timed out. Please try again.';
        return null;
      },
    );
    if (cleanText == null) return false;

    // Abort cleanly if the user deleted these strokes while OCR was running.
    final activeIds = provider.currentPage.elements.map((e) => e.id).toSet();
    final remainingStrokes = strokes
        .where((s) => activeIds.contains(s.id))
        .toList();
    if (remainingStrokes.isEmpty) {
      return false;
    }

    final double computedFontSize = computeOcrFontSize(bounds, cleanText);

    final textPainter = TextPainter(
      text: TextSpan(
        text: cleanText,
        style: TextStyle(
          fontSize: computedFontSize,
          fontWeight: FontWeight.w600,
          fontFamily: fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final textElement = TextElement(
      id: const Uuid().v4(),
      position: Offset(bounds.left, bounds.top),
      text: cleanText,
      color: dominantColor,
      fontSize: computedFontSize,
      size: textPainter.size,
      fontFamily: fontFamily,
      docPage: provider.isDocumentOverlayOpen
          ? provider.overlayCurrentPage
          : null,
    );

    provider.replaceStrokesWithText(
      remainingStrokes,
      textElement,
      selectResult: fromSelection,
    );

    return true;
  }
}
