import 'dart:io';
import 'package:path/path.dart' as p;

enum FileEncryptionMethod {
  gpgAes256,
  opensslAes256,
}

class CryptoOperationResult {
  final bool ok;
  final String message;
  final String? outputPath;

  const CryptoOperationResult({
    required this.ok,
    required this.message,
    this.outputPath,
  });
}

class CryptoService {
  static bool isEncryptedFile(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.gpg') ||
        lower.endsWith('.pgp') ||
        lower.endsWith('.asc') ||
        lower.endsWith('.enc');
  }

  static String defaultEncryptedOutputPath({
    required List<String> paths,
    required String destinationDir,
    required FileEncryptionMethod method,
  }) {
    final ext = method == FileEncryptionMethod.gpgAes256 ? '.gpg' : '.enc';
    if (paths.length == 1) {
      final single = paths.first;
      final isDir = FileSystemEntity.isDirectorySync(single);
      final base = p.basename(single);
      final name = isDir ? '$base.tar$ext' : '$base$ext';
      return _uniquePath(p.join(destinationDir, name));
    }
    return _uniquePath(p.join(destinationDir, 'encrypted_bundle.tar$ext'));
  }

  static String defaultDecryptedOutputPath(String encryptedPath, String destinationDir) {
    var name = p.basename(encryptedPath);
    final lower = name.toLowerCase();
    for (final suffix in ['.gpg', '.pgp', '.asc', '.enc']) {
      if (lower.endsWith(suffix)) {
        name = name.substring(0, name.length - suffix.length);
        break;
      }
    }
    if (name.isEmpty) name = 'decrypted_output';
    return _uniquePath(p.join(destinationDir, name));
  }

  static String _uniquePath(String desiredPath) {
    if (!File(desiredPath).existsSync() && !Directory(desiredPath).existsSync()) {
      return desiredPath;
    }
    final dir = p.dirname(desiredPath);
    final base = p.basename(desiredPath);
    int counter = 1;
    while (true) {
      final candidate = p.join(dir, '$counter-$base');
      if (!File(candidate).existsSync() && !Directory(candidate).existsSync()) {
        return candidate;
      }
      counter++;
    }
  }

  static Future<CryptoOperationResult> encryptPaths({
    required List<String> paths,
    required String destinationDir,
    required String passphrase,
    FileEncryptionMethod method = FileEncryptionMethod.gpgAes256,
    bool deleteOriginals = false,
    String? customOutputName,
  }) async {
    if (paths.isEmpty) {
      return const CryptoOperationResult(ok: false, message: 'No items selected.');
    }
    if (passphrase.isEmpty) {
      return const CryptoOperationResult(ok: false, message: 'Passphrase cannot be empty.');
    }

    final needsTar = paths.length > 1 || FileSystemEntity.isDirectorySync(paths.first);
    final ext = method == FileEncryptionMethod.gpgAes256 ? '.gpg' : '.enc';

    String outputPath;
    if (customOutputName != null && customOutputName.trim().isNotEmpty) {
      var trimmed = customOutputName.trim();
      if (needsTar && !trimmed.toLowerCase().endsWith('.tar$ext') && !trimmed.toLowerCase().endsWith(ext)) {
        trimmed = '$trimmed.tar$ext';
      } else if (!needsTar && !trimmed.toLowerCase().endsWith(ext)) {
        trimmed = '$trimmed$ext';
      }
      outputPath = _uniquePath(p.join(destinationDir, trimmed));
    } else {
      outputPath = defaultEncryptedOutputPath(
        paths: paths,
        destinationDir: destinationDir,
        method: method,
      );
    }

    Directory? tmpDir;
    try {
      String inputFilePath;
      if (needsTar) {
        tmpDir = await Directory.systemTemp.createTemp('fyr_crypt_tar_');
        final tarPath = p.join(tmpDir.path, 'bundle.tar');
        final parentDir = p.dirname(paths.first);
        final relNames = paths.map((e) => p.relative(e, from: parentDir)).toList();
        final tarRes = await Process.run(
          'tar',
          ['-cf', tarPath, '-C', parentDir, ...relNames],
        );
        if (tarRes.exitCode != 0) {
          final err = tarRes.stderr.toString().trim();
          return CryptoOperationResult(
            ok: false,
            message: err.isNotEmpty ? 'Archive step failed: $err' : 'Failed to bundle files before encryption.',
          );
        }
        inputFilePath = tarPath;
      } else {
        inputFilePath = paths.first;
      }

      tmpDir ??= await Directory.systemTemp.createTemp('fyr_crypt_pass_');
      await Process.run('chmod', ['700', tmpDir.path]);
      final passFile = File(p.join(tmpDir.path, 'pass'));
      await passFile.writeAsString(passphrase, flush: true);
      await Process.run('chmod', ['600', passFile.path]);

      late ProcessResult res;
      if (method == FileEncryptionMethod.gpgAes256) {
        res = await Process.run('gpg', [
          '--batch',
          '--yes',
          '--pinentry-mode',
          'loopback',
          '--symmetric',
          '--cipher-algo',
          'AES256',
          '--passphrase-file',
          passFile.path,
          '-o',
          outputPath,
          inputFilePath,
        ]);
      } else {
        res = await Process.run('openssl', [
          'enc',
          '-aes-256-cbc',
          '-pbkdf2',
          '-iter',
          '100000',
          '-salt',
          '-pass',
          'file:${passFile.path}',
          '-in',
          inputFilePath,
          '-out',
          outputPath,
        ]);
      }

      if (res.exitCode != 0) {
        try {
          if (File(outputPath).existsSync()) File(outputPath).deleteSync();
        } catch (_) {}
        final err = res.stderr.toString().trim();
        return CryptoOperationResult(
          ok: false,
          message: err.isNotEmpty ? err : 'Encryption failed (exit ${res.exitCode}).',
        );
      }

      if (deleteOriginals) {
        for (final src in paths) {
          try {
            if (FileSystemEntity.isDirectorySync(src)) {
              Directory(src).deleteSync(recursive: true);
            } else if (File(src).existsSync()) {
              File(src).deleteSync();
            }
          } catch (_) {}
        }
      }

      return CryptoOperationResult(
        ok: true,
        message: 'Encrypted to ${p.basename(outputPath)}',
        outputPath: outputPath,
      );
    } catch (e) {
      return CryptoOperationResult(ok: false, message: 'Encryption error: $e');
    } finally {
      try {
        if (tmpDir != null && tmpDir.existsSync()) {
          await tmpDir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  static Future<CryptoOperationResult> decryptFile({
    required String encryptedPath,
    required String destinationDir,
    required String passphrase,
    bool deleteEncrypted = false,
  }) async {
    if (passphrase.isEmpty) {
      return const CryptoOperationResult(ok: false, message: 'Passphrase cannot be empty.');
    }
    if (!File(encryptedPath).existsSync()) {
      return const CryptoOperationResult(ok: false, message: 'Encrypted file not found.');
    }

    final lower = encryptedPath.toLowerCase();
    final isOpenSsl = lower.endsWith('.enc');
    final strippedOut = defaultDecryptedOutputPath(encryptedPath, destinationDir);
    final isTarBundle = strippedOut.toLowerCase().endsWith('.tar') ||
        strippedOut.toLowerCase().endsWith('.tgz') ||
        strippedOut.toLowerCase().endsWith('.tar.gz');

    Directory? tmpDir;
    try {
      tmpDir = await Directory.systemTemp.createTemp('fyr_decrypt_');
      await Process.run('chmod', ['700', tmpDir.path]);
      final passFile = File(p.join(tmpDir.path, 'pass'));
      await passFile.writeAsString(passphrase, flush: true);
      await Process.run('chmod', ['600', passFile.path]);

      final tempOut = isTarBundle ? p.join(tmpDir.path, 'decrypted.tar') : strippedOut;

      late ProcessResult res;
      if (isOpenSsl) {
        res = await Process.run('openssl', [
          'enc',
          '-d',
          '-aes-256-cbc',
          '-pbkdf2',
          '-iter',
          '100000',
          '-pass',
          'file:${passFile.path}',
          '-in',
          encryptedPath,
          '-out',
          tempOut,
        ]);
      } else {
        res = await Process.run('gpg', [
          '--batch',
          '--yes',
          '--pinentry-mode',
          'loopback',
          '--passphrase-file',
          passFile.path,
          '-o',
          tempOut,
          '-d',
          encryptedPath,
        ]);
      }

      if (res.exitCode != 0) {
        try {
          if (File(tempOut).existsSync()) File(tempOut).deleteSync();
        } catch (_) {}
        final rawErr = res.stderr.toString().trim();
        final errLower = rawErr.toLowerCase();
        final msg = (errLower.contains('bad decrypt') ||
                errLower.contains('decryption failed') ||
                errLower.contains('bad session key'))
            ? 'Incorrect passphrase or corrupted file.'
            : (rawErr.isNotEmpty ? rawErr : 'Decryption failed.');
        return CryptoOperationResult(ok: false, message: msg);
      }

      String finalTarget = strippedOut;
      if (isTarBundle) {
        final tarArgs = strippedOut.toLowerCase().endsWith('.tar')
            ? ['-xf', tempOut, '-C', destinationDir]
            : ['-xzf', tempOut, '-C', destinationDir];
        final tarRes = await Process.run('tar', tarArgs);
        if (tarRes.exitCode != 0) {
          final err = tarRes.stderr.toString().trim();
          return CryptoOperationResult(
            ok: false,
            message: err.isNotEmpty ? 'Decrypted, but failed to extract archive: $err' : 'Failed to extract decrypted archive.',
          );
        }
        finalTarget = destinationDir;
      }

      if (deleteEncrypted) {
        try {
          File(encryptedPath).deleteSync();
        } catch (_) {}
      }

      return CryptoOperationResult(
        ok: true,
        message: isTarBundle
            ? 'Decrypted and extracted into ${p.basename(destinationDir)}'
            : 'Decrypted to ${p.basename(finalTarget)}',
        outputPath: finalTarget,
      );
    } catch (e) {
      return CryptoOperationResult(ok: false, message: 'Decryption error: $e');
    } finally {
      try {
        if (tmpDir != null && tmpDir.existsSync()) {
          await tmpDir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }
}
