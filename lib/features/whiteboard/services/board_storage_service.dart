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

class BoardStorageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
        debugPrint('Signed in anonymously to Firebase for Board Storage access');
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

  /// Captures ONLY the selected elements as a cropped image for precise AI Vision OCR
  Future<String?> captureSelectedElementsImage(
    List<BoardElement> selectedElements,
  ) async {
    try {
      if (selectedElements.isEmpty) return null;

      // 1. Calculate combined bounding box of selected elements
      Rect bounds = selectedElements[0].getRawBounds();
      for (int i = 1; i < selectedElements.length; i++) {
        bounds = bounds.expandToInclude(selectedElements[i].getRawBounds());
      }

      if (bounds.width <= 0 || bounds.height <= 0) return null;

      const double padding = 20.0;
      final cropRect = Rect.fromLTRB(
        bounds.left - padding,
        bounds.top - padding,
        bounds.right + padding,
        bounds.bottom + padding,
      );

      final double imageWidth = cropRect.width;
      final double imageHeight = cropRect.height;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // 1. Draw white background covering the image bounds (0, 0, imageWidth, imageHeight)
      canvas.drawRect(
        Rect.fromLTWH(0, 0, imageWidth, imageHeight),
        Paint()..color = Colors.white,
      );

      // 2. Translate canvas so cropRect.left, cropRect.top maps to (0, 0)
      canvas.translate(-cropRect.left, -cropRect.top);

      // 3. Render ONLY selected elements
      for (var element in selectedElements) {
        _drawElementOnCanvas(canvas, element);
      }

      final picture = recorder.endRecording();
      final image = await picture.toImage(
        cropRect.width.toInt().clamp(20, 2000),
        cropRect.height.toInt().clamp(20, 2000),
      );
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      final tempDir = await getTemporaryDirectory();
      final path =
          '${tempDir.path}/selected_crop_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(path);
      await file.writeAsBytes(byteData.buffer.asUint8List());
      return path;
    } catch (e) {
      debugPrint('Error capturing selected elements image: $e');
      return null;
    }
  }

  void _drawElementOnCanvas(Canvas canvas, BoardElement element) {
    if (element is StrokeElement) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = element.color
        ..strokeWidth = element.strokeWidth;

      if (element.points.length == 1) {
        canvas.drawCircle(
          element.points[0],
          element.strokeWidth / 2,
          Paint()..color = element.color,
        );
      } else if (element.points.length > 1) {
        canvas.drawPath(element.path, paint);
      }
    } else if (element is TextElement) {
      final textSpan = TextSpan(
        text: element.text,
        style: TextStyle(
          color: element.color,
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
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = element.color
        ..strokeWidth = element.strokeWidth;

      switch (element.shapeType) {
        case ShapeType.line:
          canvas.drawLine(element.position, element.endPoint, paint);
          break;
        case ShapeType.rectangle:
          canvas.drawRect(
            Rect.fromPoints(element.position, element.endPoint),
            paint,
          );
          break;
        case ShapeType.circle:
          canvas.drawOval(
            Rect.fromPoints(element.position, element.endPoint),
            paint,
          );
          break;
        default:
          canvas.drawRect(
            Rect.fromPoints(element.position, element.endPoint),
            paint,
          );
          break;
      }
    } else if (element is ChemicalElementElement) {
      ChemicalElementDrawer.draw(canvas, element);
    }
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
                  return pw.Center(child: pw.Image(imagePdf, fit: pw.BoxFit.contain));
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
      final fileName =
          'session_${DateTime.now().millisecondsSinceEpoch}.pdf';
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
