import 'dart:math';
import 'dart:typed_data';

class PitchDetectionResult {
  final double frequencyHz;
  final String noteName;
  final int midiNote;
  final double cents;
  final double confidence;

  const PitchDetectionResult({
    required this.frequencyHz,
    required this.noteName,
    required this.midiNote,
    required this.cents,
    required this.confidence,
  });
}

const List<String> _kNoteNames = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];

/// Estimates fundamental pitch from a mono audio buffer using normalized
/// difference / YIN-style autocorrelation. Returns null if signal is silent or noisy.
PitchDetectionResult? detectPitchHz(
  Float64List samples,
  int sampleRate, {
  double minHz = 60.0,
  double maxHz = 1200.0,
}) {
  final n = samples.length;
  if (n < 512 || sampleRate <= 0) return null;

  // Check RMS to ignore background silence
  double sumSq = 0.0;
  for (int i = 0; i < n; i++) {
    sumSq += samples[i] * samples[i];
  }
  final rms = sqrt(sumSq / n);
  if (rms < 0.008) return null;

  final int minLag = max(8, (sampleRate / maxHz).floor());
  final int maxLag = min(n ~/ 2, (sampleRate / minHz).ceil());
  if (maxLag <= minLag + 2) return null;

  final diff = Float64List(maxLag + 1);
  for (int tau = minLag; tau <= maxLag; tau++) {
    double acc = 0.0;
    final limit = n - maxLag;
    for (int i = 0; i < limit; i++) {
      final d = samples[i] - samples[i + tau];
      acc += d * d;
    }
    diff[tau] = acc;
  }

  // Cumulative mean normalized difference (CMND)
  final cmnd = Float64List(maxLag + 1);
  double runningSum = 0.0;
  for (int tau = 1; tau <= maxLag; tau++) {
    runningSum += diff[tau];
    if (tau < minLag) {
      cmnd[tau] = 1.0;
    } else {
      cmnd[tau] = runningSum > 1e-12 ? (diff[tau] * (tau - minLag + 1) / runningSum) : 1.0;
    }
  }

  int bestTau = -1;
  const double yinThreshold = 0.22;
  for (int tau = minLag; tau <= maxLag; tau++) {
    if (cmnd[tau] < yinThreshold) {
      while (tau + 1 <= maxLag && cmnd[tau + 1] < cmnd[tau]) {
        tau++;
      }
      bestTau = tau;
      break;
    }
  }

  // Fallback to global CMND minimum if threshold wasn't crossed cleanly
  if (bestTau == -1) {
    double minVal = double.infinity;
    for (int tau = minLag; tau <= maxLag; tau++) {
      if (cmnd[tau] < minVal) {
        minVal = cmnd[tau];
        bestTau = tau;
      }
    }
    if (minVal > 0.45) return null;
  }

  if (bestTau <= 0) return null;

  // Parabolic interpolation around bestTau
  double refinedTau = bestTau.toDouble();
  if (bestTau > minLag && bestTau < maxLag) {
    final s0 = cmnd[bestTau - 1];
    final s1 = cmnd[bestTau];
    final s2 = cmnd[bestTau + 1];
    final denom = 2.0 * (2.0 * s1 - s2 - s0);
    if (denom.abs() > 1e-9) {
      refinedTau += (s0 - s2) / denom;
    }
  }

  final freq = sampleRate / refinedTau;
  if (freq < minHz || freq > maxHz || freq.isNaN) return null;

  final midiFloat = 69.0 + 12.0 * (log(freq / 440.0) / ln2);
  final midiRounded = midiFloat.round();
  final cents = ((midiFloat - midiRounded) * 100.0).clamp(-50.0, 50.0);
  final name = '${_kNoteNames[(midiRounded % 12 + 12) % 12]}${(midiRounded ~/ 12) - 1}';

  return PitchDetectionResult(
    frequencyHz: freq,
    noteName: name,
    midiNote: midiRounded,
    cents: cents,
    confidence: (1.0 - cmnd[bestTau]).clamp(0.0, 1.0),
  );
}

/// Estimates short-term LUFS loudness (simplified K-style weighting via RMS dBFS - 0.691)
/// from waveform samples normalized to [-1, 1].
double estimateLufsFromWaveform(Float32List? samples) {
  if (samples == null || samples.isEmpty) return -60.0;
  final int start = samples.length >= 512 ? 256 : 0;
  final int count = samples.length - start;
  if (count <= 0) return -60.0;

  double sumSq = 0.0;
  for (int i = start; i < samples.length; i++) {
    final s = samples[i];
    sumSq += s * s;
  }
  final meanSq = sumSq / count;
  if (meanSq <= 1e-8) return -60.0;
  final lufs = -0.691 + 10.0 * (log(meanSq) / ln10);
  return lufs.clamp(-60.0, 0.0);
}

/// Computes stereo phase correlation in [-1.0, +1.0] from two channel amplitudes
/// or left/right sample buffers.
double computeStereoCorrelation(Float64List left, Float64List right) {
  final n = min(left.length, right.length);
  if (n == 0) return 1.0;
  double num = 0.0;
  double ll = 0.0;
  double rr = 0.0;
  for (int i = 0; i < n; i++) {
    num += left[i] * right[i];
    ll += left[i] * left[i];
    rr += right[i] * right[i];
  }
  final denom = sqrt(ll * rr);
  if (denom <= 1e-12) return 1.0;
  return (num / denom).clamp(-1.0, 1.0);
}

