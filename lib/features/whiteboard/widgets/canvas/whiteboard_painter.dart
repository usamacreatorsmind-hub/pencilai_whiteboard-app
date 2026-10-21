import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../models/board_element.dart';
import '../../models/document_element.dart';
import '../../models/image_element.dart';
import '../../models/mind_map_element.dart';
import '../../models/shape_element.dart';
import '../../models/stroke_element.dart';
import '../../models/table_element.dart';
import '../../models/text_element.dart';
import '../../models/chemical_element_element.dart';
import 'shape_drawer.dart';
import 'mindmap_drawer.dart';
import 'chemical_element_drawer.dart';

/// Main custom painter responsible for rendering board elements, active drawing strokes,
/// lasso selection, and managing picture recording cache for high-performance canvas painting.
class WhiteboardPainter extends CustomPainter {
  final List<BoardElement> elements;
  final List<BoardElement> activeElements;
  final Path? lassoPath;
  final Set<String> selectedIds;
  final int version;
  final Offset panOffset;

  static ui.Picture? _cachedElementsPicture;
  static int _cachedVersion = -1;
  static int _cachedElementCount = -1;
  static Size _cachedSize = Size.zero;
  static Set<String> _cachedSelectedIds = const {};

  final Paint _strokePaint = Paint()
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true
    ..filterQuality = FilterQuality.high
    ..style = PaintingStyle.stroke;

  final Paint _fillPaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.fill;

  WhiteboardPainter({
    required this.elements,
    required this.activeElements,
    this.lassoPath,
    required this.selectedIds,
    this.version = 0,
    this.panOffset = Offset.zero,
  });

  @override
  bool shouldRepaint(covariant WhiteboardPainter oldDelegate) {
    return oldDelegate.version != version ||
        oldDelegate.elements != elements ||
        oldDelegate.activeElements != activeElements ||
        oldDelegate.lassoPath != lassoPath ||
        oldDelegate.selectedIds != selectedIds ||
        oldDelegate.panOffset != panOffset;
  }

  static void invalidateCache() {
    _cachedElementsPicture?.dispose();
    _cachedElementsPicture = null;
    _cachedVersion = -1;
    _cachedElementCount = -1;
  }

  static void appendElementToCache(BoardElement newElement, int version) {
    if (_cachedElementsPicture != null && _cachedSize != Size.zero) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      canvas.drawPicture(_cachedElementsPicture!);

      final painter = WhiteboardPainter(
        elements: const [],
        activeElements: const [],
        selectedIds: const {},
        version: version,
      );
      painter._drawElement(canvas, newElement);

      _cachedElementsPicture?.dispose();
      _cachedElementsPicture = recorder.endRecording();
      _cachedElementCount++;
      _cachedVersion = version;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(panOffset.dx, panOffset.dy);
    try {
      if (elements.isNotEmpty) {
        final bool isCacheValid =
            _cachedElementsPicture != null &&
            _cachedVersion == version &&
            _cachedElementCount == elements.length &&
            _cachedSize == size &&
            _cachedSelectedIds.length == selectedIds.length &&
            _cachedSelectedIds.containsAll(selectedIds);

        if (isCacheValid) {
          canvas.drawPicture(_cachedElementsPicture!);
        } else {
          final recorder = ui.PictureRecorder();
          final recorderCanvas = Canvas(recorder);

          for (var element in elements) {
            _drawElement(recorderCanvas, element);
          }

          _cachedElementsPicture?.dispose();
          _cachedElementsPicture = recorder.endRecording();
          _cachedVersion = version;
          _cachedElementCount = elements.length;
          _cachedSize = size;
          _cachedSelectedIds = Set.from(selectedIds);

          canvas.drawPicture(_cachedElementsPicture!);
        }
      }

      for (var element in activeElements) {
        _drawElement(canvas, element, isActive: true);
      }

      if (lassoPath != null) {
        canvas.drawPath(
          lassoPath!,
          _fillPaint..color = Colors.blue.withValues(alpha: 0.05),
        );
        _strokePaint
          ..color = Colors.blue.withValues(alpha: 0.5)
          ..strokeWidth = 1.5;
        _drawDashedPath(canvas, lassoPath!, _strokePaint);
      }
    } finally {
      canvas.restore();
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

  void _drawElement(
    Canvas canvas,
    BoardElement element, {
    bool isActive = false,
  }) {
    if (element is ImageElement || element is DocumentElement) return;

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
      if (isSelected) {
        _strokePaint
          ..maskFilter = null
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = element.color
          ..strokeWidth = element.strokeWidth;

        if (element.points.length == 1) {
          canvas.drawCircle(
            element.points[0],
            element.strokeWidth / 2,
            _fillPaint..color = element.color,
          );
        } else if (element.points.length > 1) {
          canvas.drawPath(element.path, _strokePaint);
          final p1 = element.points[element.points.length - 2];
          final p2 = element.points[element.points.length - 1];
          final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
          canvas.drawLine(mid, p2, _strokePaint);
          if (isActive && element.predictedTip != null) {
            canvas.drawLine(p2, element.predictedTip!, _strokePaint);
          }
        }
      } else {
        // Not selected - render based on penType with high fidelity
        switch (element.penType) {
          case PenType.pen:
            _strokePaint
              ..maskFilter = null
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..color = element.color
              ..strokeWidth = element.strokeWidth;

            if (element.points.length == 1) {
              canvas.drawCircle(
                element.points[0],
                element.strokeWidth / 2,
                _fillPaint..color = element.color,
              );
            } else if (element.points.length > 1) {
              canvas.drawPath(element.path, _strokePaint);
              if (isActive) {
                final p1 = element.points[element.points.length - 2];
                final p2 = element.points.last;
                final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
                canvas.drawLine(mid, p2, _strokePaint);
              }
            }
            break;

          case PenType.fountainPen:
            if (element.points.length == 1) {
              canvas.drawCircle(
                element.points[0],
                element.strokeWidth / 2,
                _fillPaint..color = element.color,
              );
            } else if (element.points.length > 1) {
              final calligraphyPaint = Paint()
                ..style = PaintingStyle.stroke
                ..strokeCap = StrokeCap.round
                ..strokeJoin = StrokeJoin.round
                ..color = element.color;

              final points = element.points;
              final n = points.length;
              final List<double> smoothedWidths = element.cachedWidths;

              if (n == 2) {
                calligraphyPaint.strokeWidth =
                    (smoothedWidths[0] + smoothedWidths[1]) / 2;
                canvas.drawLine(points[0], points[1], calligraphyPaint);
              } else {
                for (var i = 0; i < n - 1; i++) {
                  final pA = points[i];
                  final pB = points[i + 1];
                  final m1 = i == 0
                      ? pA
                      : Offset((pA.dx + pB.dx) / 2, (pA.dy + pB.dy) / 2);
                  final m2 = (i == n - 2 && !isActive)
                      ? pB
                      : Offset(
                          (pB.dx + points[min(i + 2, n - 1)].dx) / 2,
                          (pB.dy + points[min(i + 2, n - 1)].dy) / 2,
                        );

                  final segmentPath = Path()
                    ..moveTo(m1.dx, m1.dy)
                    ..quadraticBezierTo(pB.dx, pB.dy, m2.dx, m2.dy);

                  calligraphyPaint.strokeWidth =
                      (smoothedWidths[i] + smoothedWidths[i + 1]) / 2;
                  canvas.drawPath(segmentPath, calligraphyPaint);
                }
              }

              if (isActive && points.length >= 2) {
                final lastP = points.last;
                final prevP = points[points.length - 2];
                final midP = Offset(
                  (prevP.dx + lastP.dx) / 2,
                  (prevP.dy + lastP.dy) / 2,
                );
                calligraphyPaint.strokeWidth = smoothedWidths.last;
                canvas.drawLine(midP, lastP, calligraphyPaint);
              }
            }
            break;

          case PenType.brush:
            if (element.points.length == 1) {
              final brushDot = Paint()
                ..style = PaintingStyle.fill
                ..color = element.color;
              canvas.drawCircle(
                element.points[0],
                element.strokeWidth / 2,
                brushDot,
              );
            } else if (element.points.length > 1) {
              final brushPaint = Paint()
                ..style = PaintingStyle.stroke
                ..strokeCap = StrokeCap.round
                ..strokeJoin = StrokeJoin.round
                ..color = element.color;

              final totalPoints = element.points.length;
              const int taperCount = 5;

              for (var i = 0; i < totalPoints - 1; i++) {
                final p1 = element.points[i];
                final p2 = element.points[i + 1];

                double taper = 1.0;
                if (i < taperCount) {
                  taper = (i + 1) / taperCount;
                } else if (!isActive && i >= totalPoints - taperCount) {
                  taper = (totalPoints - i) / taperCount;
                }
                final dynamicWidth = element.strokeWidth * (0.5 + taper * 0.5);

                brushPaint.strokeWidth = dynamicWidth.clamp(
                  1.0,
                  element.strokeWidth * 1.15,
                );
                canvas.drawLine(p1, p2, brushPaint);
              }

              if (isActive && element.points.length >= 2) {
                final lastP = element.points.last;
                final prevP = element.points[element.points.length - 2];
                final midP = Offset(
                  (prevP.dx + lastP.dx) / 2,
                  (prevP.dy + lastP.dy) / 2,
                );
                brushPaint.strokeWidth = element.strokeWidth;
                canvas.drawLine(midP, lastP, brushPaint);
              }
            }
            break;

          case PenType.marker:
            final markerWidth = element.strokeWidth;
            _strokePaint
              ..maskFilter = null
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..strokeWidth = markerWidth
              ..color = element.color.withValues(alpha: 0.40);

            if (element.points.length == 1) {
              canvas.drawCircle(
                element.points[0],
                markerWidth / 2,
                _fillPaint..color = element.color.withValues(alpha: 0.40),
              );
            } else if (element.points.length > 1) {
              canvas.drawPath(element.path, _strokePaint);
              if (isActive) {
                final p1 = element.points[element.points.length - 2];
                final p2 = element.points.last;
                final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
                canvas.drawLine(mid, p2, _strokePaint);
              }
            }
            break;
        }
      }
    } else if (element is ShapeElement) {
      _strokePaint
        ..color = element.color
        ..strokeWidth = element.strokeWidth
        ..maskFilter = null;

      ShapeDrawer.drawShape(canvas, element, _strokePaint);

      if (isActive || element.showDimensions) {
        ShapeDrawer.drawEnhancedDimensions(
          canvas,
          element,
          isActive,
          _drawDashedPath,
        );
      }
    } else if (element is TextElement) {
      final textSpan = TextSpan(
        text: element.text,
        style: TextStyle(
          color: element.color,
          fontSize: element.fontSize,
          fontWeight: FontWeight.w600,
          fontFamily: element.fontFamily,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, element.position);
    } else if (element is TableElement) {
      final tbl = element;
      final rect = Rect.fromLTWH(
        tbl.position.dx,
        tbl.position.dy,
        tbl.size.width,
        tbl.size.height,
      );

      // Header row background tint
      if (tbl.rows > 0) {
        final headerHeight = tbl.size.height / tbl.rows;
        final headerRect = Rect.fromLTWH(
          tbl.position.dx,
          tbl.position.dy,
          tbl.size.width,
          headerHeight,
        );
        canvas.drawRect(
          headerRect,
          Paint()..color = tbl.color.withValues(alpha: 0.08),
        );
      }

      final gridPaint = Paint()
        ..color = tbl.color
        ..strokeWidth = tbl.strokeWidth
        ..style = PaintingStyle.stroke;

      // Outer table border
      canvas.drawRect(rect, gridPaint);

      // Horizontal row divider lines
      final rowH = tbl.size.height / tbl.rows;
      for (int r = 1; r < tbl.rows; r++) {
        final y = tbl.position.dy + r * rowH;
        canvas.drawLine(
          Offset(tbl.position.dx, y),
          Offset(tbl.position.dx + tbl.size.width, y),
          gridPaint,
        );
      }

      // Vertical column divider lines
      final colW = tbl.size.width / tbl.cols;
      for (int c = 1; c < tbl.cols; c++) {
        final x = tbl.position.dx + c * colW;
        canvas.drawLine(
          Offset(x, tbl.position.dy),
          Offset(x, tbl.position.dy + tbl.size.height),
          gridPaint,
        );
      }
    } else if (element is MindMapElement) {
      MindMapDrawer.drawMindMapNodeTree(
        canvas,
        element,
        element.root,
        element.position,
      );
    } else if (element is ChemicalElementElement) {
      ChemicalElementDrawer.draw(canvas, element, isSelected: isSelected);
    }

    if (hasTransform) {
      canvas.restore();
    }
  }
}
