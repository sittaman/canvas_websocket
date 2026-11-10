import 'package:flutter/material.dart';
import 'package:local_websocket/local_websocket.dart';
import 'package:websocket_demo/websocket/client.dart';

class ClientPage extends StatefulWidget {
  const ClientPage({super.key, required this.client});

  final WebsocketClient client;

  @override
  State<ClientPage> createState() => _ClientPageState();
}

class _ClientPageState extends State<ClientPage> {
  final _hostController = TextEditingController(text: '127.0.0.1');
  final _portController = TextEditingController(text: '8080');
  final _usernameController = TextEditingController(
    text: 'User_${DateTime.now().millisecondsSinceEpoch % 1000}',
  );
  final _messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Reopening the sheet while connected should show the active connection.
    final connection = widget.client;
    if (connection.isConnected || connection.isConnecting) {
      _hostController.text = connection.host ?? _hostController.text;
      _portController.text =
          connection.port?.toString() ?? _portController.text;
      _usernameController.text =
          connection.username ?? _usernameController.text;
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim());
    final username = _usernameController.text.trim();

    if (host.isEmpty ||
        username.isEmpty ||
        port == null ||
        port < 1 ||
        port > 65535) {
      _showMessage('Informe usuário, host e porta válidos (1-65535).');
      return;
    }

    final connected = await widget.client.connect(
      host: host,
      port: port,
      username: username,
    );
    if (!connected && mounted) {
      _showMessage(
        widget.client.lastError ?? 'Não foi possível conectar ao servidor.',
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
      listenable: widget.client,
      builder: (context, _) {
        final connection = widget.client;
        final isConnected = connection.isConnected;
        final isConnecting = connection.isConnecting;
        final fieldsEnabled = !isConnected && !isConnecting;

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
                          'Client Configuration',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            border: OutlineInputBorder(),
                          ),
                          enabled: fieldsEnabled,
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
                                  helperText: 'IP do celular com o servidor',
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
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: fieldsEnabled ? _connect : null,
                                icon: isConnecting
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.link),
                                label: Text(
                                  isConnecting ? 'Connecting...' : 'Connect',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: isConnected
                                    ? connection.disconnect
                                    : null,
                                icon: const Icon(Icons.link_off),
                                label: const Text('Disconnect'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _ConnectionStatus(
                          status: connection.status,
                          clientId: connection.clientId,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ConnectionStatus extends StatelessWidget {
  const _ConnectionStatus({required this.status, required this.clientId});

  final ClientConnectionStatus status;
  final String? clientId;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon, String label) = switch (status) {
      ClientConnectionStatus.connected => (
        Colors.green,
        Icons.cloud_done,
        'Connected',
      ),
      ClientConnectionStatus.connecting => (
        Colors.orange,
        Icons.cloud_sync,
        'Connecting...',
      ),
      ClientConnectionStatus.disconnected => (
        Colors.red,
        Icons.cloud_off,
        'Disconnected',
      ),
    };

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
                if (status == ClientConnectionStatus.connected &&
                    clientId != null)
                  Text(
                    'Client ID: $clientId',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
