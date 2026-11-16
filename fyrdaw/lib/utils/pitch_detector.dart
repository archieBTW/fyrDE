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
  double minHz = 55.0,
  double maxHz = 1200.0,
}) {
  final n = samples.length;
  if (n < 512 || sampleRate <= 0) return null;

  // Remove DC offset and compute RMS to ignore background silence while
  // still catching sustaining passive pickups down to ~ -54 dBFS.
  double mean = 0.0;
  for (int i = 0; i < n; i++) {
    mean += samples[i];
  }
  mean /= n;

  double sumSq = 0.0;
  for (int i = 0; i < n; i++) {
    final v = samples[i] - mean;
    sumSq += v * v;
  }
  final rms = sqrt(sumSq / n);
  if (rms < 0.002) return null;

  final int minLag = max(8, (sampleRate / maxHz).floor());
  final int maxLag = min(n ~/ 2, (sampleRate / minHz).ceil());
  if (maxLag <= minLag + 2) return null;

  final int limit = n - maxLag;
  final diff = Float64List(maxLag + 1);
  for (int tau = 1; tau <= maxLag; tau++) {
    double acc = 0.0;
    for (int i = 0; i < limit; i++) {
      final d = (samples[i] - mean) - (samples[i + tau] - mean);
      acc += d * d;
    }
    diff[tau] = acc;
  }

  // Standard YIN cumulative mean normalized difference (CMND)
  final cmnd = Float64List(maxLag + 1);
  cmnd[0] = 1.0;
  double runningSum = 0.0;
  for (int tau = 1; tau <= maxLag; tau++) {
    runningSum += diff[tau];
    cmnd[tau] = runningSum > 1e-12 ? (diff[tau] * tau / runningSum) : 1.0;
  }

  int bestTau = -1;
  const double yinThreshold = 0.18;
  for (int tau = minLag; tau <= maxLag; tau++) {
    if (cmnd[tau] < yinThreshold) {
      while (tau + 1 <= maxLag && cmnd[tau + 1] < cmnd[tau]) {
        tau++;
      }
      bestTau = tau;
      break;
    }
  }

  // Fallback to global CMND minimum in valid range if threshold wasn't crossed cleanly
  if (bestTau == -1) {
    double minVal = double.infinity;
    for (int tau = minLag; tau <= maxLag; tau++) {
      if (cmnd[tau] < minVal) {
        minVal = cmnd[tau];
        bestTau = tau;
      }
    }
    if (minVal > 0.35) return null;
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

/// Sliding-window real-time pitch tracker with fast initial lock,
/// low-end 4096-sample stability, short dropout hold, and jitter smoothing.
class RealtimePitchTracker {
  final int sampleRate;
  final int windowSize;
  final int minInitialWindow;
  final int hopSize;
  final int maxHoldHops;

  final List<double> _buffer = [];
  int _samplesSinceAnalysis = 0;
  int _silenceHops = 0;
  PitchDetectionResult? _current;
  PitchDetectionResult? _pendingOctaveJump;
  int _pendingJumpCount = 0;

  RealtimePitchTracker({
    this.sampleRate = 44100,
    this.windowSize = 4096,
    this.minInitialWindow = 2048,
    this.hopSize = 1024,
    this.maxHoldHops = 6,
  });

  PitchDetectionResult? get current => _current;

  void reset() {
    _buffer.clear();
    _samplesSinceAnalysis = 0;
    _silenceHops = 0;
    _current = null;
    _pendingOctaveJump = null;
    _pendingJumpCount = 0;
  }

  /// Appends new mono [samples] and returns `true` if [current] changed
  /// meaningfully enough to trigger a UI refresh.
  bool addSamples(Iterable<double> samples) {
    int count = 0;
    for (final s in samples) {
      _buffer.add(s);
      count++;
    }
    if (count == 0) return false;
    _samplesSinceAnalysis += count;

    if (_buffer.length > windowSize * 2) {
      _buffer.removeRange(0, _buffer.length - windowSize);
    }

    final int readyLen = _buffer.length >= windowSize
        ? windowSize
        : (_buffer.length >= minInitialWindow ? minInitialWindow : 0);
    if (readyLen == 0 || _samplesSinceAnalysis < hopSize) {
      return false;
    }

    bool changed = false;
    while (_samplesSinceAnalysis >= hopSize && _buffer.length >= readyLen) {
      _samplesSinceAnalysis -= hopSize;
      final int winLen = _buffer.length >= windowSize ? windowSize : readyLen;
      final slice = Float64List.fromList(
        _buffer.sublist(_buffer.length - winLen),
      );
      final raw = detectPitchHz(slice, sampleRate);
      if (_ingestDetection(raw)) {
        changed = true;
      }
      if (_buffer.length > windowSize) {
        _buffer.removeRange(0, _buffer.length - windowSize);
      }
    }
    return changed;
  }

  bool _ingestDetection(PitchDetectionResult? raw) {
    final prev = _current;
    if (raw == null) {
      _pendingOctaveJump = null;
      _pendingJumpCount = 0;
      if (prev == null) return false;
      _silenceHops++;
      if (_silenceHops >= maxHoldHops) {
        _current = null;
        return true;
      }
      return false;
    }

    _silenceHops = 0;

    // Suppress isolated single-frame harmonic/octave glitches when locked on a note
    if (prev != null && (raw.midiNote - prev.midiNote).abs() == 12) {
      if (_pendingOctaveJump != null &&
          _pendingOctaveJump!.midiNote == raw.midiNote) {
        _pendingJumpCount++;
      } else {
        _pendingOctaveJump = raw;
        _pendingJumpCount = 1;
      }
      if (_pendingJumpCount < 2) {
        return false;
      }
    }
    _pendingOctaveJump = null;
    _pendingJumpCount = 0;

    PitchDetectionResult next = raw;
    if (prev != null && prev.midiNote == raw.midiNote) {
      // Exponential smoothing on frequency/cents to keep the needle readable
      final double freq = prev.frequencyHz * 0.55 + raw.frequencyHz * 0.45;
      final double midiFloat = 69.0 + 12.0 * (log(freq / 440.0) / ln2);
      final int midiRounded = midiFloat.round();
      final double cents = ((midiFloat - midiRounded) * 100.0).clamp(
        -50.0,
        50.0,
      );
      final String name =
          '${_kNoteNames[(midiRounded % 12 + 12) % 12]}${(midiRounded ~/ 12) - 1}';
      next = PitchDetectionResult(
        frequencyHz: freq,
        noteName: name,
        midiNote: midiRounded,
        cents: cents,
        confidence: raw.confidence,
      );
    }

    _current = next;
    if (prev == null) return true;
    return prev.noteName != next.noteName ||
        (prev.cents - next.cents).abs() >= 0.4 ||
        (prev.frequencyHz - next.frequencyHz).abs() >= 0.15;
  }
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

