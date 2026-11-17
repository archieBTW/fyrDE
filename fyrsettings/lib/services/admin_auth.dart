import 'dart:io';

import 'package:flutter/material.dart';
import '../fyr_theme.dart';

/// Result of running a privileged command via `sudo`.
class PrivilegedCommandResult {
  final bool cancelled;
  final int exitCode;
  final String stdout;
  final String stderr;

  const PrivilegedCommandResult({
    this.cancelled = false,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  bool get ok => !cancelled && exitCode == 0;
}

/// Shared elevation helper for Settings panes that execute `sudo` commands.
class AdminAuth {
  static Future<String?> promptSudoPassword(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SudoPasswordDialog(title: title, message: message),
    );
  }

  /// Ensures `sudo` authorization (reusing cached/passwordless tickets if active
  /// or prompting the user once) and returns a temporary askpass script path if
  /// a password was supplied. Callers MUST delete the returned file's parent
  /// directory in a `finally` block.
  static Future<({bool cancelled, File? askpassFile, String? error})>
      acquireSudoAskpass(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    if (await UpdateService.hasPasswordlessSudo()) {
      return (cancelled: false, askpassFile: null, error: null);
    }
    if (!context.mounted) {
      return (cancelled: true, askpassFile: null, error: null);
    }

    final password = await promptSudoPassword(
      context,
      title: title,
      message: message,
    );
    if (password == null || password.isEmpty) {
      return (cancelled: true, askpassFile: null, error: null);
    }

    final valid = await UpdateService.validateSudoPassword(password);
    if (!valid) {
      return (
        cancelled: false,
        askpassFile: null,
        error: 'Incorrect sudo password.',
      );
    }

    final tmpDir = Directory.systemTemp.createTempSync('fyr_admin_askpass_');
    final askpassFile = File('${tmpDir.path}/askpass.sh');
    final escaped = password.replaceAll("'", "'\\''");
    await askpassFile.writeAsString("#!/bin/sh\nprintf '%s\\n' '$escaped'\n");
    await Process.run('chmod', ['700', askpassFile.path]);
    return (cancelled: false, askpassFile: askpassFile, error: null);
  }

  static Future<PrivilegedCommandResult> runWithSudo({
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
    final sudoArgs = <String>[
      askpassFile != null ? '-A' : '-n',
      ...command,
    ];
    final proc = await Process.start('sudo', sudoArgs, environment: env);
    if (stdinData != null) {
      proc.stdin.write(stdinData);
    }
    await proc.stdin.flush();
    await proc.stdin.close();

    final stdoutStr = await proc.stdout.transform(const SystemEncoding().decoder).join();
    final stderrStr = await proc.stderr.transform(const SystemEncoding().decoder).join();
    final code = await proc.exitCode;
    return PrivilegedCommandResult(
      exitCode: code,
      stdout: stdoutStr,
      stderr: stderrStr,
    );
  }
}

class _SudoPasswordDialog extends StatefulWidget {
  const _SudoPasswordDialog({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  State<_SudoPasswordDialog> createState() => _SudoPasswordDialogState();
}

class _SudoPasswordDialogState extends State<_SudoPasswordDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: FyrTheme.panelBgColor,
      title: Text(widget.title, style: TextStyle(color: FyrTheme.textColor)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.message,
            style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            obscureText: _obscure,
            autofocus: true,
            style: TextStyle(color: FyrTheme.textColor),
            onSubmitted: (val) => Navigator.pop(context, val),
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
                  _obscure ? Icons.visibility : Icons.visibility_off,
                  color: FyrTheme.textColorMuted,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: FyrTheme.accentColor,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Authenticate'),
        ),
      ],
    );
  }
}
