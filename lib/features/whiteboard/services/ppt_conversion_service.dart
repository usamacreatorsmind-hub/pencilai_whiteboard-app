import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class PptConversionException implements Exception {
  final String message;
  PptConversionException(this.message);
  @override
  String toString() => message;
}


class PptConversionService {
  static const String _cloudRunUrl = 'https://libreoffice-converter-851240445518.asia-south1.run.app/convert';
  static const String _preWarmUrl = 'https://libreoffice-converter-851240445518.asia-south1.run.app/';
  static const String _apiKey = 'default_secret_key';

  /// Pre-warms the Cloud Run server instance to eliminate cold start delays.
  static Future<void> preWarmServer() async {
    try {
      await http.get(Uri.parse(_preWarmUrl)).timeout(const Duration(seconds: 3));
      debugPrint("Cloud Run pre-warm signal sent successfully.");
    } catch (_) {
      // Ignore pre-warm timeout/errors
    }
  }

  /// Converts a local PPT/PPTX file directly to PDF via our Google Cloud Run LibreOffice service.
  Future<File> convertToPdf(File pptFile, String docId, {void Function(String status)? onStatusUpdate}) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final cachedPdfFile = File('${tempDir.path}/${docId}_cached.pdf');

      // 1. Local Caching check
      if (await cachedPdfFile.exists() && (await cachedPdfFile.length()) > 0) {
        debugPrint("Using locally cached converted PDF for docId: $docId");
        onStatusUpdate?.call("Using cached PDF conversion, please wait a while...");
        return cachedPdfFile;
      }

      onStatusUpdate?.call("Converting presentation slides, please wait a while...");
      debugPrint("Sending direct POST conversion request to Cloud Run: $_cloudRunUrl");

      final request = http.MultipartRequest('POST', Uri.parse(_cloudRunUrl));
      request.headers['x-api-key'] = _apiKey;
      request.files.add(await http.MultipartFile.fromPath('file', pptFile.path));

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 120),
        onTimeout: () {
          throw PptConversionException("PPT conversion timed out after 120 seconds. Please check your internet connection.");
        },
      );

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        onStatusUpdate?.call("Processing converted slides, please wait a while...");
        await cachedPdfFile.writeAsBytes(response.bodyBytes);
        debugPrint("Successfully converted PPT to PDF natively: ${cachedPdfFile.path}");
        return cachedPdfFile;
      } else {
        debugPrint("Cloud Run Error Response (${response.statusCode}): ${response.body}");
        throw PptConversionException("Cloud conversion failed (${response.statusCode}). Please ensure your PPT file is valid.");
      }
    } catch (e) {
      if (e is PptConversionException) rethrow;
      throw PptConversionException("Failed to process PPT presentation: $e");
    }
  }
}
