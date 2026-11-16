import 'package:flutter/material.dart';
import 'package:fyrdaw/main.dart';
import 'package:fyrdaw/models/daw_clip.dart';
import 'package:fyrdaw/models/daw_effect.dart';
import 'package:fyrdaw/models/enums.dart';
import 'package:fyrdaw/models/midi_note.dart';
import 'package:fyrdaw/models/song_marker.dart';
import 'package:fyrdaw/models/track.dart';

class ProjectTemplateResult {
  final String name;
  final int bpm;
  final List<Track> tracks;
  final Map<String, List<DawClip>> trackClips;
  final List<SongMarker> markers;

  ProjectTemplateResult({
    required this.name,
    required this.bpm,
    required this.tracks,
    required this.trackClips,
    required this.markers,
  });
}

Future<ProjectTemplateResult?> showTemplatesDialog(BuildContext context) {
  final templates = [
    _TemplateInfo(
      id: 'empty',
      title: 'Empty Project',
      subtitle: 'Clean slate at 120 BPM with 1 Audio + 1 MIDI track.',
      icon: Icons.note_add_outlined,
      color: kTrackColorPalette[0],
      bpm: 120,
    ),
    _TemplateInfo(
      id: 'lofi',
      title: 'Lo-Fi Chill Sketch',
      subtitle: 'Rhodes chords, warm sine sub, vinyl Lofi pedal & 85 BPM groove.',
      icon: Icons.nights_stay_outlined,
      color: kTrackColorPalette[1],
      bpm: 85,
    ),
    _TemplateInfo(
      id: 'guitar_rig',
      title: 'Guitar + Vocals Rig',
      subtitle: 'Armed mic track + Overdrive -> GuitarAmp -> Reverb pedalboard.',
      icon: Icons.bolt,
      color: kTrackColorPalette[3],
      bpm: 112,
    ),
    _TemplateInfo(
      id: 'synthwave',
      title: 'Synthwave 4-Track',
      subtitle: 'Driving sawtooth bassline, square lead, warm pad & Chorus/Echo.',
      icon: Icons.waves,
      color: kTrackColorPalette[4],
      bpm: 118,
    ),
    _TemplateInfo(
      id: 'orchestral',
      title: 'Cinematic Strings & Piano',
      subtitle: 'Grand Piano, Solo Cello, String Ensemble & Hall Reverb.',
      icon: Icons.library_music_outlined,
      color: kTrackColorPalette[2],
      bpm: 92,
    ),
  ];

  return showDialog<ProjectTemplateResult>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: panelDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        width: 540,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: lavenderAccent),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'New Project from Template',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textMain,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.close, color: textMuted),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...templates.map(
              (tpl) => InkWell(
                onTap: () => Navigator.pop(ctx, _buildTemplate(tpl.id)),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: panelLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: tpl.color.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: tpl.color.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(tpl.icon, color: tpl.color),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    tpl.title,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: textMain,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: bgDark,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${tpl.bpm} BPM',
                                    style: TextStyle(
                                      color: textMuted,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              tpl.subtitle,
                              style: TextStyle(color: textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: textMuted),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _TemplateInfo {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final int bpm;

  _TemplateInfo({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.bpm,
  });
}

ProjectTemplateResult _buildTemplate(String id) {
  final tracks = <Track>[];
  final clips = <String, List<DawClip>>{};
  final markers = <SongMarker>[];
  int bpm = 120;

  double beatW(int b) => 100.0 * 60.0 / b;

  MidiClip makeChordClip(
    String name,
    Color color,
    int bpmVal,
    List<(double, double, List<int>, int)> chords,
  ) {
    final bw = beatW(bpmVal);
    final notes = <MidiNote>[];
    double maxEnd = bw * 4;
    for (final (beatStart, beatDur, pitches, vel) in chords) {
      final s = beatStart * bw;
      final l = beatDur * bw;
      if (s + l > maxEnd) maxEnd = s + l;
      for (final p in pitches) {
        notes.add(MidiNote(pitch: p, start: s, length: l, velocity: vel));
      }
    }
    return MidiClip(
      id: UniqueKey().toString(),
      name: name,
      start: 0.0,
      length: maxEnd,
      color: color,
      notes: notes,
    );
  }

  if (id == 'empty') {
    final t1 = Track(
      id: 't_${DateTime.now().millisecondsSinceEpoch}_1',
      name: 'Audio 1',
      type: TrackType.audio,
      colorValue: kTrackColorPalette[0].toARGB32(),
    );
    final t2 = Track(
      id: 't_${DateTime.now().millisecondsSinceEpoch}_2',
      name: 'MIDI 1',
      type: TrackType.midi,
      colorValue: kTrackColorPalette[1].toARGB32(),
    )..instrumentIndex = 3;
    tracks.addAll([t1, t2]);
    clips[t1.id] = [];
    clips[t2.id] = [];
  } else if (id == 'lofi') {
    bpm = 85;
    final bw = beatW(bpm);
    final keys = Track(
      id: 't_lofi_keys',
      name: 'Rhodes Chords',
      type: TrackType.midi,
      colorValue: kTrackColorPalette[1].toARGB32(),
    )
      ..instrumentIndex = 6
      ..reverbSend = 0.35
      ..effectsChain = [
        DawEffect('Lofi', {'Rate': 0.15, 'Bits': 0.25, 'Mix': 0.45}),
        DawEffect('EQ', {'Low': 0.42, 'Mid': 0.55, 'High': 0.38}),
      ];
    final sub = Track(
      id: 't_lofi_sub',
      name: 'Warm Sub Bass',
      type: TrackType.midi,
      colorValue: kTrackColorPalette[2].toARGB32(),
    )
      ..instrumentIndex = 2
      ..volume = 0.7;
    final drums = Track(
      id: 't_lofi_drums',
      name: 'Sampler Kit',
      type: TrackType.sampler,
      colorValue: kTrackColorPalette[3].toARGB32(),
    );
    tracks.addAll([keys, sub, drums]);
    clips[keys.id] = [
      makeChordClip('Cm9 - Fm9', keys.color, bpm, [
        (0.0, 3.8, [60, 63, 67, 70, 74], 82),
        (4.0, 3.8, [53, 56, 60, 63, 67], 78),
        (8.0, 3.8, [58, 62, 65, 68, 72], 80),
        (12.0, 3.8, [55, 59, 62, 65, 69], 84),
      ]),
    ];
    clips[sub.id] = [
      makeChordClip('Sub Roots', sub.color, bpm, [
        (0.0, 3.5, [36], 100),
        (4.0, 3.5, [41], 100),
        (8.0, 3.5, [46], 100),
        (12.0, 3.5, [43], 100),
      ]),
    ];
    clips[drums.id] = [
      MidiClip(
        id: 'c_lofi_drums',
        name: 'Pattern 1',
        start: 0.0,
        length: bw * 16,
        color: drums.color,
      ),
    ];
    markers.addAll([
      SongMarker(id: 'm1', label: 'Intro', position: 0.0, colorValue: 0xFF38BDF8),
      SongMarker(id: 'm2', label: 'Verse', position: bw * 16, colorValue: 0xFF34D399),
    ]);
  } else if (id == 'guitar_rig') {
    bpm = 112;
    final bw = beatW(bpm);
    final vox = Track(
      id: 't_vox',
      name: 'Lead Vocals',
      type: TrackType.audio,
      colorValue: kTrackColorPalette[4].toARGB32(),
    )
      ..isArmed = true
      ..reverbSend = 0.3
      ..delaySend = 0.2
      ..effectsChain = [
        DawEffect('EQ', {'Low': 0.38, 'Mid': 0.56, 'High': 0.64}),
        DawEffect('Compressor', {'Thresh': 0.55, 'Ratio': 0.5, 'Gain': 0.55, 'Mix': 1.0}),
      ];
    final gtr = Track(
      id: 't_gtr',
      name: 'Crunch Guitar',
      type: TrackType.audio,
      colorValue: kTrackColorPalette[3].toARGB32(),
    )
      ..effectsChain = [
        DawEffect('Overdrive', {'Drive': 0.45, 'Tone': 0.55, 'Level': 0.55}),
        DawEffect('GuitarAmp', {'Drive': 0.65, 'Tone': 0.58, 'Level': 0.52}),
        DawEffect('Reverb', {'Size': 0.4, 'Decay': 0.35, 'Mix': 0.25}),
      ];
    final bass = Track(
      id: 't_bass_gtr',
      name: 'Bass Guide',
      type: TrackType.midi,
      colorValue: kTrackColorPalette[2].toARGB32(),
    )..instrumentIndex = 1;
    tracks.addAll([vox, gtr, bass]);
    clips[vox.id] = [];
    clips[gtr.id] = [];
    clips[bass.id] = [
      makeChordClip('Bass Riff', bass.color, bpm, [
        (0.0, 1.5, [40], 105),
        (2.0, 1.5, [40], 95),
        (4.0, 1.5, [43], 105),
        (6.0, 1.5, [45], 105),
      ]),
    ];
    markers.addAll([
      SongMarker(id: 'm1', label: 'Intro', position: 0.0, colorValue: 0xFFFBBF24),
      SongMarker(id: 'm2', label: 'Chorus', position: bw * 8, colorValue: 0xFFF472B6),
    ]);
  } else if (id == 'synthwave') {
    bpm = 118;
    final bw = beatW(bpm);
    final arp = Track(
      id: 't_sw_bass',
      name: 'Sawtooth Arp',
      type: TrackType.midi,
      colorValue: kTrackColorPalette[4].toARGB32(),
    )
      ..instrumentIndex = 1
      ..delaySend = 0.25
      ..effectsChain = [
        DawEffect('Chorus', {'Rate': 0.4, 'Depth': 0.6, 'Mix': 0.45}),
      ];
    final pad = Track(
      id: 't_sw_pad',
      name: 'Warm Pad',
      type: TrackType.midi,
      colorValue: kTrackColorPalette[0].toARGB32(),
    )
      ..instrumentIndex = 16
      ..volume = 0.65
      ..reverbSend = 0.45;
    final lead = Track(
      id: 't_sw_lead',
      name: 'Square Lead',
      type: TrackType.midi,
      colorValue: kTrackColorPalette[1].toARGB32(),
    )
      ..instrumentIndex = 0
      ..delaySend = 0.4
      ..reverbSend = 0.3;
    final kit = Track(
      id: 't_sw_kit',
      name: 'Drum Machine',
      type: TrackType.sampler,
      colorValue: kTrackColorPalette[5].toARGB32(),
    );
    tracks.addAll([arp, pad, lead, kit]);

    final bassNotes = <(double, double, List<int>, int)>[];
    for (int i = 0; i < 16; i++) {
      final root = i < 8 ? 33 : 29;
      bassNotes.add((i * 0.5, 0.42, [root + (i.isOdd ? 12 : 0)], 105));
    }
    clips[arp.id] = [makeChordClip('16th Pulse', arp.color, bpm, bassNotes)];
    clips[pad.id] = [
      makeChordClip('Am - F', pad.color, bpm, [
        (0.0, 3.9, [57, 60, 64, 69], 75),
        (4.0, 3.9, [53, 57, 60, 65], 75),
      ]),
    ];
    clips[lead.id] = [
      makeChordClip('Hook', lead.color, bpm, [
        (0.0, 1.5, [69], 95),
        (1.5, 1.5, [72], 98),
        (3.0, 1.0, [76], 102),
        (4.0, 3.5, [74], 96),
      ]),
    ];
    clips[kit.id] = [
      MidiClip(
        id: 'c_sw_kit',
        name: '80s Kit',
        start: 0.0,
        length: bw * 8,
        color: kit.color,
      ),
    ];
    markers.addAll([
      SongMarker(id: 'm1', label: 'Intro', position: 0.0, colorValue: 0xFFF472B6),
      SongMarker(id: 'm2', label: 'Drop', position: bw * 8, colorValue: 0xFF38BDF8),
    ]);
  } else {
    bpm = 92;
    final bw = beatW(bpm);
    final piano = Track(
      id: 't_orch_piano',
      name: 'Grand Piano',
      type: TrackType.midi,
      colorValue: kTrackColorPalette[2].toARGB32(),
    )
      ..instrumentIndex = 3
      ..reverbSend = 0.4;
    final strings = Track(
      id: 't_orch_strings',
      name: 'String Ensemble',
      type: TrackType.midi,
      colorValue: kTrackColorPalette[6].toARGB32(),
    )
      ..instrumentIndex = 7
      ..volume = 0.68
      ..reverbSend = 0.55;
    final cello = Track(
      id: 't_orch_cello',
      name: 'Solo Cello',
      type: TrackType.midi,
      colorValue: kTrackColorPalette[3].toARGB32(),
    )
      ..instrumentIndex = 4
      ..reverbSend = 0.4;
    tracks.addAll([piano, strings, cello]);
    clips[piano.id] = [
      makeChordClip('Arpeggio', piano.color, bpm, [
        (0.0, 1.8, [60, 64, 67], 82),
        (2.0, 1.8, [62, 65, 69], 85),
        (4.0, 3.8, [60, 64, 67, 71], 88),
      ]),
    ];
    clips[strings.id] = [
      makeChordClip('Swell', strings.color, bpm, [
        (0.0, 7.8, [60, 67, 72], 78),
      ]),
    ];
    clips[cello.id] = [
      makeChordClip('Cello Line', cello.color, bpm, [
        (0.0, 3.8, [48], 92),
        (4.0, 3.8, [55], 96),
      ]),
    ];
    markers.add(
      SongMarker(id: 'm1', label: 'Theme A', position: 0.0, colorValue: 0xFF34D399),
    );
    if (bw > 0) {
      markers.add(
        SongMarker(id: 'm2', label: 'Crescendo', position: bw * 8, colorValue: 0xFFFBBF24),
      );
    }
  }

  return ProjectTemplateResult(
    name: id,
    bpm: bpm,
    tracks: tracks,
    trackClips: clips,
    markers: markers,
  );
}

