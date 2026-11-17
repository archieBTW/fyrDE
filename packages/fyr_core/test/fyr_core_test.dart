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

  group('DisplayTarget resolution', () {
    test('parseSwayOutputs sorts deterministically by x, y, name and filters inactive', () {
      final outputs = parseSwayOutputs([
        {
          'name': 'DP-5',
          'model': 'External',
          'active': true,
          'focused': true,
          'rect': {'x': 1920, 'y': 0, 'width': 1920, 'height': 1080},
        },
        {
          'name': 'HDMI-1',
          'active': false,
          'rect': {'x': 0, 'y': 0, 'width': 1920, 'height': 1080},
        },
        {
          'name': 'eDP-1',
          'model': 'Built-in',
          'active': true,
          'focused': false,
          'rect': {'x': 0, 'y': 0, 'width': 1920, 'height': 1080},
        },
      ]);

      expect(outputs.map((o) => o.name).toList(), ['eDP-1', 'DP-5']);
      // Primary resolution picks preferredName regardless of transient focus.
      expect(
        resolvePrimaryOutput(outputs, preferredName: 'DP-5')?.name,
        'DP-5',
      );
      // Falls back deterministically to (0, 0) output even though DP-5 was focused.
      expect(
        resolvePrimaryOutput(outputs)?.name,
        'eDP-1',
      );
    });

    test('readConfiguredPrimaryDisplay prefers ~/.config/fyr/primary_display over sway conf', () async {
      final tmpHome = Directory.systemTemp.createTempSync('fyr_disp_test_');
      addTearDown(() {
        if (tmpHome.existsSync()) tmpHome.deleteSync(recursive: true);
      });

      final swayDropIn = File(
        '${tmpHome.path}/.config/sway/conf.d/20-primary-output.conf',
      );
      swayDropIn.parent.createSync(recursive: true);
      swayDropIn.writeAsStringSync('assign [app_id="fyrdock"] output DP-5\n');

      expect(
        await readConfiguredPrimaryDisplay(homeOverride: tmpHome.path),
        'DP-5',
      );

      final primaryFile = File('${tmpHome.path}/.config/fyr/primary_display');
      primaryFile.parent.createSync(recursive: true);
      primaryFile.writeAsStringSync('eDP-1\n');

      expect(
        await readConfiguredPrimaryDisplay(homeOverride: tmpHome.path),
        'eDP-1',
      );
    });
  });

  group('UpdateService parsers and config', () {
    test('parses pacman/yay, flatpak, and snap update outputs accurately', () {
      final pacmanUpdates = UpdateService.parsePacmanQuOutput(
        ':: Synchronizing...\n'
        'linux 6.12.1-1 -> 6.12.2-1\n'
        'mesa 24.3.0-1 -> 24.3.1-1\n'
        'ignored-pkg 1.0 -> 2.0 [ignored]\n',
      );
      expect(pacmanUpdates.length, 2);
      expect(pacmanUpdates[0].name, 'linux');
      expect(pacmanUpdates[0].currentVersion, '6.12.1-1');
      expect(pacmanUpdates[0].newVersion, '6.12.2-1');
      expect(pacmanUpdates[0].source, UpdateSource.pacman);

      final aurUpdates = UpdateService.parsePacmanQuOutput(
        'yay-bin 12.4.0-1 -> 13.1.0-1\n',
        source: UpdateSource.aur,
      );
      expect(aurUpdates.single.source, UpdateSource.aur);
      expect(aurUpdates.single.name, 'yay-bin');

      final flatpaks = UpdateService.parseFlatpakUpdatesOutput(
        'org.freedesktop.Platform.GL.default\tMesa\t26.2.5\t25.08\n'
        'org.mozilla.firefox\tFirefox\t\tstable\n',
      );
      expect(flatpaks.length, 2);
      expect(flatpaks[0].name, 'Mesa');
      expect(flatpaks[0].newVersion, '26.2.5');
      expect(flatpaks[0].source, UpdateSource.flatpak);
      expect(flatpaks[1].name, 'Firefox');
      expect(flatpaks[1].newVersion, 'latest');

      final snaps = UpdateService.parseSnapRefreshListOutput(
        'Name     Version   Rev   Publisher   Notes\n'
        'spotify  1.2.40    78    spotify     -\n',
      );
      expect(snaps.length, 1);
      expect(snaps[0].name, 'spotify');
      expect(snaps[0].newVersion, '1.2.40');
      expect(snaps[0].currentVersion, 'rev 78');
      expect(snaps[0].source, UpdateSource.snap);

      final summary = UpdateService.formatNotificationBody([
        ...pacmanUpdates,
        ...aurUpdates,
        ...flatpaks,
        ...snaps,
      ]);
      expect(summary, contains('2 Pacman'));
      expect(summary, contains('1 AUR (yay)'));
      expect(summary, contains('2 Flatpak'));
      expect(summary, contains('1 Snap'));
    });

    test('persists UpdatesConfig atomically', () async {
      final tmpHome = Directory.systemTemp.createTempSync('fyr_updates_cfg_');
      addTearDown(() {
        if (tmpHome.existsSync()) tmpHome.deleteSync(recursive: true);
      });

      const cfg = UpdatesConfig(
        notificationsEnabled: true,
        autoUpdateEnabled: true,
        checkIntervalHours: 12,
        includeSnap: false,
      );
      await UpdateService.saveConfig(cfg, homeOverride: tmpHome.path);
      final loaded = await UpdateService.loadConfig(homeOverride: tmpHome.path);
      expect(loaded.notificationsEnabled, isTrue);
      expect(loaded.autoUpdateEnabled, isTrue);
      expect(loaded.checkIntervalHours, 12);
      expect(loaded.includeSnap, isFalse);
    });
  });
}
