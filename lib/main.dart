import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:websocket_demo/drawing/drawing_event.dart';
import 'package:websocket_demo/drawing/stroke.dart';
import 'package:websocket_demo/websocket/client.dart';
import 'package:websocket_demo/websocket/client_page.dart';
import 'package:websocket_demo/websocket/server.dart';
import 'package:websocket_demo/websocket/server_page.dart';

void main() {
  runApp(const DrawingApp());
}

class DrawingApp extends StatefulWidget {
  const DrawingApp({super.key});

  @override
  State<DrawingApp> createState() => _DrawingAppState();
}

class _DrawingAppState extends State<DrawingApp> {
  /// Owned here, above the navigation tree, so it outlives every bottom sheet.
  final WebsocketServer _server = WebsocketServer();
  final WebsocketClient _client = WebsocketClient(
    recordMessage: (message) => DrawingEvent.tryParse(message) == null,
  );

  @override
  void dispose() {
    _client.dispose();
    _server.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Canvas Websocket',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: DrawingPage(server: _server, client: _client),
    );
  }
}

class DrawingPage extends StatefulWidget {
  const DrawingPage({super.key, required this.server, required this.client});

  final WebsocketServer server;
  final WebsocketClient client;

  @override
  State<DrawingPage> createState() => _DrawingPageState();
}

class _DrawingPageState extends State<DrawingPage> {
  final List<Stroke> _strokes = [];
  Stroke? _current;
  final Random _random = Random();
  late final String _sessionId = _newId();

  StreamSubscription<String>? _serverMessageSubscription;
  StreamSubscription<String>? _clientMessageSubscription;
  bool _wasClientConnected = false;

  final double _widthSmall = 4.0;
  final double _widthMedium = 8.0;
  final double _widthLarge = 12.0;

  final Color _color = Colors.white70;
  double _width = 4.0;

  @override
  void initState() {
    super.initState();
    _serverMessageSubscription = widget.server.messageStream.listen(
      _handleRemoteMessage,
    );
    _clientMessageSubscription = widget.client.messageStream.listen(
      _handleRemoteMessage,
    );
    _wasClientConnected = widget.client.isConnected;
    widget.client.addListener(_handleClientConnectionChanged);
    if (_wasClientConnected) {
      widget.client.sendText(SyncRequestEvent(origin: _sessionId).encode());
    }
  }

  @override
  void dispose() {
    _serverMessageSubscription?.cancel();
    _clientMessageSubscription?.cancel();
    widget.client.removeListener(_handleClientConnectionChanged);
    super.dispose();
  }

  void _startStroke(Offset p) {
    final stroke = Stroke(
      id: _newId(),
      color: _color,
      width: _width,
      points: [p],
    );
    setState(() => _current = stroke);
    _send(
      StrokeStartEvent(
        origin: _sessionId,
        strokeId: stroke.id,
        color: stroke.color.toARGB32(),
        width: stroke.width,
        point: p,
      ),
    );
  }

  void _extendStroke(Offset p) {
    final current = _current;
    if (current == null) return;
    setState(() => current.points.add(p));
    _send(StrokePointEvent(origin: _sessionId, strokeId: current.id, point: p));
  }

  void _endStroke() {
    final current = _current;
    if (current == null) return;
    setState(() {
      _strokes.add(current);
      _current = null;
    });
    _send(StrokeEndEvent(origin: _sessionId, strokeId: current.id));
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    final removed = _strokes.last;
    setState(() => _strokes.removeLast());
    _send(StrokeRemoveEvent(origin: _sessionId, strokeId: removed.id));
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _current = null;
    });
    _send(ClearCanvasEvent(origin: _sessionId));
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(0x7fffffff)}';

  void _send(DrawingEvent event) {
    final payload = event.encode();
    widget.server.broadcastMessage(payload);
    widget.client.sendText(payload);
  }

  void _handleClientConnectionChanged() {
    final isConnected = widget.client.isConnected;
    if (isConnected && !_wasClientConnected) {
      widget.client.sendText(SyncRequestEvent(origin: _sessionId).encode());
    }
    _wasClientConnected = isConnected;
  }

  void _handleRemoteMessage(String payload) {
    final event = DrawingEvent.tryParse(payload);
    if (event == null || event.origin == _sessionId || !mounted) return;

    switch (event) {
      case StrokeStartEvent start:
        _applyStrokeStart(start);
      case StrokePointEvent point:
        _applyStrokePoint(point);
      case StrokeEndEvent():
        break;
      case StrokeRemoveEvent remove:
        _applyStrokeRemove(remove.strokeId);
      case ClearCanvasEvent():
        setState(() {
          _strokes.clear();
          _current = null;
        });
      case SyncRequestEvent():
        _sendSnapshotIfHost();
      case SnapshotEvent snapshot:
        _applySnapshot(snapshot);
    }
  }

  void _sendSnapshotIfHost() {
    if (!widget.server.isRunning) return;

    final current = _current;
    final strokes = [
      for (final stroke in _strokes)
        StrokeSnapshot(
          id: stroke.id,
          color: stroke.color.toARGB32(),
          width: stroke.width,
          points: List<Offset>.of(stroke.points),
        ),
      if (current != null)
        StrokeSnapshot(
          id: current.id,
          color: current.color.toARGB32(),
          width: current.width,
          points: List<Offset>.of(current.points),
        ),
    ];

    widget.server.broadcastMessage(
      SnapshotEvent(origin: _sessionId, strokes: strokes).encode(),
    );
  }

  void _applySnapshot(SnapshotEvent event) {
    final additions = <Stroke>[];
    for (final snapshot in event.strokes) {
      if (_findStroke(snapshot.id) != null) continue;
      additions.add(
        Stroke(
          id: snapshot.id,
          color: Color(snapshot.color),
          width: snapshot.width,
          points: snapshot.points,
        ),
      );
    }

    if (additions.isEmpty) return;
    setState(() => _strokes.addAll(additions));
  }

  void _applyStrokeStart(StrokeStartEvent event) {
    if (_findStroke(event.strokeId) != null) return;
    setState(() {
      _strokes.add(
        Stroke(
          id: event.strokeId,
          color: Color(event.color),
          width: event.width,
          points: [event.point],
        ),
      );
    });
  }

  void _applyStrokePoint(StrokePointEvent event) {
    final stroke = _findStroke(event.strokeId);
    if (stroke == null) return;
    setState(() => stroke.points.add(event.point));
  }

  void _applyStrokeRemove(String strokeId) {
    final current = _current;
    final removesCurrent = current != null && current.id == strokeId;
    final index = _strokes.indexWhere((stroke) => stroke.id == strokeId);
    if (!removesCurrent && index == -1) return;

    setState(() {
      if (removesCurrent) _current = null;
      if (index != -1) _strokes.removeAt(index);
    });
  }

  Stroke? _findStroke(String strokeId) {
    final current = _current;
    if (current != null && current.id == strokeId) return current;
    for (final stroke in _strokes) {
      if (stroke.id == strokeId) return stroke;
    }
    return null;
  }

  Future<void> showServerModal() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext context) {
        return ServerPage(server: widget.server);
      },
    );
  }

  Future<void> showClientModal() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext context) {
        return ClientPage(client: widget.client);
      },
    );
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  color: Color(0xFF264941),
                  child: Stack(
                    children: [
                      // Camada de desenho
                      Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (e) => _startStroke(e.localPosition),
                        onPointerMove: (e) => _extendStroke(e.localPosition),
                        onPointerUp: (_) => _endStroke(),
                        onPointerCancel: (_) => _endStroke(),
                        child: SizedBox.expand(
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: _DrawingPainter(
                                strokes: _strokes,
                                current: _current,
                              ),
                            ),
                          ),
                        ),
                      ), // Dica exibida quando o canvas está vazi
                    ],
                  ),
                ),
              ),
            ),
          ),
          _buildToolbar(),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    final isEmpty = _strokes.isEmpty && _current == null;

    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<double>(
                    segments: [
                      ButtonSegment(value: _widthSmall, label: const Text('4')),
                      ButtonSegment(
                        value: _widthMedium,
                        label: const Text('8'),
                      ),
                      ButtonSegment(
                        value: _widthLarge,
                        label: const Text('12'),
                      ),
                    ],
                    selected: {_width},
                    onSelectionChanged: (selection) {
                      setState(() => _width = selection.first);
                    },
                    showSelectedIcon: false,
                    expandedInsets: EdgeInsets.zero,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _strokes.isEmpty ? null : _undo,
                  icon: const Icon(Icons.undo),
                  tooltip: 'Desfazer',
                ),
                IconButton(
                  onPressed: isEmpty ? null : _clear,
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Limpar tudo',
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async => showServerModal(),
                    label: const Text('Server'),
                  ),
                ),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async => showClientModal(),
                    label: const Text('Client'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawingPainter extends CustomPainter {
  final List<Stroke> strokes;
  final Stroke? current;

  _DrawingPainter({required this.strokes, required this.current});

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      _paintStroke(canvas, s);
    }
    if (current != null) _paintStroke(canvas, current!);
  }

  void _paintStroke(Canvas canvas, Stroke stroke) {
    final pts = stroke.points;
    if (pts.isEmpty) return;

    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Um único toque vira um "ponto" redondo
    if (pts.length == 1) {
      canvas.drawCircle(
        pts.first,
        stroke.width / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }

    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length - 1; i++) {
      final p = pts[i];
      final next = pts[i + 1];
      final mid = Offset((p.dx + next.dx) / 2, (p.dy + next.dy) / 2);
      path.quadraticBezierTo(p.dx, p.dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter oldDelegate) => true;
}
