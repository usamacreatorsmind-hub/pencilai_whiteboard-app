import 'package:flutter/material.dart';
import 'board_element.dart';

class TableElement extends BoardElement {
  final int rows;
  final int cols;
  Size size;
  final Color color;
  final double strokeWidth;

  TableElement({
    required super.id,
    required super.position,
    required this.rows,
    required this.cols,
    required this.size,
    required this.color,
    required this.strokeWidth,
    super.rotation,
    super.scale,
    super.docPage,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'table',
    'id': id,
    'position': {'dx': position.dx, 'dy': position.dy},
    'rotation': rotation,
    'scale': scale,
    'docPage': docPage,
    'rows': rows,
    'cols': cols,
    'width': size.width,
    'height': size.height,
    'color': color.toARGB32(),
    'strokeWidth': strokeWidth,
  };

  factory TableElement.fromJson(Map<String, dynamic> json) {
    return TableElement(
      id: json['id'],
      position: Offset(json['position']['dx'], json['position']['dy']),
      rotation: json['rotation']?.toDouble() ?? 0.0,
      scale: json['scale']?.toDouble() ?? 1.0,
      docPage: json['docPage'],
      rows: json['rows'] ?? 3,
      cols: json['cols'] ?? 3,
      size: Size(json['width']?.toDouble() ?? 300.0, json['height']?.toDouble() ?? 150.0),
      color: Color(json['color']),
      strokeWidth: json['strokeWidth']?.toDouble() ?? 2.0,
    );
  }

  @override
  TableElement copyWith({
    String? id,
    Offset? position,
    double? rotation,
    double? scale,
    int? docPage,
    int? rows,
    int? cols,
    Size? size,
    Color? color,
    double? strokeWidth,
  }) {
    return TableElement(
      id: id ?? this.id,
      position: position ?? this.position,
      rotation: rotation ?? this.rotation,
      scale: scale ?? this.scale,
      docPage: docPage ?? this.docPage,
      rows: rows ?? this.rows,
      cols: cols ?? this.cols,
      size: size ?? this.size,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
    );
  }
}
