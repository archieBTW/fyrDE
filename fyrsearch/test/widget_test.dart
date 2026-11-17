import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrsearch/main.dart';

void main() {
  group('LauncherScreen pin to dock and app refresh tests', () {
    late Directory appsDir;
    late Directory dockDir;
    late File pinnedFile;

    setUp(() {
      appsDir = Directory.systemTemp.createTempSync('fyrsearch_apps_');
      dockDir = Directory.systemTemp.createTempSync('fyrsearch_dock_');
      pinnedFile = File('${dockDir.path}/pinned_apps.json');

      File('${appsDir.path}/sample.desktop').writeAsStringSync(
        '[Desktop Entry]\n'
        'Type=Application\n'
        'Name=Sample Editor\n'
        'Exec=sample-editor\n',
      );
    });

    tearDown(() {
      if (appsDir.existsSync()) appsDir.deleteSync(recursive: true);
      if (dockDir.existsSync()) dockDir.deleteSync(recursive: true);
    });

    testWidgets('pins and unpins apps from search overlay via button, context menu, and Ctrl+P', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: LauncherScreen(
            initiallyVisible: true,
            desktopDirs: [appsDir.path],
            pinnedAppsPath: pinnedFile.path,
          ),
        ),
      );

      for (int i = 0; i < 20 && find.text('Sample Editor').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Sample Editor'), findsOneWidget);

      Future<List<dynamic>> waitPinnedCount(
        int expectedCount, {
        required bool expectPinBadge,
      }) async {
        for (int i = 0; i < 30; i++) {
          if (pinnedFile.existsSync()) {
            try {
              final content = pinnedFile.readAsStringSync();
              if (content.isNotEmpty) {
                final list = jsonDecode(content) as List<dynamic>;
                final badgeVisible =
                    find.byIcon(Icons.push_pin_outlined).evaluate().isNotEmpty;
                if (list.length == expectedCount && badgeVisible == expectPinBadge) {
                  return list;
                }
              }
            } catch (_) {}
          }
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump(const Duration(milliseconds: 50));
        }
        return jsonDecode(pinnedFile.readAsStringSync()) as List<dynamic>;
      }

      // Select first item with ArrowDown; pin icon appears for unpinned item.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);

      // Pin via Ctrl+P; pin icon badge should disappear once pinned.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      var decoded = await waitPinnedCount(1, expectPinBadge: false);

      expect(pinnedFile.existsSync(), isTrue);
      expect(decoded.length, 1);
      expect(decoded.first['name'], 'Sample Editor');
      expect(decoded.first['exec'], 'sample-editor');
      expect(find.byIcon(Icons.push_pin), findsNothing);
      expect(find.byIcon(Icons.push_pin_outlined), findsNothing);

      // Right-click opens context menu with "Unpin from Dock"; unpinning restores pin badge.
      await tester.tap(
        find.text('Sample Editor'),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Unpin from Dock'), findsOneWidget);
      await tester.tap(find.text('Unpin from Dock'));
      await tester.pumpAndSettle();
      decoded = await waitPinnedCount(0, expectPinBadge: true);
      expect(decoded, isEmpty);
      expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);

      // Tapping the pin badge pins the item and hides the badge again.
      await tester.tap(find.byIcon(Icons.push_pin_outlined));
      await tester.pumpAndSettle();
      decoded = await waitPinnedCount(1, expectPinBadge: false);
      expect(decoded.length, 1);
      expect(find.byIcon(Icons.push_pin), findsNothing);
      expect(find.byIcon(Icons.push_pin_outlined), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('updates displayed apps when a new .desktop file is installed', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: LauncherScreen(
            initiallyVisible: true,
            desktopDirs: [appsDir.path],
            pinnedAppsPath: pinnedFile.path,
          ),
        ),
      );

      for (int i = 0; i < 20 && find.text('Sample Editor').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Freshly Installed'), findsNothing);

      File('${appsDir.path}/fresh.desktop').writeAsStringSync(
        '[Desktop Entry]\n'
        'Type=Application\n'
        'Name=Freshly Installed\n'
        'Exec=fresh-app\n',
      );

      // Wait for watcher + 300ms debounce to reload apps.
      for (int i = 0; i < 30 && find.text('Freshly Installed').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Freshly Installed'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 400));
    });
  });
}
