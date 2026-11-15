import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyr_core/fyr_core.dart';

void main() {
  group('SwayConfD', () {
    late Directory tempHome;

    setUp(() {
      tempHome = Directory.systemTemp.createTempSync('fyr_core_confd_');
      Directory('${tempHome.path}/.config/sway').createSync(recursive: true);
    });

    tearDown(() {
      if (tempHome.existsSync()) {
        tempHome.deleteSync(recursive: true);
      }
    });

    test('writes drop-in atomically and adds include directive once', () async {
      final configFile = File('${tempHome.path}/.config/sway/config');
      await configFile.writeAsString('set \$mod Mod4\n');

      await SwayConfD.writeDropIn(
        '30-touchpad.conf',
        'input "type:touchpad" {\n    tap enabled\n}\n',
        homeOverride: tempHome.path,
        reload: false,
      );

      final dropIn = File(
        '${tempHome.path}/.config/sway/conf.d/30-touchpad.conf',
      );
      expect(dropIn.existsSync(), isTrue);
      expect(dropIn.readAsStringSync(), contains('tap enabled'));

      // Writing a second time must not duplicate the include line.
      await SwayConfD.writeDropIn(
        '40-power.conf',
        'exec swayidle -w\n',
        homeOverride: tempHome.path,
        reload: false,
      );

      final mainText = await configFile.readAsString();
      expect(
        'include ~/.config/sway/conf.d/*.conf'.allMatches(mainText).length,
        1,
      );
    });

    test('reads legacy marker block and strips it cleanly', () async {
      final configFile = File('${tempHome.path}/.config/sway/config');
      await configFile.writeAsString(
        'set \$mod Mod4\n'
        '# TOUCHPAD SETTINGS\n'
        'input "type:touchpad" {\n'
        '    tap enabled\n'
        '}\n'
        '# END TOUCHPAD SETTINGS\n'
        'include ~/.config/sway/conf.d/*.conf\n',
      );

      final legacy = await SwayConfD.readDropInOrLegacyBlock(
        '30-touchpad.conf',
        startMarker: '# TOUCHPAD SETTINGS',
        endMarker: '# END TOUCHPAD SETTINGS',
        homeOverride: tempHome.path,
      );
      expect(legacy, contains('tap enabled'));

      await SwayConfD.removeLegacyMarkerBlock(
        '# TOUCHPAD SETTINGS',
        '# END TOUCHPAD SETTINGS',
        homeOverride: tempHome.path,
      );

      final cleaned = await configFile.readAsString();
      expect(cleaned, isNot(contains('# TOUCHPAD SETTINGS')));
      expect(cleaned, contains('set \$mod Mod4'));
    });
  });

  group('FyrTheme', () {
    late Directory tempHome;

    setUp(() {
      tempHome = Directory.systemTemp.createTempSync('fyr_core_theme_');
      Directory('${tempHome.path}/.config/sway').createSync(recursive: true);
    });

    tearDown(() async {
      await FyrTheme.dispose();
      FyrTheme.accentColorNotifier.value = FyrTheme.defaultAccent;
      FyrTheme.themeModeNotifier.value = ThemeMode.dark;
      if (tempHome.existsSync()) {
        tempHome.deleteSync(recursive: true);
      }
    });

    test('persists accent and theme mode and exposes consistent tokens', () async {
      FyrTheme.initialize(homeOverride: tempHome.path, watch: true);

      await FyrTheme.setThemeMode(
        ThemeMode.light,
        homeOverride: tempHome.path,
        updateSystemSettings: false,
      );
      expect(FyrTheme.isDark, isFalse);
      expect(FyrTheme.contentColor, const Color(0xFFFFFFFF));
      expect(FyrTheme.bgColor.alpha, 255);
      expect(FyrTheme.panelBgColor.alpha, lessThan(255));

      await FyrTheme.setAccentColor(
        Colors.blueAccent,
        homeOverride: tempHome.path,
        updateSystemSettings: false,
      );
      expect(FyrTheme.accentColor, Colors.blueAccent);
      expect(FyrTheme.getContrastingColor(Colors.white), Colors.black);
      expect(FyrTheme.iconThemeName, 'Tela-blue');

      await FyrTheme.setThemeMode(
        ThemeMode.dark,
        homeOverride: tempHome.path,
        updateSystemSettings: false,
      );
      expect(FyrTheme.isDark, isTrue);
      expect(FyrTheme.bgColor, const Color(0xFF000000));
      expect(FyrTheme.panelBgColor.alpha, lessThan(255));
      expect(FyrTheme.panelBgColor.red, 0x2A);
    });

    test('watches ~/.config/fyr without polling timer', () async {
      FyrTheme.initialize(homeOverride: tempHome.path, watch: true);
      final modeFile = File('${tempHome.path}/.config/fyr/theme_mode.txt');
      await SwayConfD.writeFileAtomic(modeFile.path, 'light');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(FyrTheme.themeMode, ThemeMode.light);
    });
  });

  group('OverlayWindowController', () {
    test('handles show, hide, and toggle commands over Unix socket', () async {
      final tmpDir = Directory.systemTemp.createTempSync('fyr_overlay_test_');
      addTearDown(() {
        if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
      });

      var shownCount = 0;
      var hiddenCount = 0;
      final ctrl = OverlayWindowController(
        appName: 'testoverlay',
        socketPathOverride: '${tmpDir.path}/overlay.sock',
        onShow: () => shownCount++,
        onHide: () => hiddenCount++,
      );
      await ctrl.start(initiallyVisible: false);
      addTearDown(ctrl.stop);

      Future<void> send(String cmd) async {
        final s = await Socket.connect(
          InternetAddress(ctrl.socketPath, type: InternetAddressType.unix),
          0,
        );
        s.writeln(cmd);
        await s.flush();
        await s.close();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      await send('toggle 0,0');
      expect(ctrl.isVisible, isTrue);
      expect(shownCount, 1);

      await send('toggle 0,0');
      expect(ctrl.isVisible, isFalse);
      expect(hiddenCount, 1);

      await send('show');
      expect(ctrl.isVisible, isTrue);
      expect(shownCount, 2);

      await send('hide');
      expect(ctrl.isVisible, isFalse);
      expect(hiddenCount, 2);
    });
  });
}
