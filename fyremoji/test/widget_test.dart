import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fyremoji/main.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          (call) async {
            if (call.method == 'getAll') {
              return <String, Object>{};
            }
            return true;
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          null,
        );
  });

  testWidgets('FyrEmoji search filters emojis by keyword', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const FyrEmojiApp());
    for (int i = 0; i < 30 && find.byIcon(Icons.search).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Open search view via the search icon in the bottom action bar.
    final searchBtn = find.byIcon(Icons.search);
    expect(searchBtn, findsOneWidget);
    await tester.tap(searchBtn);
    await tester.pumpAndSettle();

    // Search field is visible and focused.
    final fieldFinder = find.byType(TextField);
    expect(fieldFinder, findsOneWidget);

    await tester.enterText(fieldFinder, 'fire');
    await tester.pump();

    expect(find.text('🔥'), findsOneWidget);
    expect(find.text('😀'), findsNothing);

    // Multi-word query matches emoji name tokens across categories.
    await tester.enterText(fieldFinder, 'grinning face');
    await tester.pump();
    expect(find.text('😀'), findsOneWidget);
    expect(find.text('🔥'), findsNothing);

    // Clearing the query returns to empty prompt (when no recents exist).
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.text('Type to search emojis...'), findsOneWidget);

    // Back button closes search view cleanly.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.search), findsOneWidget);

    // Dispose widget tree cleanly (avoids window_manager or focus timers).
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
