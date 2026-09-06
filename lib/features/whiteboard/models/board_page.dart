import 'board_element.dart';

class BoardPage {
  final String id;
  final List<BoardElement> elements;

  BoardPage({
    required this.id,
    required this.elements,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'elements': elements.map((e) => e.toJson()).toList(),
      };

  factory BoardPage.fromJson(Map<String, dynamic> json) {
    return BoardPage(
      id: json['id'],
      elements: (json['elements'] as List)
          .map((e) => BoardElement.fromJson(e))
          .toList(),
    );
  }
}
