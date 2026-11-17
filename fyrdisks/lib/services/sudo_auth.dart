import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import '../fyr_theme.dart';

class PrivilegedResult {
  final bool cancelled;
  final int exitCode;
  final String stdout;
  final String stderr;

  const PrivilegedResult({
    this.cancelled = false,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  bool get ok => !cancelled && exitCode == 0;
}

class SudoAuth {
  static Future<bool> hasPasswordlessSudo() async {
    try {
      final res = await Process.run('sudo', ['-n', 'true']);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> validatePassword(String password) async {
    try {
      final proc = await Process.start('sudo', ['-k', '-S', '-p', '', 'true']);
      proc.stdin.writeln(password);
      await proc.stdin.flush();
      await proc.stdin.close();
      return (await proc.exitCode) == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<({bool cancelled, File? askpassFile, String? error})>
      acquireAskpass(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    if (await hasPasswordlessSudo()) {
      return (cancelled: false, askpassFile: null, error: null);
    }
    if (!context.mounted) {
      return (cancelled: true, askpassFile: null, error: null);
    }

    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SudoPromptDialog(title: title, message: message),
    );
    if (password == null || password.isEmpty) {
      return (cancelled: true, askpassFile: null, error: null);
    }

    final valid = await validatePassword(password);
    if (!valid) {
      return (cancelled: false, askpassFile: null, error: 'Incorrect sudo password.');
    }

    final tmpDir = await Directory.systemTemp.createTemp('fyr_disks_askpass_');
    await Process.run('chmod', ['700', tmpDir.path]);
    final askpassFile = File('${tmpDir.path}/askpass.sh');
    final escaped = password.replaceAll("'", "'\\''");
    await askpassFile.writeAsString("#!/bin/sh\nprintf '%s\\n' '$escaped'\n");
    await Process.run('chmod', ['700', askpassFile.path]);
    return (cancelled: false, askpassFile: askpassFile, error: null);
  }

  static Future<void> cleanupAskpass(File? askpassFile) async {
    try {
      if (askpassFile != null && askpassFile.parent.existsSync()) {
        await askpassFile.parent.delete(recursive: true);
      }
    } catch (_) {}
  }

  static Future<PrivilegedResult> run({
    required List<String> command,
    File? askpassFile,
    String? stdinData,
  }) async {
    final env = askpassFile != null
        ? <String, String>{
            ...Platform.environment,
            'SUDO_ASKPASS': askpassFile.path,
          }
        : null;
    final args = <String>[askpassFile != null ? '-A' : '-n', ...command];
    final proc = await Process.start('sudo', args, environment: env);
    if (stdinData != null) {
      proc.stdin.write(stdinData);
    }
    await proc.stdin.flush();
    await proc.stdin.close();

    final stdoutStr = await proc.stdout.transform(utf8.decoder).join();
    final stderrStr = await proc.stderr.transform(utf8.decoder).join();
    final code = await proc.exitCode;
    return PrivilegedResult(exitCode: code, stdout: stdoutStr, stderr: stderrStr);
  }
}

class _SudoPromptDialog extends StatefulWidget {
  const _SudoPromptDialog({required this.title, required this.message});

  final String title;
  final String message;

  @override
  State<_SudoPromptDialog> createState() => _SudoPromptDialogState();
}

class _SudoPromptDialogState extends State<_SudoPromptDialog> {
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
      title: Text(widget.title, style: TextStyle(color: FyrTheme.textColor)),
      content: SizedBox(
        width: 390,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message, style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 13)),
            const SizedBox(height: 14),
            TextField(
              controller: _ctrl,
              obscureText: _obscure,
              autofocus: true,
              onSubmitted: (v) => Navigator.pop(context, v),
              style: TextStyle(color: FyrTheme.textColor),
              decoration: InputDecoration(
                hintText: 'Sudo Password',
                hintStyle: TextStyle(color: FyrTheme.textColorMuted),
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
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: const Text('Authenticate'),
        ),
      ],
    );
  }
}
