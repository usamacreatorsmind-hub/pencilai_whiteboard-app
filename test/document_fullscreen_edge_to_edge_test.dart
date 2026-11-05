import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pencilai_whitebaord_app/features/whiteboard/models/board_page.dart';
import 'package:pencilai_whitebaord_app/features/whiteboard/models/image_element.dart';
import 'package:pencilai_whitebaord_app/features/whiteboard/state/whiteboard_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Document Full Screen Edge to Edge Tests', () {
    late WhiteboardProvider provider;

    setUp(() {
      provider = WhiteboardProvider();
    });

    test(
      'Document slides are stacked edge-to-edge from (0,0) and navigation aligns without gaps',
      () {
        const double screenWidth = 1920.0;
        const double screenHeight = 1080.0;

        // Create 3 full-screen edge-to-edge slides stacked vertically from y = 0
        final slide1 = ImageElement(
          id: 'slide_1',
          position: const Offset(0.0, 0.0),
          size: const Size(screenWidth, screenHeight),
          imageUrl: '/temp/slide1.png',
          isDocumentSlide: true,
        );

        final slide2 = ImageElement(
          id: 'slide_2',
          position: const Offset(0.0, screenHeight),
          size: const Size(screenWidth, screenHeight),
          imageUrl: '/temp/slide2.png',
          isDocumentSlide: true,
        );

        final slide3 = ImageElement(
          id: 'slide_3',
          position: const Offset(0.0, 2 * screenHeight),
          size: const Size(screenWidth, screenHeight),
          imageUrl: '/temp/slide3.png',
          isDocumentSlide: true,
        );

        final docPage = BoardPage(
          id: 'doc_page_1',
          elements: [slide1, slide2, slide3],
        );

        provider.importPages([docPage]);

        expect(provider.hasDocumentSlides, isTrue);
        expect(provider.totalDocumentSlides, equals(3));
        expect(provider.currentDocumentSlideIndex, equals(0));
        expect(provider.canvasPanOffset, equals(Offset.zero));

        // Jump to slide 2 (index 1) - must align exactly at top edge (0.0) without any gap
        provider.jumpToNextDocumentSlide();
        expect(provider.currentDocumentSlideIndex, equals(1));
        expect(
          provider.canvasPanOffset,
          equals(const Offset(0.0, -screenHeight)),
        );

        // Jump to slide 3 (index 2) - must align exactly at top edge (0.0)
        provider.jumpToNextDocumentSlide();
        expect(provider.currentDocumentSlideIndex, equals(2));
        expect(
          provider.canvasPanOffset,
          equals(const Offset(0.0, -2 * screenHeight)),
        );

        // Jump back to slide 2
        provider.jumpToPreviousDocumentSlide();
        expect(provider.currentDocumentSlideIndex, equals(1));
        expect(
          provider.canvasPanOffset,
          equals(const Offset(0.0, -screenHeight)),
        );

        // Jump back to slide 1
        provider.jumpToPreviousDocumentSlide();
        expect(provider.currentDocumentSlideIndex, equals(0));
        expect(provider.canvasPanOffset, equals(const Offset(0.0, 0.0)));
      },
    );

    test(
      'PanCanvas locks horizontal offset to 0.0 and prevents pulling beyond top/bottom edges',
      () {
        const double screenWidth = 1280.0;
        const double screenHeight = 720.0;
        const viewportSize = Size(screenWidth, screenHeight);

        final slide1 = ImageElement(
          id: 'slide_1',
          position: const Offset(0.0, 0.0),
          size: const Size(screenWidth, screenHeight),
          imageUrl: '/temp/slide1.png',
          isDocumentSlide: true,
        );
        final slide2 = ImageElement(
          id: 'slide_2',
          position: const Offset(0.0, screenHeight),
          size: const Size(screenWidth, screenHeight),
          imageUrl: '/temp/slide2.png',
          isDocumentSlide: true,
        );

        provider.importPages([
          BoardPage(id: 'p1', elements: [slide1, slide2]),
        ]);

        // Attempt to pull down (overscroll top) with horizontal wiggle
        provider.panCanvas(
          const Offset(50.0, 100.0),
          viewportSize: viewportSize,
        );
        expect(
          provider.canvasPanOffset.dx,
          equals(0.0),
          reason: 'Horizontal pan must remain locked at 0 for edge-to-edge',
        );
        expect(
          provider.canvasPanOffset.dy,
          equals(0.0),
          reason: 'Cannot pull down past top edge of slide 1',
        );

        // Scroll down by 200px
        provider.panCanvas(
          const Offset(20.0, -200.0),
          viewportSize: viewportSize,
        );
        expect(provider.canvasPanOffset.dx, equals(0.0));
        expect(provider.canvasPanOffset.dy, equals(-200.0));

        // Attempt to scroll past bottom (maxY is 2 * 720 = 1440. minPanY = -(1440 - 720) = -720)
        provider.panCanvas(
          const Offset(-30.0, -1000.0),
          viewportSize: viewportSize,
        );
        expect(provider.canvasPanOffset.dx, equals(0.0));
        expect(
          provider.canvasPanOffset.dy,
          equals(-720.0),
          reason: 'Cannot scroll past bottom edge of the last slide',
        );
      },
    );
  });
}
