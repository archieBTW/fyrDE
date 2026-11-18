import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fyrwebsite/main.dart';

void main() {
  test('fyrTools and fyrApps grids include all DE apps with existing compressed screenshots', () {
    const coreGrid = AppGrid(category: 'core');
    const systemGrid = AppGrid(category: 'system');
    const prodGrid = AppGrid(category: 'productivity');

    final coreApps = coreGrid.getApps();
    final systemApps = systemGrid.getApps();
    final prodApps = prodGrid.getApps();

    final systemByName = {for (final app in systemApps) app['name']!: app};
    final prodByName = {for (final app in prodApps) app['name']!: app};

    for (final name in [
      'Terminal',
      'fyrFiles',
      'fyrStore',
      'Settings',
      'fyrMonitor',
      'fyrDisks',
      'FyrAV',
      'FyrText',
      'Calendar',
      'Clock',
      'Calculator',
      'fyrHelp',
      'fyrEmoji',
    ]) {
      expect(systemByName.containsKey(name), isTrue, reason: 'Missing $name in system grid');
      expect(systemByName[name]!['desc'], startsWith('frickin sweet '));
    }

    for (final name in [
      'Goose',
      'FyrCode',
      'fyrAPI',
      'Music',
      'Sound Booth',
      'Journal',
      'fyrConnect',
      'Photos',
      'Watchbox',
      'Camera',
      'fyrVM',
      'fyrTorrent',
      'fyrGraphics',
      'fyrEmu',
      'fyrDirector',
      'fyrDocs',
      'fyrSheets',
      'fyrSlides',
      'fyrDB',
      'fyrPods',
    ]) {
      expect(prodByName.containsKey(name), isTrue, reason: 'Missing $name in productivity grid');
      expect(prodByName[name]!['desc'], startsWith('frickin sweet '));
    }

    for (final app in [...coreApps, ...systemApps, ...prodApps]) {
      final imgFile = File('assets/screenshots/${app['img']}');
      expect(imgFile.existsSync(), isTrue, reason: 'Missing ${imgFile.path}');
      expect(
        imgFile.lengthSync(),
        lessThan(800 * 1024),
        reason: 'Expected ${imgFile.path} to be compressed (< 800 KB)',
      );
    }
  });
}
