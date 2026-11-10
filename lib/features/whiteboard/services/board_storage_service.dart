import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:file_picker/file_picker.dart';
import '../models/board_page.dart';
import '../models/board_element.dart';
import '../models/stroke_element.dart';
import '../models/shape_element.dart';
import '../models/text_element.dart';
import '../models/chemical_element_element.dart';
import '../widgets/canvas/chemical_element_drawer.dart';
import '../widgets/canvas/shape_drawer.dart';

class BoardStorageService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  FirebaseStorage get _storage {
    try {
      return FirebaseStorage.instanceFor(
        bucket: 'gs://pencilaiboardapp.firebasestorage.app',
      );
    } catch (_) {
      return FirebaseStorage.instance;
    }
  }

  Future<void> _ensureAuth() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
        debugPrint(
          'Signed in anonymously to Firebase for Board Storage access',
        );
      }
    } catch (e) {
      debugPrint('Firebase anonymous auth note: $e');
    }
  }

  Future<void> saveBoard(String sessionId, List<BoardPage> pages) async {
    final data = {
      'pages': pages.map((p) => p.toJson()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _firestore.collection('whiteboard_sessions').doc(sessionId).set(data);
  }

  Future<List<BoardPage>> loadBoard(String sessionId) async {
    final doc = await _firestore
        .collection('whiteboard_sessions')
        .doc(sessionId)
        .get();
    if (!doc.exists) return [];

    final data = doc.data() as Map<String, dynamic>;
    final pagesList = data['pages'] as List;
    return pagesList.map((p) => BoardPage.fromJson(p)).toList();
  }

  Future<String> exportToImage(GlobalKey boundaryKey) async {
    try {
      RenderRepaintBoundary boundary =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/whiteboard_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(path);
      await file.writeAsBytes(pngBytes);

      // Save to gallery using gal package
      await Gal.putImage(path);

      return path;
    } catch (e) {
      debugPrint('Error exporting image: $e');
      rethrow;
    }
  }

  Future<String?> captureCanvasToTempFile(GlobalKey boundaryKey) async {
    try {
      final context = boundaryKey.currentContext;
      if (context == null) return null;
      RenderRepaintBoundary boundary =
          context.findRenderObject() as RenderRepaintBoundary;
      // pixelRatio: 1.0 for lightning-fast image upload and OCR processing
      ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) return null;
      Uint8List pngBytes = byteData.buffer.asUint8List();

      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/canvas_ai_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(path);
      await file.writeAsBytes(pngBytes);
      return path;
    } catch (e) {
      debugPrint('Error capturing canvas for AI: $e');
      return null;
    }
  }

  /// Transforms [point] from [element]'s local coordinates into canvas coordinates
  /// using [element]'s rotation and scale around its raw bounding box center.
  Offset transformElementPoint(BoardElement element, Offset point) {
    if (element.rotation == 0.0 && element.scale == 1.0) {
      return point;
    }

    final center = element.getRawBounds().center;
    final cosA = cos(element.rotation);
    final sinA = sin(element.rotation);
    final d = point - center;
    return center +
        Offset(d.dx * cosA - d.dy * sinA, d.dx * sinA + d.dy * cosA) *
            element.scale;
  }

  /// Computes the axis-aligned visual bounding box of [element], accounting for
  /// rotation, scale, and stroke width around its raw center.
  Rect getElementVisualBounds(BoardElement element) {
    final rawBounds = element.getRawBounds();
    final double extraRadius = (element is StrokeElement)
        ? (element.strokeWidth * element.scale * 0.5)
        : (element is ShapeElement)
        ? (element.strokeWidth * element.scale * 0.5)
        : 0.0;

    if (element.rotation == 0.0 && element.scale == 1.0) {
      return extraRadius > 0 ? rawBounds.inflate(extraRadius) : rawBounds;
    }

    final corners = [
      transformElementPoint(element, rawBounds.topLeft),
      transformElementPoint(element, rawBounds.topRight),
      transformElementPoint(element, rawBounds.bottomRight),
      transformElementPoint(element, rawBounds.bottomLeft),
    ];

    double minX = corners[0].dx;
    double maxX = corners[0].dx;
    double minY = corners[0].dy;
    double maxY = corners[0].dy;
    for (int i = 1; i < corners.length; i++) {
      minX = min(minX, corners[i].dx);
      maxX = max(maxX, corners[i].dx);
      minY = min(minY, corners[i].dy);
      maxY = max(maxY, corners[i].dy);
    }

    final transformed = Rect.fromLTRB(minX, minY, maxX, maxY);
    return extraRadius > 0 ? transformed.inflate(extraRadius) : transformed;
  }

  /// Returns the combined visual bounding box across all [elements], or null if empty.
  Rect? getCombinedVisualBounds(List<BoardElement> elements) {
    if (elements.isEmpty) return null;
    Rect bounds = getElementVisualBounds(elements[0]);
    for (int i = 1; i < elements.length; i++) {
      bounds = bounds.expandToInclude(getElementVisualBounds(elements[i]));
    }
    return bounds;
  }

  void _withElementTransform(
    Canvas canvas,
    BoardElement element,
    void Function() draw,
  ) {
    final hasTransform = element.rotation != 0.0 || element.scale != 1.0;
    if (!hasTransform) {
      draw();
      return;
    }

    canvas.save();
    final center = element.getRawBounds().center;
    canvas.translate(center.dx, center.dy);
    canvas.rotate(element.rotation);
    canvas.scale(element.scale);
    canvas.translate(-center.dx, -center.dy);
    draw();
    canvas.restore();
  }

  Color _ocrContrastColor(Color color) {
    // Ensure white, pastel, or low-alpha ink from dark themes stays readable on white.
    if (color.a < 0.55 || color.computeLuminance() > 0.65) {
      return Colors.black;
    }
    return color.a < 1.0 ? color.withValues(alpha: 1.0) : color;
  }

  Future<Uint8List?> _renderCroppedWhiteboardPng({
    required Rect bounds,
    required double padding,
    required double desiredScale,
    required double maxDimension,
    required int minTargetDimension,
    required void Function(Canvas canvas) drawContent,
  }) async {
    if (bounds.width < 0 ||
        bounds.height < 0 ||
        (bounds.width == 0 && bounds.height == 0)) {
      return null;
    }

    final cropRect = bounds.inflate(padding);
    final double originalW = cropRect.width;
    final double originalH = cropRect.height;
    if (originalW <= 0 || originalH <= 0) return null;

    // Fit longest side within maxDimension while preserving aspect ratio cleanly.
    final double longestSide = max(originalW, originalH);
    final double scale = min(desiredScale, maxDimension / longestSide);
    final double drawW = originalW * scale;
    final double drawH = originalH * scale;

    final int targetW = max(minTargetDimension, drawW.ceil());
    final int targetH = max(minTargetDimension, drawH.ceil());

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.drawRect(
      Rect.fromLTWH(0, 0, targetW.toDouble(), targetH.toDouble()),
      Paint()..color = Colors.white,
    );

    canvas.translate((targetW - drawW) * 0.5, (targetH - drawH) * 0.5);
    canvas.scale(scale, scale);
    canvas.translate(-cropRect.left, -cropRect.top);

    drawContent(canvas);

    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture
          .toImage(targetW, targetH)
          .timeout(const Duration(seconds: 3));
      final byteData = await image
          .toByteData(format: ui.ImageByteFormat.png)
          .timeout(const Duration(seconds: 3));
      return byteData?.buffer.asUint8List();
    } finally {
      image?.dispose();
      picture.dispose();
    }
  }

  /// Writes PNG [bytes] into a temporary file for platform OCR SDKs and returns its path.
  Future<String?> writeTempOcrImage(
    Uint8List bytes, {
    String prefix = 'ocr_bold',
  }) async {
    try {
      final tempDir = await getTemporaryDirectory().timeout(
        const Duration(seconds: 4),
      );
      final filePath =
          '${tempDir.path}/${prefix}_${DateTime.now().microsecondsSinceEpoch}.png';
      final file = File(filePath);
      await file
          .writeAsBytes(bytes, flush: true)
          .timeout(const Duration(seconds: 4));
      return filePath;
    } catch (e) {
      debugPrint('Error writing temp OCR image: $e');
      return null;
    }
  }

  /// Captures ONLY the selected elements and returns high-contrast PNG bytes directly in memory.
  Future<Uint8List?> captureSelectedElementsBytes(
    List<BoardElement> selectedElements, {
    double maxDimension = 1200.0,
  }) async {
    try {
      final bounds = getCombinedVisualBounds(selectedElements);
      if (bounds == null) return null;

      return await _renderCroppedWhiteboardPng(
        bounds: bounds,
        padding: 24.0,
        desiredScale: 2.0,
        maxDimension: maxDimension,
        minTargetDimension: 48,
        drawContent: (canvas) {
          for (final element in selectedElements) {
            _drawElementOnCanvas(canvas, element);
          }
        },
      );
    } catch (e) {
      debugPrint('Error capturing selected elements bytes: $e');
      return null;
    }
  }

  /// Renders handwritten strokes in high-contrast black ink on a crisp white
  /// background without clipping wide sentences or blobbing small letters.
  Future<Uint8List?> captureStrokesForOcrBytes(
    List<StrokeElement> strokes,
  ) async {
    try {
      if (strokes.isEmpty) return null;

      final bounds = getCombinedVisualBounds(strokes);
      if (bounds == null) return null;

      // Filter out tiny dots, accidental taps, or erased stroke remnants (< 10px spread).
      if (bounds.width < 10.0 && bounds.height < 10.0) return null;

      // Compute adaptive stroke thickness from median glyph height so small
      // Devanagari/Latin loops stay open while large writing remains bold.
      final heights =
          strokes
              .map((s) => getElementVisualBounds(s).height)
              .where((h) => h >= 12.0)
              .toList()
            ..sort();
      final double medianStrokeHeight =
          (heights.isEmpty ? bounds.height : heights[heights.length ~/ 2])
              .clamp(12.0, 400.0);
      final double minVisualWidth = (medianStrokeHeight * 0.055).clamp(
        2.0,
        10.0,
      );
      final double maxVisualWidth = (medianStrokeHeight * 0.11).clamp(
        3.0,
        16.0,
      );
      final double targetVisualWidth = (medianStrokeHeight * 0.075).clamp(
        minVisualWidth,
        maxVisualWidth,
      );
      final double adaptiveScale = (72.0 / medianStrokeHeight).clamp(1.5, 3.5);
      final double adaptivePadding = max(
        36.0,
        medianStrokeHeight * 0.45,
      ).clamp(36.0, 72.0);

      final fillPaint = Paint()..color = Colors.black;
      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.black;

      return await _renderCroppedWhiteboardPng(
        bounds: bounds,
        padding: adaptivePadding,
        desiredScale: adaptiveScale,
        maxDimension: 1280.0,
        minTargetDimension: 128,
        drawContent: (canvas) {
          for (final stroke in strokes) {
            final double effectiveScale = stroke.scale > 0 ? stroke.scale : 1.0;
            final double visualWidth = (stroke.strokeWidth * effectiveScale)
                .clamp(targetVisualWidth, maxVisualWidth);
            final double localWidth = visualWidth / effectiveScale;

            _withElementTransform(canvas, stroke, () {
              if (stroke.points.length == 1) {
                canvas.drawCircle(
                  stroke.points[0],
                  max(localWidth * 0.65, 1.5),
                  fillPaint,
                );
              } else if (stroke.points.length > 1) {
                strokePaint.strokeWidth = localWidth;
                canvas.drawPath(stroke.path, strokePaint);
              }
            });
          }
        },
      );
    } catch (e) {
      debugPrint('Error capturing strokes for OCR bytes: $e');
      return null;
    }
  }

  /// Renders handwritten strokes in bold black ink on a crisp white background
  /// and saves to a temporary PNG file for on-device ML Kit OCR.
  Future<String?> captureStrokesForOcr(List<StrokeElement> strokes) async {
    final bytes = await captureStrokesForOcrBytes(strokes);
    if (bytes == null) return null;
    return writeTempOcrImage(bytes, prefix: 'ocr_bold');
  }

  /// Captures ONLY the selected elements as a cropped image for precise AI Vision OCR
  Future<String?> captureSelectedElementsImage(
    List<BoardElement> selectedElements,
  ) async {
    final bytes = await captureSelectedElementsBytes(selectedElements);
    if (bytes == null) return null;
    return writeTempOcrImage(bytes, prefix: 'selected_crop');
  }

  void _drawElementOnCanvas(Canvas canvas, BoardElement element) {
    _withElementTransform(canvas, element, () {
      if (element is StrokeElement) {
        final inkColor = _ocrContrastColor(element.color);
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = inkColor
          ..strokeWidth = element.strokeWidth;

        if (element.points.length == 1) {
          canvas.drawCircle(
            element.points[0],
            element.strokeWidth / 2,
            Paint()..color = inkColor,
          );
        } else if (element.points.length > 1) {
          canvas.drawPath(element.path, paint);
        }
      } else if (element is TextElement) {
        final inkColor = _ocrContrastColor(element.color);
        final textSpan = TextSpan(
          text: element.text,
          style: TextStyle(
            color: inkColor,
            fontSize: element.fontSize,
            fontWeight: FontWeight.w600,
            fontFamily: element.fontFamily,
          ),
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(canvas, element.position);
      } else if (element is ShapeElement) {
        final inkColor = _ocrContrastColor(element.color);
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = inkColor
          ..strokeWidth = element.strokeWidth;

        ShapeDrawer.drawShape(canvas, element, paint);
      } else if (element is ChemicalElementElement) {
        ChemicalElementDrawer.draw(canvas, element);
      }
    });
  }

  Future<String?> exportToPdf(GlobalKey boundaryKey) async {
    try {
      RenderRepaintBoundary boundary =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      final pdf = pw.Document();
      final imagePdf = pw.MemoryImage(pngBytes);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Center(child: pw.Image(imagePdf));
          },
        ),
      );

      final Uint8List pdfBytes = await pdf.save();
      final fileName =
          'whiteboard_${DateTime.now().millisecondsSinceEpoch}.pdf';

      if (Platform.isAndroid || Platform.isIOS) {
        // Mobile: bytes are REQUIRED, file_picker writes it for you.
        String? outputFile = await FilePicker.saveFile(
          dialogTitle: 'Save Your Whiteboard PDF',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['pdf'],
          bytes: pdfBytes,
        );
        return outputFile;
      } else {
        // Desktop: you get a path back and write it yourself.
        String? outputFile = await FilePicker.saveFile(
          dialogTitle: 'Save Your Whiteboard PDF',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );

        if (outputFile != null) {
          final file = File(outputFile);
          await file.writeAsBytes(pdfBytes);
          return outputFile;
        }
        return null;
      }
    } catch (e) {
      debugPrint('Error exporting PDF: $e');
      rethrow;
    }
  }

  Future<File> generateMultiPagePdfFile({
    required GlobalKey boundaryKey,
    required dynamic provider, // WhiteboardProvider instance
    void Function(int current, int total)? onProgress,
  }) async {
    final pdf = pw.Document();
    final int originalPageIndex = provider.currentPageIndex;
    final int pageCount = provider.pages.length;

    try {
      for (int i = 0; i < pageCount; i++) {
        onProgress?.call(i + 1, pageCount);
        provider.switchPage(i);
        await Future.delayed(const Duration(milliseconds: 180));

        final boundaryContext = boundaryKey.currentContext;
        RenderRepaintBoundary? renderObject;
        if (boundaryContext != null) {
          final ro = boundaryContext.findRenderObject();
          if (ro is RenderRepaintBoundary) {
            renderObject = ro;
          }
        }

        if (renderObject != null) {
          ui.Image image = await renderObject.toImage(pixelRatio: 2.0);
          ByteData? byteData = await image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (byteData != null) {
            Uint8List pngBytes = byteData.buffer.asUint8List();
            final imagePdf = pw.MemoryImage(pngBytes);
            pdf.addPage(
              pw.Page(
                pageFormat: PdfPageFormat.a4.landscape,
                margin: pw.EdgeInsets.zero,
                build: (pw.Context context) {
                  return pw.Center(
                    child: pw.Image(imagePdf, fit: pw.BoxFit.contain),
                  );
                },
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error compiling multi-page PDF: $e');
      rethrow;
    } finally {
      provider.switchPage(originalPageIndex);
    }

    final tempDir = await getTemporaryDirectory();
    final filePath =
        '${tempDir.path}/whiteboard_notes_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  Future<String?> uploadPdfToFirebaseStorage(
    File pdfFile, [
    String? teacherIdOrFolder,
  ]) async {
    await _ensureAuth();
    try {
      final fileName = 'session_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final folder = (teacherIdOrFolder != null && teacherIdOrFolder.isNotEmpty)
          ? 'whiteboard_notes/$teacherIdOrFolder'
          : 'whiteboard_notes';
      final ref = _storage.ref().child(folder).child(fileName);

      UploadTask uploadTask;
      try {
        uploadTask = ref.putFile(
          pdfFile,
          SettableMetadata(contentType: 'application/pdf'),
        );
      } catch (_) {
        final bytes = await pdfFile.readAsBytes();
        uploadTask = ref.putData(
          bytes,
          SettableMetadata(contentType: 'application/pdf'),
        );
      }

      final snapshot = await uploadTask.whenComplete(() {});
      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      debugPrint('Error uploading PDF to Firebase Storage: $e');
      rethrow;
    }
  }
}
