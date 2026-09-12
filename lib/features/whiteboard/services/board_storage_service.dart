import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
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

class BoardStorageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<void> saveBoard(String sessionId, List<BoardPage> pages) async {
    final data = {'pages': pages.map((p) => p.toJson()).toList(), 'updatedAt': FieldValue.serverTimestamp()};
    await _firestore.collection('whiteboard_sessions').doc(sessionId).set(data);
  }

  Future<List<BoardPage>> loadBoard(String sessionId) async {
    final doc = await _firestore.collection('whiteboard_sessions').doc(sessionId).get();
    if (!doc.exists) return [];

    final data = doc.data() as Map<String, dynamic>;
    final pagesList = data['pages'] as List;
    return pagesList.map((p) => BoardPage.fromJson(p)).toList();
  }

  Future<String> exportToImage(GlobalKey boundaryKey) async {
    try {
      RenderRepaintBoundary boundary =
      boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/whiteboard_${DateTime.now().millisecondsSinceEpoch}.png';
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

  Future<String?> exportToPdf(GlobalKey boundaryKey) async {
    try {
      RenderRepaintBoundary boundary = boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
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
      final fileName = 'whiteboard_${DateTime.now().millisecondsSinceEpoch}.pdf';

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
}
