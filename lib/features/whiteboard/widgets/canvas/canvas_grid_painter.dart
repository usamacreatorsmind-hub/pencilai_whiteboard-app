import 'dart:math';
import 'package:flutter/material.dart';

enum CanvasGridType {
  none,
  square,
  lined,
  dots,
  mixGrid,
  denseGrid,
  ruledNote,
  crossGrid,
  columns,
  isometric,
}


extension CanvasGridTypeExtension on CanvasGridType {
  String get displayName {
    switch (this) {
      case CanvasGridType.none:
        return 'None';
      case CanvasGridType.square:
        return 'Square Grid';
      case CanvasGridType.lined:
        return 'Lined';
      case CanvasGridType.dots:
        return 'Dot Grid';
      case CanvasGridType.mixGrid:
        return 'Mix Grid';
      case CanvasGridType.denseGrid:
        return 'Dense Grid';
      case CanvasGridType.ruledNote:
        return 'Ruled Note';
      case CanvasGridType.crossGrid:
        return 'Cross Grid';
      case CanvasGridType.columns:
        return 'Columns';
      case CanvasGridType.isometric:
        return 'Isometric';
    }
  }
}

/// Custom painter that draws background color and infinite canvas grid patterns,
/// synchronized with viewport pan offset.
class CanvasGridPainter extends CustomPainter {
  final Color backgroundColor;
  final CanvasGridType gridType;
  final Offset panOffset;

  const CanvasGridPainter({
    required this.backgroundColor,
    required this.gridType,
    this.panOffset = Offset.zero,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw solid canvas background (skip if transparent / custom image background)
    if (backgroundColor != Colors.transparent) {
      final bgPaint = Paint()..color = backgroundColor;
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);
    }

    if (gridType == CanvasGridType.none) return;

    final isDark = backgroundColor != Colors.transparent &&
        backgroundColor.computeLuminance() < 0.5;
    final baseColor = isDark ? Colors.white : const Color(0xFF1E293B);

    switch (gridType) {
      case CanvasGridType.none:
        break;

      case CanvasGridType.square:
        _drawSquareGrid(canvas, size, baseColor, isDark, step: 40.0);
        break;

      case CanvasGridType.denseGrid:
        _drawSquareGrid(canvas, size, baseColor, isDark, step: 22.0);
        break;

      case CanvasGridType.lined:
        _drawLined(canvas, size, baseColor, isDark, step: 38.0);
        break;

      case CanvasGridType.dots:
        _drawDots(canvas, size, baseColor, isDark, step: 36.0);
        break;

      case CanvasGridType.mixGrid:
        _drawMixGrid(canvas, size, baseColor, isDark);
        break;

      case CanvasGridType.ruledNote:
        _drawRuledNote(canvas, size, baseColor, isDark);
        break;

      case CanvasGridType.crossGrid:
        _drawCrossGrid(canvas, size, baseColor, isDark, step: 48.0);
        break;

      case CanvasGridType.columns:
        _drawColumns(canvas, size, baseColor, isDark, step: 44.0);
        break;

      case CanvasGridType.isometric:
        _drawIsometric(canvas, size, baseColor, isDark, step: 40.0);
        break;
    }
  }

  void _drawSquareGrid(
    Canvas canvas,
    Size size,
    Color baseColor,
    bool isDark, {
    required double step,
  }) {
    final linePaint = Paint()
      ..color = baseColor.withValues(alpha: isDark ? 0.12 : 0.08)
      ..strokeWidth = 1.0;

    final double startX = (panOffset.dx % step) - step;
    final double startY = (panOffset.dy % step) - step;

    for (double x = startX; x <= size.width + step; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    for (double y = startY; y <= size.height + step; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
  }

  void _drawLined(
    Canvas canvas,
    Size size,
    Color baseColor,
    bool isDark, {
    required double step,
  }) {
    final linePaint = Paint()
      ..color = baseColor.withValues(alpha: isDark ? 0.14 : 0.10)
      ..strokeWidth = 1.0;

    final double startY = (panOffset.dy % step) - step;
    for (double y = startY; y <= size.height + step; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
  }

  void _drawDots(
    Canvas canvas,
    Size size,
    Color baseColor,
    bool isDark, {
    required double step,
  }) {
    final dotPaint = Paint()
      ..color = baseColor.withValues(alpha: isDark ? 0.28 : 0.22)
      ..style = PaintingStyle.fill;

    final double startX = (panOffset.dx % step) - step;
    final double startY = (panOffset.dy % step) - step;

    for (double x = startX; x <= size.width + step; x += step) {
      for (double y = startY; y <= size.height + step; y += step) {
        canvas.drawCircle(Offset(x, y), 1.5, dotPaint);
      }
    }
  }

  void _drawMixGrid(
    Canvas canvas,
    Size size,
    Color baseColor,
    bool isDark,
  ) {
    const double minorStep = 24.0;
    const double majorStep = 96.0;

    final minorPaint = Paint()
      ..color = baseColor.withValues(alpha: isDark ? 0.07 : 0.05)
      ..strokeWidth = 0.8;

    final majorColor = isDark ? const Color(0xFF38BDF8) : const Color(0xFF2563EB);
    final majorPaint = Paint()
      ..color = majorColor.withValues(alpha: isDark ? 0.28 : 0.18)
      ..strokeWidth = 1.2;

    // 1. Minor lines
    final double minorStartX = (panOffset.dx % minorStep) - minorStep;
    final double minorStartY = (panOffset.dy % minorStep) - minorStep;

    for (double x = minorStartX; x <= size.width + minorStep; x += minorStep) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), minorPaint);
    }
    for (double y = minorStartY; y <= size.height + minorStep; y += minorStep) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), minorPaint);
    }

    // 2. Major accent lines
    final double majorStartX = (panOffset.dx % majorStep) - majorStep;
    final double majorStartY = (panOffset.dy % majorStep) - majorStep;

    for (double x = majorStartX; x <= size.width + majorStep; x += majorStep) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), majorPaint);
    }
    for (double y = majorStartY; y <= size.height + majorStep; y += majorStep) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), majorPaint);
    }
  }

  void _drawRuledNote(
    Canvas canvas,
    Size size,
    Color baseColor,
    bool isDark,
  ) {
    const double step = 36.0;
    final linePaint = Paint()
      ..color = baseColor.withValues(alpha: isDark ? 0.15 : 0.10)
      ..strokeWidth = 1.0;

    final double startY = (panOffset.dy % step) - step;
    for (double y = startY; y <= size.height + step; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    // Vertical margin line (classic notebook red/coral line)
    final double marginX = 72.0 + panOffset.dx;
    if (marginX >= 0 && marginX <= size.width) {
      final marginPaint = Paint()
        ..color = const Color(0xFFEF4444).withValues(alpha: isDark ? 0.40 : 0.30)
        ..strokeWidth = 1.4;
      canvas.drawLine(Offset(marginX, 0), Offset(marginX, size.height), marginPaint);
    }
  }

  void _drawCrossGrid(
    Canvas canvas,
    Size size,
    Color baseColor,
    bool isDark, {
    required double step,
  }) {
    final crossPaint = Paint()
      ..color = baseColor.withValues(alpha: isDark ? 0.25 : 0.18)
      ..strokeWidth = 1.0;

    final double startX = (panOffset.dx % step) - step;
    final double startY = (panOffset.dy % step) - step;
    const double arm = 4.0;

    for (double x = startX; x <= size.width + step; x += step) {
      for (double y = startY; y <= size.height + step; y += step) {
        canvas.drawLine(Offset(x - arm, y), Offset(x + arm, y), crossPaint);
        canvas.drawLine(Offset(x, y - arm), Offset(x, y + arm), crossPaint);
      }
    }
  }

  void _drawColumns(
    Canvas canvas,
    Size size,
    Color baseColor,
    bool isDark, {
    required double step,
  }) {
    final linePaint = Paint()
      ..color = baseColor.withValues(alpha: isDark ? 0.14 : 0.10)
      ..strokeWidth = 1.0;

    final double startX = (panOffset.dx % step) - step;
    for (double x = startX; x <= size.width + step; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
  }

  void _drawIsometric(
    Canvas canvas,
    Size size,
    Color baseColor,
    bool isDark, {
    required double step,
  }) {
    final linePaint = Paint()
      ..color = baseColor.withValues(alpha: isDark ? 0.10 : 0.07)
      ..strokeWidth = 0.8;

    final double h = step * sqrt(3) / 2;
    final double startY = (panOffset.dy % h) - h * 2;

    // Horizontal lines
    for (double y = startY; y <= size.height + h * 2; y += h) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    // Diagonal lines (+60 deg and -60 deg)
    final double diagStep = step;
    final double startX = (panOffset.dx % diagStep) - size.height;
    for (double x = startX; x <= size.width + size.height; x += diagStep) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height * 0.577, size.height), linePaint);
      canvas.drawLine(Offset(x, 0), Offset(x - size.height * 0.577, size.height), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CanvasGridPainter oldDelegate) {
    return oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.gridType != gridType ||
        oldDelegate.panOffset != panOffset;
  }
}
