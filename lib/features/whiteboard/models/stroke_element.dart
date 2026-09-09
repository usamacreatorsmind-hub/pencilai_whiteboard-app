import 'package:flutter/material.dart';
import 'board_element.dart';

class StrokeElement extends BoardElement {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;

  StrokeElement({
    required super.id,
    required super.position,
    required this.points,
    required this.color,
    required this.strokeWidth,
    super.rotation,
    super.scale,
  });

  Path? _cachedPath;
  Offset? predictedTip;

  Path get path {
    if (_cachedPath != null) return _cachedPath!;

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
    } else if (points.isNotEmpty) {
      _cachedPath!.moveTo(points[0].dx, points[0].dy);
    }
    return _cachedPath!;
  }

  void addPoint(Offset p) {
    points.add(p);
    if (_cachedPath == null) {
      // Path pehle point se shuru honi chahiye, naye point se nahi
      _cachedPath = Path()..moveTo(points[0].dx, points[0].dy);
      if (points.length == 2) {
        // Agar ye doosra point hai, turant is tak line bhi khींch do
        final mid = Offset((points[0].dx + points[1].dx) / 2, (points[0].dy + points[1].dy) / 2);
        _cachedPath!.lineTo(mid.dx, mid.dy);
      }
    } else if (points.length > 2) {
      final p1 = points[points.length - 2];
      final p2 = points[points.length - 1];
      final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
      _cachedPath!.quadraticBezierTo(p1.dx, p1.dy, mid.dx, mid.dy);
    } else {
      final p1 = points[0];
      final p2 = points[1];
      final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
      _cachedPath!.lineTo(mid.dx, mid.dy);
    }
    invalidateBounds();
  }

  @override
  void invalidateBounds() {
    super.invalidateBounds();
  }

  @override
  void invalidatePath() {
    _cachedPath = null;
    predictedTip = null;
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'stroke',
    'id': id,
    'position': {'dx': position.dx, 'dy': position.dy},
    'rotation': rotation,
    'scale': scale,
    'points': points.map((p) => {'dx': p.dx, 'dy': p.dy}).toList(),
    'color': color.value,
    'strokeWidth': strokeWidth,
  };

  factory StrokeElement.fromJson(Map<String, dynamic> json) {
    return StrokeElement(
      id: json['id'],
      position: Offset(json['position']['dx'], json['position']['dy']),
      rotation: json['rotation']?.toDouble() ?? 0.0,
      scale: json['scale']?.toDouble() ?? 1.0,
      points: (json['points'] as List).map((p) => Offset(p['dx'], p['dy'])).toList(),
      color: Color(json['color']),
      strokeWidth: json['strokeWidth'].toDouble(),
    );
  }

  @override
  StrokeElement copyWith({
    String? id,
    Offset? position,
    double? rotation,
    double? scale,
    List<Offset>? points,
    Color? color,
    double? strokeWidth,
  }) {
    return StrokeElement(
      id: id ?? this.id,
      position: position ?? this.position,
      rotation: rotation ?? this.rotation,
      scale: scale ?? this.scale,
      points: points ?? this.points,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
    );
  }
}
