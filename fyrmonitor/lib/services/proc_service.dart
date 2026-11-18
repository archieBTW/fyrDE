import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../models/monitor_models.dart';

/// Reader for the Linux `/proc` pseudo filesystem.
///
/// Design rules:
///  * Every file access is individually guarded — a short lived PID vanishing
///    between the `/proc` directory listing and the actual read is completely
///    normal, so [FileSystemException] is swallowed and the pid is skipped.
///  * Parsing is separated from I/O (static `parse*` helpers) so the logic can
///    be unit tested against captured `/proc` snippets without a live kernel.
///  * Only the files required by the caller are touched: the caller decides
///    which sweep to run for the tab that is currently visible.
class ProcService {
  ProcService._();

  /// Page size assumed for the `statm` resident counter (4 KiB on the x86_64 /
  /// aarch64 kernels fyrDE targets).
  static const int pageSize = 4096;

  /// `_SC_CLK_TCK`. 100 on every modern Linux userspace ABI, which is what the
  /// `/proc/[pid]/stat` utime/stime counters are expressed in.
  static const int clockTicksPerSecond = 100;

  /// Cached real UID of the session user, used by the process filter.
  static int? _cachedUid;

  // ---------------------------------------------------------------- CPU ----

  /// Parses `/proc/stat` into `{'cpu': CpuTimes, 'cpu0': CpuTimes, ...}`.
  ///
  /// `guest` / `guest_nice` are intentionally ignored: they are already
  /// accounted for inside `user` / `nice` and would double count.
  static Map<String, CpuTimes> parseStatTimes(String content) {
    final result = <String, CpuTimes>{};
    final cpuLabel = RegExp(r'^cpu\d*$');
    for (final line in const LineSplitter().convert(content)) {
      if (!line.startsWith('cpu')) continue;
      final fields = line.trim().split(RegExp(r'\s+'));
      if (fields.isEmpty || !cpuLabel.hasMatch(fields.first)) continue;
      final values = <int>[];
      for (var i = 1; i < fields.length && values.length < 8; i++) {
        final parsed = int.tryParse(fields[i]);
        if (parsed == null) break;
        values.add(parsed);
      }
      if (values.length < 4) continue;
      final idle = values[3] + (values.length > 4 ? values[4] : 0);
      final total = values.fold<int>(0, (sum, value) => sum + value);
      result[fields.first] = CpuTimes(total: total, idle: idle);
    }
    return result;
  }

  static Future<Map<String, CpuTimes>> readCpuTimes() async {
    try {
      return parseStatTimes(await File('/proc/stat').readAsString());
    } on FileSystemException {
      return const {};
    }
  }

  // ------------------------------------------------------------- Memory ----

  /// Parses the `key: value kB` lines of `/proc/meminfo`.
  static Map<String, int> parseMeminfoKb(String content) {
    final values = <String, int>{};
    final pattern = RegExp(r'^(\w+):\s+(\d+)');
    for (final line in const LineSplitter().convert(content)) {
      final match = pattern.firstMatch(line);
      if (match == null) continue;
      values[match.group(1)!] = int.tryParse(match.group(2)!) ?? 0;
    }
    return values;
  }

  /// `Used` follows the kernel's own definition (`MemTotal - MemAvailable`) so
  /// the numbers line up with `free -m` instead of counting cache as used.
  static MemSnapshot parseMeminfo(String content) {
    final values = parseMeminfoKb(content);
    final totalKb = values['MemTotal'] ?? 0;
    final availableKb = values['MemAvailable'] ?? values['MemFree'] ?? 0;
    final cachedKb = values['Cached'] ?? 0;
    final swapTotalKb = values['SwapTotal'] ?? 0;
    final swapFreeKb = values['SwapFree'] ?? 0;
    return MemSnapshot(
      totalMb: totalKb / 1024.0,
      usedMb: math.max(0, totalKb - availableKb) / 1024.0,
      cachedMb: cachedKb / 1024.0,
      swapTotalMb: swapTotalKb / 1024.0,
      swapUsedMb: math.max(0, swapTotalKb - swapFreeKb) / 1024.0,
    );
  }

  static Future<MemSnapshot> readMemory() async {
    try {
      return parseMeminfo(await File('/proc/meminfo').readAsString());
    } on FileSystemException {
      return MemSnapshot.empty;
    }
  }

  // ----------------------------------------------------------- Disk / Net ----

  /// Whole block devices only — partitions (`sda1`, `nvme0n1p2`) are already
  /// included in their parent's counters and `loop`/`dm` devices would double
  /// count.
  static final RegExp _wholeDiskPattern = RegExp(
    r'^(sd[a-z]+|hd[a-z]+|vd[a-z]+|xvd[a-z]+|nvme\d+n\d+|mmcblk\d+)$',
  );

  /// Sums sectors read/written (512 byte units) of physical disks.
  static ({int readSectors, int writeSectors}) parseDiskstats(String content) {
    var read = 0;
    var write = 0;
    for (final line in const LineSplitter().convert(content)) {
      final fields = line.trim().split(RegExp(r'\s+'));
      if (fields.length < 10) continue;
      if (!_wholeDiskPattern.hasMatch(fields[2])) continue;
      read += int.tryParse(fields[5]) ?? 0;
      write += int.tryParse(fields[9]) ?? 0;
    }
    return (readSectors: read, writeSectors: write);
  }

  static Future<({int readSectors, int writeSectors})> readDiskTotals() async {
    try {
      return parseDiskstats(await File('/proc/diskstats').readAsString());
    } on FileSystemException {
      return (readSectors: 0, writeSectors: 0);
    }
  }

  /// Sums `rx_bytes` / `tx_bytes` of every interface except loopback.
  static ({int rxBytes, int txBytes}) parseNetDev(String content) {
    var rx = 0;
    var tx = 0;
    for (final line in const LineSplitter().convert(content)) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final iface = line.substring(0, colon).trim();
      if (iface.isEmpty || iface == 'lo' || iface.contains('|')) continue;
      final fields = line.substring(colon + 1).trim().split(RegExp(r'\s+'));
      if (fields.length < 9) continue;
      rx += int.tryParse(fields[0]) ?? 0;
      tx += int.tryParse(fields[8]) ?? 0;
    }
    return (rxBytes: rx, txBytes: tx);
  }

  static Future<({int rxBytes, int txBytes})> readNetworkTotals() async {
    try {
      return parseNetDev(await File('/proc/net/dev').readAsString());
    } on FileSystemException {
      return (rxBytes: 0, txBytes: 0);
    }
  }

  // ----------------------------------------------------------- Processes ----

  /// Extracts `utime + stime` from one `/proc/[pid]/stat` line.
  ///
  /// The process name is wrapped in parentheses and may itself contain spaces
  /// or parentheses, so the fields are located after the *last* `)`.
  static int? parseProcessTicks(String stat) {
    final close = stat.lastIndexOf(')');
    if (close < 0 || close + 2 >= stat.length) return null;
    final fields = stat.substring(close + 2).trim().split(RegExp(r'\s+'));
    // fields[0] == state (field 3 of stat), so utime (field 14) is index 11.
    if (fields.length < 13) return null;
    final utime = int.tryParse(fields[11]);
    final stime = int.tryParse(fields[12]);
    if (utime == null || stime == null) return null;
    return utime + stime;
  }

  /// Resident pages from the second field of `/proc/[pid]/statm`.
  static int? parseStatmResidentPages(String statm) {
    final fields = statm.trim().split(RegExp(r'\s+'));
    if (fields.length < 2) return null;
    return int.tryParse(fields[1]);
  }

  /// Real UID from the `Uid:` line of `/proc/[pid]/status`.
  static int? parseUid(String status) {
    for (final line in const LineSplitter().convert(status)) {
      if (!line.startsWith('Uid:')) continue;
      final fields = line.substring(4).trim().split(RegExp(r'\s+'));
      if (fields.isEmpty) return null;
      return int.tryParse(fields.first);
    }
    return null;
  }

  /// Real UID of the current session user, cached after the first lookup.
  static Future<int> currentUid() async {
    final cached = _cachedUid;
    if (cached != null) return cached;
    try {
      final uid = parseUid(await File('/proc/self/status').readAsString());
      if (uid != null) return _cachedUid = uid;
    } on FileSystemException {
      // Fall through to the environment / `id -u` fallbacks.
    }
    final fromEnv = int.tryParse(Platform.environment['UID'] ?? '');
    if (fromEnv != null) return _cachedUid = fromEnv;
    try {
      final result = await Process.run('id', ['-u']);
      final parsed = int.tryParse(result.stdout.toString().trim());
      if (parsed != null) return _cachedUid = parsed;
    } catch (_) {
      // Ignore — the filter simply degrades to "no processes match".
    }
    return _cachedUid = -1;
  }

  /// Numeric directory names inside `/proc`.
  static List<int> listPids() {
    final pids = <int>[];
    try {
      for (final entity in Directory('/proc').listSync(followLinks: false)) {
        final pid = int.tryParse(entity.path.split('/').last);
        if (pid != null) pids.add(pid);
      }
    } on FileSystemException {
      // /proc unavailable (non-Linux host) — return what we have.
    }
    pids.sort();
    return pids;
  }

  /// Resident set size of [pid] in KiB, or 0 when the process already exited.
  static Future<int> readRssKb(int pid) async {
    try {
      final pages = parseStatmResidentPages(
        await File('/proc/$pid/statm').readAsString(),
      );
      return pages == null ? 0 : (pages * pageSize) ~/ 1024;
    } on FileSystemException {
      return 0;
    }
  }

  /// One pass over `/proc`, reading only `comm`, `statm`, `stat` (plus `status`
  /// when [userOnly] is set) for every live pid.
  ///
  /// [query] is applied to the process name before the `stat`/`statm` reads so
  /// a filtered list is genuinely cheaper than an unfiltered one.
  static Future<ProcScanResult> scanProcesses({
    Map<int, int> previousTicks = const {},
    DateTime? previousAt,
    bool userOnly = false,
    String query = '',
  }) async {
    final now = DateTime.now();
    final elapsed = previousAt == null
        ? 0.0
        : now.difference(previousAt).inMicroseconds / 1000000.0;
    final uid = userOnly ? await currentUid() : -1;
    final needle = query.trim().toLowerCase();
    final pids = listPids();
    final processes = <ProcessInfo>[];
    final ticks = <int, int>{};

    // Bounded fan-out keeps the number of open file descriptors sane on
    // machines with thousands of processes while still overlapping the three
    // reads per pid. 96 keeps the peak at ~288 fds, well under the usual 1024
    // soft limit.
    const chunkSize = 96;
    for (var start = 0; start < pids.length; start += chunkSize) {
      final end = math.min(start + chunkSize, pids.length);
      final slice = pids.sublist(start, end);
      final batch = await Future.wait(
        slice.map((pid) => _readProcess(pid, needle, userOnly, uid)),
      );
      for (final raw in batch) {
        if (raw == null) continue;
        ticks[raw.pid] = raw.ticks;
        final previous = previousTicks[raw.pid];
        var cpu = 0.0;
        if (previous != null && elapsed > 0) {
          final delta = raw.ticks - previous;
          cpu = (delta / clockTicksPerSecond) / elapsed * 100.0;
          if (!cpu.isFinite || cpu < 0) cpu = 0;
        }
        processes.add(
          ProcessInfo(
            pid: raw.pid,
            name: raw.name,
            cpuPercent: cpu,
            rssKb: raw.rssKb,
          ),
        );
      }
    }

    return ProcScanResult(processes: processes, ticks: ticks, timestamp: now);
  }

  static Future<_RawProcess?> _readProcess(
    int pid,
    String needle,
    bool userOnly,
    int uid,
  ) async {
    try {
      final name = (await File('/proc/$pid/comm').readAsString()).trim();
      if (name.isEmpty) return null;
      if (needle.isNotEmpty && !name.toLowerCase().contains(needle)) {
        return null;
      }
      if (userOnly) {
        final owner = parseUid(await File('/proc/$pid/status').readAsString());
        if (owner == null || owner != uid) return null;
      }
      final pages = parseStatmResidentPages(
        await File('/proc/$pid/statm').readAsString(),
      );
      final ticks = parseProcessTicks(
        await File('/proc/$pid/stat').readAsString(),
      );
      if (pages == null || ticks == null) return null;
      return _RawProcess(
        pid: pid,
        name: name,
        ticks: ticks,
        rssKb: (pages * pageSize) ~/ 1024,
      );
    } on FileSystemException {
      // The PID exited between the /proc listing and the reads — normal.
      return null;
    } on FormatException {
      return null;
    }
  }
}

class _RawProcess {
  const _RawProcess({
    required this.pid,
    required this.name,
    required this.ticks,
    required this.rssKb,
  });

  final int pid;
  final String name;
  final int ticks;
  final int rssKb;
}
