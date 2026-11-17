import 'dart:convert';
import 'dart:io';

/// Normalized metadata for an active Sway output.
class DisplayOutputInfo {
  final String name;
  final String model;
  final int x;
  final int y;
  final int width;
  final int height;
  final bool active;
  final bool focused;

  const DisplayOutputInfo({
    required this.name,
    this.model = '',
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.active = true,
    this.focused = false,
  });

  Map<String, dynamic> toMonitorArgs() => <String, dynamic>{
        'name': name,
        'model': model,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };

  bool samePlacement(DisplayOutputInfo? other) =>
      other != null &&
      name == other.name &&
      x == other.x &&
      y == other.y &&
      width == other.width &&
      height == other.height;
}

/// Parses `swaymsg -t get_outputs` JSON entries into deterministically sorted
/// active [DisplayOutputInfo] objects.
List<DisplayOutputInfo> parseSwayOutputs(List<dynamic> rawOutputs) {
  final parsed = <DisplayOutputInfo>[];
  for (final item in rawOutputs) {
    if (item is! Map) continue;
    final name = item['name']?.toString() ?? '';
    if (name.isEmpty || name == '__i3') continue;
    final rect = item['rect'];
    final int x = rect is Map ? (rect['x'] as num?)?.toInt() ?? 0 : 0;
    final int y = rect is Map ? (rect['y'] as num?)?.toInt() ?? 0 : 0;
    final int width =
        rect is Map ? (rect['width'] as num?)?.toInt() ?? 1920 : 1920;
    final int height =
        rect is Map ? (rect['height'] as num?)?.toInt() ?? 1080 : 1080;
    parsed.add(
      DisplayOutputInfo(
        name: name,
        model: item['model']?.toString() ?? '',
        x: x,
        y: y,
        width: width > 0 ? width : 1920,
        height: height > 0 ? height : 1080,
        active: item['active'] != false,
        focused: item['focused'] == true,
      ),
    );
  }

  final active = parsed.where((o) => o.active).toList();
  final list = active.isNotEmpty ? active : parsed;
  list.sort((a, b) {
    final cmpX = a.x.compareTo(b.x);
    if (cmpX != 0) return cmpX;
    final cmpY = a.y.compareTo(b.y);
    if (cmpY != 0) return cmpY;
    return a.name.compareTo(b.name);
  });
  return list;
}

/// Reads the configured primary output name from `~/.config/fyr/primary_display`
/// or Sway config output assignments.
Future<String?> readConfiguredPrimaryDisplay({String? homeOverride}) async {
  final home = homeOverride ?? Platform.environment['HOME'] ?? '';
  if (home.isEmpty) return null;

  try {
    final primaryFile = File('$home/.config/fyr/primary_display');
    if (await primaryFile.exists()) {
      final content = (await primaryFile.readAsString()).trim();
      if (content.isNotEmpty) return content;
    }
  } catch (_) {}

  for (final rel in [
    '.config/sway/conf.d/20-primary-output.conf',
    '.config/sway/config',
  ]) {
    try {
      final file = File('$home/$rel');
      if (await file.exists()) {
        final content = await file.readAsString();
        final match = RegExp(
          r'assign\s+\[app_id="(?:fyrtaskbar|fyrdock)"\]\s+output\s+([^\s]+)',
        ).firstMatch(content);
        if (match != null) return match.group(1);
      }
    } catch (_) {}
  }
  return null;
}

/// Deterministically chooses the primary display output so taskbar and dock
/// always resolve the exact same monitor regardless of transient pointer focus.
DisplayOutputInfo? resolvePrimaryOutput(
  List<DisplayOutputInfo> outputs, {
  String? preferredName,
}) {
  if (outputs.isEmpty) return null;
  if (preferredName != null && preferredName.isNotEmpty) {
    for (final out in outputs) {
      if (out.name == preferredName) return out;
    }
  }
  for (final out in outputs) {
    if (out.x == 0 && out.y == 0) return out;
  }
  return outputs.first;
}

/// Queries Sway for currently active outputs.
Future<List<DisplayOutputInfo>> getActiveSwayOutputs() async {
  try {
    final res = await Process.run('swaymsg', ['-t', 'get_outputs']);
    if (res.exitCode == 0) {
      final raw = res.stdout.toString().trim();
      if (raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return parseSwayOutputs(decoded);
        }
      }
    }
  } catch (_) {}
  return const [];
}

/// Resolves either a specific [requestedOutput] (when non-null) or the shared
/// primary display output.
Future<DisplayOutputInfo?> resolveTargetDisplayOutput({
  String? requestedOutput,
  String? homeOverride,
}) async {
  final outputs = await getActiveSwayOutputs();
  if (outputs.isEmpty) return null;
  if (requestedOutput != null && requestedOutput.isNotEmpty) {
    for (final out in outputs) {
      if (out.name == requestedOutput) return out;
    }
    return null;
  }
  final preferred = await readConfiguredPrimaryDisplay(homeOverride: homeOverride);
  return resolvePrimaryOutput(outputs, preferredName: preferred);
}
