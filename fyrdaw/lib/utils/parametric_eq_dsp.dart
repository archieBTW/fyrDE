import 'dart:math';
import 'dart:typed_data';

enum EqBandKind { lowShelf, peak, highShelf }

class EqBandSpec {
  final int index;
  final String label;
  final EqBandKind kind;
  final String freqKey;
  final String gainKey;
  final String? qKey;
  final double defaultFreq;
  final double minFreq;
  final double maxFreq;
  final double defaultQ;

  const EqBandSpec({
    required this.index,
    required this.label,
    required this.kind,
    required this.freqKey,
    required this.gainKey,
    this.qKey,
    required this.defaultFreq,
    required this.minFreq,
    required this.maxFreq,
    this.defaultQ = 1.0,
  });
}

/// 4-band Parametric EQ specification shared across DSP filter rendering and
/// interactive FFT-overlaid EQ UI.
const List<EqBandSpec> kParametricEqBands = [
  EqBandSpec(
    index: 0,
    label: 'Low',
    kind: EqBandKind.lowShelf,
    freqKey: 'lowFreq',
    gainKey: 'lowGain',
    defaultFreq: 100.0,
    minFreq: 25.0,
    maxFreq: 500.0,
    defaultQ: 0.707,
  ),
  EqBandSpec(
    index: 1,
    label: 'Lo-Mid',
    kind: EqBandKind.peak,
    freqKey: 'lowMidFreq',
    gainKey: 'lowMidGain',
    qKey: 'lowMidQ',
    defaultFreq: 420.0,
    minFreq: 120.0,
    maxFreq: 2400.0,
    defaultQ: 1.1,
  ),
  EqBandSpec(
    index: 2,
    label: 'Hi-Mid',
    kind: EqBandKind.peak,
    freqKey: 'highMidFreq',
    gainKey: 'highMidGain',
    qKey: 'highMidQ',
    defaultFreq: 2200.0,
    minFreq: 500.0,
    maxFreq: 8500.0,
    defaultQ: 1.1,
  ),
  EqBandSpec(
    index: 3,
    label: 'High',
    kind: EqBandKind.highShelf,
    freqKey: 'highFreq',
    gainKey: 'highGain',
    defaultFreq: 8500.0,
    minFreq: 1800.0,
    maxFreq: 18000.0,
    defaultQ: 0.707,
  ),
];

class BiquadCoeffs {
  final double b0;
  final double b1;
  final double b2;
  final double a1;
  final double a2;

  const BiquadCoeffs(this.b0, this.b1, this.b2, this.a1, this.a2);

  /// Audio EQ Cookbook biquad design normalized by a0 = 1.
  factory BiquadCoeffs.design({
    required EqBandKind kind,
    required double sampleRate,
    required double freqHz,
    required double gainDb,
    double q = 1.0,
  }) {
    if (gainDb.abs() < 0.05) {
      return const BiquadCoeffs(1.0, 0.0, 0.0, 0.0, 0.0);
    }
    final double f0 = freqHz.clamp(18.0, sampleRate * 0.45);
    final double w0 = 2.0 * pi * f0 / sampleRate;
    final double cosW0 = cos(w0);
    final double sinW0 = sin(w0);
    final double aLin = pow(10.0, gainDb / 40.0).toDouble();
    final double safeQ = q.clamp(0.25, 8.0);
    final double alpha = sinW0 / (2.0 * safeQ);

    double b0, b1, b2, a0, a1, a2;
    switch (kind) {
      case EqBandKind.lowShelf:
        final double beta = 2.0 * sqrt(aLin) * (sinW0 / (2.0 * 0.707));
        b0 = aLin * ((aLin + 1.0) - (aLin - 1.0) * cosW0 + beta);
        b1 = 2.0 * aLin * ((aLin - 1.0) - (aLin + 1.0) * cosW0);
        b2 = aLin * ((aLin + 1.0) - (aLin - 1.0) * cosW0 - beta);
        a0 = (aLin + 1.0) + (aLin - 1.0) * cosW0 + beta;
        a1 = -2.0 * ((aLin - 1.0) + (aLin + 1.0) * cosW0);
        a2 = (aLin + 1.0) + (aLin - 1.0) * cosW0 - beta;
        break;
      case EqBandKind.peak:
        b0 = 1.0 + alpha * aLin;
        b1 = -2.0 * cosW0;
        b2 = 1.0 - alpha * aLin;
        a0 = 1.0 + alpha / aLin;
        a1 = -2.0 * cosW0;
        a2 = 1.0 - alpha / aLin;
        break;
      case EqBandKind.highShelf:
        final double beta = 2.0 * sqrt(aLin) * (sinW0 / (2.0 * 0.707));
        b0 = aLin * ((aLin + 1.0) + (aLin - 1.0) * cosW0 + beta);
        b1 = -2.0 * aLin * ((aLin - 1.0) + (aLin + 1.0) * cosW0);
        b2 = aLin * ((aLin + 1.0) + (aLin - 1.0) * cosW0 - beta);
        a0 = (aLin + 1.0) - (aLin - 1.0) * cosW0 + beta;
        a1 = 2.0 * ((aLin - 1.0) - (aLin + 1.0) * cosW0);
        a2 = (aLin + 1.0) - (aLin - 1.0) * cosW0 - beta;
        break;
    }
    return BiquadCoeffs(b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0);
  }

  /// Magnitude response squared |H(e^{jw})|^2 at [freqHz].
  double magnitudeSquaredAt(double freqHz, double sampleRate) {
    final double w = 2.0 * pi * freqHz / sampleRate;
    final double cos1 = cos(w);
    final double sin1 = sin(w);
    final double cos2 = cos(2.0 * w);
    final double sin2 = sin(2.0 * w);

    final double numRe = b0 + b1 * cos1 + b2 * cos2;
    final double numIm = -b1 * sin1 - b2 * sin2;
    final double denRe = 1.0 + a1 * cos1 + a2 * cos2;
    final double denIm = -a1 * sin1 - a2 * sin2;

    final double denMag2 = max(1e-12, denRe * denRe + denIm * denIm);
    return (numRe * numRe + numIm * numIm) / denMag2;
  }
}

class ParametricEqDsp {
  static double bandFreq(Map<String, double> params, EqBandSpec band) =>
      (params[band.freqKey] ?? band.defaultFreq).clamp(
        band.minFreq,
        band.maxFreq,
      );

  static double bandGainDb(Map<String, double> params, EqBandSpec band) {
    if (params.containsKey(band.gainKey)) {
      return params[band.gainKey]!.clamp(-15.0, 15.0);
    }
    // Backwards-compatible fallback for legacy 3-knob ('Low'/'Mid'/'High') EQ params
    if (band.index == 0 && params.containsKey('Low')) {
      return ((params['Low']! - 0.5) * 24.0).clamp(-15.0, 15.0);
    }
    if (band.index == 1 && params.containsKey('Mid')) {
      return ((params['Mid']! - 0.5) * 20.0).clamp(-15.0, 15.0);
    }
    if (band.index == 3 && params.containsKey('High')) {
      return ((params['High']! - 0.5) * 24.0).clamp(-15.0, 15.0);
    }
    return 0.0;
  }

  static double bandQ(Map<String, double> params, EqBandSpec band) {
    if (band.qKey == null) return band.defaultQ;
    return (params[band.qKey!] ?? band.defaultQ).clamp(0.35, 6.0);
  }

  static List<BiquadCoeffs> buildStages(
    Map<String, double> params, {
    double sampleRate = 44100.0,
  }) {
    return kParametricEqBands
        .map(
          (b) => BiquadCoeffs.design(
            kind: b.kind,
            sampleRate: sampleRate,
            freqHz: bandFreq(params, b),
            gainDb: bandGainDb(params, b),
            q: bandQ(params, b),
          ),
        )
        .toList();
  }

  /// Total dB response at [freqHz] across all 4 cascaded parametric EQ bands.
  static double responseDbAt(
    Map<String, double> params,
    double freqHz, {
    double sampleRate = 44100.0,
    List<BiquadCoeffs>? prebuiltStages,
  }) {
    final stages =
        prebuiltStages ?? buildStages(params, sampleRate: sampleRate);
    double mag2 = 1.0;
    for (final s in stages) {
      mag2 *= s.magnitudeSquaredAt(freqHz, sampleRate);
    }
    final double db = 10.0 * (log(max(1e-12, mag2)) / ln10);
    return db.clamp(-24.0, 24.0);
  }

  /// Processes stereo sample arrays in-place through all active EQ biquads.
  static void processStereoInPlace({
    required List<double> left,
    required List<double> right,
    required Map<String, double> params,
    double sampleRate = 44100.0,
  }) {
    final stages = buildStages(params, sampleRate: sampleRate);
    for (final c in stages) {
      if ((c.b0 - 1.0).abs() < 1e-6 &&
          c.b1.abs() < 1e-6 &&
          c.b2.abs() < 1e-6) {
        continue;
      }
      double x1L = 0, x2L = 0, y1L = 0, y2L = 0;
      double x1R = 0, x2R = 0, y1R = 0, y2R = 0;
      for (int i = 0; i < left.length; i++) {
        final double inL = left[i];
        final double outL =
            c.b0 * inL + c.b1 * x1L + c.b2 * x2L - c.a1 * y1L - c.a2 * y2L;
        x2L = x1L;
        x1L = inL;
        y2L = y1L;
        y1L = outL;
        left[i] = outL;

        final double inR = right[i];
        final double outR =
            c.b0 * inR + c.b1 * x1R + c.b2 * x2R - c.a1 * y1R - c.a2 * y2R;
        x2R = x1R;
        x1R = inR;
        y2R = y1R;
        y1R = outR;
        right[i] = outR;
      }
    }
  }

  /// Converts real-time linear time-domain samples into normalized 0..1 spectral
  /// magnitude bins for live FFT overlay inside [ParametricEqWidget].
  static List<double> computeFftBinsFromSamples(
    Float32List? samples, {
    int numBins = 64,
  }) {
    if (samples == null || samples.isEmpty) return const [];
    final n = min(128, samples.length);
    final bins = List<double>.filled(numBins, 0.0);
    for (int k = 0; k < numBins; k++) {
      final int binIndex = ((k + 1) * (n ~/ 2) / numBins).round().clamp(1, n ~/ 2);
      double re = 0.0;
      double im = 0.0;
      final double w = 2.0 * pi * binIndex / n;
      for (int i = 0; i < n; i++) {
        final double win = 0.5 * (1.0 - cos(2.0 * pi * i / (n - 1)));
        final double s = samples[i] * win;
        re += s * cos(w * i);
        im -= s * sin(w * i);
      }
      final double mag = sqrt(re * re + im * im) / (n * 0.25);
      bins[k] = mag.clamp(0.0, 1.0);
    }
    return bins;
  }
}
