import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';
import '../models/board_page.dart';
import '../models/image_element.dart';


typedef ImportProgressCallback = void Function(int current, int total, String statusMessage);

class OfflinePptParserService {
  static const _uuid = Uuid();

  /// Parses a .pptx/.ppt file offline. Converts Slide 1 immediately (blazing fast < 1s)
  /// so the presentation opens instantly, and converts remaining slides in the background.
  Future<List<BoardPage>> parsePptxOffline(
    File pptxFile, {
    Size? targetScreenSize,
    ImportProgressCallback? onProgress,
    void Function(int slideIndex, String imagePath)? onSlideBackgroundConverted,
  }) async {
    final sw = targetScreenSize?.width ?? 1280.0;
    final sh = (targetScreenSize?.height ?? 720.0) - 65.0; // Usable height minus bottom toolbar

    if (!await pptxFile.exists()) {
      throw Exception('PPTX file does not exist at ${pptxFile.path}');
    }

    onProgress?.call(1, 100, 'Opening presentation...');

    // 1. Read archive to extract exact slide dimensions (<p:sldSz cx cy>) and count slides
    final bytes = await pptxFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    double slideWidth = 1920.0;
    double slideHeight = 1080.0;
    try {
      final presFile = archive.files.firstWhere((f) => f.name == 'ppt/presentation.xml');
      final presXml = XmlDocument.parse(utf8.decode(presFile.content as List<int>));
      final sldSz = presXml.findAllElements('p:sldSz').firstOrNull;
      if (sldSz != null) {
        final cx = double.tryParse(sldSz.getAttribute('cx') ?? '') ?? 9144000.0;
        final cy = double.tryParse(sldSz.getAttribute('cy') ?? '') ?? 5143500.0;
        slideWidth = 1920.0;
        slideHeight = 1920.0 * (cy / cx);
      }
    } catch (e) {
      debugPrint('Error reading slide dimensions from presentation.xml: $e');
    }

    final slideFiles = archive.files.where((f) {
      final name = f.name.toLowerCase();
      return name.startsWith('ppt/slides/slide') && name.endsWith('.xml') && !name.contains('_rels');
    }).toList();

    final int totalSlides = slideFiles.isNotEmpty ? slideFiles.length : 1;

    // 2. Setup caching directory
    final appDir = await getApplicationDocumentsDirectory();
    final fileHash = pptxFile.path.hashCode.abs().toString();
    final cacheDir = Directory('${appDir.path}/ppt_cache_$fileHash');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    // Check if cache already exists for all slides
    bool allCached = true;
    final List<String> cachedPaths = List<String>.filled(totalSlides, '');
    for (int i = 0; i < totalSlides; i++) {
      final slideFile = File('${cacheDir.path}/slide_${i + 1}.png');
      if (await slideFile.exists() && (await slideFile.length()) > 0) {
        cachedPaths[i] = slideFile.path;
      } else {
        allCached = false;
      }
    }

    if (allCached) {
      onProgress?.call(totalSlides, totalSlides, 'Loaded cached presentation.');
      return _buildPagesFromImagePaths(cachedPaths, slideWidth, slideHeight, sw, sh);
    }

    // 3. Fast path: Convert Slide 1 immediately so presentation opens instantly (< 1s)
    onProgress?.call(1, totalSlides, 'Preparing Slide 1...');
    final String base64Data = base64Encode(bytes);
    final String jsLibrary = await rootBundle.loadString('assets/pptx-preview.umd.js');

    final List<String> slidePaths = List<String>.from(cachedPaths);

    HeadlessInAppWebView? headlessWebView;
    try {
      headlessWebView = HeadlessInAppWebView(
        initialSize: Size(slideWidth, slideHeight),
        initialData: InAppWebViewInitialData(
          data: '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=${slideWidth.toInt()}, initial-scale=1, maximum-scale=1, user-scalable=no">
  <style>
    html, body {
      margin: 0;
      padding: 0;
      width: ${slideWidth}px;
      height: ${slideHeight}px;
      overflow: hidden;
      background-color: #ffffff;
    }
    #v {
      width: ${slideWidth}px;
      height: ${slideHeight}px;
      position: relative;
      overflow: hidden;
      background-color: #ffffff;
    }
    .pptx-preview-wrapper {
      background-color: #ffffff !important;
      width: ${slideWidth}px !important;
      height: ${slideHeight}px !important;
      position: relative !important;
      overflow: hidden !important;
      margin: 0 !important;
    }
    .pptx-preview-slide-wrapper {
      margin: 0 !important;
      position: absolute !important;
      top: 0 !important;
      left: 0 !important;
      width: ${slideWidth}px !important;
      height: ${slideHeight}px !important;
      background-color: #ffffff !important;
    }
  </style>
</head>
<body>
  <div id="v"></div>
  <script>
    $jsLibrary
    
    window.initPptx = async function(base64Str) {
      try {
        const binaryStr = atob(base64Str);
        const len = binaryStr.length;
        const bytes = new Uint8Array(len);
        for (let i = 0; i < len; i++) {
          bytes[i] = binaryStr.charCodeAt(i);
        }
        const container = document.getElementById('v');
        window.previewer = pptxPreview.init(container, {
          width: ${slideWidth},
          height: ${slideHeight},
          mode: 'slide'
        });
        const pptx = await window.previewer.preview(bytes.buffer);
        return pptx && pptx.slides ? pptx.slides.length : 1;
      } catch (err) {
        console.error("initPptx error:", err);
        throw err;
      }
    };

    window.renderSlideIndex = function(index) {
      if (window.previewer && window.previewer.wrapper) {
        window.previewer.wrapper.innerHTML = '';
      }
      if (window.previewer && window.previewer.htmlRender) {
        window.previewer.htmlRender.renderSlide(index);
      }
    };
  </script>
</body>
</html>
''',
        ),
        initialSettings: InAppWebViewSettings(
          isInspectable: true,
          javaScriptEnabled: true,
          clearCache: true,
          useWideViewPort: true,
          loadWithOverviewMode: true,
          supportZoom: false,
          builtInZoomControls: false,
        ),
      );

      await headlessWebView.run();
      final webViewController = headlessWebView.webViewController;
      if (webViewController == null) {
        throw Exception("Failed to initialize headless webview controller.");
      }

      await Future.delayed(const Duration(milliseconds: 600));

      // Push base64 data in chunks
      await webViewController.evaluateJavascript(source: "window.pptxChunks = [];");
      const int chunkSize = 512 * 1024;
      final int totalLen = base64Data.length;
      for (int offset = 0; offset < totalLen; offset += chunkSize) {
        final int end = min(offset + chunkSize, totalLen);
        final String chunk = base64Data.substring(offset, end);
        await webViewController.evaluateJavascript(source: "window.pptxChunks.push('$chunk');");
      }

      await webViewController.evaluateJavascript(source: """
        (async function() {
          try {
            const fullBase64 = window.pptxChunks.join('');
            window.pptxChunks = null;
            await window.initPptx(fullBase64);
            return true;
          } catch(e) {
            return false;
          }
        })();
      """);

      // Convert Slide 1 immediately
      if (slidePaths[0].isEmpty || !await File(slidePaths[0]).exists()) {
        await webViewController.evaluateJavascript(source: "window.renderSlideIndex(0);");
        await Future.delayed(const Duration(milliseconds: 250));
        final Uint8List? pngBytes = await webViewController.takeScreenshot(
          screenshotConfiguration: ScreenshotConfiguration(compressFormat: CompressFormat.PNG, quality: 100),
        );
        if (pngBytes != null && pngBytes.isNotEmpty) {
          final f = File('${cacheDir.path}/slide_1.png');
          await f.writeAsBytes(pngBytes);
          slidePaths[0] = f.path;
        }
      }

      // If there are remaining slides, convert them in the background asynchronously
      if (totalSlides > 1) {
        Future.microtask(() async {
          try {
            for (int i = 1; i < totalSlides; i++) {
              if (slidePaths[i].isNotEmpty && await File(slidePaths[i]).exists()) continue;

              await webViewController.evaluateJavascript(source: "window.renderSlideIndex($i);");
              await Future.delayed(const Duration(milliseconds: 120));

              final Uint8List? pngBytes = await webViewController.takeScreenshot(
                screenshotConfiguration: ScreenshotConfiguration(compressFormat: CompressFormat.PNG, quality: 100),
              );

              if (pngBytes != null && pngBytes.isNotEmpty) {
                final f = File('${cacheDir.path}/slide_${i + 1}.png');
                await f.writeAsBytes(pngBytes);
                slidePaths[i] = f.path;
                onSlideBackgroundConverted?.call(i, f.path);
              }
            }
          } catch (e) {
            debugPrint("Background slide conversion error: $e");
          } finally {
            await headlessWebView?.dispose();
          }
        });
      } else {
        await headlessWebView.dispose();
      }
    } catch (e) {
      debugPrint("Error in HeadlessInAppWebView PPTX conversion: $e");
      try {
        await headlessWebView?.dispose();
      } catch (_) {}
    }

    // For any unrendered slides on first load, use slide 1 or placeholder temporarily
    for (int i = 0; i < totalSlides; i++) {
      if (slidePaths[i].isEmpty || !await File(slidePaths[i]).exists()) {
        slidePaths[i] = slidePaths[0]; // fallback to slide 1 until background task finishes
      }
    }

    return _buildPagesFromImagePaths(slidePaths, slideWidth, slideHeight, sw, sh);
  }

  List<BoardPage> _buildPagesFromImagePaths(
    List<String> imagePaths,
    double slideW,
    double slideH,
    double boardW,
    double boardH,
  ) {
    final List<BoardPage> pages = [];
    for (int i = 0; i < imagePaths.length; i++) {
      double slideRatio = slideW / slideH;
      double boardRatio = boardW / boardH;
      double w, h;
      if (slideRatio > boardRatio) {
        w = boardW;
        h = boardW / slideRatio;
      } else {
        h = boardH;
        w = boardH * slideRatio;
      }
      Offset pos = Offset((boardW - w) / 2, (boardH - h) / 2);

      final imageElement = ImageElement(
        id: _uuid.v4(),
        position: pos,
        size: Size(w, h),
        imageUrl: imagePaths[i],
        isDocumentSlide: true,
      );

      pages.add(BoardPage(
        id: _uuid.v4(),
        elements: [imageElement],
      ));
    }
    return pages;
  }
}
