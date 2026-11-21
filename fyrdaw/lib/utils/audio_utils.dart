import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:fyrdaw/models/midi_note.dart';
import 'package:fyrdaw/utils/pitch_detector.dart';
import 'package:fyrdaw/wav_writer.dart';

const int _kWaveformIsolateByteThreshold = 524288;

Future<Uint8List?> _readPathOrAssetBytes(String path) async {
  if (path.startsWith('assets/')) {
    try {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }
  final file = File(path);
  if (!file.existsSync()) return null;
  return await file.readAsBytes();
}

Uint8List? _reverseWavBytesSync(Uint8List bytes) {
  if (bytes.length < 44) return null;

  int fmtOffset = 12;
  while (fmtOffset < bytes.length - 8) {
    String chunkId = String.fromCharCodes(
      bytes.sublist(fmtOffset, fmtOffset + 4),
    );
    if (chunkId == 'fmt ') break;
    int chunkSize =
        bytes[fmtOffset + 4] |
        (bytes[fmtOffset + 5] << 8) |
        (bytes[fmtOffset + 6] << 16) |
        (bytes[fmtOffset + 7] << 24);
    fmtOffset += 8 + chunkSize;
  }

  int numChannels = bytes[fmtOffset + 10] | (bytes[fmtOffset + 11] << 8);
  int bitsPerSample = bytes[fmtOffset + 22] | (bytes[fmtOffset + 23] << 8);
  int bytesPerFrame = numChannels * (bitsPerSample ~/ 8);
  if (bytesPerFrame <= 0) bytesPerFrame = 2;

  int dataOffset = 12;
  int dataSize = 0;
  while (dataOffset < bytes.length - 8) {
    String chunkId = String.fromCharCodes(
      bytes.sublist(dataOffset, dataOffset + 4),
    );
    int chunkSize =
        bytes[dataOffset + 4] |
        (bytes[dataOffset + 5] << 8) |
        (bytes[dataOffset + 6] << 16) |
        (bytes[dataOffset + 7] << 24);
    if (chunkId == 'data') {
      dataSize = chunkSize;
      dataOffset += 8;
      break;
    }
    dataOffset += 8 + chunkSize;
  }

  if (dataOffset >= bytes.length || dataSize == 0) return null;
  if (dataOffset + dataSize > bytes.length) {
    dataSize = bytes.length - dataOffset;
  }

  Uint8List newBytes = Uint8List.fromList(bytes);
  int numFrames = dataSize ~/ bytesPerFrame;

  for (int i = 0; i < numFrames ~/ 2; i++) {
    int srcIdx = dataOffset + i * bytesPerFrame;
    int dstIdx = dataOffset + (numFrames - 1 - i) * bytesPerFrame;
    for (int b = 0; b < bytesPerFrame; b++) {
      if (dstIdx + b < newBytes.length && srcIdx + b < newBytes.length) {
        int temp = newBytes[srcIdx + b];
        newBytes[srcIdx + b] = newBytes[dstIdx + b];
        newBytes[dstIdx + b] = temp;
      }
    }
  }
  return newBytes;
}

Future<void> reverseWavFile(String inputPath, String outputPath) async {
  if (inputPath.startsWith('assets/')) {
    final bytes = await _readPathOrAssetBytes(inputPath);
    if (bytes == null || bytes.length < 44) return;
    await Isolate.run(() {
      final reversed = _reverseWavBytesSync(bytes);
      if (reversed != null) {
        File(outputPath).writeAsBytesSync(reversed);
      }
    });
    return;
  }
  await Isolate.run(() {
    final file = File(inputPath);
    if (!file.existsSync()) return;
    final bytes = file.readAsBytesSync();
    final reversed = _reverseWavBytesSync(bytes);
    if (reversed != null) {
      File(outputPath).writeAsBytesSync(reversed);
    }
  });
}

/// Pure, isolate-safe peak extraction from raw WAV [bytes] into [chunks] bins.
List<double>? extractWavWaveformFromBytes(Uint8List bytes, int chunks) {
  try {
    if (bytes.length < 44) return null;

    int fmtOffset = 12;
    int bytesPerFrame = 2;
    while (fmtOffset < bytes.length - 8) {
      String chunkId = String.fromCharCodes(
        bytes.sublist(fmtOffset, fmtOffset + 4),
      );
      if (chunkId == 'fmt ') {
        int numChannels = bytes[fmtOffset + 10] | (bytes[fmtOffset + 11] << 8);
        int bitsPerSample =
            bytes[fmtOffset + 22] | (bytes[fmtOffset + 23] << 8);
        bytesPerFrame = numChannels * (bitsPerSample ~/ 8);
        if (bytesPerFrame <= 0) bytesPerFrame = 2;
        break;
      }
      int chunkSize =
          bytes[fmtOffset + 4] |
          (bytes[fmtOffset + 5] << 8) |
          (bytes[fmtOffset + 6] << 16) |
          (bytes[fmtOffset + 7] << 24);
      fmtOffset += 8 + chunkSize;
    }

    int dataOffset = 12;
    int dataSize = 0;
    while (dataOffset < bytes.length - 8) {
      String chunkId = String.fromCharCodes(
        bytes.sublist(dataOffset, dataOffset + 4),
      );
      int chunkSize =
          bytes[dataOffset + 4] |
          (bytes[dataOffset + 5] << 8) |
          (bytes[dataOffset + 6] << 16) |
          (bytes[dataOffset + 7] << 24);
      if (chunkId == 'data') {
        dataSize = chunkSize;
        dataOffset += 8;
        break;
      }
      dataOffset += 8 + chunkSize;
    }

    if (dataSize == 0 || dataOffset >= bytes.length) return null;
    if (dataOffset + dataSize > bytes.length) {
      dataSize = bytes.length - dataOffset;
    }

    int numFrames = dataSize ~/ bytesPerFrame;
    if (numFrames <= 0) return null;

    int framesPerChunk = numFrames ~/ chunks;
    if (framesPerChunk <= 0) framesPerChunk = 1;
    int actualChunks = numFrames < chunks ? numFrames : chunks;

    List<double> data = [];
    for (int i = 0; i < actualChunks; i++) {
      double maxAmp = 0;
      for (int j = 0; j < framesPerChunk; j++) {
        int frameIdx = i * framesPerChunk + j;
        int index = dataOffset + frameIdx * bytesPerFrame;
        if (index + 1 < bytes.length) {
          int sample = bytes[index] | (bytes[index + 1] << 8);
          if (sample > 32767) sample -= 65536;
          double amp = sample.abs() / 32768.0;
          if (amp > maxAmp) maxAmp = amp;
        }
      }
      data.add(maxAmp);
    }
    return data;
  } catch (e) {
    return null;
  }
}

List<double>? _extractWavWaveformFromDiskSync(String path, int chunks) {
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    return extractWavWaveformFromBytes(file.readAsBytesSync(), chunks);
  } catch (_) {
    return null;
  }
}

Future<List<double>?> extractWavWaveform(String path, int chunks) async {
  try {
    if (path.startsWith('assets/')) {
      final bytes = await _readPathOrAssetBytes(path);
      if (bytes == null || bytes.length < 44) return null;
      if (bytes.length >= _kWaveformIsolateByteThreshold) {
        return Isolate.run(() => extractWavWaveformFromBytes(bytes, chunks));
      }
      return extractWavWaveformFromBytes(bytes, chunks);
    }
    final file = File(path);
    if (!file.existsSync()) return null;
    if (file.lengthSync() >= _kWaveformIsolateByteThreshold) {
      return Isolate.run(() => _extractWavWaveformFromDiskSync(path, chunks));
    }
    return _extractWavWaveformFromDiskSync(path, chunks);
  } catch (e) {
    return null;
  }
}

class DecodedWav {
  final int sampleRate;
  final int channels;
  final Float64List left;
  final Float64List right;

  DecodedWav({
    required this.sampleRate,
    required this.channels,
    required this.left,
    required this.right,
  });

  int get frameCount => left.length;
  double get durationSeconds => sampleRate > 0 ? frameCount / sampleRate : 0.0;
}

/// Decodes a 16-bit or 24-bit or 32-bit float PCM WAV byte buffer into stereo Float64 samples.
DecodedWav? decodeWavBytes(Uint8List bytes) {
  if (bytes.length < 44) return null;
  final riff = String.fromCharCodes(bytes.sublist(0, 4));
  final wave = String.fromCharCodes(bytes.sublist(8, 12));
  if (riff != 'RIFF' || wave != 'WAVE') return null;

  int offset = 12;
  int audioFormat = 1;
  int numChannels = 2;
  int sampleRate = 44100;
  int bitsPerSample = 16;
  int dataOffset = -1;
  int dataSize = 0;

  while (offset <= bytes.length - 8) {
    final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final chunkSize =
        bytes[offset + 4] |
        (bytes[offset + 5] << 8) |
        (bytes[offset + 6] << 16) |
        (bytes[offset + 7] << 24);
    final payloadStart = offset + 8;

    if (chunkId == 'fmt ' && payloadStart + 16 <= bytes.length) {
      audioFormat = bytes[payloadStart] | (bytes[payloadStart + 1] << 8);
      numChannels = bytes[payloadStart + 2] | (bytes[payloadStart + 3] << 8);
      sampleRate =
          bytes[payloadStart + 4] |
          (bytes[payloadStart + 5] << 8) |
          (bytes[payloadStart + 6] << 16) |
          (bytes[payloadStart + 7] << 24);
      bitsPerSample = bytes[payloadStart + 14] | (bytes[payloadStart + 15] << 8);
    } else if (chunkId == 'data') {
      dataOffset = payloadStart;
      dataSize = chunkSize;
      break;
    }

    int next = payloadStart + chunkSize + (chunkSize.isOdd ? 1 : 0);
    if (next <= offset) break;
    offset = next;
  }

  if (dataOffset < 0 || dataOffset >= bytes.length || numChannels <= 0) {
    return null;
  }
  if (dataOffset + dataSize > bytes.length) {
    dataSize = bytes.length - dataOffset;
  }

  final bytesPerSample = (bitsPerSample ~/ 8).clamp(1, 4);
  final bytesPerFrame = numChannels * bytesPerSample;
  if (bytesPerFrame <= 0) return null;
  final numFrames = dataSize ~/ bytesPerFrame;
  if (numFrames <= 0) return null;

  final left = Float64List(numFrames);
  final right = Float64List(numFrames);
  final bd = ByteData.sublistView(bytes);

  double readSample(int bytePos) {
    if (audioFormat == 3 && bitsPerSample == 32 && bytePos + 4 <= bytes.length) {
      return bd.getFloat32(bytePos, Endian.little).toDouble();
    }
    if (bitsPerSample == 32 && bytePos + 4 <= bytes.length) {
      return bd.getInt32(bytePos, Endian.little) / 2147483648.0;
    }
    if (bitsPerSample == 16 && bytePos + 2 <= bytes.length) {
      return bd.getInt16(bytePos, Endian.little) / 32768.0;
    }
    if (bitsPerSample == 24 && bytePos + 3 <= bytes.length) {
      int v = bytes[bytePos] | (bytes[bytePos + 1] << 8) | (bytes[bytePos + 2] << 16);
      if ((v & 0x800000) != 0) v -= 0x1000000;
      return v / 8388608.0;
    }
    if (bitsPerSample == 8 && bytePos < bytes.length) {
      return (bytes[bytePos] - 128) / 128.0;
    }
    return 0.0;
  }

  for (int i = 0; i < numFrames; i++) {
    final framePos = dataOffset + i * bytesPerFrame;
    final l = readSample(framePos);
    final r = numChannels >= 2 ? readSample(framePos + bytesPerSample) : l;
    left[i] = l;
    right[i] = r;
  }

  return DecodedWav(
    sampleRate: sampleRate,
    channels: numChannels,
    left: left,
    right: right,
  );
}

DecodedWav? decodeWavFileSync(String path) {
  try {
    final f = File(path);
    if (!f.existsSync()) return null;
    final bytes = f.readAsBytesSync();
    return decodeWavBytes(bytes);
  } catch (_) {
    return null;
  }
}

Future<DecodedWav?> decodeWavFile(String path) async {
  try {
    final f = File(path);
    if (!f.existsSync()) return null;
    final bytes = await f.readAsBytes();
    return decodeWavBytes(bytes);
  } catch (_) {
    return null;
  }
}

/// Detects transient onset slices as normalized [start, end] pairs in 0.0..1.0.
Future<List<(double, double)>> detectAudioTransients(
  String path, {
  int maxSlices = 16,
  double sensitivity = 0.25,
}) {
  return Isolate.run(() {
    final wav = decodeWavFileSync(path);
    if (wav == null || wav.frameCount == 0) return <(double, double)>[];
    return detectTransientsFromSamples(
      wav.left,
      wav.right,
      wav.sampleRate,
      maxSlices: maxSlices,
      sensitivity: sensitivity,
    );
  });
}

List<(double, double)> detectTransientsFromSamples(
  Float64List left,
  Float64List right,
  int sampleRate, {
  int maxSlices = 16,
  double sensitivity = 0.25,
}) {
  final total = left.length;
  if (total == 0) return [];

  final int windowFrames = (sampleRate * 0.015).round().clamp(64, 4096);
  final int minGapFrames = (sampleRate * 0.075).round().clamp(windowFrames, total);
  final int numWindows = (total / windowFrames).ceil();
  if (numWindows <= 1) return [(0.0, 1.0)];

  final energies = Float64List(numWindows);
  double maxEnergy = 0.0;
  for (int w = 0; w < numWindows; w++) {
    final start = w * windowFrames;
    final end = (start + windowFrames).clamp(0, total);
    double sum = 0.0;
    for (int i = start; i < end; i++) {
      final mono = 0.5 * (left[i].abs() + right[i].abs());
      sum += mono;
    }
    final avg = sum / (end - start);
    energies[w] = avg;
    if (avg > maxEnergy) maxEnergy = avg;
  }

  if (maxEnergy <= 1e-6) return [(0.0, 1.0)];

  final threshold = maxEnergy * sensitivity.clamp(0.05, 0.8);
  final List<int> onsets = [0];
  int lastOnsetFrame = 0;

  for (int w = 1; w < numWindows; w++) {
    final framePos = w * windowFrames;
    if (framePos - lastOnsetFrame < minGapFrames) continue;
    final prev = energies[w - 1];
    final curr = energies[w];
    if (curr > threshold && curr > prev * 1.45) {
      onsets.add(framePos);
      lastOnsetFrame = framePos;
      if (onsets.length >= maxSlices) break;
    }
  }

  // If few transients detected, fall back to even beat-grid slices up to 8 slices
  if (onsets.length <= 1) {
    final sliceCount = maxSlices.clamp(1, 8);
    return List.generate(
      sliceCount,
      (i) => (i / sliceCount, (i + 1) / sliceCount),
    );
  }

  final List<(double, double)> slices = [];
  for (int i = 0; i < onsets.length; i++) {
    final s = onsets[i] / total;
    final e = (i + 1 < onsets.length ? onsets[i + 1] : total) / total;
    if (e > s + 0.005) {
      slices.add((s.clamp(0.0, 1.0), e.clamp(0.0, 1.0)));
    }
  }
  return slices;
}

/// Writes a peak-normalized copy of [inputPath] scaled to [targetPeak] (default -1 dBFS)
/// and returns the output path, or null if silent/unreadable.
/// Executes on a background [Isolate] to avoid blocking the UI thread.
Future<String?> normalizeWavPeak(
  String inputPath, {
  String? outPath,
  double targetPeak = 0.89,
}) {
  return Isolate.run(() {
    final wav = decodeWavFileSync(inputPath);
    if (wav == null || wav.frameCount == 0) return null;

    double peak = 0.0;
    for (int i = 0; i < wav.frameCount; i++) {
      final al = wav.left[i].abs();
      final ar = wav.right[i].abs();
      if (al > peak) peak = al;
      if (ar > peak) peak = ar;
    }
    if (peak <= 1e-6) return null;

    final gain = targetPeak / peak;
    final target =
        outPath ??
        inputPath.replaceFirst(
          RegExp(r'\.wav$', caseSensitive: false),
          '_norm.wav',
        );
    final writer = WavWriter(target, sampleRate: wav.sampleRate, channels: 2);
    final outPcm = Int16List(wav.frameCount * 2);
    for (int i = 0; i < wav.frameCount; i++) {
      outPcm[i * 2] =
          (wav.left[i] * gain * 32767.0).round().clamp(-32768, 32767);
      outPcm[i * 2 + 1] =
          (wav.right[i] * gain * 32767.0).round().clamp(-32768, 32767);
    }
    writer.write(ByteData.view(outPcm.buffer).buffer.asUint8List());
    writer.close();
    return target;
  });
}

/// Scans decoded PCM to split non-silent regions (returning normalized 0..1 ranges)
/// for "Strip Silence" editing. Executes on a background [Isolate].
Future<List<(double, double)>> detectAudioNonSilentRanges(
  String inputPath, {
  double threshold = 0.025,
  double minSilenceSec = 0.12,
}) {
  return Isolate.run(() {
    final wav = decodeWavFileSync(inputPath);
    if (wav == null || wav.frameCount == 0) return <(double, double)>[];
    final sr = wav.sampleRate;
    final total = wav.frameCount;
    final win = (sr * 0.02).round().clamp(64, 2048);
    final minSilentWins = max(1, (minSilenceSec / 0.02).round());

    final List<bool> active = [];
    for (int start = 0; start < total; start += win) {
      final end = min(total, start + win);
      double pk = 0.0;
      for (int i = start; i < end; i++) {
        final a = max(wav.left[i].abs(), wav.right[i].abs());
        if (a > pk) pk = a;
      }
      active.add(pk >= threshold);
    }

    // Bridge brief dips shorter than minSilentWins
    int silentRun = 0;
    for (int i = 0; i < active.length; i++) {
      if (!active[i]) {
        silentRun++;
      } else {
        if (silentRun > 0 && silentRun < minSilentWins && i - silentRun > 0) {
          for (int k = i - silentRun; k < i; k++) {
            active[k] = true;
          }
        }
        silentRun = 0;
      }
    }

    final segments = <(double, double)>[];
    int? segStart;
    for (int i = 0; i < active.length; i++) {
      if (active[i] && segStart == null) {
        segStart = i;
      } else if (!active[i] && segStart != null) {
        final sFrac = ((segStart * win) / total).clamp(0.0, 1.0);
        final eFrac = min(total, i * win) / total;
        if (eFrac > sFrac + 0.01) segments.add((sFrac, eFrac));
        segStart = null;
      }
    }
    if (segStart != null) {
      final sFrac = ((segStart * win) / total).clamp(0.0, 1.0);
      if (1.0 > sFrac + 0.01) segments.add((sFrac, 1.0));
    }
    return segments;
  });
}

/// Estimates integrated LUFS from a decoded WAV file on a background [Isolate].
Future<double> estimateWavIntegratedLufs(String filePath) {
  return Isolate.run(() {
    final wav = decodeWavFileSync(filePath);
    if (wav == null || wav.frameCount == 0) return -60.0;
    double sumSq = 0.0;
    for (int i = 0; i < wav.frameCount; i++) {
      final mono = 0.5 * (wav.left[i] + wav.right[i]);
      sumSq += mono * mono;
    }
    final meanSq = sumSq / wav.frameCount;
    if (meanSq <= 1e-8) return -60.0;
    return (-0.691 + 10.0 * (log(meanSq) / ln10)).clamp(-60.0, 0.0);
  });
}

/// Transcribes a monophonic audio WAV file into quantized/merged [MidiNote]s using
/// [detectPitchHz] across sliding analysis windows on a background [Isolate].
Future<List<MidiNote>> extractMelodyMidiNotes(
  String filePath,
  double clipLength, {
  double stepSec = 0.08,
  double windowSec = 0.10,
}) {
  if (clipLength <= 0) return Future.value(<MidiNote>[]);
  return Isolate.run(() {
    final wav = decodeWavFileSync(filePath);
    if (wav == null || wav.frameCount == 0) return <MidiNote>[];
    final sr = wav.sampleRate;
    final stepFrames = max(512, (sr * stepSec).round());
    final winFrames = max(1024, (sr * windowSec).round());

    final notes = <MidiNote>[];
    int? curMidi;
    double curStart = 0.0;
    double curRms = 0.0;
    int curFrames = 0;

    for (int pos = 0; pos + winFrames <= wav.frameCount; pos += stepFrames) {
      final buf = Float64List(winFrames);
      double sumSq = 0.0;
      for (int i = 0; i < winFrames; i++) {
        final m = 0.5 * (wav.left[pos + i] + wav.right[pos + i]);
        buf[i] = m;
        sumSq += m * m;
      }
      final rms = sqrt(sumSq / winFrames);
      final res = detectPitchHz(buf, sr);
      final midi = (res != null && res.confidence > 0.55) ? res.midiNote : null;
      final tFrac = pos / wav.frameCount;
      final tPos = tFrac * clipLength;

      if (midi != null && midi == curMidi) {
        curRms += rms;
        curFrames++;
      } else {
        if (curMidi != null) {
          final len = (tPos - curStart).clamp(4.0, clipLength - curStart);
          final avgRms = curRms / max(1, curFrames);
          final vel = (avgRms * 260.0).round().clamp(45, 127);
          notes.add(
            MidiNote(pitch: curMidi, start: curStart, length: len, velocity: vel),
          );
        }
        curMidi = midi;
        curStart = tPos;
        curRms = midi != null ? rms : 0.0;
        curFrames = midi != null ? 1 : 0;
      }
    }
    if (curMidi != null) {
      final len = (clipLength - curStart).clamp(4.0, clipLength);
      final avgRms = curRms / max(1, curFrames);
      final vel = (avgRms * 260.0).round().clamp(45, 127);
      notes.add(
        MidiNote(pitch: curMidi, start: curStart, length: len, velocity: vel),
      );
    }
    return notes;
  });
}

/// Adds subtle organic timing & velocity micro-variation to a MIDI clip's notes.
void humanizeMidiNotes(
  List<MidiNote> notes, {
  double timingJitterPx = 4.0,
  int velocityJitter = 12,
  int seed = 1337,
}) {
  final rng = Random(seed);
  for (final n in notes) {
    final dt = (rng.nextDouble() * 2.0 - 1.0) * timingJitterPx;
    final dv = ((rng.nextDouble() * 2.0 - 1.0) * velocityJitter).round();
    n.start = max(0.0, n.start + dt);
    n.velocity = (n.velocity + dv).clamp(25, 127);
  }
}

/// Snaps [notes] subtly toward normalized transient anchors extracted from an audio groove.
void applyGrooveToMidiNotes(
  List<MidiNote> notes,
  List<(double, double)> transients,
  double clipLength, {
  double strength = 0.75,
}) {
  if (transients.isEmpty || clipLength <= 0) return;
  final anchors = transients.map((t) => t.$1 * clipLength).toList();
  for (final n in notes) {
    double bestAnchor = n.start;
    double bestDist = double.infinity;
    for (final a in anchors) {
      final d = (n.start - a).abs();
      if (d < bestDist) {
        bestDist = d;
        bestAnchor = a;
      }
    }
    if (bestDist < clipLength * 0.25) {
      n.start = max(0.0, n.start + (bestAnchor - n.start) * strength.clamp(0.0, 1.0));
    }
  }
}
