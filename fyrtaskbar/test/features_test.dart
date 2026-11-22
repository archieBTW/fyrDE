import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrtaskbar/models/notification.dart';
import 'package:fyrtaskbar/services/app_service.dart';
import 'package:fyrtaskbar/services/osd_service.dart';
import 'package:fyrtaskbar/services/tray_service.dart';
import 'package:fyrtaskbar/state/system_state.dart';
import 'package:fyrtaskbar/ui/taskbar_screen.dart';
import 'package:fyrtaskbar/ui/tray_menu_popup.dart';

void main() {
  setUp(() {
    SystemState.clearAllNotifications();
    SystemState.doNotDisturb.value = false;
    SystemState.dismissScreenshotPreview();
    SystemState.activeVpnName.value = null;
    TrayService.resetForTest();
    SystemState.screenWidth = 1920;
    SystemState.screenHeight = 1080;
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

  group('TaskbarScreen popup layout and input-region regressions', () {
    late Directory tempAppsDir;
    late List<({String channel, String method, dynamic arguments})> nativeCalls;

    setUp(() async {
      tempAppsDir = Directory.systemTemp.createTempSync('fyrtaskbar_screen_');
      File('${tempAppsDir.path}/sample.desktop').writeAsStringSync(
        '[Desktop Entry]\nType=Application\nName=Sample App\nExec=true\n',
      );
      AppService.searchPathsOverride = {tempAppsDir.path};
      await AppService.resetForTest();

      nativeCalls = [];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('fyrtaskbar/resize'),
        (call) async {
          nativeCalls.add((
            channel: 'resize',
            method: call.method,
            arguments: call.arguments,
          ));
          return null;
        },
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('wayland_layer_shell'),
        (call) async {
          nativeCalls.add((
            channel: 'wls',
            method: call.method,
            arguments: call.arguments,
          ));
          return true;
        },
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async {
          nativeCalls.add((
            channel: 'wm',
            method: call.method,
            arguments: call.arguments,
          ));
          return true;
        },
      );
    });

    tearDown(() async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('fyrtaskbar/resize'),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('wayland_layer_shell'),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        null,
      );
      await AppService.resetForTest();
      AppService.searchPathsOverride = null;
      if (tempAppsDir.existsSync()) {
        tempAppsDir.deleteSync(recursive: true);
      }
    });

    testWidgets(
      'popup area spans full width and outside tap / Escape collapses overlay',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(1920, 1080));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(const MaterialApp(home: TaskbarScreen()));
        await tester.pump();

        // Regression: ScreenshotToastOverlay returning non-positioned
        // SizedBox.shrink() previously collapsed ClipRect/Stack width to 0.0.
        final clipRectSize = tester.getSize(find.byType(ClipRect));
        expect(clipRectSize.width, 1920.0);
        expect(clipRectSize.height, 1024.0);

        // Tap start button to open Start Menu.
        await tester.tapAt(const Offset(30, 28));
        await tester.pumpAndSettle();

        expect(find.text('Sample App'), findsOneWidget);
        expect(
          nativeCalls.any(
            (c) =>
                c.channel == 'resize' &&
                c.method == 'setSize' &&
                c.arguments['height'] == 1080,
          ),
          isTrue,
        );
        expect(
          nativeCalls.any(
            (c) =>
                c.channel == 'resize' &&
                c.method == 'setInputRegion' &&
                c.arguments['full'] == true,
          ),
          isTrue,
        );

        // Tap outside Start Menu on the transparent backdrop to dismiss it.
        nativeCalls.clear();
        await tester.tapAt(const Offset(960, 540));
        await tester.pumpAndSettle();

        expect(
          nativeCalls.any(
            (c) =>
                c.channel == 'resize' &&
                c.method == 'setSize' &&
                c.arguments['height'] == 56,
          ),
          isTrue,
        );
        expect(
          nativeCalls.any(
            (c) =>
                c.channel == 'wls' &&
                c.method == 'setLayer' &&
                c.arguments['layer'] == 2, // ShellLayer.layerTop
          ),
          isTrue,
        );

        // Open Calendar via clock tap and dismiss via Escape key.
        nativeCalls.clear();
        await tester.tapAt(const Offset(960, 28));
        await tester.pumpAndSettle();
        expect(find.text('Open Calendar'), findsOneWidget);

        nativeCalls.clear();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('Open Calendar'), findsNothing);
        expect(
          nativeCalls.any(
            (c) =>
                c.channel == 'resize' &&
                c.method == 'setSize' &&
                c.arguments['height'] == 56,
          ),
          isTrue,
        );

        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );

    testWidgets(
      'passive notifications and screenshot toast restrict input region instead of blocking desktop',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(1920, 1080));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(const MaterialApp(home: TaskbarScreen()));
        await tester.pump();
        nativeCalls.clear();

        SystemState.activePopups.value = [
          FyrNotification(
            id: 1,
            appName: 'System',
            title: 'Hello',
            body: 'World',
            icon: '',
            timestamp: DateTime.now(),
            timeout: 0,
          ),
        ];
        await tester.pump();
        await tester.pump();

        final regionCall = nativeCalls.lastWhere(
          (c) => c.channel == 'resize' && c.method == 'setInputRegion',
        );
        expect(regionCall.arguments['full'], isNull);
        final rects = regionCall.arguments['rects'] as List<dynamic>;
        expect(rects.length, 2);
        // Top bar rect
        expect(rects[0]['y'], 0);
        expect(rects[0]['height'], 56);
        // Top-center notification popup rect only (leaves rest of screen click-through)
        expect(rects[1]['x'], (1920 - 356) ~/ 2);
        expect(rects[1]['y'], 56);

        // Screenshot toast also keeps the rest of the desktop click-through.
        nativeCalls.clear();
        SystemState.activePopups.value = [];
        SystemState.activeScreenshotToast.value = ScreenshotPreview(
          filePath: '/tmp/nonexistent_test_shot.png',
          label: 'Region screenshot',
          timestamp: DateTime.now(),
        );
        await tester.pump();
        await tester.pump();

        final toastRegionCall = nativeCalls.lastWhere(
          (c) => c.channel == 'resize' && c.method == 'setInputRegion',
        );
        expect(toastRegionCall.arguments['full'], isNull);
        final toastRects = toastRegionCall.arguments['rects'] as List<dynamic>;
        expect(toastRects.length, 2);
        expect(toastRects[1]['x'], greaterThan(1500));

        // Clearing toasts collapses back to 56px and restores full input region.
        nativeCalls.clear();
        SystemState.dismissScreenshotPreview();
        await tester.pump();
        await tester.pump();

        expect(
          nativeCalls.any(
            (c) =>
                c.channel == 'resize' &&
                c.method == 'setSize' &&
                c.arguments['height'] == 56,
          ),
          isTrue,
        );
        expect(
          nativeCalls.any(
            (c) =>
                c.channel == 'resize' &&
                c.method == 'setInputRegion' &&
                c.arguments['full'] == true,
          ),
          isTrue,
        );

        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );

    test('TrayService.parseRegistration handles all SNI registration forms', () {
      expect(
        TrayService.parseRegistration('/StatusNotifierItem', ':1.42'),
        (':1.42', '/StatusNotifierItem'),
      );
      expect(
        TrayService.parseRegistration(
          'org.kde.StatusNotifierItem-proton.vpn.app.gtk-1234',
          ':1.99',
        ),
        (
          'org.kde.StatusNotifierItem-proton.vpn.app.gtk-1234',
          '/StatusNotifierItem',
        ),
      );
      expect(
        TrayService.parseRegistration(':1.55/org/ayatana/NotificationItem/app', null),
        (':1.55', '/org/ayatana/NotificationItem/app'),
      );
    });

    test('TrayItem.displayLabel combines title and accessible status description', () {
      const item = TrayItem(
        serviceKey: 'org.kde.StatusNotifierItem-proton-1/StatusNotifierItem',
        busName: 'org.kde.StatusNotifierItem-proton-1',
        objectPath: '/StatusNotifierItem',
        id: 'proton.vpn.app.gtk',
        title: 'Proton VPN',
        tooltip: '',
        iconAccessibleDesc: 'VPN connected',
        status: 'Active',
        iconName: 'proton-vpn-sign',
        iconThemePath: '',
        resolvedIconFile: null,
        pixmapImage: null,
        itemIsMenu: true,
        menuPath: '/MenuBar',
      );
      expect(item.displayTitle, 'Proton VPN');
      expect(item.displayLabel, 'Proton VPN — VPN connected');
    });

    testWidgets(
      'TaskbarScreen renders AppIndicator tray icons and TrayMenuPopup',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(1920, 1080));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const vpnItem = TrayItem(
          serviceKey: 'org.kde.StatusNotifierItem-proton-1/StatusNotifierItem',
          busName: 'org.kde.StatusNotifierItem-proton-1',
          objectPath: '/StatusNotifierItem',
          id: 'proton.vpn.app.gtk',
          title: 'Proton VPN',
          tooltip: '',
          iconAccessibleDesc: 'VPN connected',
          status: 'Active',
          iconName: 'proton-vpn-sign',
          iconThemePath: '',
          resolvedIconFile: null,
          pixmapImage: null,
          itemIsMenu: true,
          menuPath: '/MenuBar',
        );
        TrayService.items.value = const [vpnItem];

        await tester.pumpWidget(const MaterialApp(home: TaskbarScreen()));
        await tester.pump();

        final trayFinder = find.bySemanticsLabel('Proton VPN — VPN connected');
        expect(trayFinder, findsOneWidget);
        expect(find.byType(Tooltip), findsNothing);

        // Tap the tray icon to open its popup menu
        await tester.tap(trayFinder);
        await tester.pumpAndSettle();

        expect(find.byType(TrayMenuPopup), findsOneWidget);
        expect(find.text('Proton VPN'), findsOneWidget);
        expect(find.text('VPN connected'), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );

    test('SystemState.parseActiveVpnFromNmcli detects WireGuard and OpenVPN connections', () {
      const sample = '''
AWTR:802-11-wireless:activated
pvpn-killswitch-ipv6:dummy:activated
ProtonVPN US-TX#543:wireguard:activated
lo:loopback:activated
''';
      expect(
        SystemState.parseActiveVpnFromNmcli(sample),
        'ProtonVPN US-TX#543',
      );
      expect(
        SystemState.parseActiveVpnFromNmcli(
          'Office\\:Primary:vpn:activated\nAWTR:802-11-wireless:activated\n',
        ),
        'Office:Primary',
      );
      expect(
        SystemState.parseActiveVpnFromNmcli('AWTR:802-11-wireless:activated\n'),
        isNull,
      );
    });

    testWidgets(
      'TaskbarScreen shows generic VPN indicator when activeVpnName is set',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(1920, 1080));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        SystemState.activeVpnName.value = 'Work WireGuard';
        await tester.pumpWidget(const MaterialApp(home: TaskbarScreen()));
        await tester.pump();

        expect(find.bySemanticsLabel('VPN: Work WireGuard'), findsOneWidget);
        expect(find.byIcon(Icons.vpn_lock_rounded), findsOneWidget);
        expect(find.byType(Tooltip), findsNothing);

        // Open Quick Settings and verify neither "Quick Settings" heading nor
        // a Settings button appears in the menu.
        await tester.tapAt(const Offset(1880, 28));
        await tester.pumpAndSettle();
        expect(find.text('Quick Settings'), findsNothing);
        expect(find.byIcon(Icons.settings_rounded), findsNothing);
        expect(find.text('Settings'), findsNothing);

        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  });
}
