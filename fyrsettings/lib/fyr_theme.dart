import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';

class FyrTheme {
  static const Color defaultAccent = Colors.purpleAccent;

  static final ValueNotifier<Color> accentColorNotifier = ValueNotifier<Color>(
    defaultAccent,
  );
  static final ValueNotifier<ThemeMode> themeModeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.dark);

  static Timer? _watchTimer;

  static void initialize() {
    _updateColor();
    _updateMode();
    _watchTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _updateColor();
      _updateMode();
    });
  }

  static void _updateColor() {
    try {
      final file = File(
        '${Platform.environment['HOME']}/.config/fyr/theme.txt',
      );
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
    } catch (e) {
      // Ignore
    }
  }

  static void _updateMode() {
    try {
      final file = File(
        '${Platform.environment['HOME']}/.config/fyr/theme_mode.txt',
      );
      if (file.existsSync()) {
        final modeStr = file.readAsStringSync().trim().toLowerCase();
        final newMode = modeStr == 'light' ? ThemeMode.light : ThemeMode.dark;
        if (themeModeNotifier.value != newMode) {
          themeModeNotifier.value = newMode;
        }
        return;
      }
    } catch (e) {
      // Ignore
    }
  }

  static Color get accentColor => accentColorNotifier.value;
  static ThemeMode get themeMode => themeModeNotifier.value;

  static bool get isDark => themeMode == ThemeMode.dark;
  static Color get textColor => isDark ? Colors.white : Colors.black87;
  static Color get textColorMuted => isDark ? Colors.white70 : Colors.black54;
  static Color get bgColor => isDark
      ? const Color(0xFF2A282C).withOpacity(0.8)
      : Colors.white.withOpacity(0.9);
  static Color get cardColor =>
      isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05);
  static Color get hoverColor =>
      isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1);
  static Color get dividerColor =>
      isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1);

  static Future<void> setAccentColor(Color color) async {
    try {
      final dir = Directory('${Platform.environment['HOME']}/.config/fyr');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final file = File('${dir.path}/theme.txt');
      await file.writeAsString(color.value.toRadixString(16).padLeft(8, '0'));
      accentColorNotifier.value = color;

      await _updateGtkSettings(themeModeNotifier.value, color: color);

      final swayConfigFile = File(
        '${Platform.environment['HOME']}/.config/sway/config',
      );
      if (swayConfigFile.existsSync()) {
        final hexColor =
            '#${color.value.toRadixString(16).substring(2).padLeft(6, '0')}';
        final lines = await swayConfigFile.readAsLines();
        final newLines = lines.map((line) {
          if (line.startsWith('client.focused ')) {
            return 'client.focused $hexColor $hexColor #ffffff $hexColor $hexColor';
          }
          return line;
        }).toList();
        final tempFile = File('${swayConfigFile.path}.tmp');
        await tempFile.writeAsString('${newLines.join('\n')}\n');
        await tempFile.rename(swayConfigFile.path);
        Process.run('swaymsg', ['reload']);
      }
    } catch (e) {
      // Ignore
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

    String bestTheme = 'purple';
    double minDistance = double.infinity;

    for (final entry in themeColors.entries) {
      final tc = entry.value;
      final dist = (r - tc.red) * (r - tc.red) +
                   (g - tc.green) * (g - tc.green) +
                   (b - tc.blue) * (b - tc.blue);
      if (dist < minDistance) {
        minDistance = dist.toDouble();
        bestTheme = entry.key;
      }
    }

    final isDark = themeModeNotifier.value == ThemeMode.dark;
    if (bestTheme == 'standard') {
      return isDark ? 'Tela-dark' : 'Tela';
    }
    return isDark ? 'Tela-$bestTheme-dark' : 'Tela-$bestTheme';
  }

  static Future<void> _updateGtkSettings(ThemeMode mode, {Color? color}) async {
    try {
      final themeName = mode == ThemeMode.light ? 'Fyr-Light' : 'Fyr-Dark';
      final preferDark = mode == ThemeMode.dark ? '1' : '0';

      final currentIconTheme = iconThemeName;

      final gtk3Dir = Directory(
        '${Platform.environment['HOME']}/.config/gtk-3.0',
      );
      if (!gtk3Dir.existsSync()) gtk3Dir.createSync(recursive: true);

      final gtk3File = File('${gtk3Dir.path}/settings.ini');
      String content = '[Settings]\n';
      content += 'gtk-theme-name=$themeName\n';
      content += 'gtk-icon-theme-name=$currentIconTheme\n';
      content += 'gtk-application-prefer-dark-theme=$preferDark\n';
      content += 'gtk-decoration-layout=close,minimize,maximize:\n';

      final tempGtk3File = File('${gtk3Dir.path}/settings.ini.tmp');
      await tempGtk3File.writeAsString(content);
      await tempGtk3File.rename(gtk3File.path);

      final gtk4Dir = Directory(
        '${Platform.environment['HOME']}/.config/gtk-4.0',
      );
      if (!gtk4Dir.existsSync()) gtk4Dir.createSync(recursive: true);

      final gtk4File = File('${gtk4Dir.path}/settings.ini');
      final tempGtk4File = File('${gtk4Dir.path}/settings.ini.tmp');
      await tempGtk4File.writeAsString(content);
      await tempGtk4File.rename(gtk4File.path);

      final gtk4CssFile = File('${gtk4Dir.path}/gtk.css');
      final targetCssName = mode == ThemeMode.light
          ? 'gtk-light.css'
          : 'gtk-dark.css';
      final targetCssFile = File('${gtk4Dir.path}/$targetCssName');
      if (targetCssFile.existsSync()) {
        final tempCssFile = File('${gtk4Dir.path}/gtk.css.tmp');
        targetCssFile.copySync(tempCssFile.path);
        tempCssFile.renameSync(gtk4CssFile.path);
      }

      Process.run('gsettings', [
        'set',
        'org.gnome.desktop.interface',
        'gtk-theme',
        themeName,
      ]);
      Process.run('gsettings', [
        'set',
        'org.gnome.desktop.interface',
        'icon-theme',
        currentIconTheme,
      ]);
      Process.run('gsettings', [
        'set',
        'org.gnome.desktop.interface',
        'color-scheme',
        mode == ThemeMode.dark ? 'prefer-dark' : 'default',
      ]);
    } catch (e) {
      // Ignore
    }
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    try {
      final dir = Directory('${Platform.environment['HOME']}/.config/fyr');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final file = File('${dir.path}/theme_mode.txt');
      final tempFile = File('${dir.path}/theme_mode.txt.tmp');
      await tempFile.writeAsString(mode == ThemeMode.light ? 'light' : 'dark');
      await tempFile.rename(file.path);
      themeModeNotifier.value = mode;
      await _updateGtkSettings(mode);
    } catch (e) {
      // Ignore
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
