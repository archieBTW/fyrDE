import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fyrmonitor/models/monitor_models.dart';
import 'package:fyrmonitor/services/perf_service.dart';

void main() {
  group('PerfSampler', () {
    test('the first sample has no rates', () async {
      final sampler = PerfSampler();
      final sample = await sampler.sample();

      // No previous counters exist yet, so every delta must be zero rather than
      // a spike covering the whole uptime of the machine.
      expect(sample.diskReadBytesPerSec, 0);
      expect(sample.diskWriteBytesPerSec, 0);
      expect(sample.netRxBytesPerSec, 0);
      expect(sample.netTxBytesPerSec, 0);
      expect(sample.cpuTotal, 0);
    });

    test('subsequent samples stay within sane bounds', () async {
      final sampler = PerfSampler();
      await sampler.sample();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final sample = await sampler.sample();

      expect(sample.cpuTotal, inInclusiveRange(0, 100));
      for (final core in sample.cpuCores) {
        expect(core, inInclusiveRange(0, 100));
      }
      expect(sample.memory.totalMb, greaterThan(0));
      expect(sample.diskReadBytesPerSec, greaterThanOrEqualTo(0));
      expect(sample.netRxBytesPerSec, greaterThanOrEqualTo(0));
      expect(sample.memory.usedPercent, inInclusiveRange(0, 100));
    });

    test('one CPU entry per core, excluding the aggregate', () async {
      final sampler = PerfSampler();
      final sample = await sampler.sample();
      final stat = File('/proc/stat').readAsStringSync();
      final coreLines = stat
          .split('\n')
          .where((line) => RegExp(r'^cpu\d+\s').hasMatch(line))
          .length;
      expect(sample.cpuCores.length, coreLines);
    });

    test('reset() drops the baseline so the next sample is a fresh start',
        () async {
      final sampler = PerfSampler();
      await sampler.sample();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      sampler.reset();
      final sample = await sampler.sample();
      expect(sample.diskReadBytesPerSec, 0);
      expect(sample.netRxBytesPerSec, 0);
      expect(sample.cpuTotal, 0);
    });
  });

  group('MemSnapshot', () {
    test('guards against division by zero on a swap-less machine', () {
      const snapshot = MemSnapshot(
        totalMb: 100,
        usedMb: 50,
        cachedMb: 10,
        swapTotalMb: 0,
        swapUsedMb: 0,
      );
      expect(snapshot.swapPercent, 0);
      expect(snapshot.usedPercent, 50);
    });

    test('empty snapshot is all zeroes', () {
      expect(MemSnapshot.empty.totalMb, 0);
      expect(MemSnapshot.empty.usedPercent, 0);
    });
  });

  group('CpuTimes', () {
    test('full utilisation and full idle', () {
      const previous = CpuTimes(total: 0, idle: 0);
      expect(const CpuTimes(total: 100, idle: 0).usageSince(previous), 100);
      expect(const CpuTimes(total: 100, idle: 100).usageSince(previous), 0);
    });
  });
}
