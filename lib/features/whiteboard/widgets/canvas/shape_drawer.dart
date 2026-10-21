import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/shape_element.dart';

/// Helper class for rendering 2D and 3D geometric shapes and shape dimensions on a [Canvas].
class ShapeDrawer {
  ShapeDrawer._();

  /// Main entry point to draw a [ShapeElement].
  static void drawShape(Canvas canvas, ShapeElement element, Paint strokePaint) {
    switch (element.shapeType) {
      case ShapeType.line:
        canvas.drawLine(element.position, element.endPoint, strokePaint);
        break;
      case ShapeType.rectangle:
        canvas.drawRect(Rect.fromPoints(element.position, element.endPoint), strokePaint);
        break;
      case ShapeType.circle:
        final rect = Rect.fromPoints(element.position, element.endPoint);
        canvas.drawOval(rect, strokePaint);
        break;
      case ShapeType.arrow:
        drawArrow(canvas, element.position, element.endPoint, strokePaint);
        break;
      case ShapeType.triangle:
        drawTriangle(canvas, element.position, element.endPoint, strokePaint);
        break;
      case ShapeType.star:
        drawStar(canvas, element.position, element.endPoint, strokePaint);
        break;
      case ShapeType.diamond:
        drawDiamond(canvas, element.position, element.endPoint, strokePaint);
        break;
      case ShapeType.pentagon:
        drawPolygon(canvas, element.position, element.endPoint, 5, strokePaint);
        break;
      case ShapeType.hexagon:
        drawPolygon(canvas, element.position, element.endPoint, 6, strokePaint);
        break;
      case ShapeType.rightTriangle:
        drawRightTriangle(canvas, element.position, element.endPoint, strokePaint);
        break;
      case ShapeType.parallelogram:
        drawParallelogram(canvas, element.position, element.endPoint, strokePaint);
        break;
      case ShapeType.trapezoid:
        drawTrapezoid(canvas, element.position, element.endPoint, strokePaint);
        break;
      case ShapeType.heart:
        drawHeart(canvas, element.position, element.endPoint, strokePaint);
        break;
      case ShapeType.cube3d:
        drawCube3D(canvas, element.position, element.endPoint, strokePaint);
        break;
      case ShapeType.cylinder3d:
        drawCylinder3D(canvas, element.position, element.endPoint, strokePaint);
        break;
      case ShapeType.cone3d:
        drawCone3D(canvas, element.position, element.endPoint, strokePaint);
        break;
      case ShapeType.pyramid3d:
        drawPyramid3D(canvas, element.position, element.endPoint, strokePaint);
        break;
      case ShapeType.sphere3d:
        drawSphere3D(canvas, element.position, element.endPoint, strokePaint);
        break;
    }
  }

  static void drawEnhancedDimensions(
    Canvas canvas,
    ShapeElement element,
    bool isActive,
    void Function(Canvas canvas, Path path, Paint paint) drawDashedPath,
  ) {
    final start = element.position;
    final end = element.endPoint;
    final rect = Rect.fromPoints(start, end);

    switch (element.shapeType) {
      case ShapeType.rectangle:
        drawRectangleDimensions(canvas, rect);
        break;
      case ShapeType.circle:
        drawCircleDimensions(canvas, rect, drawDashedPath);
        break;
      case ShapeType.triangle:
        drawTriangleDimensions(canvas, start, end);
        break;
      case ShapeType.line:
        final dx = end.dx - start.dx;
        final dy = end.dy - start.dy;
        final length = Offset(dx, dy).distance;
        final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);

        double angle = atan2(dy, dx);
        if (angle > pi / 2 || angle < -pi / 2) angle += pi;

        drawText(canvas, mid, length.toStringAsFixed(1), rotate: angle);
        break;
      case ShapeType.arrow:
      case ShapeType.star:
      default:
        break;
    }
  }

  static void drawRectangleDimensions(Canvas canvas, Rect rect) {
    final width = rect.width.abs();
    final height = rect.height.abs();
    final wStr = (width / 10).toStringAsFixed(1);
    final hStr = (height / 10).toStringAsFixed(1);

    drawText(canvas, Offset(rect.left + rect.width / 2, rect.top - 15), wStr);
    drawText(canvas, Offset(rect.left + rect.width / 2, rect.bottom + 15), wStr);
    drawText(canvas, Offset(rect.left - 25, rect.top + rect.height / 2), hStr, rotate: -pi / 2);
    drawText(canvas, Offset(rect.right + 25, rect.top + rect.height / 2), hStr, rotate: pi / 2);
  }

  static void drawCircleDimensions(
    Canvas canvas,
    Rect rect,
    void Function(Canvas canvas, Path path, Paint paint) drawDashedPath,
  ) {
    final center = rect.center;
    final radiusX = rect.width.abs() / 2;
    final radiusY = rect.height.abs() / 2;
    final rStr = (radiusX / 10).toStringAsFixed(1);

    final dashPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final hPath = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(center.dx + radiusX, center.dy);
    drawDashedPath(canvas, hPath, dashPaint);
    drawText(canvas, Offset(center.dx + radiusX / 2, center.dy - 10), rStr);

    final vPath = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(center.dx, center.dy + radiusY);
    drawDashedPath(canvas, vPath, dashPaint);
    drawText(canvas, Offset(center.dx - 25, center.dy + radiusY / 2), rStr, rotate: -pi / 2);
  }

  static void drawTriangleDimensions(Canvas canvas, Offset start, Offset end) {
    final rect = Rect.fromPoints(start, end);
    final apex = Offset(rect.left + rect.width / 2, rect.top);
    final bottomRight = Offset(rect.right, rect.bottom);
    final bottomLeft = Offset(rect.left, rect.bottom);

    void drawSideLen(Offset p1, Offset p2, bool isBottom) {
      final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
      final dist = (p1 - p2).distance;
      double angle = atan2(p2.dy - p1.dy, p2.dx - p1.dx);

      if (angle > pi / 2 || angle < -pi / 2) {
        angle += pi;
      }

      final normalOffset = isBottom ? 18.0 : 15.0;
      final normal = Offset(-sin(angle), cos(angle)) * normalOffset;

      drawText(canvas, mid + normal, (dist / 10).toStringAsFixed(1), rotate: angle);
    }

    drawSideLen(bottomLeft, apex, false);
    drawSideLen(apex, bottomRight, false);
    drawSideLen(bottomRight, bottomLeft, true);
  }

  static void drawText(Canvas canvas, Offset position, String text, {double rotate = 0, double fontSize = 12}) {
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

  static void drawArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(end.dx, end.dy);
    canvas.drawPath(path, paint);
  }

  static void drawTriangle(Canvas canvas, Offset start, Offset end, Paint paint) {
    final rect = Rect.fromPoints(start, end);
    final path = Path()
      ..moveTo(rect.centerLeft.dx + rect.width / 2, rect.top)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..close();
    canvas.drawPath(path, paint);
  }

  static void drawStar(Canvas canvas, Offset start, Offset end, Paint paint) {
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

  static void drawDiamond(Canvas canvas, Offset start, Offset end, Paint paint) {
    final rect = Rect.fromPoints(start, end);
    final path = Path()
      ..moveTo(rect.center.dx, rect.top)
      ..lineTo(rect.right, rect.center.dy)
      ..lineTo(rect.center.dx, rect.bottom)
      ..lineTo(rect.left, rect.center.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  static void drawPolygon(Canvas canvas, Offset start, Offset end, int sides, Paint paint) {
    final rect = Rect.fromPoints(start, end);
    final center = rect.center;
    final radius = min(rect.width.abs(), rect.height.abs()) / 2;
    final path = Path();
    for (var i = 0; i < sides; i++) {
      final angle = (i * 2 * pi) / sides - pi / 2;
      final x = center.dx + radius * cos(angle);
      final y = center.dy + radius * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  static void drawRightTriangle(Canvas canvas, Offset start, Offset end, Paint paint) {
    final rect = Rect.fromPoints(start, end);
    final path = Path()
      ..moveTo(rect.left, rect.top)
      ..lineTo(rect.left, rect.bottom)
      ..lineTo(rect.right, rect.bottom)
      ..close();
    canvas.drawPath(path, paint);
  }

  static void drawParallelogram(Canvas canvas, Offset start, Offset end, Paint paint) {
    final rect = Rect.fromPoints(start, end);
    final offset = rect.width * 0.2;
    final path = Path()
      ..moveTo(rect.left + offset, rect.top)
      ..lineTo(rect.right, rect.top)
      ..lineTo(rect.right - offset, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..close();
    canvas.drawPath(path, paint);
  }

  static void drawTrapezoid(Canvas canvas, Offset start, Offset end, Paint paint) {
    final rect = Rect.fromPoints(start, end);
    final offset = rect.width * 0.25;
    final path = Path()
      ..moveTo(rect.left + offset, rect.top)
      ..lineTo(rect.right - offset, rect.top)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..close();
    canvas.drawPath(path, paint);
  }

  static void drawHeart(Canvas canvas, Offset start, Offset end, Paint paint) {
    final rect = Rect.fromPoints(start, end);
    final width = rect.width;
    final height = rect.height;
    final path = Path()
      ..moveTo(rect.center.dx, rect.top + height * 0.3)
      ..cubicTo(rect.center.dx + width * 0.5, rect.top - height * 0.1, rect.right, rect.top + height * 0.4, rect.center.dx, rect.bottom)
      ..cubicTo(
        rect.left,
        rect.top + height * 0.4,
        rect.center.dx - width * 0.5,
        rect.top - height * 0.1,
        rect.center.dx,
        rect.top + height * 0.3,
      );
    canvas.drawPath(path, paint);
  }

  static void drawCube3D(Canvas canvas, Offset start, Offset end, Paint paint) {
    final rect = Rect.fromPoints(start, end);
    final w = rect.width;
    final h = rect.height;
    final dx = w * 0.3;
    final dy = h * 0.3;

    final front = Rect.fromLTWH(rect.left, rect.top + dy, w - dx, h - dy);
    final back = Rect.fromLTWH(rect.left + dx, rect.top, w - dx, h - dy);

    canvas.drawRect(front, paint);
    canvas.drawRect(back, paint);

    canvas.drawLine(front.topLeft, back.topLeft, paint);
    canvas.drawLine(front.topRight, back.topRight, paint);
    canvas.drawLine(front.bottomLeft, back.bottomLeft, paint);
    canvas.drawLine(front.bottomRight, back.bottomRight, paint);
  }

  static void drawCylinder3D(Canvas canvas, Offset start, Offset end, Paint paint) {
    final rect = Rect.fromPoints(start, end);
    final cx = rect.center.dx;
    final topY = rect.top + rect.height * 0.15;
    final botY = rect.bottom - rect.height * 0.15;
    final rx = rect.width / 2;
    final ry = rect.height * 0.15;

    canvas.drawOval(Rect.fromCenter(center: Offset(cx, topY), width: rx * 2, height: ry * 2), paint);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, botY), width: rx * 2, height: ry * 2), paint);

    canvas.drawLine(Offset(cx - rx, topY), Offset(cx - rx, botY), paint);
    canvas.drawLine(Offset(cx + rx, topY), Offset(cx + rx, botY), paint);
  }

  static void drawCone3D(Canvas canvas, Offset start, Offset end, Paint paint) {
    final rect = Rect.fromPoints(start, end);
    final cx = rect.center.dx;
    final apex = Offset(cx, rect.top);
    final botY = rect.bottom;
    final rx = rect.width / 2;
    final ry = rect.height * 0.15;

    canvas.drawOval(Rect.fromCenter(center: Offset(cx, botY), width: rx * 2, height: ry * 2), paint);
    canvas.drawLine(apex, Offset(cx - rx, botY), paint);
    canvas.drawLine(apex, Offset(cx + rx, botY), paint);
  }

  static void drawPyramid3D(Canvas canvas, Offset start, Offset end, Paint paint) {
    final rect = Rect.fromPoints(start, end);
    final apex = Offset(rect.center.dx, rect.top);
    final tl = rect.topLeft + Offset(0, rect.height * 0.3);
    final tr = rect.topRight + Offset(0, rect.height * 0.3);
    final bl = rect.bottomLeft;
    final br = rect.bottomRight;

    final path = Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(bl.dx, bl.dy)
      ..close();
    canvas.drawPath(path, paint);

    canvas.drawLine(tl, apex, paint);
    canvas.drawLine(tr, apex, paint);
    canvas.drawLine(bl, apex, paint);
    canvas.drawLine(br, apex, paint);
  }

  static void drawSphere3D(Canvas canvas, Offset start, Offset end, Paint paint) {
    final rect = Rect.fromPoints(start, end);
    canvas.drawOval(rect, paint);
    final center = rect.center;
    final rx = rect.width / 2;
    final ry = rect.height / 2;

    canvas.drawArc(Rect.fromCenter(center: center, width: rx, height: ry * 2), 0, pi, false, paint);
    canvas.drawArc(Rect.fromCenter(center: center, width: rx * 2, height: ry), pi / 2, pi, false, paint);
  }
}
