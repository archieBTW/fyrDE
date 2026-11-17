import 'dart:io';

import 'package:flutter/material.dart';
import '../fyr_theme.dart';
import '../services/backup_service.dart';

class BackupPane extends StatefulWidget {
  const BackupPane({
    super.key,
    this.autoLoad = true,
    this.initialConfig,
    this.initialItems,
    this.initialBackups,
    this.initialMountedDrives,
    this.initialEstimatedBytes,
  });

  final bool autoLoad;
  final BackupSettingsConfig? initialConfig;
  final List<BackupDiscoveredItem>? initialItems;
  final List<BackupArchiveEntry>? initialBackups;
  final List<String>? initialMountedDrives;
  final int? initialEstimatedBytes;

  @override
  State<BackupPane> createState() => _BackupPaneState();
}

class _BackupPaneState extends State<BackupPane> {
  late BackupSelection _selection;
  late TextEditingController _destCtrl;
  List<BackupDiscoveredItem> _discoveredItems = [];
  List<BackupArchiveEntry> _existingBackups = [];
  List<String> _mountedDrives = [];
  int _estimatedBytes = 0;
  DateTime? _lastBackupAt;
  String? _lastBackupPath;

  bool _encryptBackup = false;
  final _passCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool _obscurePass = true;

  bool _loading = false;
  bool _running = false;
  bool _showDetails = false;

  @override
  void initState() {
    super.initState();
    _selection = widget.initialConfig?.selection ?? const BackupSelection();
    _destCtrl = TextEditingController(
      text: widget.initialConfig?.destinationDir ?? BackupService.defaultDestinationDir(),
    );
    _lastBackupAt = widget.initialConfig?.lastBackupAt;
    _lastBackupPath = widget.initialConfig?.lastBackupPath;
    _discoveredItems = widget.initialItems ?? [];
    _existingBackups = widget.initialBackups ?? [];
    _mountedDrives = widget.initialMountedDrives ?? [];
    _estimatedBytes = widget.initialEstimatedBytes ?? 0;

    if (widget.autoLoad) {
      _loadAll();
    }
  }

  @override
  void dispose() {
    _destCtrl.dispose();
    _passCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final cfg = await BackupService.loadConfig();
    if (!mounted) return;
    _destCtrl.text = cfg.destinationDir;
    _selection = cfg.selection;
    _lastBackupAt = cfg.lastBackupAt;
    _lastBackupPath = cfg.lastBackupPath;
    await _recalculatePreview();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _recalculatePreview() async {
    final dest = _destCtrl.text.trim();
    if (!widget.autoLoad) {
      setState(() {
        _existingBackups = dest.isNotEmpty
            ? BackupService.listBackupsInDirectory(dest)
            : const <BackupArchiveEntry>[];
      });
      return;
    }
    final items = BackupService.discoverPaths(_selection);
    final drives = BackupService.listMountedExternalDestinations();
    final backups = dest.isNotEmpty
        ? BackupService.listBackupsInDirectory(dest)
        : const <BackupArchiveEntry>[];
    final size = await BackupService.estimateSizeBytes(_selection, destinationDir: dest);
    if (!mounted) return;
    setState(() {
      _discoveredItems = items;
      _mountedDrives = drives;
      _existingBackups = backups;
      _estimatedBytes = size;
    });
  }

  Future<void> _saveSelection(BackupSelection next) async {
    setState(() => _selection = next);
    await BackupService.saveConfig(BackupSettingsConfig(
      destinationDir: _destCtrl.text.trim(),
      selection: next,
      lastBackupAt: _lastBackupAt,
      lastBackupPath: _lastBackupPath,
    ));
    await _recalculatePreview();
  }

  Future<void> _pickDestinationFolder() async {
    try {
      final res = await Process.run('zenity', [
        '--file-selection',
        '--directory',
        '--title=Select Backup Destination Folder',
      ]);
      if (res.exitCode == 0) {
        final chosen = res.stdout.toString().trim();
        if (chosen.isNotEmpty && mounted) {
          _destCtrl.text = chosen;
          await _recalculatePreview();
        }
      }
    } catch (e) {
      _showSnack('Could not open folder picker: $e', isError: true);
    }
  }

  Future<void> _pickExternalArchiveToRestore() async {
    try {
      final res = await Process.run('zenity', [
        '--file-selection',
        '--title=Select Fyr Backup Archive (.tar.gz / .gpg)',
      ]);
      if (res.exitCode == 0) {
        final chosen = res.stdout.toString().trim();
        if (chosen.isNotEmpty && mounted) {
          await _promptRestoreArchive(chosen);
        }
      }
    } catch (e) {
      _showSnack('Could not open archive picker: $e', isError: true);
    }
  }

  Future<void> _runBackupNow() async {
    final dest = _destCtrl.text.trim();
    if (dest.isEmpty) {
      _showSnack('Choose a backup destination folder.', isError: true);
      return;
    }
    if (!_selection.hasAnySelection) {
      _showSnack('Select at least one category to back up.', isError: true);
      return;
    }
    if (_encryptBackup) {
      if (_passCtrl.text.isEmpty || _passCtrl.text != _confirmPassCtrl.text) {
        _showSnack('Encryption passphrases must match and not be empty.', isError: true);
        return;
      }
    }

    setState(() => _running = true);
    final res = await BackupService.createBackup(
      selection: _selection,
      destinationDir: dest,
      encryptionPassphrase: _encryptBackup ? _passCtrl.text : null,
    );
    if (!mounted) return;
    if (res.ok) {
      _lastBackupAt = DateTime.now();
      _lastBackupPath = res.archivePath;
    }
    await _recalculatePreview();
    if (!mounted) return;
    setState(() => _running = false);
    _showSnack(res.message, isError: !res.ok);
  }

  Future<void> _promptRestoreArchive(String archivePath) async {
    final isEnc = archivePath.toLowerCase().endsWith('.gpg');
    String? passphrase;
    if (isEnc) {
      passphrase = await showDialog<String>(
        context: context,
        builder: (_) => _RestorePassphraseDialog(archivePath: archivePath),
      );
      if (passphrase == null || !mounted) return;
    }

    setState(() => _running = true);
    final manifest = await BackupService.inspectArchive(archivePath, passphrase: passphrase);
    if (!mounted) return;
    setState(() => _running = false);

    if (manifest == null) {
      _showSnack(
        isEnc ? 'Incorrect passphrase or invalid backup archive.' : 'Could not inspect archive.',
        isError: true,
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FyrTheme.panelBgColor,
        title: Text('Restore Backup to Home?', style: TextStyle(color: FyrTheme.textColor)),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Archive: ${archivePath.split('/').last} (${BackupService.formatBytes(manifest.archiveSizeBytes)})',
                style: TextStyle(color: FyrTheme.textColor, fontWeight: FontWeight.w600),
              ),
              if (manifest.createdAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Created: ${_formatDate(manifest.createdAt!)}',
                  style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 13),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                'Included items (${manifest.includedPaths.length}):',
                style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: manifest.includedPaths
                        .map((p) => Text('• ~/$p', style: TextStyle(color: FyrTheme.textColor, fontSize: 12)))
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Existing matching files in your home folder will be updated from the archive.',
                style: TextStyle(color: Colors.amberAccent, fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: FyrTheme.accentColor, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore Now'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _running = true);
    final res = await BackupService.restoreArchive(
      archivePath: archivePath,
      passphrase: passphrase,
    );
    if (!mounted) return;
    setState(() => _running = false);
    _showSnack(res.message, isError: !res.ok);
  }

  Future<void> _deleteArchive(BackupArchiveEntry entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FyrTheme.panelBgColor,
        title: Text('Delete Backup?', style: TextStyle(color: FyrTheme.textColor)),
        content: Text(
          'Permanently delete ${entry.name} (${BackupService.formatBytes(entry.sizeBytes)})?',
          style: TextStyle(color: FyrTheme.textColorMuted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await File(entry.path).delete();
      await _recalculatePreview();
      _showSnack('Deleted ${entry.name}.');
    } catch (e) {
      _showSnack('Failed to delete: $e', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : FyrTheme.accentColor,
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
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
                      'Backup & Restore',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: FyrTheme.textColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Archive your home folder, Fyr configs, journal entries, file tags, and app data',
                      style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: (_loading || _running) ? null : _pickExternalArchiveToRestore,
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('Restore File...'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: FyrTheme.textColor,
                      side: BorderSide(color: FyrTheme.dividerColor),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: (_loading || _running) ? null : _runBackupNow,
                    icon: _running
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.backup, size: 18),
                    label: Text(_running ? 'Backing Up...' : 'Back Up Now'),
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
          const SizedBox(height: 20),

          // Destination Card
          Card(
            color: FyrTheme.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: FyrTheme.isDark ? BorderSide.none : BorderSide(color: FyrTheme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Backup Destination',
                    style: TextStyle(color: FyrTheme.textColor, fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _destCtrl,
                          onSubmitted: (_) => _recalculatePreview(),
                          style: TextStyle(color: FyrTheme.textColor),
                          decoration: InputDecoration(
                            labelText: 'Destination Folder',
                            labelStyle: TextStyle(color: FyrTheme.textColorMuted),
                            filled: true,
                            fillColor: FyrTheme.surfaceColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _running ? null : _pickDestinationFolder,
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: const Text('Browse...'),
                      ),
                    ],
                  ),
                  if (_mountedDrives.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('External Drives:', style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12)),
                        ..._mountedDrives.map((mp) {
                          final name = mp.split('/').last;
                          return ActionChip(
                            avatar: const Icon(Icons.usb, size: 16),
                            label: Text(name),
                            onPressed: () {
                              _destCtrl.text = '$mp/fyr-backups';
                              _recalculatePreview();
                            },
                          );
                        }),
                      ],
                    ),
                  ],
                  if (_lastBackupAt != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Last backup: ${_formatDate(_lastBackupAt!)}'
                      '${_lastBackupPath != null ? ' • ${_lastBackupPath!.split('/').last}' : ''}',
                      style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // What to Include Card
          Card(
            color: FyrTheme.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: FyrTheme.isDark ? BorderSide.none : BorderSide(color: FyrTheme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'What to Back Up',
                        style: TextStyle(color: FyrTheme.textColor, fontWeight: FontWeight.w600, fontSize: 16),
                      ),
                      Text(
                        'Estimated: ${BackupService.formatBytes(_estimatedBytes)} (${_discoveredItems.length} locations)',
                        style: TextStyle(color: FyrTheme.accentColor, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: FyrTheme.accentColor,
                    title: Text('Fyr Desktop & App Configs', style: TextStyle(color: FyrTheme.textColor)),
                    subtitle: Text(
                      '~/.config/fyr, ~/.config/sway, ~/.config/fyrdock, ~/.config/fyrtaskbar',
                      style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12),
                    ),
                    value: _selection.includeFullHome || _selection.includeFyrConfigs,
                    onChanged: _selection.includeFullHome
                        ? null
                        : (v) => _saveSelection(BackupSelection(
                              includeFyrConfigs: v,
                              includeFyrData: _selection.includeFyrData,
                              includeHomeFolders: _selection.includeHomeFolders,
                              includeFullHome: false,
                            )),
                  ),
                  Divider(color: FyrTheme.dividerColor, height: 1),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: FyrTheme.accentColor,
                    title: Text('Fyr Data, Journal Entries & File Tags', style: TextStyle(color: FyrTheme.textColor)),
                    subtitle: Text(
                      '~/.fyr (tags, pins, S3), ~/Documents/fyrjournal, ~/.local/share/fyr*',
                      style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12),
                    ),
                    value: _selection.includeFullHome || _selection.includeFyrData,
                    onChanged: _selection.includeFullHome
                        ? null
                        : (v) => _saveSelection(BackupSelection(
                              includeFyrConfigs: _selection.includeFyrConfigs,
                              includeFyrData: v,
                              includeHomeFolders: _selection.includeHomeFolders,
                              includeFullHome: false,
                            )),
                  ),
                  Divider(color: FyrTheme.dividerColor, height: 1),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: FyrTheme.accentColor,
                    title: Text('Home User Folders', style: TextStyle(color: FyrTheme.textColor)),
                    subtitle: Text(
                      '~/Desktop, ~/Documents, ~/Downloads, ~/Music, ~/Pictures, ~/Videos',
                      style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12),
                    ),
                    value: _selection.includeFullHome || _selection.includeHomeFolders,
                    onChanged: _selection.includeFullHome
                        ? null
                        : (v) => _saveSelection(BackupSelection(
                              includeFyrConfigs: _selection.includeFyrConfigs,
                              includeFyrData: _selection.includeFyrData,
                              includeHomeFolders: v,
                              includeFullHome: false,
                            )),
                  ),
                  Divider(color: FyrTheme.dividerColor, height: 1),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: FyrTheme.accentColor,
                    title: Text('Entire Home Folder (~)', style: TextStyle(color: FyrTheme.textColor)),
                    subtitle: Text(
                      'Includes all dotfiles, SSH keys, and folders (automatically skips .cache, Trash & mounts)',
                      style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12),
                    ),
                    value: _selection.includeFullHome,
                    onChanged: (v) => _saveSelection(BackupSelection(
                      includeFyrConfigs: _selection.includeFyrConfigs,
                      includeFyrData: _selection.includeFyrData,
                      includeHomeFolders: _selection.includeHomeFolders,
                      includeFullHome: v,
                    )),
                  ),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: () => setState(() => _showDetails = !_showDetails),
                    icon: Icon(_showDetails ? Icons.expand_less : Icons.expand_more, size: 18),
                    label: Text(_showDetails ? 'Hide Included Paths' : 'Preview Included Paths (${_discoveredItems.length})'),
                  ),
                  if (_showDetails)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: FyrTheme.surfaceColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _discoveredItems
                            .map((item) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Text(
                                    '~/${item.relativePath}  —  ${item.description}',
                                    style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Encryption Card
          Card(
            color: FyrTheme.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: FyrTheme.isDark ? BorderSide.none : BorderSide(color: FyrTheme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: FyrTheme.accentColor,
                    title: Text('Encrypt Backup Archive (GPG AES-256)', style: TextStyle(color: FyrTheme.textColor)),
                    subtitle: Text(
                      'Protects your backup with a passphrase (.fyrbackup.tar.gz.gpg)',
                      style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12),
                    ),
                    value: _encryptBackup,
                    onChanged: (v) => setState(() => _encryptBackup = v),
                  ),
                  if (_encryptBackup) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _passCtrl,
                            obscureText: _obscurePass,
                            style: TextStyle(color: FyrTheme.textColor),
                            decoration: InputDecoration(
                              labelText: 'Backup Passphrase',
                              labelStyle: TextStyle(color: FyrTheme.textColorMuted),
                              filled: true,
                              fillColor: FyrTheme.surfaceColor,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePass ? Icons.visibility : Icons.visibility_off,
                                  color: FyrTheme.textColorMuted,
                                ),
                                onPressed: () => setState(() => _obscurePass = !_obscurePass),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _confirmPassCtrl,
                            obscureText: _obscurePass,
                            style: TextStyle(color: FyrTheme.textColor),
                            decoration: InputDecoration(
                              labelText: 'Confirm Passphrase',
                              labelStyle: TextStyle(color: FyrTheme.textColorMuted),
                              filled: true,
                              fillColor: FyrTheme.surfaceColor,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),

          // Recent Backups List
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Available Backups in Destination (${_existingBackups.length})',
                style: TextStyle(color: FyrTheme.textColor, fontSize: 16, fontWeight: FontWeight.w600),
              ),
              IconButton(
                tooltip: 'Refresh list',
                onPressed: _recalculatePreview,
                icon: Icon(Icons.refresh, color: FyrTheme.textColorMuted, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Card(
            color: FyrTheme.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: FyrTheme.isDark ? BorderSide.none : BorderSide(color: FyrTheme.dividerColor),
            ),
            child: _existingBackups.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'No `.fyrbackup` archives found in ${_destCtrl.text.trim()}.',
                        style: TextStyle(color: FyrTheme.textColorMuted),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _existingBackups.length,
                    separatorBuilder: (_, _) => Divider(color: FyrTheme.dividerColor, height: 1),
                    itemBuilder: (_, idx) {
                      final entry = _existingBackups[idx];
                      return ListTile(
                        leading: Icon(
                          entry.isEncrypted ? Icons.lock : Icons.archive_outlined,
                          color: entry.isEncrypted ? Colors.amberAccent : FyrTheme.accentColor,
                        ),
                        title: Text(entry.name, style: TextStyle(color: FyrTheme.textColor, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${_formatDate(entry.modifiedAt)} • ${BackupService.formatBytes(entry.sizeBytes)}'
                          '${entry.isEncrypted ? ' • Encrypted' : ''}',
                          style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12),
                        ),
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: _running ? null : () => _promptRestoreArchive(entry.path),
                              child: const Text('Restore'),
                            ),
                            IconButton(
                              tooltip: 'Delete backup',
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                              onPressed: _running ? null : () => _deleteArchive(entry),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _RestorePassphraseDialog extends StatefulWidget {
  const _RestorePassphraseDialog({required this.archivePath});

  final String archivePath;

  @override
  State<_RestorePassphraseDialog> createState() => _RestorePassphraseDialogState();
}

class _RestorePassphraseDialogState extends State<_RestorePassphraseDialog> {
  final _ctrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: FyrTheme.panelBgColor,
      title: Text('Unlock Encrypted Backup', style: TextStyle(color: FyrTheme.textColor)),
      content: SizedBox(
        width: 390,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the passphrase for ${widget.archivePath.split('/').last}.',
              style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _ctrl,
              obscureText: _obscure,
              autofocus: true,
              onSubmitted: (_) {
                if (_ctrl.text.isNotEmpty) Navigator.pop(context, _ctrl.text);
              },
              style: TextStyle(color: FyrTheme.textColor),
              decoration: InputDecoration(
                labelText: 'Passphrase',
                labelStyle: TextStyle(color: FyrTheme.textColorMuted),
                filled: true,
                fillColor: FyrTheme.cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off, color: FyrTheme.textColorMuted),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: FyrTheme.accentColor, foregroundColor: Colors.white),
          onPressed: () {
            if (_ctrl.text.isEmpty) return;
            Navigator.pop(context, _ctrl.text);
          },
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
