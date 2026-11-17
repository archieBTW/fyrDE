import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrtaskbar/main.dart';
import 'package:fyrtaskbar/services/app_service.dart';
import 'package:fyrtaskbar/ui/start_menu.dart';

void main() {
  group('AppService and StartMenuPopup refresh tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('fyrtaskbar_apps_test_');
      AppService.searchPathsOverride = {tempDir.path};
      await AppService.resetForTest();
    });

    tearDown(() async {
      await AppService.resetForTest();
      AppService.searchPathsOverride = null;
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    void writeDesktopFile(String id, String name, String exec) {
      File('${tempDir.path}/$id.desktop').writeAsStringSync(
        '[Desktop Entry]\n'
        'Type=Application\n'
        'Name=$name\n'
        'Exec=$exec\n',
      );
    }

    test('getInstalledApps picks up newly installed apps with forceRefresh and notifies onAppsChanged', () async {
      writeDesktopFile('alpha', 'Alpha App', 'alpha-bin');

      final initial = await AppService.getInstalledApps();
      expect(initial.map((a) => a.name), ['Alpha App']);

      final changeFuture = AppService.onAppsChanged.first;
      writeDesktopFile('beta', 'Beta Newly Installed', 'beta-bin');

      await changeFuture.timeout(const Duration(seconds: 3));

      final refreshed = await AppService.getInstalledApps(forceRefresh: true);
      expect(
        refreshed.map((a) => a.name),
        containsAll(['Alpha App', 'Beta Newly Installed']),
      );
    });

    testWidgets('StartMenuPopup displays newly installed app when reopened', (
      WidgetTester tester,
    ) async {
      writeDesktopFile('alpha', 'Alpha App', 'alpha-bin');
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StartMenuPopup(onClose: () {})),
        ),
      );
      for (int i = 0; i < 20 && find.text('Alpha App').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Alpha App'), findsOneWidget);
      expect(find.text('Gamma App'), findsNothing);

      // Unmount popup (closing start menu), install a new .desktop entry, then reopen.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      writeDesktopFile('gamma', 'Gamma App', 'gamma-bin');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StartMenuPopup(onClose: () {})),
        ),
      );
      for (int i = 0; i < 20 && find.text('Gamma App').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Alpha App'), findsOneWidget);
      expect(find.text('Gamma App'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  testWidgets('DesktopBackgroundScreen opens context menu on right-click and closes on tap', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: DesktopBackgroundScreen()),
    );
    await tester.pump();

    expect(find.text('Change Wallpaper...'), findsNothing);

    await tester.tapAt(
      const Offset(400, 400),
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();

    expect(find.text('Change Wallpaper...'), findsOneWidget);
    expect(find.text('Display Settings'), findsOneWidget);
    expect(find.text('Open Terminal'), findsOneWidget);

    await tester.tapAt(const Offset(50, 50));
    await tester.pump();
    expect(find.text('Change Wallpaper...'), findsNothing);
  });
}
