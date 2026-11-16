import 'dart:typed_data';

/// Represents a selectable hardware input channel or stereo channel pair
/// on an audio interface (e.g., Ch 1 Mono, Ch 2 Mono, Ch 1-2 Stereo).
class AudioInputChannelOption {
  final String id;
  final int channelIndex;
  final bool isStereo;
  final String label;
  final String shortLabel;

  const AudioInputChannelOption({
    required this.id,
    required this.channelIndex,
    required this.isStereo,
    required this.label,
    required this.shortLabel,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioInputChannelOption && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Builds selectable input channel options for an audio device exposing
/// [channelCount] hardware channels.
List<AudioInputChannelOption> buildInputChannelOptions(int channelCount) {
  final int count = channelCount.clamp(1, 32);
  if (count == 1) {
    return const [
      AudioInputChannelOption(
        id: 'mono:0',
        channelIndex: 0,
        isStereo: false,
        label: 'Ch 1 (Mono)',
        shortLabel: 'Ch 1',
      ),
    ];
  }

  final options = <AudioInputChannelOption>[];
  for (int pairStart = 0; pairStart + 1 < count; pairStart += 2) {
    final c1 = pairStart + 1;
    final c2 = pairStart + 2;
    options.add(
      AudioInputChannelOption(
        id: 'stereo:$pairStart',
        channelIndex: pairStart,
        isStereo: true,
        label: 'Ch $c1-$c2 (Stereo)',
        shortLabel: '$c1-$c2',
      ),
    );
  }
  for (int ch = 0; ch < count; ch++) {
    final numLabel = ch + 1;
    final String suffix = count == 2
        ? (ch == 0 ? ' (Left / Mono)' : ' (Right / Mono)')
        : ' (Mono)';
    options.add(
      AudioInputChannelOption(
        id: 'mono:$ch',
        channelIndex: ch,
        isStereo: false,
        label: 'Ch $numLabel$suffix',
        shortLabel: 'Ch $numLabel',
      ),
    );
  }
  return options;
}

/// Resolves [id] against the available options for [channelCount],
/// falling back cleanly when switching between interfaces with different channel counts.
AudioInputChannelOption resolveInputChannelOption(
  String? id,
  int channelCount,
) {
  final options = buildInputChannelOptions(channelCount);
  if (id != null) {
    for (final opt in options) {
      if (opt.id == id) return opt;
    }
  }
  return options.first;
}

/// Normalizes a platform audio input device identifier by trimming whitespace
/// and stripping surrounding quotes (such as `"..."` left by `record_linux`
/// when parsing PipeWire `node.name = "..."` properties).
String normalizeAudioInputDeviceId(String id) {
  String cleaned = id.trim();
  while (cleaned.length >= 2 &&
      ((cleaned.startsWith('"') && cleaned.endsWith('"')) ||
          (cleaned.startsWith("'") && cleaned.endsWith("'")))) {
    cleaned = cleaned.substring(1, cleaned.length - 1).trim();
  }
  return cleaned;
}

/// Resolves the hardware channel count for an input device using parsed
/// `pactl` source metadata, falling back to `.mono` / `.mono-fallback` source
/// profile naming when metadata is unavailable.
int resolveInputDeviceChannelCount(
  String deviceId,
  Map<String, int> pactlChannelMap, {
  int fallback = 2,
}) {
  final cleanId = normalizeAudioInputDeviceId(deviceId);
  if (cleanId.isNotEmpty) {
    final mapped = pactlChannelMap[cleanId] ?? pactlChannelMap[deviceId];
    if (mapped != null && mapped > 0) return mapped;
    final lower = cleanId.toLowerCase();
    if (lower.endsWith('.mono-fallback') || lower.endsWith('.mono')) {
      return 1;
    }
  }
  return fallback;
}

/// Parses `pactl list sources` output lines into a map of source Name -> channel count.
Map<String, int> parsePactlSourceChannels(Iterable<String> lines) {
  final result = <String, int>{};
  String? currentName;
  final specRegex = RegExp(r'(\d+)ch\b');

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.startsWith('Source #')) {
      currentName = null;
    } else if (line.startsWith('Name:')) {
      final name = normalizeAudioInputDeviceId(line.substring('Name:'.length));
      currentName = name.isEmpty ? null : name;
    } else if (currentName != null && line.startsWith('Sample Specification:')) {
      final match = specRegex.firstMatch(line);
      if (match != null) {
        final ch = int.tryParse(match.group(1)!);
        if (ch != null && ch > 0) {
          result[currentName] = ch;
        }
      }
    } else if (currentName != null &&
        !result.containsKey(currentName) &&
        line.startsWith('Channel Map:')) {
      final mapPart = line.substring('Channel Map:'.length).trim();
      if (mapPart.isNotEmpty) {
        final count = mapPart.split(',').where((s) => s.trim().isNotEmpty).length;
        if (count > 0) {
          result[currentName] = count;
        }
      }
    }
  }
  return result;
}

/// Extracts aligned interleaved `s16le` frames from [remainderBytes] + [rawChunk].
({Uint8List alignedFrames, Uint8List nextRemainder}) alignPcm16Frames(
  List<int> rawChunk,
  Uint8List remainderBytes, {
  required int captureChannels,
}) {
  final int ch = captureChannels.clamp(1, 32);
  final int frameBytes = ch * 2;
  final Uint8List combined;
  if (remainderBytes.isEmpty) {
    combined = rawChunk is Uint8List ? rawChunk : Uint8List.fromList(rawChunk);
  } else {
    combined = Uint8List(remainderBytes.length + rawChunk.length);
    combined.setRange(0, remainderBytes.length, remainderBytes);
    combined.setRange(remainderBytes.length, combined.length, rawChunk);
  }

  final int alignedLen = (combined.length ~/ frameBytes) * frameBytes;
  if (alignedLen == 0) {
    return (alignedFrames: Uint8List(0), nextRemainder: combined);
  }
  final aligned = alignedLen == combined.length
      ? combined
      : Uint8List.sublistView(combined, 0, alignedLen);
  final nextRem = alignedLen < combined.length
      ? Uint8List.fromList(combined.sublist(alignedLen))
      : Uint8List(0);
  return (alignedFrames: aligned, nextRemainder: nextRem);
}

/// Maps [alignedFrames] (with [captureChannels] interleaved `s16le` samples per frame)
/// into stereo (2ch) interleaved `s16le` PCM bytes according to [selection].
///
/// Mono selections center the chosen channel identically into both Left and Right.
/// Stereo selections extract `(channelIndex, channelIndex + 1)` into `(Left, Right)`.
Uint8List mapAlignedPcm16ToStereo(
  Uint8List alignedFrames, {
  required int captureChannels,
  required AudioInputChannelOption selection,
}) {
  final int srcCh = captureChannels.clamp(1, 32);
  final int frameBytes = srcCh * 2;
  final int frameCount = alignedFrames.length ~/ frameBytes;
  if (frameCount == 0) return Uint8List(0);

  final ByteData inBd = ByteData.sublistView(alignedFrames);
  final Uint8List outBytes = Uint8List(frameCount * 4);
  final ByteData outBd = ByteData.sublistView(outBytes);

  final int chL = selection.channelIndex.clamp(0, srcCh - 1);
  if (!selection.isStereo || srcCh == 1) {
    for (int f = 0; f < frameCount; f++) {
      final int s = inBd.getInt16(f * frameBytes + chL * 2, Endian.little);
      final int outOffset = f * 4;
      outBd.setInt16(outOffset, s, Endian.little);
      outBd.setInt16(outOffset + 2, s, Endian.little);
    }
  } else {
    final int chR = (chL + 1).clamp(0, srcCh - 1);
    for (int f = 0; f < frameCount; f++) {
      final int inFrameStart = f * frameBytes;
      final int l = inBd.getInt16(inFrameStart + chL * 2, Endian.little);
      final int r = inBd.getInt16(inFrameStart + chR * 2, Endian.little);
      final int outOffset = f * 4;
      outBd.setInt16(outOffset, l, Endian.little);
      outBd.setInt16(outOffset + 2, r, Endian.little);
    }
  }
  return outBytes;
}
