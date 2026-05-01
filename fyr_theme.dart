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
  static Color get bgColor =>
      isDark ? const Color(0xFF2A282C) : Colors.white.withOpacity(0.9);
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

      final swayConfigFile = File('${Platform.environment['HOME']}/.config/sway/config');
      if (swayConfigFile.existsSync()) {
        final hexColor = '#${color.value.toRadixString(16).substring(2).padLeft(6, '0')}';
        final lines = await swayConfigFile.readAsLines();
        final newLines = lines.map((line) {
          if (line.startsWith('client.focused ')) {
            return 'client.focused $hexColor $hexColor #ffffff $hexColor $hexColor';
          }
          return line;
        }).toList();
        await swayConfigFile.writeAsString('${newLines.join('\\n')}\\n');
        Process.run('swaymsg', ['reload']);
      }
    } catch (e) {
      // Ignore
    }
  }

  static Future<void> _updateGtkSettings(ThemeMode mode) async {
    try {
      final themeName = mode == ThemeMode.light ? 'Fyr-Purple-Light' : 'Fyr-Purple-Dark';
      final preferDark = mode == ThemeMode.dark ? '1' : '0';
      
      final gtk3Dir = Directory('${Platform.environment['HOME']}/.config/gtk-3.0');
      if (!gtk3Dir.existsSync()) gtk3Dir.createSync(recursive: true);
      
      final gtk3File = File('${gtk3Dir.path}/settings.ini');
      String content = '[Settings]\n';
      content += 'gtk-theme-name=$themeName\n';
      content += 'gtk-application-prefer-dark-theme=$preferDark\n';
      content += 'gtk-decoration-layout=close,minimize,maximize:\n';
      
      await gtk3File.writeAsString(content);
      
      final gtk4Dir = Directory('${Platform.environment['HOME']}/.config/gtk-4.0');
      if (!gtk4Dir.existsSync()) gtk4Dir.createSync(recursive: true);
      
      final gtk4File = File('${gtk4Dir.path}/settings.ini');
      await gtk4File.writeAsString(content);
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
      await file.writeAsString(mode == ThemeMode.light ? 'light' : 'dark');
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
