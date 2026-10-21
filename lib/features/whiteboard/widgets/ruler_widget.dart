import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Panel ke diagonal size (inch) aur resolution se estimate:
/// 1 cm = kitne logical px. Ye sirf starting point hai, final value calibration se.
double estimatePxPerCm(double diagonalInches) {
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final phys = view.physicalSize; // poori screen, window nahi
  final diagPx = sqrt(phys.width * phys.width + phys.height * phys.height);
  final physicalPpi = diagPx / diagonalInches;
  return physicalPpi / view.devicePixelRatio / 2.54;
}

enum _ActiveRulerEdge { none, top, bottom }

class RulerWidget extends StatefulWidget {
  final Offset initialPosition;
  final VoidCallback onClose;
  final ValueChanged<List<Offset>>? onDrawLine;

  /// Calibrated value (saved earlier). Null => default use hoga.
  final double? initialPxPerCm;

  /// Panel ka diagonal (65 / 75 / 86). initialPxPerCm na ho to isse estimate hota hai.
  final double? panelDiagonalInches;

  /// Calibration save hone par call hota hai (yahan shared_preferences me save karo).
  final ValueChanged<double>? onPxPerCmChanged;

  const RulerWidget({
    super.key,
    required this.initialPosition,
    required this.onClose,
    this.onDrawLine,
    this.initialPxPerCm,
    this.panelDiagonalInches,
    this.onPxPerCmChanged,
  });

  @override
  State<RulerWidget> createState() => _RulerWidgetState();
}

class _RulerWidgetState extends State<RulerWidget> {
  // Diagonal pata na ho to fallback (phone ke liye)
  static const double _fallbackPxPerCm = 160 / 2.54;
  static const double _pad = 20.0; // Outer hit-test padding margin around ruler edges

  final GlobalKey _bodyKey = GlobalKey();

  late Offset _position;
  late double _pxPerCm;
  double _rotation = 0.0;
  final double _scale = 1.0;

  double _width = 440.0;
  final double _height = 110.0;

  static const double _minWidth = 280.0;
  static const double _maxWidth = 4000.0;

  // Interactive Edge Pen Drawing State
  bool _isDrawingEdgeLine = false;
  _ActiveRulerEdge _activeEdge = _ActiveRulerEdge.none;
  Offset _dragStartPoint = Offset.zero;
  Offset _edgeLineStart = Offset.zero;
  Offset _edgeLineEnd = Offset.zero;

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition;
    _pxPerCm =
        widget.initialPxPerCm ?? (widget.panelDiagonalInches != null ? estimatePxPerCm(widget.panelDiagonalInches!) : _fallbackPxPerCm);
  }

  RenderBox? get _bodyBox => _bodyKey.currentContext?.findRenderObject() as RenderBox?;

  void _onRulerPanStart(DragStartDetails d) {
    final localY = d.localPosition.dy;
    if (localY < _pad + _height / 2) {
      _activeEdge = _ActiveRulerEdge.top;
    } else {
      _activeEdge = _ActiveRulerEdge.bottom;
    }
    final edgeY = _activeEdge == _ActiveRulerEdge.top ? _pad : _pad + _height;
    final x = (d.localPosition.dx - _pad).clamp(0.0, _width - _RulerPainter.endPadding);
    _dragStartPoint = Offset(_pad + x, edgeY);
    _edgeLineStart = _dragStartPoint;
    _edgeLineEnd = _dragStartPoint;
    _isDrawingEdgeLine = true;
    setState(() {});
  }

  void _onRulerPanUpdate(DragUpdateDetails d) {
    final edgeY = _activeEdge == _ActiveRulerEdge.top ? _pad : _pad + _height;
    final x1 = (_dragStartPoint.dx - _pad).clamp(0.0, _width - _RulerPainter.endPadding);
    final x2 = (d.localPosition.dx - _pad).clamp(0.0, _width - _RulerPainter.endPadding);
    _edgeLineStart = Offset(_pad + x1, edgeY);
    _edgeLineEnd = Offset(_pad + x2, edgeY);
    setState(() {});
  }

  void _onRulerPanEnd(DragEndDetails d) {
    if (_isDrawingEdgeLine && _activeEdge != _ActiveRulerEdge.none) {
      final box = _bodyBox;
      final cb = widget.onDrawLine;
      final dist = (_edgeLineEnd - _edgeLineStart).distance;
      if (cb != null && box != null && dist > 4.0) {
        final p1 = box.localToGlobal(_edgeLineStart);
        final p2 = box.localToGlobal(_edgeLineEnd);
        cb([p1, p2]);
      }
    }
    _isDrawingEdgeLine = false;
    _activeEdge = _ActiveRulerEdge.none;
    setState(() {});
  }

  void _onRulerPanCancel() {
    _isDrawingEdgeLine = false;
    _activeEdge = _ActiveRulerEdge.none;
    setState(() {});
  }

  /// Button action: Draws full length straight line along the bottom scale edge.
  void _drawLineAlongEdge() {
    final cb = widget.onDrawLine;
    final box = _bodyBox;
    if (cb == null || box == null) return;

    final p1 = box.localToGlobal(Offset(_pad + _RulerPainter.startX, _pad + _height));
    final p2 = box.localToGlobal(Offset(_pad + _width - _RulerPainter.endPadding, _pad + _height));
    cb([p1, p2]);
  }

  @override
  Widget build(BuildContext context) {
    final totalW = _width + _pad * 2;
    final totalH = _height + _pad * 2;
    final edgeLineDistPx = (_edgeLineEnd - _edgeLineStart).distance;
    final edgeLineDistCm = (edgeLineDistPx / _pxPerCm).toStringAsFixed(1);
    final edgeLineDistIn = (edgeLineDistPx / (_pxPerCm * 2.54)).toStringAsFixed(1);

    return Positioned(
      left: _position.dx - _pad,
      top: _position.dy - _pad,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..scaleByDouble(_scale, _scale, _scale, 1.0)
          ..rotateZ(_rotation),
        child: Material(
          color: Colors.transparent,
          child: SizedBox(
            key: _bodyKey,
            width: totalW,
            height: totalH,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Ruler Visual Box
                Positioned(
                  left: _pad,
                  top: _pad,
                  child: Container(
                    width: _width,
                    height: _height,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF94A3B8), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: CustomPaint(
                      size: Size(_width, _height),
                      painter: _RulerPainter(width: _width, pxPerCm: _pxPerCm),
                    ),
                  ),
                ),

                // Unified Pan Gesture Detector along scale edges
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onPanStart: _onRulerPanStart,
                    onPanUpdate: _onRulerPanUpdate,
                    onPanEnd: _onRulerPanEnd,
                    onPanCancel: _onRulerPanCancel,
                    child: const SizedBox.expand(),
                  ),
                ),

                // Live preview line being drawn
                if (_isDrawingEdgeLine && _activeEdge != _ActiveRulerEdge.none)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _RulerLinePreviewPainter(
                          start: _edgeLineStart,
                          end: _edgeLineEnd,
                        ),
                      ),
                    ),
                  ),

                // Measurement Tooltip Badge while drawing along ruler edge
                if (_isDrawingEdgeLine && _activeEdge != _ActiveRulerEdge.none && edgeLineDistPx > 2.0)
                  Positioned(
                    left: ((_edgeLineStart.dx + _edgeLineEnd.dx) / 2 - 35).clamp(2.0, totalW - 70),
                    top: _activeEdge == _ActiveRulerEdge.top
                        ? (_pad - 28.0).clamp(2.0, totalH)
                        : (_pad + _height + 6.0).clamp(2.0, totalH - 24),
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Text(
                          _activeEdge == _ActiveRulerEdge.top
                              ? '$edgeLineDistCm cm ($edgeLineDistIn in)'
                              : '$edgeLineDistCm cm',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),

                // Center Drag Handle (Pill shape) to move ruler
                Positioned(
                  left: _pad + (_width - 50) / 2,
                  top: _pad + (_height - 14) / 2,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) {
                      setState(() {
                        _position += details.delta;
                      });
                    },
                    child: Container(
                      width: 50,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 24,
                          height: 3,
                          decoration: BoxDecoration(
                            color: const Color(0xFF94A3B8),
                            borderRadius: BorderRadius.circular(1.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Right Edge Action Buttons (Close, Draw Line, Resize, Rotate)
                Positioned(
                  left: _pad + _width - 34,
                  top: _pad,
                  bottom: _pad,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _RulerActionButton(
                          icon: LucideIcons.x,
                          color: Colors.redAccent,
                          onTap: widget.onClose,
                        ),
                        const SizedBox(height: 5),
                        _RulerActionButton(
                          icon: LucideIcons.pencil,
                          color: const Color(0xFFDC2626),
                          onTap: _drawLineAlongEdge,
                        ),
                        const SizedBox(height: 5),
                        _RulerActionButton(
                          icon: LucideIcons.moveHorizontal,
                          color: const Color(0xFF0284C7),
                          onPanUpdate: (details) {
                            setState(() {
                              _width = (_width + details.delta.dx).clamp(_minWidth, _maxWidth);
                            });
                          },
                        ),
                        const SizedBox(height: 5),
                        _RulerActionButton(
                          icon: LucideIcons.rotateCw,
                          color: const Color(0xFF0284C7),
                          onPanUpdate: (details) {
                            setState(() {
                              _rotation += details.delta.dx * 0.01;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RulerActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final ValueChanged<DragUpdateDetails>? onPanUpdate;

  const _RulerActionButton({
    required this.icon,
    required this.color,
    this.onTap,
    this.onPanUpdate,
  });

  @override
  Widget build(BuildContext context) {
    Widget child = Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(child: Icon(icon, size: 12, color: color)),
    );

    if (onPanUpdate != null) {
      return GestureDetector(onPanUpdate: onPanUpdate, child: child);
    }
    return GestureDetector(onTap: onTap, child: child);
  }
}

class _RulerLinePreviewPainter extends CustomPainter {
  final Offset start;
  final Offset end;

  const _RulerLinePreviewPainter({required this.start, required this.end});

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFFDC2626)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(start, end, linePaint);
    canvas.drawCircle(start, 4.0, Paint()..color = const Color(0xFFDC2626));
    canvas.drawCircle(end, 4.0, Paint()..color = const Color(0xFFDC2626));
  }

  @override
  bool shouldRepaint(covariant _RulerLinePreviewPainter oldDelegate) =>
      oldDelegate.start != start || oldDelegate.end != end;
}

class _RulerPainter extends CustomPainter {
  final double width;
  final double pxPerCm; // calibrated: 1 cm = kitne logical px

  _RulerPainter({required this.width, required this.pxPerCm});

  double get mmPx => pxPerCm / 10;
  double get inchPx => pxPerCm * 2.54;
  double get eighthPx => inchPx / 8;

  static const double startX = 50.0; // 0 ka position
  static const double endPadding = 46.0; // right buttons ke liye jagah

  @override
  void paint(Canvas canvas, Size size) {
    final paintTick = Paint()
      ..color = const Color(0xFF334155)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    final paintInchTick = Paint()
      ..color = const Color(0xFFDC2626)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    final double usable = size.width - startX - endPadding;

    // ================= INCH (top) =================
    textPainter.text = const TextSpan(
      text: '0inch',
      style: TextStyle(color: Color(0xFFDC2626), fontSize: 10, fontWeight: FontWeight.bold),
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(12, 8));

    final int totalEighths = (usable / eighthPx).floor();
    for (int i = 0; i <= totalEighths; i++) {
      final double x = startX + i * eighthPx;

      if (i % 8 == 0) {
        canvas.drawLine(Offset(x, 0), Offset(x, 16), paintInchTick);
        if (i > 0) {
          textPainter.text = TextSpan(
            text: '${i ~/ 8}',
            style: const TextStyle(color: Color(0xFFDC2626), fontSize: 10, fontWeight: FontWeight.w600),
          );
          textPainter.layout();
          textPainter.paint(canvas, Offset(x - (textPainter.width / 2), 17));
        }
      } else {
        final double tickH = (i % 4 == 0) ? 12.0 : ((i % 2 == 0) ? 9.0 : 6.0);
        canvas.drawLine(Offset(x, 0), Offset(x, tickH), paintInchTick);
      }
    }

    // ================= CM / MM (bottom) =================
    textPainter.text = const TextSpan(
      text: '0cm',
      style: TextStyle(color: Color(0xFF0F172A), fontSize: 10, fontWeight: FontWeight.bold),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(12, size.height - 20));

    final int totalMm = (usable / mmPx).floor();
    for (int i = 0; i <= totalMm; i++) {
      final double x = startX + i * mmPx;

      if (i % 10 == 0) {
        canvas.drawLine(Offset(x, size.height), Offset(x, size.height - 18), paintTick);
        if (i > 0) {
          textPainter.text = TextSpan(
            text: '${i ~/ 10}',
            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 10, fontWeight: FontWeight.w600),
          );
          textPainter.layout();
          textPainter.paint(canvas, Offset(x - (textPainter.width / 2), size.height - 32));
        }
      } else {
        final double tickH = (i % 5 == 0) ? 12.0 : 7.0;
        canvas.drawLine(Offset(x, size.height), Offset(x, size.height - tickH), paintTick);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) => oldDelegate.width != width || oldDelegate.pxPerCm != pxPerCm;
}
