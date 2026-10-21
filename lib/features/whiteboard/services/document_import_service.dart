import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:uuid/uuid.dart';
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

    final List<BoardPage?> importedPages = List<BoardPage?>.filled(totalPages, null);
    final tempDir = await getTemporaryDirectory();
    final double screenWidth = targetScreenSize?.width ?? 1280.0;
    final double screenHeight = targetScreenSize?.height ?? 720.0;

    // Process slides in parallel batches of 4 for maximum performance speedup
    const int batchSize = 4;

    for (int start = 1; start <= totalPages; start += batchSize) {
      final int end = min(start + batchSize - 1, totalPages);
      onProgress?.call(40 + ((start / totalPages) * 55).toInt(), 100, 'Rendering slides $start to $end of $totalPages, please wait...');

      List<Future<void>> batchFutures = [];
      for (int i = start; i <= end; i++) {
        final pageNum = i;
        batchFutures.add(() async {
          final page = await pdfDoc.getPage(pageNum);
          final pageImage = await page.render(width: page.width * 3.0, height: page.height * 3.0, format: PdfPageImageFormat.png);
          await page.close();

          if (pageImage != null && pageImage.bytes.isNotEmpty) {
            final imagePath = '${tempDir.path}/slide_${docId}_p${pageNum}_${DateTime.now().millisecondsSinceEpoch}.png';
            final imageFile = File(imagePath);
            await imageFile.writeAsBytes(pageImage.bytes);

            final imageElement = ImageElement(
              id: const Uuid().v4(),
              position: Offset.zero,
              imageUrl: imagePath,
              size: Size(screenWidth, screenHeight),
            );

            importedPages[pageNum - 1] = BoardPage(id: const Uuid().v4(), elements: [imageElement]);
          }
        }());
      }
      await Future.wait(batchFutures);
    }

    await pdfDoc.close();
    onProgress?.call(100, 100, 'Import completed successfully!');

    return importedPages.whereType<BoardPage>().toList();
  }
}
