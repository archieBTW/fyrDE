import 'dart:io';

import 'package:fyrtaskbar/fyr_theme.dart';
import 'package:fyrtaskbar/models/app_entry.dart';

class AppService {
  static List<DesktopApp>? cachedApps;

  static Future<List<DesktopApp>> getInstalledApps() async {
    if (cachedApps != null) return cachedApps!;

    Map<String, DesktopApp> appMap = {};
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

    for (String path in searchPaths) {
      final dir = Directory(path);
      if (await dir.exists()) {
        try {
          final entities = dir.listSync();
          for (var entity in entities) {
            if (entity is File && entity.path.endsWith('.desktop')) {
              try {
                final content = await entity.readAsString();
                final fileId = entity.path.split('/').last;
                String? name;
                String? exec;
                String? icon;
                String? onlyShowIn;
                String? notShowIn;
                bool noDisplay = false;

                for (var line in content.split('\n')) {
                  final trimmed = line.trim();
                  if (trimmed.startsWith('Name=') && name == null) {
                    name = trimmed.substring(5).trim();
                  } else if (trimmed.startsWith('Exec=') && exec == null) {
                    exec = trimmed.substring(5).trim();
                  } else if (trimmed.startsWith('Icon=') && icon == null) {
                    icon = trimmed.substring(5).trim();
                  } else if (trimmed.toLowerCase().startsWith('nodisplay=')) {
                    noDisplay = trimmed.split('=')[1].trim().toLowerCase() == 'true';
                  } else if (trimmed.startsWith('OnlyShowIn=')) {
                    onlyShowIn = trimmed.substring(11).trim();
                  } else if (trimmed.startsWith('NotShowIn=')) {
                    notShowIn = trimmed.substring(10).trim();
                  }
                }

                final currentDesktop = (Platform.environment['XDG_CURRENT_DESKTOP'] ?? 'sway').toLowerCase();
                final currentDesktops = currentDesktop.split(':').map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toSet();
                currentDesktops.addAll(['sway', 'fyr', 'fyrde', 'wlroots']);

                if (onlyShowIn != null && onlyShowIn.trim().isNotEmpty) {
                  final allowed = onlyShowIn.split(';').map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toSet();
                  if (allowed.isNotEmpty && !allowed.any((d) => currentDesktops.contains(d))) {
                    noDisplay = true;
                  }
                }

                if (notShowIn != null && notShowIn.trim().isNotEmpty) {
                  final disallowed = notShowIn.split(';').map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toSet();
                  if (disallowed.any((d) => currentDesktops.contains(d))) {
                    noDisplay = true;
                  }
                }

                if (noDisplay) {
                  appMap.remove(fileId);
                } else if (name != null && exec != null) {
                  // clean up exec line
                  exec = exec
                      .replaceAll(RegExp(r'@@[uU]?\s+%[uUfF]\s+@@'), '')
                      .replaceAll(RegExp(r'@@[uU]?'), '')
                      .replaceAll('@@', '')
                      .replaceAll(RegExp(r'%[a-zA-Z]'), '')
                      .trim();
                if (icon != null && !icon.startsWith('/')) {
                  final possiblePaths = [
                    '/usr/share/pixmaps/$icon.png',
                    '/usr/share/pixmaps/$icon.svg',
                    '/usr/share/icons/${FyrTheme.iconThemeName}/scalable/apps/$icon.svg',
                    '/usr/share/icons/${FyrTheme.iconThemeName}/48/apps/$icon.svg',
                    '${Platform.environment['HOME']}/.local/share/icons/${FyrTheme.iconThemeName}/scalable/apps/$icon.svg',
                    '${Platform.environment['HOME']}/.local/share/icons/${FyrTheme.iconThemeName}/48/apps/$icon.svg',
                    '/usr/share/icons/hicolor/scalable/apps/$icon.svg',
                    '/usr/share/icons/hicolor/48x48/apps/$icon.png',
                    '/usr/share/icons/hicolor/128x128/apps/$icon.png',
                    '/usr/share/icons/hicolor/256x256/apps/$icon.png',
                    '/usr/share/icons/hicolor/512x512/apps/$icon.png',
                    '/usr/share/icons/Adwaita/scalable/apps/$icon.svg',
                    '/usr/share/icons/breeze/apps/48/$icon.svg',
                    '${Platform.environment['HOME']}/.local/share/icons/hicolor/scalable/apps/$icon.svg',
                    '${Platform.environment['HOME']}/.local/share/icons/hicolor/48x48/apps/$icon.png',
                    '${Platform.environment['HOME']}/.local/share/icons/hicolor/128x128/apps/$icon.png',
                    '${Platform.environment['HOME']}/.local/share/icons/hicolor/256x256/apps/$icon.png',
                    '${Platform.environment['HOME']}/.local/share/icons/hicolor/512x512/apps/$icon.png',
                    '${Platform.environment['HOME']}/.local/share/icons/$icon.png',
                    '${Platform.environment['HOME']}/.local/share/icons/$icon.svg',
                  ];
                  for (var p in possiblePaths) {
                    if (await File(p).exists()) {
                      icon = p;
                      break;
                    }
                  }
                }
                  appMap[fileId] = DesktopApp(
                    name: name,
                    exec: exec,
                    icon: icon ?? '',
                    path: entity.path,
                  );
                }
              } catch (e) {}
            }
          }
        } catch (_) {}
      }
    }

    List<DesktopApp> apps = appMap.values.toList();
    apps.sort((a, b) => a.name.compareTo(b.name));
    cachedApps = apps;
    return apps;
  }
}
