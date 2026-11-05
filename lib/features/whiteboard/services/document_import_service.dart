import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:uuid/uuid.dart';
import '../models/board_element.dart';
import '../models/board_page.dart';
import '../models/image_element.dart';
import 'ppt_conversion_service.dart';


typedef ImportProgressCallback = void Function(int current, int total, String statusMessage);

class DocumentImportService {
  final PptConversionService _pptConversionService = PptConversionService();

  /// Converts a PPT/PPTX/PDF document file into a list of [BoardPage]s,
  /// where each slide page is extracted as a high-resolution image in parallel batches.
  Future<List<BoardPage>> importDocumentToBoardPages({
    required File file,
    required String fileName,
    ImportProgressCallback? onProgress,
    Size? targetScreenSize,
    double bottomToolbarHeight = 65.0,
  }) async {
    final docId = const Uuid().v4();
    final extension = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    File? pdfFile;

    onProgress?.call(0, 100, 'Importing file, please wait a while...');

    if (extension == 'pdf') {
      pdfFile = file;
    } else {
      onProgress?.call(10, 100, 'Uploading file, please wait a while...');
      pdfFile = await _pptConversionService.convertToPdf(
        file,
        docId,
        onStatusUpdate: (statusMessage) {
          onProgress?.call(20, 100, statusMessage);
        },
      );
    }

    if (!await pdfFile.exists()) {
      throw Exception("Failed to process document slides for $fileName.");
    }

    onProgress?.call(40, 100, 'Opening document, please wait a while...');
    final pdfDoc = await PdfDocument.openFile(pdfFile.path);
    final totalPages = pdfDoc.pagesCount;

    if (totalPages == 0) {
      await pdfDoc.close();
      throw Exception("The document contains no readable pages.");
    }

    final List<ImageElement?> importedSlideElements = List<ImageElement?>.filled(totalPages, null);
    final tempDir = await getTemporaryDirectory();
    final double screenWidth = targetScreenSize?.width ?? 1280.0;
    final double screenHeight = targetScreenSize?.height ?? 720.0;

    // Process slides in parallel batches of 4 for maximum performance speedup
    const int batchSize = 4;

    for (int start = 1; start <= totalPages; start += batchSize) {
      final int end = min(start + batchSize - 1, totalPages);
      onProgress?.call(
        40 + ((start / totalPages) * 55).toInt(),
        100,
        'Importing slides, please wait...',
      );

      List<Future<void>> batchFutures = [];
      for (int i = start; i <= end; i++) {
        final pageNum = i;
        batchFutures.add(() async {
          final page = await pdfDoc.getPage(pageNum);
          final double pWidth = page.width;
          final double pHeight = page.height;
          final double aspect = (pHeight > 0 && pWidth > 0) ? (pWidth / pHeight) : (16.0 / 9.0);

          double slideWidth;
          double slideHeight;
          if (aspect >= 1.0) {
            // Landscape presentation: Full screen edge to edge
            slideWidth = screenWidth;
            slideHeight = screenHeight;
          } else {
            // Portrait document (e.g. A4 PDF): Full width edge to edge
            slideWidth = screenWidth;
            slideHeight = screenWidth / aspect;
          }
          const double slideX = 0.0;

          final pageImage = await page.render(
            width: max(page.width * 2.5, screenWidth * 2.0),
            height: max(page.height * 2.5, slideHeight * 2.0),
            format: PdfPageImageFormat.png,
          );
          await page.close();

          if (pageImage != null && pageImage.bytes.isNotEmpty) {
            final imagePath = '${tempDir.path}/slide_${docId}_p${pageNum}_${DateTime.now().millisecondsSinceEpoch}.png';
            final imageFile = File(imagePath);
            await imageFile.writeAsBytes(pageImage.bytes);

            importedSlideElements[pageNum - 1] = ImageElement(
              id: const Uuid().v4(),
              position: const Offset(slideX, 0.0),
              imageUrl: imagePath,
              size: Size(slideWidth, slideHeight),
              isDocumentSlide: true,
            );
          }
        }());
      }
      await Future.wait(batchFutures);
    }

    await pdfDoc.close();

    // Stack slides in vertical sequence edge to edge without gaps
    double currentY = 0.0;
    final List<BoardElement> allSlides = [];

    for (int i = 0; i < totalPages; i++) {
      final slide = importedSlideElements[i];
      if (slide != null) {
        slide.position = Offset(0.0, currentY);
        allSlides.add(slide);
        currentY += slide.size.height;
      }
    }

    onProgress?.call(100, 100, 'Import completed successfully!');

    final verticalDocumentPage = BoardPage(
      id: const Uuid().v4(),
      elements: allSlides,
    );

    return [verticalDocumentPage];
  }

  /// Progressive Document Import:
  /// Renders the INITIAL BATCH (e.g., 5 slides) instantly and returns the initial [BoardPage]
  /// alongside a background worker function that streams remaining slides in batches of 5.
  Future<
      ({
        BoardPage initialPage,
        int totalPages,
        Future<void> Function() backgroundWorker,
      })> importDocumentProgressive({
    required File file,
    required String fileName,
    ImportProgressCallback? onProgress,
    void Function(
      List<ImageElement> batchSlides,
      int totalRendered,
      int totalPages,
    )? onBatchRendered,
    bool Function()? isCancelled,
    Size? targetScreenSize,
    double bottomToolbarHeight = 65.0,
    int initialBatchSize = 5,
  }) async {
    final docId = const Uuid().v4();
    final extension =
        fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    File? pdfFile;

    onProgress?.call(0, 100, 'Importing file, please wait a while...');

    if (extension == 'pdf') {
      pdfFile = file;
    } else {
      onProgress?.call(10, 100, 'Uploading file, please wait a while...');
      pdfFile = await _pptConversionService.convertToPdf(
        file,
        docId,
        onStatusUpdate: (statusMessage) {
          onProgress?.call(20, 100, statusMessage);
        },
      );
    }

    if (!await pdfFile.exists()) {
      throw Exception("Failed to process document slides for $fileName.");
    }

    onProgress?.call(40, 100, 'Opening document, please wait a while...');
    final pdfDoc = await PdfDocument.openFile(pdfFile.path);
    final totalPages = pdfDoc.pagesCount;

    if (totalPages == 0) {
      await pdfDoc.close();
      throw Exception("The document contains no readable pages.");
    }

    final tempDir = await getTemporaryDirectory();
    final double screenWidth = targetScreenSize?.width ?? 1280.0;
    final double screenHeight = targetScreenSize?.height ?? 720.0;

    // 1. Render Initial Batch (Slides 1 to min(initialBatchSize, totalPages))
    final int firstBatchEnd = min(initialBatchSize, totalPages);
    onProgress?.call(
      50,
      100,
      'Preparing your slides, please wait...',
    );

    final List<BoardElement> initialSlides = [];
    double currentY = 0.0;

    for (int pageNum = 1; pageNum <= firstBatchEnd; pageNum++) {
      if (isCancelled?.call() == true) {
        await pdfDoc.close();
        throw Exception("Import cancelled by user.");
      }

      final page = await pdfDoc.getPage(pageNum);
      final double pWidth = page.width;
      final double pHeight = page.height;
      final double aspect =
          (pHeight > 0 && pWidth > 0) ? (pWidth / pHeight) : (16.0 / 9.0);

      double slideWidth = aspect >= 1.0 ? screenWidth : screenWidth;
      double slideHeight =
          aspect >= 1.0 ? screenHeight : (screenWidth / aspect);

      final pageImage = await page.render(
        width: max(page.width * 2.5, screenWidth * 2.0),
        height: max(page.height * 2.5, slideHeight * 2.0),
        format: PdfPageImageFormat.png,
      );
      await page.close();

      if (pageImage != null && pageImage.bytes.isNotEmpty) {
        final imagePath =
            '${tempDir.path}/slide_${docId}_p${pageNum}_${DateTime.now().millisecondsSinceEpoch}.png';
        final imageFile = File(imagePath);
        await imageFile.writeAsBytes(pageImage.bytes);

        final slideElement = ImageElement(
          id: const Uuid().v4(),
          position: Offset(0.0, currentY),
          imageUrl: imagePath,
          size: Size(slideWidth, slideHeight),
          isDocumentSlide: true,
        );

        initialSlides.add(slideElement);
        currentY += slideHeight;
      }
    }

    final initialBoardPage = BoardPage(
      id: const Uuid().v4(),
      elements: initialSlides,
    );

    onProgress?.call(100, 100, 'Preparing completed!');

    // 2. Define background worker for remaining slides (Page firstBatchEnd + 1 to totalPages)
    Future<void> backgroundWorker() async {
      if (firstBatchEnd >= totalPages) {
        await pdfDoc.close();
        return;
      }

      double bgCurrentY = currentY;
      const int bgBatchSize = 5;

      for (int start = firstBatchEnd + 1;
          start <= totalPages;
          start += bgBatchSize) {
        if (isCancelled?.call() == true) {
          debugPrint("Background slide import cancelled.");
          await pdfDoc.close();
          return;
        }

        final int end = min(start + bgBatchSize - 1, totalPages);
        List<ImageElement> batchSlides = [];

        for (int pageNum = start; pageNum <= end; pageNum++) {
          if (isCancelled?.call() == true) break;

          final page = await pdfDoc.getPage(pageNum);
          final double pWidth = page.width;
          final double pHeight = page.height;
          final double aspect =
              (pHeight > 0 && pWidth > 0) ? (pWidth / pHeight) : (16.0 / 9.0);

          double slideWidth = aspect >= 1.0 ? screenWidth : screenWidth;
          double slideHeight =
              aspect >= 1.0 ? screenHeight : (screenWidth / aspect);

          final pageImage = await page.render(
            width: max(page.width * 2.5, screenWidth * 2.0),
            height: max(page.height * 2.5, slideHeight * 2.0),
            format: PdfPageImageFormat.png,
          );
          await page.close();

          if (pageImage != null && pageImage.bytes.isNotEmpty) {
            final imagePath =
                '${tempDir.path}/slide_${docId}_p${pageNum}_${DateTime.now().millisecondsSinceEpoch}.png';
            final imageFile = File(imagePath);
            await imageFile.writeAsBytes(pageImage.bytes);

            final slideElement = ImageElement(
              id: const Uuid().v4(),
              position: Offset(0.0, bgCurrentY),
              imageUrl: imagePath,
              size: Size(slideWidth, slideHeight),
              isDocumentSlide: true,
            );

            batchSlides.add(slideElement);
            bgCurrentY += slideHeight;
          }
        }

        if (batchSlides.isNotEmpty) {
          onBatchRendered?.call(batchSlides, end, totalPages);
        }
      }

      await pdfDoc.close();
    }

    return (
      initialPage: initialBoardPage,
      totalPages: totalPages,
      backgroundWorker: backgroundWorker,
    );
  }
}
