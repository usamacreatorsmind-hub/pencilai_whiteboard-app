import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Native Android Drag & Drop listener wrapper widget.
/// Captures cross-app drop events (images, content URIs, URLs) seamlessly via Method/EventChannel.
class NativeDropTarget extends StatefulWidget {
  final Widget child;
  final VoidCallback? onDragEntered;
  final ValueChanged<Offset>? onDragUpdated;
  final VoidCallback? onDragExited;
  final Function(Uint8List bytes, String mime, Offset localPosition)? onDropImage;
  final Function(String text, String? html, Offset localPosition)? onDropText;
  final ValueChanged<String>? onError;

  const NativeDropTarget({
    super.key,
    required this.child,
    this.onDragEntered,
    this.onDragUpdated,
    this.onDragExited,
    this.onDropImage,
    this.onDropText,
    this.onError,
  });

  @override
  State<NativeDropTarget> createState() => _NativeDropTargetState();
}

class _NativeDropTargetState extends State<NativeDropTarget> {
  static const EventChannel _dropChannel = EventChannel('com.pencilai.whiteboard/drop');
  StreamSubscription? _dropSubscription;

  int _lastDropTime = 0;
  int _lastBytesHash = 0;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _dropSubscription = _dropChannel.receiveBroadcastStream().listen(
        _handleNativeEvent,
        onError: (err) {
          debugPrint('Native drop channel error: $err');
          widget.onError?.call(err.toString());
        },
      );
    }
  }

  @override
  void dispose() {
    _dropSubscription?.cancel();
    super.dispose();
  }

  Offset _getLocalOffset(double rawX, double rawY) {
    if (!mounted) return Offset(rawX, rawY);
    final double dpr = MediaQuery.of(context).devicePixelRatio;
    final Offset logicalGlobal = Offset(rawX / dpr, rawY / dpr);
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      return renderBox.globalToLocal(logicalGlobal);
    }
    return logicalGlobal;
  }

  bool _isDuplicate(Uint8List bytes) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final hash = Object.hashAll(bytes.take(100));
    if (now - _lastDropTime < 500 && hash == _lastBytesHash) {
      return true;
    }
    _lastDropTime = now;
    _lastBytesHash = hash;
    return false;
  }

  Future<void> _handleNativeEvent(dynamic event) async {
    if (event is! Map) return;

    final String type = event['type']?.toString() ?? '';
    final double rawX = (event['x'] as num?)?.toDouble() ?? 0.0;
    final double rawY = (event['y'] as num?)?.toDouble() ?? 0.0;
    final Offset localPos = _getLocalOffset(rawX, rawY);

    switch (type) {
      case 'enter':
        widget.onDragEntered?.call();
        break;
      case 'update':
        widget.onDragUpdated?.call(localPos);
        break;
      case 'exit':
        widget.onDragExited?.call();
        break;
      case 'drop':
        widget.onDragExited?.call();
        final String kind = event['kind']?.toString() ?? '';
        if (kind == 'image') {
          final dynamic rawBytes = event['bytes'];
          if (rawBytes is Uint8List && rawBytes.isNotEmpty) {
            if (_isDuplicate(rawBytes)) return;
            final String mime = event['mime']?.toString() ?? 'image/png';
            widget.onDropImage?.call(rawBytes, mime, localPos);
          }
        } else if (kind == 'text') {
          final String? text = event['text']?.toString();
          final String? html = event['html']?.toString();
          await _processTextOrHtmlDrop(text, html, localPos);
        }
        break;
    }
  }

  Future<void> _processTextOrHtmlDrop(
    String? text,
    String? html,
    Offset localPos,
  ) async {
    // 1. Check HTML for <img src="..."> tag
    if (html != null && html.isNotEmpty) {
      final imgRegex = RegExp(r'''<img [^>]*src=["']([^"']+)["']''', caseSensitive: false);
      final match = imgRegex.firstMatch(html);
      if (match != null) {
        final src = match.group(1);
        if (src != null && src.isNotEmpty) {
          if (await _tryProcessImageSrc(src, localPos)) {
            return;
          }
        }
      }
    }

    // 2. Check plain text for direct image URL
    if (text != null && text.isNotEmpty) {
      final urlMatch = RegExp(r'https?://[^\s"<]+', caseSensitive: false).firstMatch(text);
      final url = urlMatch?.group(0) ?? text.trim();
      if (url.startsWith('http://') || url.startsWith('https://')) {
        if (await _tryProcessImageSrc(url, localPos)) {
          return;
        }
      }
    }

    // 3. Fallback to drop text
    if (text != null && text.isNotEmpty) {
      widget.onDropText?.call(text, html, localPos);
    }
  }

  Future<bool> _tryProcessImageSrc(String src, Offset localPos) async {
    // Handle data:image/png;base64,... URIs
    if (src.startsWith('data:image/')) {
      try {
        final commaIdx = src.indexOf(',');
        if (commaIdx != -1) {
          final base64Data = src.substring(commaIdx + 1);
          final bytes = base64Decode(base64Data);
          if (bytes.isNotEmpty && !_isDuplicate(bytes)) {
            widget.onDropImage?.call(bytes, 'image/png', localPos);
            return true;
          }
        }
      } catch (e) {
        debugPrint('Base64 image decode error: $e');
      }
    }

    // Handle http/https URLs
    if (src.startsWith('http://') || src.startsWith('https://')) {
      try {
        final response = await http.get(
          Uri.parse(src),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          },
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200 &&
            response.bodyBytes.isNotEmpty &&
            response.bodyBytes.length <= 25 * 1024 * 1024) {
          final contentType = response.headers['content-type'] ?? 'image/png';
          if (contentType.startsWith('image/') || contentType.contains('octet-stream')) {
            if (!_isDuplicate(response.bodyBytes)) {
              widget.onDropImage?.call(response.bodyBytes, contentType, localPos);
              return true;
            }
          }
        }
      } catch (e) {
        debugPrint('Failed to download image URL ($src): $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not download dropped image from web link'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
