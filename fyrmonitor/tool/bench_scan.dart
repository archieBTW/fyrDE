// Measures the cost of one `/proc` sweep without any rendering involved.
//
//   dart run tool/bench_scan.dart
//
// Used to keep the "polling is nearly free" claim honest: the 1.5 s timer only
// matters if one sweep is well below the 1500 ms budget.
import 'dart:io';

import 'package:fyrmonitor/services/proc_service.dart';

Future<void> main() async {
  // Warm the page cache and the cached uid so the numbers reflect steady state.
  await ProcService.scanProcesses();
  await ProcService.scanProcesses(userOnly: true);

  const runs = 10;
  var total = Duration.zero;
  var count = 0;

  for (var i = 0; i < runs; i++) {
    final stopwatch = Stopwatch()..start();
    final result = await ProcService.scanProcesses();
    stopwatch.stop();
    total += stopwatch.elapsed;
    count = result.processes.length;
  }

  final averageMs = total.inMicroseconds / runs / 1000;
  stdout.writeln('processes: $count');
  stdout.writeln('average sweep: ${averageMs.toStringAsFixed(1)} ms');
  stdout.writeln('budget used: ${(averageMs / 1500 * 100).toStringAsFixed(2)}% '
      'of the 1500 ms poll interval');
}
