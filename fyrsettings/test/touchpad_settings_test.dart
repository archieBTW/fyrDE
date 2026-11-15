import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrsettings/panes/touchpad_pane.dart';

void main() {
  test('TouchpadSettingsConfig parses and updates Sway config cleanly', () {
    const initialConfig = '''
set \$mod Mod4
# TOUCHPAD SETTINGS
input "type:touchpad" {
    tap enabled
    tap_button_map lrm
    drag enabled
    dwt enabled
    natural_scroll disabled
    pointer_accel 0.25
}
# END TOUCHPAD SETTINGS
output eDP-1 resolution 1920x1080 position 0 0
''';

    final parsed = TouchpadSettingsConfig.fromSwayConfigContent(initialConfig);
    expect(parsed.tapToClick, isTrue);
    expect(parsed.tapAndDrag, isTrue);
    expect(parsed.disableWhileTyping, isTrue);
    expect(parsed.naturalScroll, isFalse);
    expect(parsed.pointerSpeed, closeTo(0.25, 1e-6));

    final updatedContent = TouchpadSettingsConfig.upsertSwayConfigContent(
      initialConfig,
      parsed.copyWith(naturalScroll: true, pointerSpeed: -0.4),
    );
    expect(updatedContent, contains('set \$mod Mod4'));
    expect(updatedContent, contains('output eDP-1 resolution 1920x1080 position 0 0'));
    expect(
      TouchpadSettingsConfig.startMarker.allMatches(updatedContent).length,
      1,
    );

    final reparsed = TouchpadSettingsConfig.fromSwayConfigContent(updatedContent);
    expect(reparsed.tapToClick, isTrue);
    expect(reparsed.naturalScroll, isTrue);
    expect(reparsed.pointerSpeed, closeTo(-0.4, 1e-6));
  });

  testWidgets('TouchpadPane renders and toggles tap-to-click controls', (tester) async {
    TouchpadSettingsConfig? applied;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 700,
            child: TouchpadPane(
              loadState: () async => (
                config: const TouchpadSettingsConfig(tapToClick: true),
                deviceName: 'Test Touchpad',
              ),
              onApplyConfig: (config) async {
                applied = config;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mouse & Touchpad'), findsOneWidget);
    expect(find.text('Active touchpad: Test Touchpad'), findsOneWidget);
    expect(find.text('Tap to Click'), findsOneWidget);
    expect(find.text('Tap and Drag'), findsOneWidget);
    expect(find.text('Natural Scrolling'), findsOneWidget);
    expect(find.text('Disable Touchpad While Typing'), findsOneWidget);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(applied, isNotNull);
    expect(applied!.tapToClick, isFalse);
  });
}

