import 'dart:math';
import 'package:flutter/material.dart';
import 'stroke_element.dart';
import 'shape_element.dart';
import 'image_element.dart';

abstract class BoardElement {
  final String id;
  Offset position;
  double rotation;
  double scale;

  BoardElement({
    required this.id,
    required this.position,
    this.rotation = 0.0,
    this.scale = 1.0,
  });

  Map<String, dynamic> toJson();

  factory BoardElement.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    switch (type) {
      case 'stroke':
        return StrokeElement.fromJson(json);
      case 'shape':
        return ShapeElement.fromJson(json);
      case 'image':
        return ImageElement.fromJson(json);
      default:
        throw Exception('Unknown BoardElement type: $type');
    }
  }

  BoardElement copyWith({
    String? id,
    Offset? position,
    double? rotation,
    double? scale,
  });

  Rect getRawBounds() {
    if (this is StrokeElement) {
      final points = (this as StrokeElement).points;
      if (points.isEmpty) return Rect.fromLTWH(position.dx, position.dy, 0, 0);
      double minX = points[0].dx;
      double maxX = points[0].dx;
      double minY = points[0].dy;
      double maxY = points[0].dy;
      for (var p in points) {
        minX = min(minX, p.dx);
        maxX = max(maxX, p.dx);
        minY = min(minY, p.dy);
        maxY = max(maxY, p.dy);
      }
      return Rect.fromLTRB(minX, minY, maxX, maxY);
    } else if (this is ShapeElement) {
      final shape = this as ShapeElement;
      return Rect.fromPoints(shape.position, shape.endPoint);
    } else if (this is ImageElement) {
      final img = this as ImageElement;
      return Rect.fromLTWH(img.position.dx, img.position.dy, img.size.width, img.size.height);
    }
    return Rect.fromLTWH(position.dx, position.dy, 100, 100);
  }
}
