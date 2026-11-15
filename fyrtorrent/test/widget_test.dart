import 'dart:io';
import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart' as bencoding;
import 'package:crypto/crypto.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:dtorrent_task/dtorrent_task.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrtorrent/main.dart';
import 'package:fyrtorrent/services/torrent_service.dart';

Future<Torrent> _makeDummyTorrent() async {
  final pieces = Uint8List.fromList(sha1.convert(Uint8List(16384)).bytes);
  final bytes = Uint8List.fromList(
    bencoding.encode({
      'info': {
        'name': 'completed_sample.iso',
        'piece length': 16384,
        'pieces': pieces,
        'length': 16384,
      },
    }),
  );
  return Torrent.parse(bytes);
}

void main() {
  testWidgets('Completed torrent displays Seeding badge and working remove button',
      (WidgetTester tester) async {
    late Directory tmpDir;
    late Torrent model;
    await tester.runAsync(() async {
      tmpDir = await Directory.systemTemp.createTemp('fyrtorrent_widget_');
      model = await _makeDummyTorrent();
    });
    final task = TorrentTask.newTask(model, tmpDir.path);
    final item = TorrentItem(
      infoHash: model.infoHash,
      name: model.name,
      savePath: tmpDir.path,
      task: task,
      model: model,
    )
      ..isCompleted = true
      ..progress = 1.0;

    addTearDown(() async {
      item.stop();
      await tester.runAsync(() async {
        if (tmpDir.existsSync()) {
          await tmpDir.delete(recursive: true);
        }
      });
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TorrentListItem(item: item),
        ),
      ),
    );

    expect(find.text('Seeding'), findsOneWidget);
    expect(find.byTooltip('Pause seeding'), findsOneWidget);
    expect(find.byTooltip('Remove torrent'), findsOneWidget);

    final pauseButtonFinder = find.widgetWithIcon(IconButton, Icons.pause);
    expect(pauseButtonFinder, findsOneWidget);
    await tester.tap(pauseButtonFinder);
    await tester.pump();

    expect(item.isPaused, isTrue);
    expect(find.text('Paused'), findsOneWidget);
    expect(find.byTooltip('Resume seeding'), findsOneWidget);

    final resumeButtonFinder = find.widgetWithIcon(IconButton, Icons.play_arrow);
    expect(resumeButtonFinder, findsOneWidget);
    await tester.tap(resumeButtonFinder);
    await tester.pump();

    expect(item.isPaused, isFalse);
    expect(find.text('Seeding'), findsOneWidget);

    final removeButtonFinder = find.widgetWithIcon(IconButton, Icons.close);
    expect(removeButtonFinder, findsOneWidget);
    final IconButton button = tester.widget(removeButtonFinder);
    expect(button.onPressed, isNotNull);

    // Stop item before test body ends so Flutter's invariant check sees zero pending timers.
    item.stop();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
