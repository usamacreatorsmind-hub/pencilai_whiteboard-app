import 'dart:math';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class CompassWidget extends StatefulWidget {
  final Offset initialPosition;
  final VoidCallback onClose;

  /// Emits stroke points in global screen coordinates whenever a circle or arc is drawn.
  final ValueChanged<List<Offset>>? onDrawArc;

  /// Logical pixels per centimeter (default: 42.0 px/cm).
  final double pxPerCm;

  const CompassWidget({
    super.key,
    required this.initialPosition,
    required this.onClose,
    this.onDrawArc,
    this.pxPerCm = 42.0,
  });

  @override
  State<CompassWidget> createState() => _CompassWidgetState();
}

class _CompassWidgetState extends State<CompassWidget> {
  static const double _width = 280.0;
  static const double _height = 320.0;

  static const double _rulerY = 265.0;
  static const Offset _pivot = Offset(_width / 2, 85.0);

  late Offset _position;

  double _rotation = 0.0; // Rotation angle in radians
  double _spreadAngle = 0.42; // Leg spread angle in radians (~24 deg)

  // Live arc drawing state
  bool _isDrawing = false;
  final List<Offset> _liveArcPoints = [];
  double _liveSweepAngle = 0.0;
  double _lastTouchAngle = 0.0;

  // Bounded spread limits
  double get _maxSpreadAngle => atan((_width / 2 - 25) / (_rulerY - _pivot.dy));
  static const double _minSpreadAngle = pi / 25; // ~7.2 degrees

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition;
  }

  // Needle tip (left leg tip) in local unrotated space touching rulerY
  Offset _getNeedleTipLocal() {
    return Offset(
      _pivot.dx - (_rulerY - _pivot.dy) * tan(_spreadAngle),
      _rulerY,
    );
  }

  // Pencil tip (right leg tip) in local unrotated space touching rulerY
  Offset _getPencilTipLocal() {
    return Offset(
      _pivot.dx + (_rulerY - _pivot.dy) * tan(_spreadAngle),
      _rulerY,
    );
  }

  // Radius in pixels (distance between needle tip and pencil tip)
  double get _radiusPx => _getPencilTipLocal().dx - _getNeedleTipLocal().dx;

  // Real-time Radius in centimeters
  double get _radiusCm => _radiusPx / widget.pxPerCm;

  // Global position of Needle Tip (Pivot)
  Offset get _globalNeedleTip => _position + _getNeedleTipLocal();

  // Global position of Pencil Tip at current _rotation
  Offset get _globalPencilTip {
    final needle = _globalNeedleTip;
    final r = _radiusPx;
    return Offset(
      needle.dx + r * cos(_rotation),
      needle.dy + r * sin(_rotation),
    );
  }

  // Left Leg Handle Position (for spread adjustment)
  Offset _getLeftHandleLocal() {
    final needle = _getNeedleTipLocal();
    return Offset.lerp(_pivot, needle, 0.65)!;
  }

  // Right Leg Handle Position (for spread adjustment)
  Offset _getRightHandleLocal() {
    final pencil = _getPencilTipLocal();
    return Offset.lerp(_pivot, pencil, 0.65)!;
  }

  // Quick 360 Full Circle Drawing
  void _drawFullCircle() {
    final needle = _globalNeedleTip;
    final r = _radiusPx;
    const numSteps = 90;
    final points = <Offset>[];

    for (int i = 0; i <= numSteps; i++) {
      final angle = (i / numSteps) * 2 * pi;
      points.add(Offset(
        needle.dx + r * cos(angle),
        needle.dy + r * sin(angle),
      ));
    }

    widget.onDrawArc?.call(points);
  }

  // Pencil Tip Touch & Drag Drawing Handlers
  void _onPencilPanStart(DragStartDetails details) {
    final needle = _globalNeedleTip;
    final touch = details.globalPosition;
    _lastTouchAngle = atan2(touch.dy - needle.dy, touch.dx - needle.dx);

    setState(() {
      _isDrawing = true;
      _liveSweepAngle = 0.0;
      _liveArcPoints.clear();
      _liveArcPoints.add(_globalPencilTip);
    });
  }

  void _onPencilPanUpdate(DragUpdateDetails details) {
    final needle = _globalNeedleTip;
    final touch = details.globalPosition;
    final newAngle = atan2(touch.dy - needle.dy, touch.dx - needle.dx);

    double delta = newAngle - _lastTouchAngle;
    while (delta > pi) {
      delta -= 2 * pi;
    }
    while (delta < -pi) {
      delta += 2 * pi;
    }

    _lastTouchAngle = newAngle;

    setState(() {
      _rotation += delta;
      _liveSweepAngle += delta;

      final currentPencil = _globalPencilTip;
      if (_liveArcPoints.isEmpty ||
          (currentPencil - _liveArcPoints.last).distance >= 3.0) {
        _liveArcPoints.add(currentPencil);
      }
    });
  }

  void _onPencilPanEnd(DragEndDetails details) {
    if (_liveArcPoints.length >= 2) {
      widget.onDrawArc?.call(List.from(_liveArcPoints));
    }
    setState(() {
      _isDrawing = false;
      _liveArcPoints.clear();
      _liveSweepAngle = 0.0;
    });
  }

  void _updateSpread(double delta, {required bool isLeft}) {
    setState(() {
      final direction = isLeft ? -1.0 : 1.0;
      _spreadAngle = (_spreadAngle + delta * direction * 0.010)
          .clamp(_minSpreadAngle, _maxSpreadAngle)
          .toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    final needleLocal = _getNeedleTipLocal();
    final pencilLocal = _getPencilTipLocal();

    final leftHandleLocal = _getLeftHandleLocal();
    final rightHandleLocal = _getRightHandleLocal();

    // Alignment pivot for rotation around needle tip
    final alignX = (needleLocal.dx / _width) * 2 - 1;
    final alignY = (needleLocal.dy / _height) * 2 - 1;

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: Transform(
        alignment: Alignment(alignX, alignY),
        transform: Matrix4.identity()..rotateZ(_rotation),
        child: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: _width,
            height: _height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Custom Painter for Compass Assembly, Legs, Tips & Ruler
                CustomPaint(
                  size: const Size(_width, _height),
                  painter: _CompassPainter(
                    pivot: _pivot,
                    needleTip: needleLocal,
                    pencilTip: pencilLocal,
                    spreadAngle: _spreadAngle,
                    rulerY: _rulerY,
                    pxPerCm: widget.pxPerCm,
                    isDrawing: _isDrawing,
                    liveSweepAngle: _liveSweepAngle,
                  ),
                ),

                // Dynamic Floating Measurement Badge (Positioned below the joint / center wheel)
                Positioned(
                  left: _width / 2 - 42,
                  top: 125,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xEE0F172A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.cyanAccent, width: 1.2),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          LucideIcons.ruler,
                          size: 13,
                          color: Colors.cyanAccent,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${_radiusCm.toStringAsFixed(1)} cm',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Top Stem: Drag to move compass
                Positioned(
                  left: _width / 2 - 15,
                  top: 15,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      setState(() {
                        _position += details.delta;
                      });
                    },
                    child: Container(
                      width: 30,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C766B).withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white,
                          width: 2.0,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Close Button
                Positioned(
                  left: _width / 2 + 25,
                  top: 22,
                  child: GestureDetector(
                    onTap: widget.onClose,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFA092),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFFFC2B7),
                          width: 1.2,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 3,
                          ),
                        ],
                      ),
                      child: const Icon(
                        LucideIcons.x,
                        color: Colors.white,
                        size: 15,
                      ),
                    ),
                  ),
                ),

                // Center Rotation Hinge Wheel
                Positioned(
                  left: _pivot.dx - 30,
                  top: _pivot.dy - 30,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      setState(() {
                        _rotation += details.delta.dx * 0.01;
                      });
                    },
                    onDoubleTap: _drawFullCircle,
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C766B).withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 2.0,
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 1.8,
                            ),
                          ),
                          child: const Icon(
                            LucideIcons.rotateCcw,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Left Leg Spread Handle
                Positioned(
                  left: leftHandleLocal.dx - 13,
                  top: leftHandleLocal.dy - 13,
                  child: _CompassHandle(
                    icon: LucideIcons.arrowLeftRight,
                    onPanUpdate: (details) {
                      _updateSpread(details.delta.dx, isLeft: true);
                    },
                  ),
                ),

                // Right Leg Spread Handle
                Positioned(
                  left: rightHandleLocal.dx - 13,
                  top: rightHandleLocal.dy - 13,
                  child: _CompassHandle(
                    icon: LucideIcons.moveHorizontal,
                    onPanUpdate: (details) {
                      _updateSpread(details.delta.dx, isLeft: false);
                    },
                  ),
                ),

                // Interactive Blue Pencil Tip Touch Handle (Draws Circle on Touch/Drag)
                Positioned(
                  left: pencilLocal.dx - 18,
                  top: _rulerY - 18,
                  child: GestureDetector(
                    onPanStart: _onPencilPanStart,
                    onPanUpdate: _onPencilPanUpdate,
                    onPanEnd: _onPencilPanEnd,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _isDrawing
                            ? const Color(0xFF09B7F5).withValues(alpha: 0.35)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: const Color(0xFF09B7F5),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.8),
                            boxShadow: const [
                              BoxShadow(color: Color(0xFF09B7F5), blurRadius: 6),
                            ],
                          ),
                        ),
                      ),
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

class _CompassHandle extends StatelessWidget {
  final IconData icon;
  final ValueChanged<DragUpdateDetails> onPanUpdate;

  const _CompassHandle({
    required this.icon,
    required this.onPanUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: onPanUpdate,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: const Color(0xFF7C766B).withValues(alpha: 0.55),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white,
            width: 1.5,
          ),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 3),
          ],
        ),
        child: Icon(
          icon,
          size: 14,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  final Offset pivot;
  final Offset needleTip;
  final Offset pencilTip;
  final double spreadAngle;
  final double rulerY;
  final double pxPerCm;
  final bool isDrawing;
  final double liveSweepAngle;

  _CompassPainter({
    required this.pivot,
    required this.needleTip,
    required this.pencilTip,
    required this.spreadAngle,
    required this.rulerY,
    required this.pxPerCm,
    required this.isDrawing,
    required this.liveSweepAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Left Leg (Grey stick) and Metal Needle Nib
    _drawLeftLegAndNeedle(canvas);

    // 2. Draw Right Leg (Grey stick) and Pencil
    _drawRightLegAndPencil(canvas);

    // 3. Draw Ruler Scale Bounded strictly between Needle Tip & Pencil Tip
    _drawRuler(canvas);

    // 4. Draw Live Arc Trace if drawing
    if (isDrawing && liveSweepAngle.abs() > 0.01) {
      _drawLiveArcTrace(canvas);
    }
  }

  void _drawLeftLegAndNeedle(Canvas canvas) {
    final dirLeft = Offset(-sin(spreadAngle), cos(spreadAngle));
    final normalLeft = Offset(-dirLeft.dy, dirLeft.dx);
    final totalDist = (rulerY - pivot.dy) / cos(spreadAngle);

    // --- Leg Stick (aligned along center axis) ---
    final legStart = pivot + dirLeft * 28.0;
    final legEnd = pivot + dirLeft * (totalDist - 28.0);

    final legPath = Path()
      ..moveTo(legStart.dx + normalLeft.dx * 9.0, legStart.dy + normalLeft.dy * 9.0)
      ..lineTo(legEnd.dx + normalLeft.dx * 5.5, legEnd.dy + normalLeft.dy * 5.5)
      ..lineTo(legEnd.dx - normalLeft.dx * 5.5, legEnd.dy - normalLeft.dy * 5.5)
      ..lineTo(legStart.dx - normalLeft.dx * 9.0, legStart.dy - normalLeft.dy * 9.0)
      ..close();

    canvas.drawPath(
      legPath,
      Paint()
        ..color = const Color(0xFF7C766B).withValues(alpha: 0.35)
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      legPath,
      Paint()
        ..color = const Color(0xFFF6F2E8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeJoin = StrokeJoin.round,
    );

    // --- Metal Needle Nib (aligned along center axis) ---
    final nibAttach = legEnd;
    final nibTip = needleTip;

    // Metallic attachment collar
    final collarStart = nibAttach - dirLeft * 2.0;
    final collarEnd = nibAttach + dirLeft * 4.0;

    final collarPath = Path()
      ..moveTo(collarStart.dx + normalLeft.dx * 6.0, collarStart.dy + normalLeft.dy * 6.0)
      ..lineTo(collarEnd.dx + normalLeft.dx * 5.0, collarEnd.dy + normalLeft.dy * 5.0)
      ..lineTo(collarEnd.dx - normalLeft.dx * 5.0, collarEnd.dy - normalLeft.dy * 5.0)
      ..lineTo(collarStart.dx - normalLeft.dx * 6.0, collarStart.dy - normalLeft.dy * 6.0)
      ..close();

    canvas.drawPath(
      collarPath,
      Paint()
        ..color = const Color(0xFF475569)
        ..style = PaintingStyle.fill,
    );

    // Metallic needle body tapering to sharp tip at needleTip
    final needleBodyStart = collarEnd;
    final needlePath = Path()
      ..moveTo(needleBodyStart.dx + normalLeft.dx * 3.5, needleBodyStart.dy + normalLeft.dy * 3.5)
      ..lineTo(nibTip.dx, nibTip.dy)
      ..lineTo(needleBodyStart.dx - normalLeft.dx * 3.5, needleBodyStart.dy - normalLeft.dy * 3.5)
      ..close();

    canvas.drawPath(
      needlePath,
      Paint()
        ..color = const Color(0xFF38BDF8)
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      needlePath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  void _drawRightLegAndPencil(Canvas canvas) {
    final dirRight = Offset(sin(spreadAngle), cos(spreadAngle));
    final normalRight = Offset(-dirRight.dy, dirRight.dx);
    final totalDist = (rulerY - pivot.dy) / cos(spreadAngle);

    // --- Leg Stick (aligned along center axis) ---
    final legStart = pivot + dirRight * 28.0;
    final legEnd = pivot + dirRight * (totalDist - 42.0);

    final legPath = Path()
      ..moveTo(legStart.dx + normalRight.dx * 9.0, legStart.dy + normalRight.dy * 9.0)
      ..lineTo(legEnd.dx + normalRight.dx * 5.5, legEnd.dy + normalRight.dy * 5.5)
      ..lineTo(legEnd.dx - normalRight.dx * 5.5, legEnd.dy - normalRight.dy * 5.5)
      ..lineTo(legStart.dx - normalRight.dx * 9.0, legStart.dy - normalRight.dy * 9.0)
      ..close();

    canvas.drawPath(
      legPath,
      Paint()
        ..color = const Color(0xFF7C766B).withValues(alpha: 0.35)
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      legPath,
      Paint()
        ..color = const Color(0xFFF6F2E8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeJoin = StrokeJoin.round,
    );

    // --- Pencil Assembly (aligned along center axis) ---
    // 1. Metal Ferrule / Holder Band (from totalDist - 42.0 to totalDist - 32.0)
    final ferruleStart = legEnd;
    final ferruleEnd = pivot + dirRight * (totalDist - 32.0);

    final ferrulePath = Path()
      ..moveTo(ferruleStart.dx + normalRight.dx * 6.0, ferruleStart.dy + normalRight.dy * 6.0)
      ..lineTo(ferruleEnd.dx + normalRight.dx * 5.5, ferruleEnd.dy + normalRight.dy * 5.5)
      ..lineTo(ferruleEnd.dx - normalRight.dx * 5.5, ferruleEnd.dy - normalRight.dy * 5.5)
      ..lineTo(ferruleStart.dx - normalRight.dx * 6.0, ferruleStart.dy - normalRight.dy * 6.0)
      ..close();

    canvas.drawPath(
      ferrulePath,
      Paint()
        ..color = const Color(0xFF94A3B8)
        ..style = PaintingStyle.fill,
    );

    // 2. Cyan Pencil Shaft (from totalDist - 32.0 to totalDist - 12.0)
    final shaftStart = ferruleEnd;
    final shaftEnd = pivot + dirRight * (totalDist - 12.0);

    final shaftPath = Path()
      ..moveTo(shaftStart.dx + normalRight.dx * 5.5, shaftStart.dy + normalRight.dy * 5.5)
      ..lineTo(shaftEnd.dx + normalRight.dx * 5.0, shaftEnd.dy + normalRight.dy * 5.0)
      ..lineTo(shaftEnd.dx - normalRight.dx * 5.0, shaftEnd.dy - normalRight.dy * 5.0)
      ..lineTo(shaftStart.dx - normalRight.dx * 5.5, shaftStart.dy - normalRight.dy * 5.5)
      ..close();

    canvas.drawPath(
      shaftPath,
      Paint()
        ..color = const Color(0xFF09B7F5)
        ..style = PaintingStyle.fill,
    );

    // Pencil Center Highlight Stripe
    canvas.drawLine(
      shaftStart,
      shaftEnd,
      Paint()
        ..color = const Color(0xFF7DD3FC)
        ..strokeWidth = 1.8,
    );

    // 3. Sharpened Wooden Cone (from totalDist - 12.0 to totalDist - 4.0)
    final woodStart = shaftEnd;
    final leadStart = pivot + dirRight * (totalDist - 4.0);

    final woodPath = Path()
      ..moveTo(woodStart.dx + normalRight.dx * 5.0, woodStart.dy + normalRight.dy * 5.0)
      ..lineTo(leadStart.dx + normalRight.dx * 2.0, leadStart.dy + normalRight.dy * 2.0)
      ..lineTo(leadStart.dx - normalRight.dx * 2.0, leadStart.dy - normalRight.dy * 2.0)
      ..lineTo(woodStart.dx - normalRight.dx * 5.0, woodStart.dy - normalRight.dy * 5.0)
      ..close();

    canvas.drawPath(
      woodPath,
      Paint()
        ..color = const Color(0xFFE2B07E)
        ..style = PaintingStyle.fill,
    );

    // 4. Cyan Lead Tip (from totalDist - 4.0 to pencilTip)
    final leadPath = Path()
      ..moveTo(leadStart.dx + normalRight.dx * 2.0, leadStart.dy + normalRight.dy * 2.0)
      ..lineTo(pencilTip.dx, pencilTip.dy)
      ..lineTo(leadStart.dx - normalRight.dx * 2.0, leadStart.dy - normalRight.dy * 2.0)
      ..close();

    canvas.drawPath(
      leadPath,
      Paint()
        ..color = const Color(0xFF0284C7)
        ..style = PaintingStyle.fill,
    );
  }

  void _drawRuler(Canvas canvas) {
    final startX = needleTip.dx;
    final endX = pencilTip.dx;

    if (endX <= startX) return;

    final rulerPaint = Paint()
      ..color = const Color(0xFF09B7F5)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    // 1. Horizontal scale line strictly bounded between needle tip and pencil tip
    canvas.drawLine(
      Offset(startX, rulerY),
      Offset(endX, rulerY),
      rulerPaint,
    );

    // 2. End cap dots at needle tip and pencil tip
    final capPaint = Paint()
      ..color = const Color(0xFF09B7F5)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(startX, rulerY), 2.5, capPaint);
    canvas.drawCircle(Offset(endX, rulerY), 2.5, capPaint);

    // 3. Tick marks along the scale
    final zeroX = startX;
    final unitWidth = pxPerCm;

    final totalMmTicks = ((endX - startX) / (unitWidth / 10)).floor();

    final tickPaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    for (int i = 0; i <= totalMmTicks; i++) {
      final x = zeroX + i * (unitWidth / 10);
      if (x > endX + 0.1) break;

      final isMajor = i % 10 == 0;
      final isHalf = i % 5 == 0;

      final tickLength = isMajor
          ? 10.0
          : isHalf
              ? 6.0
              : 3.5;

      canvas.drawLine(
        Offset(x, rulerY),
        Offset(x, rulerY + tickLength),
        tickPaint,
      );

      // Major Number Labels (0, 1, 2, 3...)
      if (isMajor) {
        final label = (i ~/ 10).toString();

        final textPainter = TextPainter(
          text: TextSpan(
            text: label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );

        textPainter.layout();

        textPainter.paint(
          canvas,
          Offset(
            x - textPainter.width / 2,
            rulerY + 12,
          ),
        );
      }
    }
  }

  void _drawLiveArcTrace(Canvas canvas) {
    final radius = (pencilTip - needleTip).distance;

    final arcPaint = Paint()
      ..color = const Color(0xFF09B7F5)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final startAngle = liveSweepAngle > 0 ? -liveSweepAngle : 0.0;
    final sweep = liveSweepAngle > 0 ? liveSweepAngle : liveSweepAngle;

    canvas.drawArc(
      Rect.fromCircle(center: needleTip, radius: radius),
      startAngle,
      sweep,
      false,
      arcPaint,
    );

    // 1. Draw dashed radius line from needle tip (center) to pencil tip
    final radiusLinePaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    _drawDashedLine(canvas, needleTip, pencilTip, radiusLinePaint);

    // 2. Draw live radius and angle badge
    final radiusCm = radius / pxPerCm;
    final degrees = (liveSweepAngle.abs() * 180 / pi).round().clamp(0, 360);
    final labelText = 'r = ${radiusCm.toStringAsFixed(1)} cm ($degrees°)';

    final textPainter = TextPainter(
      text: TextSpan(
        text: labelText,
        style: const TextStyle(
          color: Colors.cyanAccent,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    final midX = (needleTip.dx + pencilTip.dx) / 2;
    final midY = rulerY - 20;

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(midX, midY),
        width: textPainter.width + 14,
        height: textPainter.height + 6,
      ),
      const Radius.circular(8),
    );


    canvas.drawRRect(
      bgRect,
      Paint()..color = const Color(0xEE0F172A),
    );

    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = Colors.cyanAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    textPainter.paint(
      canvas,
      Offset(midX - textPainter.width / 2, midY - textPainter.height / 2),
    );
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const dashWidth = 4.0;
    const dashSpace = 3.0;
    double distance = (p2 - p1).distance;
    if (distance == 0) return;

    double dx = (p2.dx - p1.dx) / distance;
    double dy = (p2.dy - p1.dy) / distance;

    double current = 0.0;
    while (current < distance) {
      final start = Offset(p1.dx + dx * current, p1.dy + dy * current);
      current = min(current + dashWidth, distance);
      final end = Offset(p1.dx + dx * current, p1.dy + dy * current);
      canvas.drawLine(start, end, paint);
      current += dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _CompassPainter oldDelegate) {
    return oldDelegate.spreadAngle != spreadAngle ||
        oldDelegate.needleTip != needleTip ||
        oldDelegate.pencilTip != pencilTip ||
        oldDelegate.isDrawing != isDrawing ||
        oldDelegate.liveSweepAngle != liveSweepAngle;
  }
}
