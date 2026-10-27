import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// A widget that renders a specific slide of a .pptx file 100% offline inside a WebView using pptx-preview.umd.js.
class PptxViewer extends StatefulWidget {
  final File file;
  final Size? size;
  final int slideIndex;

  const PptxViewer({
    super.key,
    required this.file,
    this.size,
    this.slideIndex = 0,
  });

  @override
  State<PptxViewer> createState() => _PptxViewerState();
}

class _PptxViewerState extends State<PptxViewer> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _isPageLoaded = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initWebViewController();
  }

  @override
  void didUpdateWidget(covariant PptxViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _retryRender();
    } else if (oldWidget.slideIndex != widget.slideIndex && _isPageLoaded && !_isLoading) {
      _switchSlideTo(widget.slideIndex);
    }
  }

  void _initWebViewController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setOnConsoleMessage((JavaScriptConsoleMessage message) {
        debugPrint('[PptxViewer JS Console] ${message.level.name}: ${message.message}');
      })
      ..addJavaScriptChannel(
        'PptxViewerChannel',
        onMessageReceived: (JavaScriptMessage message) {
          if (!mounted) return;
          try {
            final data = jsonDecode(message.message);
            if (data['status'] == 'success') {
              setState(() {
                _isLoading = false;
                _errorMessage = null;
              });
            } else if (data['status'] == 'error') {
              setState(() {
                _isLoading = false;
                _errorMessage = data['message'] ?? 'Failed to render PPTX presentation.';
              });
            }
          } catch (e) {
            debugPrint('[PptxViewer] Error parsing channel message: $e');
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            if (mounted && !_isPageLoaded) {
              _isPageLoaded = true;
              _renderPptx();
            }
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('[PptxViewer WebResourceError] ${error.description}');
            if (mounted) {
              setState(() {
                _isLoading = false;
                _errorMessage = error.description;
              });
            }
          },
        ),
      );

    _loadInitialHtml();
  }

  Future<void> _loadInitialHtml() async {
    const htmlContent = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes">
  <style>
    html, body {
      margin: 0;
      padding: 0;
      width: 100%;
      height: 100%;
      background-color: #ffffff;
      overflow: hidden;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    #v {
      width: 100%;
      height: 100%;
      box-sizing: border-box;
      display: flex;
      align-items: center;
      justify-content: center;
      overflow: hidden;
    }
    .pptx-preview-wrapper {
      background-color: #ffffff !important;
      width: 100% !important;
      height: 100% !important;
      display: flex !important;
      align-items: center !important;
      justify-content: center !important;
      overflow: hidden !important;
      margin: 0 !important;
    }
    .pptx-preview-slide-wrapper {
      margin: 0 auto !important;
      box-shadow: none !important;
      max-width: 100% !important;
      max-height: 100% !important;
      position: relative !important;
      top: 0 !important;
      background-color: #ffffff !important;
    }
    .pptx-preview-slide-wrapper svg,
    .pptx-preview-slide-wrapper canvas,
    .pptx-preview-slide-wrapper img {
      max-width: 100% !important;
      max-height: 100% !important;
    }
  </style>
</head>
<body>
  <div id="v"></div>
</body>
</html>
''';

    await _controller.loadHtmlString(htmlContent);
  }

  /// Copies file to app-accessible storage directory if necessary (e.g. Android content picker cache)
  Future<File> _getAccessibleFile(File source) async {
    try {
      if (await source.exists()) {
        final appDir = await getApplicationDocumentsDirectory();
        final fileName = source.path.split('/').last;
        final targetPath = '${appDir.path}/$fileName';

        if (source.path == targetPath) {
          return source;
        }

        final targetFile = File(targetPath);
        if (!await targetFile.exists() || (await targetFile.length()) != (await source.length())) {
          return await source.copy(targetPath);
        }
        return targetFile;
      }
    } catch (e) {
      debugPrint('[PptxViewer] Error copying file to app storage: $e');
    }
    return source;
  }

  /// Fast switch slide index without re-parsing chunks if file hasn't changed
  Future<void> _switchSlideTo(int targetSlideIndex) async {
    try {
      final String script = '''
        (function() {
          if (window.currentPreviewer && window.currentPreviewer.htmlRender) {
            if (window.currentPreviewer.wrapper) {
              window.currentPreviewer.wrapper.innerHTML = '';
            }
            window.currentPreviewer.htmlRender.renderSlide($targetSlideIndex);
          }
        })();
      ''';
      await _controller.runJavaScript(script);
    } catch (e) {
      debugPrint('[PptxViewer] Error switching slide index: $e');
    }
  }

  /// Sends the PPTX file bytes in chunks to JS and renders the specified slide via pptxPreview library
  Future<void> _renderPptx() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final accessibleFile = await _getAccessibleFile(widget.file);
      if (!await accessibleFile.exists()) {
        throw Exception("PPTX file does not exist at path: ${accessibleFile.path}");
      }

      final Uint8List bytes = await accessibleFile.readAsBytes();
      if (bytes.isEmpty) {
        throw Exception("PPTX file is empty.");
      }

      // Check for legacy binary .ppt (PowerPoint 97-2003 OLE Compound File header: 0xD0 0xCF)
      if (bytes.length >= 2 && bytes[0] == 0xD0 && bytes[1] == 0xCF) {
        throw Exception("Binary .ppt (PowerPoint 97-2003) is not supported offline.\nPlease save or convert the file as .pptx format.");
      }

      // Convert file bytes to base64
      final String base64Data = base64Encode(bytes);

      // 1. Read local pptx-preview library UMD bundle from rootBundle assets
      final String jsLibrary = await rootBundle.loadString('assets/pptx-preview.umd.js');

      // 2. Inject library script into WebView DOM
      await _controller.runJavaScript(jsLibrary);

      // 3. Initialize chunk array in JS scope
      await _controller.runJavaScript('window.pptxChunks = [];');

      // 4. CHUNKED TRANSFER LOGIC:
      // Partition base64Data into 512 KB chunks and append them sequentially in JS.
      const int chunkSize = 512 * 1024;
      final int totalLength = base64Data.length;
      for (int offset = 0; offset < totalLength; offset += chunkSize) {
        final int end = min(offset + chunkSize, totalLength);
        final String chunk = base64Data.substring(offset, end);
        await _controller.runJavaScript("window.pptxChunks.push('$chunk');");
      }

      // 5. Reassemble chunks in JS, decode to Uint8Array, and render single slide
      final double? targetW = widget.size?.width;
      final double? targetH = widget.size?.height;

      final String renderScript = '''
        (async function() {
          try {
            if (!window.pptxChunks || window.pptxChunks.length === 0) {
              throw new Error("No chunked PPTX data received.");
            }
            const fullBase64 = window.pptxChunks.join('');
            window.pptxChunks = null;

            const binaryStr = atob(fullBase64);
            const len = binaryStr.length;
            const bytes = new Uint8Array(len);
            for (let i = 0; i < len; i++) {
              bytes[i] = binaryStr.charCodeAt(i);
            }
            const arrayBuffer = bytes.buffer;

            const container = document.getElementById('v');
            if (!container) {
              throw new Error("Container '#v' not found in DOM.");
            }
            container.innerHTML = '';

            if (typeof pptxPreview === 'undefined' || !pptxPreview.init) {
              throw new Error("pptxPreview library not found on global scope.");
            }

            const options = {
              element: container,
              ${targetW != null && targetW > 0 ? 'width: $targetW,' : ''}
              ${targetH != null && targetH > 0 ? 'height: $targetH,' : ''}
            };

            window.currentPreviewer = pptxPreview.init(container, options);
            const pptx = await window.currentPreviewer.preview(arrayBuffer);

            if (window.currentPreviewer.wrapper) {
              window.currentPreviewer.wrapper.innerHTML = '';
            }

            const totalSlides = (pptx && pptx.slides) ? pptx.slides.length : 1;
            const targetIdx = (${widget.slideIndex} >= 0 && ${widget.slideIndex} < totalSlides) ? ${widget.slideIndex} : 0;

            if (window.currentPreviewer.htmlRender && typeof window.currentPreviewer.htmlRender.renderSlide === 'function') {
              window.currentPreviewer.htmlRender.renderSlide(targetIdx);
            }

            if (window.PptxViewerChannel) {
              window.PptxViewerChannel.postMessage(JSON.stringify({
                status: 'success',
                totalSlides: totalSlides,
                currentSlide: targetIdx
              }));
            }
          } catch (err) {
            console.error("PPTX JS execution error:", err);
            if (window.PptxViewerChannel) {
              window.PptxViewerChannel.postMessage(JSON.stringify({ status: 'error', message: err.message || String(err) }));
            }
          }
        })();
      ''';

      await _controller.runJavaScript(renderScript);
    } catch (e) {
      debugPrint('[PptxViewer] Exception during _renderPptx: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _retryRender() {
    _isPageLoaded = false;
    _loadInitialHtml();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            Container(
              color: Colors.white,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.blueAccent),
                    SizedBox(height: 12),
                    Text(
                      'Rendering slide...',
                      style: TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w600, decoration: TextDecoration.none),
                    ),
                  ],
                ),
              ),
            ),
          if (_errorMessage != null && !_isLoading)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 40),
                    const SizedBox(height: 8),
                    const Text(
                      'Failed to render slide',
                      style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 14, decoration: TextDecoration.none),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.black54, fontSize: 11, decoration: TextDecoration.none),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _retryRender,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

