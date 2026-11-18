import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';
import 'fyr_theme.dart';
import 'models/disk_models.dart';
import 'services/disk_backend.dart';
import 'services/sudo_auth.dart';
import 'widgets/disk_dialogs.dart';
import 'widgets/iso_flasher_view.dart';
import 'widgets/resizable_window.dart';
import 'widgets/traffic_lights.dart';

String? _initialArgImage;
String? _initialArgDisk;

void main(List<String> args) async {
  for (final raw in args) {
    final arg = raw.trim();
    if (arg.isEmpty || arg.startsWith('-')) continue;
    final lower = arg.toLowerCase();
    if ((lower.endsWith('.iso') || lower.endsWith('.img') || lower.endsWith('.raw')) &&
        File(arg).existsSync()) {
      _initialArgImage = arg;
    } else if (arg.startsWith('/dev/')) {
      _initialArgDisk = arg;
    }
  }

  WidgetsFlutterBinding.ensureInitialized();
  FyrTheme.initialize();
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1160, 740),
    minimumSize: Size(860, 560),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'fyrDisks',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const FyrDisksApp());
}

class FyrDisksApp extends StatelessWidget {
  const FyrDisksApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        FyrTheme.accentColorNotifier,
        FyrTheme.themeModeNotifier,
      ]),
      builder: (_, __) {
        final accent = FyrTheme.accentColor;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'fyrDisks',
          themeMode: FyrTheme.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: ColorScheme.light(
              primary: accent,
              secondary: accent,
              surface: FyrTheme.surfaceColor,
            ),
            textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
            scaffoldBackgroundColor: FyrTheme.bgColor,
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.dark(
              primary: accent,
              secondary: accent,
              surface: FyrTheme.surfaceColor,
            ),
            textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
            scaffoldBackgroundColor: const Color(0xFF000000),
          ),
          home: DisksShell(
            initialImagePath: _initialArgImage,
            initialDiskPath: _initialArgDisk,
          ),
        );
      },
    );
  }
}

class DisksShell extends StatefulWidget {
  const DisksShell({
    super.key,
    this.initialDisks,
    this.initialFilesystems,
    this.autoLoad = true,
    this.initialImagePath,
    this.initialDiskPath,
  });

  final List<BlockDisk>? initialDisks;
  final List<FilesystemOption>? initialFilesystems;
  final bool autoLoad;
  final String? initialImagePath;
  final String? initialDiskPath;

  @override
  State<DisksShell> createState() => _DisksShellState();
}

class _DisksShellState extends State<DisksShell> {
  List<BlockDisk> _disks = [];
  List<FilesystemOption> _filesystems = [];
  String? _selectedDiskPath;
  String? _selectedPartitionPath;
  bool _showFlasher = false;
  String? _flasherTargetDisk;
  bool _loading = false;
  bool _busy = false;
  String? _busyMessage;
  String? _error;

  @override
  void initState() {
    super.initState();
    _disks = widget.initialDisks ?? [];
    _filesystems = widget.initialFilesystems ?? [];
    if (widget.initialImagePath != null) {
      _showFlasher = true;
    }
    if (widget.initialDiskPath != null) {
      _selectedDiskPath = widget.initialDiskPath;
    } else if (_disks.isNotEmpty) {
      _selectedDiskPath = _disks.first.devicePath;
    }

    if (widget.autoLoad) {
      _refreshAll();
    }
  }

  Future<void> _refreshAll({bool probeFreeSpace = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        DiskBackend.loadDisks(includeFreeRegions: probeFreeSpace),
        DiskBackend.detectFilesystemOptions(),
      ]);
      if (!mounted) return;
      final loadedDisks = results[0] as List<BlockDisk>;
      final loadedFs = results[1] as List<FilesystemOption>;
      setState(() {
        _disks = loadedDisks;
        _filesystems = loadedFs;
        _loading = false;
        if (_selectedDiskPath == null ||
            !_disks.any((d) => d.devicePath == _selectedDiskPath)) {
          _selectedDiskPath = _disks.isNotEmpty ? _disks.first.devicePath : null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  BlockDisk? get _selectedDisk {
    if (_selectedDiskPath == null) return _disks.firstOrNull;
    return _disks.where((d) => d.devicePath == _selectedDiskPath).firstOrNull ?? _disks.firstOrNull;
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

  Future<void> _runPrivileged({
    required String authTitle,
    required String authMessage,
    required String busyLabel,
    required Future<DiskOpResult> Function(File? askpassFile) action,
  }) async {
    File? askpassFile;
    setState(() {
      _busy = true;
      _busyMessage = busyLabel;
    });
    try {
      final auth = await SudoAuth.acquireAskpass(
        context,
        title: authTitle,
        message: authMessage,
      );
      if (auth.cancelled) return;
      if (auth.error != null) {
        _showSnack(auth.error!, isError: true);
        return;
      }
      askpassFile = auth.askpassFile;
      final res = await action(askpassFile);
      _showSnack(
        res.ok ? res.message : '${res.message} ${res.details}'.trim(),
        isError: !res.ok,
      );
      await _refreshAll();
    } finally {
      await SudoAuth.cleanupAskpass(askpassFile);
      if (mounted) {
        setState(() {
          _busy = false;
          _busyMessage = null;
        });
      }
    }
  }

  Future<void> _handleMountOrUnmount(BlockPartition part) async {
    setState(() => _busy = true);
    try {
      final res = part.isMounted
          ? await DiskBackend.unmountPartition(part)
          : await DiskBackend.mountPartition(part);
      _showSnack(res.message, isError: !res.ok);
      await _refreshAll();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleUnlockOrLock(BlockPartition part) async {
    if (part.isUnlocked) {
      setState(() => _busy = true);
      try {
        final res = await DiskBackend.lockPartition(part);
        _showSnack(res.message, isError: !res.ok);
        await _refreshAll();
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }

    final pass = await showDialog<String>(
      context: context,
      builder: (_) => UnlockLuksDialog(partition: part),
    );
    if (pass == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final res = await DiskBackend.unlockPartition(part, pass);
      _showSnack(res.message, isError: !res.ok);
      await _refreshAll();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleNewPartitionTable(BlockDisk disk) async {
    final req = await showDialog<PartitionTableRequest>(
      context: context,
      builder: (_) => CreatePartitionTableDialog(disk: disk),
    );
    if (req == null || !mounted) return;
    await _runPrivileged(
      authTitle: 'Initialize ${disk.devicePath}',
      authMessage: 'Enter your sudo password to create a ${req.tableType.toUpperCase()} partition table on ${disk.devicePath}.',
      busyLabel: 'Creating partition table on ${disk.devicePath}...',
      action: (askpass) => DiskBackend.createPartitionTable(
        disk: disk,
        tableType: req.tableType,
        askpassFile: askpass,
      ),
    );
  }

  Future<void> _handleFormatPartition(BlockPartition part) async {
    final req = await showDialog<FormatRequest>(
      context: context,
      builder: (_) => PartitionFormatDialog(
        title: 'Format ${part.devicePath}',
        subtitle: 'Warning: Formatting permanently erases existing data on ${part.displayLabel} (${BlockDisk.formatBytes(part.sizeBytes)}).',
        filesystems: _filesystems,
        initialLabel: part.label ?? '',
        isCreate: false,
      ),
    );
    if (req == null || !mounted) return;
    await _runPrivileged(
      authTitle: 'Format ${part.devicePath}',
      authMessage: 'Enter your sudo password to format ${part.devicePath} as ${req.fsId}.',
      busyLabel: 'Formatting ${part.devicePath}...',
      action: (askpass) => DiskBackend.formatPartition(
        part: part,
        fsId: req.fsId,
        label: req.label,
        luksPassphrase: req.luksPassphrase,
        askpassFile: askpass,
      ),
    );
  }

  Future<void> _handleCreatePartition(BlockDisk disk) async {
    // Query live free regions right before opening dialog so start/end offsets match disk geometry.
    FreeDiskRegion? region = disk.freeRegions.firstOrNull;
    if (region == null) {
      if (disk.partitions.isEmpty && disk.sizeBytes > 16 * 1024 * 1024) {
        region = FreeDiskRegion(
          startBytes: 1024 * 1024,
          endBytes: disk.sizeBytes - 1024 * 1024,
          sizeBytes: disk.sizeBytes - 2 * 1024 * 1024,
        );
      } else {
        await _runPrivileged(
          authTitle: 'Inspect Free Space',
          authMessage: 'Enter your sudo password to read free partition gaps on ${disk.devicePath}.',
          busyLabel: 'Scanning partition layout...',
          action: (askpass) async {
            final res = await SudoAuth.run(
              command: ['parted', '-m', disk.devicePath, 'unit', 'B', 'print', 'free'],
              askpassFile: askpass,
            );
            if (!res.ok) {
              return DiskOpResult(ok: false, message: 'Could not scan free regions.', details: res.stderr);
            }
            final regions = DiskBackend.parsePartedFreeRegions(res.stdout);
            if (regions.isEmpty) {
              return const DiskOpResult(ok: false, message: 'No unallocated space >= 4 MB found on this disk.');
            }
            region = regions.reduce((a, b) => a.sizeBytes >= b.sizeBytes ? a : b);
            return const DiskOpResult(ok: true, message: 'Ready to create partition.');
          },
        );
      }
    }

    if (region == null || !mounted) return;
    final req = await showDialog<FormatRequest>(
      context: context,
      builder: (_) => PartitionFormatDialog(
        title: 'Create Partition on ${disk.devicePath}',
        subtitle: 'Available unallocated space: ${BlockDisk.formatBytes(region!.sizeBytes)}.',
        filesystems: _filesystems,
        freeRegion: region,
        isCreate: true,
      ),
    );
    if (req == null || !mounted || req.startBytes == null || req.endBytes == null) return;

    await _runPrivileged(
      authTitle: 'Create Partition',
      authMessage: 'Enter your sudo password to create and format the new partition on ${disk.devicePath}.',
      busyLabel: 'Creating partition on ${disk.devicePath}...',
      action: (askpass) => DiskBackend.createPartitionAndFormat(
        disk: disk,
        startBytes: req.startBytes!,
        endBytes: req.endBytes!,
        fsId: req.fsId,
        label: req.label,
        luksPassphrase: req.luksPassphrase,
        askpassFile: askpass,
      ),
    );
  }

  Future<void> _handleDeletePartition(BlockDisk disk, BlockPartition part) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FyrTheme.panelBgColor,
        title: Text('Delete ${part.devicePath}?', style: TextStyle(color: FyrTheme.textColor)),
        content: Text(
          'This will permanently delete partition "${part.displayLabel}" (${BlockDisk.formatBytes(part.sizeBytes)}) and all data inside it.',
          style: TextStyle(color: FyrTheme.textColorMuted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Partition'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runPrivileged(
      authTitle: 'Delete ${part.devicePath}',
      authMessage: 'Enter your sudo password to remove partition #${part.partitionNumber ?? ''} from ${disk.devicePath}.',
      busyLabel: 'Deleting ${part.devicePath}...',
      action: (askpass) => DiskBackend.deletePartition(
        disk: disk,
        part: part,
        askpassFile: askpass,
      ),
    );
  }

  Future<void> _handleRenameLabel(BlockPartition part) async {
    final newLabel = await showDialog<String>(
      context: context,
      builder: (_) => RenameLabelDialog(
        initialLabel: part.unlockedLabel ?? part.label ?? '',
        devicePath: part.mountTargetDevice,
      ),
    );
    if (newLabel == null || !mounted) return;
    await _runPrivileged(
      authTitle: 'Rename Filesystem Label',
      authMessage: 'Enter your sudo password to rename ${part.mountTargetDevice}.',
      busyLabel: 'Updating label...',
      action: (askpass) => DiskBackend.renamePartitionLabel(
        part: part,
        newLabel: newLabel,
        askpassFile: askpass,
      ),
    );
  }

  Future<void> _handleOpenInFyrFiles(BlockPartition part) async {
    if (!part.isMounted) return;
    try {
      await Process.start('fyrfiles', [part.mountPoints.first], mode: ProcessStartMode.detached);
    } catch (e) {
      _showSnack('Could not open fyrfiles: $e', isError: true);
    }
  }

  Future<void> _handlePowerOff(BlockDisk disk) async {
    setState(() => _busy = true);
    try {
      final res = await DiskBackend.powerOffDisk(disk);
      _showSnack(res.message, isError: !res.ok);
      await _refreshAll();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _colorForFilesystem(String? fs, bool isEncrypted) {
    if (isEncrypted) return Colors.deepPurpleAccent;
    switch ((fs ?? '').toLowerCase()) {
      case 'ext4':
      case 'ext3':
      case 'ext2':
        return Colors.blueAccent;
      case 'btrfs':
        return Colors.tealAccent.shade700;
      case 'vfat':
      case 'fat32':
      case 'exfat':
        return Colors.amber.shade700;
      case 'ntfs':
        return Colors.indigoAccent;
      case 'iso9660':
        return Colors.cyan.shade700;
      case 'swap':
        return Colors.deepOrangeAccent;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final disk = _selectedDisk;

    return ResizableWindow(
      child: Scaffold(
        backgroundColor: FyrTheme.bgColor,
        body: Column(
          children: [
            _buildTitleBar(),
            if (_busy)
              LinearProgressIndicator(color: FyrTheme.accentColor, minHeight: 2),
            Expanded(
              child: Row(
                children: [
                  _buildSidebar(),
                  Expanded(
                    child: Container(
                      color: FyrTheme.contentColor,
                      child: _showFlasher
                          ? IsoFlasherView(
                              disks: _disks,
                              initialImagePath: widget.initialImagePath,
                              initialTargetDiskPath: _flasherTargetDisk,
                              onCompleted: () => _refreshAll(),
                            )
                          : (disk == null
                              ? _buildEmptyState()
                              : _buildDiskInspector(disk)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: FyrTheme.sidebarColor,
          border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
        ),
        child: Row(
          children: [
            const TrafficLights(),
            const SizedBox(width: 14),
            Icon(Icons.storage_rounded, color: FyrTheme.accentColor, size: 20),
            const SizedBox(width: 10),
            Text(
              'fyrDisks',
              style: TextStyle(color: FyrTheme.textColor, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            if (_busyMessage != null) ...[
              const SizedBox(width: 14),
              Text(_busyMessage!, style: TextStyle(color: FyrTheme.accentColor, fontSize: 12)),
            ],
            const Spacer(),
            IconButton(
              tooltip: 'Refresh Drives',
              icon: Icon(Icons.refresh, size: 18, color: FyrTheme.textColorMuted),
              onPressed: _loading || _busy ? null : () => _refreshAll(probeFreeSpace: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    final externalDisks = _disks.where((d) => d.isExternal).toList();
    final internalDisks = _disks.where((d) => !d.isExternal).toList();

    return Container(
      width: 268,
      decoration: BoxDecoration(
        color: FyrTheme.sidebarColor,
        border: Border(right: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        children: [
          _sidebarSectionLabel('TOOLS'),
          _sidebarActionTile(
            icon: Icons.disc_full,
            label: 'Flash ISO / Image',
            subtitle: 'Write bootable USB drives',
            selected: _showFlasher,
            onTap: () => setState(() {
              _showFlasher = true;
              _flasherTargetDisk = null;
            }),
          ),
          const SizedBox(height: 16),
          if (externalDisks.isNotEmpty) ...[
            _sidebarSectionLabel('EXTERNAL & REMOVABLE'),
            ...externalDisks.map(_buildDiskNavTile),
            const SizedBox(height: 14),
          ],
          _sidebarSectionLabel('INTERNAL DRIVES'),
          if (internalDisks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text('No drives detected', style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12)),
            )
          else
            ...internalDisks.map(_buildDiskNavTile),
        ],
      ),
    );
  }

  Widget _sidebarSectionLabel(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      child: Text(
        title,
        style: TextStyle(
          color: FyrTheme.textColorMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _sidebarActionTile({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: selected ? FyrTheme.accentColor.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: selected ? Border.all(color: FyrTheme.accentColor.withValues(alpha: 0.5)) : null,
      ),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: FyrTheme.accentColor, size: 22),
        title: Text(label, style: TextStyle(color: FyrTheme.textColor, fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Text(subtitle, style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 11)),
        onTap: onTap,
      ),
    );
  }

  Widget _buildDiskNavTile(BlockDisk disk) {
    final isSelected = !_showFlasher && _selectedDisk?.devicePath == disk.devicePath;
    final IconData icon;
    if (disk.hasAnyEncryptedPartition) {
      icon = Icons.enhanced_encryption;
    } else if (disk.transport == 'usb' || disk.isRemovable || disk.isHotplug) {
      icon = Icons.usb;
    } else {
      icon = Icons.storage;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isSelected ? FyrTheme.accentColor.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: isSelected ? Border.all(color: FyrTheme.accentColor.withValues(alpha: 0.5)) : null,
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          icon,
          color: isSelected ? FyrTheme.accentColor : FyrTheme.textColorMuted,
          size: 22,
        ),
        title: Text(
          disk.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: FyrTheme.textColor, fontWeight: FontWeight.w600, fontSize: 13),
        ),
        subtitle: Text(
          '${BlockDisk.formatBytes(disk.sizeBytes)} • ${disk.devicePath}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 11),
        ),
        onTap: () => setState(() {
          _showFlasher = false;
          _selectedDiskPath = disk.devicePath;
          _selectedPartitionPath = null;
        }),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Text(
        _error ?? (_loading ? 'Scanning block devices...' : 'Select a drive from the sidebar.'),
        style: TextStyle(color: FyrTheme.textColorMuted),
      ),
    );
  }

  Widget _buildDiskInspector(BlockDisk disk) {
    final totalBytes = max(1, disk.sizeBytes);
    final unallocBytes = disk.unallocatedBytes;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                disk.displayTitle,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: FyrTheme.textColor),
              ),
              if (disk.isSystemDisk)
                _pill('System OS Disk', Colors.amber)
              else if (disk.isExternal)
                _pill('External Drive', FyrTheme.accentColor),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${disk.devicePath} • ${BlockDisk.formatBytes(disk.sizeBytes)}'
            '${disk.transport != null ? ' • ${disk.transport!.toUpperCase()}' : ''}'
            '${disk.partitionTable != null ? ' • ${disk.partitionTable!.toUpperCase()} Table' : ' • Raw / ISO'}'
            '${disk.serial != null && disk.serial!.isNotEmpty ? ' • S/N ${disk.serial}' : ''}',
            style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!disk.isSystemDisk) ...[
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _handleCreatePartition(disk),
                  icon: const Icon(Icons.add_box_outlined, size: 17),
                  label: const Text('New Partition'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _handleNewPartitionTable(disk),
                  icon: const Icon(Icons.table_chart_outlined, size: 17),
                  label: const Text('Partition Table'),
                ),
                ElevatedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _flasherTargetDisk = disk.devicePath;
                            _showFlasher = true;
                          }),
                  icon: const Icon(Icons.disc_full, size: 17),
                  label: const Text('Flash ISO'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FyrTheme.accentColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
              if (disk.isExternal)
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _handlePowerOff(disk),
                  icon: const Icon(Icons.eject, size: 17),
                  label: const Text('Power Off'),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // Visual proportional partition bar
          Text('Volume Layout', style: TextStyle(color: FyrTheme.textColor, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Container(
            height: 62,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: FyrTheme.cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: FyrTheme.dividerColor),
            ),
            child: disk.partitions.isEmpty
                ? Center(
                    child: Text(
                      disk.fsType != null && disk.fsType!.isNotEmpty
                          ? 'Whole-disk ${disk.fsType} (${disk.label ?? disk.devicePath})'
                          : 'Unallocated Space — ${BlockDisk.formatBytes(disk.sizeBytes)}',
                      style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 13),
                    ),
                  )
                : Row(
                    children: [
                      ...disk.partitions.map((part) {
                        final flex = max(4, ((part.sizeBytes / totalBytes) * 1000).round());
                        final color = _colorForFilesystem(part.effectiveFsType, part.isEncrypted);
                        final selected = _selectedPartitionPath == part.devicePath;
                        return Expanded(
                          flex: flex,
                          child: InkWell(
                            onTap: () => setState(() => _selectedPartitionPath = part.devicePath),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: selected ? 0.35 : 0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: selected ? FyrTheme.accentColor : color.withValues(alpha: 0.7),
                                  width: selected ? 2 : 1,
                                ),
                              ),
                              child: LayoutBuilder(
                                builder: (_, constraints) {
                                  if (constraints.maxWidth < 48) {
                                    return const SizedBox.shrink();
                                  }
                                  return Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          if (part.isEncrypted)
                                            Padding(
                                              padding: const EdgeInsets.only(right: 4),
                                              child: Icon(
                                                part.isUnlocked ? Icons.lock_open : Icons.lock,
                                                size: 13,
                                                color: color,
                                              ),
                                            ),
                                          Expanded(
                                            child: Text(
                                              part.displayLabel,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: FyrTheme.textColor,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        '${part.effectiveFsType} • ${BlockDisk.formatBytes(part.sizeBytes)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 11),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      }),
                      if (unallocBytes > 16 * 1024 * 1024)
                        Expanded(
                          flex: max(4, ((unallocBytes / totalBytes) * 1000).round()),
                          child: InkWell(
                            onTap: _busy || disk.isSystemDisk ? null : () => _handleCreatePartition(disk),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: FyrTheme.surfaceColor.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: FyrTheme.dividerColor),
                              ),
                              child: Center(
                                child: Text(
                                  'Free (${BlockDisk.formatBytes(unallocBytes)})',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 11),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 22),

          Text('Partitions (${disk.partitions.length})',
              style: TextStyle(color: FyrTheme.textColor, fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 10),

          if (disk.partitions.isEmpty)
            Card(
              color: FyrTheme.cardColor,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: FyrTheme.textColorMuted),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        disk.fsType != null && disk.fsType!.isNotEmpty
                            ? 'This drive has a whole-disk filesystem (${disk.fsType}) with no partition table.'
                            : 'This disk has no partitions. Create a GPT partition table and partition to get started.',
                        style: TextStyle(color: FyrTheme.textColorMuted),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...disk.partitions.map((part) => _buildPartitionCard(disk, part)),
        ],
      ),
    );
  }

  Widget _buildPartitionCard(BlockDisk disk, BlockPartition part) {
    final fsColor = _colorForFilesystem(part.effectiveFsType, part.isEncrypted);
    final selected = _selectedPartitionPath == part.devicePath;

    return Card(
      color: FyrTheme.cardColor,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? FyrTheme.accentColor : FyrTheme.dividerColor,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: fsColor.withValues(alpha: 0.18),
                  child: Icon(
                    part.isLocked
                        ? Icons.lock
                        : (part.isEncrypted ? Icons.lock_open : Icons.pie_chart_outline),
                    color: fsColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            part.displayLabel,
                            style: TextStyle(color: FyrTheme.textColor, fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                          _pill(part.effectiveFsType, fsColor),
                          if (part.isEncrypted)
                            _pill(
                              part.isUnlocked ? 'LUKS Unlocked' : 'LUKS Locked',
                              part.isUnlocked ? Colors.green : Colors.amber,
                            ),
                          if (part.isMounted)
                            _pill('Mounted', Colors.green),
                          if (part.isSystemCritical)
                            _pill('Protected OS Partition', Colors.amber),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${part.devicePath} • ${BlockDisk.formatBytes(part.sizeBytes)}'
                        '${part.mapperPath != null ? ' • Mapper: ${part.mapperPath}' : ''}'
                        '${part.isMounted ? ' • Mounted at ${part.mountPoints.join(', ')}' : ''}',
                        style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (part.isEncrypted)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _handleUnlockOrLock(part),
                    icon: Icon(part.isUnlocked ? Icons.lock : Icons.lock_open, size: 16),
                    label: Text(part.isUnlocked ? 'Lock LUKS' : 'Unlock LUKS'),
                  ),
                if (!part.isLocked && part.effectiveFsType != 'swap' && part.effectiveFsType != 'unformatted')
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _handleMountOrUnmount(part),
                    icon: Icon(part.isMounted ? Icons.link_off : Icons.folder_open, size: 16),
                    label: Text(part.isMounted ? 'Unmount' : 'Mount'),
                  ),
                if (part.isMounted)
                  OutlinedButton.icon(
                    onPressed: () => _handleOpenInFyrFiles(part),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Browse in fyrfiles'),
                  ),
                if (!part.isLocked && !part.isSystemCritical && part.effectiveFsType != 'unformatted' && part.effectiveFsType != 'swap')
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _handleRenameLabel(part),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Label'),
                  ),
                if (!part.isSystemCritical) ...[
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _handleFormatPartition(part),
                    icon: const Icon(Icons.cleaning_services, size: 16),
                    label: const Text('Format...'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _handleDeletePartition(disk, part),
                    icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                    label: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
