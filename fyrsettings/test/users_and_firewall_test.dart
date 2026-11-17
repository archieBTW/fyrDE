import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrsettings/panes/firewall_pane.dart';
import 'package:fyrsettings/panes/users_pane.dart';
import 'package:fyrsettings/services/firewall_service.dart';
import 'package:fyrsettings/services/users_service.dart';

void main() {
  group('UsersService', () {
    test('parses human users, admin roles, and GECOS display names', () {
      const passwd = '''
root:x:0:0:root:/root:/bin/bash
nobody:x:65534:65534:Kernel Overflow User:/:/usr/bin/nologin
archer:x:1000:1000:Archer User,Room 101:/home/archer:/bin/zsh
guest:x:1001:1001:Guest Account:/home/guest:/bin/bash
svc:x:1002:1002:Service:/var/svc:/usr/bin/nologin
''';
      const group = '''
root:x:0:root
wheel:x:998:archer
users:x:985:archer,guest
''';

      final users = UsersService.parsePasswdAndGroup(
        passwd,
        group,
        currentUser: 'archer',
      );
      expect(users.map((u) => u.username).toList(), ['archer', 'guest']);
      expect(users[0].fullName, 'Archer User');
      expect(users[0].isAdmin, isTrue);
      expect(users[0].isCurrent, isTrue);
      expect(users[1].fullName, 'Guest Account');
      expect(users[1].isAdmin, isFalse);
      expect(users[1].isCurrent, isFalse);

      expect(UsersService.isValidUsername('alice_01'), isTrue);
      expect(UsersService.isValidUsername('InvalidUser'), isFalse);
      expect(UsersService.isValidUsername('1bad'), isFalse);
    });
  });

  group('FirewallService', () {
    test('parses ufw status verbose, numbered rules, and builds add-rule commands', () {
      const verbose = '''
Status: active
Logging: on (medium)
Default: deny (incoming), allow (outgoing), disabled (routed)
New profiles: skip
''';
      final parsed = FirewallService.parseUfwStatusVerbose(verbose);
      expect(parsed.isActive, isTrue);
      expect(parsed.loggingLevel, 'medium');
      expect(parsed.defaultIncoming, 'deny');
      expect(parsed.defaultOutgoing, 'allow');

      const numbered = '''
Status: active

     To                         Action      From
     --                         ------      ----
[ 1] 22/tcp                     ALLOW IN    192.168.1.0/24             # LAN SSH
[ 2] 443/tcp                    ALLOW IN    Anywhere
[ 3] 22/tcp (v6)                LIMIT IN    Anywhere (v6)
''';
      final rules = FirewallService.parseUfwStatusNumbered(numbered);
      expect(rules.length, 3);
      expect(rules[0].number, 1);
      expect(rules[0].to, '22/tcp');
      expect(rules[0].action, 'ALLOW');
      expect(rules[0].direction, 'IN');
      expect(rules[0].from, '192.168.1.0/24');
      expect(rules[0].comment, 'LAN SSH');
      expect(rules[2].isV6, isTrue);
      expect(rules[2].action, 'LIMIT');

      expect(
        FirewallService.buildAddRuleArgs(
          action: 'allow',
          portOrService: '22',
          protocol: 'tcp',
          direction: 'in',
          fromAddress: '10.0.0.0/8',
          comment: 'Corp',
        ),
        [
          'ufw',
          'allow',
          'from',
          '10.0.0.0/8',
          'to',
          'any',
          'port',
          '22',
          'proto',
          'tcp',
          'comment',
          'Corp',
        ],
      );
    });
  });

  group('UsersPane and FirewallPane widgets', () {
    testWidgets('UsersPane displays accounts and validates Add User dialog', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UsersPane(
              autoLoadOnInit: false,
              initialUsers: [
                SystemUserAccount(
                  username: 'archer',
                  fullName: 'Archer User',
                  uid: 1000,
                  gid: 1000,
                  homeDir: '/home/archer',
                  shell: '/bin/zsh',
                  isAdmin: true,
                  isCurrent: true,
                  groups: ['wheel'],
                ),
                SystemUserAccount(
                  username: 'guest',
                  fullName: 'Guest',
                  uid: 1001,
                  gid: 1001,
                  homeDir: '/home/guest',
                  shell: '/bin/bash',
                  isAdmin: false,
                  isCurrent: false,
                  groups: ['guest'],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('User Accounts'), findsOneWidget);
      expect(find.text('Archer User'), findsOneWidget);
      expect(find.text('Administrator'), findsOneWidget);
      expect(find.text('Standard'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget); // Only non-current user

      await tester.tap(find.text('Add User'));
      await tester.pumpAndSettle();
      expect(find.text('Add User Account'), findsOneWidget);
      await tester.tap(find.text('Create User'));
      await tester.pump();
      expect(find.textContaining('lowercase letters'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('FirewallPane displays policies and rules', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FirewallPane(
              autoLoadOnInit: false,
              initialSnapshot: FirewallSnapshot(
                hasUfw: true,
                hasFirewalld: false,
                isActive: true,
                enabledAtBoot: true,
                defaultIncoming: 'deny',
                defaultOutgoing: 'allow',
                loggingLevel: 'low',
                rulesLoaded: true,
                rules: [
                  FirewallRule(
                    number: 1,
                    to: '22/tcp',
                    action: 'ALLOW',
                    direction: 'IN',
                    from: 'Anywhere',
                    comment: 'SSH',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Firewall (UFW)'), findsOneWidget);
      expect(find.text('Firewall Rules (1)'), findsOneWidget);
      expect(find.text('22/tcp'), findsOneWidget);
      expect(find.text('ALLOW IN'), findsOneWidget);

      await tester.tap(find.text('Add Rule'));
      await tester.pumpAndSettle();
      expect(find.text('Add Firewall Rule'), findsOneWidget);
      expect(find.text('SSH (22/tcp)'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });
}
