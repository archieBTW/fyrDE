import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:fyrjournal/main.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('WSL environment detection', () {
    test('detects WSL via WSL_DISTRO_NAME and WSL_INTEROP', () {
      expect(
        isWslEnvironment(
          environment: const {'WSL_DISTRO_NAME': 'Arch'},
          procVersionContent: 'Linux version 6.8.0-arch1-1',
        ),
        isTrue,
      );
      expect(
        isWslEnvironment(
          environment: const {'WSL_INTEROP': '/run/WSL/123_interop'},
          procVersionContent: 'Linux version 6.8.0-arch1-1',
        ),
        isTrue,
      );
    });

    test('detects WSL via /proc/version case-insensitively', () {
      expect(
        isWslEnvironment(
          environment: const {},
          procVersionContent:
              'Linux version 5.15.153.1-microsoft-standard-WSL2',
        ),
        isTrue,
      );
      expect(
        isWslEnvironment(
          environment: const {},
          procVersionContent: 'Linux version 6.6.0-custom-wsl',
        ),
        isTrue,
      );
    });

    test('returns false on standard native Linux', () {
      expect(
        isWslEnvironment(
          environment: const {'HOME': '/home/archer'},
          procVersionContent: 'Linux version 6.10.2-arch1-1',
        ),
        isFalse,
      );
    });
  });

  testWidgets('journal loads existing entries from the storage directory',
      (WidgetTester tester) async {
    final tempDir = Directory.systemTemp.createTempSync('fyrjournal_test');
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    final today = DateTime.now();
    final todayKey = DateFormat('yyyy-MM-dd').format(today);
    File('${tempDir.path}/$todayKey.txt')
        .writeAsStringSync('hello from the test');

    await tester.pumpWidget(MaterialApp(
      home: JournalHomePage(
        storageDirOverride: tempDir,
        showCustomTitleBar: true,
      ),
    ));

    // Storage init + day loading use real dart:io reads; flush inside runAsync.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    // Today's row is always rendered, pre-filled with the stored entry.
    expect(find.text('hello from the test'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const Key('custom_title_bar')), findsOneWidget);
  });

  testWidgets('hides custom traffic-light bar in WSL mode',
      (WidgetTester tester) async {
    final tempDir = Directory.systemTemp.createTempSync('fyrjournal_wsl_');
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    await tester.pumpWidget(MaterialApp(
      home: JournalHomePage(
        storageDirOverride: tempDir,
        showCustomTitleBar: false,
      ),
    ));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    expect(find.byKey(const Key('custom_title_bar')), findsNothing);
    expect(find.byType(JournalDayItem), findsOneWidget);
  });
}
