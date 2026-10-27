import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/stroke_element.dart';
import '../services/smart_pen_service.dart';
import '../state/whiteboard_provider.dart';

class SmartPenSuggestionWidget extends StatefulWidget {
  const SmartPenSuggestionWidget({super.key});

  @override
  State<SmartPenSuggestionWidget> createState() =>
      _SmartPenSuggestionWidgetState();
}

class _SmartPenSuggestionWidgetState extends State<SmartPenSuggestionWidget> {
  bool _isReplacing = false;

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<WhiteboardProvider>(context);
    final stroke = provider.activeSmartPenStroke;
    if (stroke == null) return const SizedBox.shrink();
    // Calculate stroke bounds in canvas viewport coordinates
    final rawBounds = stroke.getRawBounds();
    final rect = rawBounds.shift(provider.canvasPanOffset);

    // Padding around doodle for the dashed bounding box
    const double padding = 8.0;
    final boxLeft = rect.left - padding;
    final boxTop = rect.top - padding;
    final boxWidth = rect.width + padding * 2;
    final boxHeight = rect.height + padding * 2;

    // Get 8 matching candidate objects
    final candidates = SmartPenService().getCandidatesForStroke(stroke);
    if (candidates.isEmpty) return const SizedBox.shrink();

    final screenSize = MediaQuery.of(context).size;
    const double popupWidth = 226.0;
    const double popupHeight = 226.0;

    // Determine whether to place popup on Right or Left of doodle
    final bool placeOnRight =
        (boxLeft + boxWidth + popupWidth + 24) < screenSize.width;
    final double popupLeft = placeOnRight
        ? (boxLeft + boxWidth + 14.0)
        : max(12.0, boxLeft - popupWidth - 14.0);

    double popupTop = (boxTop + boxHeight / 2) - (popupHeight / 2);
    popupTop = popupTop.clamp(16.0, screenSize.height - popupHeight - 75.0);

    // Arrow pointer Y relative to popup card
    final double arrowCenterY = (boxTop + boxHeight / 2) - popupTop;
    final double clampedArrowY = arrowCenterY.clamp(20.0, popupHeight - 20.0);

    return Stack(
      children: [
        // 1. Dashed Cyan Bounding Box around the drawn stroke
        Positioned(
          left: boxLeft,
          top: boxTop,
          width: boxWidth,
          height: boxHeight,
          child: IgnorePointer(
            child: CustomPaint(
              painter: _DashedBorderPainter(
                color: const Color(0xFF00C8AC),
                strokeWidth: 1.8,
              ),
            ),
          ),
        ),

        // 2. Triangular Notch Arrow pointing towards doodle
        Positioned(
          left: placeOnRight ? (popupLeft - 10) : (popupLeft + popupWidth),
          top: popupTop + clampedArrowY - 8,
          child: CustomPaint(
            size: const Size(10, 16),
            painter: _ArrowPointerPainter(
              pointsLeft: placeOnRight,
              color: Colors.white,
            ),
          ),
        ),

        // 3. White Floating Suggestion Card (3x3 Grid)
        Positioned(
          left: popupLeft,
          top: popupTop,
          width: popupWidth,
          height: popupHeight,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFCBD5E1),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 18,
                  spreadRadius: 1,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: _isReplacing
                ? const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Color(0xFF00C8AC),
                      ),
                    ),
                  )
                : Column(
                    children: [
                      // Row 1 (Original Stroke + Candidates 0, 1)
                      Expanded(
                        child: Row(
                          children: [
                            // Tile 1: Original doodle (Selected with teal border)
                            Expanded(
                              child: _buildTile(
                                isOriginal: true,
                                child: CustomPaint(
                                  painter: _MiniStrokePainter(stroke: stroke),
                                ),
                                onTap: () => provider.clearActiveSmartPenStroke(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (candidates.isNotEmpty)
                              Expanded(
                                child: _buildCandidateTile(
                                  candidates[0],
                                  stroke,
                                  provider,
                                ),
                              ),
                            const SizedBox(width: 8),
                            if (candidates.length > 1)
                              Expanded(
                                child: _buildCandidateTile(
                                  candidates[1],
                                  stroke,
                                  provider,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Row 2 (Candidates 2, 3, 4)
                      Expanded(
                        child: Row(
                          children: [
                            if (candidates.length > 2)
                              Expanded(
                                child: _buildCandidateTile(
                                  candidates[2],
                                  stroke,
                                  provider,
                                ),
                              ),
                            const SizedBox(width: 8),
                            if (candidates.length > 3)
                              Expanded(
                                child: _buildCandidateTile(
                                  candidates[3],
                                  stroke,
                                  provider,
                                ),
                              ),
                            const SizedBox(width: 8),
                            if (candidates.length > 4)
                              Expanded(
                                child: _buildCandidateTile(
                                  candidates[4],
                                  stroke,
                                  provider,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Row 3 (Candidates 5, 6, 7)
                      Expanded(
                        child: Row(
                          children: [
                            if (candidates.length > 5)
                              Expanded(
                                child: _buildCandidateTile(
                                  candidates[5],
                                  stroke,
                                  provider,
                                ),
                              ),
                            const SizedBox(width: 8),
                            if (candidates.length > 6)
                              Expanded(
                                child: _buildCandidateTile(
                                  candidates[6],
                                  stroke,
                                  provider,
                                ),
                              ),
                            const SizedBox(width: 8),
                            if (candidates.length > 7)
                              Expanded(
                                child: _buildCandidateTile(
                                  candidates[7],
                                  stroke,
                                  provider,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildCandidateTile(
    SmartPenCandidate candidate,
    StrokeElement stroke,
    WhiteboardProvider provider,
  ) {
    return _buildTile(
      isOriginal: false,
      child: CustomPaint(
        painter: candidate.painterBuilder(const Color(0xFF1E293B)),
      ),
      onTap: () async {
        if (_isReplacing) return;
        setState(() => _isReplacing = true);
        try {
          await provider.replaceSmartPenStrokeWithObject(stroke, candidate);
        } finally {
          if (mounted) {
            setState(() => _isReplacing = false);
          }
        }
      },
    );
  }

  Widget _buildTile({
    required bool isOriginal,
    required Widget child,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isOriginal ? const Color(0xFFE6F7F4) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isOriginal ? const Color(0xFF00C8AC) : Colors.transparent,
              width: isOriginal ? 1.5 : 0.0,
            ),
          ),
          child: Center(
            child: AspectRatio(
              aspectRatio: 1.0,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Mini painter that renders the original doodle inside the top-left tile
class _MiniStrokePainter extends CustomPainter {
  final StrokeElement stroke;
  _MiniStrokePainter({required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    if (stroke.points.length < 2) return;
    final bounds = stroke.getRawBounds();
    final double scale = min(
      (size.width - 6) / max(bounds.width, 1.0),
      (size.height - 6) / max(bounds.height, 1.0),
    );
    final offset = Offset(
      (size.width - bounds.width * scale) / 2 - bounds.left * scale,
      (size.height - bounds.height * scale) / 2 - bounds.top * scale,
    );

    final paint = Paint()
      ..color = stroke.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.5, stroke.strokeWidth * scale)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    for (int i = 0; i < stroke.points.length; i++) {
      final p = stroke.points[i] * scale + offset;
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MiniStrokePainter oldDelegate) => true;
}

/// Painter for Dashed Bounding Box around the doodle
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  _DashedBorderPainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    const dashWidth = 5.0;
    const dashSpace = 4.0;

    // Top edge
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(min(x + dashWidth, size.width), 0),
        paint,
      );
      x += dashWidth + dashSpace;
    }
    // Bottom edge
    x = 0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(min(x + dashWidth, size.width), size.height),
        paint,
      );
      x += dashWidth + dashSpace;
    }
    // Left edge
    double y = 0;
    while (y < size.height) {
      canvas.drawLine(
        Offset(0, y),
        Offset(0, min(y + dashWidth, size.height)),
        paint,
      );
      y += dashWidth + dashSpace;
    }
    // Right edge
    y = 0;
    while (y < size.height) {
      canvas.drawLine(
        Offset(size.width, y),
        Offset(size.width, min(y + dashWidth, size.height)),
        paint,
      );
      y += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) => false;
}

/// Painter for the triangle notch pointer arrow
class _ArrowPointerPainter extends CustomPainter {
  final bool pointsLeft;
  final Color color;
  _ArrowPointerPainter({required this.pointsLeft, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    if (pointsLeft) {
      path.moveTo(size.width, 0);
      path.lineTo(0, size.height / 2);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, 0);
      path.lineTo(size.width, size.height / 2);
      path.lineTo(0, size.height);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ArrowPointerPainter oldDelegate) => false;
}
