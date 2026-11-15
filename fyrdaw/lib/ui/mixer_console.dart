import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:fyrdaw/main.dart';
import 'package:fyrdaw/models/enums.dart';
import 'package:fyrdaw/models/track.dart';
import 'package:fyrdaw/ui/dial.dart';
import 'package:fyrdaw/ui/meters.dart';

/// Modular Mixer Console strip bank: track channel strips (Sends, Pre-Fader toggles,
/// Pan, Fader, L/R VU meters, Mute/Solo), Aux Reverb & Delay return strips (with Solo),
/// and Master strip (FFT Spectrum, Limiter, LUFS target, Stereo Correlation, Reference A/B).
class MixerConsoleView extends StatelessWidget {
  final List<Track> tracks;
  final Map<String, (double, double)> trackLevels;
  final Map<String, (double, double)> trackPeaks;
  final double auxReverbMix;
  final double auxDelayMix;
  final (double, double) auxRevLevel;
  final (double, double) auxDlyLevel;
  final bool auxReverbSolo;
  final bool auxDelaySolo;
  final double masterVolume;
  final bool masterLimiter;
  final (double, double) masterLevel;
  final (double, double) masterPeak;
  final Float32List? masterVizSamples;
  final double masterLufs;
  final double masterLufsTarget;
  final double stereoCorrelation;
  final String? referenceTrackName;
  final bool isAuditioningReference;
  final bool midiLearnActive;
  final String? midiLearnTarget;
  final VoidCallback onSaveState;
  final void Function(Track track, double value) onTrackVolumeChanged;
  final void Function(Track track, double value) onTrackPanChanged;
  final void Function(Track track, double value) onTrackRevSendChanged;
  final void Function(Track track, double value) onTrackDlySendChanged;
  final void Function(Track track)? onToggleReverbPreFader;
  final void Function(Track track)? onToggleDelayPreFader;
  final void Function(Track track) onToggleMute;
  final void Function(Track track) onToggleSolo;
  final ValueChanged<double> onAuxReverbMixChanged;
  final ValueChanged<double> onAuxDelayMixChanged;
  final VoidCallback? onToggleAuxReverbSolo;
  final VoidCallback? onToggleAuxDelaySolo;
  final ValueChanged<double> onMasterVolumeChanged;
  final VoidCallback onToggleMasterLimiter;
  final VoidCallback? onCycleLufsTarget;
  final VoidCallback? onLoadReference;
  final VoidCallback? onToggleReferenceAB;
  final void Function(String trackId, String param)? onMidiLearnSelect;

  const MixerConsoleView({
    super.key,
    required this.tracks,
    required this.trackLevels,
    required this.trackPeaks,
    required this.auxReverbMix,
    required this.auxDelayMix,
    required this.auxRevLevel,
    required this.auxDlyLevel,
    this.auxReverbSolo = false,
    this.auxDelaySolo = false,
    required this.masterVolume,
    required this.masterLimiter,
    required this.masterLevel,
    required this.masterPeak,
    required this.masterVizSamples,
    required this.masterLufs,
    this.masterLufsTarget = -14.0,
    required this.stereoCorrelation,
    this.referenceTrackName,
    this.isAuditioningReference = false,
    this.midiLearnActive = false,
    this.midiLearnTarget,
    required this.onSaveState,
    required this.onTrackVolumeChanged,
    required this.onTrackPanChanged,
    required this.onTrackRevSendChanged,
    required this.onTrackDlySendChanged,
    this.onToggleReverbPreFader,
    this.onToggleDelayPreFader,
    required this.onToggleMute,
    required this.onToggleSolo,
    required this.onAuxReverbMixChanged,
    required this.onAuxDelayMixChanged,
    this.onToggleAuxReverbSolo,
    this.onToggleAuxDelaySolo,
    required this.onMasterVolumeChanged,
    required this.onToggleMasterLimiter,
    this.onCycleLufsTarget,
    this.onLoadReference,
    this.onToggleReferenceAB,
    this.onMidiLearnSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: tracks.length,
            itemBuilder: (context, index) {
              final t = tracks[index];
              final lvl = trackLevels[t.id] ?? (0.0, 0.0);
              final peak = trackPeaks[t.id] ?? (0.0, 0.0);
              return Container(
                width: 112,
                decoration: BoxDecoration(
                  color: panelDark.withValues(alpha: 0.45),
                  border: Border(right: BorderSide(color: panelLight)),
                ),
                child: Column(
                  children: [
                    Container(height: 3, color: t.color),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (t.type == TrackType.group)
                            Container(
                              margin: const EdgeInsets.only(right: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                color: lavenderAccent.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: Text(
                                'BUS',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: lavenderLight,
                                ),
                              ),
                            ),
                          Flexible(
                            child: Text(
                              t.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _dialItem(
                              'REV',
                              ValueDial(
                                value: t.reverbSend,
                                min: 0.0,
                                max: 1.0,
                                defaultValue: 0.0,
                                size: 18,
                                activeColor: Colors.cyanAccent,
                                formatLabel: (v) => 'Rev ${(v * 100).round()}%',
                                onChangeStart: onSaveState,
                                onChanged: (v) => onTrackRevSendChanged(t, v),
                              ),
                            ),
                            GestureDetector(
                              onTap: onToggleReverbPreFader != null
                                  ? () => onToggleReverbPreFader!(t)
                                  : null,
                              child: Text(
                                t.reverbPreFader ? 'PRE' : 'PST',
                                style: TextStyle(
                                  fontSize: 7,
                                  fontWeight: FontWeight.bold,
                                  color: t.reverbPreFader
                                      ? Colors.cyanAccent
                                      : textFaint,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _dialItem(
                              'DLY',
                              ValueDial(
                                value: t.delaySend,
                                min: 0.0,
                                max: 1.0,
                                defaultValue: 0.0,
                                size: 18,
                                activeColor: Colors.amberAccent,
                                formatLabel: (v) => 'Dly ${(v * 100).round()}%',
                                onChangeStart: onSaveState,
                                onChanged: (v) => onTrackDlySendChanged(t, v),
                              ),
                            ),
                            GestureDetector(
                              onTap: onToggleDelayPreFader != null
                                  ? () => onToggleDelayPreFader!(t)
                                  : null,
                              child: Text(
                                t.delayPreFader ? 'PRE' : 'PST',
                                style: TextStyle(
                                  fontSize: 7,
                                  fontWeight: FontWeight.bold,
                                  color: t.delayPreFader
                                      ? Colors.amberAccent
                                      : textFaint,
                                ),
                              ),
                            ),
                          ],
                        ),
                        _dialItem(
                          'PAN',
                          PanDial(
                            onChangeStart: onSaveState,
                            pan: t.pan,
                            size: 18,
                            onChanged: (v) => onTrackPanChanged(t, v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          RotatedBox(
                            quarterTurns: 3,
                            child: SliderTheme(
                              data: SliderThemeData(
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                ),
                                overlayShape: SliderComponentShape.noOverlay,
                              ),
                              child: Slider(
                                onChangeStart: (_) => onSaveState(),
                                value: t.volume.clamp(0.0, 1.0),
                                activeColor: t.color,
                                onChanged: (v) => onTrackVolumeChanged(t, v),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SegmentedVuMeter(
                            leftLevel: lvl.$1,
                            rightLevel: lvl.$2,
                            leftPeak: peak.$1,
                            rightPeak: peak.$2,
                            width: 14,
                            height: 112,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _msButton(
                          'M',
                          t.isMuted,
                          Colors.redAccent,
                          () => onToggleMute(t),
                        ),
                        const SizedBox(width: 4),
                        _msButton(
                          'S',
                          t.isSolo,
                          Colors.amber,
                          () => onToggleSolo(t),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: onMidiLearnSelect != null
                              ? () => onMidiLearnSelect!(t.id, 'volume')
                              : null,
                          child: Text(
                            midiLearnActive &&
                                    midiLearnTarget == '${t.id}:volume'
                                ? 'TWIST'
                                : '${(t.volume * 100).round()}%',
                            style: TextStyle(
                              fontSize: 10,
                              color: midiLearnActive
                                  ? Colors.amberAccent
                                  : textMuted,
                              fontWeight: midiLearnActive
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              );
            },
          ),
        ),
        _auxStrip(
          title: 'FX A: REV',
          accent: Colors.cyanAccent,
          value: auxReverbMix,
          level: auxRevLevel,
          isSolo: auxReverbSolo,
          onToggleSolo: onToggleAuxReverbSolo,
          onChanged: onAuxReverbMixChanged,
        ),
        _auxStrip(
          title: 'FX B: DLY',
          accent: Colors.amberAccent,
          value: auxDelayMix,
          level: auxDlyLevel,
          isSolo: auxDelaySolo,
          onToggleSolo: onToggleAuxDelaySolo,
          onChanged: onAuxDelayMixChanged,
        ),
        // Master Bus Strip with LUFS, Target & Reference A/B Compare
        Container(
          width: 204,
          color: panelDark,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'MASTER',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Row(
                    children: [
                      if (onToggleReferenceAB != null || onLoadReference != null)
                        GestureDetector(
                          onTap: referenceTrackName != null
                              ? onToggleReferenceAB
                              : onLoadReference,
                          onLongPress: onLoadReference,
                          child: Container(
                            margin: const EdgeInsets.only(right: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isAuditioningReference
                                  ? Colors.cyanAccent.withValues(alpha: 0.25)
                                  : bgDark,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isAuditioningReference
                                    ? Colors.cyanAccent
                                    : (referenceTrackName != null
                                          ? lavenderAccent
                                          : borderMain),
                              ),
                            ),
                            child: Text(
                              referenceTrackName == null
                                  ? '+REF'
                                  : (isAuditioningReference ? 'REF B' : 'MIX A'),
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: isAuditioningReference
                                    ? Colors.cyanAccent
                                    : textMuted,
                              ),
                            ),
                          ),
                        ),
                      GestureDetector(
                        onTap: onToggleMasterLimiter,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: masterLimiter
                                ? Colors.greenAccent.withValues(alpha: 0.2)
                                : bgDark,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: masterLimiter
                                  ? Colors.greenAccent
                                  : borderMain,
                            ),
                          ),
                          child: Text(
                            'LIMIT',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: masterLimiter
                                  ? Colors.greenAccent
                                  : textMuted,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              MasterSpectrumWidget(
                samples: masterVizSamples,
                width: 152,
                height: 22,
                accentColor: lavenderAccent,
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: GestureDetector(
                      onTap: onCycleLufsTarget,
                      child: Text(
                        masterLufs <= -59.0
                            ? '-∞/${masterLufsTarget.round()} LUFS'
                            : '${masterLufs.toStringAsFixed(1)}/${masterLufsTarget.round()} LUFS',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 8,
                          color: masterLufs > masterLufsTarget + 2.0
                              ? Colors.amberAccent
                              : textMuted,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  StereoCorrelationMeter(correlation: stereoCorrelation, width: 52),
                ],
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    RotatedBox(
                      quarterTurns: 3,
                      child: SliderTheme(
                        data: SliderThemeData(
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: SliderComponentShape.noOverlay,
                        ),
                        child: Slider(
                          onChangeStart: (_) => onSaveState(),
                          value: masterVolume.clamp(0.0, 1.0),
                          activeColor: Colors.redAccent,
                          onChanged: onMasterVolumeChanged,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SegmentedVuMeter(
                      leftLevel: masterLevel.$1,
                      rightLevel: masterLevel.$2,
                      leftPeak: masterPeak.$1,
                      rightPeak: masterPeak.$2,
                      width: 18,
                      height: 98,
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onMidiLearnSelect != null
                    ? () => onMidiLearnSelect!('__master__', 'volume')
                    : null,
                child: Text(
                  midiLearnActive && midiLearnTarget == '__master__:volume'
                      ? 'TWIST CC...'
                      : '${(masterVolume * 100).round()}%',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: midiLearnActive ? Colors.amberAccent : textMain,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dialItem(String label, Widget dial) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        dial,
        Text(label, style: TextStyle(fontSize: 8, color: textFaint)),
      ],
    );
  }

  Widget _msButton(String label, bool active, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 20,
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? color : bgDark,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: active ? color : borderMain),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: active ? Colors.black : textMuted,
          ),
        ),
      ),
    );
  }

  Widget _auxStrip({
    required String title,
    required Color accent,
    required double value,
    required (double, double) level,
    bool isSolo = false,
    VoidCallback? onToggleSolo,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      width: 100,
      decoration: BoxDecoration(
        color: bgDark,
        border: Border(
          left: BorderSide(color: panelLight, width: 2),
          right: BorderSide(color: panelLight),
        ),
      ),
      child: Column(
        children: [
          Container(height: 3, color: accent),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 9),
                  ),
                ),
                if (onToggleSolo != null) ...[
                  const SizedBox(width: 4),
                  _msButton('S', isSolo, Colors.amber, onToggleSolo),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RotatedBox(
                  quarterTurns: 3,
                  child: SliderTheme(
                    data: SliderThemeData(
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 5,
                      ),
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      onChangeStart: (_) => onSaveState(),
                      value: value.clamp(0.0, 1.0),
                      activeColor: accent,
                      onChanged: onChanged,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SegmentedVuMeter(
                  leftLevel: level.$1,
                  rightLevel: level.$2,
                  width: 10,
                  height: 112,
                ),
              ],
            ),
          ),
          Text(
            '${(value * 100).round()}%',
            style: TextStyle(fontSize: 10, color: textMuted),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

