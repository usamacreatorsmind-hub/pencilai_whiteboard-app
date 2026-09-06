import 'dart:io';
import 'dart:math';
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
  Path? _currentLasso;

  void _onPointerDown(PointerDownEvent event, WhiteboardProvider provider) {
    final localPos = event.localPosition;
    final pointerId = event.pointer;

    if (provider.currentTool == WhiteboardTool.select) {
      if (_activeElements.isEmpty) {
        final hit = provider.hitTest(localPos);
        if (hit != null) {
          provider.selectElement(hit.id, multi: provider.selectedElementIds.contains(hit.id));
        } else {
          setState(() {
            _currentLasso = Path()..moveTo(localPos.dx, localPos.dy);
          });
          provider.clearSelection();
        }
      }
      return;
    }

    setState(() {
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
    });
  }

  void _onPointerMove(PointerMoveEvent event, WhiteboardProvider provider) {
    final localPos = event.localPosition;
    final pointerId = event.pointer;

    if (provider.currentTool == WhiteboardTool.select && _currentLasso != null) {
      setState(() {
        _currentLasso!.lineTo(localPos.dx, localPos.dy);
      });
      provider.updateLassoPath(_currentLasso);
      return;
    }

    if (provider.currentTool == WhiteboardTool.eraser) {
      setState(() {
        _eraserPositions[pointerId] = localPos;
      });
      provider.partialErase(localPos, 25.0);
      return;
    }

    final active = _activeElements[pointerId];
    if (active == null) return;

    setState(() {
      if (active is StrokeElement) {
        active.points.add(localPos);
      } else if (active is ShapeElement) {
        _activeElements[pointerId] = active.copyWith(endPoint: localPos);
      }
    });
  }

  void _onPointerUp(PointerUpEvent event, WhiteboardProvider provider) {
    final pointerId = event.pointer;

    if (provider.currentTool == WhiteboardTool.select) {
      if (_currentLasso != null) {
        _currentLasso!.close();
        provider.updateLassoPath(_currentLasso);
        setState(() {
          _currentLasso = null;
        });
        provider.updateLassoPath(null);
      }
      return;
    }

    setState(() {
      if (provider.currentTool == WhiteboardTool.eraser) {
        _eraserPositions.remove(pointerId);
      }

      final element = _activeElements.remove(pointerId);
      if (element != null) {
        // Only add if it's a significant drawing
        if (element is StrokeElement && element.points.length > 1) {
          provider.addElement(element);
        } else if (element is ShapeElement) {
          if ((element.position - element.endPoint).distance > 5) {
            provider.addElement(element);
          }
        } else if (element is! StrokeElement && element is! ShapeElement) {
          provider.addElement(element);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<WhiteboardProvider>(context);

    return Listener(
      onPointerDown: (e) => _onPointerDown(e, provider),
      onPointerMove: (e) => _onPointerMove(e, provider),
      onPointerUp: (e) => _onPointerUp(e, provider),
      child: Stack(
        children: [
          // 1. Images
          ...provider.currentPage.elements.whereType<ImageElement>().map((img) {
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
                    ? Image.network(img.imageUrl, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.broken_image, size: 50))
                    : Image.file(
                        File(img.imageUrl),
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => const Icon(Icons.broken_image, size: 50),
                      ),
              ),
            );
          }),

          // 2. Custom Painter
          CustomPaint(
            painter: WhiteboardPainter(
              elements: provider.currentPage.elements.where((e) => e is! ImageElement).toList(),
              activeElements: _activeElements.values.toList(),
              lassoPath: provider.lassoPath,
              selectedIds: provider.selectedElementIds,
            ),
            size: Size.infinite,
          ),

          // 3. Eraser indicators
          ..._eraserPositions.values.map(
            (pos) => Positioned(
              left: pos.dx - 25,
              top: pos.dy - 25,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.5),
                  border: Border.all(color: Colors.blue, width: 2),
                ),
                child: const Icon(Icons.auto_fix_normal, color: Colors.blue, size: 30),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WhiteboardPainter extends CustomPainter {
  final List<BoardElement> elements;
  final List<BoardElement> activeElements;
  final Path? lassoPath;
  final Set<String> selectedIds;

  WhiteboardPainter({required this.elements, required this.activeElements, this.lassoPath, required this.selectedIds});

  @override
  void paint(Canvas canvas, Size size) {
    for (var element in elements) {
      _drawElement(canvas, element);
    }
    for (var element in activeElements) {
      _drawElement(canvas, element);
    }

    if (lassoPath != null) {
      final fillPaint = Paint()
        ..color = Colors.blue.withOpacity(0.05)
        ..style = PaintingStyle.fill;
      canvas.drawPath(lassoPath!, fillPaint);

      final strokePaint = Paint()
        ..color = Colors.blue.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;

      // Draw dashed lasso path for premium feel
      _drawDashedPath(canvas, lassoPath!, strokePaint);
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
    canvas.save();

    final rawBounds = element.getRawBounds();
    final center = rawBounds.center;

    // Apply transformations around the center
    canvas.translate(center.dx, center.dy);
    canvas.rotate(element.rotation);
    canvas.scale(element.scale);
    canvas.translate(-center.dx, -center.dy);

    final isSelected = selectedIds.contains(element.id);

    if (element is StrokeElement) {
      final paint = Paint()
        ..color = isSelected ? Colors.blue : element.color
        ..strokeWidth = isSelected ? element.strokeWidth + 1 : element.strokeWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      if (isSelected) {
        canvas.drawPath(_createPath(element.points), paint..maskFilter = const MaskFilter.blur(BlurStyle.outer, 3));
        paint.maskFilter = null;
      }

      if (element.points.length > 1) {
        final path = _createPath(element.points);
        canvas.drawPath(path, paint);
      }
    } else if (element is ShapeElement) {
      final paint = Paint()
        ..color = isSelected ? Colors.blue : element.color
        ..strokeWidth = isSelected ? element.strokeWidth + 1 : element.strokeWidth
        ..style = PaintingStyle.stroke;

      switch (element.shapeType) {
        case ShapeType.line:
          canvas.drawLine(element.position, element.endPoint, paint);
          break;
        case ShapeType.rectangle:
          canvas.drawRect(Rect.fromPoints(element.position, element.endPoint), paint);
          break;
        case ShapeType.circle:
          final rect = Rect.fromPoints(element.position, element.endPoint);
          canvas.drawOval(rect, paint);
          break;
        case ShapeType.arrow:
          _drawArrow(canvas, element.position, element.endPoint, paint);
          break;
        case ShapeType.triangle:
          _drawTriangle(canvas, element.position, element.endPoint, paint);
          break;
        case ShapeType.star:
          _drawStar(canvas, element.position, element.endPoint, paint);
          break;
      }
    }
    canvas.restore();
  }

  Path _createPath(List<Offset> points) {
    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    return path;
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
