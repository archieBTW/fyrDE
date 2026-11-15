import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'sway_conf_d.dart';

/// Shared theme state, colors, and filesystem watcher for all fyrDE apps.
class FyrTheme {
  static const Color defaultAccent = Colors.purpleAccent;

  static final ValueNotifier<Color> accentColorNotifier = ValueNotifier<Color>(
    defaultAccent,
  );
  static final ValueNotifier<ThemeMode> themeModeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.dark);

  static StreamSubscription<FileSystemEvent>? _watchSub;
  static String? _homeOverride;

  static String get _fyrConfigDirPath =>
      '${SwayConfD.homeDir(homeOverride: _homeOverride)}/.config/fyr';

  /// Loads persisted theme color and mode and watches `~/.config/fyr` for changes
  /// using native filesystem events instead of periodic polling.
  static void initialize({String? homeOverride, bool watch = true}) {
    _homeOverride = homeOverride;
    _updateColor();
    _updateMode();
    if (!watch) return;

    _watchSub?.cancel();
    _watchSub = null;
    try {
      final dir = Directory(_fyrConfigDirPath);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      _watchSub = dir
          .watch(
            events:
                FileSystemEvent.create |
                FileSystemEvent.modify |
                FileSystemEvent.move,
          )
          .listen(
            (event) {
              if (event.path.endsWith('/theme.txt') ||
                  event.path.endsWith('/theme.txt.tmp')) {
                _updateColor();
              } else if (event.path.endsWith('/theme_mode.txt') ||
                  event.path.endsWith('/theme_mode.txt.tmp')) {
                _updateMode();
              }
            },
            onError: (_) {},
          );
    } catch (_) {
      // Ignore watch setup failures in restricted test environments.
    }
  }

  static Future<void> dispose() async {
    await _watchSub?.cancel();
    _watchSub = null;
  }

  static void _updateColor() {
    try {
      final file = File('$_fyrConfigDirPath/theme.txt');
      if (file.existsSync()) {
        final colorStr = file.readAsStringSync().trim();
        if (colorStr.isNotEmpty && colorStr.length == 8) {
          final newColor = Color(int.parse(colorStr, radix: 16));
          if (accentColorNotifier.value != newColor) {
            accentColorNotifier.value = newColor;
          }
          return;
        }
      }
    } catch (_) {
      // Ignore parse/read errors.
    }
  }

  static void _updateMode() {
    try {
      final file = File('$_fyrConfigDirPath/theme_mode.txt');
      if (file.existsSync()) {
        final modeStr = file.readAsStringSync().trim().toLowerCase();
        final newMode = modeStr == 'light' ? ThemeMode.light : ThemeMode.dark;
        if (themeModeNotifier.value != newMode) {
          themeModeNotifier.value = newMode;
        }
        return;
      }
    } catch (_) {
      // Ignore read errors.
    }
  }

  static Color get accentColor => accentColorNotifier.value;
  static ThemeMode get themeMode => themeModeNotifier.value;

  static bool get isDark => themeMode == ThemeMode.dark;
  static Color get textColor => isDark ? Colors.white : Colors.black87;
  static Color get textColorMuted => isDark ? Colors.white70 : Colors.black54;
  static Color get bgColor =>
      isDark ? const Color(0xFF000000) : Colors.white;
  /// Translucent glass background for compositor-blurred shell panels, docks,
  /// menus, and notification cards.
  static Color get panelBgColor => isDark
      ? const Color(0xFF2A282C).withOpacity(0.8)
      : Colors.white.withOpacity(0.9);
  static Color get sidebarColor =>
      isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
  static Color get surfaceColor =>
      isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFFFFFF);
  static Color get contentColor =>
      isDark ? const Color(0xFF0A0A0A) : const Color(0xFFFFFFFF);
  static Color get cardColor =>
      isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFFFFFFF);
  static Color get hoverColor =>
      isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05);
  static Color get dividerColor =>
      isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.08);

  static Color getContrastingColor(Color color) {
    return color.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  }

  static Future<void> setAccentColor(
    Color color, {
    String? homeOverride,
    bool updateSystemSettings = true,
  }) async {
    final effectiveHome = homeOverride ?? _homeOverride;
    try {
      final dir = Directory(
        '${SwayConfD.homeDir(homeOverride: effectiveHome)}/.config/fyr',
      );
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      await SwayConfD.writeFileAtomic(
        '${dir.path}/theme.txt',
        color.value.toRadixString(16).padLeft(8, '0'),
      );
      accentColorNotifier.value = color;

      if (updateSystemSettings) {
        await _updateGtkSettings(
          themeModeNotifier.value,
          color: color,
          homeOverride: effectiveHome,
        );
        final hexColor =
            '#${color.value.toRadixString(16).substring(2).padLeft(6, '0')}';
        await SwayConfD.writeDropIn(
          '10-theme.conf',
          'client.focused $hexColor $hexColor #ffffff $hexColor $hexColor\n',
          homeOverride: effectiveHome,
          reload: true,
        );
      }
    } catch (_) {
      // Ignore persistence errors.
    }
  }

  static String get iconThemeName {
    final currentColor = accentColorNotifier.value;
    final r = currentColor.red;
    final g = currentColor.green;
    final b = currentColor.blue;

    final Map<String, Color> themeColors = {
      'purple': Colors.purple,
      'blue': Colors.blue,
      'standard': Colors.teal,
      'green': Colors.green,
      'yellow': Colors.yellow,
      'orange': Colors.orange,
      'red': Colors.red,
      'pink': Colors.pink,
    };

    var bestTheme = 'purple';
    var minDistance = double.infinity;

    for (final entry in themeColors.entries) {
      final tc = entry.value;
      final dist =
          (r - tc.red) * (r - tc.red) +
          (g - tc.green) * (g - tc.green) +
          (b - tc.blue) * (b - tc.blue);
      if (dist < minDistance) {
        minDistance = dist.toDouble();
        bestTheme = entry.key;
      }
    }

    final isDarkMode = themeModeNotifier.value == ThemeMode.dark;
    if (bestTheme == 'standard') {
      return isDarkMode ? 'Tela-dark' : 'Tela';
    }
    return isDarkMode ? 'Tela-$bestTheme-dark' : 'Tela-$bestTheme';
  }

  static Future<void> _updateGtkSettings(
    ThemeMode mode, {
    Color? color,
    String? homeOverride,
  }) async {
    try {
      final home = SwayConfD.homeDir(homeOverride: homeOverride);
      final themeName = mode == ThemeMode.light ? 'Fyr-Light' : 'Fyr-Dark';
      final preferDark = mode == ThemeMode.dark ? '1' : '0';
      final currentIconTheme = iconThemeName;

      final content = StringBuffer()
        ..writeln('[Settings]')
        ..writeln('gtk-theme-name=$themeName')
        ..writeln('gtk-icon-theme-name=$currentIconTheme')
        ..writeln('gtk-application-prefer-dark-theme=$preferDark')
        ..writeln('gtk-decoration-layout=close,minimize,maximize:');
      final settingsText = content.toString();

      final gtk3Dir = Directory('$home/.config/gtk-3.0');
      if (!gtk3Dir.existsSync()) gtk3Dir.createSync(recursive: true);
      await SwayConfD.writeFileAtomic(
        '${gtk3Dir.path}/settings.ini',
        settingsText,
      );

      final gtk4Dir = Directory('$home/.config/gtk-4.0');
      if (!gtk4Dir.existsSync()) gtk4Dir.createSync(recursive: true);
      await SwayConfD.writeFileAtomic(
        '${gtk4Dir.path}/settings.ini',
        settingsText,
      );

      final targetCssName = mode == ThemeMode.light
          ? 'gtk-light.css'
          : 'gtk-dark.css';
      final targetCssFile = File('${gtk4Dir.path}/$targetCssName');
      if (targetCssFile.existsSync()) {
        final tempCssFile = File('${gtk4Dir.path}/gtk.css.tmp');
        targetCssFile.copySync(tempCssFile.path);
        tempCssFile.renameSync('${gtk4Dir.path}/gtk.css');
      }

      await Process.run('gsettings', [
        'set',
        'org.gnome.desktop.interface',
        'gtk-theme',
        themeName,
      ]);
      await Process.run('gsettings', [
        'set',
        'org.gnome.desktop.interface',
        'icon-theme',
        currentIconTheme,
      ]);
      await Process.run('gsettings', [
        'set',
        'org.gnome.desktop.interface',
        'color-scheme',
        mode == ThemeMode.dark ? 'prefer-dark' : 'default',
      ]);
    } catch (_) {
      // Ignore outside GTK environment.
    }
  }

  static Future<void> setThemeMode(
    ThemeMode mode, {
    String? homeOverride,
    bool updateSystemSettings = true,
  }) async {
    final effectiveHome = homeOverride ?? _homeOverride;
    try {
      final dir = Directory(
        '${SwayConfD.homeDir(homeOverride: effectiveHome)}/.config/fyr',
      );
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      await SwayConfD.writeFileAtomic(
        '${dir.path}/theme_mode.txt',
        mode == ThemeMode.light ? 'light' : 'dark',
      );
      themeModeNotifier.value = mode;
      if (updateSystemSettings) {
        await _updateGtkSettings(mode, homeOverride: effectiveHome);
        await SwayConfD.reloadSway();
      }
    } catch (_) {
      // Ignore persistence errors.
    }
  }

  static const List<Color> customColors = [
    Colors.purpleAccent,
    Colors.purple,
    Colors.deepPurpleAccent,
    Colors.indigoAccent,
    Colors.blueAccent,
    Colors.lightBlueAccent,
    Colors.cyanAccent,
    Colors.tealAccent,
    Colors.greenAccent,
    Colors.lightGreenAccent,
    Colors.limeAccent,
    Colors.yellowAccent,
    Colors.amberAccent,
    Colors.orangeAccent,
    Colors.deepOrangeAccent,
    Colors.redAccent,
    Colors.pinkAccent,
  ];
}
