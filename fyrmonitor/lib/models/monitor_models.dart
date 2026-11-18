/// Plain data holders shared by the fyrMonitor tabs.
///
/// Nothing in here touches the filesystem so the models stay trivially
/// testable from `flutter test` without a live `/proc`.
library;

/// A single sway window shown in the "Open Apps" tab.
class WindowInfo {
  const WindowInfo({
    required this.conId,
    required this.pid,
    required this.appId,
    required this.title,
    required this.workspaceName,
    required this.workspaceNumber,
    required this.rssKb,
    required this.focused,
  });

  /// sway container id (`con_id`).
  final int conId;

  /// Owning process id; every row is guaranteed to have a positive pid.
  final int pid;

  /// `app_id` for native Wayland clients, X11 class/instance for XWayland.
  final String appId;
  final String title;
  final String workspaceName;
  final int workspaceNumber;

  /// Resident set size of [pid] read from `/proc/[pid]/statm`.
  final int rssKb;
  final bool focused;

  double get rssMb => rssKb / 1024.0;

  String get workspaceLabel =>
      workspaceNumber >= 0 ? '$workspaceNumber · $workspaceName' : workspaceName;
}

/// A single row of the "Processes" tab.
class ProcessInfo {
  const ProcessInfo({
    required this.pid,
    required this.name,
    required this.cpuPercent,
    required this.rssKb,
  });

  final int pid;

  /// `/proc/[pid]/comm` — the kernel's 15 character process name.
  final String name;

  /// Tick delta of (`utime` + `stime`) normalised by the sampling interval.
  /// 100% == one fully busy core, so a multi-threaded process may exceed 100%.
  final double cpuPercent;

  /// Resident set size in KiB from `/proc/[pid]/statm`.
  final int rssKb;

  double get rssMb => rssKb / 1024.0;
}

/// Result of one `/proc` process sweep.
class ProcScanResult {
  const ProcScanResult({
    required this.processes,
    required this.ticks,
    required this.timestamp,
  });

  final List<ProcessInfo> processes;

  /// Raw `utime + stime` jiffies per pid, fed back in as the next scan's
  /// baseline so CPU percentages never need a second file read.
  final Map<int, int> ticks;
  final DateTime timestamp;
}

/// Aggregated jiffies of one `/proc/stat` cpu line.
class CpuTimes {
  const CpuTimes({required this.total, required this.idle});

  /// Sum of user, nice, system, idle, iowait, irq, softirq and steal jiffies.
  final int total;

  /// idle + iowait jiffies.
  final int idle;

  /// Busy percentage between [previous] and this sample.
  double usageSince(CpuTimes? previous) {
    if (previous == null) return 0;
    final totalDelta = total - previous.total;
    if (totalDelta <= 0) return 0;
    final idleDelta = idle - previous.idle;
    final busy = totalDelta - idleDelta;
    return (busy / totalDelta * 100).clamp(0, 100).toDouble();
  }
}

/// Memory + swap values parsed from `/proc/meminfo`.
class MemSnapshot {
  const MemSnapshot({
    required this.totalMb,
    required this.usedMb,
    required this.cachedMb,
    required this.swapTotalMb,
    required this.swapUsedMb,
  });

  static const MemSnapshot empty = MemSnapshot(
    totalMb: 0,
    usedMb: 0,
    cachedMb: 0,
    swapTotalMb: 0,
    swapUsedMb: 0,
  );

  final double totalMb;
  final double usedMb;
  final double cachedMb;
  final double swapTotalMb;
  final double swapUsedMb;

  double get usedPercent =>
      totalMb <= 0 ? 0 : (usedMb / totalMb * 100).clamp(0, 100).toDouble();

  double get swapPercent => swapTotalMb <= 0
      ? 0
      : (swapUsedMb / swapTotalMb * 100).clamp(0, 100).toDouble();
}

/// One sample of the "Performance" tab.
class PerformanceSample {
  const PerformanceSample({
    required this.cpuTotal,
    required this.cpuCores,
    required this.memory,
    required this.diskReadBytesPerSec,
    required this.diskWriteBytesPerSec,
    required this.netRxBytesPerSec,
    required this.netTxBytesPerSec,
  });

  final double cpuTotal;

  /// Per-core utilisation in core order (`cpu0`, `cpu1`, ...).
  final List<double> cpuCores;
  final MemSnapshot memory;
  final double diskReadBytesPerSec;
  final double diskWriteBytesPerSec;
  final double netRxBytesPerSec;
  final double netTxBytesPerSec;
}

/// Human readable formatting shared by every tab.
class Units {
  Units._();

  static String memory(num mb) {
    final value = mb.toDouble();
    if (value >= 1024) return '${(value / 1024).toStringAsFixed(1)} GB';
    if (value >= 100) return '${value.toStringAsFixed(0)} MB';
    return '${value.toStringAsFixed(1)} MB';
  }

  static String rate(double bytesPerSecond) {
    if (!bytesPerSecond.isFinite || bytesPerSecond <= 0) return '0 B/s';
    if (bytesPerSecond >= 1024 * 1024) {
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    if (bytesPerSecond >= 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${bytesPerSecond.toStringAsFixed(0)} B/s';
  }

  /// `rate()` in bits for the network card, matching what Task Manager shows.
  static String bitRate(double bytesPerSecond) {
    final bits = bytesPerSecond * 8;
    if (bits >= 1000 * 1000 * 1000) {
      return '${(bits / (1000 * 1000 * 1000)).toStringAsFixed(2)} Gbps';
    }
    if (bits >= 1000 * 1000) {
      return '${(bits / (1000 * 1000)).toStringAsFixed(1)} Mbps';
    }
    if (bits >= 1000) return '${(bits / 1000).toStringAsFixed(1)} Kbps';
    return '${bits.toStringAsFixed(0)} bps';
  }

  static String percent(double value) => '${value.toStringAsFixed(1)}%';
}
