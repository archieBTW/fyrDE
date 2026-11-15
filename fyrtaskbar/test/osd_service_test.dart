import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fyrtaskbar/services/osd_service.dart';

void main() {
  group('OsdService', () {
    test('parses volume, mic, and brightness commands accurately', () {
      final vol = OsdService.parseCommand('volume 72');
      expect(vol, isNotNull);
      expect(vol!.kind, 'volume');
      expect(vol.label, 'Volume');
      expect(vol.valueText, '72%');
      expect(vol.fraction, closeTo(0.72, 0.001));
      expect(vol.muted, isFalse);

      final mutedVol = OsdService.parseCommand('volume 50 muted');
      expect(mutedVol!.muted, isTrue);
      expect(mutedVol.valueText, 'Muted');

      final micMuted = OsdService.parseCommand('mic muted');
      expect(micMuted!.kind, 'mic');
      expect(micMuted.muted, isTrue);
      expect(micMuted.valueText, 'Muted');

      final micOn = OsdService.parseCommand('mic unmuted');
      expect(micOn!.muted, isFalse);
      expect(micOn.valueText, 'Active');

      final bright = OsdService.parseCommand('brightness 45');
      expect(bright!.kind, 'brightness');
      expect(bright.valueText, '45%');
      expect(bright.fraction, closeTo(0.45, 0.001));

      expect(OsdService.parseCommand('unknown 10'), isNull);
    });

    test('receives socket commands and invokes show then auto-hide', () async {
      final tmpDir = Directory.systemTemp.createTempSync('fyrosd_test_');
      addTearDown(() async {
        await OsdService.dispose();
        if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
      });

      final sockPath = '${tmpDir.path}/osd.sock';
      final calls = <({String method, Map<String, dynamic>? args})>[];

      await OsdService.init(
        socketPath: sockPath,
        invoker: (method, args) async {
          calls.add((method: method, args: args));
        },
      );

      final client = await Socket.connect(
        InternetAddress(sockPath, type: InternetAddressType.unix),
        0,
      );
      client.writeln('volume 80');
      await client.flush();
      await client.close();

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(calls, isNotEmpty);
      expect(calls.first.method, 'show');
      expect(calls.first.args?['kind'], 'volume');
      expect(calls.first.args?['valueText'], '80%');
    });
  });
}
