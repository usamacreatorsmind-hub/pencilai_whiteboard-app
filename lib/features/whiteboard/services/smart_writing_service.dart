import 'package:flutter/material.dart';
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

    // 2. Capture ONLY selected strokes region as in-memory bytes for fast AI OCR
    final imageBytes = await BoardStorageService().captureSelectedElementsBytes(
      selectedStrokes,
    );
    if (imageBytes == null) return false;

    // 3. Fast AI Vision OCR (SmartWrite is always in English)
    final recognizedText = await AiService().recognizeHandwriting(
      imageBytes: imageBytes,
      language: 'English',
    );
    if (recognizedText.isEmpty ||
        recognizedText.startsWith('Error') ||
        recognizedText.startsWith('⚠️')) {
      return false;
    }

    // Clean up text
    final cleanText = recognizedText.trim();
    if (cleanText.isEmpty ||
        cleanText.toLowerCase().contains('no text visible')) {
      return false;
    }

    // 4. Calculate appropriate font size based on bounding box height
    final double computedFontSize = (bounds.height * 0.75).clamp(18.0, 96.0);

    // Calculate actual layout dimensions with TextPainter so bounds match real text exactly
    final textPainter = TextPainter(
      text: TextSpan(
        text: cleanText,
        style: TextStyle(
          fontSize: computedFontSize,
          fontWeight: FontWeight.w600,
          fontFamily: 'Roboto',
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
}
