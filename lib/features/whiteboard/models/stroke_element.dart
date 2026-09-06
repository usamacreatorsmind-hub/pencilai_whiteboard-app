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
      points: (json['points'] as List)
          .map((p) => Offset(p['dx'], p['dy']))
          .toList(),
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
