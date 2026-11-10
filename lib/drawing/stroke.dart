import 'dart:ui';

/// Um traço completo: vários pontos + cor + espessura.
class Stroke {
  Stroke({
    required this.id,
    required this.color,
    required this.width,
    Iterable<Offset> points = const [],
  }) : points = List<Offset>.of(points);

  final String id;
  final Color color;
  final double width;
  final List<Offset> points;
}
