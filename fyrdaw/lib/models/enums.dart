import 'package:flutter/material.dart';

enum TrackType { audio, midi, sampler, group }

enum ClipType { audio, midi }

enum ArpMode { up, down, upDown, random }

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
  InstrumentPreset(
    index: 17,
    name: 'Nylon Spanish Guitar',
    category: 'Guitars & Bass',
    description: 'Warm fingerstyle classical nylon guitar with spruce body resonance.',
    assetPath: 'assets/samples/nylon_guitar_c3.wav',
    basePitch: 48,
    loopPointMs: 1000,
    releaseMs: 180,
    volumeMultiplier: 1.15,
    icon: Icons.music_note,
  ),
  InstrumentPreset(
    index: 18,
    name: 'Upright Acoustic Bass',
    category: 'Guitars & Bass',
    description: 'Woody jazz pizzicato double bass with fingerboard knock and deep sustain.',
    assetPath: 'assets/samples/upright_bass_c2.wav',
    basePitch: 36,
    loopPointMs: 1000,
    releaseMs: 140,
    volumeMultiplier: 1.2,
    icon: Icons.graphic_eq,
  ),
  InstrumentPreset(
    index: 19,
    name: 'Fingered Electric Bass',
    category: 'Guitars & Bass',
    description: 'Vintage P-Bass roundwound pluck with warm low-mid growl and punch.',
    assetPath: 'assets/samples/finger_bass_c2.wav',
    basePitch: 36,
    loopPointMs: 1000,
    releaseMs: 120,
    volumeMultiplier: 1.2,
    icon: Icons.electric_bolt,
  ),
  InstrumentPreset(
    index: 20,
    name: 'Warm Felted Piano',
    category: 'Keys & Mallets',
    description: 'Intimate studio upright piano with soft felt hammers and cabinet bloom.',
    assetPath: 'assets/samples/jazz_piano_c4.wav',
    basePitch: 60,
    loopPointMs: 1000,
    releaseMs: 200,
    volumeMultiplier: 1.15,
    icon: Icons.piano,
  ),
  InstrumentPreset(
    index: 21,
    name: 'Concert Marimba',
    category: 'Keys & Mallets',
    description: 'Tuned rosewood bar mallet instrument with natural woody resonator sustain.',
    assetPath: 'assets/samples/marimba_c4.wav',
    basePitch: 60,
    loopPointMs: 1000,
    releaseMs: 160,
    volumeMultiplier: 1.15,
    icon: Icons.view_week,
  ),
  InstrumentPreset(
    index: 22,
    name: 'Concert Harp',
    category: 'Keys & Mallets',
    description: 'Shimmering stereo plucked gut strings with orchestral hall ambience.',
    assetPath: 'assets/samples/harp_c4.wav',
    basePitch: 60,
    loopPointMs: 1000,
    releaseMs: 240,
    volumeMultiplier: 1.15,
    icon: Icons.auto_awesome,
  ),
  InstrumentPreset(
    index: 23,
    name: 'FM Glassy Bell',
    category: 'Keys & Mallets',
    description: 'Sparkling 4-operator FM electric tine bell with wide stereo chime.',
    assetPath: 'assets/samples/fm_bell_c4.wav',
    basePitch: 60,
    loopPointMs: 1000,
    releaseMs: 220,
    volumeMultiplier: 1.1,
    icon: Icons.notifications_active,
  ),
  InstrumentPreset(
    index: 24,
    name: 'Tenor / Alto Sax',
    category: 'Strings & Orchestral',
    description: 'Expressive conical-bore reed sax with breath onset and warm vibrato.',
    assetPath: 'assets/samples/sax_c4.wav',
    basePitch: 60,
    loopPointMs: 1000,
    releaseMs: 130,
    volumeMultiplier: 1.15,
    icon: Icons.mic,
  ),
  InstrumentPreset(
    index: 25,
    name: 'Supersaw Trance Lead',
    category: 'Synth & Leads',
    description: '7-voice stereo detuned supersaw stack for euphoric leads and chords.',
    assetPath: 'assets/samples/supersaw_c4.wav',
    basePitch: 60,
    loopPointMs: 1000,
    releaseMs: 140,
    volumeMultiplier: 1.05,
    icon: Icons.waves,
  ),
  InstrumentPreset(
    index: 26,
    name: 'Analog Poly Brass',
    category: 'Synth & Leads',
    description: '80s dual-saw polysynth brass swell with bright filter bite.',
    assetPath: 'assets/samples/synth_brass_c3.wav',
    basePitch: 48,
    loopPointMs: 1000,
    releaseMs: 160,
    volumeMultiplier: 1.1,
    icon: Icons.surround_sound,
  ),
  InstrumentPreset(
    index: 27,
    name: 'Acid 303 Bass',
    category: 'Synth & Leads',
    description: 'Resonant squelching analog saw bass with gritty diode saturation.',
    assetPath: 'assets/samples/acid_bass_c2.wav',
    basePitch: 36,
    loopPointMs: 1000,
    releaseMs: 80,
    volumeMultiplier: 1.1,
    icon: Icons.equalizer,
  ),
  InstrumentPreset(
    index: 28,
    name: 'Pure Deep Sine Bass',
    category: 'Sine & 808 Bass',
    description: 'Clean sub-bass sine wave with gentle tube warmth for chest-rattling lows.',
    assetPath: 'assets/samples/deep_sine_c2.wav',
    basePitch: 36,
    loopPointMs: 1000,
    releaseMs: 90,
    volumeMultiplier: 1.25,
    icon: Icons.lens_blur,
  ),
  InstrumentPreset(
    index: 29,
    name: '808 Boom Sub',
    category: 'Sine & 808 Bass',
    description: 'Punchy pitch-dropped 808 sub bass with tape harmonics that cut through mixes.',
    assetPath: 'assets/samples/sub_808_c2.wav',
    basePitch: 36,
    loopPointMs: 1000,
    releaseMs: 110,
    volumeMultiplier: 1.25,
    icon: Icons.speaker,
  ),
  InstrumentPreset(
    index: 30,
    name: 'Detuned Reese Sub',
    category: 'Sine & 808 Bass',
    description: 'Dark stereo detuned saw + locked sub fundamental for DnB, trap, and halftime.',
    assetPath: 'assets/samples/reese_bass_c2.wav',
    basePitch: 36,
    loopPointMs: 1000,
    releaseMs: 120,
    volumeMultiplier: 1.15,
    icon: Icons.blur_on,
  ),
];

InstrumentPreset getInstrumentPreset(int index) {
  for (final p in kInstrumentPresets) {
    if (p.index == index) return p;
  }
  return kInstrumentPresets.first;
}

String getInstrumentName(int index) => getInstrumentPreset(index).name;

class DrumPadSpec {
  final int padIndex;
  final String label;
  final String assetPath;
  final int midiNote;
  final int chokeGroup;

  const DrumPadSpec({
    required this.padIndex,
    required this.label,
    required this.assetPath,
    required this.midiNote,
    this.chokeGroup = 0,
  });
}

class DrumKitPreset {
  final String id;
  final String name;
  final String description;
  final List<DrumPadSpec> pads;

  const DrumKitPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.pads,
  });
}

const List<DrumKitPreset> kDrumKits = [
  DrumKitPreset(
    id: 'acoustic_studio',
    name: 'Acoustic Studio Kit',
    description: 'Punchy studio birch shells, crisp snare wires, B20 hats, and natural room reflections.',
    pads: [
      DrumPadSpec(padIndex: 0, label: 'Kick', assetPath: 'assets/samples/drums/studio_kick.wav', midiNote: 36),
      DrumPadSpec(padIndex: 1, label: 'Rimshot', assetPath: 'assets/samples/drums/studio_rim.wav', midiNote: 37),
      DrumPadSpec(padIndex: 2, label: 'Snare', assetPath: 'assets/samples/drums/studio_snare.wav', midiNote: 38),
      DrumPadSpec(padIndex: 3, label: 'Clap', assetPath: 'assets/samples/drums/studio_clap.wav', midiNote: 39),
      DrumPadSpec(padIndex: 4, label: 'Tight Snare', assetPath: 'assets/samples/drums/studio_snare_tight.wav', midiNote: 40),
      DrumPadSpec(padIndex: 5, label: 'Low Tom', assetPath: 'assets/samples/drums/studio_tom_low.wav', midiNote: 41),
      DrumPadSpec(padIndex: 6, label: 'Closed Hat', assetPath: 'assets/samples/drums/studio_chh.wav', midiNote: 42, chokeGroup: 1),
      DrumPadSpec(padIndex: 7, label: 'Mid Tom', assetPath: 'assets/samples/drums/studio_tom_mid.wav', midiNote: 43),
      DrumPadSpec(padIndex: 8, label: 'Pedal Hat', assetPath: 'assets/samples/drums/studio_phh.wav', midiNote: 44, chokeGroup: 1),
      DrumPadSpec(padIndex: 9, label: 'High Tom', assetPath: 'assets/samples/drums/studio_tom_hi.wav', midiNote: 45),
      DrumPadSpec(padIndex: 10, label: 'Open Hat', assetPath: 'assets/samples/drums/studio_ohh.wav', midiNote: 46, chokeGroup: 1),
      DrumPadSpec(padIndex: 11, label: 'Tambourine', assetPath: 'assets/samples/drums/studio_tamb.wav', midiNote: 47),
      DrumPadSpec(padIndex: 12, label: 'Crash', assetPath: 'assets/samples/drums/studio_crash.wav', midiNote: 48),
      DrumPadSpec(padIndex: 13, label: 'Ride', assetPath: 'assets/samples/drums/studio_ride.wav', midiNote: 49),
    ],
  ),
  DrumKitPreset(
    id: '808_trap',
    name: '808 Trap Kit',
    description: 'Deep analog 808 sub kicks, crisp hats, claps, cowbell, and bridged-T snares.',
    pads: [
      DrumPadSpec(padIndex: 0, label: '808 Kick', assetPath: 'assets/samples/drums/808_kick.wav', midiNote: 36),
      DrumPadSpec(padIndex: 1, label: '808 Rim', assetPath: 'assets/samples/drums/808_rim.wav', midiNote: 37),
      DrumPadSpec(padIndex: 2, label: '808 Snare', assetPath: 'assets/samples/drums/808_snare.wav', midiNote: 38),
      DrumPadSpec(padIndex: 3, label: '808 Clap', assetPath: 'assets/samples/drums/808_clap.wav', midiNote: 39),
      DrumPadSpec(padIndex: 4, label: 'Hard 808', assetPath: 'assets/samples/drums/808_sub_hard.wav', midiNote: 40),
      DrumPadSpec(padIndex: 5, label: '808 Low Tom', assetPath: 'assets/samples/drums/808_tom_low.wav', midiNote: 41),
      DrumPadSpec(padIndex: 6, label: '808 CHH', assetPath: 'assets/samples/drums/808_chh.wav', midiNote: 42, chokeGroup: 1),
      DrumPadSpec(padIndex: 7, label: '808 Mid Tom', assetPath: 'assets/samples/drums/808_tom_mid.wav', midiNote: 43),
      DrumPadSpec(padIndex: 8, label: '808 Shaker', assetPath: 'assets/samples/drums/808_maraca.wav', midiNote: 44, chokeGroup: 1),
      DrumPadSpec(padIndex: 9, label: 'Cowbell', assetPath: 'assets/samples/drums/808_cowbell.wav', midiNote: 45),
      DrumPadSpec(padIndex: 10, label: '808 OHH', assetPath: 'assets/samples/drums/808_ohh.wav', midiNote: 46, chokeGroup: 1),
      DrumPadSpec(padIndex: 11, label: 'Clave', assetPath: 'assets/samples/drums/808_clave.wav', midiNote: 47),
    ],
  ),
  DrumKitPreset(
    id: 'vintage_lofi',
    name: 'Vintage Boom-Bap Kit',
    description: 'Warm SP-1200/MPC dusty breaks with saturated punch and mellow hats.',
    pads: [
      DrumPadSpec(padIndex: 0, label: 'Dusty Kick', assetPath: 'assets/samples/drums/lofi_kick.wav', midiNote: 36),
      DrumPadSpec(padIndex: 1, label: 'Wood Knock', assetPath: 'assets/samples/drums/lofi_rim.wav', midiNote: 37),
      DrumPadSpec(padIndex: 2, label: 'Crack Snare', assetPath: 'assets/samples/drums/lofi_snare.wav', midiNote: 38),
      DrumPadSpec(padIndex: 3, label: 'Vinyl Clap', assetPath: 'assets/samples/drums/lofi_clap.wav', midiNote: 39),
      DrumPadSpec(padIndex: 5, label: 'Sub Thump', assetPath: 'assets/samples/drums/lofi_thump.wav', midiNote: 41),
      DrumPadSpec(padIndex: 6, label: 'Lo-Fi CHH', assetPath: 'assets/samples/drums/lofi_chh.wav', midiNote: 42, chokeGroup: 1),
      DrumPadSpec(padIndex: 8, label: 'Shaker', assetPath: 'assets/samples/drums/lofi_shaker.wav', midiNote: 44, chokeGroup: 1),
      DrumPadSpec(padIndex: 10, label: 'Lo-Fi OHH', assetPath: 'assets/samples/drums/lofi_ohh.wav', midiNote: 46, chokeGroup: 1),
      DrumPadSpec(padIndex: 11, label: 'Bongo', assetPath: 'assets/samples/drums/lofi_bongo.wav', midiNote: 47),
      DrumPadSpec(padIndex: 12, label: 'Splash', assetPath: 'assets/samples/drums/lofi_splash.wav', midiNote: 48),
    ],
  ),
];

DrumKitPreset? findDrumKitById(String id) {
  for (final k in kDrumKits) {
    if (k.id == id) return k;
  }
  return null;
}
