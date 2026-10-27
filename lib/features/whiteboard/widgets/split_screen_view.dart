import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../state/whiteboard_provider.dart';
import 'canvas/canvas_grid_painter.dart';

/// Represents a single stroke inside a split column
class _SplitStroke {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;

  _SplitStroke({
    required this.points,
    required this.color,
    required this.strokeWidth,
  });
}

/// Represents the active state of an ongoing pointer drag
class _ActivePointer {
  final int columnIndex;
  final List<Offset> points;
  final Color color;
  final double strokeWidth;

  _ActivePointer({
    required this.columnIndex,
    required this.points,
    required this.color,
    required this.strokeWidth,
  });
}

/// Fullscreen Split Screen module supporting 2, 3, or 4 independent drawing columns.
class SplitScreenView extends StatefulWidget {
  final int splitCount;
  final VoidCallback onExit;

  const SplitScreenView({
    super.key,
    required this.splitCount,
    required this.onExit,
  });

  @override
  State<SplitScreenView> createState() => _SplitScreenViewState();
}

class _SplitScreenViewState extends State<SplitScreenView> {
  // 4 Color options matching user requirement & image
  static const List<Color> _presetColors = [
    Color(0xFFFFFFFF), // White
    Color(0xFF18181B), // Black
    Color(0xFFEA580C), // Orange / Red
    Color(0xFF0284C7), // Blue
  ];

  // 3 Thickness options matching user requirement & image
  static const List<({double strokeWidth, double dotSize})> _thicknessOptions =
      [
        (strokeWidth: 3.0, dotSize: 4.0), // Thin
        (strokeWidth: 6.0, dotSize: 7.0), // Medium
        (strokeWidth: 10.0, dotSize: 10.0), // Thick
      ];

  // Per-column settings
  late List<int> _selectedColorIndices;
  late List<int> _selectedThicknessIndices;
  late List<List<_SplitStroke>> _columnStrokes;

  // Multi-touch active tracking (pointerId -> _ActivePointer)
  final Map<int, _ActivePointer> _activePointers = {};

  // Active palm erasing tracking (pointerId -> Offset)
  final Map<int, Offset> _activePalms = {};

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final provider = Provider.of<WhiteboardProvider>(context, listen: false);
      _initColumns(provider.canvasBackgroundColor);
    }
  }

  @override
  void didUpdateWidget(covariant SplitScreenView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.splitCount != widget.splitCount) {
      final provider = Provider.of<WhiteboardProvider>(context, listen: false);
      _initColumns(provider.canvasBackgroundColor);
    }
  }

  void _initColumns([Color? bgColor]) {
    final count = widget.splitCount.clamp(2, 4);
    final isLight = (bgColor ?? Colors.white).computeLuminance() > 0.5;
    _selectedColorIndices = List.generate(count, (index) {
      if (isLight) {
        // On white / light backgrounds: avoid white pen (index 0)
        return index == 1 ? 3 : 1; // Col 0: Black, Col 1: Blue, etc.
      }
      return index == 1
          ? 1
          : 0; // On dark backgrounds: Col 0: White, Col 1: Black
    });
    _selectedThicknessIndices = List.filled(count, 1); // Default medium
    _columnStrokes = List.generate(count, (_) => <_SplitStroke>[]);
  }

  void _eraseAt(int columnIndex, Offset center, double radius) {
    final strokes = _columnStrokes[columnIndex];
    for (int i = strokes.length - 1; i >= 0; i--) {
      final s = strokes[i];
      bool hit = false;
      for (final pt in s.points) {
        if ((pt - center).distanceSquared <= radius * radius) {
          hit = true;
          break;
        }
      }
      if (hit) {
        strokes.removeAt(i);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WhiteboardProvider>();
    final Size screenSize = MediaQuery.sizeOf(context);
    final int count = widget.splitCount.clamp(2, 4);
    final double colWidth = screenSize.width / count;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 1. Drawing Canvas & Touch Listener
          Positioned.fill(
            child: Listener(
              onPointerDown: (e) {
                final double x = e.localPosition.dx;
                final int colIndex = (x / colWidth).clamp(0, count - 1).floor();

                // Palm and backhand detection
                final double r = max(e.radiusMajor, e.radiusMinor);
                final bool isPalmOrBackhand = (r >= 6.5 || e.size >= 0.045);
                if (isPalmOrBackhand) {
                  _activePalms[e.pointer] = e.localPosition;
                  _eraseAt(colIndex, e.localPosition, 45.0);
                  setState(() {});
                  return;
                }

                final color = _presetColors[_selectedColorIndices[colIndex]];
                final thickness =
                    _thicknessOptions[_selectedThicknessIndices[colIndex]]
                        .strokeWidth;

                _activePointers[e.pointer] = _ActivePointer(
                  columnIndex: colIndex,
                  points: [e.localPosition],
                  color: color,
                  strokeWidth: thickness,
                );
                setState(() {});
              },
              onPointerMove: (e) {
                if (_activePalms.containsKey(e.pointer)) {
                  _activePalms[e.pointer] = e.localPosition;
                  final int colIndex = (e.localPosition.dx / colWidth)
                      .clamp(0, count - 1)
                      .floor();
                  _eraseAt(colIndex, e.localPosition, 45.0);
                  setState(() {});
                  return;
                }

                final active = _activePointers[e.pointer];
                if (active != null) {
                  // Clamp to column bounds
                  final double minX = active.columnIndex * colWidth;
                  final double maxX = (active.columnIndex + 1) * colWidth;
                  final clampedX = e.localPosition.dx.clamp(minX, maxX);
                  active.points.add(Offset(clampedX, e.localPosition.dy));
                  setState(() {});
                }
              },
              onPointerUp: (e) {
                if (_activePalms.remove(e.pointer) != null) {
                  setState(() {});
                  return;
                }

                final active = _activePointers.remove(e.pointer);
                if (active != null && active.points.isNotEmpty) {
                  _columnStrokes[active.columnIndex].add(
                    _SplitStroke(
                      points: List<Offset>.from(active.points),
                      color: active.color,
                      strokeWidth: active.strokeWidth,
                    ),
                  );
                  setState(() {});
                }
              },
              onPointerCancel: (e) {
                _activePalms.remove(e.pointer);
                _activePointers.remove(e.pointer);
                setState(() {});
              },
              child: Container(
                decoration:
                    provider.canvasBackgroundImagePath != null &&
                        File(provider.canvasBackgroundImagePath!).existsSync()
                    ? BoxDecoration(
                        color: provider.canvasBackgroundColor,
                        image: DecorationImage(
                          image: FileImage(
                            File(provider.canvasBackgroundImagePath!),
                          ),
                          fit: BoxFit.cover,
                        ),
                      )
                    : BoxDecoration(color: provider.canvasBackgroundColor),
                child: CustomPaint(
                  painter: _SplitScreenCanvasPainter(
                    backgroundColor:
                        provider.canvasBackgroundImagePath != null &&
                            File(
                              provider.canvasBackgroundImagePath!,
                            ).existsSync()
                        ? Colors.transparent
                        : provider.canvasBackgroundColor,
                    gridType: provider.canvasGridType,
                    splitCount: count,
                    columnStrokes: _columnStrokes,
                    activePointers: _activePointers.values.toList(),
                    activePalms: _activePalms.values.toList(),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),

          // 2. Per-column Bottom Floating Pill Toolbars
          for (int i = 0; i < count; i++)
            Positioned(
              left: i * colWidth,
              width: colWidth,
              bottom: 18,
              child: Center(
                child: _buildColumnPillToolbar(
                  columnIndex: i,
                  availableWidth: colWidth,
                ),
              ),
            ),

          // 3. Standalone Exit / Logout Button on Left Corner
          Positioned(
            left: 20,
            bottom: 18,
            child: GestureDetector(
              onTap: widget.onExit,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    LucideIcons.arrowLeft,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Floating Pill Toolbar for a Single Column
  // ---------------------------------------------------------------------------
  Widget _buildColumnPillToolbar({
    required int columnIndex,
    required double availableWidth,
  }) {
    final int currentColorIndex = _selectedColorIndices[columnIndex];
    final int currentThicknessIndex = _selectedThicknessIndices[columnIndex];
    final bool isCompact = availableWidth < 300;

    return Container(
      height: 42,
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 8 : 12,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 4 Colors
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(_presetColors.length, (cIndex) {
              final color = _presetColors[cIndex];
              final bool isSelected = cIndex == currentColorIndex;
              final bool isWhite = color == const Color(0xFFFFFFFF);

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedColorIndices[columnIndex] = cIndex;
                  });
                },
                child: Container(
                  margin: EdgeInsets.symmetric(horizontal: isCompact ? 2.5 : 4),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: isSelected
                        ? Border.all(color: const Color(0xFF0284C7), width: 1.8)
                        : null,
                  ),
                  padding: EdgeInsets.all(isSelected ? 2.0 : 0.0),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                      border: isWhite
                          ? Border.all(
                              color: Colors.black.withValues(alpha: 0.15),
                              width: 0.8,
                            )
                          : null,
                      boxShadow: [
                        if (!isSelected)
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),

          SizedBox(width: isCompact ? 6 : 10),
          Container(width: 1, height: 18, color: const Color(0xFFE2E8F0)),
          SizedBox(width: isCompact ? 6 : 10),

          // 3 Thickness Dots
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(_thicknessOptions.length, (tIndex) {
              final opt = _thicknessOptions[tIndex];
              final bool isSelected = tIndex == currentThicknessIndex;

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedThicknessIndices[columnIndex] = tIndex;
                  });
                },
                child: Container(
                  width: 20,
                  height: 24,
                  alignment: Alignment.center,
                  child: Container(
                    width: opt.dotSize,
                    height: opt.dotSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? const Color(0xFF0284C7)
                          : const Color(0xFFCBD5E1),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Split Screen Canvas CustomPainter
// -----------------------------------------------------------------------------
class _SplitScreenCanvasPainter extends CustomPainter {
  final Color backgroundColor;
  final CanvasGridType gridType;
  final int splitCount;
  final List<List<_SplitStroke>> columnStrokes;
  final List<_ActivePointer> activePointers;
  final List<Offset> activePalms;

  const _SplitScreenCanvasPainter({
    required this.backgroundColor,
    required this.gridType,
    required this.splitCount,
    required this.columnStrokes,
    required this.activePointers,
    required this.activePalms,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double colWidth = size.width / splitCount;

    // 1. Paint canvas background & grid
    final gridPainter = CanvasGridPainter(
      backgroundColor: backgroundColor,
      gridType: gridType,
      panOffset: Offset.zero,
    );
    gridPainter.paint(canvas, size);

    // 2. Paint strokes per column (clipped to column rect)
    for (int i = 0; i < splitCount; i++) {
      final colRect = Rect.fromLTWH(i * colWidth, 0, colWidth, size.height);
      canvas.save();
      canvas.clipRect(colRect);

      // Completed strokes
      if (i < columnStrokes.length) {
        for (final stroke in columnStrokes[i]) {
          _drawStroke(canvas, stroke.points, stroke.color, stroke.strokeWidth);
        }
      }

      // Active in-progress strokes in this column
      for (final active in activePointers) {
        if (active.columnIndex == i) {
          _drawStroke(canvas, active.points, active.color, active.strokeWidth);
        }
      }

      canvas.restore();
    }

    // 3. Paint Vertical Column Dividers (dark on light background, white on dark background)
    final bool isLight = backgroundColor.computeLuminance() > 0.5;
    final dividerPaint = Paint()
      ..color = isLight
          ? const Color(0xFF0F172A).withValues(alpha: 0.35)
          : Colors.white.withValues(alpha: 0.65)
      ..strokeWidth = 1.5;

    for (int i = 1; i < splitCount; i++) {
      final double x = i * colWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), dividerPaint);
    }

    // 4. Palm eraser visual feedback
    final palmPaint = Paint()
      ..color = isLight
          ? Colors.black.withValues(alpha: 0.08)
          : Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    final palmRingPaint = Paint()
      ..color = isLight
          ? Colors.black.withValues(alpha: 0.30)
          : Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (final palm in activePalms) {
      canvas.drawCircle(palm, 45.0, palmPaint);
      canvas.drawCircle(palm, 45.0, palmRingPaint);
    }
  }

  void _drawStroke(
    Canvas canvas,
    List<Offset> points,
    Color color,
    double strokeWidth,
  ) {
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (points.length == 1) {
      canvas.drawCircle(
        points[0],
        strokeWidth / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }

    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);

    for (int i = 1; i < points.length; i++) {
      final p0 = points[i - 1];
      final p1 = points[i];
      final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
      path.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SplitScreenCanvasPainter oldDelegate) => true;
}
