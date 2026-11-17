import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrsettings/fyr_theme.dart';
import 'package:fyrsettings/panes/updates_pane.dart';

void main() {
  testWidgets('UpdatesPane renders Pacman, AUR, Flatpak, and Snap updates and toggles', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final initial = UpdateCheckResult(
      checkedAt: DateTime(2026, 11, 17, 14, 0),
      errors: const [],
      backends: const BackendAvailability(
        hasPacman: true,
        hasYay: true,
        hasFlatpak: true,
        hasSnap: true,
        hasCheckupdates: false,
        hasFakeroot: true,
      ),
      updates: const [
        PendingUpdate(
          name: 'linux',
          currentVersion: '6.12.1-1',
          newVersion: '6.12.2-1',
          source: UpdateSource.pacman,
        ),
        PendingUpdate(
          name: 'yay-bin',
          currentVersion: '12.4.0-1',
          newVersion: '13.1.0-1',
          source: UpdateSource.aur,
        ),
        PendingUpdate(
          name: 'Mesa',
          currentVersion: '25.08',
          newVersion: '26.2.5',
          source: UpdateSource.flatpak,
        ),
        PendingUpdate(
          name: 'spotify',
          currentVersion: 'rev 78',
          newVersion: '1.2.40',
          source: UpdateSource.snap,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: UpdatesPane(
              autoCheckOnInit: false,
              initialResult: initial,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('System Updates'), findsOneWidget);
    expect(find.text('Update Notifications'), findsOneWidget);
    expect(find.text('Automatic Background Updates'), findsOneWidget);
    expect(find.text('Available Updates (4)'), findsOneWidget);
    expect(find.text('linux'), findsOneWidget);
    expect(find.text('yay-bin'), findsOneWidget);
    expect(find.text('Mesa'), findsOneWidget);
    expect(find.text('spotify'), findsOneWidget);
    expect(find.text('Pacman'), findsOneWidget);
    expect(find.text('AUR (yay)'), findsOneWidget);
  });
}
