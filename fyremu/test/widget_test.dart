import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:fyremu/main.dart';
import 'package:fyremu/models/emu_types.dart';
import 'package:fyremu/state/emu_controller.dart';

void main() {
  group('fyrEmu Models & Input Mapping', () {
    test('detects console platforms from ROM extensions', () {
      expect(ConsolePlatform.fromExtension('.gb'), ConsolePlatform.gb);
      expect(ConsolePlatform.fromExtension('.gbc'), ConsolePlatform.gbc);
      expect(ConsolePlatform.fromExtension('.gba'), ConsolePlatform.gba);
      expect(ConsolePlatform.fromExtension('.nes'), ConsolePlatform.nes);
      expect(ConsolePlatform.fromExtension('.sfc'), ConsolePlatform.snes);
      expect(ConsolePlatform.fromExtension('.SMC'), ConsolePlatform.snes);
      expect(ConsolePlatform.fromExtension('.md'), ConsolePlatform.genesis);
      expect(ConsolePlatform.fromExtension('.txt'), isNull);
    });

    test('InputProfile serializes and restores keyboard & gamepad bindings',
        () {
      final profile = InputProfile.defaults();
      profile.keyboardMap[RetroButton.a] = LogicalKeyboardKey.space.keyId;
      profile.gamepadMap[RetroButton.start] =
          const GamepadSource(kind: GamepadInputKind.button, index: 9);

      final restored = InputProfile.fromJson(profile.toJson());
      expect(
          restored.keyboardMap[RetroButton.a], LogicalKeyboardKey.space.keyId);
      expect(restored.gamepadMap[RetroButton.start]?.index, 9);
      expect(restored.gamepadMap[RetroButton.start]?.kind,
          GamepadInputKind.button);
    });

    test('EmuController computes joypad bitmask from pressed keyboard keys',
        () {
      final ctrl = EmuController();
      ctrl.handleKeyboardEvent(KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.arrowUp,
        logicalKey: LogicalKeyboardKey.arrowUp,
        timeStamp: Duration.zero,
      ));
      ctrl.handleKeyboardEvent(KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyX,
        logicalKey: LogicalKeyboardKey.keyX,
        timeStamp: Duration.zero,
      ));

      final mask = ctrl.computeJoypadMask();
      expect(mask & (1 << RetroButton.up.retroId), isNonZero);
      expect(mask & (1 << RetroButton.a.retroId), isNonZero);
      expect(mask & (1 << RetroButton.b.retroId), 0);

      ctrl.dispose();
    });
  });

  group('fyrEmu UI Smoke Test', () {
    testWidgets('renders LibraryView with platforms and controls',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 820);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final ctrl = EmuController();

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: ctrl,
          child: const FyrEmuApp(),
        ),
      );
      await tester.pump();

      expect(find.text('fyrEmu'), findsOneWidget);
      expect(find.text('All Games'), findsWidgets);
      expect(find.text('Game Boy Color'), findsOneWidget);
      expect(find.text('Game Boy Advance'), findsOneWidget);
      expect(find.text('NES / Famicom'), findsOneWidget);
      expect(find.text('SNES / Super Famicom'), findsOneWidget);
      expect(find.text('Controls'), findsOneWidget);
      expect(find.text('Cores'), findsOneWidget);
    });
  });
}
