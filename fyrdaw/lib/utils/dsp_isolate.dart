import 'dart:async';
import 'dart:isolate';

/// Runs CPU-intensive DSP or archive workloads off the Flutter UI thread via
/// [Isolate.run] when [useIsolate] is true, falling back to direct execution
/// when explicitly disabled (e.g., deterministic inline tests).
Future<T> runInBackgroundIsolate<T>(
  FutureOr<T> Function() computation, {
  bool useIsolate = true,
}) {
  if (!useIsolate) {
    return Future<T>.sync(computation);
  }
  return Isolate.run(computation);
}
