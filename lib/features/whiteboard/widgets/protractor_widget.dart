import 'dart:math';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Result of pressing the angle draw buttons (dynamic or presets).
/// ALL points are in GLOBAL (screen) coordinates. Convert them to your canvas
/// space with `canvasBox.globalToLocal(p)` and add them as normal pen strokes.
class ProtractorAngleShape {
  final int degrees;
  final Offset vertex;

  /// End of the base ray (zero side) and of the arm ray.
  final Offset baseEnd;
  final Offset armEnd;

  /// Pen-ready, densely sampled polyline: baseEnd -> vertex -> armEnd
  /// (the angle itself, drawn as ONE stroke).
  final List<Offset> strokePoints;

  /// Optional second stroke: square corner for 90°, small arc for other angles.
  final List<Offset> markerPoints;


  const ProtractorAngleShape({
    required this.degrees,
    required this.vertex,
    required this.baseEnd,
    required this.armEnd,
    required this.strokePoints,
    required this.markerPoints,
  });
}

/// Shared geometry (measured from the protractor's own top-left). Compact size.
class _G {
  static const double w = 320.0; // total width
  static const double r = 160.0; // outer radius of the half-disc
  static const double strip = 42.0; // toolbar strip under the baseline
  static const double h = r + strip; // total height
  static const Offset c = Offset(w / 2, r); // vertex
  static const double scaleR = 142.0; // outer scale radius
  static const double innerR = 112.0; // inner scale radius
  static const double wedgeR = 85.0; // filled wedge radius
  static const double gripR = 60.0; // arm grip distance from vertex
}

/// Point at distance [r] from [c] at angle [theta] (radians) from the zero side (right).
Offset _polar(Offset c, double r, double theta) {
  return Offset(c.dx + r * cos(theta), c.dy - r * sin(theta));
}

/// Points from [a] to [b] (inclusive), roughly every [step] px.
List<Offset> _line(Offset a, Offset b, {double step = 4.0}) {
  final n = max(1, ((b - a).distance / step).ceil());
  return [for (int i = 0; i <= n; i++) Offset.lerp(a, b, i / n)!];
}

Path _bodyPath() {
  final disc = Path()
    ..moveTo(0, _G.r)
    ..arcTo(Rect.fromCircle(center: _G.c, radius: _G.r), pi, pi, false)
    ..close();
  final base = Path()
    ..addRRect(RRect.fromLTRBAndCorners(
      0,
      _G.r - 0.5,
      _G.w,
      _G.h,
      bottomLeft: const Radius.circular(12),
      bottomRight: const Radius.circular(12),
    ));
  return Path.combine(PathOperation.union, disc, base);
}

class ProtractorWidget extends StatefulWidget {
  final Offset initialPosition;
  final VoidCallback onClose;

  /// Called when any angle draw button is pressed. Use the points in the
  /// shape to add pen strokes to your canvas.
  final ValueChanged<ProtractorAngleShape>? onDrawAngle;

  /// Length (screen px) of each ray drawn with the pen.
  final double penRayLength;

  const ProtractorWidget({
    super.key,
    required this.initialPosition,
    required this.onClose,
    this.onDrawAngle,
    this.penRayLength = 260.0,
  });

  @override
  State<ProtractorWidget> createState() => _ProtractorWidgetState();
}

class _ProtractorWidgetState extends State<ProtractorWidget> {
  final GlobalKey _bodyKey = GlobalKey();

  late Offset _position;
  double _rotation = 0.0;
  int _deg = 90; // arm angle in whole degrees from the zero side

  Offset _lastGlobal = Offset.zero;
  double _lastPointerAngle = 0.0;

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition;
  }

  // ---------------------------------------------------------------- helpers

  RenderBox? get _bodyBox =>
      _bodyKey.currentContext?.findRenderObject() as RenderBox?;

  /// Whole degrees, with a magnet on 0 / 45 / 90 / 135 / 180.
  int _snapDeg(double deg) {
    for (final m in const [0, 45, 90, 135, 180]) {
      if ((deg - m).abs() <= 2.0) return m;
    }
    return deg.round().clamp(0, 180).toInt();
  }

  void _setArmFromLocal(Offset p) {
    final dx = p.dx - _G.c.dx;
    final dy = _G.c.dy - p.dy;
    double phi = atan2(dy, dx);
    if (phi < 0) phi = dx < 0 ? pi : 0; // below baseline -> nearest side
    setState(() => _deg = _snapDeg(phi * 180 / pi));
  }

  /// Sets the arm to [deg] and hands pen-ready strokes to the host canvas.
  void _drawAngle(int deg) {
    setState(() => _deg = deg);
    final cb = widget.onDrawAngle;
    final box = _bodyBox;
    if (cb == null || box == null) return;

    final theta = deg * pi / 180.0;
    final vertex = box.localToGlobal(_G.c);

    // Unit direction (in screen space) of a ray at angle t from the zero side.
    Offset dirAt(double t) {
      final d = box.localToGlobal(_polar(_G.c, 1, t)) - vertex;
      return d / d.distance;
    }

    final L = widget.penRayLength;
    final baseDir = dirAt(0);
    final armDir = dirAt(theta);
    final baseEnd = vertex + baseDir * L;
    final armEnd = vertex + armDir * L;

    // The angle as one continuous stroke: base end -> vertex -> arm end.
    final stroke = <Offset>[
      ..._line(baseEnd, vertex),
      ..._line(vertex, armEnd).skip(1),
    ];

    // Marker: square corner for 90°, arc for other angles.
    final marker = <Offset>[];
    if (deg == 90) {
      const s = 28.0;
      final p1 = vertex + baseDir * s;
      final p2 = vertex + (baseDir + armDir) * s;
      final p3 = vertex + armDir * s;
      marker
        ..addAll(_line(p1, p2))
        ..addAll(_line(p2, p3).skip(1));
    } else if (deg > 0) {
      const radius = 40.0;
      final n = max(4, (deg / 1.5).ceil());
      for (int i = 0; i <= n; i++) {
        marker.add(vertex + dirAt(theta * i / n) * radius);
      }
    }

    cb(ProtractorAngleShape(
      degrees: deg,
      vertex: vertex,
      baseEnd: baseEnd,
      armEnd: armEnd,
      strokePoints: stroke,
      markerPoints: marker,
    ));
  }

  // Move: use GLOBAL positions so it follows the finger even when rotated.
  void _moveStart(DragStartDetails d) => _lastGlobal = d.globalPosition;

  void _moveUpdate(DragUpdateDetails d) {
    final g = d.globalPosition;
    setState(() => _position += g - _lastGlobal);
    _lastGlobal = g;
  }

  // Rotate around the vertex, following the finger.
  double? _pointerAngle(Offset global) {
    final box = _bodyBox;
    if (box == null) return null;
    final v = box.localToGlobal(_G.c);
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

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final grip = _polar(_G.c, _G.gripR, _deg * pi / 180.0);
    const Color redAccent = Color(0xFFDC2626);

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: Transform(
        origin: _G.c,
        transform: Matrix4.rotationZ(_rotation),
        child: Material(
          color: Colors.transparent,
          child: SizedBox(
            key: _bodyKey,
            width: _G.w,
            height: _G.h,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Body, scales, wedge, rays, markers
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ProtractorPainter(
                      angleDeg: _deg,
                    ),
                  ),
                ),

                // Drag anywhere on the dial to aim the arm
                Positioned.fill(
                  child: ClipPath(
                    clipper: _DiscClipper(),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) => _setArmFromLocal(d.localPosition),
                      onPanStart: (d) => _setArmFromLocal(d.localPosition),
                      onPanUpdate: (d) => _setArmFromLocal(d.localPosition),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),

                // Toolbar strip: drag to move the protractor
                Positioned(
                  left: 0,
                  right: 0,
                  top: _G.r,
                  bottom: 0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: _moveStart,
                    onPanUpdate: _moveUpdate,
                    child: const SizedBox.expand(),
                  ),
                ),

                // Grip indicator line on toolbar
                Positioned(
                  left: _G.w / 2 - 14,
                  bottom: 3,
                  child: IgnorePointer(
                    child: Container(
                      width: 28,
                      height: 3,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                  ),
                ),

                // Arm grip handle (Red dot with icon)
                Positioned(
                  left: grip.dx - 12,
                  top: grip.dy - 12,
                  child: IgnorePointer(
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: redAccent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(LucideIcons.pencil,
                            size: 11, color: Colors.white),
                      ),
                    ),
                  ),
                ),

                // Toolbar: [Close Reset Rotate]  [Dynamic Angle Draw Button]  [∠45° ∠90°]
                Positioned(
                  left: 6,
                  right: 6,
                  top: _G.r + 6,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Action controls
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ActionButton(
                            icon: LucideIcons.x,
                            color: Colors.white,
                            bgColor: const Color(0xFFEF4444),
                            onTap: widget.onClose,
                          ),
                          const SizedBox(width: 4),
                          _ActionButton(
                            icon: LucideIcons.rotateCcw,
                            color: const Color(0xFF334155),
                            onTap: () => setState(() {
                              _deg = 90;
                              _rotation = 0.0;
                            }),
                          ),
                          const SizedBox(width: 4),
                          _ActionButton(
                            icon: LucideIcons.rotateCw,
                            color: const Color(0xFF334155),
                            onPanStart: _rotateStart,
                            onPanUpdate: _rotateUpdate,
                          ),
                        ],
                      ),

                      // Dynamic Angle Draw Button (presses to draw current angle)
                      _DynamicAngleButton(
                        degrees: _deg,
                        onTap: () => _drawAngle(_deg),
                      ),

                      // Static Preset Buttons
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _PresetButton(
                            label: '∠45°',
                            active: _deg == 45,
                            onTap: () => _drawAngle(45),
                          ),
                          const SizedBox(width: 4),
                          _PresetButton(
                            label: '∠90°',
                            active: _deg == 90,
                            onTap: () => _drawAngle(90),
                          ),
                        ],
                      ),
                    ],
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

class _DiscClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, _G.r)
    ..arcTo(Rect.fromCircle(center: _G.c, radius: _G.r), pi, pi, false)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _DynamicAngleButton extends StatelessWidget {
  final int degrees;
  final VoidCallback onTap;

  const _DynamicAngleButton({
    required this.degrees,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFFDC2626); // Red Accent
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: 'Draw $degrees° Angle',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: primary.withValues(alpha: 0.35),
                blurRadius: 4,
                offset: const Offset(0, 1.5),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.pencil, size: 12, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                '∠$degrees°',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _PresetButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFFDC2626); // Red
    const inactiveText = Color(0xFF334155);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? primary : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: active ? primary : const Color(0xFFCBD5E1), width: 1.0),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.08), blurRadius: 3),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : inactiveText,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color? bgColor;
  final VoidCallback? onTap;
  final GestureDragStartCallback? onPanStart;
  final GestureDragUpdateCallback? onPanUpdate;

  const _ActionButton({
    required this.icon,
    required this.color,
    this.bgColor,
    this.onTap,
    this.onPanStart,
    this.onPanUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final Widget child = Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: bgColor ?? Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.0),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.08), blurRadius: 3),
        ],
      ),
      child: Center(child: Icon(icon, size: 14, color: color)),
    );

    if (onPanUpdate != null) {
      return GestureDetector(
        onPanStart: onPanStart,
        onPanUpdate: onPanUpdate,
        child: child,
      );
    }
    return GestureDetector(onTap: onTap, child: child);
  }
}

class _ProtractorPainter extends CustomPainter {
  final int angleDeg;

  const _ProtractorPainter({
    required this.angleDeg,
  });

  static const Color _redAccent = Color(0xFFDC2626);

  @override
  void paint(Canvas canvas, Size size) {
    final c = _G.c;
    final theta = angleDeg * pi / 180.0;
    final body = _bodyPath();

    // --- Body (Clean White Disc) ---------------------------------------------
    canvas.drawShadow(body, Colors.black.withValues(alpha: 0.25), 6, true);
    canvas.drawPath(
        body, Paint()..color = Colors.white.withValues(alpha: 0.96));

    canvas.save();
    canvas.clipPath(body);
    canvas.drawRect(
      Rect.fromLTWH(0, _G.r, _G.w, _G.strip),
      Paint()..color = const Color(0xFFF8FAFC),
    );
    canvas.restore();

    // Body outline
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFFCBD5E1),
    );
    // Baseline line
    canvas.drawLine(
      Offset(0, c.dy),
      Offset(_G.w, c.dy),
      Paint()
        ..color = const Color(0xFFCBD5E1)
        ..strokeWidth = 1.0,
    );

    // --- Scale arcs & ticks --------------------------------------------------
    final paintTick = Paint()
      ..color = const Color(0xFF475569)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    final paintArc = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawArc(Rect.fromCircle(center: c, radius: _G.scaleR), 0, -pi,
        false, paintArc);
    canvas.drawArc(Rect.fromCircle(center: c, radius: _G.innerR), 0, -pi,
        false, paintArc);

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (int angle = 0; angle <= 180; angle++) {
      final rad = angle * pi / 180.0;
      final bool isMajor = angle % 10 == 0;
      final bool isMedium = angle % 5 == 0;

      final double outerLen = isMajor ? 12.0 : (isMedium ? 8.0 : 5.0);
      canvas.drawLine(
        _polar(c, _G.scaleR, rad),
        _polar(c, _G.scaleR - outerLen, rad),
        paintTick,
      );

      final double innerLen = isMajor ? 8.0 : 4.0;
      canvas.drawLine(
        _polar(c, _G.innerR, rad),
        _polar(c, _G.innerR - innerLen, rad),
        paintTick,
      );

      if (isMajor) {
        // Outer scale numbers: 0 -> 180
        _paintNumber(
          canvas,
          textPainter,
          '$angle',
          _polar(c, _G.scaleR - 20, rad),
          pi / 2 - rad,
          const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 8.5,
              fontWeight: FontWeight.bold),
        );

        // Inner scale numbers: 180 -> 0
        _paintNumber(
          canvas,
          textPainter,
          '${180 - angle}',
          _polar(c, _G.innerR - 16, rad),
          pi / 2 - rad,
          const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 7.5,
              fontWeight: FontWeight.w600),
        );
      }
    }

    // --- Red Measurement Line & Angle Shape ----------------------------------
    final wedgeBase = _polar(c, _G.wedgeR, 0);
    final wedge = Path()
      ..moveTo(c.dx, c.dy)
      ..lineTo(wedgeBase.dx, wedgeBase.dy)
      ..arcTo(Rect.fromCircle(center: c, radius: _G.wedgeR), 0, -theta, false)
      ..close();
    canvas.drawPath(wedge, Paint()..color = _redAccent.withValues(alpha: 0.15));

    final markerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeJoin = StrokeJoin.miter
      ..color = _redAccent;

    if (angleDeg == 90) {
      final u = _polar(c, 1, 0) - c;
      final v = _polar(c, 1, theta) - c;
      const double s = 20.0;
      final p1 = c + u * s;
      final p2 = c + (u + v) * s;
      final p3 = c + v * s;
      canvas.drawPath(
        Path()
          ..moveTo(p1.dx, p1.dy)
          ..lineTo(p2.dx, p2.dy)
          ..lineTo(p3.dx, p3.dy),
        markerPaint,
      );
    } else if (angleDeg > 0) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: 26), 0, -theta,
          false, markerPaint);
    }

    // Red lines for base ray and arm ray
    final rayPaint = Paint()
      ..color = _redAccent
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c, _polar(c, _G.scaleR, 0), rayPaint);
    canvas.drawLine(c, _polar(c, _G.scaleR, theta), rayPaint);

    // Vertex point
    canvas.drawCircle(c, 4.0, Paint()..color = _redAccent);
    canvas.drawCircle(c, 1.6, Paint()..color = Colors.white);
  }

  void _paintNumber(Canvas canvas, TextPainter tp, String text, Offset at,
      double rotation, TextStyle style) {
    tp.text = TextSpan(text: text, style: style);
    tp.layout();
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(rotation);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ProtractorPainter old) =>
      old.angleDeg != angleDeg;
}
