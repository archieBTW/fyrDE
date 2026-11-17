import 'dart:async';

import 'package:flutter/material.dart';
import '../fyr_theme.dart';

/// Settings pane for checking, notifying, scheduling, and installing system
/// updates across pacman/yay, Flatpak, and Snap.
class UpdatesPane extends StatefulWidget {
  final bool autoCheckOnInit;
  final UpdateCheckResult? initialResult;

  const UpdatesPane({
    super.key,
    this.autoCheckOnInit = true,
    this.initialResult,
  });

  @override
  State<UpdatesPane> createState() => _UpdatesPaneState();
}

class _UpdatesPaneState extends State<UpdatesPane> {
  UpdatesConfig _config = const UpdatesConfig();
  UpdateCheckResult? _result;
  bool _checking = false;
  bool _installing = false;
  bool _hasPasswordlessSudo = false;
  final List<String> _logs = [];
  final ScrollController _logScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _result = widget.initialResult;
    _initStateAsync();
  }

  @override
  void dispose() {
    _logScroll.dispose();
    super.dispose();
  }

  Future<void> _initStateAsync() async {
    final cfg = await UpdateService.loadConfig();
    final sudoOk = await UpdateService.hasPasswordlessSudo();
    if (!mounted) return;
    setState(() {
      _config = cfg;
      _hasPasswordlessSudo = sudoOk;
    });
    if (widget.autoCheckOnInit) {
      await _checkNow();
    }
  }

  Future<void> _saveConfig(UpdatesConfig next) async {
    setState(() => _config = next);
    await UpdateService.saveConfig(next);
  }

  Future<void> _checkNow() async {
    if (_checking || _installing) return;
    setState(() => _checking = true);
    try {
      final res = await UpdateService.checkAllUpdates(_config);
      final sudoOk = await UpdateService.hasPasswordlessSudo();
      final nextCfg = _config.copyWith(
        lastCheckedAt: res.checkedAt,
        clearLastError: res.errors.isEmpty,
        lastError: res.errors.isNotEmpty ? res.errors.join('; ') : null,
      );
      await UpdateService.saveConfig(nextCfg);
      if (!mounted) return;
      setState(() {
        _result = res;
        _config = nextCfg;
        _hasPasswordlessSudo = sudoOk;
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<String?> _promptSudoPassword() async {
    final controller = TextEditingController();
    bool obscure = true;
    final submitted = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: FyrTheme.panelBgColor,
          title: Text(
            'Administrator Authentication',
            style: TextStyle(color: FyrTheme.textColor),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter your sudo password to install pacman/yay or Snap updates.',
                style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: obscure,
                autofocus: true,
                style: TextStyle(color: FyrTheme.textColor),
                onSubmitted: (val) => Navigator.pop(ctx, val),
                decoration: InputDecoration(
                  hintText: 'Password',
                  hintStyle: TextStyle(color: FyrTheme.textColorMuted),
                  filled: true,
                  fillColor: FyrTheme.cardColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure ? Icons.visibility : Icons.visibility_off,
                      color: FyrTheme.textColorMuted,
                    ),
                    onPressed: () =>
                        setDialogState(() => obscure = !obscure),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: FyrTheme.accentColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Authenticate'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return submitted;
  }

  void _appendLog(String line) {
    if (!mounted) return;
    setState(() => _logs.add(line));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _installAll() async {
    if (_installing || _checking) return;
    final updates = _result?.updates ?? const [];
    final needsRoot = updates.any((u) => u.requiresRoot);
    String? password;

    if (needsRoot && !_hasPasswordlessSudo) {
      password = await _promptSudoPassword();
      if (password == null || password.isEmpty) return;
    }

    setState(() {
      _installing = true;
      _logs.clear();
    });

    try {
      final res = await UpdateService.installUpdates(
        config: _config,
        backends: _result?.backends,
        sudoPassword: password,
        onLog: _appendLog,
      );

      final nextCfg = _config.copyWith(
        lastUpdatedAt: res.success ? DateTime.now() : null,
        clearLastError: res.success,
        lastError: res.errors.isNotEmpty ? res.errors.join('; ') : null,
      );
      await UpdateService.saveConfig(nextCfg);
      if (!mounted) return;
      setState(() => _config = nextCfg);

      if (res.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('All updates installed successfully.'),
            backgroundColor: FyrTheme.accentColor,
          ),
        );
      } else if (res.errors.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.errors.join(' | ')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _installing = false);
    }

    await _checkNow();
  }

  String _formatTimestamp(DateTime? dt) {
    if (dt == null) return 'Never';
    final local = dt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $hh:$mm';
  }

  Color _sourceColor(UpdateSource source) {
    switch (source) {
      case UpdateSource.pacman:
        return const Color(0xFF1793D1);
      case UpdateSource.aur:
        return FyrTheme.accentColor;
      case UpdateSource.flatpak:
        return const Color(0xFF4A86CF);
      case UpdateSource.snap:
        return const Color(0xFF82BEA0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final updates = _result?.updates ?? const [];
    final backends = _result?.backends;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'System Updates',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: FyrTheme.textColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _checking
                        ? 'Checking repositories, AUR, Flatpak, and Snap...'
                        : updates.isEmpty
                            ? 'Up to date • Last checked: ${_formatTimestamp(_config.lastCheckedAt)}'
                            : '${updates.length} update${updates.length == 1 ? '' : 's'} available • Last checked: ${_formatTimestamp(_config.lastCheckedAt)}',
                    style: TextStyle(
                      color: FyrTheme.textColorMuted,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: (_checking || _installing) ? null : _checkNow,
                    icon: _checking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    label: const Text('Check Now'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: FyrTheme.textColor,
                      side: BorderSide(color: FyrTheme.dividerColor),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: (_checking || _installing || updates.isEmpty)
                        ? null
                        : _installAll,
                    icon: _installing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.system_update_alt, size: 18),
                    label: Text(_installing ? 'Updating...' : 'Update All'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: FyrTheme.accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Automation & Notification Settings
          Text(
            'Notifications & Auto-Updates',
            style: TextStyle(
              color: FyrTheme.textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: FyrTheme.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: FyrTheme.isDark
                  ? BorderSide.none
                  : BorderSide(color: FyrTheme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: FyrTheme.accentColor,
                    title: Text(
                      'Update Notifications',
                      style: TextStyle(
                        color: FyrTheme.textColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      'Notify when pacman, AUR, Flatpak, or Snap updates are found',
                      style: TextStyle(
                        color: FyrTheme.textColorMuted,
                        fontSize: 13,
                      ),
                    ),
                    value: _config.notificationsEnabled,
                    onChanged: (val) => _saveConfig(
                      _config.copyWith(notificationsEnabled: val),
                    ),
                  ),
                  Divider(color: FyrTheme.dividerColor, height: 24),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: FyrTheme.accentColor,
                    title: Text(
                      'Automatic Background Updates',
                      style: TextStyle(
                        color: FyrTheme.textColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      _hasPasswordlessSudo
                          ? 'Automatically runs yay, pacman, Flatpak, and Snap updates on schedule'
                          : 'Flatpaks update automatically; pacman/yay & Snap prompt if sudo requires a password',
                      style: TextStyle(
                        color: FyrTheme.textColorMuted,
                        fontSize: 13,
                      ),
                    ),
                    value: _config.autoUpdateEnabled,
                    onChanged: (val) => _saveConfig(
                      _config.copyWith(autoUpdateEnabled: val),
                    ),
                  ),
                  Divider(color: FyrTheme.dividerColor, height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Check Frequency',
                        style: TextStyle(
                          color: FyrTheme.textColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      DropdownButton<int>(
                        value: _config.checkIntervalHours,
                        dropdownColor: FyrTheme.cardColor,
                        style: TextStyle(color: FyrTheme.textColor, fontSize: 15),
                        underline: const SizedBox.shrink(),
                        icon: Icon(
                          Icons.arrow_drop_down,
                          color: FyrTheme.accentColor,
                        ),
                        items: const [1, 3, 6, 12, 24]
                            .map(
                              (h) => DropdownMenuItem<int>(
                                value: h,
                                child: Text(h == 1 ? 'Every hour' : 'Every $h hours'),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            _saveConfig(_config.copyWith(checkIntervalHours: val));
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Enabled Sources',
                    style: TextStyle(
                      color: FyrTheme.textColorMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        label: Text(
                          backends == null
                              ? 'Pacman & AUR (yay)'
                              : (backends.hasYay
                                  ? 'Pacman & AUR (yay)'
                                  : backends.hasPacman
                                      ? 'Pacman'
                                      : 'Pacman / yay (not found)'),
                        ),
                        selected: _config.includePacmanAur,
                        selectedColor:
                            FyrTheme.accentColor.withValues(alpha: 0.25),
                        checkmarkColor: FyrTheme.accentColor,
                        onSelected: (val) => _saveConfig(
                          _config.copyWith(includePacmanAur: val),
                        ),
                      ),
                      FilterChip(
                        label: Text(
                          backends == null || backends.hasFlatpak
                              ? 'Flatpak'
                              : 'Flatpak (not installed)',
                        ),
                        selected: _config.includeFlatpak,
                        selectedColor:
                            FyrTheme.accentColor.withValues(alpha: 0.25),
                        checkmarkColor: FyrTheme.accentColor,
                        onSelected: (val) => _saveConfig(
                          _config.copyWith(includeFlatpak: val),
                        ),
                      ),
                      FilterChip(
                        label: Text(
                          backends == null || backends.hasSnap
                              ? 'Snap'
                              : 'Snap (not installed)',
                        ),
                        selected: _config.includeSnap,
                        selectedColor:
                            FyrTheme.accentColor.withValues(alpha: 0.25),
                        checkmarkColor: FyrTheme.accentColor,
                        onSelected: (val) => _saveConfig(
                          _config.copyWith(includeSnap: val),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Available Updates (${updates.length})',
                style: TextStyle(
                  color: FyrTheme.textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_config.lastUpdatedAt != null)
                Text(
                  'Last updated: ${_formatTimestamp(_config.lastUpdatedAt)}',
                  style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 13),
                ),
            ],
          ),
          const SizedBox(height: 12),

          Card(
            color: FyrTheme.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: FyrTheme.isDark
                  ? BorderSide.none
                  : BorderSide(color: FyrTheme.dividerColor),
            ),
            child: updates.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 32,
                      horizontal: 24,
                    ),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 40,
                            color: FyrTheme.accentColor,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _checking
                                ? 'Checking for updates...'
                                : 'Your system and apps are up to date.',
                            style: TextStyle(
                              color: FyrTheme.textColor,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: updates.length,
                    separatorBuilder: (_, __) =>
                        Divider(color: FyrTheme.dividerColor, height: 1),
                    itemBuilder: (context, index) {
                      final u = updates[index];
                      final badgeColor = _sourceColor(u.source);
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 4,
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                u.name,
                                style: TextStyle(
                                  color: FyrTheme.textColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: badgeColor.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: badgeColor.withValues(alpha: 0.45),
                                ),
                              ),
                              child: Text(
                                u.source.label,
                                style: TextStyle(
                                  color: badgeColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          '${u.currentVersion} → ${u.newVersion}',
                          style: TextStyle(
                            color: FyrTheme.textColorMuted,
                            fontSize: 13,
                          ),
                        ),
                      );
                    },
                  ),
          ),

          if (_logs.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Update Output Log',
              style: TextStyle(
                color: FyrTheme.textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 200,
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: FyrTheme.dividerColor),
              ),
              child: ListView.builder(
                controller: _logScroll,
                itemCount: _logs.length,
                itemBuilder: (_, i) => Text(
                  _logs[i],
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
