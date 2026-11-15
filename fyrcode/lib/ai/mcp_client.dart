import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ai_models.dart';

/// A tool exposed by a connected MCP server.
class McpToolSpec {
  final String serverId;
  final String serverName;
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  const McpToolSpec({
    required this.serverId,
    required this.serverName,
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  /// Qualified OpenAI/DeepSeek function tool name: `mcp__<serverId>__<name>`.
  String get qualifiedName => 'mcp__${_sanitize(serverId)}__${_sanitize(name)}';

  Map<String, dynamic> toOpenAiToolSchema() => {
        'type': 'function',
        'function': {
          'name': qualifiedName,
          'description': '[$serverName MCP] $description',
          'parameters': inputSchema.isEmpty
              ? {'type': 'object', 'properties': {}}
              : inputSchema,
        },
      };

  static String _sanitize(String s) =>
      s.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
}

/// JSON-RPC 2.0 stdio client for a single Model Context Protocol (MCP) server.
class McpStdioClient {
  final McpServerConfig config;
  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  final Map<int, Completer<dynamic>> _pending = {};
  int _nextId = 1;
  bool _initialized = false;
  List<McpToolSpec> _tools = [];

  McpStdioClient(this.config);

  bool get isConnected => _initialized && _process != null;
  List<McpToolSpec> get tools => List.unmodifiable(_tools);

  Future<void> connect({String? workingDirectory}) async {
    if (_process != null) return;
    final env = <String, String>{...Platform.environment, ...config.env};
    final proc = await Process.start(
      config.command,
      config.args,
      workingDirectory: workingDirectory,
      environment: env,
    );
    _process = proc;

    _stdoutSub = proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _handleLine,
          onDone: _handleClose,
          onError: (_) => _handleClose(),
        );

    proc.stderr.drain<void>();

    await _sendRequest('initialize', {
      'protocolVersion': '2024-11-05',
      'capabilities': {},
      'clientInfo': {'name': 'fyrcode', 'version': '1.0.0'},
    });

    _sendNotification('notifications/initialized', const {});
    _initialized = true;
    await refreshTools();
  }

  Future<List<McpToolSpec>> refreshTools() async {
    if (!_initialized) return const [];
    final res = await _sendRequest('tools/list', const {});
    final rawTools = (res is Map ? res['tools'] : null) as List? ?? const [];
    _tools = rawTools.whereType<Map>().map((t) {
      final map = Map<String, dynamic>.from(t);
      return McpToolSpec(
        serverId: config.id,
        serverName: config.name,
        name: map['name']?.toString() ?? '',
        description: map['description']?.toString() ?? '',
        inputSchema: map['inputSchema'] is Map
            ? Map<String, dynamic>.from(map['inputSchema'] as Map)
            : const {},
      );
    }).where((t) => t.name.isNotEmpty).toList();
    return _tools;
  }

  Future<({String output, bool isError})> callTool(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    if (!isConnected) {
      return (
        output: 'MCP server "${config.name}" is not connected.',
        isError: true,
      );
    }

    try {
      final res = await _sendRequest('tools/call', {
        'name': toolName,
        'arguments': arguments,
      });

      if (res is Map) {
        final isError = res['isError'] == true;
        final content = res['content'];
        if (content is List) {
          final texts = content.map((c) {
            if (c is Map && c['text'] != null) return c['text'].toString();
            return jsonEncode(c);
          }).join('\n');
          return (
            output: texts.isEmpty ? jsonEncode(res) : texts,
            isError: isError,
          );
        }
        return (output: jsonEncode(res), isError: isError);
      }
      return (output: res?.toString() ?? '', isError: false);
    } catch (e) {
      return (output: 'MCP tool error: $e', isError: true);
    }
  }

  Future<dynamic> _sendRequest(String method, Map<String, dynamic> params) {
    final proc = _process;
    if (proc == null) {
      return Future.error(StateError('MCP process not running'));
    }
    final id = _nextId++;
    final completer = Completer<dynamic>();
    _pending[id] = completer;

    final payload = jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });
    proc.stdin.writeln(payload);

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('MCP request "$method" timed out');
      },
    );
  }

  void _sendNotification(String method, Map<String, dynamic> params) {
    final proc = _process;
    if (proc == null) return;
    proc.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'method': method,
        'params': params,
      }),
    );
  }

  void _handleLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return;
      final id = decoded['id'];
      if (id is int && _pending.containsKey(id)) {
        final completer = _pending.remove(id)!;
        if (decoded['error'] != null) {
          completer.completeError(decoded['error'].toString());
        } else {
          completer.complete(decoded['result']);
        }
      }
    } catch (_) {}
  }

  void _handleClose() {
    _initialized = false;
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(StateError('MCP server disconnected'));
      }
    }
    _pending.clear();
  }

  Future<void> dispose() async {
    await _stdoutSub?.cancel();
    _process?.kill();
    _process = null;
    _handleClose();
  }
}

/// Manages active MCP stdio server connections for a workspace.
class McpManager {
  final Map<String, McpStdioClient> _clients = {};
  final Map<String, String> _connectionErrors = {};

  Map<String, String> get connectionErrors =>
      Map.unmodifiable(_connectionErrors);

  List<McpToolSpec> get allTools {
    return _clients.values
        .where((c) => c.isConnected)
        .expand((c) => c.tools)
        .toList();
  }

  bool isConnected(String serverId) =>
      _clients[serverId]?.isConnected ?? false;

  int toolCountFor(String serverId) => _clients[serverId]?.tools.length ?? 0;

  Future<void> syncServers(
    List<McpServerConfig> configs, {
    String? workingDirectory,
  }) async {
    final enabledIds = configs.where((c) => c.enabled).map((c) => c.id).toSet();

    // Stop disabled or removed servers.
    final toRemove = _clients.keys.where((id) => !enabledIds.contains(id)).toList();
    for (final id in toRemove) {
      await _clients.remove(id)?.dispose();
      _connectionErrors.remove(id);
    }

    // Start newly enabled servers.
    for (final cfg in configs.where((c) => c.enabled)) {
      if (_clients.containsKey(cfg.id) && _clients[cfg.id]!.isConnected) {
        continue;
      }
      await _clients.remove(cfg.id)?.dispose();
      final client = McpStdioClient(cfg);
      try {
        await client.connect(workingDirectory: workingDirectory);
        _clients[cfg.id] = client;
        _connectionErrors.remove(cfg.id);
      } catch (e) {
        _connectionErrors[cfg.id] = e.toString();
        await client.dispose();
      }
    }
  }

  McpToolSpec? findToolByQualifiedName(String qualifiedName) {
    for (final tool in allTools) {
      if (tool.qualifiedName == qualifiedName) return tool;
    }
    return null;
  }

  Future<({String output, bool isError})> callQualifiedTool(
    String qualifiedName,
    Map<String, dynamic> args,
  ) async {
    final spec = findToolByQualifiedName(qualifiedName);
    if (spec == null) {
      return (
        output: 'MCP tool not found: $qualifiedName',
        isError: true,
      );
    }
    final client = _clients[spec.serverId];
    if (client == null || !client.isConnected) {
      return (
        output: 'MCP server "${spec.serverName}" is disconnected.',
        isError: true,
      );
    }
    return client.callTool(spec.name, args);
  }

  Future<void> disposeAll() async {
    for (final client in _clients.values) {
      await client.dispose();
    }
    _clients.clear();
  }
}
