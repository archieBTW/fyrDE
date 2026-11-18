import 'dart:async';

import 'package:flutter/material.dart';

import '../fyr_theme.dart';
import '../models/monitor_models.dart';
import '../services/sway_windows.dart';
import '../widgets/row_action_button.dart';

/// Tab 1 — every mapped sway window with focus / close / force-kill actions.
///
/// Only polls while [active] is true so no `swaymsg` process is spawned while
/// the user is looking at another tab.
class OpenAppsTab extends StatefulWidget {
  const OpenAppsTab({super.key, required this.active});

  final bool active;

  @override
  State<OpenAppsTab> createState() => _OpenAppsTabState();
}

class _OpenAppsTabState extends State<OpenAppsTab> {
  static const Duration _pollInterval = Duration(milliseconds: 1500);

  static const double _wWorkspace = 118;
  static const double _wPid = 70;
  static const double _wMemory = 84;
  static const double _wActions = 88;

  Timer? _timer;
  List<WindowInfo> _windows = const [];
  bool _busy = false;
  bool _swayAvailable = true;

  @override
  void initState() {
    super.initState();
    // Synchronous, no subprocess: the periodic get_tree already proves
    // reachability, this only decides which empty-state hint to show.
    _swayAvailable = SwayWindows.hasSession;
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(covariant OpenAppsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _start();
    } else if (!widget.active && oldWidget.active) {
      _stop();
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    _refresh();
    _timer = Timer.periodic(_pollInterval, (_) => _refresh());
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      final windows = await SwayWindows.list();
      if (!mounted) return;
      setState(() => _windows = windows);
    } finally {
      _busy = false;
    }
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? Colors.redAccent : FyrTheme.accentColor,
        ),
      );
  }

  Future<void> _focus(WindowInfo window) async {
    final ok = await SwayWindows.focus(window.pid);
    _snack(
      ok ? 'Focused "${window.title}"' : 'Could not focus PID ${window.pid}',
      isError: !ok,
    );
    if (ok) await _refresh();
  }

  Future<void> _close(WindowInfo window) async {
    final ok = await SwayWindows.close(window.pid);
    _snack(
      ok
          ? 'Asked PID ${window.pid} to close'
          : 'Could not close PID ${window.pid}',
      isError: !ok,
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await _refresh();
  }

  Future<void> _forceKill(WindowInfo window) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FyrTheme.surfaceColor,
        title: Text(
          'Force kill "${window.title}"?',
          style: TextStyle(color: FyrTheme.textColor, fontSize: 15),
        ),
        content: Text(
          'SIGKILL will immediately terminate PID ${window.pid} '
          '(${window.appId}). Unsaved work will be lost.',
          style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Force Kill'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = SwayWindows.forceKill(window.pid);
    _snack(
      ok ? 'Killed PID ${window.pid}' : 'Could not kill PID ${window.pid}',
      isError: !ok,
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildToolbar(),
        _buildHeaderRow(),
        Divider(height: 1, thickness: 1, color: FyrTheme.dividerColor),
        Expanded(
          child: _windows.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: _windows.length,
                  itemBuilder: (context, index) {
                    final window = _windows[index];
                    return _WindowRow(
                      window: window,
                      workspaceWidth: _wWorkspace,
                      pidWidth: _wPid,
                      memoryWidth: _wMemory,
                      actionsWidth: _wActions,
                      onFocus: () => _focus(window),
                      onClose: () => _close(window),
                      onForceKill: () => _forceKill(window),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          Icon(Icons.grid_view_rounded, size: 14, color: FyrTheme.accentColor),
          const SizedBox(width: 7),
          Text(
            '${_windows.length} open ${_windows.length == 1 ? 'window' : 'windows'}',
            style: TextStyle(
              color: FyrTheme.textColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'refreshed every 1.5 s',
            style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 10.5),
          ),
          const Spacer(),
          Tooltip(
            message: 'Refresh now',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _refresh,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.refresh_rounded,
                  size: 17,
                  color: FyrTheme.textColorMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Row(
        children: [
          _headerCell('WINDOW', expanded: true),
          _headerCell('WORKSPACE', width: _wWorkspace),
          _headerCell('PID', width: _wPid),
          _headerCell('MEMORY', width: _wMemory, align: TextAlign.right),
          SizedBox(width: _wActions),
        ],
      ),
    );
  }

  Widget _headerCell(
    String label, {
    double? width,
    bool expanded = false,
    TextAlign align = TextAlign.left,
  }) {
    final child = Text(
      label,
      textAlign: align,
      style: TextStyle(
        color: FyrTheme.textColorMuted.withValues(alpha: 0.85),
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.7,
      ),
    );
    if (expanded) return Expanded(child: child);
    return SizedBox(width: width, child: child);
  }

  Widget _buildEmptyState() {
    final message = _swayAvailable
        ? 'No mapped windows'
        : 'Sway session not detected';
    final hint = _swayAvailable
        ? 'Open an application and it will show up here.'
        : 'fyrMonitor needs an active sway/SwayFX session (SWAYSOCK).';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.window_rounded,
            size: 42,
            color: FyrTheme.textColorMuted.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              color: FyrTheme.textColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

class _WindowRow extends StatefulWidget {
  const _WindowRow({
    required this.window,
    required this.workspaceWidth,
    required this.pidWidth,
    required this.memoryWidth,
    required this.actionsWidth,
    required this.onFocus,
    required this.onClose,
    required this.onForceKill,
  });

  final WindowInfo window;
  final double workspaceWidth;
  final double pidWidth;
  final double memoryWidth;
  final double actionsWidth;
  final VoidCallback onFocus;
  final VoidCallback onClose;
  final VoidCallback onForceKill;

  @override
  State<_WindowRow> createState() => _WindowRowState();
}

class _WindowRowState extends State<_WindowRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final window = widget.window;
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _hovered ? FyrTheme.hoverColor : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: FyrTheme.dividerColor.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(
                    window.focused
                        ? Icons.radio_button_checked
                        : Icons.window_rounded,
                    size: 14,
                    color: window.focused
                        ? FyrTheme.accentColor
                        : FyrTheme.textColorMuted.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          window.title.isEmpty ? '(untitled)' : window.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: FyrTheme.textColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          window.appId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: FyrTheme.textColorMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: widget.workspaceWidth,
              child: Text(
                window.workspaceLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: FyrTheme.textColorMuted,
                  fontSize: 11,
                ),
              ),
            ),
            SizedBox(
              width: widget.pidWidth,
              child: Text(
                '${window.pid}',
                style: TextStyle(
                  color: FyrTheme.textColorMuted,
                  fontSize: 11,
                ),
              ),
            ),
            SizedBox(
              width: widget.memoryWidth,
              child: Text(
                Units.memory(window.rssMb),
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: FyrTheme.textColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            SizedBox(
              width: widget.actionsWidth,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  RowActionButton(
                    icon: Icons.center_focus_strong_rounded,
                    tooltip: 'Focus window',
                    color: FyrTheme.accentColor,
                    onPressed: widget.onFocus,
                  ),
                  RowActionButton(
                    icon: Icons.close_rounded,
                    tooltip: 'Close window (swaymsg kill)',
                    onPressed: widget.onClose,
                  ),
                  RowActionButton(
                    icon: Icons.dangerous_rounded,
                    tooltip: 'Force kill process (SIGKILL)',
                    color: Colors.redAccent,
                    onPressed: widget.onForceKill,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
