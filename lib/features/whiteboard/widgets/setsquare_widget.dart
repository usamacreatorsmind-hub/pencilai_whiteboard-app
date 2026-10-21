import 'dart:math';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const double _pad = 20.0; // Outer hit-test padding margin around set square ruler edges
const double _startPad = 6.0;
const double _labelClear = 10.0;

enum _ActiveRulerEdge { none, top, left }

double _inset(double l) => (l * 0.2).clamp(25.0, 50.0).toDouble();
double _innerLeg(double l) => l - _inset(l) * (2 + sqrt2);

Path _outerPath(double l) => Path()
  ..moveTo(_pad, _pad)
  ..lineTo(_pad + l, _pad)
  ..lineTo(_pad, _pad + l)
  ..close();

Path? _innerPath(double l) {
  final leg = _innerLeg(l);
  if (leg < 40) return null;
  final d = _inset(l);
  return Path()
    ..moveTo(_pad + d, _pad + d)
    ..lineTo(_pad + d + leg, _pad + d)
    ..lineTo(_pad + d, _pad + d + leg)
    ..close();
}

Offset _pillCenter(double l) {
  final leg = _innerLeg(l);
  final k = leg >= 40 ? _inset(l) + leg / 3 : l / 3;
  return Offset(_pad + max(k, 40.0), _pad + k);
}

Offset _onHypotenuse(double l, double t) => Offset(_pad + l - t / sqrt2, _pad + t / sqrt2);

class SetSquareWidget extends StatefulWidget {
  final Offset initialPosition;
  final VoidCallback onClose;
  final ValueChanged<List<Offset>>? onDrawLine;

  final double pxPerCm;
  final double initialLengthCm;
  final double minLengthCm;
  final double maxLengthCm;

  const SetSquareWidget({
    super.key,
    required this.initialPosition,
    required this.onClose,
    this.onDrawLine,
    this.pxPerCm = 42.0,
    this.initialLengthCm = 5.0,
    this.minLengthCm = 2.8,
    this.maxLengthCm = 30.0,
  });

  @override
  State<SetSquareWidget> createState() => _SetSquareWidgetState();
}

class _SetSquareWidgetState extends State<SetSquareWidget> {
  final GlobalKey _bodyKey = GlobalKey();

  late Offset _position;
  late double _length;
  double _rotation = 0.0;

  Offset _lastGlobal = Offset.zero;
  double _lastPointerAngle = 0.0;

  // Interactive Edge Pen Drawing State
  bool _isDrawingEdgeLine = false;
  _ActiveRulerEdge _activeEdge = _ActiveRulerEdge.none;
  Offset _dragStartPoint = Offset.zero;
  Offset _edgeLineStart = Offset.zero;
  Offset _edgeLineEnd = Offset.zero;

  double get _minLen => max(110.0, widget.minLengthCm * widget.pxPerCm);
  double get _maxLen => max(_minLen, widget.maxLengthCm * widget.pxPerCm);

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition;
    _length = (widget.initialLengthCm * widget.pxPerCm).clamp(_minLen, _maxLen).toDouble();
  }

  RenderBox? get _bodyBox => _bodyKey.currentContext?.findRenderObject() as RenderBox?;

  void _resize(DragUpdateDetails d) {
    setState(() {
      _length = (_length + d.delta.dx).clamp(_minLen, _maxLen).toDouble();
    });
  }

  void _moveStart(DragStartDetails d) => _lastGlobal = d.globalPosition;

  void _moveUpdate(DragUpdateDetails d) {
    final g = d.globalPosition;
    setState(() => _position += g - _lastGlobal);
    _lastGlobal = g;
  }

  double? _pointerAngle(Offset global) {
    final box = _bodyBox;
    if (box == null) return null;
    final v = box.localToGlobal(const Offset(_pad, _pad));
    return atan2(global.dy - v.dy, global.dx - v.dx);
  }

  void _rotateStart(DragStartDetails d) {
    final a = _pointerAngle(d.globalPosition);
    if (a != null) _lastPointerAngle = a;
  }

  void _rotateUpdate(DragUpdateDetails d) {
    final a = _pointerAngle(d.globalPosition);
    if (a == null) return;
    double delta = a - _lastPointerAngle;
    delta = atan2(sin(delta), cos(delta));
    setState(() => _rotation += delta);
    _lastPointerAngle = a;
  }

  // --- Direction-Aware Ruler Edge Pen Dragging Handlers ---

  void _onRulerPanStart(DragStartDetails d) {
    _dragStartPoint = d.localPosition;
    _activeEdge = _ActiveRulerEdge.none;
    _isDrawingEdgeLine = true;
    _edgeLineStart = d.localPosition;
    _edgeLineEnd = d.localPosition;
    setState(() {});
  }

  void _onRulerPanUpdate(DragUpdateDetails d) {
    final p = d.localPosition;

    // Detect drawing direction (horizontal -> Top Edge, vertical -> Left Edge)
    if (_activeEdge == _ActiveRulerEdge.none) {
      final dx = (p.dx - _dragStartPoint.dx).abs();
      final dy = (p.dy - _dragStartPoint.dy).abs();
      if (max(dx, dy) >= 3.0) {
        if (dx >= dy) {
          _activeEdge = _ActiveRulerEdge.top;
        } else {
          _activeEdge = _ActiveRulerEdge.left;
        }
      }
    }

    if (_activeEdge == _ActiveRulerEdge.top) {
      final x1 = (_dragStartPoint.dx - _pad).clamp(0.0, _length);
      final x2 = (p.dx - _pad).clamp(0.0, _length);
      _edgeLineStart = Offset(_pad + x1, _pad);
      _edgeLineEnd = Offset(_pad + x2, _pad);
    } else if (_activeEdge == _ActiveRulerEdge.left) {
      final y1 = (_dragStartPoint.dy - _pad).clamp(0.0, _length);
      final y2 = (p.dy - _pad).clamp(0.0, _length);
      _edgeLineStart = Offset(_pad, _pad + y1);
      _edgeLineEnd = Offset(_pad, _pad + y2);
    }

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

  /// Button action: Draws full length straight line along the top ruler edge.
  void _drawLineAlongEdge() {
    final cb = widget.onDrawLine;
    final box = _bodyBox;
    if (cb == null || box == null) return;

    final p1 = box.localToGlobal(const Offset(_pad, _pad));
    final p2 = box.localToGlobal(Offset(_pad + _length, _pad));

    // Passing exactly 2 points ensures vector-straight line without bezier curve distortion
    cb([p1, p2]);
  }

  Widget _button(
    Offset center,
    IconData icon, {
    Color? bgColor,
    Color? iconColor,
    VoidCallback? onTap,
    GestureDragStartCallback? onPanStart,
    GestureDragUpdateCallback? onPanUpdate,
  }) {
    final Widget child = Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: bgColor ?? const Color(0xFF2563EB),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 3)],
      ),
      child: Center(child: Icon(icon, size: 12, color: iconColor ?? Colors.white)),
    );

    return Positioned(
      left: center.dx - 12,
      top: center.dy - 12,
      child: onPanUpdate != null
          ? GestureDetector(onPanStart: onPanStart, onPanUpdate: onPanUpdate, child: child)
          : GestureDetector(onTap: onTap, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = _length;
    final totalW = l + _pad * 2;
    final totalH = l + _pad * 2;
    final pill = _pillCenter(l);
    final hypLen = l * sqrt2;
    final edgeLineDistPx = (_edgeLineEnd - _edgeLineStart).distance;
    final edgeLineDistCm = (edgeLineDistPx / widget.pxPerCm).toStringAsFixed(1);

    return Positioned(
      left: _position.dx - _pad,
      top: _position.dy - _pad,
      child: Transform(
        alignment: Alignment(_pad / totalW, _pad / totalH),
        transform: Matrix4.rotationZ(_rotation),
        child: Material(
          color: Colors.transparent,
          child: SizedBox(
            key: _bodyKey,
            width: totalW,
            height: totalH,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Set Square Painter
                Positioned.fill(
                  child: CustomPaint(
                    painter: _SetSquarePainter(
                      length: l,
                      pxPerCm: widget.pxPerCm,
                      isDrawingLine: _isDrawingEdgeLine && _activeEdge != _ActiveRulerEdge.none,
                      edgeLineStart: _edgeLineStart,
                      edgeLineEnd: _edgeLineEnd,
                    ),
                  ),
                ),

                // Unified Direction-Aware Ruler Drag Gesture Detector (Top & Left Scale Edges)
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

                // Measurement Tooltip Badge while drawing along ruler edge
                if (_isDrawingEdgeLine && _activeEdge != _ActiveRulerEdge.none && edgeLineDistPx > 2.0)
                  Positioned(
                    left: _activeEdge == _ActiveRulerEdge.top
                        ? ((_edgeLineStart.dx + _edgeLineEnd.dx) / 2 - 28).clamp(0.0, totalW - 56)
                        : 2.0,
                    top: _activeEdge == _ActiveRulerEdge.top
                        ? 2.0
                        : ((_edgeLineStart.dy + _edgeLineEnd.dy) / 2 - 12).clamp(0.0, totalH - 24),
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
                          '$edgeLineDistCm cm',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),

                // Move handle (pill in inner cutout) - placed after gesture detector
                Positioned(
                  left: pill.dx - 26,
                  top: pill.dy - 12,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: _moveStart,
                    onPanUpdate: _moveUpdate,
                    child: Container(
                      width: 52,
                      height: 24,
                      alignment: Alignment.center,
                      child: Container(
                        width: 44,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFCBD5E1), width: 1.0),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 3, offset: const Offset(0, 1))],
                        ),
                        child: Center(
                          child: Container(
                            width: 18,
                            height: 2.5,
                            decoration: BoxDecoration(color: const Color(0xFF94A3B8), borderRadius: BorderRadius.circular(1.2)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Buttons on hypotenuse (Resize, Rotate, Draw Full Straight Line, Close)
                _button(_onHypotenuse(l, 18), LucideIcons.moveHorizontal, onPanUpdate: _resize),
                _button(_onHypotenuse(l, 46), LucideIcons.rotateCw, onPanStart: _rotateStart, onPanUpdate: _rotateUpdate),
                _button(_onHypotenuse(l, 74), LucideIcons.pencil, bgColor: const Color(0xFFDC2626), onTap: _drawLineAlongEdge),
                _button(_onHypotenuse(l, max(102.0, hypLen - 18)), LucideIcons.x, bgColor: const Color(0xFFEF4444), onTap: widget.onClose),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SetSquarePainter extends CustomPainter {
  final double length;
  final double pxPerCm;
  final bool isDrawingLine;
  final Offset edgeLineStart;
  final Offset edgeLineEnd;

  const _SetSquarePainter({
    required this.length,
    required this.pxPerCm,
    this.isDrawingLine = false,
    this.edgeLineStart = Offset.zero,
    this.edgeLineEnd = Offset.zero,
  });

  static const Color _tick = Color(0xFF1E293B);
  static const Color _text = Color(0xFF0F172A);
  static const Color _edge = Color(0xFF2563EB);
  static const Color _redAccent = Color(0xFFDC2626);

  @override
  void paint(Canvas canvas, Size size) {
    final l = length;
    final outer = _outerPath(l);
    final inner = _innerPath(l);

    canvas.drawShadow(outer, Colors.black.withValues(alpha: 0.2), 5, true);
    final fillPath = inner == null ? outer : Path.combine(PathOperation.difference, outer, inner);
    canvas.drawPath(fillPath, Paint()..color = Colors.white.withValues(alpha: 0.94));

    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = _edge;
    canvas.drawPath(outer, edgePaint);
    if (inner != null) canvas.drawPath(inner, edgePaint);

    canvas.save();
    canvas.clipPath(outer);
    _drawScales(canvas, l);
    canvas.restore();

    // Live preview of straight line being drawn with Pen along ruler edge
    if (isDrawingLine) {
      final linePaint = Paint()
        ..color = _redAccent
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(edgeLineStart, edgeLineEnd, linePaint);
      canvas.drawCircle(edgeLineStart, 4.0, Paint()..color = _redAccent);
      canvas.drawCircle(edgeLineEnd, 4.0, Paint()..color = _redAccent);
    }
  }

  void _drawScales(Canvas canvas, double l) {
    final tickPaint = Paint()
      ..color = _tick
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    final mmPx = pxPerCm / 10;
    final maxIndex = ((l - _startPad - 4.0) / mmPx).floor();
    final tp = TextPainter(textDirection: TextDirection.ltr);

    const style = TextStyle(
      color: _text,
      fontSize: 8.5,
      fontWeight: FontWeight.bold,
    );

    for (int i = 0; i <= maxIndex; i++) {
      final double pos = _startPad + i * mmPx;
      final bool isCm = i % 10 == 0;
      final double len = isCm ? 11.0 : (i % 5 == 0 ? 8.0 : 5.0);

      canvas.drawLine(Offset(_pad + pos, _pad), Offset(_pad + pos, _pad + len), tickPaint);
      canvas.drawLine(Offset(_pad, _pad + pos), Offset(_pad + len, _pad + pos), tickPaint);

      if (isCm && (l - pos) >= _labelClear) {
        final int cm = i ~/ 10;

        tp.text = TextSpan(text: cm == 0 ? '0cm' : '$cm', style: style);
        tp.layout();
        tp.paint(canvas, Offset(_pad + pos - tp.width / 2, _pad + 12));

        if (cm > 0) {
          tp.text = TextSpan(text: '$cm', style: style);
          tp.layout();
          tp.paint(canvas, Offset(_pad + 12, _pad + pos - tp.height / 2));
        }
      }
    }
  }

  @override
  bool? hitTest(Offset position) {
    final outer = _outerPath(length);
    if (outer.contains(position)) return true;
    final totalW = length + _pad * 2;
    final totalH = length + _pad * 2;
    final rectTop = Rect.fromLTWH(0, 0, totalW, _pad + 26);
    final rectLeft = Rect.fromLTWH(0, 0, _pad + 26, totalH);
    if (rectTop.contains(position) || rectLeft.contains(position)) return true;
    return false;
  }

  @override
  bool shouldRepaint(covariant _SetSquarePainter old) =>
      old.length != length ||
      old.pxPerCm != pxPerCm ||
      old.isDrawingLine != isDrawingLine ||
      old.edgeLineStart != edgeLineStart ||
      old.edgeLineEnd != edgeLineEnd;
}
