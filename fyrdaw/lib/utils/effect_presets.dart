import 'package:fyrdaw/models/daw_effect.dart';

/// Definition of a built-in FX chain preset shown in the Effects Rack.
class EffectChainPreset {
  final String id;
  final String label;
  final bool isVocal;
  final List<DawEffect> Function() buildChain;

  const EffectChainPreset({
    required this.id,
    required this.label,
    required this.isVocal,
    required this.buildChain,
  });
}

/// Built-in FX chain presets (vocals, guitars, tape, ambient).
final List<EffectChainPreset> kEffectChainPresets = [
  EffectChainPreset(
    id: 'Crunch Guitar',
    label: 'Crunch Guitar Rig',
    isVocal: false,
    buildChain: () => [
      DawEffect('EQ', {'Low': 0.45, 'Mid': 0.65, 'High': 0.60}),
      DawEffect('Overdrive', {'Drive': 0.62, 'Tone': 0.55, 'Level': 0.70}),
      DawEffect('GuitarAmp', {'Drive': 0.65, 'Tone': 0.55, 'Level': 0.55}),
    ],
  ),
  EffectChainPreset(
    id: 'Lo-Fi Tape',
    label: 'Lo-Fi Tape Machine',
    isVocal: false,
    buildChain: () => [
      DawEffect('EQ', {'Low': 0.55, 'Mid': 0.60, 'High': 0.25}),
      DawEffect('Echo', {'Mix': 0.25, 'Delay': 0.35, 'Decay': 0.40}),
      DawEffect('Compressor', {
        'Thresh': 0.35,
        'Ratio': 0.70,
        'Gain': 0.55,
        'Mix': 1.0,
      }),
    ],
  ),
  EffectChainPreset(
    id: 'Wide Ambient',
    label: 'Wide Ambient Space',
    isVocal: false,
    buildChain: () => [
      DawEffect('Reverb', {'Mix': 0.65, 'Size': 0.85, 'Decay': 0.70}),
      DawEffect('Echo', {'Mix': 0.45, 'Delay': 0.50, 'Decay': 0.65}),
    ],
  ),
  // Vocal Presets
  EffectChainPreset(
    id: 'Vocal Polish',
    label: 'Vocal Polish Chain',
    isVocal: true,
    buildChain: () => [
      DawEffect('EQ', {'Low': 0.35, 'Mid': 0.55, 'High': 0.72}),
      DawEffect('Compressor', {
        'Thresh': 0.45,
        'Ratio': 0.55,
        'Gain': 0.58,
        'Mix': 1.0,
      }),
      DawEffect('Reverb', {'Mix': 0.25, 'Size': 0.55, 'Decay': 0.48}),
    ],
  ),
  EffectChainPreset(
    id: 'Studio Lead Vocal',
    label: 'Vocal: Studio Lead',
    isVocal: true,
    buildChain: () => [
      DawEffect('EQ', {'Low': 0.30, 'Mid': 0.62, 'High': 0.78}),
      DawEffect('Compressor', {
        'Thresh': 0.42,
        'Ratio': 0.60,
        'Gain': 0.65,
        'Mix': 1.0,
      }),
      DawEffect('Echo', {'Delay': 0.16, 'Decay': 0.22, 'Mix': 0.18}),
      DawEffect('Reverb', {'Size': 0.42, 'Decay': 0.45, 'Mix': 0.22}),
    ],
  ),
  EffectChainPreset(
    id: 'Intimate Acoustic Vocal',
    label: 'Vocal: Intimate Dry',
    isVocal: true,
    buildChain: () => [
      DawEffect('EQ', {'Low': 0.35, 'Mid': 0.58, 'High': 0.68}),
      DawEffect('Compressor', {
        'Thresh': 0.50,
        'Ratio': 0.45,
        'Gain': 0.58,
        'Mix': 0.88,
      }),
      DawEffect('Reverb', {'Size': 0.28, 'Decay': 0.30, 'Mix': 0.12}),
    ],
  ),
  EffectChainPreset(
    id: 'Radio Broadcast',
    label: 'Vocal: Radio / Podcast',
    isVocal: true,
    buildChain: () => [
      DawEffect('EQ', {'Low': 0.42, 'Mid': 0.65, 'High': 0.68}),
      DawEffect('Compressor', {
        'Thresh': 0.32,
        'Ratio': 0.78,
        'Gain': 0.72,
        'Mix': 1.0,
      }),
      DawEffect('BassBoost', {'Boost': 0.35, 'Mix': 0.45}),
    ],
  ),
  EffectChainPreset(
    id: 'Dreamy Pop Doubler',
    label: 'Vocal: Dreamy Pop',
    isVocal: true,
    buildChain: () => [
      DawEffect('EQ', {'Low': 0.28, 'Mid': 0.56, 'High': 0.80}),
      DawEffect('Chorus', {'Rate': 0.35, 'Depth': 0.55, 'Mix': 0.38}),
      DawEffect('Compressor', {
        'Thresh': 0.46,
        'Ratio': 0.52,
        'Gain': 0.60,
        'Mix': 1.0,
      }),
      DawEffect('Reverb', {'Size': 0.68, 'Decay': 0.62, 'Mix': 0.36}),
    ],
  ),
  EffectChainPreset(
    id: 'Slapback Rock Vocal',
    label: 'Vocal: Slapback Rock',
    isVocal: true,
    buildChain: () => [
      DawEffect('EQ', {'Low': 0.32, 'Mid': 0.70, 'High': 0.66}),
      DawEffect('Overdrive', {'Drive': 0.22, 'Tone': 0.60, 'Level': 0.58}),
      DawEffect('Compressor', {
        'Thresh': 0.40,
        'Ratio': 0.62,
        'Gain': 0.62,
        'Mix': 1.0,
      }),
      DawEffect('Echo', {'Delay': 0.14, 'Decay': 0.18, 'Mix': 0.32}),
    ],
  ),
  EffectChainPreset(
    id: 'Lush Ballad Hall',
    label: 'Vocal: Lush Ballad',
    isVocal: true,
    buildChain: () => [
      DawEffect('EQ', {'Low': 0.34, 'Mid': 0.54, 'High': 0.74}),
      DawEffect('Compressor', {
        'Thresh': 0.48,
        'Ratio': 0.48,
        'Gain': 0.58,
        'Mix': 1.0,
      }),
      DawEffect('Echo', {'Delay': 0.38, 'Decay': 0.42, 'Mix': 0.26}),
      DawEffect('Reverb', {'Size': 0.82, 'Decay': 0.75, 'Mix': 0.42}),
    ],
  ),
  EffectChainPreset(
    id: 'Telephone Lo-Fi Vox',
    label: 'Vocal: Telephone / Megaphone',
    isVocal: true,
    buildChain: () => [
      DawEffect('EQ', {'Low': 0.08, 'Mid': 0.88, 'High': 0.12}),
      DawEffect('Overdrive', {'Drive': 0.38, 'Tone': 0.72, 'Level': 0.55}),
      DawEffect('Lofi', {'Rate': 0.18, 'Bits': 0.26, 'Mix': 0.55}),
    ],
  ),
  EffectChainPreset(
    id: 'Hyperpop Synth Vox',
    label: 'Vocal: Hyperpop / Synth Vox',
    isVocal: true,
    buildChain: () => [
      DawEffect('EQ', {'Low': 0.22, 'Mid': 0.68, 'High': 0.85}),
      DawEffect('Chorus', {'Rate': 0.55, 'Depth': 0.72, 'Mix': 0.45}),
      DawEffect('Robotize', {'Freq': 0.32, 'Mix': 0.45}),
      DawEffect('Compressor', {
        'Thresh': 0.36,
        'Ratio': 0.72,
        'Gain': 0.66,
        'Mix': 1.0,
      }),
    ],
  ),
];

/// Builds a fresh [DawEffect] list for [presetId], or empty for `'Clear Chain'`.
List<DawEffect>? buildEffectChainForPreset(String presetId) {
  if (presetId == 'Clear Chain') return <DawEffect>[];
  for (final preset in kEffectChainPresets) {
    if (preset.id == presetId) {
      return preset.buildChain();
    }
  }
  return null;
}
