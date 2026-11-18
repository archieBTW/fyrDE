import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../fyr_theme.dart';
import '../models/monitor_models.dart';
import '../services/perf_service.dart';
import '../widgets/section_card.dart';
import '../widgets/smooth_area_chart.dart';

/// Tab 3 — 60 second scrolling area charts for CPU, memory/swap and disk/network.
///
/// Sampling only happens while [active] is true. Each tick reads `/proc/stat`,
/// `/proc/meminfo`, `/proc/diskstats` and `/proc/net/dev` — nothing else.
class PerformanceTab extends StatefulWidget {
  const PerformanceTab({super.key, required this.active});

  final bool active;

  @override
  State<PerformanceTab> createState() => _PerformanceTabState();
}

class _PerformanceTabState extends State<PerformanceTab> {
  static const Duration _pollInterval = Duration(milliseconds: 1500);

  final PerfSampler _sampler = PerfSampler();

  Timer? _timer;
  PerformanceSample? _latest;
  bool _sampling = false;

  /// Ring buffers, oldest sample first. Every list holds at most
  /// [kChartSamples] entries which is exactly the 60 s window.
  final List<double> _cpuTotal = [];
  final List<double> _memoryUsed = [];
  final List<double> _memoryCached = [];
  final List<double> _swapUsed = [];
  final List<double> _diskRead = [];
  final List<double> _diskWrite = [];
  final List<double> _netRx = [];
  final List<double> _netTx = [];

  /// Per-core history; the outer list grows as cores appear.
  final List<List<double>> _coreHistory = [];

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(covariant PerformanceTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      // A long pause would otherwise be averaged into one huge spike.
      _sampler.reset();
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
    _sample();
    _timer = Timer.periodic(_pollInterval, (_) => _sample());
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _sample() async {
    if (_sampling) return;
    _sampling = true;
    try {
      final sample = await _sampler.sample();
      if (!mounted) return;
      setState(() {
        _latest = sample;
        _push(_cpuTotal, sample.cpuTotal);
        _push(_memoryUsed, sample.memory.usedMb);
        _push(_memoryCached, sample.memory.cachedMb);
        _push(_swapUsed, sample.memory.swapUsedMb);
        _push(_diskRead, sample.diskReadBytesPerSec);
        _push(_diskWrite, sample.diskWriteBytesPerSec);
        _push(_netRx, sample.netRxBytesPerSec);
        _push(_netTx, sample.netTxBytesPerSec);

        while (_coreHistory.length < sample.cpuCores.length) {
          _coreHistory.add(<double>[]);
        }
        for (var i = 0; i < _coreHistory.length; i++) {
          _push(
            _coreHistory[i],
            i < sample.cpuCores.length ? sample.cpuCores[i] : 0,
          );
        }
      });
    } finally {
      _sampling = false;
    }
  }

  void _push(List<double> buffer, double value) {
    buffer.add(value.isFinite ? value : 0);
    if (buffer.length > kChartSamples) buffer.removeAt(0);
  }

  @override
  Widget build(BuildContext context) {
    final sample = _latest;
    final accent = FyrTheme.accentColor;

    final cpu = _buildCpuCard(sample, accent);
    final memory = _buildMemoryCard(sample, accent);
    final disk = _buildDiskCard(sample, accent);
    final network = _buildNetworkCard(sample, accent);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Two columns as soon as the window is wide enough: the default window
        // size then shows all four charts without scrolling. Narrower windows
        // fall back to a single column.
        final twoColumns = constraints.maxWidth >= 700;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
          child: twoColumns
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [cpu, const SizedBox(height: 10), disk],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [memory, const SizedBox(height: 10), network],
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    cpu,
                    const SizedBox(height: 10),
                    memory,
                    const SizedBox(height: 10),
                    disk,
                    const SizedBox(height: 10),
                    network,
                  ],
                ),
        );
      },
    );
  }

  Widget _buildCpuCard(PerformanceSample? sample, Color accent) {
    final total = sample?.cpuTotal ?? 0;
    final cores = sample?.cpuCores ?? const <double>[];
    final maxCore = cores.isEmpty ? 0.0 : cores.reduce(math.max);

    return SectionCard(
      icon: Icons.memory_rounded,
      title: 'CPU',
      accent: accent,
      trailing: CardMetric(
        value: Units.percent(total),
        caption: '${cores.length} cores · peak ${Units.percent(maxCore)}',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SmoothAreaChart(
            series: [
              ChartSeries(
                label: 'Total',
                color: accent,
                values: _cpuTotal,
              ),
            ],
            maxValue: 100,
            height: 112,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 80,
            child: _buildCoreGrid(cores),
          ),
        ],
      ),
    );
  }

  /// Compact per-core strip; scrolling keeps it readable on 32+ thread CPUs.
  Widget _buildCoreGrid(List<double> cores) {
    if (cores.isEmpty) {
      return Center(
        child: Text(
          'Waiting for the first /proc/stat sample…',
          style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 11),
        ),
      );
    }
    return SingleChildScrollView(
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < cores.length; i++)
            _CoreChip(
              index: i,
              value: cores[i],
              history: i < _coreHistory.length ? _coreHistory[i] : const [],
            ),
        ],
      ),
    );
  }

  Widget _buildMemoryCard(PerformanceSample? sample, Color accent) {
    final memory = sample?.memory ?? MemSnapshot.empty;
    final totalMb = memory.totalMb <= 0 ? 1.0 : memory.totalMb;
    return SectionCard(
      icon: Icons.developer_board_rounded,
      title: 'MEMORY',
      accent: Colors.tealAccent,
      trailing: CardMetric(
        value: Units.memory(memory.usedMb),
        caption: 'of ${Units.memory(memory.totalMb)} · '
            '${Units.percent(memory.usedPercent)}',
        color: Colors.tealAccent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SmoothAreaChart(
            series: [
              ChartSeries(
                label: 'Used',
                color: Colors.tealAccent,
                values: _memoryUsed,
              ),
              ChartSeries(
                label: 'Cached',
                color: Colors.lightBlueAccent,
                values: _memoryCached,
              ),
            ],
            maxValue: totalMb,
            height: 98,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              const ChartLegend(color: Colors.tealAccent, label: 'Used'),
              const ChartLegend(
                color: Colors.lightBlueAccent,
                label: 'Cached',
              ),
              ChartLegend(
                color: Colors.blueGrey,
                label: 'Swap ${Units.memory(memory.swapUsedMb)}',
              ),
            ],
          ),
          const SizedBox(height: 9),
          _StackedBar(
            segments: [
              (value: memory.usedMb, color: Colors.tealAccent),
              (value: memory.cachedMb, color: Colors.lightBlueAccent),
            ],
            total: totalMb,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'SWAP',
                style: TextStyle(
                  color: FyrTheme.textColorMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                sample == null
                    ? '—'
                    : memory.swapTotalMb <= 0
                    ? 'not configured'
                    : '${Units.memory(memory.swapUsedMb)} / '
                          '${Units.memory(memory.swapTotalMb)}',
                style: TextStyle(
                  color: FyrTheme.textColorMuted,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              Text(
                Units.percent(memory.swapPercent),
                style: TextStyle(
                  color: Colors.blueGrey,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (memory.swapPercent / 100).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: FyrTheme.dividerColor,
              valueColor: const AlwaysStoppedAnimation(Colors.blueGrey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiskCard(PerformanceSample? sample, Color accent) {
    final read = sample?.diskReadBytesPerSec ?? 0;
    final write = sample?.diskWriteBytesPerSec ?? 0;
    final peak = math.max(
      _diskRead.isEmpty ? 0.0 : _diskRead.reduce(math.max),
      _diskWrite.isEmpty ? 0.0 : _diskWrite.reduce(math.max),
    );
    return SectionCard(
      icon: Icons.storage_rounded,
      title: 'DISK',
      accent: Colors.amberAccent,
      trailing: CardMetric(
        value: Units.rate(read + write),
        caption: 'read ${Units.rate(read)} · write ${Units.rate(write)}',
        color: Colors.amberAccent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SmoothAreaChart(
            series: [
              ChartSeries(
                label: 'Read',
                color: Colors.amberAccent,
                values: _diskRead,
              ),
              ChartSeries(
                label: 'Write',
                color: Colors.deepOrangeAccent,
                values: _diskWrite,
              ),
            ],
            // Auto-scaling ceiling with a small headroom, minimum 1 MB/s so an
            // idle disk still renders a flat baseline instead of noise.
            maxValue: math.max(peak * 1.25, 1024 * 1024),
            height: 98,
          ),
          const SizedBox(height: 8),
          const Wrap(
            spacing: 14,
            children: [
              ChartLegend(color: Colors.amberAccent, label: 'Read'),
              ChartLegend(color: Colors.deepOrangeAccent, label: 'Write'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkCard(PerformanceSample? sample, Color accent) {
    final rx = sample?.netRxBytesPerSec ?? 0;
    final tx = sample?.netTxBytesPerSec ?? 0;
    final peak = math.max(
      _netRx.isEmpty ? 0.0 : _netRx.reduce(math.max),
      _netTx.isEmpty ? 0.0 : _netTx.reduce(math.max),
    );
    return SectionCard(
      icon: Icons.swap_vert_rounded,
      title: 'NETWORK',
      accent: Colors.lightGreenAccent,
      trailing: CardMetric(
        value: Units.bitRate(rx + tx),
        caption: 'down ${Units.bitRate(rx)} · up ${Units.bitRate(tx)}',
        color: Colors.lightGreenAccent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SmoothAreaChart(
            series: [
              ChartSeries(
                label: 'RX',
                color: Colors.lightGreenAccent,
                values: _netRx,
              ),
              ChartSeries(
                label: 'TX',
                color: Colors.pinkAccent,
                values: _netTx,
              ),
            ],
            maxValue: math.max(peak * 1.25, 64 * 1024),
            height: 98,
          ),
          const SizedBox(height: 8),
          const Wrap(
            spacing: 14,
            children: [
              ChartLegend(color: Colors.lightGreenAccent, label: 'Receiving'),
              ChartLegend(color: Colors.pinkAccent, label: 'Sending'),
            ],
          ),
        ],
      ),
    );
  }
}

class _CoreChip extends StatelessWidget {
  const _CoreChip({
    required this.index,
    required this.value,
    required this.history,
  });

  final int index;
  final double value;
  final List<double> history;

  @override
  Widget build(BuildContext context) {
    final color = value >= 75
        ? Colors.redAccent
        : value >= 40
        ? Colors.orangeAccent
        : FyrTheme.accentColor;
    return Container(
      width: 102,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
      decoration: BoxDecoration(
        color: FyrTheme.cardColor,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: FyrTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                'CPU $index',
                style: TextStyle(
                  color: FyrTheme.textColorMuted,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${value.toStringAsFixed(0)}%',
                style: TextStyle(
                  color: FyrTheme.textColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (value / 100).clamp(0.0, 1.0),
              minHeight: 3.5,
              backgroundColor: FyrTheme.dividerColor,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 5),
          SmoothAreaChart(
            series: [
              ChartSeries(label: 'CPU $index', color: color, values: history),
            ],
            maxValue: 100,
            height: 22,
            showGrid: false,
            strokeWidth: 1.2,
            fillOpacity: 0.24,
          ),
        ],
      ),
    );
  }
}

/// Used/cached composition bar shown under the memory chart.
class _StackedBar extends StatelessWidget {
  const _StackedBar({required this.segments, required this.total});

  final List<({double value, Color color})> segments;
  final double total;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 7,
        child: Row(
          children: [
            for (final segment in segments)
              Expanded(
                flex: math.max(
                  1,
                  ((segment.value / (total <= 0 ? 1 : total)) * 1000).round(),
                ),
                child: ColoredBox(color: segment.color),
              ),
            Expanded(
              flex: 1,
              child: ColoredBox(color: FyrTheme.dividerColor),
            ),
          ],
        ),
      ),
    );
  }
}
