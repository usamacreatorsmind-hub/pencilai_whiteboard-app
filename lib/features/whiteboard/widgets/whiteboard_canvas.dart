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

  DateTime _lastGestureEraseTime = DateTime.now();
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
    final double major = event.radiusMajor;
    final double minor = event.radiusMinor;
    final bool veryLargeContact = major > 15 || event.size > 0.013;
    final double ratio = minor > 0 ? major / minor : 1.0;
    final bool isWideAndRound = major > 12 && ratio < 1.25;
    return veryLargeContact || isWideAndRound;
  }

  bool _isEraserMode(PointerEvent event) {
    if (_pointers.values.any((e) => e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus)) {
      return false;
    }
    if (_pointers.length >= 4) return true;
    if (_pointers.values.any((e) => _isPalm(e))) return true;
    return false;
  }

  void _onPointerDown(PointerDownEvent event, WhiteboardProvider provider) {
    _pointers[event.pointer] = event;
    final localPos = event.localPosition;
    final pointerId = event.pointer;

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

    if (_isEraserMode(event)) {
      if (!_isUsingGestureEraser) {
        _isUsingGestureEraser = true;
        _switchToEraserMode(provider);
        return;
      }
      _eraserPositions[pointerId] = localPos;
      final now = DateTime.now();
      if (now.difference(_lastGestureEraseTime).inMilliseconds > 32) {
        provider.partialErase(localPos, 50.0);
        _lastGestureEraseTime = now;
      }
      _activeLayerPulse.value++;
      return;
    }

    if (provider.currentTool == WhiteboardTool.select && _currentLasso != null) {
      _currentLasso!.lineTo(localPos.dx, localPos.dy);
      provider.updateLassoPath(_currentLasso);
      _activeLayerPulse.value++;
      return;
    }

    if (provider.currentTool == WhiteboardTool.eraser || _eraserPositions.containsKey(pointerId)) {
      _eraserPositions[pointerId] = localPos;
      provider.partialErase(localPos, 25.0);
      _activeLayerPulse.value++;
      return;
    }

    final active = _activeElements[pointerId];
    if (active == null) return;

    if (active is StrokeElement) {
      active.addPoint(localPos);

      final delta = event.delta;
      final speed = delta.distance;

      if (speed > 0.5) {
        // Conservative adaptive factor — never exceeds 1x the frame delta,
        // so prediction can never visibly overshoot or stretch.
        final adaptiveFactor = (speed / 15.0).clamp(0.2, 0.9);
        active.predictedTip = localPos + delta * adaptiveFactor;
      } else {
        active.predictedTip = null;
      }
    } else if (active is ShapeElement) {
      _activeElements[pointerId] = active.copyWith(endPoint: localPos)..invalidateBounds();
    }
    _activeLayerPulse.value++;
  }

  void _onPointerUp(PointerUpEvent event, WhiteboardProvider provider) {
    final pointerId = event.pointer;

    if (_isUsingGestureEraser && _eraserPositions.containsKey(pointerId)) {
      provider.partialErase(event.localPosition, 50.0);
    }

    _pointers.remove(pointerId);
    _eraserPositions.remove(pointerId);

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
    _activeElements.clear();
    _lastGestureEraseTime = DateTime.now();
    for (var entry in _pointers.entries) {
      final id = entry.key;
      final event = entry.value;
      final pos = event.localPosition;
      _eraserPositions[id] = pos;
      provider.partialErase(pos, 50.0);
    }
    _activeLayerPulse.value++;
  }

  @override
  Widget build(BuildContext context) {
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
              RepaintBoundary(
                child: CustomPaint(
                  isComplex: true,
                  willChange: false,
                  foregroundPainter: WhiteboardPainter(
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
              ValueListenableBuilder<int>(
                valueListenable: _activeLayerPulse,
                builder: (context, _, __) {
                  if (_eraserPositions.isEmpty) return const SizedBox.shrink();

                  if (_isUsingGestureEraser) {
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
      _drawElement(canvas, element, isActive: true);
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

  void _drawElement(Canvas canvas, BoardElement element, {bool isActive = false}) {
    if (element is ImageElement) return;

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

      if (element.points.length == 1) {
        canvas.drawCircle(element.points[0], element.strokeWidth / 2, _fillPaint..color = _strokePaint.color);
      } else if (element.points.length > 1) {
        canvas.drawPath(element.path, _strokePaint);

        final p1 = element.points[element.points.length - 2];
        final p2 = element.points[element.points.length - 1];
        final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);

        canvas.drawLine(mid, p2, _strokePaint);

        // Minimal straight prediction extension — no curve, no overshoot.
        if (isActive && element.predictedTip != null) {
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

      if (isActive || element.showDimensions) {
        _drawEnhancedDimensions(canvas, element, isActive);
      }
    }

    if (hasTransform) {
      canvas.restore();
    }
  }

  void _drawEnhancedDimensions(Canvas canvas, ShapeElement element, bool isActive) {
    final start = element.position;
    final end = element.endPoint;
    final rect = Rect.fromPoints(start, end);

    switch (element.shapeType) {
      case ShapeType.rectangle:
        _drawRectangleDimensions(canvas, rect);
        break;
      case ShapeType.circle:
        _drawCircleDimensions(canvas, rect);
        break;
      case ShapeType.triangle:
        _drawTriangleDimensions(canvas, start, end);
        break;
      case ShapeType.line:
        final dx = end.dx - start.dx;
        final dy = end.dy - start.dy;
        final length = Offset(dx, dy).distance;
        final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);

        double angle = atan2(dy, dx);
        if (angle > pi / 2 || angle < -pi / 2) angle += pi;

        _drawText(canvas, mid, length.toStringAsFixed(1), rotate: angle);
        break;
      case ShapeType.arrow:
      case ShapeType.star:
        break;
    }
  }

  void _drawRectangleDimensions(Canvas canvas, Rect rect) {
    final width = rect.width.abs();
    final height = rect.height.abs();
    final wStr = (width / 10).toStringAsFixed(1); // Scaled for display as in screenshot
    final hStr = (height / 10).toStringAsFixed(1);

    // Top
    _drawText(canvas, Offset(rect.left + rect.width / 2, rect.top - 15), wStr);
    // Bottom
    _drawText(canvas, Offset(rect.left + rect.width / 2, rect.bottom + 15), wStr);
    // Left
    _drawText(canvas, Offset(rect.left - 25, rect.top + rect.height / 2), hStr, rotate: -pi / 2);
    // Right
    _drawText(canvas, Offset(rect.right + 25, rect.top + rect.height / 2), hStr, rotate: pi / 2);
  }

  void _drawCircleDimensions(Canvas canvas, Rect rect) {
    final center = rect.center;
    final radiusX = rect.width.abs() / 2;
    final radiusY = rect.height.abs() / 2;
    final rStr = (radiusX / 10).toStringAsFixed(1);

    final dashPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Horizontal radius line
    final hPath = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(center.dx + radiusX, center.dy);
    _drawDashedPath(canvas, hPath, dashPaint);
    _drawText(canvas, Offset(center.dx + radiusX / 2, center.dy - 10), rStr);

    // Vertical radius line
    final vPath = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(center.dx, center.dy + radiusY);
    _drawDashedPath(canvas, vPath, dashPaint);
    _drawText(canvas, Offset(center.dx - 25, center.dy + radiusY / 2), rStr, rotate: -pi / 2);
  }

  void _drawTriangleDimensions(Canvas canvas, Offset start, Offset end) {
    final rect = Rect.fromPoints(start, end);
    final apex = Offset(rect.left + rect.width / 2, rect.top);
    final bottomRight = Offset(rect.right, rect.bottom);
    final bottomLeft = Offset(rect.left, rect.bottom);

    // Sides
    void drawSideLen(Offset p1, Offset p2, bool isBottom) {
      final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
      final dist = (p1 - p2).distance;
      double angle = atan2(p2.dy - p1.dy, p2.dx - p1.dx);

      // Normalize angle to keep text upright
      if (angle > pi / 2 || angle < -pi / 2) {
        angle += pi;
      }

      // Offset text slightly from the line.
      // For the bottom line, we want it below the line.
      // For sides, we want it outside.
      final normalOffset = isBottom ? 18.0 : 15.0;
      final normal = Offset(-sin(angle), cos(angle)) * normalOffset;

      _drawText(canvas, mid + normal, (dist / 10).toStringAsFixed(1), rotate: angle);
    }

    drawSideLen(bottomLeft, apex, false);
    drawSideLen(apex, bottomRight, false);
    drawSideLen(bottomRight, bottomLeft, true);
  }

  void _drawAngle(Canvas canvas, Offset vertex, Offset p1, Offset p2, double angleDeg) {
    if (angleDeg.isNaN || angleDeg == 0) return;

    final v1 = (p1 - vertex);
    final v2 = (p2 - vertex);
    double a1 = v1.direction;
    double a2 = v2.direction;

    double sweep = a2 - a1;
    while (sweep < -pi) {
      sweep += 2 * pi;
    }
    while (sweep > pi) {
      sweep -= 2 * pi;
    }

    final radius = 22.0;
    canvas.drawArc(
      Rect.fromCircle(center: vertex, radius: radius),
      a1,
      sweep,
      false,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.6)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );

    final textAngle = a1 + sweep / 2;
    final textPos = vertex + Offset.fromDirection(textAngle, radius + 15);
    _drawText(canvas, textPos, '${angleDeg.toStringAsFixed(0)}°', fontSize: 11);
  }

  void _drawText(Canvas canvas, Offset position, String text, {double rotate = 0, double fontSize = 12}) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(color: Colors.black, fontSize: fontSize, fontWeight: FontWeight.normal),
    );
    final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
    textPainter.layout();

    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(rotate);
    textPainter.paint(canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));
    canvas.restore();
  }

  void _drawMeasurementLabel(Canvas canvas, Offset anchor, String text) {
    final textSpan = TextSpan(
      text: text,
      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
    );
    final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
    textPainter.layout();

    const double paddingH = 8.0;
    const double paddingV = 4.0;
    final double boxWidth = textPainter.width + paddingH * 2;
    final double boxHeight = textPainter.height + paddingV * 2;

    final Offset boxTopLeft = Offset(anchor.dx + 12, anchor.dy - boxHeight - 12);
    final Rect labelRect = Rect.fromLTWH(boxTopLeft.dx, boxTopLeft.dy, boxWidth, boxHeight);
    final RRect roundedRect = RRect.fromRectAndRadius(labelRect, const Radius.circular(6));

    canvas.drawRRect(
      roundedRect,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.75)
        ..style = PaintingStyle.fill,
    );

    textPainter.paint(canvas, Offset(boxTopLeft.dx + paddingH, boxTopLeft.dy + paddingV));
  }

  List<double> _calculateTriangleAngles(Offset start, Offset end) {
    final rect = Rect.fromPoints(start, end);
    final apex = Offset(rect.centerLeft.dx + rect.width / 2, rect.top);
    final bottomRight = Offset(rect.right, rect.bottom);
    final bottomLeft = Offset(rect.left, rect.bottom);

    double angleBetween(Offset p1, Offset vertex, Offset p2) {
      final v1 = p1 - vertex;
      final v2 = p2 - vertex;
      final dot = v1.dx * v2.dx + v1.dy * v2.dy;
      final mag1 = v1.distance;
      final mag2 = v2.distance;
      if (mag1 == 0 || mag2 == 0) return 0.0;
      final cosTheta = (dot / (mag1 * mag2)).clamp(-1.0, 1.0);
      return acos(cosTheta) * 180 / pi;
    }

    final apexAngle = angleBetween(bottomLeft, apex, bottomRight);
    final leftAngle = angleBetween(apex, bottomLeft, bottomRight);
    final rightAngle = angleBetween(apex, bottomRight, bottomLeft);

    return [apexAngle, leftAngle, rightAngle];
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
