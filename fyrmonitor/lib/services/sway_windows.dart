import 'dart:convert';
import 'dart:io';

import '../models/monitor_models.dart';
import 'proc_service.dart';

/// Enumerates and controls sway windows through `swaymsg`.
class SwayWindows {
  SwayWindows._();

  /// Runs `swaymsg -t get_tree` and flattens it into one row per mapped window.
  ///
  /// Only leaf `con` / `floating_con` nodes that carry a positive `pid` and
  /// either an `app_id` or XWayland `window_properties` are kept, which filters
  /// out sway's internal containers, scratchpad holders and layer surfaces.
  static Future<List<WindowInfo>> list() async {
    final tree = await _getTree();
    if (tree == null) return const [];

    final hits = <_WindowHit>[];
    _walk(tree, null, hits);

    final windows = await Future.wait(
      hits.map((hit) async {
        final rssKb = await ProcService.readRssKb(hit.pid);
        return WindowInfo(
          conId: hit.conId,
          pid: hit.pid,
          appId: hit.appId,
          title: hit.title,
          workspaceName: hit.workspaceName,
          workspaceNumber: hit.workspaceNumber,
          rssKb: rssKb,
          focused: hit.focused,
        );
      }),
    );

    windows.sort((a, b) {
      final byWorkspace = a.workspaceNumber.compareTo(b.workspaceNumber);
      if (byWorkspace != 0) return byWorkspace;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return windows;
  }

  /// `swaymsg [pid=X] focus`
  static Future<bool> focus(int pid) => _run(['[pid=$pid] focus']);

  /// `swaymsg [pid=X] kill` — asks the client to close its window.
  static Future<bool> close(int pid) => _run(['[pid=$pid] kill']);

  /// `SIGKILL` sent straight to the process, bypassing the Wayland protocol.
  static bool forceKill(int pid) {
    try {
      return Process.killPid(pid, ProcessSignal.sigkill);
    } on ArgumentError {
      return false;
    } on OSError {
      return false;
    } on ProcessException {
      return false;
    }
  }

  /// True when a sway/SwayFX session is reachable from this process.
  ///
  /// Deliberately a synchronous environment check: spawning an extra
  /// `swaymsg -t get_version` at startup just to show a hint would cost a
  /// process launch, and the periodic `get_tree` already proves reachability.
  static bool get hasSession =>
      (Platform.environment['SWAYSOCK'] ?? '').isNotEmpty;

  static Future<bool> _run(List<String> args) async {
    try {
      final result = await Process.run('swaymsg', args);
      return result.exitCode == 0;
    } on ProcessException {
      // swaymsg is not installed (or not on PATH).
      return false;
    }
  }

  static Future<Map<String, dynamic>?> _getTree() async {
    try {
      final result = await Process.run('swaymsg', ['-t', 'get_tree']);
      if (result.exitCode != 0) return null;
      final decoded = jsonDecode(result.stdout.toString());
      return decoded is Map<String, dynamic> ? decoded : null;
    } on ProcessException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Depth-first walk that carries the enclosing workspace down to the leaves.
  static void _walk(
    Map<String, dynamic> node,
    _WorkspaceScope? scope,
    List<_WindowHit> out,
  ) {
    var current = scope;
    if (node['type'] == 'workspace') {
      current = _WorkspaceScope(
        name: (node['name'] ?? '?').toString(),
        number: node['num'] is int ? node['num'] as int : -1,
      );
    }

    final children = <Map<String, dynamic>>[];
    for (final key in const ['nodes', 'floating_nodes']) {
      final value = node[key];
      if (value is List) {
        for (final child in value) {
          if (child is Map<String, dynamic>) children.add(child);
        }
      }
    }

    if (children.isNotEmpty) {
      for (final child in children) {
        _walk(child, current, out);
      }
      return;
    }

    final type = node['type'];
    if (type != 'con' && type != 'floating_con') return;

    final pid = node['pid'];
    if (pid is! int || pid <= 0) return;

    final appId = (node['app_id'] ?? '').toString();
    final properties = node['window_properties'];
    final hasProperties = properties is Map && properties.isNotEmpty;
    if (appId.isEmpty && !hasProperties) return;

    final title = (node['name'] ?? '').toString();
    final fallbackTitle = hasProperties
        ? (properties['title'] ?? properties['class'] ?? '').toString()
        : '';

    out.add(
      _WindowHit(
        conId: node['id'] is int ? node['id'] as int : -1,
        pid: pid,
        appId: appId.isNotEmpty
            ? appId
            : (hasProperties
                  ? (properties['class'] ?? properties['instance'] ?? 'xwayland')
                        .toString()
                  : 'unknown'),
        title: title.isNotEmpty ? title : fallbackTitle,
        workspaceName: current?.name ?? '?',
        workspaceNumber: current?.number ?? -1,
        focused: node['focused'] == true,
      ),
    );
  }
}

class _WorkspaceScope {
  const _WorkspaceScope({required this.name, required this.number});

  final String name;
  final int number;
}

class _WindowHit {
  const _WindowHit({
    required this.conId,
    required this.pid,
    required this.appId,
    required this.title,
    required this.workspaceName,
    required this.workspaceNumber,
    required this.focused,
  });

  final int conId;
  final int pid;
  final String appId;
  final String title;
  final String workspaceName;
  final int workspaceNumber;
  final bool focused;
}
