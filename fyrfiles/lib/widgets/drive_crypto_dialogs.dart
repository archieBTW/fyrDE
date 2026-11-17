import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../fyr_theme.dart';
import '../services/crypto_service.dart';
import '../services/drives_service.dart';

class UnlockDriveDialog extends StatefulWidget {
  const UnlockDriveDialog({super.key, required this.volume});

  final ExternalDriveVolume volume;

  @override
  State<UnlockDriveDialog> createState() => _UnlockDriveDialogState();
}

class _UnlockDriveDialogState extends State<UnlockDriveDialog> {
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final passphrase = _passCtrl.text;
    if (passphrase.isEmpty) {
      setState(() => _error = 'Enter the LUKS passphrase.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    final unlockRes = await DrivesService.unlockVolume(widget.volume, passphrase);
    if (!mounted) return;
    if (!unlockRes.ok) {
      setState(() {
        _submitting = false;
        _error = unlockRes.message;
      });
      return;
    }

    String? finalMount = unlockRes.mountPoint;
    if (finalMount == null && unlockRes.unlockedDevicePath != null) {
      final mountedVol = ExternalDriveVolume(
        devicePath: widget.volume.devicePath,
        parentDiskPath: widget.volume.parentDiskPath,
        mapperPath: unlockRes.unlockedDevicePath,
        label: widget.volume.label,
        model: widget.volume.model,
        vendor: widget.volume.vendor,
        transport: widget.volume.transport,
        fsType: widget.volume.fsType,
        sizeBytes: widget.volume.sizeBytes,
        isRemovable: widget.volume.isRemovable,
        isHotplug: widget.volume.isHotplug,
        isReadOnly: widget.volume.isReadOnly,
        isEncrypted: true,
        isUnlocked: true,
      );
      final mountRes = await DrivesService.mountVolume(mountedVol);
      if (!mounted) return;
      if (!mountRes.ok) {
        setState(() {
          _submitting = false;
          _error = 'Unlocked, but failed to mount: ${mountRes.message}';
        });
        return;
      }
      finalMount = mountRes.mountPoint;
    }

    Navigator.pop(context, finalMount ?? unlockRes.unlockedDevicePath ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: FyrTheme.panelBgColor,
      title: Row(
        children: [
          Icon(Icons.lock_open, color: FyrTheme.accentColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Unlock Encrypted Drive',
              style: TextStyle(color: FyrTheme.textColor, fontSize: 18),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.volume.displayName} (${widget.volume.devicePath})',
              style: TextStyle(color: FyrTheme.textColor, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Enter the passphrase to unlock and mount this LUKS volume.',
              style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _passCtrl,
              obscureText: _obscure,
              autofocus: true,
              enabled: !_submitting,
              onSubmitted: (_) => _submit(),
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
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                    color: FyrTheme.textColorMuted,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: FyrTheme.accentColor,
            foregroundColor: Colors.white,
          ),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Unlock & Mount'),
        ),
      ],
    );
  }
}

class EncryptDialogRequest {
  final String passphrase;
  final FileEncryptionMethod method;
  final bool deleteOriginals;
  final String outputName;

  const EncryptDialogRequest({
    required this.passphrase,
    required this.method,
    required this.deleteOriginals,
    required this.outputName,
  });
}

class EncryptFilesDialog extends StatefulWidget {
  const EncryptFilesDialog({
    super.key,
    required this.paths,
    required this.destinationDir,
  });

  final List<String> paths;
  final String destinationDir;

  @override
  State<EncryptFilesDialog> createState() => _EncryptFilesDialogState();
}

class _EncryptFilesDialogState extends State<EncryptFilesDialog> {
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  late final TextEditingController _nameCtrl;
  FileEncryptionMethod _method = FileEncryptionMethod.gpgAes256;
  bool _deleteOriginals = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final defaultOut = CryptoService.defaultEncryptedOutputPath(
      paths: widget.paths,
      destinationDir: widget.destinationDir,
      method: _method,
    );
    _nameCtrl = TextEditingController(text: p.basename(defaultOut));
  }

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _updateExtensionForMethod(FileEncryptionMethod next) {
    setState(() {
      _method = next;
      final defaultOut = CryptoService.defaultEncryptedOutputPath(
        paths: widget.paths,
        destinationDir: widget.destinationDir,
        method: next,
      );
      _nameCtrl.text = p.basename(defaultOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.paths.length == 1
        ? p.basename(widget.paths.first)
        : '${widget.paths.length} selected items';

    return AlertDialog(
      backgroundColor: FyrTheme.panelBgColor,
      title: Row(
        children: [
          Icon(Icons.enhanced_encryption, color: FyrTheme.accentColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Encrypt $summary',
              style: TextStyle(color: FyrTheme.textColor, fontSize: 18),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameCtrl,
                style: TextStyle(color: FyrTheme.textColor),
                decoration: InputDecoration(
                  labelText: 'Encrypted Filename',
                  labelStyle: TextStyle(color: FyrTheme.textColorMuted),
                  filled: true,
                  fillColor: FyrTheme.cardColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<FileEncryptionMethod>(
                initialValue: _method,
                isExpanded: true,
                dropdownColor: FyrTheme.cardColor,
                style: TextStyle(color: FyrTheme.textColor),
                decoration: InputDecoration(
                  labelText: 'Encryption Format',
                  labelStyle: TextStyle(color: FyrTheme.textColorMuted),
                  filled: true,
                  fillColor: FyrTheme.cardColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                items: const [
                  DropdownMenuItem(
                    value: FileEncryptionMethod.gpgAes256,
                    child: Text('GPG AES-256 (.gpg)', overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: FileEncryptionMethod.opensslAes256,
                    child: Text('OpenSSL AES-256-CBC (.enc)', overflow: TextOverflow.ellipsis),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) _updateExtensionForMethod(v);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                autofocus: true,
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
                    icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off,
                      color: FyrTheme.textColorMuted,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmCtrl,
                obscureText: _obscure,
                style: TextStyle(color: FyrTheme.textColor),
                decoration: InputDecoration(
                  labelText: 'Confirm Passphrase',
                  labelStyle: TextStyle(color: FyrTheme.textColorMuted),
                  filled: true,
                  fillColor: FyrTheme.cardColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: FyrTheme.accentColor,
                title: Text(
                  'Delete original after encryption',
                  style: TextStyle(color: FyrTheme.textColor, fontSize: 14),
                ),
                value: _deleteOriginals,
                onChanged: (v) => setState(() => _deleteOriginals = v),
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
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
            backgroundColor: FyrTheme.accentColor,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            if (_nameCtrl.text.trim().isEmpty) {
              setState(() => _error = 'Enter an output filename.');
              return;
            }
            if (_passCtrl.text.isEmpty || _passCtrl.text != _confirmCtrl.text) {
              setState(() => _error = 'Passphrases must match and not be empty.');
              return;
            }
            Navigator.pop(
              context,
              EncryptDialogRequest(
                passphrase: _passCtrl.text,
                method: _method,
                deleteOriginals: _deleteOriginals,
                outputName: _nameCtrl.text.trim(),
              ),
            );
          },
          child: const Text('Encrypt'),
        ),
      ],
    );
  }
}

class DecryptDialogRequest {
  final String passphrase;
  final bool deleteEncrypted;

  const DecryptDialogRequest({
    required this.passphrase,
    required this.deleteEncrypted,
  });
}

class DecryptFileDialog extends StatefulWidget {
  const DecryptFileDialog({super.key, required this.filePath});

  final String filePath;

  @override
  State<DecryptFileDialog> createState() => _DecryptFileDialogState();
}

class _DecryptFileDialogState extends State<DecryptFileDialog> {
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _deleteEncrypted = false;
  String? _error;

  @override
  void dispose() {
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = p.basename(widget.filePath);
    return AlertDialog(
      backgroundColor: FyrTheme.panelBgColor,
      title: Row(
        children: [
          Icon(Icons.lock_open, color: FyrTheme.accentColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Decrypt $name', style: TextStyle(color: FyrTheme.textColor, fontSize: 18)),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the passphrase to decrypt this file in place.',
              style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _passCtrl,
              obscureText: _obscure,
              autofocus: true,
              onSubmitted: (_) {
                if (_passCtrl.text.isEmpty) {
                  setState(() => _error = 'Passphrase cannot be empty.');
                  return;
                }
                Navigator.pop(
                  context,
                  DecryptDialogRequest(
                    passphrase: _passCtrl.text,
                    deleteEncrypted: _deleteEncrypted,
                  ),
                );
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
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                    color: FyrTheme.textColorMuted,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: FyrTheme.accentColor,
              title: Text(
                'Delete encrypted file after decrypt',
                style: TextStyle(color: FyrTheme.textColor, fontSize: 14),
              ),
              value: _deleteEncrypted,
              onChanged: (v) => setState(() => _deleteEncrypted = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: FyrTheme.accentColor,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            if (_passCtrl.text.isEmpty) {
              setState(() => _error = 'Passphrase cannot be empty.');
              return;
            }
            Navigator.pop(
              context,
              DecryptDialogRequest(
                passphrase: _passCtrl.text,
                deleteEncrypted: _deleteEncrypted,
              ),
            );
          },
          child: const Text('Decrypt'),
        ),
      ],
    );
  }
}
