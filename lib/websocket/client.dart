import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:local_websocket/local_websocket.dart';
import 'package:websocket_demo/websocket/message_text.dart';

/// Owns the WebSocket client connection and exposes its live state.
///
/// Like [WebsocketServer], this object lives above the widget tree (see
/// [DrawingApp]), so the connection survives the client modal being closed.
class WebsocketClient extends ChangeNotifier {
  /// [recordMessage] decides whether a received message is kept in [messages]
  /// (the chat history). Every message still goes through [messageStream].
  WebsocketClient({this.recordMessage});

  final bool Function(String message)? recordMessage;

  Client? _client;
  StreamSubscription<ClientConnectionStatus>? _statusSubscription;
  StreamSubscription<dynamic>? _messageSubscription;
  final _messagesController = StreamController<String>.broadcast();

  ClientConnectionStatus _status = ClientConnectionStatus.disconnected;
  final List<String> _messages = [];
  bool _isStarting = false;
  bool _disposed = false;
  String? _host;
  int? _port;
  String? _username;
  String? _lastError;

  /// Current connection status.
  ClientConnectionStatus get status => _status;

  /// Whether the client has an established connection.
  bool get isConnected => _status == ClientConnectionStatus.connected;

  /// Whether an initial connection attempt is in progress.
  bool get isConnecting =>
      _isStarting || _status == ClientConnectionStatus.connecting;

  /// Messages received from the server, oldest first.
  List<String> get messages => List<String>.unmodifiable(_messages);

  /// Host of the current/last connection attempt.
  String? get host => _host;

  /// Port of the current/last connection attempt.
  int? get port => _port;

  /// Username registered while connected.
  String? get username => _username;

  /// Server-generated identifier for the current connection.
  String? get clientId => _client?.uid;

  /// Message describing the last connection failure, if any.
  String? get lastError => _lastError;

  /// Text messages received from the server.
  Stream<String> get messageStream => _messagesController.stream;

  /// Connects to `ws://[host]:[port]/ws`.
  ///
  /// Returns `true` when the connection is established. On failure the error
  /// is exposed through [lastError] and this returns `false`.
  Future<bool> connect({
    required String host,
    required int port,
    required String username,
  }) async {
    if (isConnected || isConnecting) return false;

    _isStarting = true;
    _lastError = null;
    _messages.clear();
    _host = host;
    _port = port;
    _username = username;
    _status = ClientConnectionStatus.connecting;
    _notify();

    // Discard a stale client left behind by exhausted reconnection attempts.
    await _releaseClient();

    final client = Client(
      details: {
        'username': username,
        'device': 'Flutter App',
        'platform': 'Mobile',
      },
      clientReconnectionDelegate: ExponentialBackoffReconnect(
        maxAttempts: 5,
        initialDelay: const Duration(seconds: 1),
        maxDelay: const Duration(seconds: 30),
      ),
    );

    _client = client;
    _statusSubscription = client.connectionStream.listen((status) {
      _status = status;
      _notify();
    });
    _messageSubscription = client.messageStream.listen((message) {
      final text = messageAsText(message);
      if (text == null) return;

      _messagesController.add(text);
      if (recordMessage?.call(text) ?? true) {
        _messages.add(text);
        if (_messages.length > 100) _messages.removeAt(0);
        _notify();
      }
    });

    try {
      await client.connect('ws://$host:$port/ws');

      // Keep the snapshot in sync even before the status stream event arrives.
      _status = client.connectionStatus;

      // The app may have been torn down while connecting.
      if (_disposed) {
        await _releaseClient();
        return false;
      }

      return true;
    } catch (error) {
      _lastError = 'Falha ao conectar em $host:$port: $error';
      await _releaseClient();
      _status = ClientConnectionStatus.disconnected;
      return false;
    } finally {
      _isStarting = false;
      _notify();
    }
  }

  /// Closes the connection and stops automatic reconnection.
  Future<void> disconnect() async {
    if (_client == null) return;

    await _releaseClient();
    _status = ClientConnectionStatus.disconnected;
    _host = null;
    _port = null;
    _username = null;
    _lastError = null;
    _notify();
  }

  /// Sends a plain text [message]. Returns `false` when not connected.
  bool sendText(String message) {
    if (message.isEmpty) return false;
    return _send(message);
  }

  /// Sends [message] as a JSON chat payload. Returns `false` when not connected.
  bool sendJson(String message) {
    if (message.isEmpty) return false;
    return _send(
      jsonEncode({
        'type': 'chat',
        'user': _username,
        'message': message,
        'timestamp': DateTime.now().toIso8601String(),
      }),
    );
  }

  bool _send(String message) {
    final client = _client;
    if (client == null || !client.isConnected) return false;

    try {
      client.send(message);
      return true;
    } catch (error) {
      _lastError = 'Falha ao enviar mensagem: $error';
      _notify();
      return false;
    }
  }

  Future<void> _releaseClient() async {
    final client = _client;
    _client = null;

    final statusSubscription = _statusSubscription;
    _statusSubscription = null;
    final messageSubscription = _messageSubscription;
    _messageSubscription = null;

    await statusSubscription?.cancel();
    await messageSubscription?.cancel();

    if (client == null) return;
    try {
      await client.dispose();
    } catch (error) {
      debugPrint('Error disposing client: $error');
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;

    final client = _client;
    _client = null;

    _statusSubscription?.cancel();
    _statusSubscription = null;
    _messageSubscription?.cancel();
    _messageSubscription = null;

    if (client != null) unawaited(client.dispose());
    unawaited(_messagesController.close());

    super.dispose();
  }
}
