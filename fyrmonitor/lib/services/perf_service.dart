import 'dart:math' as math;

import '../models/monitor_models.dart';
import 'proc_service.dart';

/// Turns absolute `/proc` counters into per-second rates.
///
/// One sampler instance is owned by the Performance tab and is only polled
/// while that tab is visible, so `/proc/stat`, `/proc/meminfo`,
/// `/proc/diskstats` and `/proc/net/dev` are never read for the other tabs.
class PerfSampler {
  /// `/proc/diskstats` always reports 512 byte sectors, regardless of the real
  /// logical sector size of the device.
  static const int _sectorBytes = 512;

  Map<String, CpuTimes>? _previousCpu;
  ({int rxBytes, int txBytes})? _previousNet;
  ({int readSectors, int writeSectors})? _previousDisk;
  DateTime? _previousAt;

  /// Drops the stored baselines so the next sample becomes the new reference.
  /// Called when the tab is re-activated, otherwise a long pause would be
  /// averaged into the first rate spike.
  void reset() {
    _previousCpu = null;
    _previousNet = null;
    _previousDisk = null;
    _previousAt = null;
  }

  Future<PerformanceSample> sample() async {
    final now = DateTime.now();
    final elapsed = _previousAt == null
        ? 0.0
        : now.difference(_previousAt!).inMicroseconds / 1000000.0;

    // Only the four files the Performance tab actually renders.
    final cpu = await ProcService.readCpuTimes();
    final memory = await ProcService.readMemory();
    final disk = await ProcService.readDiskTotals();
    final net = await ProcService.readNetworkTotals();

    final totalUsage = cpu['cpu']?.usageSince(_previousCpu?['cpu']) ?? 0.0;
    final coreLabels = cpu.keys.where((label) => label != 'cpu').toList()
      ..sort(_compareCoreLabels);
    final cores = <double>[
      for (final label in coreLabels) cpu[label]!.usageSince(_previousCpu?[label]),
    ];

    final previousDisk = _previousDisk;
    final previousNet = _previousNet;
    final readBytes = previousDisk == null || elapsed <= 0
        ? 0.0
        : _perSecond(disk.readSectors - previousDisk.readSectors, elapsed) *
              _sectorBytes;
    final writeBytes = previousDisk == null || elapsed <= 0
        ? 0.0
        : _perSecond(disk.writeSectors - previousDisk.writeSectors, elapsed) *
              _sectorBytes;
    final rxBytes = previousNet == null || elapsed <= 0
        ? 0.0
        : _perSecond(net.rxBytes - previousNet.rxBytes, elapsed);
    final txBytes = previousNet == null || elapsed <= 0
        ? 0.0
        : _perSecond(net.txBytes - previousNet.txBytes, elapsed);

    _previousCpu = cpu;
    _previousDisk = disk;
    _previousNet = net;
    _previousAt = now;

    return PerformanceSample(
      cpuTotal: totalUsage,
      cpuCores: cores,
      memory: memory,
      diskReadBytesPerSec: math.max(0, readBytes),
      diskWriteBytesPerSec: math.max(0, writeBytes),
      netRxBytesPerSec: math.max(0, rxBytes),
      netTxBytesPerSec: math.max(0, txBytes),
    );
  }

  /// Clamped so a hot-plugged device (counter reset to zero) shows 0 instead of
  /// a negative spike.
  static double _perSecond(int delta, double elapsedSeconds) =>
      delta <= 0 ? 0 : delta / elapsedSeconds;

  /// Sorts `cpu2` before `cpu10`.
  static int _compareCoreLabels(String a, String b) {
    final left = int.tryParse(a.replaceFirst('cpu', '')) ?? 0;
    final right = int.tryParse(b.replaceFirst('cpu', '')) ?? 0;
    return left.compareTo(right);
  }
}
