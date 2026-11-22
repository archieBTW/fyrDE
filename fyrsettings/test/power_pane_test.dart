import 'package:flutter_test/flutter_test.dart';
import 'package:fyrsettings/panes/power_pane.dart';

void main() {
  group('PowerLockConfig', () {
    test('defaults to lid-close + before-sleep lock with no idle timeout', () {
      const cfg = PowerLockConfig();
      expect(cfg.screenLockEnabled, isTrue);
      expect(cfg.lockOnLidClose, isTrue);
      expect(cfg.lockBeforeSleep, isTrue);
      expect(cfg.autoLockOnIdle, isFalse);
      expect(cfg.isLidCloseOnlyMode, isTrue);

      final args = cfg.buildSwayIdleArgs(lockCommand: '/home/u/.config/fyr/lock.sh');
      expect(args, ['-w', 'before-sleep', '/home/u/.config/fyr/lock.sh']);

      final dropIn = cfg.renderDropIn();
      expect(dropIn, contains('bindswitch --reload --locked lid:on exec ~/.config/fyr/lock.sh'));
      expect(dropIn, contains("exec swayidle -w before-sleep '~/.config/fyr/lock.sh'"));
      expect(dropIn, isNot(contains('timeout')));
    });

    test('disabling screen lock removes lid switch and all lock commands', () {
      const cfg = PowerLockConfig(
        screenLockEnabled: false,
        lockOnLidClose: true,
        lockBeforeSleep: true,
        autoLockOnIdle: true,
        lockTimeoutMinutes: 5,
      );

      final args = cfg.buildSwayIdleArgs(lockCommand: '/home/u/.config/fyr/lock.sh');
      expect(args, ['-w']);
      expect(cfg.renderDropIn(), isEmpty);
    });

    test('enabling auto-lock with custom timeout emits timeout in seconds', () {
      const cfg = PowerLockConfig(
        screenLockEnabled: true,
        lockOnLidClose: false,
        lockBeforeSleep: true,
        autoLockOnIdle: true,
        lockTimeoutMinutes: 15,
        offMinutes: 30,
      );

      final args = cfg.buildSwayIdleArgs(lockCommand: '/home/u/.config/fyr/lock.sh');
      expect(args, [
        '-w',
        'timeout',
        '900',
        '/home/u/.config/fyr/lock.sh',
        'timeout',
        '1800',
        'swaymsg "output * power off"',
        'resume',
        'swaymsg "output * power on"',
        'before-sleep',
        '/home/u/.config/fyr/lock.sh',
      ]);

      final dropIn = cfg.renderDropIn();
      expect(dropIn, isNot(contains('bindswitch')));
      expect(dropIn, contains('timeout 900'));
    });
  });
}
