import 'dart:io';

/// Represents a local interactive user account parsed from `/etc/passwd` & `/etc/group`.
class SystemUserAccount {
  final String username;
  final String fullName;
  final int uid;
  final int gid;
  final String homeDir;
  final String shell;
  final bool isAdmin;
  final bool isCurrent;
  final List<String> groups;

  const SystemUserAccount({
    required this.username,
    required this.fullName,
    required this.uid,
    required this.gid,
    required this.homeDir,
    required this.shell,
    required this.isAdmin,
    required this.isCurrent,
    required this.groups,
  });

  String get displayName => fullName.isNotEmpty ? fullName : username;
}

/// Pure parsing & helper utilities for Linux user account management.
class UsersService {
  static const List<String> adminGroupNames = ['wheel', 'sudo'];

  static bool isValidUsername(String username) {
    return RegExp(r'^[a-z_][a-z0-9_-]{0,31}$').hasMatch(username);
  }

  /// Parses `/etc/passwd` and `/etc/group` contents into sorted human user accounts.
  static List<SystemUserAccount> parsePasswdAndGroup(
    String passwdContent,
    String groupContent, {
    String? currentUser,
  }) {
    final activeUser = currentUser ?? Platform.environment['USER'] ?? '';

    final userGroups = <String, Set<String>>{};
    final groupGids = <int, String>{};
    for (final rawLine in groupContent.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split(':');
      if (parts.length < 4) continue;
      final groupName = parts[0].trim();
      final gid = int.tryParse(parts[2].trim());
      if (gid != null) groupGids[gid] = groupName;
      final members = parts[3]
          .split(',')
          .map((m) => m.trim())
          .where((m) => m.isNotEmpty);
      for (final member in members) {
        userGroups.putIfAbsent(member, () => <String>{}).add(groupName);
      }
    }

    final accounts = <SystemUserAccount>[];
    for (final rawLine in passwdContent.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split(':');
      if (parts.length < 7) continue;

      final username = parts[0].trim();
      final uid = int.tryParse(parts[2].trim()) ?? -1;
      final gid = int.tryParse(parts[3].trim()) ?? -1;
      final gecos = parts[4].trim();
      final homeDir = parts[5].trim();
      final shell = parts[6].trim();

      // Standard Linux human user UID range (exclude nobody/nfsnobody/nologin)
      if (uid < 1000 || uid >= 65534) continue;
      if (shell.endsWith('/nologin') || shell.endsWith('/false')) continue;

      final fullName = gecos.split(',').first.trim();
      final groupsSet = <String>{...?userGroups[username]};
      final primaryGroup = groupGids[gid];
      if (primaryGroup != null && primaryGroup.isNotEmpty) {
        groupsSet.add(primaryGroup);
      }
      final sortedGroups = groupsSet.toList()..sort();
      final isAdmin = sortedGroups.any((g) => adminGroupNames.contains(g));

      accounts.add(
        SystemUserAccount(
          username: username,
          fullName: fullName,
          uid: uid,
          gid: gid,
          homeDir: homeDir,
          shell: shell,
          isAdmin: isAdmin,
          isCurrent: username == activeUser,
          groups: sortedGroups,
        ),
      );
    }

    accounts.sort((a, b) {
      if (a.isCurrent != b.isCurrent) return a.isCurrent ? -1 : 1;
      return a.username.compareTo(b.username);
    });
    return accounts;
  }

  /// Detects available login shells from `/etc/shells` with sensible defaults.
  static Future<List<String>> detectAvailableShells() async {
    const defaults = ['/bin/bash', '/bin/zsh', '/usr/bin/fish', '/bin/sh'];
    try {
      final file = File('/etc/shells');
      if (await file.exists()) {
        final shells = (await file.readAsString())
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty && !l.startsWith('#'))
            .where((l) => !l.endsWith('nologin') && !l.endsWith('git-shell'))
            .toSet()
            .toList();
        if (shells.isNotEmpty) return shells;
      }
    } catch (_) {}
    return defaults.where((s) => File(s).existsSync()).toList();
  }

  /// Picks the host's primary administrator group (`wheel` on Arch, `sudo` on Debian/Ubuntu).
  static Future<String> detectAdminGroup() async {
    try {
      final groupText = await File('/etc/group').readAsString();
      for (final candidate in adminGroupNames) {
        if (RegExp('^$candidate:', multiLine: true).hasMatch(groupText)) {
          return candidate;
        }
      }
    } catch (_) {}
    return 'wheel';
  }

  static Future<List<SystemUserAccount>> loadLocalUsers() async {
    final passwdText = await File('/etc/passwd').readAsString();
    final groupText = await File('/etc/group').readAsString();
    return parsePasswdAndGroup(passwdText, groupText);
  }
}
