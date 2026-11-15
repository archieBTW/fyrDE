import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Shared Unix-socket + MethodChannel controller for layer-shell overlay apps
/// (`fyrsearch`, `fyroverview`, `fyrwindowoverview`, `fyremoji`).
class OverlayWindowController {
  static const MethodChannel _channel = MethodChannel('fyr/overlay_window');

  final String appName;
  final VoidCallback? onShow;
  final VoidCallback? onHide;
  final String? socketPathOverride;

  ServerSocket? _server;
  bool _isVisible = false;

  OverlayWindowController({
    required this.appName,
    this.onShow,
    this.onHide,
    this.socketPathOverride,
  });

  bool get isVisible => _isVisible;

  String get socketPath {
    if (socketPathOverride != null) return socketPathOverride!;
    final home = Platform.environment['HOME'] ?? '';
    return '$home/.config/fyr/overlay-$appName.sock';
  }

  Future<void> start({bool initiallyVisible = false}) async {
    _isVisible = initiallyVisible;
    await stop();

    final sockFile = File(socketPath);
    if (!sockFile.parent.existsSync()) {
      sockFile.parent.createSync(recursive: true);
    }
    if (sockFile.existsSync()) {
      sockFile.deleteSync();
    }

    try {
      _server = await ServerSocket.bind(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      );
      _server!.listen((client) {
        client
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              (line) async {
                await handleCommand(line);
              },
              onError: (_) {},
              onDone: () => client.destroy(),
            );
      }, onError: (_) {});
    } catch (_) {
      // Ignore socket bind failures in restricted environments.
    }
  }

  Future<void> handleCommand(String rawCommand) async {
    final trimmed = rawCommand.trim();
    if (trimmed.isEmpty) return;
    final parts = trimmed.split(RegExp(r'\s+'));
    final cmd = parts.first.toLowerCase();
    final outputName = parts.length > 1 ? parts[1] : null;

    if (cmd == 'show') {
      await show(outputName: outputName);
    } else if (cmd == 'hide') {
      await hide();
    } else if (cmd == 'toggle') {
      if (_isVisible) {
        await hide();
      } else {
        await show(outputName: outputName);
      }
    }
  }

  Future<void> show({String? outputName}) async {
    _isVisible = true;
    try {
      await _channel.invokeMethod('show', <String, dynamic>{
        if (outputName != null && outputName.isNotEmpty) 'output': outputName,
      });
    } catch (_) {}
    onShow?.call();
  }

  Future<void> hide() async {
    _isVisible = false;
    try {
      await _channel.invokeMethod('hide');
    } catch (_) {}
    onHide?.call();
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
  }
}
