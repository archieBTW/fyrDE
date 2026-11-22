import 'package:flutter_test/flutter_test.dart';
import 'package:fyrav/main.dart';

void main() {
  group('SecurityState UFW parsers and validators', () {
    test('parseUfwConfEnabled detects ENABLED=yes', () {
      expect(
        SecurityState.parseUfwConfEnabled('# comment\nENABLED=yes\n'),
        isTrue,
      );
      expect(
        SecurityState.parseUfwConfEnabled('# ENABLED=yes\nENABLED=no\n'),
        isFalse,
      );
    });

    test('parseUserRulesFile parses tuple lines cleanly', () {
      const sample = '''
### RULES ###
### tuple ### allow tcp 1714:1764 0.0.0.0/0 any 0.0.0.0/0 in
### tuple ### limit tcp 22 0.0.0.0/0 any 192.168.1.0/24 in
### END RULES ###
''';
      final rules = SecurityState.parseUserRulesFile(sample);
      expect(rules.length, 2);
      expect(rules[0].target, '1714:1764/tcp');
      expect(rules[0].action, 'ALLOW IN');
      expect(rules[0].from, 'Anywhere');
      expect(rules[1].target, '22/tcp');
      expect(rules[1].action, 'LIMIT IN');
      expect(rules[1].from, '192.168.1.0/24');
    });

    test('parseNumberedStatus parses ufw status numbered output', () {
      const sample = '''
Status: active

     To                         Action      From
     --                         ------      ----
[ 1] 1714:1764/tcp              ALLOW IN    Anywhere
[ 2] 22/tcp                     LIMIT IN    Anywhere
[ 3] 1714:1764/tcp (v6)         ALLOW IN    Anywhere (v6)
''';
      final rules = SecurityState.parseNumberedStatus(sample);
      expect(rules.length, 3);
      expect(rules[0].number, 1);
      expect(rules[0].target, '1714:1764/tcp');
      expect(rules[0].action, 'ALLOW IN');
      expect(rules[0].from, 'Anywhere');
      expect(rules[2].number, 3);
      expect(rules[2].isIpv6, isTrue);
    });

    test('validatePortSpec validates single ports and ranges', () {
      expect(SecurityState.validatePortSpec('22'), isNull);
      expect(SecurityState.validatePortSpec('1714:1764'), isNull);
      expect(SecurityState.validatePortSpec(''), isNotNull);
      expect(SecurityState.validatePortSpec('70000'), isNotNull);
      expect(SecurityState.validatePortSpec('1764:1714'), isNotNull);
      expect(SecurityState.validatePortSpec('abc'), isNotNull);
    });
  });

  testWidgets('FyrAVApp renders without triggering authentication', (tester) async {
    await tester.pumpWidget(const FyrAVApp());
    expect(find.text('FyrAV'), findsOneWidget);
    expect(find.text('Firewall'), findsOneWidget);
  });
}
