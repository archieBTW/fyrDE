import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../fyr_theme.dart';
import '../models/disk_models.dart';
import '../services/disk_backend.dart';
import '../services/sudo_auth.dart';

class IsoFlasherView extends StatefulWidget {
  const IsoFlasherView({
    super.key,
    required this.disks,
    this.initialImagePath,
    this.initialTargetDiskPath,
    required this.onCompleted,
  });

  final List<BlockDisk> disks;
  final String? initialImagePath;
  final String? initialTargetDiskPath;
  final VoidCallback onCompleted;

  @override
  State<IsoFlasherView> createState() => _IsoFlasherViewState();
}

class _IsoFlasherViewState extends State<IsoFlasherView> {
  String? _imagePath;
  int _imageSize = 0;
  String? _sha256Hex;
  bool _hashing = false;
  String? _selectedDiskPath;
  bool _includeAllExternal = false;
  bool _flashing = false;
  FlashProgressUpdate? _progress;
  String? _statusMessage;
  bool _statusIsError = false;
  final _confirmCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialImagePath != null && File(widget.initialImagePath!).existsSync()) {
      _setImage(widget.initialImagePath!);
    }
    _syncDefaultTarget();
  }

  @override
  void didUpdateWidget(covariant IsoFlasherView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncDefaultTarget();
  }

  @override
  void dispose() {
    _confirmCtrl.dispose();
    super.dispose();
  }

  List<BlockDisk> get _eligibleTargets {
    return widget.disks.where((d) {
      if (d.isSystemDisk) return false;
      if (_includeAllExternal) return true;
      return d.isExternal;
    }).toList();
  }

  void _syncDefaultTarget() {
    final targets = _eligibleTargets;
    if (widget.initialTargetDiskPath != null &&
        targets.any((d) => d.devicePath == widget.initialTargetDiskPath)) {
      _selectedDiskPath ??= widget.initialTargetDiskPath;
    }
    if (_selectedDiskPath == null || !targets.any((d) => d.devicePath == _selectedDiskPath)) {
      _selectedDiskPath = targets.isNotEmpty ? targets.first.devicePath : null;
    }
  }

  void _setImage(String path) {
    final f = File(path);
    setState(() {
      _imagePath = path;
      _imageSize = f.existsSync() ? f.lengthSync() : 0;
      _sha256Hex = null;
      _statusMessage = null;
    });
  }

  Future<void> _pickImage() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Select ISO or Disk Image',
      type: FileType.custom,
      allowedExtensions: ['iso', 'img', 'raw', 'bin'],
    );
    final path = picked?.files.single.path;
    if (path != null && path.isNotEmpty) {
      _setImage(path);
    }
  }

  Future<void> _computeSha256() async {
    if (_imagePath == null || _hashing) return;
    setState(() => _hashing = true);
    try {
      final hash = await DiskBackend.computeSha256(_imagePath!);
      if (mounted) {
        setState(() {
          _sha256Hex = hash;
          _hashing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hashing = false;
          _statusMessage = 'Failed to compute SHA-256: $e';
          _statusIsError = true;
        });
      }
    }
  }

  Future<void> _startFlash() async {
    final targets = _eligibleTargets;
    final target = targets.where((d) => d.devicePath == _selectedDiskPath).firstOrNull;
    if (_imagePath == null || target == null) return;
    if (_confirmCtrl.text.trim() != target.kname) {
      setState(() {
        _statusMessage = 'Type "${target.kname}" in the confirmation box before flashing.';
        _statusIsError = true;
      });
      return;
    }

    File? askpassFile;
    setState(() {
      _flashing = true;
      _statusMessage = null;
      _statusIsError = false;
      _progress = FlashProgressUpdate(bytesWritten: 0, totalBytes: _imageSize);
    });

    try {
      final auth = await SudoAuth.acquireAskpass(
        context,
        title: 'Flash Image to ${target.devicePath}',
        message: 'Enter your sudo password to flash ${p.basename(_imagePath!)} onto ${target.displayTitle}.',
      );
      if (auth.cancelled) {
        if (mounted) setState(() => _flashing = false);
        return;
      }
      if (auth.error != null) {
        if (mounted) {
          setState(() {
            _flashing = false;
            _statusMessage = auth.error;
            _statusIsError = true;
          });
        }
        return;
      }
      askpassFile = auth.askpassFile;

      final res = await DiskBackend.flashImageToDisk(
        imagePath: _imagePath!,
        targetDisk: target,
        askpassFile: askpassFile,
        onProgress: (upd) {
          if (mounted) setState(() => _progress = upd);
        },
      );
      if (!mounted) return;
      setState(() {
        _flashing = false;
        _statusMessage = res.ok ? res.message : '${res.message} ${res.details}'.trim();
        _statusIsError = !res.ok;
        if (res.ok) _confirmCtrl.clear();
      });
      widget.onCompleted();
    } finally {
      await SudoAuth.cleanupAskpass(askpassFile);
    }
  }

  @override
  Widget build(BuildContext context) {
    final targets = _eligibleTargets;
    final selectedDisk = targets.where((d) => d.devicePath == _selectedDiskPath).firstOrNull;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Flash ISO / Disk Image',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: FyrTheme.textColor),
          ),
          const SizedBox(height: 6),
          Text(
            'Write bootable Linux ISOs or raw disk images directly to an external USB flash drive.',
            style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 14),
          ),
          const SizedBox(height: 22),

          Card(
            color: FyrTheme.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: FyrTheme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.disc_full, color: FyrTheme.accentColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '1. Source Image (.iso / .img)',
                          style: TextStyle(color: FyrTheme.textColor, fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _flashing ? null : _pickImage,
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: Text(_imagePath == null ? 'Choose Image...' : 'Change Image'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: FyrTheme.accentColor,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  if (_imagePath != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      p.basename(_imagePath!),
                      style: TextStyle(color: FyrTheme.textColor, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$_imagePath  •  ${BlockDisk.formatBytes(_imageSize)}',
                      style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    if (_sha256Hex != null)
                      SelectableText(
                        'SHA-256: $_sha256Hex',
                        style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12, fontFamily: 'monospace'),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: _hashing || _flashing ? null : _computeSha256,
                        icon: _hashing
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.verified_user_outlined, size: 16),
                        label: Text(_hashing ? 'Calculating SHA-256...' : 'Verify SHA-256 Checksum'),
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          Card(
            color: FyrTheme.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: FyrTheme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.usb, color: FyrTheme.accentColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '2. Target USB / Removable Drive',
                          style: TextStyle(color: FyrTheme.textColor, fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                      ),
                      Row(
                        children: [
                          Text('Show all non-OS disks', style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12)),
                          Switch(
                            value: _includeAllExternal,
                            activeThumbColor: FyrTheme.accentColor,
                            onChanged: _flashing
                                ? null
                                : (v) => setState(() {
                                      _includeAllExternal = v;
                                      _syncDefaultTarget();
                                    }),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (targets.isEmpty)
                    Text(
                      'No external USB flash drives detected. Plug in a USB drive and click Refresh.',
                      style: TextStyle(color: FyrTheme.textColorMuted),
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _selectedDiskPath,
                      isExpanded: true,
                      dropdownColor: FyrTheme.panelBgColor,
                      style: TextStyle(color: FyrTheme.textColor),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: FyrTheme.surfaceColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      items: targets
                          .map(
                            (d) => DropdownMenuItem(
                              value: d.devicePath,
                              child: Text(
                                '${d.displayTitle} (${d.devicePath}) — ${BlockDisk.formatBytes(d.sizeBytes)}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _flashing ? null : (v) => setState(() => _selectedDiskPath = v),
                    ),
                  if (selectedDisk != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amberAccent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.45)),
                      ),
                      child: Text(
                        'All partitions and files on ${selectedDisk.displayTitle} (${selectedDisk.devicePath}) will be permanently overwritten.',
                        style: const TextStyle(color: Colors.amberAccent, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _confirmCtrl,
                      enabled: !_flashing,
                      style: TextStyle(color: FyrTheme.textColor),
                      decoration: InputDecoration(
                        labelText: 'Type "${selectedDisk.kname}" to confirm flash',
                        labelStyle: TextStyle(color: FyrTheme.textColorMuted, fontSize: 13),
                        filled: true,
                        fillColor: FyrTheme.surfaceColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          if (_flashing && _progress != null) ...[
            const SizedBox(height: 18),
            Card(
              color: FyrTheme.cardColor,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Flashing in progress...', style: TextStyle(color: FyrTheme.textColor, fontWeight: FontWeight.w600)),
                        Text(
                          '${(_progress!.fraction * 100).toStringAsFixed(1)}%',
                          style: TextStyle(color: FyrTheme.accentColor, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: _progress!.totalBytes > 0 ? _progress!.fraction : null,
                      color: FyrTheme.accentColor,
                      minHeight: 8,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${BlockDisk.formatBytes(_progress!.bytesWritten)} / ${BlockDisk.formatBytes(_progress!.totalBytes)}'
                      '${_progress!.speedBytesPerSec != null ? '  •  ${BlockDisk.formatBytes(_progress!.speedBytesPerSec!.round())}/s' : ''}',
                      style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],

          if (_statusMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: (_statusIsError ? Colors.redAccent : Colors.greenAccent).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: (_statusIsError ? Colors.redAccent : Colors.greenAccent).withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                _statusMessage!,
                style: TextStyle(color: _statusIsError ? Colors.redAccent : Colors.greenAccent),
              ),
            ),
          ],

          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: (_flashing || _imagePath == null || selectedDisk == null) ? null : _startFlash,
            icon: const Icon(Icons.bolt),
            label: Text(_flashing ? 'Writing Image...' : 'Flash Image Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}
