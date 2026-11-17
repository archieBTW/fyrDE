import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:fyrjournal/main.dart';

void main() {
  testWidgets('journal loads existing entries from the storage directory',
      (WidgetTester tester) async {
    final tempDir = await Directory.systemTemp.createTemp('fyrjournal_test');
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    final today = DateTime.now();
    final todayKey = DateFormat('yyyy-MM-dd').format(today);
    await File('${tempDir.path}/$todayKey.txt')
        .writeAsString('hello from the test');

    await tester.pumpWidget(MaterialApp(
      home: JournalHomePage(storageDirOverride: tempDir),
    ));

    // Storage init + day loading happen asynchronously.
    await tester.pumpAndSettle();

    // Today's row is always rendered, pre-filled with the stored entry.
    expect(find.text('hello from the test'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
