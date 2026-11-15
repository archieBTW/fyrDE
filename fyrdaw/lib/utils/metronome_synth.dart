import 'dart:math';
import 'dart:typed_data';

/// Synthesizes crisp, high-clarity stereo percussive metronome click WAV buffers
/// designed to cut cleanly through dense mixes without harsh DC clicks.
class MetronomeSynth {
  static const int sampleRate = 44100;

  /// Computes effective playback gain for a beat click from user-configured
  /// [metronomeVolume] (0.0 .. 1.5). Downbeat is accented relative to regular beats.
  static double computeClickVolume(
    double metronomeVolume, {
    required bool isDownbeat,
  }) {
    final base = metronomeVolume.clamp(0.0, 1.5);
    return isDownbeat ? base : (base * 0.68);
  }

  /// Generates a 16-bit PCM stereo WAV buffer containing a synthesized
  /// woodblock/cowbell-style metronome transient (~48 ms).
  static Uint8List generateClickWav({required bool isDownbeat}) {
    const int durationMs = 48;
    const int numSamples = (sampleRate * durationMs) ~/ 1000;
    final Float64List samples = Float64List(numSamples);

    final double f1 = isDownbeat ? 1760.0 : 1175.0;
    final double f2 = isDownbeat ? 2640.0 : 1760.0;
    final double f3 = isDownbeat ? 3960.0 : 2350.0;
    final double decayRate = isDownbeat ? 92.0 : 115.0;

    double maxAbs = 0.0;
    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      // Fast 0.8 ms attack avoids hardware pop; exponential decay shapes woodblock body
      final double attack = t < 0.0008 ? (t / 0.0008) : 1.0;
      final double env = attack * exp(-decayRate * t);
      final double transientEnv = exp(-420.0 * t);

      // Slight downward pitch chirp in the first few milliseconds gives percussive snap
      final double pitchDrop = 1.0 + 0.08 * exp(-280.0 * t);
      final double body =
          sin(2.0 * pi * f1 * pitchDrop * t) * 0.62 +
          sin(2.0 * pi * f2 * t) * 0.28 * exp(-160.0 * t) +
          sin(2.0 * pi * f3 * t) * 0.14 * transientEnv;
      // Crisp 1 ms stick transient
      final double stick = (t < 0.0012 ? sin(2.0 * pi * 4800.0 * t) : 0.0) * 0.25;

      final double v = (body * env) + (stick * transientEnv);
      samples[i] = v;
      if (v.abs() > maxAbs) maxAbs = v.abs();
    }

    // Normalize near -0.5 dBFS so even lower volume slider settings stay clear
    final double norm = maxAbs > 1e-6 ? (0.94 / maxAbs) : 1.0;
    final ByteData out = ByteData(44 + numSamples * 4);
    _writeWavHeader(out, numSamples, sampleRate, 2);

    for (int i = 0; i < numSamples; i++) {
      final int s16 = (samples[i] * norm * 32767.0).round().clamp(-32768, 32767);
      final int offset = 44 + i * 4;
      out.setInt16(offset, s16, Endian.little);
      out.setInt16(offset + 2, s16, Endian.little);
    }
    return out.buffer.asUint8List();
  }

  static void _writeWavHeader(
    ByteData data,
    int numSamples,
    int sr,
    int channels,
  ) {
    final int byteRate = sr * channels * 2;
    final int blockAlign = channels * 2;
    final int dataSize = numSamples * blockAlign;
    // RIFF
    data.setUint32(0, 0x52494646, Endian.big);
    data.setUint32(4, 36 + dataSize, Endian.little);
    data.setUint32(8, 0x57415645, Endian.big); // WAVE
    // fmt
    data.setUint32(12, 0x666d7420, Endian.big);
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little); // PCM
    data.setUint16(22, channels, Endian.little);
    data.setUint32(24, sr, Endian.little);
    data.setUint32(28, byteRate, Endian.little);
    data.setUint16(32, blockAlign, Endian.little);
    data.setUint16(34, 16, Endian.little);
    // data
    data.setUint32(36, 0x64617461, Endian.big);
    data.setUint32(40, dataSize, Endian.little);
  }
}
