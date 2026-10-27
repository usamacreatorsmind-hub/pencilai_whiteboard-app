import 'package:flutter/material.dart';
import 'board_element.dart';

class DocumentElement extends BoardElement {
  final String filePath;
  final String fileName;
  Size size;
  final String? remotePreviewUrl;

  DocumentElement({
    required super.id,
    required super.position,
    required this.filePath,
    required this.fileName,
    required this.size,
    this.remotePreviewUrl,
    super.rotation,
    super.scale,
    super.docPage,
  });


  @override
  Map<String, dynamic> toJson() => {
    'type': 'document',
    'id': id,
    'position': {'dx': position.dx, 'dy': position.dy},
    'rotation': rotation,
    'scale': scale,
    'docPage': docPage,
    'filePath': filePath,
    'fileName': fileName,
    'size': {'width': size.width, 'height': size.height},
    'remotePreviewUrl': remotePreviewUrl,
  };

  factory DocumentElement.fromJson(Map<String, dynamic> json) {
    return DocumentElement(
      id: json['id'],
      position: Offset(json['position']['dx'], json['position']['dy']),
      rotation: json['rotation']?.toDouble() ?? 0.0,
      scale: json['scale']?.toDouble() ?? 1.0,
      docPage: json['docPage'],
      filePath: json['filePath'],
      fileName: json['fileName'],
      size: Size(json['size']['width'], json['size']['height']),
      remotePreviewUrl: json['remotePreviewUrl'],
    );
  }

  @override
  DocumentElement copyWith({
    String? id,
    Offset? position,
    double? rotation,
    double? scale,
    int? docPage,
    String? filePath,
    String? fileName,
    Size? size,
    String? remotePreviewUrl,
  }) {
    return DocumentElement(
      id: id ?? this.id,
      position: position ?? this.position,
      rotation: rotation ?? this.rotation,
      scale: scale ?? this.scale,
      docPage: docPage ?? this.docPage,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      size: size ?? this.size,
      remotePreviewUrl: remotePreviewUrl ?? this.remotePreviewUrl,
    );
  }
}
