import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pencilai_whitebaord_app/features/whiteboard/models/document_element.dart';
import 'package:pencilai_whitebaord_app/features/whiteboard/models/image_element.dart';
import 'package:pencilai_whitebaord_app/features/whiteboard/models/stroke_element.dart';
import 'package:pencilai_whitebaord_app/features/whiteboard/state/whiteboard_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Eraser PPT/PDF and Document Protection Tests', () {
    late WhiteboardProvider provider;

    setUp(() {
      provider = WhiteboardProvider();
    });

    test('PPT/PDF slide ImageElement is NOT removed when erasing pen strokes on top of it', () {
      // 1. Add imported PPT/PDF slide
      final slide = ImageElement(
        id: 'ppt_slide_1',
        position: Offset.zero,
        size: const Size(800, 600),
        imageUrl: '/temp/slide_doc123_p1.png',
        isDocumentSlide: true,
      );
      provider.addElement(slide);

      // 2. Add pen stroke drawn over the slide
      final stroke = StrokeElement(
        id: 'pen_stroke_1',
        position: const Offset(100, 100),
        points: const [
          Offset(100, 100),
          Offset(110, 110),
          Offset(120, 120),
        ],
        color: Colors.red,
        strokeWidth: 4.0,
      );
      provider.addElement(stroke);

      expect(provider.currentPage.elements.length, equals(2));

      // 3. User uses eraser over the pen stroke and slide area
      provider.partialErase(const Offset(110, 110), 30.0, lastPos: const Offset(100, 100));

      // 4. Verify pen stroke was erased, but PPT/PDF slide is completely preserved!
      final elements = provider.currentPage.elements;
      final slideExists = elements.any((e) => e.id == 'ppt_slide_1');
      final strokeExists = elements.any((e) => e.id == 'pen_stroke_1');

      expect(slideExists, isTrue, reason: 'PPT/PDF slide must NOT be removed by erase');
      expect(strokeExists, isFalse, reason: 'Pen stroke must be erased');
    });

    test('DocumentElement is NOT removed when erasing pen strokes', () {
      final doc = DocumentElement(
        id: 'doc_elem_1',
        position: Offset.zero,
        size: const Size(600, 800),
        filePath: '/storage/presentation.pptx',
        fileName: 'presentation.pptx',
      );
      provider.addElement(doc);

      final stroke = StrokeElement(
        id: 'pen_stroke_2',
        position: const Offset(50, 50),
        points: const [
          Offset(50, 50),
          Offset(60, 60),
        ],
        color: Colors.blue,
        strokeWidth: 3.0,
      );
      provider.addElement(stroke);

      expect(provider.currentPage.elements.length, equals(2));

      // Erase over the stroke and document
      provider.partialErase(const Offset(55, 55), 25.0);

      final elements = provider.currentPage.elements;
      final docExists = elements.any((e) => e.id == 'doc_elem_1');
      final strokeExists = elements.any((e) => e.id == 'pen_stroke_2');

      expect(docExists, isTrue, reason: 'DocumentElement must NOT be removed by erase');
      expect(strokeExists, isFalse, reason: 'Pen stroke must be erased');
    });

    test('User imported images (photos/diagrams) are NOT removed when erasing pen strokes', () {
      final image = ImageElement(
        id: 'diagram_image_1',
        position: Offset.zero,
        size: const Size(400, 300),
        imageUrl: '/photos/diagram.png',
        isDocumentSlide: false,
        isSmartPen: false,
      );
      provider.addElement(image);

      final stroke = StrokeElement(
        id: 'pen_stroke_3',
        position: const Offset(150, 150),
        points: const [
          Offset(150, 150),
          Offset(160, 160),
        ],
        color: Colors.black,
        strokeWidth: 2.0,
      );
      provider.addElement(stroke);

      provider.partialErase(const Offset(155, 155), 20.0);

      final elements = provider.currentPage.elements;
      expect(elements.any((e) => e.id == 'diagram_image_1'), isTrue);
      expect(elements.any((e) => e.id == 'pen_stroke_3'), isFalse);
    });
  });
}
