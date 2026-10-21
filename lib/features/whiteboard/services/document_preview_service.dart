import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class DocumentPreviewService {
  final FirebaseStorage _storage = FirebaseStorage.instanceFor(
    bucket: 'gs://pencilaiboardapp.firebasestorage.app',
  );

  Future<void> _ensureAuth() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
        debugPrint("Signed in anonymously to Firebase for Storage access");
      }
    } catch (e) {
      debugPrint("Firebase anonymous auth note: $e");
    }
  }

  /// Uploads a document file to Firebase Storage under `temp_previews/{docId}.{extension}`
  /// using `putData(bytes)` and `whenComplete` to guarantee object creation before fetching download URL.
  Future<String?> uploadForPreview(File file, String docId, String extension) async {
    try {
      await _ensureAuth();

      final Uint8List bytes = await file.readAsBytes();
      final storageRef = _storage.ref().child('temp_previews/$docId.$extension');

      final uploadTask = storageRef.putData(
        bytes,
        SettableMetadata(contentType: _getContentType(extension)),
      );

      // Ensure upload task completes 100% on Firebase Storage bucket
      await uploadTask.whenComplete(() {});

      final downloadUrl = await storageRef.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      debugPrint("Error uploading file for preview to Firebase Storage: $e");
      rethrow;
    }
  }

  /// Converts a local PPT / PPTX / DOC / DOCX / XLS / XLSX file to a local PDF file
  /// so that `pdfx` can render it natively with 100% exact page extraction.
  Future<File?> convertToPdf(File sourceFile, String docId, String extension) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final convertedPdfFile = File('${tempDir.path}/${docId}_converted.pdf');

      if (await convertedPdfFile.exists() && (await convertedPdfFile.length()) > 0) {
        return convertedPdfFile;
      }

      final downloadUrl = await uploadForPreview(sourceFile, docId, extension);
      if (downloadUrl == null) return null;

      // ConvertAPI Secret Key for high-speed PPT/PPTX to PDF conversion
      const String convertApiSecret = '193798952';
      final response = await http.post(
        Uri.parse('https://v2.convertapi.com/convert/$extension/to/pdf?Secret=$convertApiSecret&StoreFile=true'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'Files': [
            {
              'File': downloadUrl,
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        if (jsonResponse['Files'] != null && (jsonResponse['Files'] as List).isNotEmpty) {
          final fileUrl = jsonResponse['Files'][0]['Url'];
          final pdfBytesResponse = await http.get(Uri.parse(fileUrl));
          if (pdfBytesResponse.statusCode == 200) {
            await convertedPdfFile.writeAsBytes(pdfBytesResponse.bodyBytes);
            return convertedPdfFile;
          }
        }
      } else {
        debugPrint("ConvertAPI Response Code: ${response.statusCode}, Body: ${response.body}");
      }
      return null;
    } catch (e) {
      debugPrint("PPT to PDF conversion note: $e");
      return null;
    }
  }

  /// Deletes the temporary preview file from Firebase Storage on close/dismiss.
  Future<void> deletePreviewFile(String docId, String extension) async {
    try {
      await _ensureAuth();
      final storageRef = _storage.ref().child('temp_previews/$docId.$extension');
      await storageRef.delete();
      debugPrint("Successfully deleted temp preview file: temp_previews/$docId.$extension");
    } catch (e) {
      debugPrint("Temp preview file delete note: $e");
    }
  }

  String _getContentType(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      default:
        return 'application/octet-stream';
    }
  }
}
