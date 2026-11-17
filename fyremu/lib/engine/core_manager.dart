import 'dart:io';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../models/emu_types.dart';

class CoreManager {
  static String get homeDir => Platform.environment['HOME'] ?? '/tmp';
  static String get userCoresDir => p.join(homeDir, '.config', 'fyr', 'cores');
  static String get systemDir => p.join(homeDir, '.config', 'fyr', 'bios');
  static String get savesDir => p.join(homeDir, '.config', 'fyr', 'saves');
  static String get statesDir => p.join(homeDir, '.config', 'fyr', 'states');
  static String get romCacheDir => p.join(homeDir, '.cache', 'fyremu', 'roms');

  static List<String> get searchDirs => [
        userCoresDir,
        '/opt/fyremu/cores',
        '/usr/lib/libretro',
        '/usr/lib64/libretro',
        '/usr/local/lib/libretro',
        p.join(homeDir, '.config', 'retroarch', 'cores'),
      ];

  static void ensureDirs() {
    for (final d in [userCoresDir, systemDir, savesDir, statesDir, romCacheDir]) {
      final dir = Directory(d);
      if (!dir.existsSync()) dir.createSync(recursive: true);
    }
  }

  /// Finds an installed `.so` path for [filename], or null if missing.
  static String? findCoreFile(String filename) {
    for (final dir in searchDirs) {
      final candidate = p.join(dir, filename);
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  /// Returns the best available core path for [platform], checking
  /// preferred cores in priority order.
  static String? findBestCoreForPlatform(ConsolePlatform platform) {
    for (final coreName in platform.preferredCores) {
      final found = findCoreFile(coreName);
      if (found != null) return found;
    }
    return null;
  }

  /// Downloads and extracts a libretro core `.so.zip` from Libretro Buildbot
  /// into [userCoresDir].
  static Future<String> downloadCore(CoreDownloadSpec spec) async {
    ensureDirs();
    final resp = await http.get(Uri.parse(spec.buildbotZipUrl));
    if (resp.statusCode != 200) {
      throw Exception(
          'HTTP ${resp.statusCode} downloading ${spec.filename} from Libretro');
    }
    final archive = ZipDecoder().decodeBytes(resp.bodyBytes);
    for (final file in archive) {
      if (file.isFile && file.name.endsWith('.so')) {
        final outPath = p.join(userCoresDir, spec.filename);
        await File(outPath).writeAsBytes(file.content as List<int>);
        return outPath;
      }
    }
    throw Exception('Downloaded archive did not contain a .so core file');
  }

  /// Copies a local `.so` core file into [userCoresDir].
  static Future<String> importLocalCore(String sourceSoPath) async {
    ensureDirs();
    final name = p.basename(sourceSoPath);
    final dst = p.join(userCoresDir, name);
    await File(sourceSoPath).copy(dst);
    return dst;
  }

  /// If [romPath] is a `.zip`, extracts the first supported ROM inside it into
  /// [romCacheDir] and returns `(extractedPath, detectedPlatform)`.
  static Future<({String romPath, ConsolePlatform platform})?> resolveRomPath(
    String romPath,
  ) async {
    final ext = p.extension(romPath).toLowerCase();
    if (ext != '.zip') {
      final plat = ConsolePlatform.fromExtension(ext);
      if (plat == null) return null;
      return (romPath: romPath, platform: plat);
    }

    ensureDirs();
    final bytes = await File(romPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final innerExt = p.extension(entry.name).toLowerCase();
      final plat = ConsolePlatform.fromExtension(innerExt);
      if (plat != null) {
        final outPath = p.join(romCacheDir, p.basename(entry.name));
        await File(outPath).writeAsBytes(entry.content as List<int>);
        return (romPath: outPath, platform: plat);
      }
    }
    return null;
  }
}
