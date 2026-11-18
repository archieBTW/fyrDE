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
  const PerformanceTab({
    super.key,
    required this.active,
    this.initialSample,
    this.initialHistory,
  });

  final bool active;
  final PerformanceSample? initialSample;
  final List<PerformanceSample>? initialHistory;

  @override
  State<PerformanceTab> createState() => _PerformanceTabState();
}

class _PerformanceTabState extends State<PerformanceTab> {
  static const Duration _pollInterval = Duration(milliseconds: 1500);
  static const double _footerHeight = 78;
  static const double _chartHeight = 104;

  static const Color _memUsedColor = Color(0xFF38BDF8);
  static const Color _memCachedColor = Color(0xFF818CF8);
  static const Color _swapColor = Color(0xFF64748B);
  static const Color _diskReadColor = Color(0xFFFBBF24);
  static const Color _diskWriteColor = Color(0xFFFB7185);
  static const Color _netRxColor = Color(0xFF34D399);
  static const Color _netTxColor = Color(0xFFF472B6);

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
    final history = widget.initialHistory;
    if (history != null && history.isNotEmpty) {
      for (final s in history) {
        _ingestSample(s);
      }
    } else if (widget.initialSample != null) {
      _ingestSample(widget.initialSample!);
    }
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

  void _ingestSample(PerformanceSample sample) {
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
  }

  Future<void> _sample() async {
    if (_sampling) return;
    _sampling = true;
    try {
      final sample = await _sampler.sample();
      if (!mounted) return;
      setState(() {
        _ingestSample(sample);
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 680;
        final expandGrid = twoColumns && constraints.maxHeight >= 520;

        final cpu = _buildCpuCard(sample, accent, expandChart: expandGrid);
        final memory = _buildMemoryCard(sample, expandChart: expandGrid);
        final disk = _buildDiskCard(sample, expandChart: expandGrid);
        final network = _buildNetworkCard(sample, expandChart: expandGrid);

        if (expandGrid) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: cpu),
                      const SizedBox(width: 12),
                      Expanded(child: memory),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: disk),
                      const SizedBox(width: 12),
                      Expanded(child: network),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          child: twoColumns
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: cpu),
                          const SizedBox(width: 12),
                          Expanded(child: memory),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: disk),
                          const SizedBox(width: 12),
                          Expanded(child: network),
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    cpu,
                    const SizedBox(height: 12),
                    memory,
                    const SizedBox(height: 12),
                    disk,
                    const SizedBox(height: 12),
                    network,
                  ],
                ),
        );
      },
    );
  }

  Widget _buildChartWell({
    required List<ChartSeries> series,
    required double maxValue,
    required List<Widget> legends,
    required bool expandChart,
  }) {
    final isDark = FyrTheme.isDark;
    final chart = SmoothAreaChart(
      series: series,
      maxValue: maxValue,
      height: _chartHeight,
    );

    final content = Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 6),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF07070A)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: FyrTheme.dividerColor.withValues(alpha: isDark ? 0.7 : 0.9),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: legends,
                ),
              ),
              Text(
                '60s',
                style: TextStyle(
                  color: FyrTheme.textColorMuted.withValues(alpha: 0.55),
                  fontSize: 9.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (expandChart)
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => SmoothAreaChart(
                  series: series,
                  maxValue: maxValue,
                  height: math.max(56, box.maxHeight),
                ),
              ),
            )
          else
            chart,
        ],
      ),
    );

    if (expandChart) {
      return Expanded(child: content);
    }
    return content;
  }

  Widget _buildCpuCard(
    PerformanceSample? sample,
    Color accent, {
    required bool expandChart,
  }) {
    final total = sample?.cpuTotal ?? 0;
    final cores = sample?.cpuCores ?? const <double>[];
    final maxCore = cores.isEmpty ? 0.0 : cores.reduce(math.max);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildChartWell(
          series: [
            ChartSeries(
              label: 'Total',
              color: accent,
              values: _cpuTotal,
            ),
          ],
          maxValue: 100,
          legends: [
            ChartLegend(color: accent, label: 'Total Utilization'),
          ],
          expandChart: expandChart,
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: _footerHeight,
          child: _buildCoreGrid(cores),
        ),
      ],
    );

    return SectionCard(
      icon: Icons.memory_rounded,
      title: 'CPU',
      subtitle: 'Processor load',
      accent: accent,
      trailing: CardMetric(
        value: Units.percent(total),
        caption: '${cores.length} cores · peak ${Units.percent(maxCore)}',
        color: accent,
      ),
      child: expandChart ? Expanded(child: body) : body,
    );
  }

  /// Responsive per-core grid where every row stretches evenly across the card.
  Widget _buildCoreGrid(List<double> cores) {
    if (cores.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: FyrTheme.cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: FyrTheme.dividerColor),
        ),
        alignment: Alignment.center,
        child: Text(
          'Waiting for the first /proc/stat sample…',
          style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 11),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxCols = (constraints.maxWidth / 92).floor().clamp(2, 6);
        int cols = maxCols;
        if (cores.length <= maxCols) {
          cols = math.max(1, cores.length);
        } else if (cores.length % 4 == 0 && maxCols >= 4) {
          cols = 4;
        } else if (cores.length % 3 == 0 && maxCols >= 3) {
          cols = 3;
        }

        final rowCount = (cores.length / cols).ceil();
        return SingleChildScrollView(
          child: Column(
            children: [
              for (var r = 0; r < rowCount; r++) ...[
                if (r > 0) const SizedBox(height: 6),
                Row(
                  children: [
                    for (var c = 0; c < cols; c++) ...[
                      if (c > 0) const SizedBox(width: 6),
                      Expanded(
                        child: (r * cols + c) < cores.length
                            ? _CoreChip(
                                index: r * cols + c,
                                value: cores[r * cols + c],
                                history:
                                    (r * cols + c) < _coreHistory.length
                                        ? _coreHistory[r * cols + c]
                                        : const [],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildMemoryCard(
    PerformanceSample? sample, {
    required bool expandChart,
  }) {
    final memory = sample?.memory ?? MemSnapshot.empty;
    final totalMb = memory.totalMb <= 0 ? 1.0 : memory.totalMb;
    final freeMb = math.max(0.0, memory.totalMb - memory.usedMb - memory.cachedMb);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildChartWell(
          series: [
            ChartSeries(
              label: 'Used',
              color: _memUsedColor,
              values: _memoryUsed,
            ),
            ChartSeries(
              label: 'Cached',
              color: _memCachedColor,
              values: _memoryCached,
            ),
          ],
          maxValue: totalMb,
          legends: [
            const ChartLegend(color: _memUsedColor, label: 'Used'),
            const ChartLegend(color: _memCachedColor, label: 'Cached'),
            ChartLegend(
              color: _swapColor,
              label: 'Swap ${Units.memory(memory.swapUsedMb)}',
            ),
          ],
          expandChart: expandChart,
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: _footerHeight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: FyrTheme.cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: FyrTheme.dividerColor),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          'RAM',
                          style: TextStyle(
                            color: FyrTheme.textColorMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.7,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Cached ${Units.memory(memory.cachedMb)} · Free ${Units.memory(freeMb)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: FyrTheme.textColorMuted,
                              fontSize: 10.5,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        Text(
                          Units.percent(memory.usedPercent),
                          style: const TextStyle(
                            color: _memUsedColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    _StackedBar(
                      segments: [
                        (value: memory.usedMb, color: _memUsedColor),
                        (value: memory.cachedMb, color: _memCachedColor),
                      ],
                      total: totalMb,
                    ),
                  ],
                ),
                Column(
                  children: [
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
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            sample == null
                                ? '—'
                                : memory.swapTotalMb <= 0
                                    ? 'not configured'
                                    : '${Units.memory(memory.swapUsedMb)} / '
                                          '${Units.memory(memory.swapTotalMb)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: FyrTheme.textColorMuted,
                              fontSize: 10.5,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        Text(
                          Units.percent(memory.swapPercent),
                          style: const TextStyle(
                            color: _swapColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (memory.swapPercent / 100).clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: FyrTheme.dividerColor,
                        valueColor: const AlwaysStoppedAnimation(_swapColor),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );

    return SectionCard(
      icon: Icons.developer_board_rounded,
      title: 'MEMORY',
      subtitle: 'Physical & swap',
      accent: _memUsedColor,
      trailing: CardMetric(
        value: Units.memory(memory.usedMb),
        caption: 'of ${Units.memory(memory.totalMb)} · '
            '${Units.percent(memory.usedPercent)}',
        color: _memUsedColor,
      ),
      child: expandChart ? Expanded(child: body) : body,
    );
  }

  Widget _buildDiskCard(
    PerformanceSample? sample, {
    required bool expandChart,
  }) {
    final read = sample?.diskReadBytesPerSec ?? 0;
    final write = sample?.diskWriteBytesPerSec ?? 0;
    final peak = math.max(
      _diskRead.isEmpty ? 0.0 : _diskRead.reduce(math.max),
      _diskWrite.isEmpty ? 0.0 : _diskWrite.reduce(math.max),
    );
    final double ceiling = math.max<double>(peak * 1.25, 1024.0 * 1024.0);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildChartWell(
          series: [
            ChartSeries(
              label: 'Read',
              color: _diskReadColor,
              values: _diskRead,
            ),
            ChartSeries(
              label: 'Write',
              color: _diskWriteColor,
              values: _diskWrite,
            ),
          ],
          maxValue: ceiling,
          legends: const [
            ChartLegend(color: _diskReadColor, label: 'Read'),
            ChartLegend(color: _diskWriteColor, label: 'Write'),
          ],
          expandChart: expandChart,
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: _footerHeight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: FyrTheme.cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: FyrTheme.dividerColor),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _RateBarRow(
                  label: 'READ',
                  detail: 'Peak ${Units.rate(_diskRead.isEmpty ? 0 : _diskRead.reduce(math.max))}',
                  valueText: Units.rate(read),
                  fraction: (read / ceiling).clamp(0.0, 1.0),
                  color: _diskReadColor,
                ),
                _RateBarRow(
                  label: 'WRITE',
                  detail: 'Peak ${Units.rate(_diskWrite.isEmpty ? 0 : _diskWrite.reduce(math.max))}',
                  valueText: Units.rate(write),
                  fraction: (write / ceiling).clamp(0.0, 1.0),
                  color: _diskWriteColor,
                ),
              ],
            ),
          ),
        ),
      ],
    );

    return SectionCard(
      icon: Icons.storage_rounded,
      title: 'DISK',
      subtitle: 'Block device I/O',
      accent: _diskReadColor,
      trailing: CardMetric(
        value: Units.rate(read + write),
        caption: 'read ${Units.rate(read)} · write ${Units.rate(write)}',
        color: _diskReadColor,
      ),
      child: expandChart ? Expanded(child: body) : body,
    );
  }

  Widget _buildNetworkCard(
    PerformanceSample? sample, {
    required bool expandChart,
  }) {
    final rx = sample?.netRxBytesPerSec ?? 0;
    final tx = sample?.netTxBytesPerSec ?? 0;
    final peak = math.max(
      _netRx.isEmpty ? 0.0 : _netRx.reduce(math.max),
      _netTx.isEmpty ? 0.0 : _netTx.reduce(math.max),
    );
    final double ceiling = math.max<double>(peak * 1.25, 64.0 * 1024.0);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildChartWell(
          series: [
            ChartSeries(
              label: 'RX',
              color: _netRxColor,
              values: _netRx,
            ),
            ChartSeries(
              label: 'TX',
              color: _netTxColor,
              values: _netTx,
            ),
          ],
          maxValue: ceiling,
          legends: const [
            ChartLegend(color: _netRxColor, label: 'Receiving'),
            ChartLegend(color: _netTxColor, label: 'Sending'),
          ],
          expandChart: expandChart,
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: _footerHeight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: FyrTheme.cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: FyrTheme.dividerColor),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _RateBarRow(
                  label: 'DOWN',
                  detail: 'Peak ${Units.bitRate(_netRx.isEmpty ? 0 : _netRx.reduce(math.max))}',
                  valueText: Units.bitRate(rx),
                  fraction: (rx / ceiling).clamp(0.0, 1.0),
                  color: _netRxColor,
                ),
                _RateBarRow(
                  label: 'UP',
                  detail: 'Peak ${Units.bitRate(_netTx.isEmpty ? 0 : _netTx.reduce(math.max))}',
                  valueText: Units.bitRate(tx),
                  fraction: (tx / ceiling).clamp(0.0, 1.0),
                  color: _netTxColor,
                ),
              ],
            ),
          ),
        ),
      ],
    );

    return SectionCard(
      icon: Icons.swap_vert_rounded,
      title: 'NETWORK',
      subtitle: 'Interface traffic',
      accent: _netRxColor,
      trailing: CardMetric(
        value: Units.bitRate(rx + tx),
        caption: 'down ${Units.bitRate(rx)} · up ${Units.bitRate(tx)}',
        color: _netRxColor,
      ),
      child: expandChart ? Expanded(child: body) : body,
    );
  }
}

class _RateBarRow extends StatelessWidget {
  const _RateBarRow({
    required this.label,
    required this.detail,
    required this.valueText,
    required this.fraction,
    required this.color,
  });

  final String label;
  final String detail;
  final String valueText;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: FyrTheme.textColorMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: FyrTheme.textColorMuted.withValues(alpha: 0.75),
                  fontSize: 10.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Text(
              valueText,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction.clamp(0.0, 1.0),
            minHeight: 5,
            backgroundColor: FyrTheme.dividerColor,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
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
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      decoration: BoxDecoration(
        color: FyrTheme.cardColor,
        borderRadius: BorderRadius.circular(8),
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
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (value / 100).clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: FyrTheme.dividerColor,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 3),
          SmoothAreaChart(
            series: [
              ChartSeries(label: 'CPU $index', color: color, values: history),
            ],
            maxValue: 100,
            height: 14,
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
    final denom = total <= 0 ? 1.0 : total;
    final usedFraction = segments.fold<double>(
      0,
      (sum, seg) => sum + (seg.value / denom),
    );
    final freeFlex = math.max(1, ((1.0 - usedFraction).clamp(0.0, 1.0) * 1000).round());

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 5,
        child: Row(
          children: [
            for (final segment in segments)
              if (segment.value > 0)
                Expanded(
                  flex: math.max(1, ((segment.value / denom) * 1000).round()),
                  child: ColoredBox(color: segment.color),
                ),
            Expanded(
              flex: freeFlex,
              child: ColoredBox(color: FyrTheme.dividerColor),
            ),
          ],
        ),
      ),
    );
  }
}
