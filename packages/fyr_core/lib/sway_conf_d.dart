import 'dart:io';

/// Helpers for reading and atomically writing Sway drop-in configuration files
/// under `~/.config/sway/conf.d/` so user settings survive reinstalls.
class SwayConfD {
  static String homeDir({String? homeOverride}) =>
      homeOverride ?? Platform.environment['HOME'] ?? '';

  static String swayDirPath({String? homeOverride}) =>
      '${homeDir(homeOverride: homeOverride)}/.config/sway';

  static String confDirPath({String? homeOverride}) =>
      '${swayDirPath(homeOverride: homeOverride)}/conf.d';

  static String mainConfigPath({String? homeOverride}) =>
      '${swayDirPath(homeOverride: homeOverride)}/config';

  /// Atomically writes [content] into `~/.config/sway/conf.d/<fileName>`.
  ///
  /// Ensures `~/.config/sway/config` includes `conf.d/*.conf` if it already exists
  /// without an include directive, and optionally runs `swaymsg reload`.
  static Future<void> writeDropIn(
    String fileName,
    String content, {
    String? homeOverride,
    bool reload = true,
  }) async {
    final dir = Directory(confDirPath(homeOverride: homeOverride));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final targetPath = '${dir.path}/$fileName';
    final normalized = content.endsWith('\n') || content.isEmpty
        ? content
        : '$content\n';
    await writeFileAtomic(targetPath, normalized);

    await _ensureConfDIncluded(homeOverride: homeOverride);

    if (reload) {
      await reloadSway();
    }
  }

  /// Reads `~/.config/sway/conf.d/<fileName>`, returning `null` if absent.
  static Future<String?> readDropIn(
    String fileName, {
    String? homeOverride,
  }) async {
    final file = File(
      '${confDirPath(homeOverride: homeOverride)}/$fileName',
    );
    if (!file.existsSync()) return null;
    return file.readAsString();
  }

  /// Reads `~/.config/sway/conf.d/<fileName>` if present; otherwise falls back
  /// to extracting the legacy marker block from `~/.config/sway/config`.
  static Future<String?> readDropInOrLegacyBlock(
    String fileName, {
    required String startMarker,
    required String endMarker,
    String? homeOverride,
  }) async {
    final dropIn = await readDropIn(fileName, homeOverride: homeOverride);
    if (dropIn != null) return dropIn;

    final mainFile = File(mainConfigPath(homeOverride: homeOverride));
    if (!mainFile.existsSync()) return null;

    final lines = await mainFile.readAsLines();
    final buffer = <String>[];
    var inSection = false;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed == startMarker) {
        inSection = true;
        buffer.add(line);
        continue;
      }
      if (trimmed == endMarker && inSection) {
        buffer.add(line);
        return buffer.join('\n');
      }
      if (inSection) {
        buffer.add(line);
      }
    }
    return null;
  }

  /// Removes a legacy marker block (e.g. `# TOUCHPAD SETTINGS` .. `# END TOUCHPAD SETTINGS`)
  /// from `~/.config/sway/config` so `conf.d/` owns those settings cleanly.
  static Future<void> removeLegacyMarkerBlock(
    String startMarker,
    String endMarker, {
    String? homeOverride,
  }) async {
    final mainFile = File(mainConfigPath(homeOverride: homeOverride));
    if (!mainFile.existsSync()) return;

    final lines = await mainFile.readAsLines();
    final filtered = <String>[];
    var inSection = false;
    var removedAny = false;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed == startMarker) {
        inSection = true;
        removedAny = true;
        continue;
      }
      if (trimmed == endMarker && inSection) {
        inSection = false;
        continue;
      }
      if (!inSection) {
        filtered.add(line);
      }
    }
    if (removedAny) {
      await writeFileAtomic(mainFile.path, '${filtered.join('\n')}\n');
    }
  }

  static Future<void> _ensureConfDIncluded({String? homeOverride}) async {
    final mainFile = File(mainConfigPath(homeOverride: homeOverride));
    if (!mainFile.existsSync()) return;

    final content = await mainFile.readAsString();
    if (content.contains('conf.d/*.conf')) return;

    final trimmedRight = content.trimRight();
    final updated =
        '$trimmedRight\n\n# User-managed drop-in overrides (preserved across updates)\ninclude ~/.config/sway/conf.d/*.conf\n';
    await writeFileAtomic(mainFile.path, updated);
  }

  /// Atomically writes [content] to [path] via a temporary sibling file rename.
  static Future<void> writeFileAtomic(String path, String content) async {
    final tempFile = File('$path.tmp');
    await tempFile.writeAsString(content);
    await tempFile.rename(path);
  }

  static Future<void> reloadSway() async {
    try {
      await Process.run('swaymsg', ['reload']);
    } catch (_) {
      // Ignore outside an active Sway session (e.g. unit tests / CI).
    }
  }
}
