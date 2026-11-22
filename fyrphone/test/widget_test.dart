import 'package:flutter_test/flutter_test.dart';
import 'package:fyrphone/kde_connect_service.dart';
import 'package:fyrphone/main.dart';

void main() {
  group('KdeConnectService helpers', () {
    test('resolvePairingState handles modern pairState values', () {
      final notPaired = KdeConnectService.resolvePairingState(pairState: 0);
      expect(notPaired.isPaired, isFalse);
      expect(notPaired.isPairRequested, isFalse);
      expect(notPaired.isPairRequestedByPeer, isFalse);

      final requested = KdeConnectService.resolvePairingState(pairState: 1);
      expect(requested.isPaired, isFalse);
      expect(requested.isPairRequested, isTrue);
      expect(requested.isPairRequestedByPeer, isFalse);

      final byPeer = KdeConnectService.resolvePairingState(pairState: 2);
      expect(byPeer.isPaired, isFalse);
      expect(byPeer.isPairRequested, isFalse);
      expect(byPeer.isPairRequestedByPeer, isTrue);

      final paired = KdeConnectService.resolvePairingState(pairState: 3);
      expect(paired.isPaired, isTrue);
      expect(paired.isPairRequested, isFalse);
      expect(paired.isPairRequestedByPeer, isFalse);
    });

    test('resolvePairingState falls back to legacy booleans', () {
      final legacy = KdeConnectService.resolvePairingState(
        isPaired: false,
        isPairRequestedByPeer: true,
      );
      expect(legacy.isPaired, isFalse);
      expect(legacy.isPairRequested, isFalse);
      expect(legacy.isPairRequestedByPeer, isTrue);
    });

    test('LAN and VPN interface classification filters virtual/VPN interfaces', () {
      expect(KdeConnectService.isLanInterfaceName('wlo1'), isTrue);
      expect(KdeConnectService.isLanInterfaceName('enp3s0'), isTrue);
      expect(KdeConnectService.isLanInterfaceName('lo'), isFalse);
      expect(KdeConnectService.isLanInterfaceName('docker0'), isFalse);
      expect(KdeConnectService.isLanInterfaceName('tailscale0'), isFalse);
      expect(KdeConnectService.isLanInterfaceName('wg0'), isFalse);

      expect(KdeConnectService.isVpnInterfaceName('proton0'), isTrue);
      expect(KdeConnectService.isVpnInterfaceName('wg0'), isTrue);
      expect(KdeConnectService.isVpnInterfaceName('tun0'), isTrue);
      expect(KdeConnectService.isVpnInterfaceName('tailscale0'), isTrue);
      expect(KdeConnectService.isVpnInterfaceName('wlo1'), isFalse);
    });

    test('parseUfwConfEnabled parses ENABLED=yes accurately', () {
      expect(
        KdeConnectService.parseUfwConfEnabled('# comment\nENABLED=yes\nLOGLEVEL=low\n'),
        isTrue,
      );
      expect(
        KdeConnectService.parseUfwConfEnabled('# ENABLED=yes\nENABLED=no\n'),
        isFalse,
      );
    });

    test('hasKdeConnectUfwRule requires both TCP and UDP 1714:1764', () {
      const bothRules = '''
### RULES ###
### tuple ### allow tcp 1714:1764 0.0.0.0/0 any 0.0.0.0/0 in
### tuple ### allow udp 1714:1764 0.0.0.0/0 any 0.0.0.0/0 in
### END RULES ###
''';
      const tcpOnly = '''
### tuple ### allow tcp 1714:1764 0.0.0.0/0 any 0.0.0.0/0 in
''';
      expect(KdeConnectService.hasKdeConnectUfwRule(bothRules), isTrue);
      expect(KdeConnectService.hasKdeConnectUfwRule(tcpOnly), isFalse);
      expect(KdeConnectService.hasKdeConnectUfwRule(''), isFalse);
    });
  });

  testWidgets('FyrConnectApp renders fyrConnect branding', (tester) async {
    await tester.pumpWidget(const FyrConnectApp());
    expect(find.text('fyrConnect'), findsOneWidget);
    expect(find.text('CONNECTION HELPER'), findsOneWidget);
  });
}
