import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:fyrdaw/utils/audio_utils.dart';

/// Pure-Dart stereo WSOLA (Waveform Similarity Overlap-Add) time-scaler and
/// cubic-interpolation pitch shifter, allowing independent tempo stretching and
/// semitone pitch shifting for both offline mixdowns and live playback caching.
class TimeStretchEngine {
  static Float64List _hannWindow(int length) {
    final win = Float64List(length);
    if (length <= 1) {
      if (length == 1) win[0] = 1.0;
      return win;
    }
    for (int i = 0; i < length; i++) {
      win[i] = 0.5 * (1.0 - cos(2.0 * pi * i / (length - 1)));
    }
    return win;
  }

  /// Changes duration by [timeScale] (> 1.0 makes audio longer/slower,
  /// < 1.0 makes audio shorter/faster) while preserving pitch.
  static Float64List timeScaleMono(
    List<double> input, {
    required int sampleRate,
    required double timeScale,
  }) {
    if (input.isEmpty) return Float64List(0);
    if ((timeScale - 1.0).abs() < 0.002) {
      return Float64List.fromList(input);
    }

    final int inLen = input.length;
    final int outLen = max(1, (inLen * timeScale).round());
    // ~36 ms frame gives clean bass tracking while preserving percussive clarity
    final int winSize = max(128, min(inLen, (sampleRate * 0.036).round()));
    final int synthesisHop = max(32, winSize ~/ 3);
    final int searchRadius = max(16, (sampleRate * 0.008).round());
    final Float64List win = _hannWindow(winSize);

    final Float64List output = Float64List(outLen + winSize);
    final Float64List normBuf = Float64List(outLen + winSize);

    // Copy initial frame directly
    final int firstCopy = min(winSize, min(inLen, outLen));
    for (int i = 0; i < firstCopy; i++) {
      output[i] += input[i] * win[i];
      normBuf[i] += win[i];
    }

    final int overlapLen = winSize - synthesisHop;
    int outPos = synthesisHop;
    double nominalInPos = synthesisHop / timeScale;

    while (outPos < outLen) {
      final int nominal = nominalInPos.round().clamp(
        0,
        max(0, inLen - winSize),
      );
      final int searchStart = max(0, nominal - searchRadius);
      final int searchEnd = min(
        max(0, inLen - winSize),
        nominal + searchRadius,
      );

      // Find offset with best waveform similarity to already-written overlap tail
      int bestOffset = nominal;
      double bestScore = -double.infinity;
      // Subsample correlation every 2 samples for fast responsiveness on long clips
      const int corrStep = 2;
      for (int cand = searchStart; cand <= searchEnd; cand++) {
        double cross = 0.0;
        double energyA = 1e-9;
        double energyB = 1e-9;
        for (int k = 0; k < overlapLen && outPos + k < outLen; k += corrStep) {
          final double a = normBuf[outPos + k] > 1e-6
              ? output[outPos + k] / normBuf[outPos + k]
              : 0.0;
          final double b = cand + k < inLen ? input[cand + k] : 0.0;
          cross += a * b;
          energyA += a * a;
          energyB += b * b;
        }
        final double ncc = cross / sqrt(energyA * energyB);
        if (ncc > bestScore) {
          bestScore = ncc;
          bestOffset = cand;
        }
      }

      for (int i = 0; i < winSize; i++) {
        if (outPos + i >= outLen || bestOffset + i >= inLen) break;
        final double w = win[i];
        output[outPos + i] += input[bestOffset + i] * w;
        normBuf[outPos + i] += w;
      }

      outPos += synthesisHop;
      nominalInPos += synthesisHop / timeScale;
    }

    final Float64List result = Float64List(outLen);
    for (int i = 0; i < outLen; i++) {
      final double n = normBuf[i];
      result[i] = n > 1e-6 ? output[i] / n : 0.0;
    }
    return result;
  }

  /// Resamples [input] to [targetLength] using 4-point cubic interpolation.
  static Float64List resampleCubic(List<double> input, int targetLength) {
    if (input.isEmpty || targetLength <= 0) return Float64List(0);
    if (targetLength == input.length) return Float64List.fromList(input);

    final out = Float64List(targetLength);
    final int n = input.length;
    final double step = (n - 1) / max(1, targetLength - 1);

    for (int i = 0; i < targetLength; i++) {
      final double pos = i * step;
      final int idx = pos.floor();
      final double frac = pos - idx;

      final double y0 = input[(idx - 1).clamp(0, n - 1)];
      final double y1 = input[idx.clamp(0, n - 1)];
      final double y2 = input[(idx + 1).clamp(0, n - 1)];
      final double y3 = input[(idx + 2).clamp(0, n - 1)];

      // Catmull-Rom cubic interpolation
      final double a0 = -0.5 * y0 + 1.5 * y1 - 1.5 * y2 + 0.5 * y3;
      final double a1 = y0 - 2.5 * y1 + 2.0 * y2 - 0.5 * y3;
      final double a2 = -0.5 * y0 + 0.5 * y2;
      final double a3 = y1;
      out[i] = ((a0 * frac + a1) * frac + a2) * frac + a3;
    }
    return out;
  }

  /// Applies independent tempo stretching ([stretchFactor] > 1.0 = faster/shorter)
  /// and pitch transposition ([pitchSemitones]).
  /// When [preservePitch] is true, duration depends ONLY on [stretchFactor]
  /// (`outLen = inLen / stretchFactor`) and pitch shifts cleanly by [pitchSemitones].
  static ({Float64List left, Float64List right}) processStereo({
    required List<double> left,
    required List<double> right,
    required int sampleRate,
    required double stretchFactor,
    required double pitchSemitones,
    bool preservePitch = true,
  }) {
    final double safeStretch = stretchFactor.clamp(0.25, 4.0);
    final double pitchRatio = pow(2.0, pitchSemitones / 12.0).toDouble();

    if ((safeStretch - 1.0).abs() < 0.002 &&
        pitchSemitones.abs() < 0.01) {
      return (
        left: Float64List.fromList(left),
        right: Float64List.fromList(right),
      );
    }

    final int targetLen = max(1, (left.length / safeStretch).round());

    if (!preservePitch) {
      // Varispeed mode: resample directly by combined speed (pitch + stretch coupled)
      final int varispeedLen = max(
        1,
        (left.length / (safeStretch * pitchRatio)).round(),
      );
      return (
        left: resampleCubic(left, varispeedLen),
        right: resampleCubic(right, varispeedLen),
      );
    }

    // Independent pitch + stretch:
    // Resampling by pitchRatio produces pitchShift with duration scale 1 / pitchRatio.
    // Compensate beforehand using WSOLA timeScale = pitchRatio / safeStretch so final
    // length == inLen * (pitchRatio / safeStretch) / pitchRatio == inLen / safeStretch.
    final double wsolaScale = (pitchRatio / safeStretch).clamp(0.125, 8.0);
    final Float64List stretchedL = timeScaleMono(
      left,
      sampleRate: sampleRate,
      timeScale: wsolaScale,
    );
    final Float64List stretchedR = timeScaleMono(
      right,
      sampleRate: sampleRate,
      timeScale: wsolaScale,
    );

    return (
      left: resampleCubic(stretchedL, targetLen),
      right: resampleCubic(stretchedR, targetLen),
    );
  }

  /// Processes a WAV file on disk into [outputPath] using [processStereo].
  static Future<bool> processWavFile({
    required String inputPath,
    required String outputPath,
    required double stretchFactor,
    required double pitchSemitones,
    bool preservePitch = true,
  }) async {
    final decoded = await decodeWavFile(inputPath);
    if (decoded == null || decoded.frameCount == 0) return false;

    final processed = processStereo(
      left: decoded.left,
      right: decoded.right,
      sampleRate: decoded.sampleRate,
      stretchFactor: stretchFactor,
      pitchSemitones: pitchSemitones,
      preservePitch: preservePitch,
    );

    final int n = processed.left.length;
    final ByteData out = ByteData(44 + n * 4);
    final int sr = decoded.sampleRate;
    final int dataSize = n * 4;

    out.setUint32(0, 0x52494646, Endian.big);
    out.setUint32(4, 36 + dataSize, Endian.little);
    out.setUint32(8, 0x57415645, Endian.big);
    out.setUint32(12, 0x666d7420, Endian.big);
    out.setUint32(16, 16, Endian.little);
    out.setUint16(20, 1, Endian.little);
    out.setUint16(22, 2, Endian.little);
    out.setUint32(24, sr, Endian.little);
    out.setUint32(28, sr * 4, Endian.little);
    out.setUint16(32, 4, Endian.little);
    out.setUint16(34, 16, Endian.little);
    out.setUint32(36, 0x64617461, Endian.big);
    out.setUint32(40, dataSize, Endian.little);

    for (int i = 0; i < n; i++) {
      final int l16 = (processed.left[i].clamp(-1.0, 1.0) * 32767.0).round();
      final int r16 = (processed.right[i].clamp(-1.0, 1.0) * 32767.0).round();
      out.setInt16(44 + i * 4, l16, Endian.little);
      out.setInt16(44 + i * 4 + 2, r16, Endian.little);
    }

    await File(outputPath).writeAsBytes(out.buffer.asUint8List(), flush: true);
    return true;
  }
}
