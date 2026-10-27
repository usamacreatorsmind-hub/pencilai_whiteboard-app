import 'package:flutter/material.dart';
import 'board_element.dart';

class ImageElement extends BoardElement {
  final String imageUrl;
  Size size;
  final bool isTransparent;
  final bool isDocumentSlide;
  final bool isSmartPen;

  ImageElement({
    required super.id,
    required super.position,
    required this.imageUrl,
    required this.size,
    super.rotation,
    super.scale,
    super.docPage,
    this.isTransparent = false,
    this.isDocumentSlide = false,
    this.isSmartPen = false,
  });

  bool get isDocumentOrSlide =>
      isDocumentSlide ||
      imageUrl.contains('slide_') ||
      imageUrl.toLowerCase().endsWith('.pdf') ||
      imageUrl.toLowerCase().endsWith('.ppt') ||
      imageUrl.toLowerCase().endsWith('.pptx');

  @override
  Map<String, dynamic> toJson() => {
    'type': 'image',
    'id': id,
    'position': {'dx': position.dx, 'dy': position.dy},
    'rotation': rotation,
    'scale': scale,
    'docPage': docPage,
    'imageUrl': imageUrl,
    'size': {'width': size.width, 'height': size.height},
    'isTransparent': isTransparent,
    'isDocumentSlide': isDocumentSlide,
    'isSmartPen': isSmartPen,
  };

  factory ImageElement.fromJson(Map<String, dynamic> json) {
    return ImageElement(
      id: json['id'],
      position: Offset(json['position']['dx'], json['position']['dy']),
      rotation: json['rotation']?.toDouble() ?? 0.0,
      scale: json['scale']?.toDouble() ?? 1.0,
      docPage: json['docPage'],
      imageUrl: json['imageUrl'],
      size: Size(json['size']['width'], json['size']['height']),
      isTransparent: json['isTransparent'] ?? false,
      isDocumentSlide: json['isDocumentSlide'] ?? false,
      isSmartPen: json['isSmartPen'] ?? false,
    );
  }

  @override
  ImageElement copyWith({
    String? id,
    Offset? position,
    double? rotation,
    double? scale,
    int? docPage,
    String? imageUrl,
    Size? size,
    bool? isTransparent,
    bool? isDocumentSlide,
    bool? isSmartPen,
  }) {
    return ImageElement(
      id: id ?? this.id,
      position: position ?? this.position,
      rotation: rotation ?? this.rotation,
      scale: scale ?? this.scale,
      docPage: docPage ?? this.docPage,
      imageUrl: imageUrl ?? this.imageUrl,
      size: size ?? this.size,
      isTransparent: isTransparent ?? this.isTransparent,
      isDocumentSlide: isDocumentSlide ?? this.isDocumentSlide,
      isSmartPen: isSmartPen ?? this.isSmartPen,
    );
  }
}
