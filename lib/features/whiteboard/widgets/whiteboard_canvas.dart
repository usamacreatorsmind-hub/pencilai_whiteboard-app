import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../state/whiteboard_provider.dart';
import '../models/board_element.dart';
import '../models/stroke_element.dart';
import '../models/shape_element.dart';
import '../models/image_element.dart';

class WhiteboardCanvas extends StatefulWidget {
  const WhiteboardCanvas({super.key});

  @override
  State<WhiteboardCanvas> createState() => _WhiteboardCanvasState();
}

class _WhiteboardCanvasState extends State<WhiteboardCanvas> {
  final Map<int, BoardElement> _activeElements = {};
  final Map<int, Offset> _eraserPositions = {};
  final Map<int, PointerEvent> _pointers = {};
  Path? _currentLasso;
  bool _isUsingGestureEraser = false;

  // Throttling for gesture eraser to prevent lag
  DateTime _lastGestureEraseTime = DateTime.now();

  // Pulse to trigger active layer repaint without full widget rebuild
  final ValueNotifier<int> _activeLayerPulse = ValueNotifier(0);

  @override
  void dispose() {
    _activeLayerPulse.dispose();
    super.dispose();
  }

  bool _isPalm(PointerEvent event) {
    if (event.kind == PointerDeviceKind.stylus || event.kind == PointerDeviceKind.invertedStylus) {
      return false;
    }

    // TEMP DEBUG — hata dena tuning ke baad
    debugPrint(
      '[PALM-DEBUG] kind=${event.kind} '
      'size=${event.size.toStringAsFixed(3)} '
      'radiusMajor=${event.radiusMajor.toStringAsFixed(1)} '
      'radiusMinor=${event.radiusMinor.toStringAsFixed(1)} '
      'pressure=${event.pressure.toStringAsFixed(3)}',
    );

    final bool sizeIndicatesPalm = event.size > 0.12;
    final bool radiusIndicatesPalm = event.radiusMajor > 22 || event.radiusMinor > 20;
    final bool pressureIndicatesPalm = event.pressure > 0.85;

    return sizeIndicatesPalm || radiusIndicatesPalm || pressureIndicatesPalm;
  }

  bool _isDenseCluster() {
    if (_pointers.length < 2) return false;

    // No-Gap Rule: If any two pointers are closer than 50 pixels,
    // it's likely parts of the same hand touching (back hand/palm).
    final list = _pointers.values.toList();
    for (int i = 0; i < list.length; i++) {
      for (int j = i + 1; j < list.length; j++) {
        if ((list[i].localPosition - list[j].localPosition).distance < 50) {
          return true;
        }
      }
    }
    return false;
  }

  bool _isEraserMode(PointerEvent event) {
    // Stylus protection: Never auto-erase if a stylus is being used
    if (_pointers.values.any((e) => e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus)) {
      return false;
    }

    // 1. Quantity: 4 or more fingers always erases
    if (_pointers.length >= 4) return true;

    // 2. Heavy Contact: Palm or back-hand (large contact area)
    if (_pointers.values.any((e) => _isPalm(e))) return true;

    return false;
  }

  void _onPointerDown(PointerDownEvent event, WhiteboardProvider provider) {
    _pointers[event.pointer] = event;
    final localPos = event.localPosition;
    final pointerId = event.pointer;

    // 1. Check if we should be in Eraser mode
    if (_isEraserMode(event)) {
      _isUsingGestureEraser = true;
      _switchToEraserMode(provider);
      return;
    }

    if (provider.currentTool == WhiteboardTool.select) {
      if (_activeElements.isEmpty) {
        final hit = provider.hitTest(localPos);
        if (hit != null) {
          provider.selectElement(hit.id, multi: provider.selectedElementIds.contains(hit.id));
        } else {
          _currentLasso = Path()..moveTo(localPos.dx, localPos.dy);
          provider.clearSelection();
          _activeLayerPulse.value++;
        }
      }
      return;
    }

    final id = const Uuid().v4();
    if (provider.currentTool == WhiteboardTool.pen) {
      _activeElements[pointerId] = StrokeElement(
        id: id,
        position: localPos,
        points: [localPos],
        color: provider.currentColor,
        strokeWidth: provider.strokeWidth,
      );
    } else if (provider.currentTool == WhiteboardTool.shape) {
      _activeElements[pointerId] = ShapeElement(
        id: id,
        position: localPos,
        shapeType: provider.currentShapeType,
        endPoint: localPos,
        color: provider.currentColor,
        strokeWidth: provider.strokeWidth,
      );
    } else if (provider.currentTool == WhiteboardTool.eraser) {
      _eraserPositions[pointerId] = localPos;
      provider.partialErase(localPos, 25.0);
    }
    _activeLayerPulse.value++;
  }

  void _onPointerMove(PointerMoveEvent event, WhiteboardProvider provider) {
    _pointers[event.pointer] = event;
    final pointerId = event.pointer;
    final localPos = event.localPosition;

    // 1. Dynamic Check: If 4th finger added or palm detected mid-drawing
    if (_isEraserMode(event)) {
      if (!_isUsingGestureEraser) {
        // First frame of gesture-erase: switch mode, this already erases once
        _isUsingGestureEraser = true;
        _switchToEraserMode(provider);
        return;
      }

      // Already in gesture-eraser mode: keep tracking + throttled erasing
      _eraserPositions[pointerId] = localPos;

      final now = DateTime.now();
      if (now.difference(_lastGestureEraseTime).inMilliseconds > 32) {
        provider.partialErase(localPos, 50.0); // Changed from 60.0 → 50.0
        _lastGestureEraseTime = now;
      }

      _activeLayerPulse.value++; // keeps the blue indicator following at 60fps
      return;
    }

    // 2. Lasso Selection
    if (provider.currentTool == WhiteboardTool.select && _currentLasso != null) {
      _currentLasso!.lineTo(localPos.dx, localPos.dy);
      provider.updateLassoPath(_currentLasso);
      _activeLayerPulse.value++;
      return;
    }

    // 3. Normal Eraser tool (manual eraser mode, not gesture)
    if (provider.currentTool == WhiteboardTool.eraser || _eraserPositions.containsKey(pointerId)) {
      _eraserPositions[pointerId] = localPos;
      provider.partialErase(localPos, 25.0);
      _activeLayerPulse.value++;
      return;
    }

    // 4. Drawing (Pen / Shape)
    final active = _activeElements[pointerId];
    if (active == null) return;

    if (active is StrokeElement) {
      active.addPoint(localPos);

      // Input Prediction: Predict where the pen will be in ~16ms (1 frame)
      // based on current velocity (delta)
      final delta = event.delta;
      if (delta.distance > 2) {
        // Simple linear prediction: tip = current + delta * factor
        // A factor of 1.0 to 1.5 usually compensates for typical touch lag
        active.predictedTip = localPos + (delta * 1.5);
      } else {
        active.predictedTip = null;
      }
    } else if (active is ShapeElement) {
      // For shapes, copyWith is still needed but minimize other logic
      _activeElements[pointerId] = active.copyWith(endPoint: localPos)..invalidateBounds();
    }
    _activeLayerPulse.value++;
  }

  void _onPointerUp(PointerUpEvent event, WhiteboardProvider provider) {
    final pointerId = event.pointer;

    // Final flush: ensure the last position is erased even if throttle skipped it
    if (_isUsingGestureEraser && _eraserPositions.containsKey(pointerId)) {
      provider.partialErase(event.localPosition, 50.0);
    }

    _pointers.remove(pointerId);
    _eraserPositions.remove(pointerId);

    // If all fingers are lifted, reset gesture eraser state
    if (_pointers.isEmpty) {
      _isUsingGestureEraser = false;
    }

    if (provider.currentTool == WhiteboardTool.select) {
      if (_currentLasso != null) {
        _currentLasso!.close();
        provider.updateLassoPath(_currentLasso);
        _currentLasso = null;
        provider.updateLassoPath(null);
        _activeLayerPulse.value++;
      }
      return;
    }

    final element = _activeElements.remove(pointerId);
    if (element != null) {
      if (element is StrokeElement && element.points.length > 1) {
        element.predictedTip = null;
        provider.addElement(element);
      } else if (element is ShapeElement) {
        if ((element.position - element.endPoint).distance > 5) {
          provider.addElement(element);
        }
      }
    }
    _activeLayerPulse.value++;
  }

  void _switchToEraserMode(WhiteboardProvider provider) {
    // Cancel all active strokes
    _activeElements.clear();
    _lastGestureEraseTime = DateTime.now();

    // Start erasing for all active pointers
    for (var entry in _pointers.entries) {
      final id = entry.key;
      final event = entry.value;
      final pos = event.localPosition;

      _eraserPositions[id] = pos;
      provider.partialErase(pos, 50.0); // Changed from 60.0 → 50.0
    }
    _activeLayerPulse.value++;
  }

  @override
  Widget build(BuildContext context) {
    // Use Selector with boardVersion to trigger rebuilds when elements are added/modified
    return Selector<WhiteboardProvider, (int, Set<String>, Path?)>(
      selector: (context, provider) => (provider.boardVersion, provider.selectedElementIds, provider.lassoPath),
      builder: (context, data, _) {
        final provider = context.read<WhiteboardProvider>();
        final elements = provider.currentPage.elements;
        final selectedIds = data.$2;
        final lassoPath = data.$3;

        return Listener(
          onPointerDown: (e) => _onPointerDown(e, provider),
          onPointerMove: (e) => _onPointerMove(e, provider),
          onPointerUp: (e) => _onPointerUp(e, provider),
          child: Stack(
            children: [
              // 1. Static Layer
              RepaintBoundary(
                child: CustomPaint(
                  isComplex: true,
                  willChange: false,
                  painter: WhiteboardPainter(
                    elements: elements,
                    activeElements: const [],
                    lassoPath: null,
                    selectedIds: selectedIds,
                    version: data.$1,
                  ),
                  size: Size.infinite,
                  child: Stack(
                    children: [
                      ...elements.whereType<ImageElement>().map((img) {
                        final rawRect = img.getRawBounds();
                        final visualRect = Rect.fromCenter(
                          center: rawRect.center,
                          width: rawRect.width * img.scale,
                          height: rawRect.height * img.scale,
                        );
                        return Positioned(
                          left: visualRect.left,
                          top: visualRect.top,
                          width: visualRect.width,
                          height: visualRect.height,
                          child: Transform.rotate(
                            angle: img.rotation,
                            child: img.imageUrl.startsWith('http')
                                ? Image.network(
                                    img.imageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (c, e, s) => const Icon(Icons.broken_image, size: 50),
                                  )
                                : Image.file(
                                    File(img.imageUrl),
                                    fit: BoxFit.cover,
                                    errorBuilder: (c, e, s) => const Icon(Icons.broken_image, size: 50),
                                  ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              // 2. Active Layer
              ValueListenableBuilder<int>(
                valueListenable: _activeLayerPulse,
                builder: (context, _, __) {
                  return CustomPaint(
                    isComplex: false,
                    willChange: true,
                    painter: WhiteboardPainter(
                      elements: const [],
                      activeElements: _activeElements.values.toList(),
                      lassoPath: lassoPath ?? _currentLasso,
                      selectedIds: const {},
                    ),
                    size: Size.infinite,
                  );
                },
              ),
              // 3. Eraser indicators
              ValueListenableBuilder<int>(
                valueListenable: _activeLayerPulse,
                builder: (context, _, __) {
                  if (_eraserPositions.isEmpty) return const SizedBox.shrink();

                  if (_isUsingGestureEraser) {
                    // Unified single icon for hand gestures
                    Offset center = Offset.zero;
                    for (var pos in _eraserPositions.values) {
                      center += pos;
                    }
                    center /= _eraserPositions.length.toDouble();

                    const double size = 80.0;
                    return Positioned(
                      left: center.dx - size / 2,
                      top: center.dy - size / 2,
                      child: Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.4),
                          border: Border.all(color: Colors.blue.withValues(alpha: 0.6), width: 2),
                        ),
                        child: const Icon(Icons.cleaning_services, color: Colors.blue, size: 55),
                      ),
                    );
                  } else {
                    // Individual icons for standard eraser tool
                    return Stack(
                      children: _eraserPositions.entries.map((entry) {
                        final pos = entry.value;
                        const double size = 50.0;
                        return Positioned(
                          left: pos.dx - size / 2,
                          top: pos.dy - size / 2,
                          child: Container(
                            width: size,
                            height: size,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.5),
                              border: Border.all(color: Colors.blue, width: 2),
                            ),
                            child: const Icon(Icons.auto_fix_normal, color: Colors.blue, size: 30),
                          ),
                        );
                      }).toList(),
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class WhiteboardPainter extends CustomPainter {
  final List<BoardElement> elements;
  final List<BoardElement> activeElements;
  final Path? lassoPath;
  final Set<String> selectedIds;
  final int version;

  // Reusable Paint objects to avoid allocations
  final Paint _strokePaint = Paint()
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true
    ..filterQuality = FilterQuality.high
    ..style = PaintingStyle.stroke;

  final Paint _fillPaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.fill;

  WhiteboardPainter({required this.elements, required this.activeElements, this.lassoPath, required this.selectedIds, this.version = 0});

  @override
  void paint(Canvas canvas, Size size) {
    for (var element in elements) {
      _drawElement(canvas, element);
    }
    for (var element in activeElements) {
      _drawElement(canvas, element);
    }

    if (lassoPath != null) {
      canvas.drawPath(lassoPath!, _fillPaint..color = Colors.blue.withValues(alpha: 0.05));

      _strokePaint
        ..color = Colors.blue.withValues(alpha: 0.5)
        ..strokeWidth = 1.5;

      _drawDashedPath(canvas, lassoPath!, _strokePaint);
    }
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    const dashWidth = 8.0;
    const dashSpace = 6.0;

    for (var metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final Path extract = metric.extractPath(distance, distance + dashWidth);
        canvas.drawPath(extract, paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  void _drawElement(Canvas canvas, BoardElement element) {
    if (element is ImageElement) return; // Images are handled in the widget tree

    final isSelected = selectedIds.contains(element.id);
    final hasTransform = element.rotation != 0 || element.scale != 1.0;

    if (hasTransform) {
      canvas.save();
      final rawBounds = element.getRawBounds();
      final center = rawBounds.center;
      canvas.translate(center.dx, center.dy);
      canvas.rotate(element.rotation);
      canvas.scale(element.scale);
      canvas.translate(-center.dx, -center.dy);
    }

    if (element is StrokeElement) {
      _strokePaint
        ..color = isSelected ? Colors.blue : element.color
        ..strokeWidth = isSelected ? element.strokeWidth + 1 : element.strokeWidth
        ..maskFilter = isSelected ? const MaskFilter.blur(BlurStyle.outer, 3) : null;

      if (element.points.length > 1) {
        // 1. Draw confirmed smooth path (midpoint to midpoint)
        canvas.drawPath(element.path, _strokePaint);

        // 2. Draw segment from the end of the cached path to the actual pen tip
        final p1 = element.points[element.points.length - 2];
        final p2 = element.points[element.points.length - 1];
        final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);

        // The painter draws from mid to the last point
        canvas.drawLine(mid, p2, _strokePaint);

        // 3. Draw prediction segment for active drawing (Ultra-low latency)
        if (element.predictedTip != null) {
          canvas.drawLine(p2, element.predictedTip!, _strokePaint);
        }
      }
    } else if (element is ShapeElement) {
      _strokePaint
        ..color = isSelected ? Colors.blue : element.color
        ..strokeWidth = isSelected ? element.strokeWidth + 1 : element.strokeWidth
        ..maskFilter = null;

      switch (element.shapeType) {
        case ShapeType.line:
          canvas.drawLine(element.position, element.endPoint, _strokePaint);
          break;
        case ShapeType.rectangle:
          canvas.drawRect(Rect.fromPoints(element.position, element.endPoint), _strokePaint);
          break;
        case ShapeType.circle:
          final rect = Rect.fromPoints(element.position, element.endPoint);
          canvas.drawOval(rect, _strokePaint);
          break;
        case ShapeType.arrow:
          _drawArrow(canvas, element.position, element.endPoint, _strokePaint);
          break;
        case ShapeType.triangle:
          _drawTriangle(canvas, element.position, element.endPoint, _strokePaint);
          break;
        case ShapeType.star:
          _drawStar(canvas, element.position, element.endPoint, _strokePaint);
          break;
      }
    }

    if (hasTransform) {
      canvas.restore();
    }
  }

  void _drawTriangle(Canvas canvas, Offset start, Offset end, Paint paint) {
    final rect = Rect.fromPoints(start, end);
    final path = Path()
      ..moveTo(rect.centerLeft.dx + rect.width / 2, rect.top)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawStar(Canvas canvas, Offset start, Offset end, Paint paint) {
    final rect = Rect.fromPoints(start, end);
    final center = rect.center;
    final radius = rect.width / 2;
    final innerRadius = radius / 2.5;
    const points = 5;

    final path = Path();
    for (var i = 0; i < points * 2; i++) {
      final angle = (i * pi) / points - pi / 2;
      final r = i.isEven ? radius : innerRadius;
      final x = center.dx + r * cos(angle);
      final y = center.dy + r * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    canvas.drawLine(start, end, paint);
    final angle = (end - start).direction;
    const arrowSize = 15.0;
    final p1 = end - Offset.fromDirection(angle + 0.5, arrowSize);
    final p2 = end - Offset.fromDirection(angle - 0.5, arrowSize);
    final path = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = paint.color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant WhiteboardPainter oldDelegate) {
    return oldDelegate.elements != elements ||
        oldDelegate.activeElements != activeElements ||
        oldDelegate.lassoPath != lassoPath ||
        oldDelegate.selectedIds != selectedIds ||
        oldDelegate.version != version;
  }
}
