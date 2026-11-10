import 'dart:convert';
import 'dart:ui';

/// Eventos trocados entre os participantes do canvas via WebSocket.
///
/// Cada evento carrega um [origin] para que o remetente ignore o próprio eco.
sealed class DrawingEvent {
  const DrawingEvent({required this.origin});

  final String origin;

  Map<String, dynamic> toJson();

  String encode() => jsonEncode(toJson());

  /// Converte um payload recebido em [DrawingEvent], ou `null` se não for um
  /// evento de desenho válido (por exemplo, mensagens de chat).
  static DrawingEvent? tryParse(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }

    if (decoded is! Map<String, dynamic>) return null;
    final origin = decoded['origin'];
    if (origin is! String) return null;

    return switch (decoded['type']) {
      StrokeStartEvent.type => StrokeStartEvent.fromJson(decoded, origin),
      StrokePointEvent.type => StrokePointEvent.fromJson(decoded, origin),
      StrokeEndEvent.type => StrokeEndEvent.fromJson(decoded, origin),
      StrokeRemoveEvent.type => StrokeRemoveEvent.fromJson(decoded, origin),
      ClearCanvasEvent.type => ClearCanvasEvent(origin: origin),
      SyncRequestEvent.type => SyncRequestEvent(origin: origin),
      SnapshotEvent.type => SnapshotEvent.fromJson(decoded, origin),
      _ => null,
    };
  }
}

/// Início de um traço, com o primeiro ponto.
final class StrokeStartEvent extends DrawingEvent {
  const StrokeStartEvent({
    required super.origin,
    required this.strokeId,
    required this.color,
    required this.width,
    required this.point,
  });

  static const String type = 'stroke_start';

  final String strokeId;
  final int color;
  final double width;
  final Offset point;

  static StrokeStartEvent? fromJson(Map<String, dynamic> json, String origin) {
    final id = json['id'];
    final color = json['color'];
    final width = json['width'];
    final x = json['x'];
    final y = json['y'];
    if (id is! String ||
        color is! int ||
        width is! num ||
        x is! num ||
        y is! num) {
      return null;
    }

    return StrokeStartEvent(
      origin: origin,
      strokeId: id,
      color: color,
      width: width.toDouble(),
      point: Offset(x.toDouble(), y.toDouble()),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'origin': origin,
    'id': strokeId,
    'color': color,
    'width': width,
    'x': point.dx,
    'y': point.dy,
  };
}

/// Novo ponto adicionado a um traço em andamento.
final class StrokePointEvent extends DrawingEvent {
  const StrokePointEvent({
    required super.origin,
    required this.strokeId,
    required this.point,
  });

  static const String type = 'stroke_point';

  final String strokeId;
  final Offset point;

  static StrokePointEvent? fromJson(Map<String, dynamic> json, String origin) {
    final id = json['id'];
    final x = json['x'];
    final y = json['y'];
    if (id is! String || x is! num || y is! num) return null;

    return StrokePointEvent(
      origin: origin,
      strokeId: id,
      point: Offset(x.toDouble(), y.toDouble()),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'origin': origin,
    'id': strokeId,
    'x': point.dx,
    'y': point.dy,
  };
}

/// Fim de um traço.
final class StrokeEndEvent extends DrawingEvent {
  const StrokeEndEvent({required super.origin, required this.strokeId});

  static const String type = 'stroke_end';

  final String strokeId;

  static StrokeEndEvent? fromJson(Map<String, dynamic> json, String origin) {
    final id = json['id'];
    if (id is! String) return null;
    return StrokeEndEvent(origin: origin, strokeId: id);
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'origin': origin,
    'id': strokeId,
  };
}

/// Remoção de um traço específico (undo).
final class StrokeRemoveEvent extends DrawingEvent {
  const StrokeRemoveEvent({required super.origin, required this.strokeId});

  static const String type = 'stroke_remove';

  final String strokeId;

  static StrokeRemoveEvent? fromJson(Map<String, dynamic> json, String origin) {
    final id = json['id'];
    if (id is! String) return null;
    return StrokeRemoveEvent(origin: origin, strokeId: id);
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'origin': origin,
    'id': strokeId,
  };
}

/// Limpa o canvas de todos os participantes.
final class ClearCanvasEvent extends DrawingEvent {
  const ClearCanvasEvent({required super.origin});

  static const String type = 'clear';

  @override
  Map<String, dynamic> toJson() => {'type': type, 'origin': origin};
}

/// Pede ao host o estado atual do canvas (traços já desenhados).
final class SyncRequestEvent extends DrawingEvent {
  const SyncRequestEvent({required super.origin});

  static const String type = 'sync_request';

  @override
  Map<String, dynamic> toJson() => {'type': type, 'origin': origin};
}

/// Cópia serializável de um traço, usada no snapshot inicial.
final class StrokeSnapshot {
  const StrokeSnapshot({
    required this.id,
    required this.color,
    required this.width,
    required this.points,
  });

  final String id;
  final int color;
  final double width;
  final List<Offset> points;

  Map<String, dynamic> toJson() => {
    'id': id,
    'color': color,
    'width': width,
    'points': [
      for (final point in points) [point.dx, point.dy],
    ],
  };

  static StrokeSnapshot? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = raw['id'];
    final color = raw['color'];
    final width = raw['width'];
    final rawPoints = raw['points'];
    if (id is! String || color is! int || width is! num || rawPoints is! List) {
      return null;
    }

    final points = <Offset>[];
    for (final rawPoint in rawPoints) {
      if (rawPoint is! List || rawPoint.length != 2) return null;
      final x = rawPoint[0];
      final y = rawPoint[1];
      if (x is! num || y is! num) return null;
      points.add(Offset(x.toDouble(), y.toDouble()));
    }

    return StrokeSnapshot(
      id: id,
      color: color,
      width: width.toDouble(),
      points: points,
    );
  }
}

/// Estado completo do canvas enviado a quem acabou de entrar.
final class SnapshotEvent extends DrawingEvent {
  const SnapshotEvent({required super.origin, required this.strokes});

  static const String type = 'snapshot';

  final List<StrokeSnapshot> strokes;

  static SnapshotEvent? fromJson(Map<String, dynamic> json, String origin) {
    final rawStrokes = json['strokes'];
    if (rawStrokes is! List) return null;

    final strokes = <StrokeSnapshot>[];
    for (final raw in rawStrokes) {
      final stroke = StrokeSnapshot.fromJson(raw);
      if (stroke == null) return null;
      strokes.add(stroke);
    }

    return SnapshotEvent(origin: origin, strokes: strokes);
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'origin': origin,
    'strokes': [for (final stroke in strokes) stroke.toJson()],
  };
}
