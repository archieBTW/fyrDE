import 'dart:io';

import 'package:fyrtaskbar/fyr_theme.dart';
import 'package:fyrtaskbar/models/app_entry.dart';

class AppService {
  static List<DesktopApp>? cachedApps;

  static Future<List<DesktopApp>> getInstalledApps() async {
    if (cachedApps != null) return cachedApps!;

    Map<String, DesktopApp> appMap = {};
    List<String> searchPaths = [
      '/usr/share/applications',
      '${Platform.environment['HOME']}/.local/share/applications',
    ];

    for (String path in searchPaths) {
      final dir = Directory(path);
      if (await dir.exists()) {
        final entities = dir.listSync();
        for (var entity in entities) {
          if (entity is File && entity.path.endsWith('.desktop')) {
            try {
              final content = await entity.readAsString();
              final fileId = entity.path.split('/').last;
              String? name;
              String? exec;
              String? icon;
              bool noDisplay = false;

              for (var line in content.split('\n')) {
                if (line.startsWith('Name=') && name == null) {
                  name = line.substring(5);
                } else if (line.startsWith('Exec=') && exec == null) {
                  exec = line.substring(5);
                } else if (line.startsWith('Icon=') && icon == null) {
                  icon = line.substring(5);
                } else if (line.toLowerCase().startsWith('nodisplay=')) {
                  noDisplay = line.split('=')[1].trim().toLowerCase() == 'true';
                }
              }

              if (noDisplay) {
                appMap.remove(fileId);
              } else if (name != null && exec != null) {
                // clean up exec line
                exec = exec.replaceAll(RegExp(r' %[fFuU]'), '');
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
      }
    }

    List<DesktopApp> apps = appMap.values.toList();
    apps.sort((a, b) => a.name.compareTo(b.name));
    cachedApps = apps;
    return apps;
  }
}
