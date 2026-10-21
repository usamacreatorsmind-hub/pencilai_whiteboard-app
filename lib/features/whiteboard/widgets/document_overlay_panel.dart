import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:pdfx/pdfx.dart';
import '../state/whiteboard_provider.dart';
import '../models/document_element.dart';
import '../models/image_element.dart';
import '../services/document_preview_service.dart';
import '../../../widgets/pptx_viewer.dart';

/// Right-Side Document Side Sheet / Panel placed in WhiteboardScreen stack
class DocumentOverlayPanel extends StatefulWidget {
  const DocumentOverlayPanel({super.key});

  @override
  State<DocumentOverlayPanel> createState() => _DocumentOverlayPanelState();
}

class _DocumentOverlayPanelState extends State<DocumentOverlayPanel> {
  double _panelWidth = 580.0;
  double _topOffset = 0.0;
  double _bottomOffset = 0.0;
  bool _isImporting = false;
  bool _isMinimized = false;
  String? _lastDocId;

  int _currentPage = 1;
  int _totalPages = 10;

  final GlobalKey _previewBoundaryKey = GlobalKey();

  Future<void> _importSlideToWhiteboard(BuildContext context) async {
    if (_isImporting) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final provider = Provider.of<WhiteboardProvider>(context, listen: false);

    setState(() => _isImporting = true);

    try {
      final doc = provider.activeOverlayDocument;
      File? pdfFile;
      if (doc != null && doc.fileName.toLowerCase().endsWith('.pdf')) {
        pdfFile = File(doc.filePath);
      } else if (doc != null) {
        final tempDir = await getTemporaryDirectory();
        final converted = File('${tempDir.path}/${doc.id}_converted.pdf');
        if (await converted.exists() && (await converted.length()) > 0) {
          pdfFile = converted;
        }
      }

      // Native PDF / Converted PPT Page Rendering (Pixel-perfect single slide extraction)
      if (pdfFile != null && await pdfFile.exists()) {
        final pdfDoc = await PdfDocument.openFile(pdfFile.path);
        final targetPageNum = _currentPage.clamp(1, pdfDoc.pagesCount);
        final page = await pdfDoc.getPage(targetPageNum);

        final pageImage = await page.render(
          width: page.width * 3.0,
          height: page.height * 3.0,
          format: PdfPageImageFormat.png,
        );

        await page.close();
        await pdfDoc.close();

        if (pageImage != null && pageImage.bytes.isNotEmpty) {
          final tempDir = await getTemporaryDirectory();
          final imagePath = '${tempDir.path}/slide_${DateTime.now().millisecondsSinceEpoch}.png';
          final file = File(imagePath);
          await file.writeAsBytes(pageImage.bytes);

          final double aspectRatio = page.height / page.width;
          final double renderWidth = 560.0;
          final double renderHeight = renderWidth * aspectRatio;

          final imageElement = ImageElement(
            id: const Uuid().v4(),
            position: const Offset(120, 80),
            imageUrl: imagePath,
            size: Size(renderWidth, renderHeight),
          );

          provider.addElement(imageElement);
          provider.closeDocumentOverlay();

          return;
        }
      }

      // Full 1:1 Viewport Boundary Capture (Preserves full slide title and content without cropping)
      final boundary = _previewBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception("Preview area is not ready yet.");
      }

      ui.Image fullImage = await boundary.toImage(pixelRatio: 3.0);
      final double W = fullImage.width.toDouble();
      final double H = fullImage.height.toDouble();

      final srcRect = Rect.fromLTWH(0, 0, W, H);
      final dstRect = Rect.fromLTWH(0, 0, W, H);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, dstRect);
      canvas.drawImageRect(fullImage, srcRect, dstRect, Paint()..filterQuality = ui.FilterQuality.high);

      final picture = recorder.endRecording();
      final croppedImage = await picture.toImage(W.toInt(), H.toInt());
      ByteData? byteData = await croppedImage.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final Uint8List pngBytes = byteData.buffer.asUint8List();
        final tempDir = await getTemporaryDirectory();
        final imagePath = '${tempDir.path}/slide_${DateTime.now().millisecondsSinceEpoch}.png';
        final file = File(imagePath);
        await file.writeAsBytes(pngBytes);

        final double aspectRatio = H / W;
        final double renderWidth = 560.0;
        final double renderHeight = renderWidth * aspectRatio;

        final imageElement = ImageElement(
          id: const Uuid().v4(),
          position: const Offset(120, 80),
          imageUrl: imagePath,
          size: Size(renderWidth, renderHeight),
        );

        provider.addElement(imageElement);
        provider.closeDocumentOverlay();

        scaffoldMessenger.showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text('Page $_currentPage added to Whiteboard! You can now draw on it.'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error ide: $e");
      scaffoldMessenger.showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text('Failed to import slide: $e')));
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<WhiteboardProvider>(context);

    if (!provider.isDocumentOverlayOpen || provider.activeOverlayDocument == null) {
      return const SizedBox.shrink();
    }

    final doc = provider.activeOverlayDocument!;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Reset minimization & pages on new document
    if (_lastDocId != doc.id) {
      _lastDocId = doc.id;
      _isMinimized = false;
      _currentPage = 1;
      _totalPages = 10;
    }

    // Minimized Floating Action Button Mode
    if (_isMinimized) {
      return Positioned(
        right: 30,
        bottom: 90,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Circular Floating Action Button
            FloatingActionButton(
              heroTag: 'doc_floating_toggle_btn',
              onPressed: () {
                setState(() {
                  _isMinimized = false;
                });
              },
              backgroundColor: const Color(0xFF1E1E1E),
              elevation: 12,
              shape: const CircleBorder(
                side: BorderSide(color: Colors.blueAccent, width: 1.5),
              ),
              child: Icon(
                doc.fileName.toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf_rounded : Icons.slideshow_rounded,
                color: doc.fileName.toLowerCase().endsWith('.pdf') ? Colors.redAccent : Colors.orangeAccent,
                size: 24,
              ),
            ),

            // Cancel / Close Badge Icon on Top-Right (Crisp Vector)
            Positioned(
              top: -4,
              right: -4,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _isMinimized = false;
                  });
                  provider.closeDocumentOverlay();
                },
                child: Material(
                  color: Colors.redAccent,
                  shape: const CircleBorder(),
                  elevation: 4,
                  child: const Padding(
                    padding: EdgeInsets.all(4.0),
                    child: Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Positioned.fill(
      child: Material(
        elevation: 24,
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF242424),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 24, spreadRadius: 6)],
          ),
          child: Column(
            children: [
              // Header Bar (Title + Icon + Page Count Badge + Minimize + Close)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: const BoxDecoration(
                  color: Color(0xFF1E1E1E),
                  border: Border(bottom: BorderSide(color: Colors.white12, width: 1)),
                ),
                child: Row(
                  children: [
                    Icon(
                      doc.fileName.toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf_rounded : Icons.description_rounded,
                      size: 20,
                      color: doc.fileName.toLowerCase().endsWith('.pdf') ? Colors.redAccent : Colors.orangeAccent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        doc.fileName,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Dynamic Page Count Indicator Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.6), width: 1),
                      ),
                      child: Text(
                        '$_currentPage / $_totalPages',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.unfold_less, size: 20, color: Colors.white70),
                      onPressed: () {
                        setState(() {
                          _isMinimized = true;
                        });
                      },
                      tooltip: 'Minimize to Floating Button',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20, color: Colors.white70),
                      onPressed: provider.closeDocumentOverlay,
                      tooltip: 'Close Panel',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

              // Document Native / WebView Content
              Expanded(
                child: RepaintBoundary(
                  key: _previewBoundaryKey,
                  child: Container(
                    color: Colors.white,
                    child: DocumentOverlayContent(
                      doc: doc,
                      onPageChanged: (page) {
                        if (mounted && _currentPage != page && page > 0) {
                          setState(() {
                            _currentPage = page;
                          });
                        }
                      },
                      onTotalPagesLoaded: (totalPages) {
                        if (mounted && _totalPages != totalPages && totalPages > 0) {
                          setState(() {
                            _totalPages = totalPages;
                          });
                        }
                      },
                    ),
                  ),
                ),
              ),

              // Bottom Toolbar with "Add Page X to Whiteboard" Button (Commented out)
              /*
              GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _bottomOffset = (_bottomOffset - details.delta.dy).clamp(0.0, screenHeight - 250.0);
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E1E1E),
                    border: Border(top: BorderSide(color: Colors.white12, width: 1)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _isImporting ? null : () => _importSlideToWhiteboard(context),
                        icon: _isImporting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent),
                              )
                            : const Icon(Icons.add_to_photos_rounded, size: 16, color: Colors.blueAccent),
                        label: Text(
                          _isImporting
                              ? 'Importing Page $_currentPage...'
                              : 'Add Page $_currentPage to Whiteboard',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.blueAccent, width: 1.5),
                          backgroundColor: Colors.blueAccent.withValues(alpha: 0.15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.unfold_less, size: 18, color: Colors.white54),
                            onPressed: () {
                              setState(() {
                                _isMinimized = true;
                              });
                            },
                            tooltip: 'Minimize Panel',
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18, color: Colors.white54),
                            onPressed: provider.closeDocumentOverlay,
                            tooltip: 'Close Panel',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              */
            ],
          ),
        ),
      ),
    );
  }
}

class DocumentOverlayContent extends StatefulWidget {
  final DocumentElement doc;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onTotalPagesLoaded;

  const DocumentOverlayContent({
    super.key,
    required this.doc,
    required this.onPageChanged,
    required this.onTotalPagesLoaded,
  });

  @override
  State<DocumentOverlayContent> createState() => _DocumentOverlayContentState();
}

class _DocumentOverlayContentState extends State<DocumentOverlayContent> {
  final DocumentPreviewService _previewService = DocumentPreviewService();
  bool _isUploading = false;
  String? _previewUrl;
  String? _convertedPdfPath;
  String? _uploadError;

  WebViewController? _webViewController;
  bool _isLoadingWebView = true;
  int _loadingProgress = 0;
  bool _hasWebViewError = false;
  String? _webErrorDescription;
  bool _useGoogleViewer = false;

  @override
  void initState() {
    super.initState();
    final extension = _getExtension(widget.doc.fileName);
    _useGoogleViewer = true;

    _previewUrl = widget.doc.remotePreviewUrl;
    if (_previewUrl == null && extension != 'pdf') {
      _startUploadAndInitWebView();
    } else if (extension != 'pdf' && _previewUrl != null) {
      _initWebView(_previewUrl!);
    }
  }

  Future<void> _startUploadAndInitWebView() async {
    setState(() {
      _isUploading = true;
      _uploadError = null;
    });

    try {
      final extension = _getExtension(widget.doc.fileName);
      final file = File(widget.doc.filePath);

      if (!await file.exists()) {
        throw Exception("Local file not found.");
      }

      // Convert PPT / PPTX / DOC to PDF for 100% native vector rendering via pdfx
      if (extension != 'pdf') {
        final convertedPdf = await _previewService.convertToPdf(file, widget.doc.id, extension);
        if (convertedPdf != null && mounted) {
          setState(() {
            _convertedPdfPath = convertedPdf.path;
            _isUploading = false;
          });
          return;
        }
      }

      final url = await _previewService.uploadForPreview(file, widget.doc.id, extension);
      if (url != null && mounted) {
        setState(() {
          _previewUrl = url;
          _isUploading = false;
        });
        Provider.of<WhiteboardProvider>(context, listen: false).updateActiveDocumentPreviewUrl(url);
        _initWebView(url);
      } else {
        throw Exception("Failed to generate preview URL.");
      }
    } catch (e) {
      if (mounted) {
        String errorMsg = e.toString().replaceAll('Exception: ', '');
        if (errorMsg.contains('unauthorized')) {
          errorMsg = "Firebase Storage Rules require permission.\nIn Firebase Console -> Storage -> Rules, allow write for 'temp_previews' folder, or enable Anonymous Auth in Firebase Authentication.";
        }
        setState(() {
          _isUploading = false;
          _uploadError = errorMsg;
        });
      }
    }
  }

  void _initWebView(String downloadUrl) {
    final extension = _getExtension(widget.doc.fileName);
    final isPdf = extension == 'pdf';

    final String viewerUrl;
    if (isPdf) {
      viewerUrl = downloadUrl;
    } else if (_useGoogleViewer) {
      viewerUrl = 'https://docs.google.com/gview?embedded=true&url=${Uri.encodeComponent(downloadUrl)}';
    } else {
      viewerUrl = 'https://view.officeapps.live.com/op/embed.aspx?src=${Uri.encodeComponent(downloadUrl)}';
    }

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setUserAgent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36")
      ..addJavaScriptChannel(
        'PageScrollChannel',
        onMessageReceived: (JavaScriptMessage message) {
          final text = message.message.trim();
          if (text.contains('/')) {
            final parts = text.split('/');
            final page = int.tryParse(parts[0].trim());
            final total = int.tryParse(parts[1].trim());
            if (page != null && page > 0) {
              widget.onPageChanged(page);
            }
            if (total != null && total > 0) {
              widget.onTotalPagesLoaded(total);
            }
          } else {
            final page = int.tryParse(text);
            if (page != null && page > 0) {
              widget.onPageChanged(page);
            }
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (mounted) {
              setState(() {
                _loadingProgress = progress;
                if (progress > 60) {
                  _isLoadingWebView = false;
                }
              });
            }
          },
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _isLoadingWebView = true;
                _hasWebViewError = false;
                _loadingProgress = 0;
              });
            }
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _isLoadingWebView = false;
                _loadingProgress = 100;
              });
              _webViewController?.runJavaScript('''
                (function() {
                  // 1. Hide Google Docs Viewer floating page number pill
                  var style = document.createElement('style');
                  style.innerHTML = `
                    .ndfHFb-c4325e-i5915e, .drive-viewer-page-number-kbf, [role="tooltip"], .ndfHFb-c4325e-i5915e-A2633e {
                      display: none !important;
                      visibility: hidden !important;
                      opacity: 0 !important;
                    }
                  `;
                  document.head.appendChild(style);

                  // 2. Continuously detect active slide page & total pages from Viewer DOM
                  function syncPageNumber() {
                    var pageElem = document.querySelector('.ndfHFb-c4325e-i5915e, .drive-viewer-page-number, [aria-label*="Page"]');
                    if (pageElem) {
                      var text = pageElem.innerText || pageElem.textContent || '';
                      var match = text.match(/(\\d+)\\s*\\/\\s*(\\d+)/) || text.match(/Page\\s*(\\d+)\\s*of\\s*(\\d+)/i) || text.match(/Page\\s*(\\d+)/i);
                      if (match) {
                        if (match[2]) {
                          window.PageScrollChannel.postMessage(match[1] + '/' + match[2]);
                        } else if (match[1]) {
                          window.PageScrollChannel.postMessage(match[1]);
                        }
                      }
                    } else {
                      var scrollTop = window.pageYOffset || document.documentElement.scrollTop || document.body.scrollTop || 0;
                      var viewHeight = window.innerHeight || 500;
                      var page = Math.floor(scrollTop / (viewHeight * 0.8)) + 1;
                      if (window.PageScrollChannel) {
                        window.PageScrollChannel.postMessage(page.toString());
                      }
                    }
                  }

                  setInterval(syncPageNumber, 600);
                })();
              ''').catchError((_) {});
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (mounted) {
              setState(() {
                _isLoadingWebView = false;
                _hasWebViewError = true;
                _webErrorDescription = error.description;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(viewerUrl));

    setState(() {
      _webViewController = controller;
    });
  }

  void _switchViewer() {
    if (_previewUrl != null) {
      setState(() {
        _useGoogleViewer = !_useGoogleViewer;
      });
      _initWebView(_previewUrl!);
    }
  }

  String _getExtension(String fileName) {
    return fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
  }

  @override
  Widget build(BuildContext context) {
    final extension = _getExtension(widget.doc.fileName);
    final isPdf = extension == 'pdf';
    final lowerPath = widget.doc.filePath.toLowerCase();
    final isPptx = extension == 'pptx' || extension == 'ppt' || lowerPath.endsWith('.pptx') || lowerPath.endsWith('.ppt');

    if (isPptx) {
      return PptxViewer(
        file: File(widget.doc.filePath),
      );
    }

    final effectivePdfPath = isPdf ? widget.doc.filePath : _convertedPdfPath;

    if (effectivePdfPath != null) {
      return NativePdfPreview(
        filePath: effectivePdfPath,
        onPageChanged: widget.onPageChanged,
        onTotalPagesLoaded: widget.onTotalPagesLoaded,
      );
    }

    return Container(
      color: Colors.white,
      child: Stack(
        children: [
          if (_isUploading)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.blueAccent),
                  const SizedBox(height: 16),
                  const Text(
                    'Preparing document preview...',
                    style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  Text('Uploading file to storage...', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                ],
              ),
            )
          else if (_uploadError != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.redAccent),
                    const SizedBox(height: 12),
                    const Text(
                      'Upload or Preview Failed',
                      style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _uploadError!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[700], fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _startUploadAndInitWebView,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Retry Upload'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                    ),
                  ],
                ),
              ),
            )
          else if (_hasWebViewError)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.orangeAccent),
                      const SizedBox(height: 12),
                      const Text(
                        'Unable to Load Preview',
                        style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _webErrorDescription ?? 'Please check your internet connection.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () {
                              if (_previewUrl != null) _initWebView(_previewUrl!);
                            },
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Retry'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                          ),
                          if (!isPdf) ...[
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed: _switchViewer,
                              icon: const Icon(Icons.swap_horiz, size: 16),
                              label: Text(_useGoogleViewer ? 'Try Microsoft Viewer' : 'Try Google Viewer'),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              )
            else if (_webViewController != null)
                WebViewWidget(controller: _webViewController!),

          // Floating Viewer Switcher Chip on Top-Right for non-PDFs (PPT, DOC, XLS)
          if (!isPdf && !_isUploading && _uploadError == null && !_hasWebViewError)
            Positioned(
              top: 10,
              right: 10,
              child: Material(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(20),
                elevation: 4,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _switchViewer,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.swap_horiz_rounded, size: 14, color: Colors.blueAccent),
                        const SizedBox(width: 4),
                        Text(
                          _useGoogleViewer ? 'Switch to MS Viewer' : 'Switch to Google Viewer',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          if (_isLoadingWebView && !_isUploading && _uploadError == null && !_hasWebViewError)
            Container(
              color: Colors.white,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(value: _loadingProgress > 0 ? _loadingProgress / 100.0 : null, color: Colors.blueAccent),
                    const SizedBox(height: 12),
                    Text(
                      _loadingProgress > 0 ? 'Loading document ($_loadingProgress%)...' : 'Loading document...',
                      style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    if (!isPdf && _loadingProgress < 50) ...[
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: _switchViewer,
                        icon: const Icon(Icons.swap_horiz, size: 14),
                        label: Text(
                          _useGoogleViewer ? 'Switch to Microsoft Viewer' : 'Switch to Google Viewer',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class NativePdfPreview extends StatefulWidget {
  final String filePath;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onTotalPagesLoaded;

  const NativePdfPreview({
    super.key,
    required this.filePath,
    required this.onPageChanged,
    required this.onTotalPagesLoaded,
  });

  @override
  State<NativePdfPreview> createState() => _NativePdfPreviewState();
}

class _NativePdfPreviewState extends State<NativePdfPreview> {
  PdfControllerPinch? _pdfController;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initPdf();
  }

  Future<void> _initPdf() async {
    try {
      final file = File(widget.filePath);
      if (!await file.exists()) {
        throw Exception("Local document file not found at ${widget.filePath}");
      }
      final doc = await PdfDocument.openFile(widget.filePath);
      widget.onTotalPagesLoaded(doc.pagesCount);
      _pdfController = PdfControllerPinch(
        document: Future.value(doc),
        initialPage: 1,
      );
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error opening native PDF: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.blueAccent),
            SizedBox(height: 12),
            Text('Loading slides...', style: TextStyle(color: Colors.black87, fontSize: 13)),
          ],
        ),
      );
    }

    if (_error != null || _pdfController == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, size: 40, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(_error ?? 'Failed to open document preview', textAlign: TextAlign.center, style: const TextStyle(color: Colors.black87, fontSize: 12)),
            ],
          ),
        ),
      );
    }

    return PdfViewPinch(
      controller: _pdfController!,
      onPageChanged: (page) {
        widget.onPageChanged(page);
      },
    );
  }
}
