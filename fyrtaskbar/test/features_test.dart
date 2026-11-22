import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrtaskbar/services/osd_service.dart';
import 'package:fyrtaskbar/state/system_state.dart';

void main() {
  setUp(() {
    SystemState.clearAllNotifications();
    SystemState.doNotDisturb.value = false;
    SystemState.dismissScreenshotPreview();
  });

  test('Do Not Disturb records notification history but suppresses popups', () {
    SystemState.doNotDisturb.value = true;
    SystemState.addNotification(
      appName: 'Firefox',
      title: 'Download finished',
      body: 'archive.tar.gz',
      timeout: 0,
    );

    expect(SystemState.notifications.value.length, 1);
    expect(SystemState.activePopups.value, isEmpty);

    SystemState.doNotDisturb.value = false;
    SystemState.addNotification(
      appName: 'Firefox',
      title: 'Second download',
      body: 'image.png',
      timeout: 0,
    );

    expect(SystemState.notifications.value.length, 2);
    expect(SystemState.activePopups.value.length, 1);
  });

  test('dismissAppNotifications clears only the targeted app group', () {
    SystemState.addNotification(
      appName: 'Discord',
      title: 'Msg 1',
      body: 'Hi',
      timeout: 0,
    );
    SystemState.addNotification(
      appName: 'Discord',
      title: 'Msg 2',
      body: 'Hello',
      timeout: 0,
    );
    SystemState.addNotification(
      appName: 'Mail',
      title: 'Subject',
      body: 'Body',
      timeout: 0,
    );

    SystemState.dismissAppNotifications('Discord');
    expect(SystemState.notifications.value.length, 1);
    expect(SystemState.notifications.value.first.appName, 'Mail');
  });

  test('OsdService handles screenshot preview socket command', () async {
    final tmpDir = await Directory.systemTemp.createTemp('fyrtaskbar_osd_');
    final sockPath = '${tmpDir.path}/osd.sock';
    try {
      await OsdService.init(socketPath: sockPath);
      final client = await Socket.connect(
        InternetAddress(sockPath, type: InternetAddressType.unix),
        0,
      );
      client.writeln('screenshot Region screenshot|/tmp/test_shot.png');
      await client.flush();
      await client.close();

      await Future.delayed(const Duration(milliseconds: 120));
      final preview = SystemState.activeScreenshotToast.value;
      expect(preview, isNotNull);
      expect(preview!.label, 'Region screenshot');
      expect(preview.filePath, '/tmp/test_shot.png');
    } finally {
      await OsdService.dispose();
      SystemState.dismissScreenshotPreview();
      if (await tmpDir.exists()) {
        await tmpDir.delete(recursive: true);
      }
    }
  });
}
