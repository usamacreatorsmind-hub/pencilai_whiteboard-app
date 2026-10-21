import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'board_element.dart';

enum PenType { pen, fountainPen, brush, marker }

class StrokeElement extends BoardElement {
  final List<Offset> points;
  Color color;
  double strokeWidth;
  PenType penType;

  StrokeElement({
    required super.id,
    required super.position,
    required this.points,
    required this.color,
    required this.strokeWidth,
    this.penType = PenType.pen,
    super.rotation,
    super.scale,
    super.docPage,
  });

  void updateStyling({Color? newColor, double? newStrokeWidth, PenType? newPenType}) {
    if (newColor != null) color = newColor;
    if (newStrokeWidth != null) strokeWidth = newStrokeWidth;
    if (newPenType != null) penType = newPenType;
    invalidatePath();
  }

  Path? _cachedPath;
  List<double>? _cachedWidths;
  Offset? predictedTip;

  List<ui.Picture>? _liveChunkPictures;
  int _bakedChunkPointCount = 0;

  List<ui.Picture>? get liveChunkPictures => _liveChunkPictures;
  int get bakedChunkPointCount => _bakedChunkPointCount;

  void addLiveChunkPicture(ui.Picture picture, int pointCount) {
    _liveChunkPictures ??= [];
    _liveChunkPictures!.add(picture);
    _bakedChunkPointCount += pointCount;
  }

  void disposeLive() {
    if (_liveChunkPictures != null) {
      for (var pic in _liveChunkPictures!) {
        pic.dispose();
      }
      _liveChunkPictures = null;
    }
    _bakedChunkPointCount = 0;
  }

  List<double> get cachedWidths {
    if (_cachedWidths == null || _cachedWidths!.length != points.length) {
      _recomputeWidths();
    }
    return _cachedWidths!;
  }

  void _recomputeWidths() {
    final n = points.length;
    if (n == 0) {
      _cachedWidths = <double>[];
      return;
    }
    _cachedWidths = List<double>.filled(n, strokeWidth, growable: true);
    if (penType == PenType.fountainPen && n >= 2) {
      const double nibAngle = -0.610865; // -35 degrees in radians
      for (var i = 0; i < n; i++) {
        double dx = 0.0;
        double dy = 0.0;
        if (i == 0) {
          dx = points[1].dx - points[0].dx;
          dy = points[1].dy - points[0].dy;
        } else if (i == n - 1) {
          dx = points[n - 1].dx - points[n - 2].dx;
          dy = points[n - 1].dy - points[n - 2].dy;
        } else {
          dx = points[i + 1].dx - points[i - 1].dx;
          dy = points[i + 1].dy - points[i - 1].dy;
        }

        final double angle = atan2(dy, dx);
        final double angleDiff = (sin(angle - nibAngle)).abs();

        // Refined smooth interpolation for both thin and thick sides (using threshold response curve)
        // Thin side (angleDiff near 0): graceful thin stroke (0.4x)
        // Thick side (angleDiff near 1): bold rich thick stroke (1.5x)
        final double smoothFactor = 0.4 + 1.1 * pow(angleDiff, 1.3);
        _cachedWidths![i] = strokeWidth * smoothFactor.clamp(0.3, 2.2);
      }

      // Multi-pass weighted smoothing for buttery smooth thin-to-thick and thick-to-thin transitions
      for (int pass = 0; pass < 2; pass++) {
        final tempWidths = List<double>.from(_cachedWidths!);
        for (var i = 1; i < n - 1; i++) {
          _cachedWidths![i] = (tempWidths[i - 1] + tempWidths[i] * 2.0 + tempWidths[i + 1]) / 4.0;
        }
      }
    }
  }

  void _appendWidthForNewPoint() {
    final n = points.length;
    if (n == 0) return;
    if (_cachedWidths == null || _cachedWidths!.length != n - 1) {
      _recomputeWidths();
      return;
    }
    if (_cachedWidths!.isEmpty) {
      _cachedWidths!.add(strokeWidth);
      return;
    }

    if (penType == PenType.fountainPen && n >= 2) {
      const double nibAngle = -0.610865;
      final pPrev = points[n - 2];
      final pCurr = points[n - 1];
      final dx = pCurr.dx - pPrev.dx;
      final dy = pCurr.dy - pPrev.dy;
      final double angle = atan2(dy, dx);
      final double angleDiff = (sin(angle - nibAngle)).abs();
      final double smoothFactor = 0.4 + 1.1 * pow(angleDiff, 1.3);
      final double rawW = strokeWidth * smoothFactor.clamp(0.3, 2.2);
      final double prevW = _cachedWidths!.last;
      // Weighted blending for real-time live smoothness on both sides
      _cachedWidths!.add(prevW * 0.35 + rawW * 0.65);
    } else {
      _cachedWidths!.add(strokeWidth);
    }
  }

  Path get path {
    if (_cachedPath != null) return _cachedPath!;
    _rebuildFullPath();
    return _cachedPath!;
  }

  void _rebuildFullPath() {
    _cachedPath = Path();
    if (points.length >= 2) {
      _cachedPath!.moveTo(points[0].dx, points[0].dy);
      final mid0 = Offset((points[0].dx + points[1].dx) / 2, (points[0].dy + points[1].dy) / 2);
      _cachedPath!.lineTo(mid0.dx, mid0.dy);

      for (var i = 1; i < points.length - 1; i++) {
        final p1 = points[i];
        final p2 = points[i + 1];
        final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        _cachedPath!.quadraticBezierTo(p1.dx, p1.dy, mid.dx, mid.dy);
      }
      _cachedPath!.lineTo(points.last.dx, points.last.dy);
    } else if (points.isNotEmpty) {
      _cachedPath!.moveTo(points[0].dx, points[0].dy);
    }
  }

  bool addPoint(Offset p) {
    if (points.isNotEmpty) {
      final last = points.last;
      final dx = p.dx - last.dx;
      final dy = p.dy - last.dy;
      // Filter out duplicate hardware events (< 0.2px squared distance)
      if (dx * dx + dy * dy < 0.2) return false;
    }

    points.add(p);
    _appendWidthForNewPoint();

    // O(1) Incremental Path Appending with Quadratic Bezier
    if (_cachedPath == null) {
      _cachedPath = Path()..moveTo(points[0].dx, points[0].dy);
      if (points.length == 2) {
        final mid = Offset((points[0].dx + points[1].dx) / 2, (points[0].dy + points[1].dy) / 2);
        _cachedPath!.lineTo(mid.dx, mid.dy);
      }
    } else if (points.length > 2) {
      final p1 = points[points.length - 2];
      final p2 = points[points.length - 1];
      final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
      _cachedPath!.quadraticBezierTo(p1.dx, p1.dy, mid.dx, mid.dy);
    }
    invalidateBounds();
    return true;
  }

  @override
  void invalidateBounds() {
    super.invalidateBounds();
  }

  @override
  void invalidatePath() {
    _cachedPath = null;
    _cachedWidths = null;
    predictedTip = null;
    disposeLive();
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'stroke',
    'id': id,
    'position': {'dx': position.dx, 'dy': position.dy},
    'rotation': rotation,
    'scale': scale,
    'docPage': docPage,
    'points': points.map((p) => {'dx': p.dx, 'dy': p.dy}).toList(),
    'color': color.value,
    'strokeWidth': strokeWidth,
    'penType': penType.name,
  };

  factory StrokeElement.fromJson(Map<String, dynamic> json) {
    return StrokeElement(
      id: json['id'],
      position: Offset(json['position']['dx'], json['position']['dy']),
      rotation: json['rotation']?.toDouble() ?? 0.0,
      scale: json['scale']?.toDouble() ?? 1.0,
      docPage: json['docPage'],
      points: (json['points'] as List).map((p) => Offset(p['dx'], p['dy'])).toList(),
      color: Color(json['color']),
      strokeWidth: json['strokeWidth'].toDouble(),
      penType: PenType.values.firstWhere((e) => e.name == json['penType'], orElse: () => PenType.pen),
    );
  }

  @override
  StrokeElement copyWith({
    String? id,
    Offset? position,
    double? rotation,
    double? scale,
    int? docPage,
    List<Offset>? points,
    Color? color,
    double? strokeWidth,
    PenType? penType,
  }) {
    return StrokeElement(
      id: id ?? this.id,
      position: position ?? this.position,
      rotation: rotation ?? this.rotation,
      scale: scale ?? this.scale,
      docPage: docPage ?? this.docPage,
      points: points ?? this.points,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      penType: penType ?? this.penType,
    );
  }
}
