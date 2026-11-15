import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

class ExternalPluginControl {
  final String name;
  final double min;
  final double max;
  final double defaultVal;

  const ExternalPluginControl({
    required this.name,
    this.min = 0.0,
    this.max = 1.0,
    this.defaultVal = 0.5,
  });
}

class ExternalPluginInfo {
  final String id; // URI for LV2 or bundle path for VST3
  final String name;
  final String format; // 'LV2' | 'VST3'
  final String category;
  final List<ExternalPluginControl> controls;

  const ExternalPluginInfo({
    required this.id,
    required this.name,
    required this.format,
    required this.category,
    this.controls = const [],
  });
}

typedef _NativeScanC = ffi.Int32 Function(ffi.Pointer<ffi.Int8>, ffi.Int32);
typedef _NativeScanDart = int Function(ffi.Pointer<ffi.Int8>, int);

typedef _NativeProcessC = ffi.Int32 Function(
  ffi.Pointer<ffi.Int8>,
  ffi.Double,
  ffi.Int32,
  ffi.Pointer<ffi.Float>,
  ffi.Pointer<ffi.Float>,
  ffi.Pointer<ffi.Float>,
  ffi.Int32,
);
typedef _NativeProcessDart = int Function(
  ffi.Pointer<ffi.Int8>,
  double,
  int,
  ffi.Pointer<ffi.Float>,
  ffi.Pointer<ffi.Float>,
  ffi.Pointer<ffi.Float>,
  int,
);

/// Native Linux LV2 (`liblilv-0` via FFI) + VST3 bundle scanner & audio processor.
class PluginHost {
  static ffi.DynamicLibrary? _lib;
  static bool _libTried = false;

  static ffi.DynamicLibrary? _openLib() {
    if (_libTried) return _lib;
    _libTried = true;
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      for (final cand in [
        '$exeDir/lib/libsoundbooth_lv2.so',
        'libsoundbooth_lv2.so',
        'build/linux/x64/debug/bundle/lib/libsoundbooth_lv2.so',
        'build/linux/x64/release/bundle/lib/libsoundbooth_lv2.so',
      ]) {
        if (File(cand).existsSync()) {
          _lib = ffi.DynamicLibrary.open(cand);
          break;
        }
      }
    } catch (_) {
      _lib = null;
    }
    return _lib;
  }

  /// Standard Linux LV2 & VST3 plugin search locations.
  static List<String> get searchPaths {
    final home = Platform.environment['HOME'] ?? '';
    return [
      if (home.isNotEmpty) '$home/.lv2',
      '/usr/lib/lv2',
      '/usr/local/lib/lv2',
      if (home.isNotEmpty) '$home/.vst3',
      '/usr/lib/vst3',
      '/usr/local/lib/vst3',
    ];
  }

  /// Scans installed LV2 plugins via native `liblilv-0` (when available) plus
  /// filesystem discovery of `.vst3` / third-party `.lv2` bundles.
  static List<ExternalPluginInfo> scanInstalledPlugins({
    List<String> extraPaths = const [],
  }) {
    final results = <ExternalPluginInfo>[];
    final seenIds = <String>{};

    // 1. Native liblilv-0 scan if native helper library is loaded
    final lib = _openLib();
    if (lib != null) {
      try {
        final scanFn = lib.lookupFunction<_NativeScanC, _NativeScanDart>(
          'sb_lv2_scan',
        );
        const cap = 65536;
        final buf = _callocInt8(cap);
        try {
          if (scanFn(buf, cap) > 0) {
            final raw = _cStringToDart(buf);
            final list = jsonDecode(raw) as List;
            for (final item in list) {
              final uri = (item['uri'] ?? '').toString();
              if (uri.isEmpty || seenIds.contains(uri)) continue;
              seenIds.add(uri);
              final ctrls = ((item['controls'] as List?) ?? [])
                  .map(
                    (c) => ExternalPluginControl(
                      name: (c['name'] ?? 'Param').toString(),
                      min: (c['min'] as num?)?.toDouble() ?? 0.0,
                      max: (c['max'] as num?)?.toDouble() ?? 1.0,
                      defaultVal: (c['default'] as num?)?.toDouble() ?? 0.5,
                    ),
                  )
                  .toList();
              results.add(
                ExternalPluginInfo(
                  id: uri,
                  name: (item['name'] ?? uri).toString(),
                  format: 'LV2',
                  category: (item['category'] ?? 'Effect').toString(),
                  controls: ctrls,
                ),
              );
            }
          }
        } finally {
          _freePtr(buf);
        }
      } catch (_) {}
    }

    // 2. Filesystem scan for .vst3 bundles (including moduleinfo.json) and any extra .lv2 dirs
    for (final dirPath in [...searchPaths, ...extraPaths]) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;
      try {
        for (final ent in dir.listSync()) {
          final base = ent.path.split(Platform.pathSeparator).last;
          if (ent is Directory && base.endsWith('.vst3')) {
            if (seenIds.contains(ent.path)) continue;
            seenIds.add(ent.path);
            String pluginName = base.replaceAll('.vst3', '');
            String cat = 'VST3 Effect';
            final modInfo = File('${ent.path}/Contents/Resources/moduleinfo.json');
            if (modInfo.existsSync()) {
              try {
                final data = jsonDecode(modInfo.readAsStringSync());
                final classes = data['Classes'] as List?;
                if (classes != null && classes.isNotEmpty) {
                  pluginName =
                      (classes.first['Name'] ?? pluginName).toString();
                  cat = (classes.first['Category'] ?? cat).toString();
                }
              } catch (_) {}
            }
            results.add(
              ExternalPluginInfo(
                id: ent.path,
                name: pluginName,
                format: 'VST3',
                category: cat,
                controls: const [
                  ExternalPluginControl(name: 'Mix', defaultVal: 1.0),
                  ExternalPluginControl(name: 'Param 1', defaultVal: 0.5),
                  ExternalPluginControl(name: 'Param 2', defaultVal: 0.5),
                ],
              ),
            );
          } else if (ent is Directory &&
              base.endsWith('.lv2') &&
              !dirPath.startsWith('/usr/lib/lv2')) {
            // Skip standard lv2-spec vocabularies; pick up custom .lv2 bundles if native lib isn't active
            final manifest = File('${ent.path}/manifest.ttl');
            if (manifest.existsSync() &&
                !seenIds.contains(ent.path) &&
                lib == null) {
              seenIds.add(ent.path);
              results.add(
                ExternalPluginInfo(
                  id: ent.path,
                  name: base.replaceAll('.lv2', ''),
                  format: 'LV2',
                  category: 'LV2 Plugin',
                  controls: const [
                    ExternalPluginControl(name: 'Mix', defaultVal: 1.0),
                    ExternalPluginControl(name: 'Drive', defaultVal: 0.5),
                  ],
                ),
              );
            }
          }
        }
      } catch (_) {}
    }
    return results;
  }

  /// Runs an LV2 audio effect plugin natively via `libsoundbooth_lv2.so` over
  /// stereo sample buffers. Returns true if processed natively.
  static bool processLv2StereoInPlace({
    required String pluginUri,
    required List<double> left,
    required List<double> right,
    required Map<String, double> parameters,
    double sampleRate = 44100.0,
  }) {
    final lib = _openLib();
    if (lib == null || left.isEmpty) return false;
    try {
      final procFn = lib.lookupFunction<_NativeProcessC, _NativeProcessDart>(
        'sb_lv2_process_stereo',
      );
      final int n = left.length;
      final uriPtr = _dartStringToC(pluginUri);
      final lPtr = _allocFloats(n);
      final rPtr = _allocFloats(n);
      final vals = parameters.values.toList();
      final ctrlPtr = _allocFloats(vals.isEmpty ? 1 : vals.length);

      try {
        for (int i = 0; i < n; i++) {
          lPtr[i] = left[i];
          rPtr[i] = right[i];
        }
        for (int i = 0; i < vals.length; i++) {
          ctrlPtr[i] = vals[i];
        }
        final rc = procFn(
          uriPtr,
          sampleRate,
          n,
          lPtr,
          rPtr,
          ctrlPtr,
          vals.length,
        );
        if (rc == 0) {
          for (int i = 0; i < n; i++) {
            left[i] = lPtr[i];
            right[i] = rPtr[i];
          }
          return true;
        }
      } finally {
        _freePtr(uriPtr);
        _freePtr(lPtr);
        _freePtr(rPtr);
        _freePtr(ctrlPtr);
      }
    } catch (_) {}
    return false;
  }

  // Minimal POSIX malloc/free lookup from libc so we don't need package:ffi
  static final ffi.DynamicLibrary _libc = ffi.DynamicLibrary.process();
  static final _malloc = _libc.lookupFunction<
    ffi.Pointer<ffi.Void> Function(ffi.IntPtr),
    ffi.Pointer<ffi.Void> Function(int)
  >('malloc');
  static final _free = _libc.lookupFunction<
    ffi.Void Function(ffi.Pointer<ffi.Void>),
    void Function(ffi.Pointer<ffi.Void>)
  >('free');

  static ffi.Pointer<ffi.Int8> _callocInt8(int len) {
    final p = _malloc(len).cast<ffi.Int8>();
    for (int i = 0; i < len; i++) {
      p[i] = 0;
    }
    return p;
  }

  static ffi.Pointer<ffi.Float> _allocFloats(int count) =>
      _malloc(count * ffi.sizeOf<ffi.Float>()).cast<ffi.Float>();

  static ffi.Pointer<ffi.Int8> _dartStringToC(String s) {
    final bytes = utf8.encode(s);
    final p = _callocInt8(bytes.length + 1);
    for (int i = 0; i < bytes.length; i++) {
      p[i] = bytes[i];
    }
    p[bytes.length] = 0;
    return p;
  }

  static String _cStringToDart(ffi.Pointer<ffi.Int8> ptr) {
    final bytes = <int>[];
    for (int i = 0; ; i++) {
      final b = ptr[i];
      if (b == 0) break;
      bytes.add(b & 0xFF);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static void _freePtr(ffi.Pointer p) => _free(p.cast<ffi.Void>());
}
