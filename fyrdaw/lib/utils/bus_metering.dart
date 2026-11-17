import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math';
import 'package:flutter_soloud/flutter_soloud.dart';

typedef _BusSetVisC = ffi.Void Function(ffi.UnsignedInt busId, ffi.Bool enable);
typedef _BusSetVisDart = void Function(int busId, bool enable);

_BusSetVisDart? _cachedBusSetVis;
bool _busSetVisLookedUp = false;
final Set<int> _enabledBusIds = <int>{};

_BusSetVisDart? _lookupBusSetVis() {
  if (_busSetVisLookedUp) return _cachedBusSetVis;
  _busSetVisLookedUp = true;
  try {
    final ffi.DynamicLibrary lib;
    if (Platform.isLinux || Platform.isAndroid) {
      lib = ffi.DynamicLibrary.open('libflutter_soloud_plugin.so');
    } else if (Platform.isWindows) {
      lib = ffi.DynamicLibrary.open('flutter_soloud_plugin.dll');
    } else {
      lib = ffi.DynamicLibrary.process();
    }
    _cachedBusSetVis = lib.lookupFunction<_BusSetVisC, _BusSetVisDart>(
      'busSetVisualizationEnable',
    );
  } catch (_) {
    _cachedBusSetVis = null;
  }
  return _cachedBusSetVis;
}

/// Enables native SoLoud per-bus audio visualization so [Bus.getChannelVolume]
/// returns live channel levels (required because flutter_soloud leaves the
/// C++ `busSetVisualizationEnable` symbol unbound in its Dart FFI wrapper).
void enableBusVisualization(Bus bus) {
  if (_enabledBusIds.contains(bus.busId)) return;
  final fn = _lookupBusSetVis();
  if (fn == null) return;
  try {
    fn(bus.busId, true);
    _enabledBusIds.add(bus.busId);
  } catch (_) {}
}

/// Maximum linear gain allowed by track volume faders (3.0 = 300% / ~+9.5 dB
/// above unity, +12 dB above the 0.75 track default).
const double kMaxTrackVolume = 3.0;

/// Maximum linear gain allowed by the master volume fader.
const double kMaxMasterVolume = 2.0;

/// Creates, plays on engine, and enables visualization for a mixing [Bus] if
/// [existing] is null, or enables visualization on [existing] if needed.
Bus ensureActiveBus(Bus? existing, {String name = ''}) {
  final bus = existing ?? Bus(name: name);
  if (!bus.isActive) {
    bus.playOnEngine();
  }
  enableBusVisualization(bus);
  return bus;
}

/// Converts a linear audio peak amplitude (`0.0..1.0+`) into a normalized
/// `-48 dBFS .. 0 dBFS` (`0.0 .. 1.0`) meter level matching SegmentedVuMeter.
double linearAmpToDbMeter(double amp) {
  if (amp <= 0.0005) return 0.0;
  final db = 20.0 * log(amp.clamp(1e-5, 2.0)) / ln10;
  return ((db + 48.0) / 48.0).clamp(0.0, 1.0);
}

/// Converts a normalized `0.0..1.0` (`-48 dBFS .. 0 dBFS`) meter reading into
/// a compact display string such as `-6.2dB` or `-∞`.
String formatMeterDb(double meterLevel) {
  if (meterLevel <= 0.01) return '-∞';
  final db = (meterLevel.clamp(0.0, 1.0) * 48.0) - 48.0;
  return '${db.toStringAsFixed(1)}dB';
}

