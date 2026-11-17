import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:fyrdirector/main.dart';
import 'package:fyrdirector/models/director_types.dart';
import 'package:fyrdirector/state/director_controller.dart';

void main() {
  group('fyrDirector Timeline & Project Engine', () {
    test('places, splits, trims, duplicates, and undoes timeline clips', () {
      final ctrl = DirectorController(enableMediaKit: false);
      final asset = MediaAsset(
        id: 'a1',
        name: 'clip.mp4',
        path: '/tmp/clip.mp4',
        type: MediaType.video,
        durationSec: 10.0,
        hasAudio: true,
      );
      ctrl.mediaBin.add(asset);
      ctrl.addAssetToTimeline(asset, trackIndex: 1, atSec: 0.0);

      expect(ctrl.clips.length, 1);
      expect(ctrl.clips.first.durationSec, 10.0);

      // Split at 4.0s
      ctrl.splitClipAt(ctrl.clips.first.id, 4.0);
      expect(ctrl.clips.length, 2);
      expect(ctrl.clips[0].durationSec, closeTo(4.0, 0.001));
      expect(ctrl.clips[1].timelineStartSec, closeTo(4.0, 0.001));
      expect(ctrl.clips[1].sourceInSec, closeTo(4.0, 0.001));
      expect(ctrl.clips[1].durationSec, closeTo(6.0, 0.001));

      // Duplicate selected (right half)
      ctrl.duplicateSelectedClip();
      expect(ctrl.clips.length, 3);
      expect(ctrl.clips[2].timelineStartSec, closeTo(10.0, 0.001));

      // Undo back to 2 clips
      ctrl.undo();
      expect(ctrl.clips.length, 2);

      // Redo back to 3 clips
      ctrl.redo();
      expect(ctrl.clips.length, 3);

      ctrl.dispose();
    });

    test('saves and loads .fyrd project round-trip', () async {
      final tmp = await Directory.systemTemp.createTemp('fyrdirector_test_');
      try {
        final ctrl = DirectorController(enableMediaKit: false);
        ctrl.addTitleClip(
          name: 'Intro Title',
          style: TitleClipStyle(text: 'Hello World', fontSize: 48),
          durationSec: 5.0,
          atSec: 1.5,
        );
        final path = '${tmp.path}/demo.fyrd';
        await ctrl.saveProject(path);
        expect(File(path).existsSync(), isTrue);

        final ctrl2 = DirectorController(enableMediaKit: false);
        await ctrl2.openProject(path);
        expect(ctrl2.clips.length, 1);
        expect(ctrl2.clips.first.name, 'Intro Title');
        expect(ctrl2.clips.first.titleStyle?.text, 'Hello World');
        expect(ctrl2.clips.first.timelineStartSec, closeTo(1.5, 0.001));

        ctrl.dispose();
        ctrl2.dispose();
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });

  group('fyrDirector UI Smoke Test', () {
    testWidgets('renders MediaBin, ProgramMonitor, Inspector, and Timeline',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 880);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final ctrl = DirectorController(enableMediaKit: false);
      ctrl.addTitleClip(
        name: 'Sample Title',
        style: TitleClipStyle(text: 'FyrDE Cinema', fontSize: 56),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: ctrl,
          child: const FyrDirectorApp(),
        ),
      );
      await tester.pump();

      expect(find.text('fyrDirector'), findsOneWidget);
      expect(find.text('Media'), findsOneWidget);
      expect(find.text('Titles'), findsOneWidget);
      expect(find.text('Effects'), findsOneWidget);
      expect(find.text('TRACKS'), findsOneWidget);
      expect(find.text('Export'), findsOneWidget);
      expect(find.text('FyrDE Cinema'), findsNWidgets(2));
    });
  });
}
