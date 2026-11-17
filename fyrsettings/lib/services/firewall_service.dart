import 'dart:io';

/// Single numbered firewall rule from `ufw status numbered`.
class FirewallRule {
  final int number;
  final String to;
  final String action;
  final String direction;
  final String from;
  final bool isV6;
  final String? comment;

  const FirewallRule({
    required this.number,
    required this.to,
    required this.action,
    required this.direction,
    required this.from,
    this.isV6 = false,
    this.comment,
  });
}

/// Snapshot of UFW configuration and rules.
class FirewallSnapshot {
  final bool hasUfw;
  final bool hasFirewalld;
  final bool isActive;
  final bool enabledAtBoot;
  final String defaultIncoming;
  final String defaultOutgoing;
  final String loggingLevel;
  final bool rulesLoaded;
  final List<FirewallRule> rules;

  const FirewallSnapshot({
    required this.hasUfw,
    required this.hasFirewalld,
    required this.isActive,
    required this.enabledAtBoot,
    this.defaultIncoming = 'deny',
    this.defaultOutgoing = 'allow',
    this.loggingLevel = 'low',
    this.rulesLoaded = false,
    this.rules = const [],
  });
}

/// Parsing and command helpers for UFW firewall management.
class FirewallService {
  static Future<bool> _hasBinary(String name) async {
    try {
      final res = await Process.run('which', [name]);
      return res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Parses `ufw status verbose` output for active status, defaults, and logging.
  static ({
    bool isActive,
    String defaultIncoming,
    String defaultOutgoing,
    String loggingLevel,
  }) parseUfwStatusVerbose(String output) {
    bool active = false;
    String incoming = 'deny';
    String outgoing = 'allow';
    String logging = 'low';

    for (final raw in output.split('\n')) {
      final line = raw.trim();
      final lower = line.toLowerCase();
      if (lower.startsWith('status:')) {
        active = lower.contains('active') && !lower.contains('inactive');
      } else if (lower.startsWith('logging:')) {
        if (lower.contains('off')) {
          logging = 'off';
        } else {
          final m = RegExp(r'\((\w+)\)').firstMatch(lower);
          if (m != null) logging = m.group(1)!;
        }
      } else if (lower.startsWith('default:')) {
        final inMatch =
            RegExp(r'(allow|deny|reject)\s*\(incoming\)').firstMatch(lower);
        if (inMatch != null) incoming = inMatch.group(1)!;
        final outMatch =
            RegExp(r'(allow|deny|reject)\s*\(outgoing\)').firstMatch(lower);
        if (outMatch != null) outgoing = outMatch.group(1)!;
      }
    }
    return (
      isActive: active,
      defaultIncoming: incoming,
      defaultOutgoing: outgoing,
      loggingLevel: logging,
    );
  }

  /// Parses `ufw status numbered` lines such as:
  /// `[ 1] 22/tcp                     ALLOW IN    Anywhere                   # SSH`
  static List<FirewallRule> parseUfwStatusNumbered(String output) {
    final rules = <FirewallRule>[];
    final ruleRe = RegExp(
      r'^\[\s*(\d+)\]\s+(.+?)\s{2,}(ALLOW|DENY|REJECT|LIMIT)(?:\s+(IN|OUT|FWD))?\s+(.+?)$',
    );
    for (final raw in output.split('\n')) {
      final line = raw.trim();
      final m = ruleRe.firstMatch(line);
      if (m == null) continue;
      final number = int.tryParse(m.group(1)!) ?? 0;
      final to = m.group(2)!.trim();
      final action = m.group(3)!.trim();
      final direction = (m.group(4) ?? 'IN').trim();
      var fromRaw = m.group(5)!.trim();
      String? comment;
      final hashIdx = fromRaw.indexOf(' # ');
      if (hashIdx != -1) {
        comment = fromRaw.substring(hashIdx + 3).trim();
        fromRaw = fromRaw.substring(0, hashIdx).trim();
      }
      final isV6 = to.contains('(v6)') || fromRaw.contains('(v6)');
      rules.add(
        FirewallRule(
          number: number,
          to: to,
          action: action,
          direction: direction,
          from: fromRaw,
          isV6: isV6,
          comment: comment,
        ),
      );
    }
    return rules;
  }

  /// Builds UFW rule arguments cleanly for validation and execution.
  static List<String> buildAddRuleArgs({
    required String action,
    required String portOrService,
    String protocol = 'any',
    String direction = 'in',
    String? fromAddress,
    String? comment,
  }) {
    final args = <String>['ufw', action.toLowerCase()];
    if (direction.toLowerCase() == 'out') {
      args.add('out');
    }
    final from = fromAddress?.trim() ?? '';
    if (from.isNotEmpty && from.toLowerCase() != 'any') {
      args.addAll(['from', from, 'to', 'any']);
    }
    final portClean = portOrService.trim();
    if (portClean.isNotEmpty) {
      if (from.isNotEmpty && from.toLowerCase() != 'any') {
        args.addAll(['port', portClean]);
      } else if (protocol != 'any' && !portClean.contains('/')) {
        args.add('$portClean/$protocol');
      } else {
        args.add(portClean);
      }
    }
    if (from.isNotEmpty &&
        from.toLowerCase() != 'any' &&
        protocol != 'any' &&
        portClean.isNotEmpty &&
        !portClean.contains('/')) {
      args.addAll(['proto', protocol]);
    }
    if (comment != null && comment.trim().isNotEmpty) {
      args.addAll(['comment', comment.trim()]);
    }
    return args;
  }

  /// Reads non-privileged UFW metadata from `/etc/ufw/ufw.conf` and systemd.
  static Future<FirewallSnapshot> loadUnprivilegedStatus() async {
    final hasUfw = await _hasBinary('ufw');
    final hasFirewalld = await _hasBinary('firewall-cmd');
    bool active = false;
    bool enabledBoot = false;

    if (hasUfw) {
      try {
        final conf = File('/etc/ufw/ufw.conf');
        if (await conf.exists()) {
          final text = await conf.readAsString();
          active = RegExp(r'^ENABLED=yes\b', multiLine: true).hasMatch(text);
        }
      } catch (_) {}
      try {
        final sysRes = await Process.run('systemctl', ['is-enabled', 'ufw']);
        enabledBoot = sysRes.exitCode == 0 &&
            sysRes.stdout.toString().trim() == 'enabled';
      } catch (_) {}
    }

    return FirewallSnapshot(
      hasUfw: hasUfw,
      hasFirewalld: hasFirewalld,
      isActive: active,
      enabledAtBoot: enabledBoot,
      rulesLoaded: false,
    );
  }
}
