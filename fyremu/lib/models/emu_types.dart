import 'package:flutter/services.dart';

enum ConsolePlatform {
  gb(
    id: 'gb',
    label: 'Game Boy',
    shortLabel: 'GB',
    extensions: ['.gb'],
    aspectRatio: 160 / 144,
    accent: Color(0xFF9BBC0F),
    preferredCores: ['gambatte_libretro.so', 'sameboy_libretro.so', 'mgba_libretro.so'],
  ),
  gbc(
    id: 'gbc',
    label: 'Game Boy Color',
    shortLabel: 'GBC',
    extensions: ['.gbc'],
    aspectRatio: 160 / 144,
    accent: Color(0xFFAB47BC),
    preferredCores: ['gambatte_libretro.so', 'sameboy_libretro.so', 'mgba_libretro.so'],
  ),
  gba(
    id: 'gba',
    label: 'Game Boy Advance',
    shortLabel: 'GBA',
    extensions: ['.gba'],
    aspectRatio: 240 / 160,
    accent: Color(0xFF5C6BC0),
    preferredCores: ['mgba_libretro.so', 'vba_next_libretro.so', 'gpsp_libretro.so'],
  ),
  nes(
    id: 'nes',
    label: 'NES / Famicom',
    shortLabel: 'NES',
    extensions: ['.nes', '.unf', '.unif'],
    aspectRatio: 4 / 3,
    accent: Color(0xFFEF5350),
    preferredCores: ['fceumm_libretro.so', 'nestopia_libretro.so', 'mesen_libretro.so'],
  ),
  snes(
    id: 'snes',
    label: 'SNES / Super Famicom',
    shortLabel: 'SNES',
    extensions: ['.sfc', '.smc', '.fig', '.swc'],
    aspectRatio: 4 / 3,
    accent: Color(0xFF7E57C2),
    preferredCores: ['snes9x_libretro.so', 'bsnes_libretro.so', 'mesen-s_libretro.so'],
  ),
  genesis(
    id: 'genesis',
    label: 'Sega Genesis',
    shortLabel: 'MD',
    extensions: ['.md', '.gen', '.smd'],
    aspectRatio: 4 / 3,
    accent: Color(0xFF26A69A),
    preferredCores: ['genesis_plus_gx_libretro.so', 'picodrive_libretro.so'],
  );

  final String id;
  final String label;
  final String shortLabel;
  final List<String> extensions;
  final double aspectRatio;
  final Color accent;
  final List<String> preferredCores;

  const ConsolePlatform({
    required this.id,
    required this.label,
    required this.shortLabel,
    required this.extensions,
    required this.aspectRatio,
    required this.accent,
    required this.preferredCores,
  });

  static ConsolePlatform? fromExtension(String ext) {
    final lower = ext.toLowerCase();
    for (final p in ConsolePlatform.values) {
      if (p.extensions.contains(lower)) return p;
    }
    return null;
  }

  static ConsolePlatform fromId(String id) {
    return ConsolePlatform.values.firstWhere(
      (e) => e.id == id,
      orElse: () => ConsolePlatform.snes,
    );
  }
}

/// Standard Libretro Joypad button IDs (`RETRO_DEVICE_ID_JOYPAD_*`).
enum RetroButton {
  b(0, 'B'),
  y(1, 'Y'),
  select(2, 'Select'),
  start(3, 'Start'),
  up(4, 'D-Pad Up'),
  down(5, 'D-Pad Down'),
  left(6, 'D-Pad Left'),
  right(7, 'D-Pad Right'),
  a(8, 'A'),
  x(9, 'X'),
  l(10, 'L'),
  r(11, 'R');

  final int retroId;
  final String label;
  const RetroButton(this.retroId, this.label);
}

enum GamepadInputKind { button, axisNeg, axisPos }

class GamepadSource {
  final GamepadInputKind kind;
  final int index;

  const GamepadSource({required this.kind, required this.index});

  String get displayLabel {
    switch (kind) {
      case GamepadInputKind.button:
        return 'Btn $index';
      case GamepadInputKind.axisNeg:
        return 'Axis $index −';
      case GamepadInputKind.axisPos:
        return 'Axis $index +';
    }
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'index': index,
      };

  factory GamepadSource.fromJson(Map<String, dynamic> json) {
    final kindStr = json['kind'] as String? ?? 'button';
    final kind = GamepadInputKind.values.firstWhere(
      (e) => e.name == kindStr,
      orElse: () => GamepadInputKind.button,
    );
    return GamepadSource(kind: kind, index: json['index'] as int? ?? 0);
  }
}

class InputProfile {
  final Map<RetroButton, int> keyboardMap;
  final Map<RetroButton, GamepadSource> gamepadMap;
  final int controllerPortIndex;

  InputProfile({
    required this.keyboardMap,
    required this.gamepadMap,
    this.controllerPortIndex = 0,
  });

  static InputProfile defaults() {
    return InputProfile(
      keyboardMap: {
        RetroButton.up: LogicalKeyboardKey.arrowUp.keyId,
        RetroButton.down: LogicalKeyboardKey.arrowDown.keyId,
        RetroButton.left: LogicalKeyboardKey.arrowLeft.keyId,
        RetroButton.right: LogicalKeyboardKey.arrowRight.keyId,
        RetroButton.b: LogicalKeyboardKey.keyZ.keyId,
        RetroButton.a: LogicalKeyboardKey.keyX.keyId,
        RetroButton.y: LogicalKeyboardKey.keyA.keyId,
        RetroButton.x: LogicalKeyboardKey.keyS.keyId,
        RetroButton.l: LogicalKeyboardKey.keyQ.keyId,
        RetroButton.r: LogicalKeyboardKey.keyW.keyId,
        RetroButton.start: LogicalKeyboardKey.enter.keyId,
        RetroButton.select: LogicalKeyboardKey.shiftRight.keyId,
      },
      gamepadMap: xboxPreset(),
    );
  }

  static Map<RetroButton, GamepadSource> xboxPreset() => {
        RetroButton.up: const GamepadSource(kind: GamepadInputKind.axisNeg, index: 7),
        RetroButton.down: const GamepadSource(kind: GamepadInputKind.axisPos, index: 7),
        RetroButton.left: const GamepadSource(kind: GamepadInputKind.axisNeg, index: 6),
        RetroButton.right: const GamepadSource(kind: GamepadInputKind.axisPos, index: 6),
        RetroButton.b: const GamepadSource(kind: GamepadInputKind.button, index: 0),
        RetroButton.a: const GamepadSource(kind: GamepadInputKind.button, index: 1),
        RetroButton.y: const GamepadSource(kind: GamepadInputKind.button, index: 2),
        RetroButton.x: const GamepadSource(kind: GamepadInputKind.button, index: 3),
        RetroButton.l: const GamepadSource(kind: GamepadInputKind.button, index: 4),
        RetroButton.r: const GamepadSource(kind: GamepadInputKind.button, index: 5),
        RetroButton.select: const GamepadSource(kind: GamepadInputKind.button, index: 6),
        RetroButton.start: const GamepadSource(kind: GamepadInputKind.button, index: 7),
      };

  static Map<RetroButton, GamepadSource> nintendoPreset() => {
        RetroButton.up: const GamepadSource(kind: GamepadInputKind.axisNeg, index: 7),
        RetroButton.down: const GamepadSource(kind: GamepadInputKind.axisPos, index: 7),
        RetroButton.left: const GamepadSource(kind: GamepadInputKind.axisNeg, index: 6),
        RetroButton.right: const GamepadSource(kind: GamepadInputKind.axisPos, index: 6),
        RetroButton.a: const GamepadSource(kind: GamepadInputKind.button, index: 0),
        RetroButton.b: const GamepadSource(kind: GamepadInputKind.button, index: 1),
        RetroButton.x: const GamepadSource(kind: GamepadInputKind.button, index: 2),
        RetroButton.y: const GamepadSource(kind: GamepadInputKind.button, index: 3),
        RetroButton.l: const GamepadSource(kind: GamepadInputKind.button, index: 4),
        RetroButton.r: const GamepadSource(kind: GamepadInputKind.button, index: 5),
        RetroButton.select: const GamepadSource(kind: GamepadInputKind.button, index: 8),
        RetroButton.start: const GamepadSource(kind: GamepadInputKind.button, index: 9),
      };

  static String keyLabel(int? keyId) {
    if (keyId == null) return 'Unbound';
    final key = LogicalKeyboardKey.findKeyByKeyId(keyId);
    if (key == null) return 'Key 0x${keyId.toRadixString(16)}';
    if (key == LogicalKeyboardKey.arrowUp) return '↑ Up';
    if (key == LogicalKeyboardKey.arrowDown) return '↓ Down';
    if (key == LogicalKeyboardKey.arrowLeft) return '← Left';
    if (key == LogicalKeyboardKey.arrowRight) return '→ Right';
    if (key == LogicalKeyboardKey.enter) return 'Enter';
    if (key == LogicalKeyboardKey.shiftRight) return 'R-Shift';
    if (key == LogicalKeyboardKey.shiftLeft) return 'L-Shift';
    if (key == LogicalKeyboardKey.space) return 'Space';
    return key.keyLabel.isNotEmpty ? key.keyLabel.toUpperCase() : key.debugName ?? '?';
  }

  Map<String, dynamic> toJson() => {
        'controllerPortIndex': controllerPortIndex,
        'keyboardMap': {
          for (final e in keyboardMap.entries) e.key.name: e.value,
        },
        'gamepadMap': {
          for (final e in gamepadMap.entries) e.key.name: e.value.toJson(),
        },
      };

  factory InputProfile.fromJson(Map<String, dynamic> json) {
    final def = InputProfile.defaults();
    final kbRaw = json['keyboardMap'] as Map<String, dynamic>? ?? {};
    final gpRaw = json['gamepadMap'] as Map<String, dynamic>? ?? {};

    for (final btn in RetroButton.values) {
      if (kbRaw[btn.name] is int) {
        def.keyboardMap[btn] = kbRaw[btn.name] as int;
      }
      if (gpRaw[btn.name] is Map<String, dynamic>) {
        def.gamepadMap[btn] =
            GamepadSource.fromJson(gpRaw[btn.name] as Map<String, dynamic>);
      }
    }
    return InputProfile(
      keyboardMap: def.keyboardMap,
      gamepadMap: def.gamepadMap,
      controllerPortIndex: json['controllerPortIndex'] as int? ?? 0,
    );
  }
}

class RomEntry {
  final String id;
  final String title;
  final String path;
  final ConsolePlatform platform;
  DateTime? lastPlayed;
  int playTimeSeconds;
  bool favorite;

  RomEntry({
    required this.id,
    required this.title,
    required this.path,
    required this.platform,
    this.lastPlayed,
    this.playTimeSeconds = 0,
    this.favorite = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'path': path,
        'platform': platform.id,
        'lastPlayed': lastPlayed?.toIso8601String(),
        'playTimeSeconds': playTimeSeconds,
        'favorite': favorite,
      };

  factory RomEntry.fromJson(Map<String, dynamic> json) => RomEntry(
        id: json['id'] as String? ?? json['path'] as String,
        title: json['title'] as String? ?? 'Unknown ROM',
        path: json['path'] as String,
        platform: ConsolePlatform.fromId(json['platform'] as String? ?? 'snes'),
        lastPlayed: json['lastPlayed'] != null
            ? DateTime.tryParse(json['lastPlayed'] as String)
            : null,
        playTimeSeconds: json['playTimeSeconds'] as int? ?? 0,
        favorite: json['favorite'] as bool? ?? false,
      );
}

class CoreDownloadSpec {
  final String id;
  final String name;
  final String filename;
  final List<ConsolePlatform> platforms;
  final String description;

  const CoreDownloadSpec({
    required this.id,
    required this.name,
    required this.filename,
    required this.platforms,
    required this.description,
  });

  String get buildbotZipUrl =>
      'https://buildbot.libretro.com/nightly/linux/x86_64/latest/$filename.zip';
}

const List<CoreDownloadSpec> kRecommendedCores = [
  CoreDownloadSpec(
    id: 'gambatte',
    name: 'Gambatte',
    filename: 'gambatte_libretro.so',
    platforms: [ConsolePlatform.gb, ConsolePlatform.gbc],
    description: 'Accurate Game Boy & Game Boy Color core',
  ),
  CoreDownloadSpec(
    id: 'mgba',
    name: 'mGBA',
    filename: 'mgba_libretro.so',
    platforms: [ConsolePlatform.gba, ConsolePlatform.gbc, ConsolePlatform.gb],
    description: 'Fast, cycle-accurate GBA (and GB/GBC) core',
  ),
  CoreDownloadSpec(
    id: 'fceumm',
    name: 'FCEUmm',
    filename: 'fceumm_libretro.so',
    platforms: [ConsolePlatform.nes],
    description: 'High-compatibility NES / Famicom core',
  ),
  CoreDownloadSpec(
    id: 'nestopia',
    name: 'Nestopia UE',
    filename: 'nestopia_libretro.so',
    platforms: [ConsolePlatform.nes],
    description: 'Cycle-accurate NES / Famicom core',
  ),
  CoreDownloadSpec(
    id: 'snes9x',
    name: 'Snes9x',
    filename: 'snes9x_libretro.so',
    platforms: [ConsolePlatform.snes],
    description: 'Fast, high-compatibility SNES / Super Famicom core',
  ),
  CoreDownloadSpec(
    id: 'genesis_plus_gx',
    name: 'Genesis Plus GX',
    filename: 'genesis_plus_gx_libretro.so',
    platforms: [ConsolePlatform.genesis],
    description: 'Sega Genesis / Mega Drive / Master System core',
  ),
];
