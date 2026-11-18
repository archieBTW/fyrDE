import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/pod_models.dart';
import '../services/container_engine.dart';
import '../state/pods_controller.dart';

class ContainersView extends StatelessWidget {
  const ContainersView({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<PodsController>();
    final selected = ctrl.selectedContainer;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildFilterToolbar(context, ctrl),
              Expanded(
                child: ctrl.filteredContainers.isEmpty
                    ? Center(
                        child: Text(
                          'No containers match the current filter.',
                          style: TextStyle(
                              fontSize: 13, color: FyrTheme.textColorMuted),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: ctrl.filteredContainers.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final c = ctrl.filteredContainers[index];
                          return _ContainerRowCard(
                            container: c,
                            isSelected: selected?.id == c.id,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        if (selected != null)
          SizedBox(
            width: 470,
            child: _ContainerInspectorPanel(container: selected),
          ),
      ],
    );
  }

  Widget _buildFilterToolbar(BuildContext context, PodsController ctrl) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: FyrTheme.surfaceColor.withValues(alpha: 0.45),
        border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: Row(
        children: [
          for (final filter in ContainerFilter.values) ...[
            _filterPill(ctrl, filter),
            const SizedBox(width: 6),
          ],
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 30,
              child: TextField(
                onChanged: ctrl.setSearchQuery,
                style: TextStyle(fontSize: 12, color: FyrTheme.textColor),
                decoration: InputDecoration(
                  hintText: 'Search containers, images, pods, or ports...',
                  hintStyle: TextStyle(
                    fontSize: 11.5,
                    color: FyrTheme.textColorMuted.withValues(alpha: 0.55),
                  ),
                  prefixIcon: Icon(Icons.search_rounded,
                      size: 15, color: FyrTheme.textColorMuted),
                  filled: true,
                  fillColor: FyrTheme.cardColor,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: BorderSide(color: FyrTheme.dividerColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: BorderSide(color: FyrTheme.dividerColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: BorderSide(color: FyrTheme.accentColor),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterPill(PodsController ctrl, ContainerFilter filter) {
    final active = ctrl.statusFilter == filter;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => ctrl.setStatusFilter(filter),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? FyrTheme.accentColor.withValues(alpha: 0.18)
              : FyrTheme.cardColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active
                ? FyrTheme.accentColor.withValues(alpha: 0.5)
                : FyrTheme.dividerColor,
          ),
        ),
        child: Text(
          filter.label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            color: active ? FyrTheme.accentColor : FyrTheme.textColorMuted,
          ),
        ),
      ),
    );
  }
}

class _ContainerRowCard extends StatelessWidget {
  final ContainerInfo container;
  final bool isSelected;

  const _ContainerRowCard({
    required this.container,
    required this.isSelected,
  });

  Color _stateColor(ContainerStateStatus state) {
    switch (state) {
      case ContainerStateStatus.running:
        return const Color(0xFF10B981);
      case ContainerStateStatus.paused:
        return const Color(0xFFF59E0B);
      case ContainerStateStatus.restarting:
        return const Color(0xFF3B82F6);
      case ContainerStateStatus.exited:
      case ContainerStateStatus.created:
        return const Color(0xFF6B7280);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.read<PodsController>();
    final stateColor = _stateColor(container.state);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => ctrl.selectContainer(container.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? FyrTheme.accentColor.withValues(alpha: 0.10)
              : FyrTheme.cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? FyrTheme.accentColor.withValues(alpha: 0.65)
                : FyrTheme.dividerColor,
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Row(
          children: [
            // State LED
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: stateColor,
                shape: BoxShape.circle,
                boxShadow: container.state.isRunning
                    ? [
                        BoxShadow(
                          color: stateColor.withValues(alpha: 0.5),
                          blurRadius: 6,
                        )
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 11),
            // Name, Pod badge, Image
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          container.name,
                          style: GoogleFonts.outfit(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: FyrTheme.textColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (container.podName != null) ...[
                        const SizedBox(width: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: FyrTheme.accentColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            'pod: ${container.podName}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: FyrTheme.accentColor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          container.image,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            color: FyrTheme.textColorMuted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '• ${container.statusText}',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: FyrTheme.textColorMuted.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Port Mappings
            if (container.ports.isNotEmpty)
              Wrap(
                spacing: 4,
                children: container.ports
                    .take(2)
                    .map(
                      (p) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                              color: const Color(0xFF3B82F6)
                                  .withValues(alpha: 0.35)),
                        ),
                        child: Text(
                          p.shortFormatted,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF60A5FA),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            const SizedBox(width: 12),
            // CPU & RAM Telemetry
            SizedBox(
              width: 115,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'CPU ${container.cpuPercent.toStringAsFixed(1)}%',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: container.cpuPercent > 35
                          ? FyrTheme.accentColor
                          : FyrTheme.textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${container.memUsageMb.round()} / ${container.memLimitMb.round()} MB',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: FyrTheme.textColorMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Quick Action Buttons
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (container.state.isRunning)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Stop Container',
                    icon: const Icon(Icons.stop_circle_outlined,
                        size: 17, color: Color(0xFFEF4444)),
                    onPressed: () => ctrl.stopContainer(container.id),
                  )
                else
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Start Container',
                    icon: const Icon(Icons.play_circle_outline_rounded,
                        size: 17, color: Color(0xFF10B981)),
                    onPressed: () => ctrl.startContainer(container.id),
                  ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Restart Container',
                  icon: Icon(Icons.restart_alt_rounded,
                      size: 16, color: FyrTheme.textColorMuted),
                  onPressed: () => ctrl.restartContainer(container.id),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: container.state == ContainerStateStatus.paused
                      ? 'Unpause Container'
                      : 'Pause Container',
                  icon: Icon(
                    container.state == ContainerStateStatus.paused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_circle_outline_rounded,
                    size: 16,
                    color: const Color(0xFFF59E0B),
                  ),
                  onPressed: () => ctrl.pauseContainer(container.id),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Open Exec Terminal',
                  icon: Icon(Icons.terminal_rounded,
                      size: 16, color: FyrTheme.textColorMuted),
                  onPressed: () => ctrl.selectContainer(
                    container.id,
                    tab: InspectorTab.terminal,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Remove Container',
                  icon: Icon(Icons.delete_outline_rounded,
                      size: 16,
                      color: FyrTheme.textColorMuted.withValues(alpha: 0.75)),
                  onPressed: () => ctrl.removeContainer(container.id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ContainerInspectorPanel extends StatefulWidget {
  final ContainerInfo container;
  const _ContainerInspectorPanel({required this.container});

  @override
  State<_ContainerInspectorPanel> createState() =>
      _ContainerInspectorPanelState();
}

class _ContainerInspectorPanelState extends State<_ContainerInspectorPanel> {
  final TextEditingController _execInputCtrl = TextEditingController();
  bool _showComposeInYamlTab = false;

  @override
  void dispose() {
    _execInputCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<PodsController>();
    final c = widget.container;

    return Container(
      decoration: BoxDecoration(
        color: FyrTheme.surfaceColor.withValues(alpha: 0.55),
        border: Border(left: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        c.name,
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: FyrTheme.textColor,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: c.state.isRunning
                            ? const Color(0xFF10B981).withValues(alpha: 0.16)
                            : const Color(0xFFF59E0B).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        c.state.label.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: c.state.isRunning
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF59E0B),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'ID: ${c.shortId} • ${c.image}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: FyrTheme.textColorMuted,
                  ),
                ),
                const SizedBox(height: 10),
                // Inspector Tabs
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: InspectorTab.values.map((tab) {
                      final active = ctrl.activeInspectorTab == tab;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => ctrl.setInspectorTab(tab),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 5),
                            decoration: BoxDecoration(
                              color: active
                                  ? FyrTheme.accentColor.withValues(alpha: 0.18)
                                  : FyrTheme.cardColor,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: active
                                    ? FyrTheme.accentColor
                                    : FyrTheme.dividerColor,
                              ),
                            ),
                            child: Text(
                              tab.label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight:
                                    active ? FontWeight.w600 : FontWeight.w500,
                                color: active
                                    ? FyrTheme.accentColor
                                    : FyrTheme.textColorMuted,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          // Tab Body
          Expanded(
            child: _buildInspectorBody(context, ctrl, c),
          ),
        ],
      ),
    );
  }

  Widget _buildInspectorBody(
      BuildContext context, PodsController ctrl, ContainerInfo c) {
    switch (ctrl.activeInspectorTab) {
      case InspectorTab.summary:
        return _buildSummaryTab(c);
      case InspectorTab.logs:
        return _buildLogsTab(ctrl, c);
      case InspectorTab.terminal:
        return _buildTerminalTab(ctrl, c);
      case InspectorTab.kubeYaml:
        return _buildKubeYamlTab(c);
    }
  }

  Widget _buildSummaryTab(ContainerInfo c) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Live Area Charts
        Row(
          children: [
            Expanded(
              child: _ChartCard(
                title: 'CPU Utilization',
                valueText: '${c.cpuPercent.toStringAsFixed(1)}%',
                samples: c.cpuHistory,
                maxVal: 100.0,
                color: FyrTheme.accentColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ChartCard(
                title: 'Memory RSS',
                valueText: '${c.memUsageMb.round()} MB',
                samples: c.memHistory,
                maxVal: c.memLimitMb,
                color: const Color(0xFF10B981),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _sectionBox(
          title: 'RUNTIME & NETWORKING',
          children: [
            _kvRow('Command', c.command),
            _kvRow('Pod Group', c.podName ?? 'Standalone Container'),
            _kvRow('Network I/O',
                'RX ${c.netRxMb.toStringAsFixed(1)} MB / TX ${c.netTxMb.toStringAsFixed(1)} MB'),
            for (final p in c.ports) _kvRow('Port Binding', p.formatted),
          ],
        ),
        const SizedBox(height: 12),
        _sectionBox(
          title: 'VOLUME MOUNTS (${c.mounts.length})',
          children: c.mounts.isEmpty
              ? [
                  Text('No persistent volumes attached.',
                      style: TextStyle(
                          fontSize: 11.5, color: FyrTheme.textColorMuted))
                ]
              : c.mounts
                  .map((m) => _kvRow('${m.source} (${m.mode})', m.destination))
                  .toList(),
        ),
        const SizedBox(height: 12),
        _sectionBox(
          title: 'ENVIRONMENT VARIABLES (${c.env.length})',
          children: c.env.entries
              .map((e) => _kvRow(e.key, e.value))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildLogsTab(PodsController ctrl, ContainerInfo c) {
    final filteredLogs = c.logs.where((line) {
      if (ctrl.logLevelFilter != 'ALL' &&
          !line.contains('[${ctrl.logLevelFilter}]')) {
        return false;
      }
      if (ctrl.logSearchQuery.trim().isNotEmpty &&
          !line
              .toLowerCase()
              .contains(ctrl.logSearchQuery.trim().toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              for (final lvl in ['ALL', 'INFO', 'WARN', 'ERROR']) ...[
                InkWell(
                  onTap: () => ctrl.setLogLevelFilter(lvl),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: ctrl.logLevelFilter == lvl
                          ? FyrTheme.accentColor.withValues(alpha: 0.2)
                          : FyrTheme.cardColor,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: ctrl.logLevelFilter == lvl
                            ? FyrTheme.accentColor
                            : FyrTheme.dividerColor,
                      ),
                    ),
                    child: Text(
                      lvl,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: ctrl.logLevelFilter == lvl
                            ? FyrTheme.accentColor
                            : FyrTheme.textColorMuted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Expanded(
                child: SizedBox(
                  height: 26,
                  child: TextField(
                    onChanged: ctrl.setLogSearchQuery,
                    style: TextStyle(fontSize: 11.5, color: FyrTheme.textColor),
                    decoration: InputDecoration(
                      hintText: 'Filter log lines...',
                      hintStyle: TextStyle(
                          fontSize: 11, color: FyrTheme.textColorMuted),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      filled: true,
                      fillColor: FyrTheme.cardColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: FyrTheme.dividerColor),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF07080A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: FyrTheme.dividerColor),
            ),
            child: ListView.builder(
              itemCount: filteredLogs.length,
              itemBuilder: (_, i) {
                final line = filteredLogs[i];
                Color lineColor = const Color(0xFFD1D5DB);
                if (line.contains('[ERROR]')) {
                  lineColor = const Color(0xFFF87171);
                } else if (line.contains('[WARN]')) {
                  lineColor = const Color(0xFFFBBF24);
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: SelectableText(
                    line,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: lineColor,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTerminalTab(PodsController ctrl, ContainerInfo c) {
    final transcript = ctrl.terminalTranscripts[c.id] ?? const [];
    final presets = ['ps aux', 'env', 'free -m', 'df -h', 'ip addr', 'uname -a'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          child: Wrap(
            spacing: 5,
            runSpacing: 5,
            children: presets
                .map(
                  (cmd) => InkWell(
                    borderRadius: BorderRadius.circular(5),
                    onTap: () => ctrl.execCommand(c.id, cmd),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: FyrTheme.cardColor,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: FyrTheme.dividerColor),
                      ),
                      child: Text(
                        cmd,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10.5,
                          color: FyrTheme.accentColor,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF060709),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: FyrTheme.dividerColor),
            ),
            child: ListView.builder(
              itemCount: transcript.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: SelectableText(
                  transcript[i],
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: transcript[i].startsWith('root@')
                        ? const Color(0xFF10B981)
                        : const Color(0xFFE5E7EB),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    controller: _execInputCtrl,
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        ctrl.execCommand(c.id, val);
                        _execInputCtrl.clear();
                      }
                    },
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 12, color: FyrTheme.textColor),
                    decoration: InputDecoration(
                      hintText: 'Run command inside ${c.name}...',
                      hintStyle: TextStyle(
                          fontSize: 11.5, color: FyrTheme.textColorMuted),
                      prefixText: '# ',
                      prefixStyle: GoogleFonts.jetBrainsMono(
                          fontSize: 12, color: const Color(0xFF10B981)),
                      filled: true,
                      fillColor: FyrTheme.cardColor,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(7),
                        borderSide: BorderSide(color: FyrTheme.dividerColor),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: FyrTheme.accentColor,
                  foregroundColor:
                      FyrTheme.getContrastingColor(FyrTheme.accentColor),
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: () {
                  final text = _execInputCtrl.text;
                  if (text.trim().isNotEmpty) {
                    ctrl.execCommand(c.id, text);
                    _execInputCtrl.clear();
                  }
                },
                child: const Text('Exec', style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKubeYamlTab(ContainerInfo c) {
    final yamlText = _showComposeInYamlTab
        ? ContainerEngine.generateComposeYaml([c], stackName: c.podName ?? c.name)
        : ContainerEngine.generateKubeYaml(c);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('Kubernetes Pod YAML',
                    style: TextStyle(fontSize: 11)),
                selected: !_showComposeInYamlTab,
                onSelected: (_) =>
                    setState(() => _showComposeInYamlTab = false),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('Compose YAML',
                    style: TextStyle(fontSize: 11)),
                selected: _showComposeInYamlTab,
                onSelected: (_) => setState(() => _showComposeInYamlTab = true),
              ),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Copy Manifest to Clipboard',
                icon: Icon(Icons.copy_rounded,
                    size: 15, color: FyrTheme.textColorMuted),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: yamlText));
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF07080A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: FyrTheme.dividerColor),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                yamlText,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11.5,
                  color: const Color(0xFFE2E8F0),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionBox({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: FyrTheme.cardColor,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: FyrTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: FyrTheme.textColorMuted,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _kvRow(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 135,
            child: Text(
              key,
              style: TextStyle(fontSize: 11, color: FyrTheme.textColorMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: FyrTheme.textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final String valueText;
  final List<double> samples;
  final double maxVal;
  final Color color;

  const _ChartCard({
    required this.title,
    required this.valueText,
    required this.samples,
    required this.maxVal,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: FyrTheme.cardColor,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: FyrTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 11, color: FyrTheme.textColorMuted)),
              Text(
                valueText,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 54,
            width: double.infinity,
            child: CustomPaint(
              painter: _AreaSparklinePainter(
                samples: samples,
                maxVal: maxVal,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AreaSparklinePainter extends CustomPainter {
  final List<double> samples;
  final double maxVal;
  final Color color;

  _AreaSparklinePainter({
    required this.samples,
    required this.maxVal,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2 || size.width <= 0 || size.height <= 0) return;
    final effectiveMax = maxVal <= 0 ? 100.0 : maxVal;

    final linePath = Path();
    final fillPath = Path();

    for (var i = 0; i < samples.length; i++) {
      final x = (i / (samples.length - 1)) * size.width;
      final norm = (samples[i] / effectiveMax).clamp(0.0, 1.0);
      final y = size.height - (norm * (size.height - 4)) - 2;
      if (i == 0) {
        linePath.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        linePath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.38),
          color.withValues(alpha: 0.02),
        ],
      ).createShader(Offset.zero & size);

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(linePath, linePaint);
  }

  @override
  bool shouldRepaint(covariant _AreaSparklinePainter oldDelegate) => true;
}
