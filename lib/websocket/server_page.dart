import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_websocket/local_websocket.dart';
import 'package:websocket_demo/websocket/server.dart';

class ServerPage extends StatefulWidget {
  const ServerPage({super.key, required this.server});

  final WebsocketServer server;

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  final _hostController = TextEditingController(text: '0.0.0.0');
  final _portController = TextEditingController(text: '8080');

  @override
  void initState() {
    super.initState();
    final host = widget.server.host;
    final port = widget.server.port;
    if (host != null) _hostController.text = host;
    if (port != null) _portController.text = port.toString();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _startServer() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim());

    if (host.isEmpty || port == null || port < 1 || port > 65535) {
      _showMessage('Informe um host e uma porta válidos (1-65535).');
      return;
    }

    final started = await widget.server.start(host, port);
    if (!started && mounted) {
      _showMessage(
        widget.server.lastError ?? 'Não foi possível iniciar o servidor.',
      );
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.server,
      builder: (context, _) {
        final server = widget.server;
        final isRunning = server.isRunning;
        final isBusy = server.isBusy;
        final fieldsEnabled = !isRunning && !isBusy;

        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              16 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Server settings',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _hostController,
                                decoration: const InputDecoration(
                                  labelText: 'Host',
                                  border: OutlineInputBorder(),
                                  helperText:
                                      '0.0.0.0 aceita conexões da rede local',
                                ),
                                enabled: fieldsEnabled,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _portController,
                                decoration: const InputDecoration(
                                  labelText: 'Port',
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                enabled: fieldsEnabled,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _ServerStatus(server: server),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: fieldsEnabled ? _startServer : null,
                                icon: isBusy && !isRunning
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.play_arrow),
                                label: Text(
                                  server.isStarting
                                      ? 'Starting...'
                                      : 'Start Server',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: isRunning && !isBusy
                                    ? server.stop
                                    : null,
                                icon: server.isStopping
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.stop),
                                label: Text(
                                  server.isStopping
                                      ? 'Stopping...'
                                      : 'Stop Server',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _ClientsCard(clients: server.clients, serverRunning: isRunning),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ServerStatus extends StatelessWidget {
  const _ServerStatus({required this.server});

  final WebsocketServer server;

  @override
  Widget build(BuildContext context) {
    final isRunning = server.isRunning;

    final (Color color, IconData icon, String label) = switch (server) {
      WebsocketServer(isStarting: true) => (
        Colors.orange,
        Icons.cloud_sync,
        'Starting server...',
      ),
      WebsocketServer(isStopping: true) => (
        Colors.orange,
        Icons.cloud_sync,
        'Stopping server...',
      ),
      WebsocketServer(isRunning: true) => (
        Colors.green,
        Icons.cloud_done,
        'Server connected',
      ),
      _ => (Colors.red, Icons.cloud_off, 'Server disconnected'),
    };

    final host = server.host;
    final port = server.port;
    final addresses = server.lanAddresses;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontWeight: FontWeight.bold, color: color),
                ),
                if (isRunning && port != null) ...[
                  if (addresses.isEmpty)
                    Text(
                      'ws://${host ?? '?'}:$port/ws',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    )
                  else
                    ...addresses.map(
                      (address) => _AddressRow(address: address, port: port),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({required this.address, required this.port});

  final String address;
  final int port;

  @override
  Widget build(BuildContext context) {
    final url = 'ws://$address:$port/ws';

    return Row(
      children: [
        Expanded(
          child: Text(
            url,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ),
        IconButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: address));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('IP copiado')));
          },
          icon: const Icon(Icons.copy),
          iconSize: 16,
          visualDensity: VisualDensity.compact,
          tooltip: 'Copiar IP',
        ),
      ],
    );
  }
}

class _ClientsCard extends StatelessWidget {
  const _ClientsCard({required this.clients, required this.serverRunning});

  final List<Client> clients;
  final bool serverRunning;

  static String _formatDetails(Map<String, String> details) {
    if (details.isEmpty) return 'No details';
    return details.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium
        ?.copyWith(fontWeight: FontWeight.bold);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connected Clients (${clients.length})', style: titleStyle),
            const SizedBox(height: 8),
            if (clients.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  serverRunning
                      ? 'No clients connected'
                      : 'Server is not running',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              )
            else
              ...clients.map(
                (client) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.person),
                  title: Text(
                    client.details['username'] ?? client.uid,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    'ID: ${client.uid}\n${_formatDetails(client.details)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  isThreeLine: true,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
