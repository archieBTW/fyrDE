import 'dart:math';
import 'dart:typed_data';
import 'package:fyrdaw/models/automation_point.dart';
import 'package:fyrdaw/models/daw_effect.dart';
import 'package:fyrdaw/models/track.dart';
import 'package:fyrdaw/utils/parametric_eq_dsp.dart';

/// Stateful direct-form stereo biquad filter processor sharing [BiquadCoeffs].
class StereoBiquadState {
  double x1L = 0.0, x2L = 0.0, y1L = 0.0, y2L = 0.0;
  double x1R = 0.0, x2R = 0.0, y1R = 0.0, y2R = 0.0;

  void processRange(
    Float64List left,
    Float64List right,
    int start,
    int end,
    BiquadCoeffs c,
  ) {
    if ((c.b0 - 1.0).abs() < 1e-6 &&
        c.b1.abs() < 1e-6 &&
        c.b2.abs() < 1e-6 &&
        c.a1.abs() < 1e-6 &&
        c.a2.abs() < 1e-6) {
      return;
    }
    for (int i = start; i < end; i++) {
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

/// Designs a standard 2-pole Audio EQ Cookbook lowpass biquad filter.
BiquadCoeffs designLowpassBiquad({
  required double sampleRate,
  required double freqHz,
  double q = 0.707,
}) {
  final double f0 = freqHz.clamp(18.0, sampleRate * 0.45);
  final double safeQ = q.clamp(0.3, 12.0);
  final double w0 = 2.0 * pi * f0 / sampleRate;
  final double cosW0 = cos(w0);
  final double sinW0 = sin(w0);
  final double alpha = sinW0 / (2.0 * safeQ);
  final double oneMinusCos = 1.0 - cosW0;
  final double a0 = 1.0 + alpha;
  final double b0 = (oneMinusCos * 0.5) / a0;
  return BiquadCoeffs(
    b0,
    oneMinusCos / a0,
    b0,
    (-2.0 * cosW0) / a0,
    (1.0 - alpha) / a0,
  );
}

/// Stateful stereo modulated delay used by both [Chorus] and [Flanger].
class ModulatedDelayProcessor {
  final int maxDelaySamples;
  late final Float64List _bufL;
  late final Float64List _bufR;
  int _writeIdx = 0;
  double _phase = 0.0;

  ModulatedDelayProcessor({int sampleRate = 44100})
    : maxDelaySamples = max(256, (sampleRate * 0.1).round()) {
    _bufL = Float64List(maxDelaySamples);
    _bufR = Float64List(maxDelaySamples);
  }

  void processRange({
    required Float64List left,
    required Float64List right,
    required int start,
    required int end,
    required int sampleRate,
    required double baseDelaySec,
    required double modDepthSec,
    required double rateHz,
    required double mix,
    double feedback = 0.0,
    double dryScaleOffset = 0.35,
    double wetGain = 0.75,
  }) {
    final double m = mix.clamp(0.0, 1.0);
    if (m <= 1e-4) {
      // Advance write pointer cleanly if mixed back in later
      for (int i = start; i < end; i++) {
        _bufL[_writeIdx] = left[i];
        _bufR[_writeIdx] = right[i];
        _writeIdx = (_writeIdx + 1) % maxDelaySamples;
      }
      return;
    }

    final double phaseInc = 2.0 * pi * rateHz.clamp(0.02, 12.0) / sampleRate;
    final double dryScale = 1.0 - m * dryScaleOffset;
    final double wetScale = m * wetGain;
    final double fb = feedback.clamp(-0.85, 0.85);

    for (int i = start; i < end; i++) {
      final double inL = left[i];
      final double inR = right[i];

      // Quadrature stereo LFO for lush L/R spatial spread
      final double lfoL = 0.5 + 0.5 * sin(_phase);
      final double lfoR = 0.5 + 0.5 * cos(_phase);
      _phase += phaseInc;
      if (_phase >= 2.0 * pi) _phase -= 2.0 * pi;

      final double delaySamplesL = ((baseDelaySec + modDepthSec * lfoL) * sampleRate)
          .clamp(1.0, (maxDelaySamples - 2).toDouble());
      final double delaySamplesR = ((baseDelaySec + modDepthSec * lfoR) * sampleRate)
          .clamp(1.0, (maxDelaySamples - 2).toDouble());

      final double wetL = _readFrac(_bufL, delaySamplesL);
      final double wetR = _readFrac(_bufR, delaySamplesR);

      _bufL[_writeIdx] = (inL + wetL * fb).clamp(-4.0, 4.0);
      _bufR[_writeIdx] = (inR + wetR * fb).clamp(-4.0, 4.0);
      _writeIdx = (_writeIdx + 1) % maxDelaySamples;

      left[i] = inL * dryScale + wetL * wetScale;
      right[i] = inR * dryScale + wetR * wetScale;
    }
  }

  double _readFrac(Float64List buf, double delaySamples) {
    double readPos = _writeIdx - delaySamples;
    while (readPos < 0) {
      readPos += maxDelaySamples;
    }
    final int i0 = readPos.floor() % maxDelaySamples;
    final int i1 = (i0 + 1) % maxDelaySamples;
    final double frac = readPos - readPos.floor();
    return buf[i0] * (1.0 - frac) + buf[i1] * frac;
  }
}

/// Stateful Robotize carrier-modulation processor matching live frequency range.
class RobotizeProcessor {
  double _phase = 0.0;

  void processRange({
    required Float64List left,
    required Float64List right,
    required int start,
    required int end,
    required int sampleRate,
    required double freqParam,
    required double mix,
  }) {
    final double m = mix.clamp(0.0, 1.0);
    if (m <= 1e-4) return;
    final double freqHz = (15.0 + freqParam.clamp(0.0, 1.0) * 80.0).clamp(
      1.0,
      100.0,
    );
    final double phaseInc = 2.0 * pi * freqHz / sampleRate;
    for (int i = start; i < end; i++) {
      final double carrier =
          0.72 * sin(_phase) + 0.28 * sin(2.0 * _phase);
      _phase += phaseInc;
      if (_phase >= 2.0 * pi) _phase -= 2.0 * pi;
      final double dryL = left[i];
      final double dryR = right[i];
      final double wetL = dryL * carrier * 1.15;
      final double wetR = dryR * carrier * 1.15;
      left[i] = dryL * (1.0 - m) + wetL * m;
      right[i] = dryR * (1.0 - m) + wetR * m;
    }
  }
}

/// Stateful stereo Compressor / Limiter with attack/release ballistics and
/// optional sidechain detection buffer.
class CompressorProcessor {
  double _env = 0.0;

  void processRange({
    required Float64List left,
    required Float64List right,
    required int start,
    required int end,
    required int sampleRate,
    required double threshDb,
    required double ratio,
    required double makeupDb,
    required double mix,
    double attackMs = 10.0,
    double releaseMs = 100.0,
    Float64List? scLeft,
    Float64List? scRight,
  }) {
    final double m = mix.clamp(0.0, 1.0);
    if (m <= 1e-4) return;
    final double threshLin = pow(10.0, threshDb / 20.0).toDouble();
    final double safeRatio = max(1.0, ratio);
    final double makeup = pow(10.0, makeupDb / 20.0).toDouble();
    final double attCoeff = exp(-1.0 / (max(0.5, attackMs) * 0.001 * sampleRate));
    final double relCoeff = exp(-1.0 / (max(1.0, releaseMs) * 0.001 * sampleRate));

    for (int i = start; i < end; i++) {
      final double scAbsR = scRight != null ? scRight[i].abs() : 0.0;
      final double peak = scLeft != null
          ? max(scLeft[i].abs(), scAbsR)
          : max(left[i].abs(), right[i].abs());

      if (peak > _env) {
        _env = _env * attCoeff + peak * (1.0 - attCoeff);
      } else {
        _env = _env * relCoeff + peak * (1.0 - relCoeff);
      }

      double gain = 1.0;
      if (_env > threshLin && _env > 1e-6) {
        final double compressed = threshLin + (_env - threshLin) / safeRatio;
        gain = compressed / _env;
      }
      final double compL = left[i] * gain * makeup;
      final double compR = right[i] * gain * makeup;
      left[i] = left[i] * (1.0 - m) + compL * m;
      right[i] = right[i] * (1.0 - m) + compR * m;
    }
  }
}

/// Stateful stereo Echo with damped feedback loop matching live [echoFilter].
class EchoProcessor {
  final int maxDelaySamples;
  late final Float64List _bufL;
  late final Float64List _bufR;
  int _writeIdx = 0;
  double _lpL = 0.0;
  double _lpR = 0.0;

  EchoProcessor({int sampleRate = 44100})
    : maxDelaySamples = max(sampleRate * 2 + 4, 4096) {
    _bufL = Float64List(maxDelaySamples);
    _bufR = Float64List(maxDelaySamples);
  }

  void processRange({
    required Float64List left,
    required Float64List right,
    required int start,
    required int end,
    required int sampleRate,
    required double delaySec,
    required double decay,
    required double mix,
    double filterDamp = 0.35,
    bool wetOnly = false,
  }) {
    final int delayFrames = (delaySec * sampleRate).round().clamp(
      1,
      maxDelaySamples - 1,
    );
    final double fb = decay.clamp(0.01, 0.94);
    final double damp = filterDamp.clamp(0.0, 0.9);
    final double m = mix.clamp(0.0, 1.5);

    for (int i = start; i < end; i++) {
      final int readIdx =
          (_writeIdx - delayFrames + maxDelaySamples) % maxDelaySamples;
      final double tapL = _bufL[readIdx];
      final double tapR = _bufR[readIdx];

      // Subtle stereo cross-reflection + high-frequency damping in feedback loop
      final double fbL = tapL * 0.72 + tapR * 0.28;
      final double fbR = tapR * 0.72 + tapL * 0.28;
      _lpL = fbL * (1.0 - damp) + _lpL * damp;
      _lpR = fbR * (1.0 - damp) + _lpR * damp;

      final double inL = left[i];
      final double inR = right[i];
      _bufL[_writeIdx] = (inL + _lpL * fb).clamp(-8.0, 8.0);
      _bufR[_writeIdx] = (inR + _lpR * fb).clamp(-8.0, 8.0);
      _writeIdx = (_writeIdx + 1) % maxDelaySamples;

      if (wetOnly) {
        left[i] = tapL * m;
        right[i] = tapR * m;
      } else {
        final double clampedM = m.clamp(0.0, 1.0);
        left[i] = inL * (1.0 - clampedM * 0.5) + tapL * clampedM;
        right[i] = inR * (1.0 - clampedM * 0.5) + tapR * clampedM;
      }
    }
  }
}

/// Stateful Freeverb-style stereo reverb (4 damped combs + 2 series allpasses
/// per channel) normalized for live [freeverbFilter] level & Aux wet returns.
class FreeverbProcessor {
  static const List<int> _baseCombsL = [1116, 1277, 1422, 1617];
  static const List<int> _baseCombsR = [1139, 1300, 1445, 1640];
  static const List<int> _baseAllpassL = [556, 441];
  static const List<int> _baseAllpassR = [579, 464];

  late final List<Float64List> _combBufL;
  late final List<Float64List> _combBufR;
  late final List<int> _combIdxL;
  late final List<int> _combIdxR;
  late final Float64List _combStoreL;
  late final Float64List _combStoreR;

  late final List<Float64List> _apBufL;
  late final List<Float64List> _apBufR;
  late final List<int> _apIdxL;
  late final List<int> _apIdxR;

  FreeverbProcessor({int sampleRate = 44100}) {
    final double srScale = sampleRate / 44100.0;
    _combBufL = _baseCombsL
        .map((d) => Float64List(max(64, (d * srScale).round())))
        .toList();
    _combBufR = _baseCombsR
        .map((d) => Float64List(max(64, (d * srScale).round())))
        .toList();
    _combIdxL = List.filled(_baseCombsL.length, 0);
    _combIdxR = List.filled(_baseCombsR.length, 0);
    _combStoreL = Float64List(_baseCombsL.length);
    _combStoreR = Float64List(_baseCombsR.length);

    _apBufL = _baseAllpassL
        .map((d) => Float64List(max(32, (d * srScale).round())))
        .toList();
    _apBufR = _baseAllpassR
        .map((d) => Float64List(max(32, (d * srScale).round())))
        .toList();
    _apIdxL = List.filled(_baseAllpassL.length, 0);
    _apIdxR = List.filled(_baseAllpassR.length, 0);
  }

  void processRange({
    required Float64List left,
    required Float64List right,
    required int start,
    required int end,
    required double roomSize,
    required double damp,
    required double mix,
    bool wetOnly = false,
  }) {
    final double fb = (0.70 + roomSize.clamp(0.1, 0.98) * 0.255).clamp(
      0.5,
      0.96,
    );
    final double d1 = damp.clamp(0.05, 0.95);
    final double d0 = 1.0 - d1;
    final double m = mix.clamp(0.0, 1.5);
    const double inputScale = 0.065;

    for (int i = start; i < end; i++) {
      final double inL = left[i];
      final double inR = right[i];
      final double monoIn = (inL + inR) * 0.5 * inputScale;

      double wetL = 0.0;
      for (int c = 0; c < _combBufL.length; c++) {
        final buf = _combBufL[c];
        final int idx = _combIdxL[c];
        final double out = buf[idx];
        final double store = out * d0 + _combStoreL[c] * d1;
        _combStoreL[c] = store;
        buf[idx] = monoIn + store * fb;
        _combIdxL[c] = (idx + 1) % buf.length;
        wetL += out;
      }

      double wetR = 0.0;
      for (int c = 0; c < _combBufR.length; c++) {
        final buf = _combBufR[c];
        final int idx = _combIdxR[c];
        final double out = buf[idx];
        final double store = out * d0 + _combStoreR[c] * d1;
        _combStoreR[c] = store;
        buf[idx] = monoIn + store * fb;
        _combIdxR[c] = (idx + 1) % buf.length;
        wetR += out;
      }

      for (int a = 0; a < _apBufL.length; a++) {
        final buf = _apBufL[a];
        final int idx = _apIdxL[a];
        final double bufOut = buf[idx];
        buf[idx] = wetL + bufOut * 0.5;
        wetL = bufOut - wetL * 0.5;
        _apIdxL[a] = (idx + 1) % buf.length;
      }
      for (int a = 0; a < _apBufR.length; a++) {
        final buf = _apBufR[a];
        final int idx = _apIdxR[a];
        final double bufOut = buf[idx];
        buf[idx] = wetR + bufOut * 0.5;
        wetR = bufOut - wetR * 0.5;
        _apIdxR[a] = (idx + 1) % buf.length;
      }

      if (wetOnly) {
        left[i] = wetL * m;
        right[i] = wetR * m;
      } else {
        final double clampedM = m.clamp(0.0, 1.0);
        left[i] = inL * (1.0 - clampedM * 0.45) + wetL * clampedM;
        right[i] = inR * (1.0 - clampedM * 0.45) + wetR * clampedM;
      }
    }
  }
}

/// Stateful Lo-Fi bitcrusher & sample-rate reducer matching live [lofiFilter].
class LofiProcessor {
  double _holdL = 0.0;
  double _holdR = 0.0;
  int _counter = 0;

  void processRange({
    required Float64List left,
    required Float64List right,
    required int start,
    required int end,
    required int sampleRate,
    required double rateParam,
    required double bitsParam,
    required double mix,
  }) {
    final double m = mix.clamp(0.0, 1.0);
    if (m <= 1e-4) return;
    final double targetSr = (1200.0 + rateParam.clamp(0.0, 1.0) * 14000.0)
        .clamp(500.0, 22000.0);
    final int step = (sampleRate / targetSr).round().clamp(1, 88);
    final double bitDepth = (2.0 + bitsParam.clamp(0.0, 1.0) * 12.0).clamp(
      1.0,
      16.0,
    );
    final double levels = pow(2.0, bitDepth).toDouble();

    for (int i = start; i < end; i++) {
      if (_counter % step == 0) {
        _holdL = (left[i] * levels).round() / levels;
        _holdR = (right[i] * levels).round() / levels;
      }
      _counter++;
      left[i] = left[i] * (1.0 - m) + _holdL * m;
      right[i] = right[i] * (1.0 - m) + _holdR * m;
    }
  }
}

/// Stateful 4-band Parametric EQ reusing [kParametricEqBands] and [BiquadCoeffs]
/// so automated EQ moves stay click-free across control blocks.
class EqProcessor {
  final List<StereoBiquadState> _bands = List.generate(
    kParametricEqBands.length,
    (_) => StereoBiquadState(),
  );

  void processRange({
    required Float64List left,
    required Float64List right,
    required int start,
    required int end,
    required int sampleRate,
    required Map<String, double> params,
  }) {
    final double sr = sampleRate.toDouble();
    for (int i = 0; i < kParametricEqBands.length; i++) {
      final b = kParametricEqBands[i];
      final coeffs = BiquadCoeffs.design(
        kind: b.kind,
        sampleRate: sr,
        freqHz: ParametricEqDsp.bandFreq(params, b),
        gainDb: ParametricEqDsp.bandGainDb(params, b),
        q: ParametricEqDsp.bandQ(params, b),
      );
      _bands[i].processRange(left, right, start, end, coeffs);
    }
  }
}

/// Stateful Overdrive + GuitarAmp processor matching `_updateTrackFilters`
/// asymmetric diode/tube saturation, 5-band mid-hump & 4x12 cab EQ, cabinet
/// lowpass, power-tube sag compressor, and output limiter.
class OverdriveAndAmpProcessor {
  final List<StereoBiquadState> _cabEqStates =
      List.generate(5, (_) => StereoBiquadState());
  final StereoBiquadState _cabLpfState = StereoBiquadState();
  final CompressorProcessor _sagComp = CompressorProcessor();
  final CompressorProcessor _outLimiter = CompressorProcessor();

  static const List<double> _cabBandFreqs = [30.0, 144.0, 693.0, 3330.0, 16000.0];
  static const List<EqBandKind> _cabBandKinds = [
    EqBandKind.lowShelf,
    EqBandKind.peak,
    EqBandKind.peak,
    EqBandKind.peak,
    EqBandKind.highShelf,
  ];

  void processRange({
    required Float64List left,
    required Float64List right,
    required int start,
    required int end,
    required int sampleRate,
    Map<String, double>? odParams,
    Map<String, double>? ampParams,
    required bool hasDedicatedEq,
    required bool hasDedicatedComp,
  }) {
    if (odParams == null && ampParams == null) return;

    final double odDrive = (odParams?['Drive'] ?? 0.5).clamp(0.0, 1.0);
    final double odTone = (odParams?['Tone'] ?? 0.5).clamp(0.0, 1.0);
    final double odLevel = (odParams?['Level'] ?? 0.5).clamp(0.0, 1.0);

    final double ampDrive = (ampParams?['Drive'] ?? 0.7).clamp(0.0, 1.0);
    final double ampTone = (ampParams?['Tone'] ?? 0.6).clamp(0.0, 1.0);
    final double ampLevel = (ampParams?['Level'] ?? 0.5).clamp(0.0, 1.0);

    final bool hasOd = odParams != null;
    final bool hasAmp = ampParams != null;

    double wsAmount;
    double wsWet;
    double lpfCutoff;
    double lpfResonance;

    if (hasOd && hasAmp) {
      final double combinedDrive =
          (1.0 - (1.0 - odDrive * 0.85) * (1.0 - ampDrive * 0.92)).clamp(
            0.0,
            1.0,
          );
      wsAmount = (0.58 + 0.412 * (1.0 - pow(1.0 - combinedDrive, 2.5))).clamp(
        0.0,
        0.992,
      );
      wsWet = (0.93 + 0.07 * combinedDrive).clamp(0.0, 1.0);
      final double blendedTone = (0.55 * odTone + 0.45 * ampTone).clamp(
        0.0,
        1.0,
      );
      lpfCutoff = (1400.0 + blendedTone * 2800.0).clamp(1100.0, 4400.0);
      lpfResonance = (1.20 + 0.55 * odDrive).clamp(0.7, 2.2);
    } else if (hasOd) {
      wsAmount = (0.35 + 0.635 * (1.0 - pow(1.0 - odDrive, 2.2))).clamp(
        0.0,
        0.99,
      );
      wsWet = (0.85 + 0.15 * odDrive).clamp(0.0, 1.0);
      lpfCutoff = (900.0 * pow(4.8, odTone)).clamp(800.0, 4800.0);
      lpfResonance = (0.90 + 0.55 * odDrive + 0.30 * odTone).clamp(0.5, 2.2);
    } else {
      wsAmount = (0.52 + 0.468 * (1.0 - pow(1.0 - ampDrive, 2.4))).clamp(
        0.0,
        0.992,
      );
      wsWet = (0.92 + 0.08 * ampDrive).clamp(0.0, 1.0);
      lpfCutoff = (1650.0 + ampTone * 2550.0).clamp(1200.0, 4500.0);
      lpfResonance = 1.30;
    }

    // 1. Asymmetric waveshaper saturation (zero DC offset at x == 0)
    final double kPos = (2.0 * wsAmount) / max(1e-4, 1.0 - wsAmount);
    final double kNeg = kPos * 0.86;
    for (int i = start; i < end; i++) {
      left[i] = _shapeSample(left[i], kPos, kNeg, wsWet);
      right[i] = _shapeSample(right[i], kPos, kNeg, wsWet);
    }

    // 2. 5-band mid-hump & 4x12 cab EQ (when not overridden by standalone EQ)
    if (!hasDedicatedEq) {
      final List<double> gains = List<double>.filled(5, 1.0);
      if (hasOd && hasAmp) {
        final double gain = (0.45 + 1.15 * odLevel) * (0.55 + 1.05 * ampLevel);
        gains[0] = (0.35 * gain).clamp(0.05, 4.0);
        gains[1] = (1.15 * gain).clamp(0.05, 4.0);
        gains[2] = ((1.55 + 0.85 * odDrive) * gain).clamp(0.05, 4.0);
        gains[3] = ((0.95 + 0.65 * (0.5 * odTone + 0.5 * ampTone)) * gain)
            .clamp(0.05, 4.0);
        gains[4] = (0.18 * gain).clamp(0.05, 4.0);
      } else if (hasOd) {
        final double gain = 0.35 + 1.45 * odLevel;
        gains[0] = (0.35 * gain).clamp(0.05, 4.0);
        gains[1] = (0.85 * gain).clamp(0.05, 4.0);
        gains[2] = ((1.35 + 0.85 * odDrive) * gain).clamp(0.05, 4.0);
        gains[3] = ((0.75 + 0.75 * odTone) * gain).clamp(0.05, 4.0);
        gains[4] = ((0.22 + 0.30 * odTone) * gain).clamp(0.05, 4.0);
      } else {
        final double gain = 0.40 + 1.40 * ampLevel;
        gains[0] = (0.45 * gain).clamp(0.05, 4.0);
        gains[1] = (1.35 * gain).clamp(0.05, 4.0);
        gains[2] = ((0.95 + 0.45 * ampTone) * gain).clamp(0.05, 4.0);
        gains[3] = ((1.10 + 0.65 * ampTone) * gain).clamp(0.05, 4.0);
        gains[4] = (0.18 * gain).clamp(0.05, 4.0);
      }

      for (int b = 0; b < 5; b++) {
        final double gainDb =
            (20.0 * (log(max(0.05, gains[b])) / ln10)).clamp(-24.0, 12.0);
        final coeffs = BiquadCoeffs.design(
          kind: _cabBandKinds[b],
          sampleRate: sampleRate.toDouble(),
          freqHz: _cabBandFreqs[b],
          gainDb: gainDb,
          q: _cabBandKinds[b] == EqBandKind.peak ? 1.15 : 0.707,
        );
        _cabEqStates[b].processRange(left, right, start, end, coeffs);
      }
    }

    // 3. Cabinet Biquad Lowpass
    final lpfCoeffs = designLowpassBiquad(
      sampleRate: sampleRate.toDouble(),
      freqHz: lpfCutoff,
      q: lpfResonance,
    );
    _cabLpfState.processRange(left, right, start, end, lpfCoeffs);

    // 4. GuitarAmp power-tube sag & compression
    if (hasAmp && !hasDedicatedComp) {
      _sagComp.processRange(
        left: left,
        right: right,
        start: start,
        end: end,
        sampleRate: sampleRate,
        threshDb: (-14.0 - ampDrive * 18.0).clamp(-45.0, -5.0),
        ratio: (3.0 + ampDrive * 4.5).clamp(1.0, 10.0),
        makeupDb: ((ampLevel - 0.5) * 16.0 + ampDrive * 3.5).clamp(
          -20.0,
          24.0,
        ),
        mix: 1.0,
        attackMs: 8.0,
        releaseMs: 110.0,
      );
    }

    // 5. Output peak limiter (-1.5 dB threshold, -0.5 dB ceiling)
    _outLimiter.processRange(
      left: left,
      right: right,
      start: start,
      end: end,
      sampleRate: sampleRate,
      threshDb: -1.5,
      ratio: 18.0,
      makeupDb: 0.0,
      mix: 1.0,
      attackMs: 1.0,
      releaseMs: 40.0,
    );
  }

  static double _shapeSample(
    double x,
    double kPos,
    double kNeg,
    double wet,
  ) {
    final double k = x >= 0 ? kPos : kNeg;
    final double shaped = ((1.0 + k) * x) / (1.0 + k * x.abs());
    return x * (1.0 - wet) + shaped * wet;
  }
}

/// Pure, isolate-safe parameter evaluation querying `${fx.name}_$paramKey`
/// from [automation] at [posUnits] when present.
double resolveEffectParamFromAutomation(
  Map<String, List<AutomationPoint>>? automation,
  DawEffect fx,
  String paramKey,
  double fallback,
  double? posUnits,
) {
  final double baseVal = fx.parameters[paramKey] ?? fallback;
  if (automation == null || posUnits == null) return baseVal.clamp(0.0, 1.0);
  final String autoKey = '${fx.name}_$paramKey';
  final pts = automation[autoKey];
  if (pts == null || pts.isEmpty) {
    return baseVal.clamp(0.0, 1.0);
  }
  final double av = interpolateAutomationPoints(pts, posUnits);
  return (av >= 0.0 ? av : baseVal).clamp(0.0, 1.0);
}

/// Pure, isolate-safe parameter map evaluation for [fx] at [posUnits].
Map<String, double> resolveEffectParamMapFromAutomation(
  Map<String, List<AutomationPoint>>? automation,
  DawEffect fx,
  double? posUnits,
) {
  if (automation == null || posUnits == null) return fx.parameters;
  bool anyAuto = false;
  for (final k in fx.parameters.keys) {
    if (automation['${fx.name}_$k']?.isNotEmpty ?? false) {
      anyAuto = true;
      break;
    }
  }
  if (!anyAuto) return fx.parameters;
  return {
    for (final e in fx.parameters.entries)
      e.key: (automation['${fx.name}_${e.key}']?.isNotEmpty ?? false)
          ? (() {
              final av = interpolateAutomationPoints(
                automation['${fx.name}_${e.key}'],
                posUnits,
              );
              return av >= 0.0 ? av : e.value;
            })()
          : e.value,
  };
}

/// Evaluates effective parameter values for [fx] on optional [track], querying
/// `${fx.name}_$paramKey` automation at [posUnits] when present.
double resolveEffectParam(
  Track? track,
  DawEffect fx,
  String paramKey,
  double fallback,
  double? posUnits,
) => resolveEffectParamFromAutomation(
  track?.automation,
  fx,
  paramKey,
  fallback,
  posUnits,
);

/// Builds a parameter map for [fx] evaluated at [posUnits], preserving raw EQ
/// parameters when un-automated and applying automation curves where present.
Map<String, double> resolveEffectParamMap(
  Track? track,
  DawEffect fx,
  double? posUnits,
) => resolveEffectParamMapFromAutomation(track?.automation, fx, posUnits);
