import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrsettings/panes/shortcuts_pane.dart';

void main() {
  group('SwayShortcutStore', () {
    test('parses bindsym and bindgesture and saves conf.d drop-in', () async {
      final tmpHome = Directory.systemTemp.createTempSync('fyr_shortcuts_');
      addTearDown(() {
        if (tmpHome.existsSync()) tmpHome.deleteSync(recursive: true);
      });

      final swayDir = Directory('${tmpHome.path}/.config/sway')
        ..createSync(recursive: true);
      File('${swayDir.path}/config').writeAsStringSync(
        'bindsym \$mod+Return exec /opt/fyrterm/fyrterm\n'
        'bindsym --locked XF86AudioMute exec ~/.config/fyr/osd.sh vol-mute\n'
        'bindgesture swipe:3:down exec ~/.config/fyr/overview_toggle.sh back\n',
      );

      await SwayShortcutStore.saveCustomShortcuts(
        const [
          SwayShortcutEntry(
            kind: 'bindsym',
            trigger: '\$mod+Shift+t',
            action: 'exec /opt/fyrterm/fyrterm',
            sourceFile: '50-shortcuts.conf',
            isCustom: true,
          ),
        ],
        unbinds: const ['\$mod+Return'],
        homeOverride: tmpHome.path,
        reload: false,
      );

      final loaded = await SwayShortcutStore.loadAll(
        homeOverride: tmpHome.path,
      );
      expect(loaded.unbinds, contains('\$mod+Return'));
      expect(
        loaded.entries.any((e) => e.trigger == '\$mod+Return' && !e.isCustom),
        isFalse,
      );
      expect(
        loaded.entries.any((e) => e.trigger == '\$mod+Shift+t' && e.isCustom),
        isTrue,
      );
      expect(
        loaded.entries.any(
          (e) => e.kind == 'bindgesture' && e.trigger == 'swipe:3:down',
        ),
        isTrue,
      );
    });
  });

  testWidgets('ShortcutsPane renders and filters entries', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShortcutsPane(
            loadOverride: () async => (
              entries: const [
                SwayShortcutEntry(
                  kind: 'bindsym',
                  trigger: '\$mod+space',
                  action: 'exec ~/.config/fyr/launcher_toggle.sh',
                  sourceFile: 'config',
                ),
                SwayShortcutEntry(
                  kind: 'bindgesture',
                  trigger: 'swipe:3:up',
                  action: 'exec ~/.config/fyr/overview_toggle.sh hide',
                  sourceFile: '50-shortcuts.conf',
                  isCustom: true,
                ),
              ],
              unbinds: const <String>[],
            ),
            saveOverride: (_, __) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Super + space'), findsOneWidget);
    expect(find.text('swipe:3:up'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'launcher');
    await tester.pumpAndSettle();

    expect(find.text('Super + space'), findsOneWidget);
    expect(find.text('swipe:3:up'), findsNothing);
  });
}
