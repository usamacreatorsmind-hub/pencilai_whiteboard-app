import 'package:flutter/material.dart';
import 'board_element.dart';

enum ShapeType { line, rectangle, circle, arrow, triangle, star }

class ShapeElement extends BoardElement {
  final ShapeType shapeType;
  Offset endPoint;
  final Color color;
  final double strokeWidth;
  final bool showDimensions;

  ShapeElement({
    required super.id,
    required super.position,
    required this.shapeType,
    required this.endPoint,
    required this.color,
    required this.strokeWidth,
    this.showDimensions = true,
    super.rotation,
    super.scale,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'shape',
        'id': id,
        'position': {'dx': position.dx, 'dy': position.dy},
        'rotation': rotation,
        'scale': scale,
        'shapeType': shapeType.name,
        'endPoint': {'dx': endPoint.dx, 'dy': endPoint.dy},
        'color': color.value,
        'strokeWidth': strokeWidth,
        'showDimensions': showDimensions,
      };

  factory ShapeElement.fromJson(Map<String, dynamic> json) {
    return ShapeElement(
      id: json['id'],
      position: Offset(json['position']['dx'], json['position']['dy']),
      rotation: json['rotation']?.toDouble() ?? 0.0,
      scale: json['scale']?.toDouble() ?? 1.0,
      shapeType: ShapeType.values.byName(json['shapeType']),
      endPoint: Offset(json['endPoint']['dx'], json['endPoint']['dy']),
      color: Color(json['color']),
      strokeWidth: json['strokeWidth'].toDouble(),
      showDimensions: json['showDimensions'] ?? true,
    );
  }

  @override
  ShapeElement copyWith({
    String? id,
    Offset? position,
    double? rotation,
    double? scale,
    ShapeType? shapeType,
    Offset? endPoint,
    Color? color,
    double? strokeWidth,
    bool? showDimensions,
  }) {
    return ShapeElement(
      id: id ?? this.id,
      position: position ?? this.position,
      rotation: rotation ?? this.rotation,
      scale: scale ?? this.scale,
      shapeType: shapeType ?? this.shapeType,
      endPoint: endPoint ?? this.endPoint,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      showDimensions: showDimensions ?? this.showDimensions,
    );
  }
}
