import 'package:flutter_test/flutter_test.dart';
import 'package:fyrmonitor/models/monitor_models.dart';
import 'package:fyrmonitor/services/proc_service.dart';

void main() {
  group('parseStatTimes', () {
    test('parses the aggregate and per-core lines', () {
      const stat = '''
cpu  100 0 50 800 50 0 0 0 0 0
cpu0 60 0 30 400 10 0 0 0 0 0
cpu1 40 0 20 400 40 0 0 0 0 0
intr 12345 0 0
''';
      final times = ProcService.parseStatTimes(stat);

      expect(times.keys, containsAll(['cpu', 'cpu0', 'cpu1']));
      // total = 100 + 0 + 50 + 800 + 50 = 1000, idle = 800 + 50 = 850
      expect(times['cpu']!.total, 1000);
      expect(times['cpu']!.idle, 850);
      expect(times['cpu0']!.total, 500);
      expect(times['cpu1']!.total, 500);
    });

    test('ignores guest counters to avoid double counting', () {
      const stat = 'cpu 10 0 10 80 0 0 0 0 5 5\n';
      final times = ProcService.parseStatTimes(stat);
      // Only the first eight counters are summed: 10+0+10+80 = 100.
      expect(times['cpu']!.total, 100);
      expect(times['cpu']!.idle, 80);
    });

    test('usageSince returns 0 for the first sample', () {
      const current = CpuTimes(total: 1000, idle: 800);
      expect(current.usageSince(null), 0);
    });

    test('usageSince computes the busy fraction of the delta', () {
      const previous = CpuTimes(total: 1000, idle: 800);
      // 200 jiffies passed, 150 of which were idle => 25% busy.
      const current = CpuTimes(total: 1200, idle: 950);
      expect(current.usageSince(previous), closeTo(25, 0.001));
    });

    test('usageSince clamps to 0 when counters go backwards', () {
      const previous = CpuTimes(total: 2000, idle: 1000);
      const current = CpuTimes(total: 1000, idle: 500);
      expect(current.usageSince(previous), 0);
    });
  });

  group('parseMeminfo', () {
    test('derives used memory from MemTotal - MemAvailable', () {
      const meminfo = '''
MemTotal:       16000000 kB
MemFree:         2000000 kB
MemAvailable:    9000000 kB
Cached:          4000000 kB
SwapTotal:       2000000 kB
SwapFree:        1500000 kB
''';
      final snapshot = ProcService.parseMeminfo(meminfo);

      expect(snapshot.totalMb, closeTo(15625, 0.01));
      expect(snapshot.usedMb, closeTo(6835.94, 0.5));
      expect(snapshot.cachedMb, closeTo(3906.25, 0.01));
      expect(snapshot.swapTotalMb, closeTo(1953.125, 0.01));
      expect(snapshot.swapUsedMb, closeTo(488.28, 0.5));
    });

    test('handles a machine with swap disabled', () {
      const meminfo = '''
MemTotal:        8000000 kB
MemAvailable:    4000000 kB
SwapTotal:             0 kB
SwapFree:              0 kB
''';
      final snapshot = ProcService.parseMeminfo(meminfo);
      expect(snapshot.swapTotalMb, 0);
      expect(snapshot.swapPercent, 0);
    });

    test('falls back to MemFree when MemAvailable is missing', () {
      const meminfo = 'MemTotal: 1000 kB\nMemFree: 250 kB\n';
      final snapshot = ProcService.parseMeminfo(meminfo);
      expect(snapshot.usedMb, closeTo(750 / 1024, 0.001));
    });
  });

  group('parseDiskstats', () {
    test('sums whole disks and ignores partitions, loops and dm devices', () {
      const diskstats = '''
   8       0 sda 1000 0 5000 0 2000 0 8000 0 0 0 0
   8       1 sda1 900 0 4500 0 1900 0 7800 0 0 0 0
 259       0 nvme0n1 500 0 2000 0 700 0 3000 0 0 0 0
 259       1 nvme0n1p1 480 0 1900 0 650 0 2800 0 0 0 0
   7       0 loop0 10 0 20 0 0 0 0 0 0 0 0
 254       0 dm-0 100 0 400 0 90 0 700 0 0 0 0
''';
      final totals = ProcService.parseDiskstats(diskstats);
      // sda (5000/8000) + nvme0n1 (2000/3000)
      expect(totals.readSectors, 7000);
      expect(totals.writeSectors, 11000);
    });
  });

  group('parseNetDev', () {
    test('sums rx/tx across interfaces but skips loopback', () {
      const netDev = '''
Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo:  900000    1000    0    0    0     0          0         0   900000    1000    0    0    0     0       0          0
  eth0: 1000000    2000    0    0    0     0          0         0   400000    1500    0    0    0     0       0          0
  wlan0: 500000    800    0    0    0     0          0         0   250000     700    0    0    0     0       0          0
''';
      final totals = ProcService.parseNetDev(netDev);
      expect(totals.rxBytes, 1500000);
      expect(totals.txBytes, 650000);
    });
  });

  group('parseProcessTicks', () {
    test('locates utime/stime after the parenthesised comm', () {
      // comm contains a space and a closing paren to prove the parser uses the
      // last ')' rather than the first.
      const stat =
          '4242 (weird ) name) S 1 4242 4242 0 -1 4194304 100 0 0 0 '
          '11 7 0 0 20 0 1 0 900 100000 512 18446744073709551615';
      expect(ProcService.parseProcessTicks(stat), 18);
    });

    test('returns null for a truncated stat line', () {
      expect(ProcService.parseProcessTicks('4242 (bash) S 1 4242'), isNull);
      expect(ProcService.parseProcessTicks('garbage'), isNull);
    });
  });

  group('parseStatmResidentPages', () {
    test('reads the resident field', () {
      expect(ProcService.parseStatmResidentPages('1234 567 89 1 0 100 0'), 567);
    });

    test('returns null when the file is malformed', () {
      expect(ProcService.parseStatmResidentPages('1234'), isNull);
      expect(ProcService.parseStatmResidentPages(''), isNull);
    });
  });

  group('parseUid', () {
    test('extracts the real uid from /proc/[pid]/status', () {
      const status = '''
Name:\tfirefox
State:\tS (sleeping)
Tgid:\t4242
Uid:\t1000\t1000\t1000\t1000
Gid:\t1000\t1000\t1000\t1000
''';
      expect(ProcService.parseUid(status), 1000);
    });

    test('returns null when no Uid line exists', () {
      expect(ProcService.parseUid('Name:\tinit\n'), isNull);
    });
  });

  group('scanProcesses', () {
    test('does not throw when /proc is readable', () async {
      // Smoke test: a live sweep must never throw, even though short lived PIDs
      // routinely disappear between the directory listing and the reads.
      final result = await ProcService.scanProcesses();
      expect(result.processes, isNotEmpty);
      expect(result.ticks.length, result.processes.length);
      for (final process in result.processes) {
        expect(process.pid, greaterThan(0));
        expect(process.name, isNotEmpty);
        expect(process.cpuPercent, greaterThanOrEqualTo(0));
      }
    });

    test('name filter narrows the result set', () async {
      final all = await ProcService.scanProcesses();
      final someName = all.processes.first.name;
      final filtered = await ProcService.scanProcesses(
        query: someName.substring(0, (someName.length / 2).ceil()),
      );
      expect(filtered.processes.length, lessThanOrEqualTo(all.processes.length));
      for (final process in filtered.processes) {
        expect(process.name.toLowerCase(), contains(someName.substring(0, 1).toLowerCase()));
      }
    });

    test('second sweep with the previous ticks yields a finite CPU%', () async {
      final first = await ProcService.scanProcesses();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final second = await ProcService.scanProcesses(
        previousTicks: first.ticks,
        previousAt: first.timestamp,
      );
      for (final process in second.processes) {
        expect(process.cpuPercent.isFinite, isTrue);
        expect(process.cpuPercent, greaterThanOrEqualTo(0));
      }
    });
  });

  group('Units', () {
    test('formats memory in MB and GB', () {
      expect(Units.memory(64), '64.0 MB');
      expect(Units.memory(2048), '2.0 GB');
    });

    test('formats byte rates', () {
      expect(Units.rate(0), '0 B/s');
      expect(Units.rate(512), '512 B/s');
      expect(Units.rate(2048), '2.0 KB/s');
      expect(Units.rate(5 * 1024 * 1024), '5.0 MB/s');
    });

    test('formats network rates in bits', () {
      expect(Units.bitRate(125000), '1.0 Mbps');
      expect(Units.bitRate(0), '0 bps');
    });
  });

  group('WindowInfo', () {
    test('converts resident KiB to MB', () {
      const window = WindowInfo(
        conId: 1,
        pid: 42,
        appId: 'fyrterm',
        title: 'fyrterm',
        workspaceName: '1',
        workspaceNumber: 1,
        rssKb: 2048,
        focused: true,
      );
      expect(window.rssMb, 2.0);
      expect(window.workspaceLabel, '1 · 1');
    });
  });
}
