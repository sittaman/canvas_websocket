import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:local_websocket/local_websocket.dart';
import 'package:websocket_demo/websocket/message_text.dart';

/// Owns the WebSocket server instance and exposes its live state.
///
/// This object lives above the widget tree (see [DrawingApp]), so the server
/// keeps running when the server modal is closed, and any UI can observe
/// [isRunning] and [clients] without touching the underlying socket server.
class WebsocketServer extends ChangeNotifier {
  Server? _server;
  StreamSubscription<Set<Client>>? _clientsSubscription;
  StreamSubscription<dynamic>? _messageSubscription;
  final _messagesController = StreamController<String>.broadcast();

  List<Client> _clients = const [];
  List<String> _lanAddresses = const [];
  bool _isStarting = false;
  bool _isStopping = false;
  bool _disposed = false;
  String? _host;
  int? _port;
  String? _lastError;

  /// Whether the server is currently listening.
  bool get isRunning => _server != null;

  /// Whether a start operation is in progress.
  bool get isStarting => _isStarting;

  /// Whether a stop operation is in progress.
  bool get isStopping => _isStopping;

  /// Whether a start/stop transition is in progress.
  bool get isBusy => _isStarting || _isStopping;

  /// Snapshot of the currently connected clients.
  List<Client> get clients => List<Client>.unmodifiable(_clients);

  /// Host the server is listening on, or `null` when stopped.
  String? get host => _host;

  /// Port the server is listening on, or `null` when stopped.
  int? get port => _port;

  /// IPv4 addresses clients on the local network can use to reach the server.
  List<String> get lanAddresses => List<String>.unmodifiable(_lanAddresses);

  /// Message describing the last start failure, if any.
  String? get lastError => _lastError;

  /// Text messages received from connected clients.
  Stream<String> get messageStream => _messagesController.stream;

  /// Starts the server on [host]:[port].
  ///
  /// Returns `true` when the server started listening. On failure the error is
  /// exposed through [lastError] and this returns `false`.
  Future<bool> start(String host, int port) async {
    if (isRunning || isBusy) return false;

    _isStarting = true;
    _lastError = null;
    _notify();

    final server = Server(
      echo: false, // Broadcast mode
      details: {
        'name': 'Local Websocket',
        'description': 'Flutter WebSocket Server',
        'version': '1.0.0',
        'platform': 'Flutter',
        'authEnabled': false,
        'validationEnabled': false,
      },
    );

    try {
      await server.start(host, port: port);

      // The app may have been torn down while binding the socket.
      if (_disposed) {
        await server.dispose();
        return false;
      }

      final lanAddresses = await _resolveLanAddresses(
        host,
      ).timeout(const Duration(seconds: 2), onTimeout: () => const <String>[]);
      if (_disposed) {
        await server.dispose();
        return false;
      }

      _server = server;
      _host = host;
      _port = port;
      _lanAddresses = lanAddresses;
      _clients = server.clients.toList(growable: false);

      _clientsSubscription = server.clientsStream.listen((clients) {
        _clients = clients.toList(growable: false);
        _notify();
      });

      _messageSubscription = server.messageStream.listen((message) {
        final text = messageAsText(message);
        if (text != null) _messagesController.add(text);
      });

      return true;
    } catch (error) {
      _lastError = 'Falha ao iniciar o servidor em $host:$port: $error';
      try {
        await server.dispose();
      } catch (disposeError) {
        debugPrint('Error disposing failed server: $disposeError');
      }
      return false;
    } finally {
      _isStarting = false;
      _notify();
    }
  }

  /// Stops the server and disconnects every client.
  Future<void> stop() async {
    if (!isRunning || isBusy) return;

    _isStopping = true;
    _notify();

    final server = _server;
    _server = null;
    _host = null;
    _port = null;
    _lanAddresses = const [];
    _clients = const [];

    final subscription = _clientsSubscription;
    _clientsSubscription = null;
    final messageSubscription = _messageSubscription;
    _messageSubscription = null;

    try {
      await subscription?.cancel();
      await messageSubscription?.cancel();
      await server?.dispose();
    } catch (error) {
      debugPrint('Error stopping server: $error');
    } finally {
      _isStopping = false;
      _notify();
    }
  }

  /// Sends [message] to every connected client. No-op when the server is down.
  void broadcastMessage(String message) {
    _server?.send(message);
  }

  /// Resolves the addresses a client on the same network can dial.
  ///
  /// When bound to `0.0.0.0`/`::`, every non-loopback IPv4 interface is listed.
  Future<List<String>> _resolveLanAddresses(String host) async {
    final normalized = host.trim();
    if (normalized.isEmpty) return const [];

    if (normalized != '0.0.0.0' && normalized != '::') {
      return [normalized];
    }

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final addresses = <String>{};
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.type == InternetAddressType.IPv4) {
            addresses.add(address.address);
          }
        }
      }
      return addresses.toList(growable: false);
    } catch (error) {
      debugPrint('Error listing network interfaces: $error');
      return const [];
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;

    final server = _server;
    _server = null;
    _clients = const [];
    _lanAddresses = const [];

    _clientsSubscription?.cancel();
    _clientsSubscription = null;
    _messageSubscription?.cancel();
    _messageSubscription = null;

    if (server != null) unawaited(server.dispose());
    unawaited(_messagesController.close());

    super.dispose();
  }
}
