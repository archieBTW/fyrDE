import 'package:flutter/material.dart';
import '../fyr_theme.dart';
import '../models/disk_models.dart';

class UnlockLuksDialog extends StatefulWidget {
  const UnlockLuksDialog({super.key, required this.partition});

  final BlockPartition partition;

  @override
  State<UnlockLuksDialog> createState() => _UnlockLuksDialogState();
}

class _UnlockLuksDialogState extends State<UnlockLuksDialog> {
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
      title: Text('Unlock ${widget.partition.devicePath}', style: TextStyle(color: FyrTheme.textColor)),
      content: SizedBox(
        width: 390,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the LUKS passphrase for ${widget.partition.displayLabel}.',
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
              decoration: _diskInputDecoration('Passphrase').copyWith(
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
          child: const Text('Unlock'),
        ),
      ],
    );
  }
}

class PartitionTableRequest {
  final String tableType; // 'gpt' | 'msdos'
  const PartitionTableRequest(this.tableType);
}

class CreatePartitionTableDialog extends StatefulWidget {
  const CreatePartitionTableDialog({super.key, required this.disk});

  final BlockDisk disk;

  @override
  State<CreatePartitionTableDialog> createState() => _CreatePartitionTableDialogState();
}

class _CreatePartitionTableDialogState extends State<CreatePartitionTableDialog> {
  final _confirmCtrl = TextEditingController();
  String _tableType = 'gpt';
  String? _error;

  @override
  void dispose() {
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expected = widget.disk.kname;
    return AlertDialog(
      backgroundColor: FyrTheme.panelBgColor,
      title: Text('New Partition Table (${widget.disk.devicePath})', style: TextStyle(color: FyrTheme.textColor)),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.45)),
              ),
              child: Text(
                'Warning: Initializing a partition table will ERASE ALL PARTITIONS AND DATA on ${widget.disk.displayTitle} (${BlockDisk.formatBytes(widget.disk.sizeBytes)}).',
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _tableType,
              isExpanded: true,
              dropdownColor: FyrTheme.cardColor,
              style: TextStyle(color: FyrTheme.textColor),
              decoration: _diskInputDecoration('Partition Table Type'),
              items: const [
                DropdownMenuItem(value: 'gpt', child: Text('GPT (GUID Partition Table - Recommended)')),
                DropdownMenuItem(value: 'msdos', child: Text('MBR / DOS (Legacy BIOS Compatibility)')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _tableType = v);
              },
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _confirmCtrl,
              style: TextStyle(color: FyrTheme.textColor),
              decoration: _diskInputDecoration('Type "$expected" to confirm erase'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
          onPressed: () {
            if (_confirmCtrl.text.trim() != expected) {
              setState(() => _error = 'Type "$expected" exactly to proceed.');
              return;
            }
            Navigator.pop(context, PartitionTableRequest(_tableType));
          },
          child: const Text('Erase & Create Table'),
        ),
      ],
    );
  }
}

class FormatRequest {
  final String fsId;
  final String label;
  final String? luksPassphrase;
  final int? startBytes;
  final int? endBytes;

  const FormatRequest({
    required this.fsId,
    required this.label,
    this.luksPassphrase,
    this.startBytes,
    this.endBytes,
  });
}

class PartitionFormatDialog extends StatefulWidget {
  const PartitionFormatDialog({
    super.key,
    required this.title,
    required this.subtitle,
    required this.filesystems,
    this.freeRegion,
    this.initialLabel = '',
    this.isCreate = false,
  });

  final String title;
  final String subtitle;
  final List<FilesystemOption> filesystems;
  final FreeDiskRegion? freeRegion;
  final String initialLabel;
  final bool isCreate;

  @override
  State<PartitionFormatDialog> createState() => _PartitionFormatDialogState();
}

class _PartitionFormatDialogState extends State<PartitionFormatDialog> {
  late final TextEditingController _labelCtrl;
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  late String _selectedFs;
  late double _sizeMb;
  String? _error;
  bool _obscure = true;

  int get _maxMb => widget.freeRegion != null
      ? (widget.freeRegion!.sizeBytes ~/ (1024 * 1024)).clamp(4, 100000000)
      : 0;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.initialLabel);
    final available = widget.filesystems.where((f) => f.available).toList();
    _selectedFs = available.isNotEmpty ? available.first.id : widget.filesystems.first.id;
    _sizeMb = _maxMb.toDouble();
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedOpt = widget.filesystems.firstWhere(
      (f) => f.id == _selectedFs,
      orElse: () => widget.filesystems.first,
    );
    final needsLuks = selectedOpt.supportsEncryption;

    return AlertDialog(
      backgroundColor: FyrTheme.panelBgColor,
      title: Text(widget.title, style: TextStyle(color: FyrTheme.textColor)),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.subtitle, style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 13)),
              if (widget.isCreate && widget.freeRegion != null && _maxMb > 8) ...[
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Partition Size', style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 13)),
                    Text(
                      BlockDisk.formatBytes(_sizeMb.round() * 1024 * 1024),
                      style: TextStyle(color: FyrTheme.textColor, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                Slider(
                  value: _sizeMb.clamp(4.0, _maxMb.toDouble()),
                  min: 4.0,
                  max: _maxMb.toDouble(),
                  activeColor: FyrTheme.accentColor,
                  onChanged: (v) => setState(() => _sizeMb = v),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedFs,
                isExpanded: true,
                dropdownColor: FyrTheme.cardColor,
                style: TextStyle(color: FyrTheme.textColor),
                decoration: _diskInputDecoration('Filesystem'),
                items: widget.filesystems
                    .map(
                      (fs) => DropdownMenuItem(
                        value: fs.id,
                        enabled: fs.available,
                        child: Text(
                          fs.available ? fs.displayName : '${fs.displayName} (install ${fs.toolBinary})',
                          style: TextStyle(
                            color: fs.available ? FyrTheme.textColor : FyrTheme.textColorMuted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedFs = val);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _labelCtrl,
                style: TextStyle(color: FyrTheme.textColor),
                decoration: _diskInputDecoration('Volume Label (optional)'),
              ),
              if (needsLuks) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _passCtrl,
                  obscureText: _obscure,
                  style: TextStyle(color: FyrTheme.textColor),
                  decoration: _diskInputDecoration('LUKS Encryption Passphrase').copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off, color: FyrTheme.textColorMuted),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmCtrl,
                  obscureText: _obscure,
                  style: TextStyle(color: FyrTheme.textColor),
                  decoration: _diskInputDecoration('Confirm Passphrase'),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.isCreate ? FyrTheme.accentColor : Colors.orangeAccent,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            if (!selectedOpt.available) {
              setState(() => _error = 'Install ${selectedOpt.toolBinary} to use ${selectedOpt.displayName}.');
              return;
            }
            if (needsLuks && (_passCtrl.text.isEmpty || _passCtrl.text != _confirmCtrl.text)) {
              setState(() => _error = 'LUKS passphrases must match and not be empty.');
              return;
            }
            int? startB;
            int? endB;
            if (widget.isCreate && widget.freeRegion != null) {
              startB = widget.freeRegion!.startBytes;
              final wantedBytes = _sizeMb.round() * 1024 * 1024;
              endB = (startB + wantedBytes).clamp(startB + 4 * 1024 * 1024, widget.freeRegion!.endBytes);
            }
            Navigator.pop(
              context,
              FormatRequest(
                fsId: _selectedFs,
                label: _labelCtrl.text.trim(),
                luksPassphrase: needsLuks ? _passCtrl.text : null,
                startBytes: startB,
                endBytes: endB,
              ),
            );
          },
          child: Text(widget.isCreate ? 'Create Partition' : 'Format'),
        ),
      ],
    );
  }
}

class RenameLabelDialog extends StatefulWidget {
  const RenameLabelDialog({super.key, required this.initialLabel, required this.devicePath});

  final String initialLabel;
  final String devicePath;

  @override
  State<RenameLabelDialog> createState() => _RenameLabelDialogState();
}

class _RenameLabelDialogState extends State<RenameLabelDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialLabel);
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
      title: Text('Rename Label (${widget.devicePath})', style: TextStyle(color: FyrTheme.textColor)),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: _ctrl,
          autofocus: true,
          style: TextStyle(color: FyrTheme.textColor),
          decoration: _diskInputDecoration('Filesystem Label'),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: FyrTheme.accentColor, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('Save Label'),
        ),
      ],
    );
  }
}

InputDecoration _diskInputDecoration(String label) => InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: FyrTheme.textColorMuted, fontSize: 13),
      filled: true,
      fillColor: FyrTheme.cardColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
    );
