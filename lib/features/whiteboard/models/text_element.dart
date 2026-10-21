import 'package:flutter/material.dart';
import 'board_element.dart';

class TextElement extends BoardElement {
  final String text;
  final Color color;
  double fontSize;
  Size size;
  final String fontFamily;

  TextElement({
    required super.id,
    required super.position,
    required this.text,
    required this.color,
    required this.fontSize,
    required this.size,
    this.fontFamily = 'Roboto',
    super.rotation,
    super.scale,
    super.docPage,
  });

  /// Computes the exact layout size of the text as rendered on the whiteboard
  Size computeActualSize() {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          fontFamily: fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return textPainter.size;
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'text',
    'id': id,
    'position': {'dx': position.dx, 'dy': position.dy},
    'rotation': rotation,
    'scale': scale,
    'docPage': docPage,
    'text': text,
    'color': color.value,
    'fontSize': fontSize,
    'size': {'width': size.width, 'height': size.height},
    'fontFamily': fontFamily,
  };

  factory TextElement.fromJson(Map<String, dynamic> json) {
    return TextElement(
      id: json['id'],
      position: Offset(json['position']['dx'], json['position']['dy']),
      rotation: json['rotation']?.toDouble() ?? 0.0,
      scale: json['scale']?.toDouble() ?? 1.0,
      docPage: json['docPage'],
      text: json['text'],
      color: Color(json['color']),
      fontSize: json['fontSize']?.toDouble() ?? 24.0,
      size: Size(
        json['size']['width']?.toDouble() ?? 100.0,
        json['size']['height']?.toDouble() ?? 40.0,
      ),
      fontFamily: json['fontFamily'] ?? 'Roboto',
    );
  }

  @override
  TextElement copyWith({
    String? id,
    Offset? position,
    double? rotation,
    double? scale,
    int? docPage,
    String? text,
    Color? color,
    double? fontSize,
    Size? size,
    String? fontFamily,
  }) {
    return TextElement(
      id: id ?? this.id,
      position: position ?? this.position,
      rotation: rotation ?? this.rotation,
      scale: scale ?? this.scale,
      docPage: docPage ?? this.docPage,
      text: text ?? this.text,
      color: color ?? this.color,
      fontSize: fontSize ?? this.fontSize,
      size: size ?? this.size,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }
}
