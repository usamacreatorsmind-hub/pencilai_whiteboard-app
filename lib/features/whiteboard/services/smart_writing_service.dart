import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart' hide TextElement;
import 'package:uuid/uuid.dart';
import '../models/stroke_element.dart';
import '../models/text_element.dart';
import '../state/whiteboard_provider.dart';
import 'ai_service.dart';
import 'board_storage_service.dart';

class SmartWritingService {
  static final SmartWritingService _instance = SmartWritingService._internal();
  factory SmartWritingService() => _instance;
  SmartWritingService._internal();

  static const Set<String> _blacklistedPhrases = {
    'n/a',
    'na',
    'none',
    'null',
    'undefined',
    'no text',
    'no text visible',
    'no text found',
    'no text generated',
    'no handwriting ocr generated',
    'no handwriting ocr',
    'no ocr generated',
    'not applicable',
    'no text detected',
    'error',
  };

  /// Sanitizes raw OCR output and returns null if the text is invalid,
  /// blacklisted, or accidental OCR noise.
  String? _cleanAndValidateRecognizedText(String rawText) {
    if (rawText.isEmpty) return null;

    String clean = rawText.trim();
    // Remove quotation marks wrapped by AI/OCR
    if ((clean.startsWith('"') && clean.endsWith('"')) ||
        (clean.startsWith("'") && clean.endsWith("'"))) {
      clean = clean.substring(1, clean.length - 1).trim();
    }

    final lower = clean.toLowerCase();
    if (_blacklistedPhrases.contains(lower)) return null;
    if (lower.startsWith('no ') && lower.contains('generated')) return null;
    if (lower.contains('handwriting ocr')) return null;

    for (var phrase in _blacklistedPhrases) {
      if (lower == phrase || lower.startsWith('$phrase ') || lower.endsWith(' $phrase')) {
        return null;
      }
    }

    // Reject standalone single noise punctuation marks (| ~ _ / \ - . , ?)
    final RegExp noiseOnlyPattern = RegExp(r'^[\s\-_\|\\\/~\.,\?\*\!\#\$\%]+$');
    if (noiseOnlyPattern.hasMatch(clean)) return null;

    // Reject if string doesn't contain at least 1 alphanumeric letter or number
    final RegExp alphaNumericPattern = RegExp(r'[a-zA-Z0-9\u0900-\u097F\u0C00-\u0C7F\u0B80-\u0BFF\u0980-\u09FF\u0A80-\u0AFF\u0D00-\u0D7F]');
    if (!alphaNumericPattern.hasMatch(clean)) return null;

    return clean;
  }

  /// Fast hybrid OCR: Try lightning-fast on-device ML Kit OCR on high-contrast bold image,
  /// with automatic AI Cloud OCR fallback.
  Future<String> _recognizeStrokesText(
    List<StrokeElement> strokes,
    Uint8List? fallbackBytes,
    WhiteboardProvider provider,
  ) async {
    String recognizedText = '';
    String? boldOcrImagePath;

    try {
      // 1. High-contrast bold black stroke rendering for maximum ML Kit accuracy
      boldOcrImagePath = await BoardStorageService().captureStrokesForOcr(strokes);
      if (boldOcrImagePath != null && File(boldOcrImagePath).existsSync()) {
        final inputImage = InputImage.fromFilePath(boldOcrImagePath);
        final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
        final result = await textRecognizer.processImage(inputImage);
        recognizedText = result.text.replaceAll('\n', ' ').trim();
        await textRecognizer.close();
      }
    } catch (e) {
      debugPrint('On-device ML Kit OCR note: $e');
    } finally {
      try {
        if (boldOcrImagePath != null) {
          final f = File(boldOcrImagePath);
          if (await f.exists()) await f.delete();
        }
      } catch (_) {}
    }

    // 2. If on-device ML Kit returns empty or unreadable, fallback to AI Cloud OCR
    if (recognizedText.isEmpty && fallbackBytes != null) {
      recognizedText = await AiService().recognizeHandwriting(
        imageBytes: fallbackBytes,
        language: provider.selectedHandwritingLanguage,
      );
    }

    return recognizedText;
  }

  /// Converts selected handwritten strokes to clean formatted [TextElement]s
  Future<bool> convertSelectedStrokesToText(WhiteboardProvider provider) async {
    final selectedIds = provider.selectedElementIds;
    if (selectedIds.isEmpty) return false;

    final selectedStrokes = provider.currentPage.elements
        .where((e) => selectedIds.contains(e.id) && e is StrokeElement)
        .cast<StrokeElement>()
        .toList();

    if (selectedStrokes.isEmpty) return false;

    // 1. Calculate bounding box and dominant color of selected strokes
    Rect bounds = selectedStrokes[0].getRawBounds();
    Color dominantColor = selectedStrokes[0].color;

    for (int i = 1; i < selectedStrokes.length; i++) {
      final strokeBounds = selectedStrokes[i].getRawBounds();
      bounds = bounds.expandToInclude(strokeBounds);
    }

    // 2. Capture fallback image bytes for Cloud AI
    final imageBytes = await BoardStorageService().captureSelectedElementsBytes(
      selectedStrokes,
    );

    // 3. Fast Hybrid OCR
    final rawText = await _recognizeStrokesText(
      selectedStrokes,
      imageBytes,
      provider,
    );
    final cleanText = _cleanAndValidateRecognizedText(rawText);
    if (cleanText == null) return false;

    // 4. Calculate appropriate font size based on bounding box height
    final double computedFontSize = (bounds.height * 0.45).clamp(14.0, 42.0);

    // Calculate actual layout dimensions with TextPainter so bounds match real text exactly
    final textPainter = TextPainter(
      text: TextSpan(
        text: cleanText,
        style: TextStyle(
          fontSize: computedFontSize,
          fontWeight: FontWeight.w600,
          fontFamily: 'Poppins',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final actualTextSize = textPainter.size;

    // 5. Create new TextElement placed at exact bounding box location with real text size
    final textElement = TextElement(
      id: const Uuid().v4(),
      position: Offset(bounds.left, bounds.top),
      text: cleanText,
      color: dominantColor,
      fontSize: computedFontSize,
      size: actualTextSize,
      fontFamily: 'Poppins',
      docPage: provider.isDocumentOverlayOpen
          ? provider.overlayCurrentPage
          : null,
    );

    // 6. Swap out old strokes for the new clean TextElement
    provider.removeSelectedElements();
    provider.addElement(textElement);
    provider.selectElement(textElement.id);

    return true;
  }

  /// Converts a specific list of handwritten strokes to a formatted [TextElement]
  Future<bool> convertStrokesToFormattedText(
    WhiteboardProvider provider,
    List<StrokeElement> strokes, {
    String fontFamily = 'Poppins',
  }) async {
    if (strokes.isEmpty) return false;

    // 1. Calculate bounding box and dominant color of strokes
    Rect bounds = strokes[0].getRawBounds();
    Color dominantColor = strokes[0].color;

    for (int i = 1; i < strokes.length; i++) {
      final strokeBounds = strokes[i].getRawBounds();
      bounds = bounds.expandToInclude(strokeBounds);
    }

    // 2. Capture fallback image bytes for Cloud AI
    final imageBytes = await BoardStorageService().captureSelectedElementsBytes(
      strokes,
    );

    // 3. Fast Hybrid OCR (ML Kit bold black image -> instant ~20ms, fallback to Cloud AI)
    final rawText = await _recognizeStrokesText(
      strokes,
      imageBytes,
      provider,
    );
    final cleanText = _cleanAndValidateRecognizedText(rawText);
    if (cleanText == null) return false;

    // 4. Calculate appropriate font size based on bounding box height (smaller & neat)
    final double computedFontSize = (bounds.height * 0.45).clamp(14.0, 42.0);

    // Calculate actual layout dimensions with TextPainter so bounds match real text exactly
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

    final actualTextSize = textPainter.size;

    // 5. Create new TextElement placed at exact bounding box location with real text size
    final textElement = TextElement(
      id: const Uuid().v4(),
      position: Offset(bounds.left, bounds.top),
      text: cleanText,
      color: dominantColor,
      fontSize: computedFontSize,
      size: actualTextSize,
      fontFamily: fontFamily,
      docPage: provider.isDocumentOverlayOpen
          ? provider.overlayCurrentPage
          : null,
    );

    // 6. Remove original handwritten strokes and add the clean TextElement
    final strokeIds = strokes.map((s) => s.id).toSet();
    provider.currentPage.elements.removeWhere((e) => strokeIds.contains(e.id));
    provider.addElement(textElement);
    provider.refreshBoard();

    return true;
  }
}
