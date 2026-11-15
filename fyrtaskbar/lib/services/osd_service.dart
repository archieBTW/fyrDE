import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fyrtaskbar/fyr_theme.dart';
import 'package:fyrtaskbar/state/system_state.dart';

/// Parsed OSD notification payload sent over `~/.config/fyr/osd.sock`.
class OsdPayload {
  final String kind;
  final String label;
  final String valueText;
  final double fraction;
  final bool muted;

  const OsdPayload({
    required this.kind,
    required this.label,
    required this.valueText,
    required this.fraction,
    required this.muted,
  });
}

/// Receives volume, microphone, and brightness OSD events over a Unix socket
/// and drives the native GtkLayerShell overlay via `fyrtaskbar/osd`.
class OsdService {
  static const MethodChannel _channel = MethodChannel('fyrtaskbar/osd');
  static ServerSocket? _server;
  static Timer? _hideTimer;

  static String defaultSocketPath({String? homeOverride}) {
    final home = homeOverride ?? Platform.environment['HOME'] ?? '';
    return '$home/.config/fyr/osd.sock';
  }

  /// Parses commands of the form:
  /// - `volume <0-150> [muted]`
  /// - `mic <muted|unmuted|0|100> [muted]`
  /// - `brightness <0-100>`
  static OsdPayload? parseCommand(String raw) {
    final parts = raw.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return null;

    final kind = parts.first.toLowerCase();
    final hasMutedToken = parts.any((p) => p.toLowerCase() == 'muted');

    if (kind == 'volume') {
      final pct = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
      final clamped = pct.clamp(0, 150);
      return OsdPayload(
        kind: 'volume',
        label: hasMutedToken ? 'Muted' : 'Volume',
        valueText: hasMutedToken ? 'Muted' : '$clamped%',
        fraction: (clamped / 100.0).clamp(0.0, 1.0),
        muted: hasMutedToken,
      );
    }

    if (kind == 'mic') {
      final arg = parts.length > 1 ? parts[1].toLowerCase() : 'muted';
      final muted = hasMutedToken || arg == 'muted' || arg == '0';
      return OsdPayload(
        kind: 'mic',
        label: 'Microphone',
        valueText: muted ? 'Muted' : 'Active',
        fraction: muted ? 0.0 : 1.0,
        muted: muted,
      );
    }

    if (kind == 'brightness') {
      final pct = (parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0)
          .clamp(0, 100);
      return OsdPayload(
        kind: 'brightness',
        label: 'Brightness',
        valueText: '$pct%',
        fraction: pct / 100.0,
        muted: false,
      );
    }

    return null;
  }

  static Future<void> init({
    String? socketPath,
    Future<void> Function(String method, Map<String, dynamic>? args)? invoker,
  }) async {
    await dispose();
    final path = socketPath ?? defaultSocketPath();
    final sockFile = File(path);
    if (!sockFile.parent.existsSync()) {
      sockFile.parent.createSync(recursive: true);
    }
    if (sockFile.existsSync()) {
      sockFile.deleteSync();
    }

    try {
      _server = await ServerSocket.bind(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      _server!.listen((client) {
        client
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              (line) => _handleLine(line, invoker: invoker),
              onError: (_) {},
              onDone: () => client.destroy(),
            );
      }, onError: (_) {});
    } catch (_) {
      // Ignore socket bind failures in restricted environments.
    }
  }

  static Future<void> _handleLine(
    String line, {
    Future<void> Function(String method, Map<String, dynamic>? args)? invoker,
  }) async {
    final payload = parseCommand(line);
    if (payload == null) return;

    if (payload.kind == 'volume') {
      SystemState.volume.value = payload.fraction;
    } else if (payload.kind == 'brightness') {
      SystemState.brightness.value = payload.fraction;
    }

    final bgColor = FyrTheme.isDark
        ? const Color(0xFF141418)
        : const Color(0xFFF6F6F8);
    final args = <String, dynamic>{
      'kind': payload.kind,
      'label': payload.label,
      'valueText': payload.valueText,
      'fraction': payload.fraction,
      'muted': payload.muted,
      'bgArgb': bgColor.value,
      'textArgb': FyrTheme.textColor.value,
      'accentArgb': FyrTheme.accentColor.value,
    };

    try {
      if (invoker != null) {
        await invoker('show', args);
      } else {
        await _channel.invokeMethod('show', args);
      }
    } catch (_) {}

    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 1600), () async {
      try {
        if (invoker != null) {
          await invoker('hide', null);
        } else {
          await _channel.invokeMethod('hide');
        }
      } catch (_) {}
    });
  }

  static Future<void> dispose() async {
    _hideTimer?.cancel();
    _hideTimer = null;
    await _server?.close();
    _server = null;
  }
}
