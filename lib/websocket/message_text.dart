import 'dart:convert';

/// Normaliza um payload do WebSocket para texto (frames binários em UTF-8).
String? messageAsText(Object? message) {
  if (message is String) return message;
  if (message is List<int>) return utf8.decode(message, allowMalformed: true);
  return null;
}
