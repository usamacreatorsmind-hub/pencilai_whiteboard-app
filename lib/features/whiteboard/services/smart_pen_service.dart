import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/stroke_element.dart';


/// Represents an AI/AutoDraw suggested smart object candidate
class SmartPenCandidate {
  final String id;
  final String name;
  final CustomPainter Function(Color color) painterBuilder;

  SmartPenCandidate({
    required this.id,
    required this.name,
    required this.painterBuilder,
  });

  /// Renders this candidate to a high-resolution transparent PNG file on disk
  Future<String> renderToImageFile(Color color, Size size) async {
    final tempDir = await getTemporaryDirectory();
    final fileName =
        'smart_obj_${id}_${color.toARGB32()}_${DateTime.now().microsecondsSinceEpoch}.png';
    final filePath = '${tempDir.path}/$fileName';
    final file = File(filePath);

    // High-resolution scale for super crisp vector quality
    const double pixelRatio = 3.0;
    final int renderWidth = (size.width * pixelRatio).toInt().clamp(120, 1024);
    final int renderHeight = (size.height * pixelRatio).toInt().clamp(
      120,
      1024,
    );

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, renderWidth.toDouble(), renderHeight.toDouble()),
    );
    canvas.scale(renderWidth / size.width, renderHeight / size.height);

    final painter = painterBuilder(color);
    painter.paint(canvas, size);

    final picture = recorder.endRecording();
    final image = await picture.toImage(renderWidth, renderHeight);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();

    await file.writeAsBytes(bytes);
    return filePath;
  }
}

/// Service that classifies handwritten doodles and provides matching SmartPen objects
class SmartPenService {
  static final SmartPenService _instance = SmartPenService._internal();
  factory SmartPenService() => _instance;
  SmartPenService._internal();

  /// Analyzes stroke geometry and returns 8 matching candidate objects
  List<SmartPenCandidate> getCandidatesForStroke(StrokeElement stroke) {
    if (stroke.isDotOrTap) return [];
    final points = stroke.points;
    if (points.length < 5) return [];

    final bounds = stroke.getRawBounds();
    final double width = bounds.width;
    final double height = bounds.height;
    final double longest = max(width, height);
    if (longest < 5) return _getCircleCandidates();

    // 1. Calculate Centroid
    double sumX = 0;
    double sumY = 0;
    for (final p in points) {
      sumX += p.dx;
      sumY += p.dy;
    }
    final centroid = Offset(sumX / points.length, sumY / points.length);

    // 2. Calculate Radii from centroid
    final radii = points.map((p) => (p - centroid).distance).toList();
    final double meanRadius = radii.reduce((a, b) => a + b) / radii.length;

    // Variance & coefficient of variation
    double variance = 0;
    for (final r in radii) {
      variance += (r - meanRadius) * (r - meanRadius);
    }
    variance /= radii.length;
    final double stdDev = sqrt(variance);
    final double radiusCoeffVar = meanRadius > 0 ? (stdDev / meanRadius) : 1.0;

    // Start-to-end distance (is it closed?)
    final double startEndDist = (points.first - points.last).distance;
    final bool isNearClosed = startEndDist < longest * 0.45;

    // Count sharp directional changes (corners)
    int corners = 0;
    const int step = 3;
    if (points.length >= step * 2 + 1) {
      for (int i = step; i < points.length - step; i += step) {
        final v1 = points[i] - points[i - step];
        final v2 = points[i + step] - points[i];
        final double angle1 = v1.direction;
        final double angle2 = v2.direction;
        double diff = (angle1 - angle2).abs();
        if (diff > pi) diff = 2 * pi - diff;
        if (diff > 0.8) corners++;
      }
    }

    // Classification Decision Tree:
    // A. Circle / Ellipse / Round object (Like user's reference image!)
    if ((radiusCoeffVar < 0.32 && isNearClosed) || (radiusCoeffVar < 0.25)) {
      return _getCircleCandidates();
    }

    // B. Triangle / Triangular Wedge
    if (corners == 3 || (!isNearClosed && corners >= 2 && corners <= 4)) {
      return _getTriangleCandidates();
    }

    // C. Star / Sparkle
    if (corners >= 5 && isNearClosed) {
      return _getStarCandidates();
    }

    // D. Rectangle / Box
    if (corners == 4 ||
        (width > 20 &&
            height > 20 &&
            (width / height > 1.5 || height / width > 1.5))) {
      return _getRectangleCandidates();
    }

    // Default to the reference circular & popular set
    return _getCircleCandidates();
  }

  // --- CANDIDATE SETS ---

  List<SmartPenCandidate> _getCircleCandidates() {
    return [
      SmartPenCandidate(
        id: 'basketball',
        name: 'Basketball',
        painterBuilder: (c) => BasketballPainter(color: c),
      ),
      SmartPenCandidate(
        id: 'volleyball',
        name: 'Volleyball',
        painterBuilder: (c) => VolleyballPainter(color: c),
      ),
      SmartPenCandidate(
        id: 'circle',
        name: 'Circle',
        painterBuilder: (c) => PerfectCirclePainter(color: c),
      ),
      SmartPenCandidate(
        id: 'ship_wheel',
        name: 'Lifebuoy / Wheel',
        painterBuilder: (c) => ShipWheelPainter(color: c),
      ),
      SmartPenCandidate(
        id: 'steering_wheel',
        name: 'Steering Wheel',
        painterBuilder: (c) => SteeringWheelPainter(color: c),
      ),
      SmartPenCandidate(
        id: 'watermelon_bite',
        name: 'Watermelon Slice',
        painterBuilder: (c) => WatermelonBitePainter(color: c),
      ),
      SmartPenCandidate(
        id: 'watermelon_crescent',
        name: 'Watermelon Crescent',
        painterBuilder: (c) => WatermelonCrescentPainter(color: c),
      ),
      SmartPenCandidate(
        id: 'watermelon_triangle',
        name: 'Watermelon Wedge',
        painterBuilder: (c) => WatermelonTrianglePainter(color: c),
      ),
    ];
  }

  List<SmartPenCandidate> _getTriangleCandidates() {
    return [
      SmartPenCandidate(
        id: 'watermelon_triangle',
        name: 'Watermelon Wedge',
        painterBuilder: (c) => WatermelonTrianglePainter(color: c),
      ),
      SmartPenCandidate(
        id: 'pizza',
        name: 'Pizza Slice',
        painterBuilder: (c) => PizzaSlicePainter(color: c),
      ),
      SmartPenCandidate(
        id: 'triangle',
        name: 'Triangle',
        painterBuilder: (c) => TrianglePainter(color: c),
      ),
      SmartPenCandidate(
        id: 'star',
        name: 'Star',
        painterBuilder: (c) => StarPainter(color: c),
      ),
      SmartPenCandidate(
        id: 'house',
        name: 'House',
        painterBuilder: (c) => HousePainter(color: c),
      ),
      SmartPenCandidate(
        id: 'tree',
        name: 'Tree',
        painterBuilder: (c) => TreePainter(color: c),
      ),
      SmartPenCandidate(
        id: 'arrow',
        name: 'Arrow',
        painterBuilder: (c) => ArrowPainter(color: c),
      ),
      SmartPenCandidate(
        id: 'watermelon_bite',
        name: 'Watermelon Slice',
        painterBuilder: (c) => WatermelonBitePainter(color: c),
      ),
    ];
  }

  List<SmartPenCandidate> _getStarCandidates() {
    return [
      SmartPenCandidate(
        id: 'star',
        name: 'Star',
        painterBuilder: (c) => StarPainter(color: c),
      ),
      SmartPenCandidate(
        id: 'sparkles',
        name: 'Sparkles',
        painterBuilder: (c) => SparklesPainter(color: c),
      ),
      SmartPenCandidate(
        id: 'sun',
        name: 'Sun',
        painterBuilder: (c) => SunPainter(color: c),
      ),
      SmartPenCandidate(
        id: 'flower',
        name: 'Flower',
        painterBuilder: (c) => FlowerPainter(color: c),
      ),
      SmartPenCandidate(
        id: 'heart',
        name: 'Heart',
        painterBuilder: (c) => HeartPainter(color: c),
      ),
      SmartPenCandidate(
        id: 'smile',
        name: 'Smile',
        painterBuilder: (c) => SmilePainter(color: c),
      ),
      SmartPenCandidate(
        id: 'circle',
        name: 'Circle',
        painterBuilder: (c) => PerfectCirclePainter(color: c),
      ),
      SmartPenCandidate(
        id: 'basketball',
        name: 'Basketball',
        painterBuilder: (c) => BasketballPainter(color: c),
      ),
    ];
  }

  List<SmartPenCandidate> _getRectangleCandidates() {
    return [
      SmartPenCandidate(
        id: 'rectangle',
        name: 'Rectangle',
        painterBuilder: (c) => RectanglePainter(color: c),
      ),
      SmartPenCandidate(
        id: 'book',
        name: 'Book',
        painterBuilder: (c) => BookPainter(color: c),
      ),
      SmartPenCandidate(
        id: 'house',
        name: 'House',
        painterBuilder: (c) => HousePainter(color: c),
      ),
      SmartPenCandidate(
        id: 'car',
        name: 'Car',
        painterBuilder: (c) => CarPainter(color: c),
      ),
      SmartPenCandidate(
        id: 'cloud',
        name: 'Cloud',
        painterBuilder: (c) => CloudPainter(color: c),
      ),
      SmartPenCandidate(
        id: 'lightbulb',
        name: 'Lightbulb',
        painterBuilder: (c) => LightbulbPainter(color: c),
      ),
      SmartPenCandidate(
        id: 'clock',
        name: 'Clock',
        painterBuilder: (c) => ClockPainter(color: c),
      ),
      SmartPenCandidate(
        id: 'steering_wheel',
        name: 'Steering Wheel',
        painterBuilder: (c) => SteeringWheelPainter(color: c),
      ),
    ];
  }
}

// ==========================================
// VECTOR CLIPART PAINTERS (Matching Reference UI)
// ==========================================

/// 1. Basketball (Outer circle with standard basketball curved seams)
class BasketballPainter extends CustomPainter {
  final Color color;
  BasketballPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.05).clamp(2.0, 6.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) * 0.44;

    // Outer circle
    canvas.drawCircle(center, radius, stroke);

    // Center vertical and horizontal lines
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      stroke,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      stroke,
    );

    // Left curved rib
    final leftPath = Path()
      ..moveTo(center.dx - radius * 0.7, center.dy - radius * 0.7)
      ..quadraticBezierTo(
        center.dx - radius * 0.25,
        center.dy,
        center.dx - radius * 0.7,
        center.dy + radius * 0.7,
      );
    canvas.drawPath(leftPath, stroke);

    // Right curved rib
    final rightPath = Path()
      ..moveTo(center.dx + radius * 0.7, center.dy - radius * 0.7)
      ..quadraticBezierTo(
        center.dx + radius * 0.25,
        center.dy,
        center.dx + radius * 0.7,
        center.dy + radius * 0.7,
      );
    canvas.drawPath(rightPath, stroke);
  }

  @override
  bool shouldRepaint(covariant BasketballPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 2. Volleyball (3-section curved seams)
class VolleyballPainter extends CustomPainter {
  final Color color;
  VolleyballPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.05).clamp(2.0, 6.0)
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) * 0.44;

    canvas.drawCircle(center, radius, stroke);

    // Three curved radial ribbons
    for (int i = 0; i < 3; i++) {
      final double angle = i * 2 * pi / 3;
      final start = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );
      final control = Offset(
        center.dx + radius * 0.4 * cos(angle + pi / 3),
        center.dy + radius * 0.4 * sin(angle + pi / 3),
      );
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..quadraticBezierTo(control.dx, control.dy, start.dx, start.dy);
      canvas.drawPath(path, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant VolleyballPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 3. Perfect Circle
class PerfectCirclePainter extends CustomPainter {
  final Color color;
  PerfectCirclePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.05).clamp(2.0, 6.0);

    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) * 0.44;
    canvas.drawCircle(center, radius, stroke);
  }

  @override
  bool shouldRepaint(covariant PerfectCirclePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 4. Ship Wheel / Lifebuoy
class ShipWheelPainter extends CustomPainter {
  final Color color;
  ShipWheelPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.05).clamp(2.0, 6.0)
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final outerR = min(size.width, size.height) * 0.42;
    final innerR = outerR * 0.55;

    // Outer & inner rings
    canvas.drawCircle(center, outerR, stroke);
    canvas.drawCircle(center, innerR, stroke);

    // 4 spokes (horizontal, vertical, diagonal)
    for (int i = 0; i < 4; i++) {
      final double angle = i * pi / 4;
      final p1 = Offset(
        center.dx + outerR * cos(angle),
        center.dy + outerR * sin(angle),
      );
      final p2 = Offset(
        center.dx - outerR * cos(angle),
        center.dy - outerR * sin(angle),
      );
      canvas.drawLine(p1, p2, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant ShipWheelPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 5. Steering Wheel
class SteeringWheelPainter extends CustomPainter {
  final Color color;
  SteeringWheelPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.05).clamp(2.0, 6.0)
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) * 0.44;
    final hubR = radius * 0.32;

    // Rim & Hub
    canvas.drawCircle(center, radius, stroke);
    canvas.drawCircle(center, hubR, stroke);

    // 3 spokes: Left, Right, Bottom
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx - hubR, center.dy),
      stroke,
    );
    canvas.drawLine(
      Offset(center.dx + hubR, center.dy),
      Offset(center.dx + radius, center.dy),
      stroke,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy + hubR),
      Offset(center.dx, center.dy + radius),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant SteeringWheelPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 6. Watermelon Slice with Bite Mark
class WatermelonBitePainter extends CustomPainter {
  final Color color;
  WatermelonBitePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.05).clamp(2.0, 6.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    // Semicircle wedge with bite mark on top
    final path = Path()
      ..moveTo(w * 0.15, h * 0.45)
      // Top line with a bite scallop
      ..lineTo(w * 0.40, h * 0.45)
      ..arcToPoint(
        Offset(w * 0.60, h * 0.45),
        radius: Radius.circular(w * 0.10),
        clockwise: false,
      )
      ..lineTo(w * 0.85, h * 0.45)
      // Bottom curved rind
      ..arcToPoint(
        Offset(w * 0.15, h * 0.45),
        radius: Radius.circular(w * 0.42),
        clockwise: true,
      );

    canvas.drawPath(path, stroke);

    // Small seed dots
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.32, h * 0.58), w * 0.025, fill);
    canvas.drawCircle(Offset(w * 0.50, h * 0.64), w * 0.025, fill);
    canvas.drawCircle(Offset(w * 0.68, h * 0.58), w * 0.025, fill);
  }

  @override
  bool shouldRepaint(covariant WatermelonBitePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 7. Crescent Watermelon Slice
class WatermelonCrescentPainter extends CustomPainter {
  final Color color;
  WatermelonCrescentPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.05).clamp(2.0, 6.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(w * 0.15, h * 0.35)
      ..quadraticBezierTo(w * 0.5, h * 0.90, w * 0.85, h * 0.35)
      ..quadraticBezierTo(w * 0.5, h * 0.70, w * 0.15, h * 0.35);

    canvas.drawPath(path, stroke);

    final fill = Paint()..color = color;
    canvas.drawCircle(Offset(w * 0.38, h * 0.52), w * 0.025, fill);
    canvas.drawCircle(Offset(w * 0.50, h * 0.58), w * 0.025, fill);
    canvas.drawCircle(Offset(w * 0.62, h * 0.52), w * 0.025, fill);
  }

  @override
  bool shouldRepaint(covariant WatermelonCrescentPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 8. Watermelon Triangle / Wedge
class WatermelonTrianglePainter extends CustomPainter {
  final Color color;
  WatermelonTrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.05).clamp(2.0, 6.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(w * 0.5, h * 0.15)
      ..lineTo(w * 0.85, h * 0.78)
      ..quadraticBezierTo(w * 0.5, h * 0.88, w * 0.15, h * 0.78)
      ..close();

    canvas.drawPath(path, stroke);

    // Seed dots
    final fill = Paint()..color = color;
    canvas.drawCircle(Offset(w * 0.50, h * 0.42), w * 0.025, fill);
    canvas.drawCircle(Offset(w * 0.42, h * 0.58), w * 0.025, fill);
    canvas.drawCircle(Offset(w * 0.58, h * 0.58), w * 0.025, fill);
    canvas.drawCircle(Offset(w * 0.50, h * 0.70), w * 0.025, fill);
  }

  @override
  bool shouldRepaint(covariant WatermelonTrianglePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Pizza Slice
class PizzaSlicePainter extends CustomPainter {
  final Color color;
  PizzaSlicePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.05).clamp(2.0, 6.0)
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(w * 0.5, h * 0.85)
      ..lineTo(w * 0.2, h * 0.22)
      ..quadraticBezierTo(w * 0.5, h * 0.14, w * 0.8, h * 0.22)
      ..close();

    canvas.drawPath(path, stroke);

    // Pepperoni circles
    final dot = Paint()..color = color;
    canvas.drawCircle(Offset(w * 0.5, h * 0.38), w * 0.04, dot);
    canvas.drawCircle(Offset(w * 0.38, h * 0.55), w * 0.035, dot);
    canvas.drawCircle(Offset(w * 0.60, h * 0.55), w * 0.035, dot);
  }

  @override
  bool shouldRepaint(covariant PizzaSlicePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Star
class StarPainter extends CustomPainter {
  final Color color;
  StarPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.05).clamp(2.0, 6.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final center = Offset(size.width / 2, size.height / 2);
    final outerR = min(size.width, size.height) * 0.44;
    final innerR = outerR * 0.42;

    final path = Path();
    for (int i = 0; i < 10; i++) {
      final double r = i.isEven ? outerR : innerR;
      final double angle = -pi / 2 + i * pi / 5;
      final pt = Offset(center.dx + r * cos(angle), center.dy + r * sin(angle));
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant StarPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Sparkles
class SparklesPainter extends CustomPainter {
  final Color color;
  SparklesPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.05).clamp(2.0, 6.0)
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width * 0.5, size.height * 0.5);
    final r = min(size.width, size.height) * 0.40;

    // 4-point star sparkle
    final path = Path()
      ..moveTo(center.dx, center.dy - r)
      ..quadraticBezierTo(center.dx, center.dy, center.dx + r, center.dy)
      ..quadraticBezierTo(center.dx, center.dy, center.dx, center.dy + r)
      ..quadraticBezierTo(center.dx, center.dy, center.dx - r, center.dy)
      ..quadraticBezierTo(center.dx, center.dy, center.dx, center.dy - r);
    canvas.drawPath(path, stroke);

    // Two small accent sparkles
    final fill = Paint()..color = color;
    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.22),
      size.width * 0.03,
      fill,
    );
    canvas.drawCircle(
      Offset(size.width * 0.20, size.height * 0.78),
      size.width * 0.025,
      fill,
    );
  }

  @override
  bool shouldRepaint(covariant SparklesPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Triangle
class TrianglePainter extends CustomPainter {
  final Color color;
  TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.05).clamp(2.0, 6.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(size.width * 0.5, size.height * 0.15)
      ..lineTo(size.width * 0.88, size.height * 0.85)
      ..lineTo(size.width * 0.12, size.height * 0.85)
      ..close();
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant TrianglePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Rectangle
class RectanglePainter extends CustomPainter {
  final Color color;
  RectanglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.05).clamp(2.0, 6.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.76,
      height: size.height * 0.76,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.width * 0.08)),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant RectanglePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Heart
class HeartPainter extends CustomPainter {
  final Color color;
  HeartPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.05).clamp(2.0, 6.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(w * 0.5, h * 0.32)
      ..cubicTo(w * 0.45, h * 0.12, w * 0.12, h * 0.14, w * 0.14, h * 0.46)
      ..cubicTo(w * 0.16, h * 0.68, w * 0.42, h * 0.82, w * 0.5, h * 0.90)
      ..cubicTo(w * 0.58, h * 0.82, w * 0.84, h * 0.68, w * 0.86, h * 0.46)
      ..cubicTo(w * 0.88, h * 0.14, w * 0.55, h * 0.12, w * 0.5, h * 0.32);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant HeartPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Smile
class SmilePainter extends CustomPainter {
  final Color color;
  SmilePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.05).clamp(2.0, 6.0)
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final r = min(size.width, size.height) * 0.44;

    canvas.drawCircle(center, r, stroke);

    // Eyes
    final fill = Paint()..color = color;
    canvas.drawCircle(
      Offset(center.dx - r * 0.35, center.dy - r * 0.2),
      r * 0.09,
      fill,
    );
    canvas.drawCircle(
      Offset(center.dx + r * 0.35, center.dy - r * 0.2),
      r * 0.09,
      fill,
    );

    // Smile arc
    final smilePath = Path()
      ..moveTo(center.dx - r * 0.45, center.dy + r * 0.12)
      ..quadraticBezierTo(
        center.dx,
        center.dy + r * 0.55,
        center.dx + r * 0.45,
        center.dy + r * 0.12,
      );
    canvas.drawPath(smilePath, stroke);
  }

  @override
  bool shouldRepaint(covariant SmilePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Flower
class FlowerPainter extends CustomPainter {
  final Color color;
  FlowerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.05).clamp(2.0, 6.0)
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final centerR = min(size.width, size.height) * 0.15;
    final petalR = min(size.width, size.height) * 0.18;
    final dist = min(size.width, size.height) * 0.26;

    // 5 petals
    for (int i = 0; i < 5; i++) {
      final double a = i * 2 * pi / 5 - pi / 2;
      canvas.drawCircle(
        Offset(center.dx + dist * cos(a), center.dy + dist * sin(a)),
        petalR,
        stroke,
      );
    }
    // Center ring
    canvas.drawCircle(center, centerR, stroke);
  }

  @override
  bool shouldRepaint(covariant FlowerPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Tree
class TreePainter extends CustomPainter {
  final Color color;
  TreePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.05).clamp(2.0, 6.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    // Trunk
    canvas.drawLine(
      Offset(w * 0.5, h * 0.58),
      Offset(w * 0.5, h * 0.88),
      stroke,
    );

    // Crown (3 leafy puffs)
    canvas.drawCircle(Offset(w * 0.5, h * 0.32), w * 0.22, stroke);
    canvas.drawCircle(Offset(w * 0.36, h * 0.46), w * 0.18, stroke);
    canvas.drawCircle(Offset(w * 0.64, h * 0.46), w * 0.18, stroke);
  }

  @override
  bool shouldRepaint(covariant TreePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Car
class CarPainter extends CustomPainter {
  final Color color;
  CarPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.05).clamp(2.0, 6.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    // Car body silhouette
    final body = Path()
      ..moveTo(w * 0.12, h * 0.65)
      ..lineTo(w * 0.12, h * 0.54)
      ..lineTo(w * 0.28, h * 0.54)
      ..lineTo(w * 0.40, h * 0.35)
      ..lineTo(w * 0.70, h * 0.35)
      ..lineTo(w * 0.84, h * 0.54)
      ..lineTo(w * 0.90, h * 0.54)
      ..lineTo(w * 0.90, h * 0.65)
      ..lineTo(w * 0.78, h * 0.65)
      ..arcToPoint(
        Offset(w * 0.62, h * 0.65),
        radius: Radius.circular(w * 0.08),
        clockwise: false,
      )
      ..lineTo(w * 0.38, h * 0.65)
      ..arcToPoint(
        Offset(w * 0.22, h * 0.65),
        radius: Radius.circular(w * 0.08),
        clockwise: false,
      )
      ..close();
    canvas.drawPath(body, stroke);

    // Wheels
    canvas.drawCircle(Offset(w * 0.30, h * 0.65), w * 0.07, stroke);
    canvas.drawCircle(Offset(w * 0.70, h * 0.65), w * 0.07, stroke);
  }

  @override
  bool shouldRepaint(covariant CarPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// House
class HousePainter extends CustomPainter {
  final Color color;
  HousePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.05).clamp(2.0, 6.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    // Roof triangle
    final roof = Path()
      ..moveTo(w * 0.5, h * 0.18)
      ..lineTo(w * 0.86, h * 0.48)
      ..lineTo(w * 0.14, h * 0.48)
      ..close();
    canvas.drawPath(roof, stroke);

    // Walls
    final walls = Path()
      ..moveTo(w * 0.22, h * 0.48)
      ..lineTo(w * 0.22, h * 0.85)
      ..lineTo(w * 0.78, h * 0.85)
      ..lineTo(w * 0.78, h * 0.48);
    canvas.drawPath(walls, stroke);

    // Door
    final door = Path()
      ..moveTo(w * 0.42, h * 0.85)
      ..lineTo(w * 0.42, h * 0.62)
      ..lineTo(w * 0.58, h * 0.62)
      ..lineTo(w * 0.58, h * 0.85);
    canvas.drawPath(door, stroke);
  }

  @override
  bool shouldRepaint(covariant HousePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Cloud
class CloudPainter extends CustomPainter {
  final Color color;
  CloudPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.05).clamp(2.0, 6.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(w * 0.25, h * 0.65)
      ..arcToPoint(
        Offset(w * 0.22, h * 0.45),
        radius: Radius.circular(w * 0.12),
        clockwise: true,
      )
      ..arcToPoint(
        Offset(w * 0.45, h * 0.32),
        radius: Radius.circular(w * 0.18),
        clockwise: true,
      )
      ..arcToPoint(
        Offset(w * 0.72, h * 0.38),
        radius: Radius.circular(w * 0.16),
        clockwise: true,
      )
      ..arcToPoint(
        Offset(w * 0.82, h * 0.65),
        radius: Radius.circular(w * 0.14),
        clockwise: true,
      )
      ..close();
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant CloudPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Sun
class SunPainter extends CustomPainter {
  final Color color;
  SunPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.05).clamp(2.0, 6.0)
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final coreR = min(size.width, size.height) * 0.24;
    final rayStart = coreR * 1.35;
    final rayEnd = coreR * 1.80;

    canvas.drawCircle(center, coreR, stroke);

    // 8 rays
    for (int i = 0; i < 8; i++) {
      final double a = i * pi / 4;
      final p1 = Offset(
        center.dx + rayStart * cos(a),
        center.dy + rayStart * sin(a),
      );
      final p2 = Offset(
        center.dx + rayEnd * cos(a),
        center.dy + rayEnd * sin(a),
      );
      canvas.drawLine(p1, p2, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant SunPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Lightbulb
class LightbulbPainter extends CustomPainter {
  final Color color;
  LightbulbPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.05).clamp(2.0, 6.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    final bulb = Path()
      ..moveTo(w * 0.38, h * 0.68)
      ..cubicTo(w * 0.20, h * 0.55, w * 0.20, h * 0.25, w * 0.50, h * 0.22)
      ..cubicTo(w * 0.80, h * 0.25, w * 0.80, h * 0.55, w * 0.62, h * 0.68)
      ..lineTo(w * 0.38, h * 0.68);
    canvas.drawPath(bulb, stroke);

    // Base screw lines
    canvas.drawLine(
      Offset(w * 0.40, h * 0.74),
      Offset(w * 0.60, h * 0.74),
      stroke,
    );
    canvas.drawLine(
      Offset(w * 0.42, h * 0.80),
      Offset(w * 0.58, h * 0.80),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant LightbulbPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Book
class BookPainter extends CustomPainter {
  final Color color;
  BookPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.05).clamp(2.0, 6.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    // Open book pages
    final path = Path()
      ..moveTo(w * 0.5, h * 0.78)
      ..quadraticBezierTo(w * 0.3, h * 0.70, w * 0.14, h * 0.74)
      ..lineTo(w * 0.14, h * 0.32)
      ..quadraticBezierTo(w * 0.3, h * 0.28, w * 0.5, h * 0.36)
      ..quadraticBezierTo(w * 0.7, h * 0.28, w * 0.86, h * 0.32)
      ..lineTo(w * 0.86, h * 0.74)
      ..quadraticBezierTo(w * 0.7, h * 0.70, w * 0.5, h * 0.78);
    canvas.drawPath(path, stroke);
    canvas.drawLine(
      Offset(w * 0.5, h * 0.36),
      Offset(w * 0.5, h * 0.78),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant BookPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Arrow
class ArrowPainter extends CustomPainter {
  final Color color;
  ArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.05).clamp(2.0, 6.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    // Arrow shaft
    canvas.drawLine(
      Offset(w * 0.15, h * 0.5),
      Offset(w * 0.80, h * 0.5),
      stroke,
    );

    // Arrow head
    final head = Path()
      ..moveTo(w * 0.58, h * 0.30)
      ..lineTo(w * 0.85, h * 0.50)
      ..lineTo(w * 0.58, h * 0.70);
    canvas.drawPath(head, stroke);
  }

  @override
  bool shouldRepaint(covariant ArrowPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Clock
class ClockPainter extends CustomPainter {
  final Color color;
  ClockPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.05).clamp(2.0, 6.0)
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final r = min(size.width, size.height) * 0.44;

    canvas.drawCircle(center, r, stroke);

    // Hands: Hour pointing up-right, minute pointing straight up
    canvas.drawLine(center, Offset(center.dx, center.dy - r * 0.65), stroke);
    canvas.drawLine(
      center,
      Offset(center.dx + r * 0.45, center.dy - r * 0.20),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant ClockPainter oldDelegate) =>
      oldDelegate.color != color;
}
