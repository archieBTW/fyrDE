import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fyrtaskbar/fyr_theme.dart';
import 'package:fyrtaskbar/models/app_entry.dart';

class AppService {
  static List<DesktopApp>? cachedApps;
  static Set<String>? searchPathsOverride;
  static final List<StreamSubscription<FileSystemEvent>> _watchers = [];
  static final StreamController<void> _updatesController =
      StreamController<void>.broadcast();
  static final Map<String, String> _iconPathCache = {};
  static Future<List<DesktopApp>>? _inFlightRefresh;

  static Stream<void> get onAppsChanged => _updatesController.stream;

  @visibleForTesting
  static Future<void> resetForTest() async {
    cachedApps = null;
    _iconPathCache.clear();
    _inFlightRefresh = null;
    for (final sub in _watchers) {
      await sub.cancel();
    }
    _watchers.clear();
  }

  static Set<String> _getSearchPaths() {
    if (searchPathsOverride != null) {
      return Set<String>.from(searchPathsOverride!);
    }
    final Set<String> searchPaths = {};
    final home = Platform.environment['HOME'] ?? '';
    if (home.isNotEmpty) {
      searchPaths.add('$home/.local/share/applications');
      searchPaths.add('$home/.local/share/flatpak/exports/share/applications');
    }
    final xdgDataDirs = Platform.environment['XDG_DATA_DIRS'];
    if (xdgDataDirs != null && xdgDataDirs.isNotEmpty) {
      for (var dir in xdgDataDirs.split(':')) {
        if (dir.trim().isNotEmpty) {
          searchPaths.add('${dir.trim()}/applications');
        }
      }
    }
    searchPaths.add('/usr/local/share/applications');
    searchPaths.add('/usr/share/applications');
    searchPaths.add('/var/lib/flatpak/exports/share/applications');
    searchPaths.add('/var/lib/snapd/desktop/applications');
    return searchPaths;
  }

  static void ensureWatchersStarted() {
    if (_watchers.isNotEmpty) return;
    for (final path in _getSearchPaths()) {
      final dir = Directory(path);
      if (!dir.existsSync()) continue;
      try {
        final sub = dir.watch().listen(
          (event) {
            if (event.path.endsWith('.desktop') ||
                event.type == FileSystemEvent.create ||
                event.type == FileSystemEvent.delete ||
                event.type == FileSystemEvent.move) {
              // Refresh in place without clearing cachedApps to null, so
              // opening the Start Menu never hits an empty/loading state.
              getInstalledAppsSync(forceRefresh: true);
              _updatesController.add(null);
            }
          },
          onError: (_) {},
        );
        _watchers.add(sub);
      } catch (_) {}
    }
  }

  static String _resolveIconSync(String icon) {
    if (icon.isEmpty || icon.startsWith('/')) return icon;
    final themeName = FyrTheme.iconThemeName;
    final cacheKey = '$themeName::$icon';
    final cached = _iconPathCache[cacheKey];
    if (cached != null) return cached;

    final home = Platform.environment['HOME'] ?? '';
    final possiblePaths = [
      '/usr/share/pixmaps/$icon.png',
      '/usr/share/pixmaps/$icon.svg',
      '/usr/share/icons/$themeName/scalable/apps/$icon.svg',
      '/usr/share/icons/$themeName/48/apps/$icon.svg',
      if (home.isNotEmpty)
        '$home/.local/share/icons/$themeName/scalable/apps/$icon.svg',
      if (home.isNotEmpty)
        '$home/.local/share/icons/$themeName/48/apps/$icon.svg',
      '/usr/share/icons/hicolor/scalable/apps/$icon.svg',
      '/usr/share/icons/hicolor/48x48/apps/$icon.png',
      '/usr/share/icons/hicolor/128x128/apps/$icon.png',
      '/usr/share/icons/hicolor/256x256/apps/$icon.png',
      '/usr/share/icons/hicolor/512x512/apps/$icon.png',
      '/usr/share/icons/Adwaita/scalable/apps/$icon.svg',
      '/usr/share/icons/breeze/apps/48/$icon.svg',
      if (home.isNotEmpty)
        '$home/.local/share/icons/hicolor/scalable/apps/$icon.svg',
      if (home.isNotEmpty)
        '$home/.local/share/icons/hicolor/48x48/apps/$icon.png',
      if (home.isNotEmpty)
        '$home/.local/share/icons/hicolor/128x128/apps/$icon.png',
      if (home.isNotEmpty)
        '$home/.local/share/icons/hicolor/256x256/apps/$icon.png',
      if (home.isNotEmpty)
        '$home/.local/share/icons/hicolor/512x512/apps/$icon.png',
      if (home.isNotEmpty) '$home/.local/share/icons/$icon.png',
      if (home.isNotEmpty) '$home/.local/share/icons/$icon.svg',
    ];
    for (final p in possiblePaths) {
      if (File(p).existsSync()) {
        _iconPathCache[cacheKey] = p;
        return p;
      }
    }
    _iconPathCache[cacheKey] = icon;
    return icon;
  }

  /// Synchronously scans `.desktop` directories and updates [cachedApps] in
  /// place so the Start Menu always has its application list ready before the
  /// first frame is rendered.
  static List<DesktopApp> getInstalledAppsSync({bool forceRefresh = false}) {
    ensureWatchersStarted();
    if (!forceRefresh && cachedApps != null) return cachedApps!;

    final Map<String, DesktopApp> appMap = {};
    final Set<String> searchPaths = _getSearchPaths();

    final currentDesktop =
        (Platform.environment['XDG_CURRENT_DESKTOP'] ?? 'sway').toLowerCase();
    final currentDesktops = currentDesktop
        .split(':')
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet()
      ..addAll(['sway', 'fyr', 'fyrde', 'wlroots']);

    for (final String path in searchPaths) {
      final dir = Directory(path);
      if (!dir.existsSync()) continue;
      try {
        final entities = dir.listSync();
        for (final entity in entities) {
          if (entity is File && entity.path.endsWith('.desktop')) {
            try {
              final content = entity.readAsStringSync();
              final fileId = entity.path.split('/').last;
              String? name;
              String? exec;
              String? icon;
              String? onlyShowIn;
              String? notShowIn;
              bool noDisplay = false;

              for (final line in content.split('\n')) {
                final trimmed = line.trim();
                if (trimmed.startsWith('Name=') && name == null) {
                  name = trimmed.substring(5).trim();
                } else if (trimmed.startsWith('Exec=') && exec == null) {
                  exec = trimmed.substring(5).trim();
                } else if (trimmed.startsWith('Icon=') && icon == null) {
                  icon = trimmed.substring(5).trim();
                } else if (trimmed.toLowerCase().startsWith('nodisplay=')) {
                  noDisplay =
                      trimmed.split('=')[1].trim().toLowerCase() == 'true';
                } else if (trimmed.startsWith('OnlyShowIn=')) {
                  onlyShowIn = trimmed.substring(11).trim();
                } else if (trimmed.startsWith('NotShowIn=')) {
                  notShowIn = trimmed.substring(10).trim();
                }
              }

              if (onlyShowIn != null && onlyShowIn.trim().isNotEmpty) {
                final allowed = onlyShowIn
                    .split(';')
                    .map((s) => s.trim().toLowerCase())
                    .where((s) => s.isNotEmpty)
                    .toSet();
                if (allowed.isNotEmpty &&
                    !allowed.any((d) => currentDesktops.contains(d))) {
                  noDisplay = true;
                }
              }

              if (notShowIn != null && notShowIn.trim().isNotEmpty) {
                final disallowed = notShowIn
                    .split(';')
                    .map((s) => s.trim().toLowerCase())
                    .where((s) => s.isNotEmpty)
                    .toSet();
                if (disallowed.any((d) => currentDesktops.contains(d))) {
                  noDisplay = true;
                }
              }

              if (noDisplay) {
                appMap.remove(fileId);
              } else if (name != null && exec != null) {
                exec = exec
                    .replaceAll(RegExp(r'@@[uU]?\s+%[uUfF]\s+@@'), '')
                    .replaceAll(RegExp(r'@@[uU]?'), '')
                    .replaceAll('@@', '')
                    .replaceAll(RegExp(r'%[a-zA-Z]'), '')
                    .trim();
                if (icon != null && !icon.startsWith('/')) {
                  icon = _resolveIconSync(icon);
                }
                appMap[fileId] = DesktopApp(
                  name: name,
                  exec: exec,
                  icon: icon ?? '',
                  path: entity.path,
                );
              }
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    final List<DesktopApp> apps = appMap.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    cachedApps = apps;
    return apps;
  }

  static Future<List<DesktopApp>> getInstalledApps({
    bool forceRefresh = false,
  }) async {
    ensureWatchersStarted();
    if (!forceRefresh && cachedApps != null) return cachedApps!;
    if (_inFlightRefresh != null) return _inFlightRefresh!;

    final future = Future<List<DesktopApp>>.value(
      getInstalledAppsSync(forceRefresh: forceRefresh),
    );
    _inFlightRefresh = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlightRefresh, future)) {
        _inFlightRefresh = null;
      }
    }
  }
}
