import 'package:flutter/material.dart';

enum TrackType { audio, midi, sampler }

enum ClipType { audio, midi }

class InstrumentPreset {
  final int index;
  final String name;
  final String category;
  final String description;
  final String assetPath;
  final int basePitch;
  final int loopPointMs;
  final int releaseMs;
  final double volumeMultiplier;
  final IconData icon;

  const InstrumentPreset({
    required this.index,
    required this.name,
    required this.category,
    required this.description,
    required this.assetPath,
    required this.basePitch,
    this.loopPointMs = 1000,
    this.releaseMs = 140,
    this.volumeMultiplier = 1.0,
    required this.icon,
  });
}

const List<InstrumentPreset> kInstrumentPresets = [
  InstrumentPreset(
    index: 0,
    name: 'Square Lead',
    category: 'Synth & Bass',
    description: 'Warm analog PWM lead with subtle vibrato and unlimited sustain.',
    assetPath: 'assets/samples/synth_c4.wav',
    basePitch: 60,
    loopPointMs: 1000,
    releaseMs: 90,
    volumeMultiplier: 0.95,
    icon: Icons.graphic_eq,
  ),
  InstrumentPreset(
    index: 1,
    name: 'Sawtooth Bass',
    category: 'Synth & Bass',
    description: 'Fat unison analog sawtooth bass with resonant lowpass punch and sub.',
    assetPath: 'assets/samples/saw_c3.wav',
    basePitch: 48,
    loopPointMs: 1000,
    releaseMs: 85,
    volumeMultiplier: 1.0,
    icon: Icons.waves,
  ),
  InstrumentPreset(
    index: 2,
    name: 'Sine Sub',
    category: 'Synth & Bass',
    description: 'Deep studio sub-bass with warm tube harmonics and infinite sustain.',
    assetPath: 'assets/samples/sine_c3.wav',
    basePitch: 48,
    loopPointMs: 1000,
    releaseMs: 100,
    volumeMultiplier: 1.05,
    icon: Icons.blur_on,
  ),
  InstrumentPreset(
    index: 3,
    name: 'Grand Piano',
    category: 'Keys & Organ',
    description: 'Concert grand piano with felt hammer attack and sympathetic string sustain.',
    assetPath: 'assets/samples/piano_c4.wav',
    basePitch: 60,
    loopPointMs: 1000,
    releaseMs: 180,
    volumeMultiplier: 1.25,
    icon: Icons.piano,
  ),
  InstrumentPreset(
    index: 4,
    name: 'Solo Cello',
    category: 'Strings & Orchestral',
    description: 'Rich acoustic cello with rosin bow bite, wood resonance, and endless vibrato.',
    assetPath: 'assets/samples/cello_c3.wav',
    basePitch: 48,
    loopPointMs: 1000,
    releaseMs: 170,
    volumeMultiplier: 1.15,
    icon: Icons.music_note,
  ),
  InstrumentPreset(
    index: 5,
    name: 'Solo Violin',
    category: 'Strings & Orchestral',
    description: 'Expressive solo violin with natural bow articulation and singing sustain.',
    assetPath: 'assets/samples/violin_c4.wav',
    basePitch: 60,
    loopPointMs: 1000,
    releaseMs: 160,
    volumeMultiplier: 1.1,
    icon: Icons.music_note,
  ),
  InstrumentPreset(
    index: 6,
    name: 'Electric Piano (Rhodes)',
    category: 'Keys & Organ',
    description: 'Vintage tine electric piano with bell chime, warm bark, and stereo tremolo.',
    assetPath: 'assets/samples/epiano_c4.wav',
    basePitch: 60,
    loopPointMs: 1000,
    releaseMs: 160,
    volumeMultiplier: 1.15,
    icon: Icons.piano,
  ),
  InstrumentPreset(
    index: 7,
    name: 'String Ensemble',
    category: 'Strings & Orchestral',
    description: 'Lush 8-player symphonic string section with rich stereo orchestral sustain.',
    assetPath: 'assets/samples/strings_c4.wav',
    basePitch: 60,
    loopPointMs: 1000,
    releaseMs: 240,
    volumeMultiplier: 1.15,
    icon: Icons.library_music,
  ),
  InstrumentPreset(
    index: 8,
    name: 'Clean Electric Guitar',
    category: 'Guitars',
    description: 'Neck/middle pickup electric guitar with crisp pick attack and long sustain.',
    assetPath: 'assets/samples/clean_guitar_c3.wav',
    basePitch: 48,
    loopPointMs: 1000,
    releaseMs: 150,
    volumeMultiplier: 1.2,
    icon: Icons.audiotrack,
  ),
  InstrumentPreset(
    index: 9,
    name: 'Overdriven Guitar',
    category: 'Guitars',
    description: 'Singing rock/blues lead electric guitar with harmonic feedback sustain.',
    assetPath: 'assets/samples/overdrive_guitar_c3.wav',
    basePitch: 48,
    loopPointMs: 1000,
    releaseMs: 150,
    volumeMultiplier: 1.1,
    icon: Icons.bolt,
  ),
  InstrumentPreset(
    index: 10,
    name: 'Acoustic Guitar',
    category: 'Guitars',
    description: 'Warm fingerstyle acoustic guitar with spruce top resonance and sustained tail.',
    assetPath: 'assets/samples/acoustic_guitar_c3.wav',
    basePitch: 48,
    loopPointMs: 1000,
    releaseMs: 160,
    volumeMultiplier: 1.2,
    icon: Icons.music_video,
  ),
  InstrumentPreset(
    index: 11,
    name: 'Hammond B3 Organ',
    category: 'Keys & Organ',
    description: '9-drawbar tonewheel organ with key click, percussion, and Leslie rotary speaker.',
    assetPath: 'assets/samples/organ_c4.wav',
    basePitch: 60,
    loopPointMs: 1000,
    releaseMs: 75,
    volumeMultiplier: 1.05,
    icon: Icons.dns,
  ),
  InstrumentPreset(
    index: 12,
    name: 'Cathedral Pipe Organ',
    category: 'Keys & Organ',
    description: 'Coupled diapason, principal, and flute ranks with pipe wind chiff and infinite sustain.',
    assetPath: 'assets/samples/pipe_organ_c4.wav',
    basePitch: 60,
    loopPointMs: 1000,
    releaseMs: 200,
    volumeMultiplier: 1.1,
    icon: Icons.account_balance,
  ),
  InstrumentPreset(
    index: 13,
    name: 'Brass Section',
    category: 'Strings & Orchestral',
    description: 'Warm French horn, trombone, and trumpet ensemble with golden brass swell.',
    assetPath: 'assets/samples/brass_c4.wav',
    basePitch: 60,
    loopPointMs: 1000,
    releaseMs: 150,
    volumeMultiplier: 1.15,
    icon: Icons.campaign,
  ),
  InstrumentPreset(
    index: 14,
    name: 'Concert Flute',
    category: 'Strings & Orchestral',
    description: 'Silver concert flute with breathy chiff attack and expressive vibrato sustain.',
    assetPath: 'assets/samples/flute_c4.wav',
    basePitch: 60,
    loopPointMs: 1000,
    releaseMs: 130,
    volumeMultiplier: 1.15,
    icon: Icons.air,
  ),
  InstrumentPreset(
    index: 15,
    name: 'Choir Pad (Ahh)',
    category: 'Pads & Choir',
    description: 'Multi-voice formant-shaped vocal choir ensemble with endless lush sustain.',
    assetPath: 'assets/samples/choir_c4.wav',
    basePitch: 60,
    loopPointMs: 1000,
    releaseMs: 240,
    volumeMultiplier: 1.1,
    icon: Icons.record_voice_over,
  ),
  InstrumentPreset(
    index: 16,
    name: 'Analog Warm Pad',
    category: 'Pads & Choir',
    description: '6-voice unison polysynth pad with stereo filter movement and infinite sustain.',
    assetPath: 'assets/samples/warm_pad_c4.wav',
    basePitch: 60,
    loopPointMs: 1000,
    releaseMs: 250,
    volumeMultiplier: 1.1,
    icon: Icons.cloud,
  ),
];

InstrumentPreset getInstrumentPreset(int index) {
  for (final p in kInstrumentPresets) {
    if (p.index == index) return p;
  }
  return kInstrumentPresets.first;
}

String getInstrumentName(int index) => getInstrumentPreset(index).name;
