import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Binary i3/Sway IPC framing constants matching sway/ipc.h.
class SwayIpcProtocol {
  static const List<int> magic = [0x69, 0x33, 0x2d, 0x69, 0x70, 0x63]; // i3-ipc
  static const int headerLength = 14;

  static const int runCommand = 0;
  static const int getWorkspaces = 1;
  static const int getOutputs = 3;
  static const int getTree = 4;

  static int? typeCodeForName(String ipcType) {
    switch (ipcType) {
      case 'run_command':
        return runCommand;
      case 'get_workspaces':
        return getWorkspaces;
      case 'get_outputs':
        return getOutputs;
      case 'get_tree':
        return getTree;
      default:
        return null;
    }
  }

  static Uint8List encodeFrame(int messageType, [String payload = '']) {
    final payloadBytes = utf8.encode(payload);
    final frame = ByteData(headerLength + payloadBytes.length);
    for (var i = 0; i < magic.length; i++) {
      frame.setUint8(i, magic[i]);
    }
    frame.setUint32(6, payloadBytes.length, Endian.host);
    frame.setUint32(10, messageType, Endian.host);
    final out = frame.buffer.asUint8List();
    out.setRange(headerLength, headerLength + payloadBytes.length, payloadBytes);
    return out;
  }

  /// Attempts to decode one complete Sway IPC message from [buffer].
  /// Returns null when more bytes are still needed.
  static ({int messageType, String payload, int totalBytes})? tryDecodeFrame(
    List<int> buffer,
  ) {
    if (buffer.length < headerLength) return null;
    for (var i = 0; i < magic.length; i++) {
      if (buffer[i] != magic[i]) {
        throw const FormatException('Invalid Sway IPC magic header');
      }
    }
    final header = ByteData.sublistView(
      Uint8List.fromList(buffer.sublist(0, headerLength)),
    );
    final payloadLength = header.getUint32(6, Endian.host);
    final messageType = header.getUint32(10, Endian.host);
    final totalBytes = headerLength + payloadLength;
    if (buffer.length < totalBytes) return null;
    final payload = utf8.decode(buffer.sublist(headerLength, totalBytes));
    return (
      messageType: messageType,
      payload: payload,
      totalBytes: totalBytes,
    );
  }
}

/// Subscription handle for an event-driven `swaymsg -t subscribe` stream.
class SwaySubscription {
  final List<String> events;
  final void Function(Map<String, dynamic> event) onEvent;
  final void Function(Object error)? onError;
  final Duration reconnectDelay;

  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  Timer? _reconnectTimer;
  bool _disposed = false;

  SwaySubscription._({
    required this.events,
    required this.onEvent,
    this.onError,
    this.reconnectDelay = const Duration(seconds: 2),
  }) {
    _connect();
  }

  Future<void> _connect() async {
    if (_disposed) return;
    try {
      final process = await Process.start(
        'swaymsg',
        ['-t', 'subscribe', '-m', jsonEncode(events)],
      );
      if (_disposed) {
        process.kill();
        return;
      }
      _process = process;
      _stdoutSub = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) return;
          try {
            final decoded = jsonDecode(trimmed);
            if (decoded is Map<String, dynamic>) {
              onEvent(decoded);
            }
          } catch (e) {
            onError?.call(e);
          }
        },
        onError: (Object error) => onError?.call(error),
        onDone: _scheduleReconnect,
        cancelOnError: false,
      );
      // Drain stderr so the child process never blocks on a full pipe.
      process.stderr.drain<void>().catchError((_) {});
    } catch (e) {
      onError?.call(e);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _stdoutSub?.cancel();
    _stdoutSub = null;
    _process = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(reconnectDelay, _connect);
  }

  Future<void> cancel() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _stdoutSub?.cancel();
    _stdoutSub = null;
    _process?.kill();
    _process = null;
  }
}

/// Lightweight event-driven Sway IPC helper backed by `swaymsg`.
class SwayIpc {
  static SwaySubscription subscribe(
    List<String> events, {
    required void Function(Map<String, dynamic> event) onEvent,
    void Function(Object error)? onError,
    Duration reconnectDelay = const Duration(seconds: 2),
  }) {
    return SwaySubscription._(
      events: events,
      onEvent: onEvent,
      onError: onError,
      reconnectDelay: reconnectDelay,
    );
  }

  static String? get swaySocketPath {
    final sock = Platform.environment['SWAYSOCK'];
    if (sock == null || sock.isEmpty) return null;
    return sock;
  }

  static Future<String?> _sendRawIpc(int messageType, [String payload = '']) async {
    final sockPath = swaySocketPath;
    if (sockPath == null) return null;
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress(sockPath, type: InternetAddressType.unix),
        0,
        timeout: const Duration(milliseconds: 500),
      );
      socket.add(SwayIpcProtocol.encodeFrame(messageType, payload));
      await socket.flush();

      final buffer = <int>[];
      await for (final chunk in socket) {
        buffer.addAll(chunk);
        final decoded = SwayIpcProtocol.tryDecodeFrame(buffer);
        if (decoded != null) {
          return decoded.payload;
        }
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      await socket?.close();
    }
  }

  static Future<dynamic> queryJson(String ipcType) async {
    try {
      final typeCode = SwayIpcProtocol.typeCodeForName(ipcType);
      if (typeCode != null) {
        final rawPayload = await _sendRawIpc(typeCode);
        if (rawPayload != null) {
          return jsonDecode(rawPayload);
        }
      }
      final result = await Process.run('swaymsg', ['-t', ipcType]);
      if (result.exitCode != 0) return null;
      return jsonDecode(result.stdout.toString());
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getTree() async {
    final data = await queryJson('get_tree');
    return data is Map<String, dynamic> ? data : null;
  }

  static Future<List<dynamic>> getOutputs() async {
    final data = await queryJson('get_outputs');
    return data is List<dynamic> ? data : const [];
  }

  static Future<List<dynamic>> getWorkspaces() async {
    final data = await queryJson('get_workspaces');
    return data is List<dynamic> ? data : const [];
  }

  /// Queries workspaces and tree concurrently over Sway IPC.
  static Future<(List<dynamic>, Map<String, dynamic>?)>
  getWorkspacesAndTree() async {
    final results = await Future.wait<dynamic>([getWorkspaces(), getTree()]);
    return (
      results[0] as List<dynamic>,
      results[1] as Map<String, dynamic>?,
    );
  }

  /// Returns an immediate default wallpaper path without spawning subprocesses.
  static String? initialWallpaperFallback() {
    final home = Platform.environment['HOME'] ?? '';
    if (home.isEmpty) return null;
    final defaultWall = '$home/.config/fyr/space.jpg';
    return File(defaultWall).existsSync() ? defaultWall : null;
  }

  /// Resolves the active wallpaper from `swaybg` or Sway config.
  static Future<String?> detectWallpaperPath() async {
    try {
      final result = await Process.run('pgrep', ['-a', 'swaybg']);
      if (result.exitCode == 0) {
        final match = RegExp(r'-i\s+([^\s]+)').firstMatch(
          result.stdout.toString(),
        );
        if (match != null) {
          return match.group(1);
        }
      }
    } catch (_) {}

    final home = Platform.environment['HOME'] ?? '';
    if (home.isNotEmpty) {
      try {
        final configFile = File('$home/.config/sway/config');
        if (await configFile.exists()) {
          final lines = await configFile.readAsLines();
          for (final line in lines) {
            final match = RegExp(
              r'^\s*output\s+\S+\s+bg\s+("([^"]+)"|(\S+))',
            ).firstMatch(line);
            if (match != null) {
              var path = match.group(2) ?? match.group(3) ?? '';
              if (path.startsWith('~/')) {
                path = '$home/${path.substring(2)}';
              }
              if (path.isNotEmpty && await File(path).exists()) {
                return path;
              }
            }
          }
        }
      } catch (_) {}
    }
    return initialWallpaperFallback();
  }

  static Future<void> command(String cmd) async {
    try {
      final rawReply = await _sendRawIpc(SwayIpcProtocol.runCommand, cmd);
      if (rawReply != null) return;
      await Process.run('swaymsg', [cmd]);
    } catch (_) {
      // Ignore outside an active Sway session.
    }
  }
}
