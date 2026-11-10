# Collaborative WebSocket Canvas

A real-time collaborative drawing app built with Flutter that runs on local network. One device hosts a WebSocket server and the others connect as clients: strokes drawn by any participant appear on every device, along with undo and clear operations.

[![Watch the demo video](https://img.youtube.com/vi/0eBZUm4gX_0/hqdefault.jpg)](https://www.youtube.com/watch?v=0eBZUm4gX_0)
_Watch the demo video_

## Project structure

```text
lib/
├── main.dart                     # App, canvas, toolbar, and local/remote sync
├── drawing/
│   ├── stroke.dart               # Stroke model (id, color, width, points)
│   └── drawing_event.dart        # JSON drawing protocol and snapshot
└── websocket/
    ├── server.dart               # WebsocketServer (ChangeNotifier)
    ├── client.dart               # WebsocketClient (ChangeNotifier)
    ├── server_page.dart          # Server configuration/state modal
    ├── client_page.dart          # Client connection/state modal
    └── message_text.dart         # Frame normalization (String/bytes) to text
```

Platform files under `android/` hold the network permissions. The app uses `dart:io` (through `local_websocket`), so it is **not web-compatible**.

## Architecture

```text
Phone 1 (host)                                   Phone 2+ (clients)
┌─────────────────────────────────┐               ┌──────────────────────────────────┐
│ DrawingPage                     │               │ DrawingPage                      │
│   ├─ WebsocketServer            │   ws://IP     │   ├─ WebsocketClient             │
│   │    └─ broadcastMessage ─────┼──────────────▶│   │    └─ sendText ──────────────┼──▶ host
│   └─ messageStream ◀────────────┼───────────────│   └─ messageStream ◀─────────────│◀── host
└─────────────────────────────────┘               └──────────────────────────────────┘
```

- `WebsocketServer` and `WebsocketClient` are created in `_DrawingAppState` (`lib/main.dart`), above the routes. Closing the modal does not stop the server or drop the connection.
- Both services are `ChangeNotifier`: the modals use `ListenableBuilder` and reflect status in real time.
- Both expose `messageStream` with received messages. `DrawingPage` listens to both streams and applies events to the canvas.
- Every local gesture is encoded as JSON and sent through `server.broadcastMessage` (to the server's own clients) and `client.sendText` (to the server this app is connected to).
- Every event carries an `origin` (session id) so the sender can ignore its own echo.
- Every stroke has a unique `id`; undo removes the stroke by id, keeping consistency even with events from multiple devices.
- On connect/reconnect, the client sends `sync_request`; the running host replies with `snapshot`; the canvas merges strokes it does not have yet.

## WebSocket protocol

Endpoint: `ws://HOST:PORT/ws` (default port `8080`). Payloads are JSON text.

| Type | Sent by | Fields | Purpose |
| --- | --- | --- | --- |
| `stroke_start` | host/clients | `origin`, `id`, `color` (ARGB int), `width`, `x`, `y` | Starts a stroke with the first point |
| `stroke_point` | host/clients | `origin`, `id`, `x`, `y` | Adds a point to the stroke |
| `stroke_end` | host/clients | `origin`, `id` | Ends the stroke |
| `stroke_remove` | host/clients | `origin`, `id` | Removes a stroke (undo) |
| `clear` | host/clients | `origin` | Clears everyone's canvas |
| `sync_request` | client | `origin` | Requests the current state from the host |
| `snapshot` | host | `origin`, `strokes[]` | Sends all existing strokes |

Each `snapshot.strokes` item has `id`, `color`, `width`, and `points` (`[[x, y], ...]`).

## Running

```bash
flutter pub get
flutter run
```

To build an APK:

```bash
flutter build apk --debug
# output: build/app/outputs/flutter-apk/app-debug.apk
```

Other useful commands:

```bash
flutter devices        # list devices
flutter analyze        # static analysis
dart format lib        # formatting
```

## Using it with two phones

1. Install the app on both devices and connect them to the **same Wi-Fi network**.
2. On phone 1, open **Server**:
   - Host: `0.0.0.0` (default; accepts local network connections)
   - Port: `8080`
   - Tap **Start Server**.
   - The status shows the addresses, for example `ws://192.168.0.15:8080/ws`. Tap the copy icon to copy the IP.
3. On phone 2, open **Client**:
   - Host: the Wi-Fi IP shown on phone 1 (for example `192.168.0.15`) — **do not use `127.0.0.1`**.
   - Port: `8080`
   - Username: a name to identify the participant.
   - Tap **Connect**.
4. Close the modals and draw on either device. Strokes, undo, and clear are synchronized.
5. If a client joins later, it automatically requests and receives the canvas snapshot.
6. The server and the connection stay active when you close the modals. If the host goes down, the client tries to reconnect and requests a new snapshot when it comes back.

## Troubleshooting

- **Devices do not connect to each other:** make sure the server is bound to `0.0.0.0`, the client uses the host's Wi-Fi IP, and both are on the same subnet. `127.0.0.1`/`localhost` only work on the device itself.
- **Guest network or client isolation:** guest networks and some routers block device-to-device communication (`AP isolation`). Use the main network or disable isolation.
- **Multiple IPs shown:** prefer the Wi-Fi interface address (usually `192.168.x.x`).
- **Port already in use:** choose another port on both the server and the client.
- **Changed `AndroidManifest.xml`:** permissions and cleartext require a rebuild/reinstall; hot reload does not apply manifest changes.
- **Android 16+:** if the system asks for local network access permission, allow it.
- **Previous drawings do not appear:** the snapshot is only served if the host app is open with the server running.
- **Strokes do not appear on a specific client:** check the status in the Client modal; the `Client ID` is shown while connected.

## Limitations

- No authentication, authorization, TLS (`wss`), or message validation; suitable only for a trusted LAN.
- No persistence: closing/recreating the app loses strokes (the snapshot lives in memory).
- Every finger movement generates a `stroke_point` message; very long drawings generate proportional traffic.
- Undo removes the last stroke known to that device and removes it globally by id.
- No automatic host discovery; the address must be entered manually (or copied from the host).
- Widths limited to 4/8/12 and a fixed color (`Colors.white70`).
- Web is not supported; the project is configured for Android. iOS/desktop would require adding the platform folders and reviewing the network rules.
- No automated tests are included in the repository.

## Version

`0.1.0+1` — demo project.
