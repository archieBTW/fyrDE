import 'dart:io';
import 'package:flutter_soloud/flutter_soloud.dart';

/// Represents a PulseAudio / PipeWire playback sink on Linux.
class LinuxAudioSink {
  final int? index;
  final String name;
  final String description;

  const LinuxAudioSink({
    this.index,
    required this.name,
    required this.description,
  });

  String get displayName => description.isNotEmpty ? description : name;
}

/// Parses `pactl info` output and extracts the configured `Default Sink`.
String? parsePactlDefaultSink(String infoOutput) {
  for (final rawLine in infoOutput.split('\n')) {
    final line = rawLine.trim();
    if (line.startsWith('Default Sink:')) {
      final val = line.substring('Default Sink:'.length).trim();
      return val.isEmpty ? null : val;
    }
  }
  return null;
}

/// Parses `pactl list sinks` output lines into [LinuxAudioSink] entries.
List<LinuxAudioSink> parsePactlSinks(Iterable<String> lines) {
  final sinks = <LinuxAudioSink>[];
  int? curIdx;
  String? curName;
  String curDesc = '';

  void flush() {
    if (curName != null && curName!.isNotEmpty) {
      sinks.add(
        LinuxAudioSink(
          index: curIdx,
          name: curName!,
          description: curDesc,
        ),
      );
    }
    curIdx = null;
    curName = null;
    curDesc = '';
  }

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.startsWith('Sink #')) {
      flush();
      curIdx = int.tryParse(line.substring('Sink #'.length).trim());
    } else if (line.startsWith('Name:')) {
      curName = line.substring('Name:'.length).trim();
    } else if (line.startsWith('Description:')) {
      curDesc = line.substring('Description:'.length).trim();
    }
  }
  flush();
  return sinks;
}

/// Parses `pactl list sink-inputs` output lines and returns active sink-input IDs
/// belonging to [pid] (optionally excluding streams already on [targetSinkIndex]).
List<int> parsePactlSinkInputIdsForPid(
  Iterable<String> lines,
  int pid, {
  int? targetSinkIndex,
}) {
  final matches = <int>[];
  int? curInputId;
  int? curSinkIdx;
  int? curPid;

  void flush() {
    if (curInputId != null && curPid == pid) {
      if (targetSinkIndex == null || curSinkIdx != targetSinkIndex) {
        matches.add(curInputId!);
      }
    }
    curInputId = null;
    curSinkIdx = null;
    curPid = null;
  }

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.startsWith('Sink Input #')) {
      flush();
      curInputId = int.tryParse(line.substring('Sink Input #'.length).trim());
    } else if (line.startsWith('Sink:')) {
      curSinkIdx = int.tryParse(line.substring('Sink:'.length).trim());
    } else if (line.startsWith('application.process.id =')) {
      final rawVal = line
          .substring('application.process.id ='.length)
          .trim()
          .replaceAll('"', '');
      curPid = int.tryParse(rawVal);
    }
  }
  flush();
  return matches;
}

/// Matches a SoLoud [PlaybackDevice] against a Linux [LinuxAudioSink] (by exact
/// description/name or substring overlap), falling back cleanly when null.
PlaybackDevice? matchPlaybackDeviceForSink(
  List<PlaybackDevice> devices,
  LinuxAudioSink? sink,
) {
  if (devices.isEmpty) return null;
  if (sink != null) {
    final desc = sink.description.trim().toLowerCase();
    final name = sink.name.trim().toLowerCase();
    for (final d in devices) {
      final dn = d.name.trim().toLowerCase();
      if ((desc.isNotEmpty && dn == desc) || (name.isNotEmpty && dn == name)) {
        return d;
      }
    }
    for (final d in devices) {
      final dn = d.name.trim().toLowerCase();
      if (desc.isNotEmpty && (dn.contains(desc) || desc.contains(dn))) {
        return d;
      }
    }
  }
  return devices.where((d) => d.isDefault).firstOrNull ?? devices.first;
}

/// Matches a Linux [LinuxAudioSink] for a given SoLoud [PlaybackDevice].
LinuxAudioSink? matchSinkForPlaybackDevice(
  List<LinuxAudioSink> sinks,
  PlaybackDevice? device,
) {
  if (sinks.isEmpty || device == null) return null;
  final dn = device.name.trim().toLowerCase();
  if (dn.isEmpty) return null;
  for (final s in sinks) {
    if (s.description.trim().toLowerCase() == dn ||
        s.name.trim().toLowerCase() == dn) {
      return s;
    }
  }
  for (final s in sinks) {
    final sd = s.description.trim().toLowerCase();
    if (sd.isNotEmpty && (sd.contains(dn) || dn.contains(sd))) {
      return s;
    }
  }
  return null;
}

/// Helpers for syncing Sound Booth's active PulseAudio/PipeWire stream on Linux
/// with the configured system Default Sink or user-chosen sink.
class LinuxOutputRouter {
  static Future<String?> getDefaultSinkName() async {
    if (!Platform.isLinux) return null;
    try {
      final res = await Process.run('pactl', ['info']);
      if (res.exitCode != 0) return null;
      return parsePactlDefaultSink(res.stdout.toString());
    } catch (_) {
      return null;
    }
  }

  static Future<List<LinuxAudioSink>> listSinks() async {
    if (!Platform.isLinux) return const [];
    try {
      final res = await Process.run('pactl', ['list', 'sinks']);
      if (res.exitCode != 0) return const [];
      return parsePactlSinks(res.stdout.toString().split('\n'));
    } catch (_) {
      return const [];
    }
  }

  /// Moves any PipeWire / PulseAudio sink-input owned by [processId] (defaults to current [pid])
  /// onto [sinkName] so desktop routing overrides stale stream-restore pins.
  static Future<void> routeProcessAudioToSink(
    String sinkName, {
    int? targetSinkIndex,
    int? processId,
  }) async {
    if (!Platform.isLinux || sinkName.isEmpty) return;
    try {
      final res = await Process.run('pactl', ['list', 'sink-inputs']);
      if (res.exitCode != 0) return;
      final inputIds = parsePactlSinkInputIdsForPid(
        res.stdout.toString().split('\n'),
        processId ?? pid,
        targetSinkIndex: targetSinkIndex,
      );
      for (final id in inputIds) {
        try {
          await Process.run('pactl', [
            'move-sink-input',
            '$id',
            sinkName,
          ]);
        } catch (_) {}
      }
    } catch (_) {}
  }
}
