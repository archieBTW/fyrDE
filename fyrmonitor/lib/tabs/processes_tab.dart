import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../fyr_theme.dart';
import '../models/monitor_models.dart';
import '../services/proc_service.dart';
import '../widgets/row_action_button.dart';

/// Sortable columns of the process table.
enum ProcessSort { name, pid, cpu, memory }

/// Tab 2 — every process in `/proc`, with live search, user filter, sorting and
/// SIGTERM / SIGKILL actions.
///
/// The sweep only runs while [active] is true; the search field additionally
/// debounces keystrokes so typing does not trigger a `/proc` scan per character.
class ProcessesTab extends StatefulWidget {
  const ProcessesTab({super.key, required this.active});

  final bool active;

  @override
  State<ProcessesTab> createState() => _ProcessesTabState();
}

class _ProcessesTabState extends State<ProcessesTab> {
  static const Duration _pollInterval = Duration(milliseconds: 1500);
  static const Duration _searchDebounce = Duration(milliseconds: 280);

  static const double _wPid = 66;
  static const double _wCpu = 70;
  static const double _wMemory = 80;
  static const double _wActions = 64;

  final TextEditingController _searchController = TextEditingController();

  Timer? _timer;
  Timer? _searchTimer;
  List<ProcessInfo> _processes = const [];
  String _query = '';
  bool _userOnly = false;
  ProcessSort _sort = ProcessSort.cpu;
  bool _sortAscending = false;
  bool _scanning = false;

  /// Baseline for the CPU% delta. Kept as a plain field so the 1.5 s timer can
  /// reuse the counters from the previous sweep instead of re-reading `stat`.
  Map<int, int> _previousTicks = const {};
  DateTime? _previousAt;

  int get _totalProcessCount => _processes.length;

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(covariant ProcessesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      // Baseline is stale after a pause; drop it so the first sample is 0%
      // instead of a spike averaged over the whole inactive period.
      _previousTicks = const {};
      _previousAt = null;
      _start();
    } else if (!widget.active && oldWidget.active) {
      _stop();
    }
  }

  @override
  void dispose() {
    _stop();
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    _scan();
    _timer = Timer.periodic(_pollInterval, (_) => _scan());
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _scan() async {
    if (_scanning) return;
    _scanning = true;
    try {
      final result = await ProcService.scanProcesses(
        previousTicks: _previousTicks,
        previousAt: _previousAt,
        userOnly: _userOnly,
        query: _query,
      );
      if (!mounted) return;
      _previousTicks = result.ticks;
      _previousAt = result.timestamp;
      setState(() {
        _processes = result.processes;
        _applySortInPlace();
      });
    } finally {
      _scanning = false;
    }
  }

  void _onSearchChanged(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(_searchDebounce, () {
      if (!mounted || value == _query) return;
      setState(() => _query = value);
      _previousTicks = const {};
      _previousAt = null;
      _scan();
    });
  }

  void _setSort(ProcessSort sort) {
    setState(() {
      if (_sort == sort) {
        _sortAscending = !_sortAscending;
      } else {
        _sort = sort;
        // CPU and memory are far more useful biggest-first by default.
        _sortAscending = sort == ProcessSort.name || sort == ProcessSort.pid;
      }
      _applySortInPlace();
    });
  }

  /// Sorts `_processes` in place; called from inside `setState`.
  void _applySortInPlace() {
    final list = List<ProcessInfo>.from(_processes);
    list.sort((a, b) {
      final int result;
      switch (_sort) {
        case ProcessSort.name:
          result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case ProcessSort.pid:
          result = a.pid.compareTo(b.pid);
        case ProcessSort.cpu:
          result = a.cpuPercent.compareTo(b.cpuPercent);
        case ProcessSort.memory:
          result = a.rssKb.compareTo(b.rssKb);
      }
      return _sortAscending ? result : -result;
    });
    _processes = list;
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

  Future<void> _terminate(ProcessInfo process) =>
      _signal(process, ProcessSignal.sigterm, 'SIGTERM sent to');

  Future<void> _kill(ProcessInfo process) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FyrTheme.surfaceColor,
        title: Text(
          'Kill "${process.name}"?',
          style: TextStyle(color: FyrTheme.textColor, fontSize: 15),
        ),
        content: Text(
          'SIGKILL cannot be caught — PID ${process.pid} will be terminated '
          'immediately and unsaved work will be lost.',
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
            child: const Text('Kill'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _signal(process, ProcessSignal.sigkill, 'SIGKILL sent to');
  }

  Future<void> _signal(
    ProcessInfo process,
    ProcessSignal signal,
    String label,
  ) async {
    var ok = false;
    try {
      ok = Process.killPid(process.pid, signal);
    } on ArgumentError {
      ok = false;
    } on OSError {
      ok = false;
    } on ProcessException {
      ok = false;
    }
    _snack(
      ok
          ? '$label ${process.name} (${process.pid})'
          : 'Not permitted to signal PID ${process.pid}',
      isError: !ok,
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await _scan();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildToolbar(),
        _buildHeaderRow(),
        Divider(height: 1, thickness: 1, color: FyrTheme.dividerColor),
        Expanded(
          child: _processes.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: _processes.length,
                  itemBuilder: (context, index) {
                    final process = _processes[index];
                    return _ProcessRow(
                      key: ValueKey(process.pid),
                      process: process,
                      pidWidth: _wPid,
                      cpuWidth: _wCpu,
                      memoryWidth: _wMemory,
                      actionsWidth: _wActions,
                      onTerminate: () => _terminate(process),
                      onKill: () => _kill(process),
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
          Expanded(
            child: SizedBox(
              height: 31,
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: TextStyle(color: FyrTheme.textColor, fontSize: 12.5),
                cursorColor: FyrTheme.accentColor,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search processes by name',
                  hintStyle: TextStyle(
                    color: FyrTheme.textColorMuted.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 16,
                    color: FyrTheme.textColorMuted,
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 31,
                    minHeight: 31,
                  ),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: Icon(
                            Icons.close_rounded,
                            size: 15,
                            color: FyrTheme.textColorMuted,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            _searchTimer?.cancel();
                            setState(() => _query = '');
                            _previousTicks = const {};
                            _previousAt = null;
                            _scan();
                          },
                        ),
                  filled: true,
                  fillColor: FyrTheme.cardColor,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: BorderSide(color: FyrTheme.dividerColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: BorderSide(color: FyrTheme.dividerColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: BorderSide(
                      color: FyrTheme.accentColor.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _UserFilterToggle(
            value: _userOnly,
            onChanged: (value) {
              setState(() => _userOnly = value);
              _previousTicks = const {};
              _previousAt = null;
              _scan();
            },
          ),
          const SizedBox(width: 12),
          Text(
            '$_totalProcessCount shown',
            style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 11),
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
          Expanded(
            child: _SortableHeader(
              label: 'NAME',
              active: _sort == ProcessSort.name,
              ascending: _sortAscending,
              onTap: () => _setSort(ProcessSort.name),
            ),
          ),
          _SortableHeader(
            label: 'PID',
            width: _wPid,
            active: _sort == ProcessSort.pid,
            ascending: _sortAscending,
            onTap: () => _setSort(ProcessSort.pid),
          ),
          _SortableHeader(
            label: 'CPU',
            width: _wCpu,
            active: _sort == ProcessSort.cpu,
            ascending: _sortAscending,
            onTap: () => _setSort(ProcessSort.cpu),
          ),
          _SortableHeader(
            label: 'MEMORY',
            width: _wMemory,
            active: _sort == ProcessSort.memory,
            ascending: _sortAscending,
            align: TextAlign.right,
            onTap: () => _setSort(ProcessSort.memory),
          ),
          SizedBox(width: _wActions),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final filtered = _query.isNotEmpty || _userOnly;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.memory_rounded,
            size: 42,
            color: FyrTheme.textColorMuted.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 12),
          Text(
            filtered ? 'No matching processes' : 'No processes found',
            style: TextStyle(
              color: FyrTheme.textColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            filtered
                ? 'Try a different name or disable the user filter.'
                : 'Could not read /proc — is this a Linux host?',
            style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

class _UserFilterToggle extends StatelessWidget {
  const _UserFilterToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final user = Platform.environment['USER'] ?? 'user';
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 31,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: value
                ? FyrTheme.accentColor.withValues(alpha: 0.16)
                : FyrTheme.cardColor,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: value
                  ? FyrTheme.accentColor.withValues(alpha: 0.55)
                  : FyrTheme.dividerColor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                value ? Icons.check_box_rounded : Icons.check_box_outline_blank,
                size: 15,
                color: value ? FyrTheme.accentColor : FyrTheme.textColorMuted,
              ),
              const SizedBox(width: 7),
              Text(
                '$user only',
                style: TextStyle(
                  color: value ? FyrTheme.textColor : FyrTheme.textColorMuted,
                  fontSize: 11.5,
                  fontWeight: value ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SortableHeader extends StatelessWidget {
  const _SortableHeader({
    required this.label,
    required this.active,
    required this.ascending,
    required this.onTap,
    this.width,
    this.align = TextAlign.left,
  });

  final String label;
  final bool active;
  final bool ascending;
  final VoidCallback onTap;
  final double? width;
  final TextAlign align;

  /// Callers wrap the flexible column in an [Expanded]; a fixed width column is
  /// sized here so the row layout stays aligned across headers and cells.
  @override
  Widget build(BuildContext context) {
    final child = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: align == TextAlign.right
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: active
                    ? FyrTheme.accentColor
                    : FyrTheme.textColorMuted.withValues(alpha: 0.85),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
              ),
            ),
            if (active) ...[
              const SizedBox(width: 3),
              Icon(
                ascending
                    ? Icons.arrow_drop_up_rounded
                    : Icons.arrow_drop_down_rounded,
                size: 15,
                color: FyrTheme.accentColor,
              ),
            ],
          ],
        ),
      ),
    );
    if (width == null) return child;
    return SizedBox(width: width, child: child);
  }
}

class _ProcessRow extends StatefulWidget {
  const _ProcessRow({
    super.key,
    required this.process,
    required this.pidWidth,
    required this.cpuWidth,
    required this.memoryWidth,
    required this.actionsWidth,
    required this.onTerminate,
    required this.onKill,
  });

  final ProcessInfo process;
  final double pidWidth;
  final double cpuWidth;
  final double memoryWidth;
  final double actionsWidth;
  final VoidCallback onTerminate;
  final VoidCallback onKill;

  @override
  State<_ProcessRow> createState() => _ProcessRowState();
}

class _ProcessRowState extends State<_ProcessRow> {
  bool _hovered = false;

  /// Hot processes get a coloured CPU figure, matching Task Manager's emphasis.
  Color _cpuColor(double cpu) {
    if (cpu >= 50) return Colors.redAccent;
    if (cpu >= 15) return Colors.orangeAccent;
    return FyrTheme.textColor;
  }

  @override
  Widget build(BuildContext context) {
    final process = widget.process;
    final isSelf = process.pid == pid;
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _hovered
              ? FyrTheme.hoverColor
              : (isSelf
                    ? FyrTheme.accentColor.withValues(alpha: 0.06)
                    : Colors.transparent),
          border: Border(
            bottom: BorderSide(
              color: FyrTheme.dividerColor.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                process.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: FyrTheme.textColor,
                  fontSize: 12,
                  fontWeight: isSelf ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            SizedBox(
              width: widget.pidWidth,
              child: Text(
                '${process.pid}',
                style: TextStyle(
                  color: FyrTheme.textColorMuted,
                  fontSize: 11.5,
                ),
              ),
            ),
            SizedBox(
              width: widget.cpuWidth,
              child: Text(
                Units.percent(process.cpuPercent),
                style: TextStyle(
                  color: _cpuColor(process.cpuPercent),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(
              width: widget.memoryWidth,
              child: Text(
                Units.memory(process.rssMb),
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: FyrTheme.textColor,
                  fontSize: 11.5,
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
                    icon: Icons.power_settings_new_rounded,
                    tooltip: 'Terminate gracefully (SIGTERM)',
                    color: Colors.orangeAccent,
                    onPressed: widget.onTerminate,
                  ),
                  RowActionButton(
                    icon: Icons.dangerous_rounded,
                    tooltip: 'Kill immediately (SIGKILL)',
                    color: Colors.redAccent,
                    onPressed: widget.onKill,
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
