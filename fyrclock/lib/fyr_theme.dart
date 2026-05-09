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
      isDark ? const Color(0xFF000000) : Colors.white;
  static Color get sidebarColor =>
      isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF5F5F5);
  static Color get surfaceColor =>
      isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFFFFFF);
  static Color get cardColor =>
      isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03);
  static Color get hoverColor =>
      isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05);
  static Color get dividerColor =>
      isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.08);

  static Color getContrastingColor(Color color) {
    return color.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  }
}
