import 'dart:io';

import 'package:flutter/material.dart';
import '../fyr_theme.dart';
import '../services/admin_auth.dart';
import '../services/users_service.dart';

/// Settings pane for viewing, creating, modifying, and removing local Linux
/// user accounts (backed by `useradd`, `usermod`, `userdel`, and `chpasswd`).
class UsersPane extends StatefulWidget {
  final List<SystemUserAccount>? initialUsers;
  final bool autoLoadOnInit;

  const UsersPane({
    super.key,
    this.initialUsers,
    this.autoLoadOnInit = true,
  });

  @override
  State<UsersPane> createState() => _UsersPaneState();
}

class _UsersPaneState extends State<UsersPane> {
  List<SystemUserAccount> _users = [];
  List<String> _availableShells = ['/bin/bash'];
  String _adminGroup = 'wheel';
  bool _loading = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialUsers != null) {
      _users = widget.initialUsers!;
    }
    if (widget.autoLoadOnInit) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        UsersService.loadLocalUsers(),
        UsersService.detectAvailableShells(),
        UsersService.detectAdminGroup(),
      ]);
      if (!mounted) return;
      setState(() {
        _users = results[0] as List<SystemUserAccount>;
        final shells = results[1] as List<String>;
        if (shells.isNotEmpty) _availableShells = shells;
        _adminGroup = results[2] as String;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to read system users: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _runUserAdmin(
    List<String> command, {
    String? stdinData,
    required String promptMessage,
  }) async {
    setState(() => _busy = true);
    File? askpassFile;
    try {
      final auth = await AdminAuth.acquireSudoAskpass(
        context,
        title: 'Administrator Authentication',
        message: promptMessage,
      );
      if (auth.cancelled) return false;
      if (auth.error != null) {
        _showError(auth.error!);
        return false;
      }
      askpassFile = auth.askpassFile;
      final res = await AdminAuth.runWithSudo(
        command: command,
        askpassFile: askpassFile,
        stdinData: stdinData,
      );
      if (!res.ok) {
        final msg = res.stderr.trim().isNotEmpty
            ? res.stderr.trim()
            : 'Command failed with exit code ${res.exitCode}';
        _showError(msg);
        return false;
      }
      return true;
    } finally {
      try {
        if (askpassFile != null && askpassFile.parent.existsSync()) {
          askpassFile.parent.deleteSync(recursive: true);
        }
      } catch (_) {}
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: FyrTheme.accentColor),
    );
  }

  Future<void> _showAddUserDialog() async {
    final result = await showDialog<_AddUserDialogResult>(
      context: context,
      builder: (_) => _AddUserDialog(
        availableShells: _availableShells,
        adminGroup: _adminGroup,
        existingUsernames: _users.map((u) => u.username).toSet(),
      ),
    );
    if (result == null || !mounted) return;

    final args = <String>[
      'useradd',
      '-m',
      '-s',
      result.shell,
      if (result.fullName.isNotEmpty) ...['-c', result.fullName],
      if (result.isAdmin) ...['-G', _adminGroup],
      result.username,
    ];

    setState(() => _busy = true);
    File? askpassFile;
    try {
      final auth = await AdminAuth.acquireSudoAskpass(
        context,
        title: 'Create User Account',
        message: 'Enter your sudo password to create "${result.username}".',
      );
      if (auth.cancelled) return;
      if (auth.error != null) {
        _showError(auth.error!);
        return;
      }
      askpassFile = auth.askpassFile;
      final addRes = await AdminAuth.runWithSudo(command: args, askpassFile: askpassFile);
      if (!addRes.ok) {
        _showError(addRes.stderr.trim().isNotEmpty ? addRes.stderr.trim() : 'Failed to create user.');
        return;
      }
      final passRes = await AdminAuth.runWithSudo(
        command: ['chpasswd'],
        askpassFile: askpassFile,
        stdinData: '${result.username}:${result.password}\n',
      );
      if (!passRes.ok) {
        _showError('User created, but setting password failed: ${passRes.stderr.trim()}');
      } else {
        _showSuccess('Created user "${result.username}".');
      }
    } finally {
      try {
        if (askpassFile != null && askpassFile.parent.existsSync()) {
          askpassFile.parent.deleteSync(recursive: true);
        }
      } catch (_) {}
      if (mounted) setState(() => _busy = false);
    }
    await _loadData();
  }

  Future<void> _changePassword(SystemUserAccount user) async {
    final newPass = await showDialog<String>(
      context: context,
      builder: (_) => _ChangePasswordDialog(username: user.username),
    );
    if (newPass == null || !mounted) return;

    final updated = await _runUserAdmin(
      ['chpasswd'],
      stdinData: '${user.username}:$newPass\n',
      promptMessage: 'Enter your sudo password to update the password for "${user.username}".',
    );
    if (updated) _showSuccess('Updated password for "${user.username}".');
  }

  Future<void> _editFullName(SystemUserAccount user) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => _EditFullNameDialog(username: user.username, initialFullName: user.fullName),
    );
    if (newName == null || !mounted) return;

    final ok = await _runUserAdmin(
      ['usermod', '-c', newName, user.username],
      promptMessage: 'Enter your sudo password to rename "${user.username}".',
    );
    if (ok) {
      _showSuccess('Updated display name.');
      await _loadData();
    }
  }

  Future<void> _toggleAdminRole(SystemUserAccount user) async {
    if (user.isAdmin && _users.where((u) => u.isAdmin).length <= 1) {
      _showError('Cannot remove administrator role from the only admin account.');
      return;
    }
    final cmd = user.isAdmin
        ? ['gpasswd', '-d', user.username, _adminGroup]
        : ['usermod', '-aG', _adminGroup, user.username];
    final ok = await _runUserAdmin(
      cmd,
      promptMessage: 'Enter your sudo password to change account privileges for "${user.username}".',
    );
    if (ok) {
      _showSuccess(user.isAdmin
          ? 'Changed "${user.username}" to Standard user.'
          : 'Granted Administrator role to "${user.username}".');
      await _loadData();
    }
  }

  Future<void> _deleteUser(SystemUserAccount user) async {
    if (user.isCurrent) {
      _showError('Cannot delete the currently logged-in account.');
      return;
    }
    bool removeHome = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: FyrTheme.panelBgColor,
          title: Text('Delete User "${user.username}"?', style: TextStyle(color: FyrTheme.textColor)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This permanently removes the account "${user.username}" from the system.',
                style: TextStyle(color: FyrTheme.textColorMuted),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: Colors.redAccent,
                value: removeHome,
                onChanged: (v) => setDlgState(() => removeHome = v ?? false),
                title: Text(
                  'Also delete home directory (${user.homeDir})',
                  style: TextStyle(color: FyrTheme.textColor, fontSize: 13),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete User'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final cmd = ['userdel', if (removeHome) '-r', user.username];
    final ok = await _runUserAdmin(
      cmd,
      promptMessage: 'Enter your sudo password to delete "${user.username}".',
    );
    if (ok) {
      _showSuccess('Deleted user "${user.username}".');
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'User Accounts',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: FyrTheme.textColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Manage local accounts, passwords, shells, and administrator privileges',
                      style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: (_loading || _busy) ? null : _loadData,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Refresh'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: FyrTheme.textColor,
                      side: BorderSide(color: FyrTheme.dividerColor),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _busy ? null : _showAddUserDialog,
                    icon: const Icon(Icons.person_add, size: 18),
                    label: const Text('Add User'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: FyrTheme.accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
          else if (_users.isEmpty)
            Card(
              color: FyrTheme.cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text('No local user accounts found.', style: TextStyle(color: FyrTheme.textColorMuted)),
                ),
              ),
            )
          else
            ..._users.map((user) {
              final initials = user.displayName.isNotEmpty
                  ? user.displayName.substring(0, 1).toUpperCase()
                  : '?';
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Card(
                  color: FyrTheme.cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: FyrTheme.isDark
                        ? BorderSide.none
                        : BorderSide(color: FyrTheme.dividerColor),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: FyrTheme.accentColor.withValues(alpha: 0.2),
                          child: Text(
                            initials,
                            style: TextStyle(
                              color: FyrTheme.accentColor,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    user.displayName,
                                    style: TextStyle(
                                      color: FyrTheme.textColor,
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (user.isCurrent)
                                    _badge('Current', FyrTheme.accentColor),
                                  _badge(
                                    user.isAdmin ? 'Administrator' : 'Standard',
                                    user.isAdmin ? Colors.amber : Colors.blueGrey,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '@${user.username} • UID ${user.uid} • ${user.homeDir} • ${user.shell}',
                                style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: _busy ? null : () => _changePassword(user),
                              child: const Text('Password'),
                            ),
                            OutlinedButton(
                              onPressed: _busy ? null : () => _editFullName(user),
                              child: const Text('Rename'),
                            ),
                            OutlinedButton(
                              onPressed: _busy ? null : () => _toggleAdminRole(user),
                              child: Text(user.isAdmin ? 'Make Standard' : 'Make Admin'),
                            ),
                            if (!user.isCurrent)
                              IconButton(
                                tooltip: 'Delete user',
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                onPressed: _busy ? null : () => _deleteUser(user),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

InputDecoration _userInputDecoration(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: FyrTheme.textColorMuted),
      filled: true,
      fillColor: FyrTheme.cardColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
    );

class _AddUserDialogResult {
  const _AddUserDialogResult({
    required this.username,
    required this.fullName,
    required this.password,
    required this.shell,
    required this.isAdmin,
  });

  final String username;
  final String fullName;
  final String password;
  final String shell;
  final bool isAdmin;
}

class _AddUserDialog extends StatefulWidget {
  const _AddUserDialog({
    required this.availableShells,
    required this.adminGroup,
    required this.existingUsernames,
  });

  final List<String> availableShells;
  final String adminGroup;
  final Set<String> existingUsernames;

  @override
  State<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<_AddUserDialog> {
  final _usernameCtrl = TextEditingController();
  final _fullNameCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  late String _selectedShell;
  bool _isAdmin = false;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _selectedShell = widget.availableShells.first;
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _fullNameCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: FyrTheme.panelBgColor,
      title: Text('Add User Account', style: TextStyle(color: FyrTheme.textColor)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _usernameCtrl,
                autofocus: true,
                style: TextStyle(color: FyrTheme.textColor),
                decoration: _userInputDecoration('Username (e.g. alice)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _fullNameCtrl,
                style: TextStyle(color: FyrTheme.textColor),
                decoration: _userInputDecoration('Full Name (optional)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passCtrl,
                obscureText: true,
                style: TextStyle(color: FyrTheme.textColor),
                decoration: _userInputDecoration('Password'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmCtrl,
                obscureText: true,
                style: TextStyle(color: FyrTheme.textColor),
                decoration: _userInputDecoration('Confirm Password'),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Login Shell', style: TextStyle(color: FyrTheme.textColorMuted)),
                  DropdownButton<String>(
                    value: _selectedShell,
                    dropdownColor: FyrTheme.cardColor,
                    style: TextStyle(color: FyrTheme.textColor),
                    underline: const SizedBox.shrink(),
                    items: widget.availableShells
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedShell = val);
                    },
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: FyrTheme.accentColor,
                title: Text('Administrator', style: TextStyle(color: FyrTheme.textColor)),
                subtitle: Text(
                  'Member of ${widget.adminGroup} group (can run sudo)',
                  style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12),
                ),
                value: _isAdmin,
                onChanged: (v) => setState(() => _isAdmin = v),
              ),
              if (_validationError != null) ...[
                const SizedBox(height: 8),
                Text(_validationError!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: FyrTheme.accentColor, foregroundColor: Colors.white),
          onPressed: () {
            final u = _usernameCtrl.text.trim();
            if (!UsersService.isValidUsername(u)) {
              setState(() => _validationError = 'Use lowercase letters, digits, _ or - (must start with a letter or _).');
              return;
            }
            if (widget.existingUsernames.contains(u)) {
              setState(() => _validationError = 'User "$u" already exists.');
              return;
            }
            if (_passCtrl.text.isEmpty || _passCtrl.text != _confirmCtrl.text) {
              setState(() => _validationError = 'Passwords must match and not be empty.');
              return;
            }
            Navigator.pop(
              context,
              _AddUserDialogResult(
                username: u,
                fullName: _fullNameCtrl.text.trim(),
                password: _passCtrl.text,
                shell: _selectedShell,
                isAdmin: _isAdmin,
              ),
            );
          },
          child: const Text('Create User'),
        ),
      ],
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.username});

  final String username;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _err;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: FyrTheme.panelBgColor,
      title: Text('Change Password (${widget.username})', style: TextStyle(color: FyrTheme.textColor)),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _passCtrl,
              obscureText: true,
              autofocus: true,
              style: TextStyle(color: FyrTheme.textColor),
              decoration: _userInputDecoration('New Password'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmCtrl,
              obscureText: true,
              style: TextStyle(color: FyrTheme.textColor),
              decoration: _userInputDecoration('Confirm New Password'),
            ),
            if (_err != null) ...[
              const SizedBox(height: 8),
              Text(_err!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: FyrTheme.accentColor, foregroundColor: Colors.white),
          onPressed: () {
            if (_passCtrl.text.isEmpty || _passCtrl.text != _confirmCtrl.text) {
              setState(() => _err = 'Passwords must match and not be empty.');
              return;
            }
            Navigator.pop(context, _passCtrl.text);
          },
          child: const Text('Save Password'),
        ),
      ],
    );
  }
}

class _EditFullNameDialog extends StatefulWidget {
  const _EditFullNameDialog({
    required this.username,
    required this.initialFullName,
  });

  final String username;
  final String initialFullName;

  @override
  State<_EditFullNameDialog> createState() => _EditFullNameDialogState();
}

class _EditFullNameDialogState extends State<_EditFullNameDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialFullName);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: FyrTheme.panelBgColor,
      title: Text('Edit Full Name (${widget.username})', style: TextStyle(color: FyrTheme.textColor)),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        style: TextStyle(color: FyrTheme.textColor),
        decoration: _userInputDecoration('Display Name'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: FyrTheme.accentColor, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
