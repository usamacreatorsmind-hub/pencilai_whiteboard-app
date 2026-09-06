import 'package:flutter/material.dart';
import 'board_element.dart';

class ImageElement extends BoardElement {
  final String imageUrl;
  final Size size;

  ImageElement({required super.id, required super.position, required this.imageUrl, required this.size, super.rotation, super.scale});

  @override
  Map<String, dynamic> toJson() => {
    'type': 'image',
    'id': id,
    'position': {'dx': position.dx, 'dy': position.dy},
    'rotation': rotation,
    'scale': scale,
    'imageUrl': imageUrl,
    'size': {'width': size.width, 'height': size.height},
  };

  factory ImageElement.fromJson(Map<String, dynamic> json) {
    return ImageElement(
      id: json['id'],
      position: Offset(json['position']['dx'], json['position']['dy']),
      rotation: json['rotation']?.toDouble() ?? 0.0,
      scale: json['scale']?.toDouble() ?? 1.0,
      imageUrl: json['imageUrl'],
      size: Size(json['size']['width'], json['size']['height']),
    );
  }

  @override
  ImageElement copyWith({String? id, Offset? position, double? rotation, double? scale, String? imageUrl, Size? size}) {
    return ImageElement(
      id: id ?? this.id,
      position: position ?? this.position,
      rotation: rotation ?? this.rotation,
      scale: scale ?? this.scale,
      imageUrl: imageUrl ?? this.imageUrl,
      size: size ?? this.size,
    );
  }
}
