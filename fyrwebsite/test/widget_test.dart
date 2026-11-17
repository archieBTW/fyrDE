import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fyrwebsite/main.dart';

void main() {
  test('fyrApps grid includes fyrGraphics, fyrEmu, and fyrDirector with existing screenshots', () {
    const grid = AppGrid(category: 'productivity');
    final apps = grid.getApps();

    final byName = {for (final app in apps) app['name']!: app};
    expect(byName.containsKey('fyrGraphics'), isTrue);
    expect(byName.containsKey('fyrEmu'), isTrue);
    expect(byName.containsKey('fyrDirector'), isTrue);

    expect(byName['fyrGraphics']!['desc'], startsWith('frickin sweet '));
    expect(byName['fyrEmu']!['desc'], startsWith('frickin sweet '));
    expect(byName['fyrDirector']!['desc'], startsWith('frickin sweet '));

    for (final name in ['fyrGraphics', 'fyrEmu', 'fyrDirector']) {
      final imgFile = File('assets/screenshots/${byName[name]!['img']}');
      expect(imgFile.existsSync(), isTrue, reason: 'Missing ${imgFile.path}');
    }
  });
}
