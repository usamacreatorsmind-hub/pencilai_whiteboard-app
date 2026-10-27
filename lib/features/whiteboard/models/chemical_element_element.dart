import 'package:flutter/material.dart';
import 'board_element.dart';
import 'chemical_element.dart';

class ChemicalElementElement extends BoardElement {
  final int atomicNumber;
  final String symbol;
  final String name;
  final String atomicMass;
  final String category;
  final Color color;
  final String electronConfiguration;
  final String state;
  Size size;


  ChemicalElementElement({
    required super.id,
    required super.position,
    required this.atomicNumber,
    required this.symbol,
    required this.name,
    required this.atomicMass,
    required this.category,
    required this.color,
    required this.electronConfiguration,
    required this.state,
    Size? size,
    super.rotation,
    super.scale,
    super.docPage,
  }) : size = size ?? const Size(150.0, 175.0);

  factory ChemicalElementElement.fromChemicalElement(
    ChemicalElement element, {
    required String id,
    required Offset position,
    double rotation = 0.0,
    double scale = 1.0,
    int? docPage,
    Size? size,
  }) {
    return ChemicalElementElement(
      id: id,
      position: position,
      atomicNumber: element.atomicNumber,
      symbol: element.symbol,
      name: element.name,
      atomicMass: element.atomicMass,
      category: element.category,
      color: element.categoryColor,
      electronConfiguration: element.electronConfiguration,
      state: element.state,
      rotation: rotation,
      scale: scale,
      docPage: docPage,
      size: size ?? const Size(150.0, 175.0),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'chemical_element',
    'id': id,
    'position': {'dx': position.dx, 'dy': position.dy},
    'rotation': rotation,
    'scale': scale,
    'docPage': docPage,
    'width': size.width,
    'height': size.height,
    'atomicNumber': atomicNumber,
    'symbol': symbol,
    'name': name,
    'atomicMass': atomicMass,
    'category': category,
    'color': color.toARGB32(),
    'electronConfiguration': electronConfiguration,
    'state': state,
  };

  factory ChemicalElementElement.fromJson(Map<String, dynamic> json) {
    return ChemicalElementElement(
      id: json['id'] as String,
      position: Offset(
        (json['position']['dx'] as num).toDouble(),
        (json['position']['dy'] as num).toDouble(),
      ),
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      docPage: json['docPage'] as int?,
      size: Size(
        (json['width'] as num?)?.toDouble() ?? 150.0,
        (json['height'] as num?)?.toDouble() ?? 175.0,
      ),
      atomicNumber: json['atomicNumber'] as int? ?? 1,
      symbol: json['symbol'] as String? ?? 'H',
      name: json['name'] as String? ?? 'Hydrogen',
      atomicMass: json['atomicMass'] as String? ?? '1.008',
      category: json['category'] as String? ?? 'Reactive Nonmetal',
      color: Color(json['color'] as int? ?? 0xFF10B981),
      electronConfiguration: json['electronConfiguration'] as String? ?? '1s¹',
      state: json['state'] as String? ?? 'Gas',
    );
  }

  @override
  ChemicalElementElement copyWith({
    String? id,
    Offset? position,
    double? rotation,
    double? scale,
    int? docPage,
    int? atomicNumber,
    String? symbol,
    String? name,
    String? atomicMass,
    String? category,
    Color? color,
    String? electronConfiguration,
    String? state,
    Size? size,
  }) {
    final copy = ChemicalElementElement(
      id: id ?? this.id,
      position: position ?? this.position,
      rotation: rotation ?? this.rotation,
      scale: scale ?? this.scale,
      docPage: docPage ?? this.docPage,
      atomicNumber: atomicNumber ?? this.atomicNumber,
      symbol: symbol ?? this.symbol,
      name: name ?? this.name,
      atomicMass: atomicMass ?? this.atomicMass,
      category: category ?? this.category,
      color: color ?? this.color,
      electronConfiguration:
          electronConfiguration ?? this.electronConfiguration,
      state: state ?? this.state,
      size: size ?? this.size,
    );
    return copy;
  }
}
