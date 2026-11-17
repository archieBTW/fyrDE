import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:fyrdaw/models/daw_clip.dart';
import 'package:fyrdaw/models/daw_effect.dart';
import 'package:fyrdaw/models/enums.dart';
import 'package:fyrdaw/models/sampler_pad.dart';
import 'package:fyrdaw/models/tempo_marker.dart';
import 'package:fyrdaw/models/track.dart';
import 'package:fyrdaw/utils/audio_utils.dart';
import 'package:fyrdaw/utils/mixdown_dsp.dart';
import 'package:fyrdaw/utils/parametric_eq_dsp.dart';
import 'package:fyrdaw/utils/plugin_host.dart';
import 'package:fyrdaw/utils/time_stretch.dart';
import 'package:fyrdaw/wav_writer.dart';

class MixdownRenderer {
  static const int sampleRate = 44100;
  static const double unitsPerSecond = 100.0;

  /// Renders either the full project (when [onlyTrack] is null) or a single
  /// track (when [onlyTrack] is provided) into a stereo 16-bit WAV file at
  /// [outWavPath]. Returns true if any audio was rendered.
  static Future<bool> renderToWav({
    required List<Track> tracks,
    required Map<String, List<DawClip>> trackClips,
    required String outWavPath,
    required int bpm,
    double? beatWidth,
    Track? onlyTrack,
    double masterVolume = 1.0,
    bool masterLimiter = true,
    double auxReverbMix = 0.85,
    double auxDelayMix = 0.75,
    bool auxReverbSolo = false,
    bool auxDelaySolo = false,
    List<DawEffect> masterEffectsChain = const [],
    List<TempoMarker> tempoMarkers = const [],
  }) async {
    final targetTracks = onlyTrack != null ? [onlyTrack] : tracks;
    final groupTracksMap = <String, Track>{
      for (final t in tracks)
        if (t.type == TrackType.group) t.id: t,
    };
    final bool anySolo = onlyTrack == null && tracks.any((t) => t.isSolo);

    final activeTracks = targetTracks.where((t) {
      if (onlyTrack != null) return true;
      final group = t.groupTrackId != null ? groupTracksMap[t.groupTrackId] : null;
      if (t.isMuted || (group != null && group.isMuted)) return false;
      if (anySolo && !t.isSolo && (group == null || !group.isSolo)) return false;
      return true;
    }).toList();

    double maxTimelinePos = 0.0;
    for (final t in activeTracks) {
      for (final c in trackClips[t.id] ?? const <DawClip>[]) {
        if (c.start + c.length > maxTimelinePos) {
          maxTimelinePos = c.start + c.length;
        }
      }
    }

    if (maxTimelinePos <= 0.0) return false;

    final double resolvedBeatWidth = beatWidth ?? (100.0 * 60.0 / bpm);

    double timelineToSec(double units) {
      if (tempoMarkers.isEmpty) return units / unitsPerSecond;
      return TempoMarker.timelineToSeconds(
        units,
        markers: tempoMarkers,
        baseBpm: bpm.toDouble(),
        beatWidth: resolvedBeatWidth,
      );
    }

    double secToTimeline(double sec) {
      if (sec <= 0.0) return 0.0;
      if (tempoMarkers.isEmpty) return sec * unitsPerSecond;
      double lo = 0.0;
      double hi = max(maxTimelinePos + 200.0, sec * unitsPerSecond * 4.0);
      for (int it = 0; it < 24; it++) {
        final double mid = 0.5 * (lo + hi);
        if (timelineToSec(mid) < sec) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      return 0.5 * (lo + hi);
    }

    // Add 1.5s tail for reverb/delay/release tails
    final int totalFrames =
        (timelineToSec(maxTimelinePos) * sampleRate).ceil() +
        (sampleRate * 1.5).round();
    if (totalFrames <= 0) return false;

    final masterL = Float64List(totalFrames);
    final masterR = Float64List(totalFrames);
    final auxRevL = Float64List(totalFrames);
    final auxRevR = Float64List(totalFrames);
    final auxDlyL = Float64List(totalFrames);
    final auxDlyR = Float64List(totalFrames);

    final Map<String, DecodedWav?> wavCache = {};

    Future<DecodedWav?> loadAudio(String pathOrAsset, {bool isAsset = false}) async {
      if (wavCache.containsKey(pathOrAsset)) return wavCache[pathOrAsset];
      DecodedWav? decoded;
      if (isAsset) {
        try {
          final data = await rootBundle.load(pathOrAsset);
          decoded = decodeWavBytes(data.buffer.asUint8List());
        } catch (_) {}
      } else {
        decoded = await decodeWavFile(pathOrAsset);
        if (decoded == null && File(pathOrAsset).existsSync()) {
          decoded = await decodeAudioFileWithFfmpeg(pathOrAsset);
        }
      }
      wavCache[pathOrAsset] = decoded;
      return decoded;
    }

    bool anyAudioRendered = false;

    final Map<String, Float64List> trackDryL = {};
    final Map<String, Float64List> trackDryR = {};

    for (final track in activeTracks) {
      final clips = trackClips[track.id] ?? const <DawClip>[];
      if (clips.isEmpty) continue;

      final trackL = Float64List(totalFrames);
      final trackR = Float64List(totalFrames);
      bool trackHasAudio = false;

      final audioClipsOnTrack = clips.whereType<AudioClip>().toList()
        ..sort((a, b) => a.start.compareTo(b.start));

      for (final clip in clips) {
        if (clip is AudioClip) {
          final wav = await loadAudio(clip.filePath);
          if (wav == null || wav.frameCount == 0) continue;

          // Compute automatic crossfade overlap windows with neighbors on same track
          final clipIdx = audioClipsOnTrack.indexOf(clip);
          double xfadeInUnits = 0.0;
          if (clipIdx > 0) {
            final prev = audioClipsOnTrack[clipIdx - 1];
            if (prev.start + prev.length > clip.start) {
              xfadeInUnits = min(clip.length, prev.start + prev.length - clip.start);
            }
          }
          double xfadeOutUnits = 0.0;
          if (clipIdx >= 0 && clipIdx + 1 < audioClipsOnTrack.length) {
            final next = audioClipsOnTrack[clipIdx + 1];
            if (clip.start + clip.length > next.start) {
              xfadeOutUnits = min(clip.length, clip.start + clip.length - next.start);
            }
          }
          final int xfadeInFrames =
              ((xfadeInUnits / unitsPerSecond) * sampleRate).round();
          final int xfadeOutFrames =
              ((xfadeOutUnits / unitsPerSecond) * sampleRate).round();

          final int clipStartFrame =
              (timelineToSec(clip.start) * sampleRate).round();
          final int clipLenFrames = max(
            1,
            ((timelineToSec(clip.start + clip.length) -
                        timelineToSec(clip.start)) *
                    sampleRate)
                .round(),
          );

          // Apply independent pitch-preserved time stretching / semitone shifting
          List<double> srcLeft = wav.left;
          List<double> srcRight = wav.right;
          double rateRatio = wav.sampleRate / sampleRate;
          final bool useWsola = clip.preservePitch &&
              (clip.pitchSemitones.abs() > 0.01 ||
                  (clip.stretchFactor - 1.0).abs() > 0.005);
          if (useWsola) {
            final stretched = TimeStretchEngine.processStereo(
              left: wav.left,
              right: wav.right,
              sampleRate: wav.sampleRate,
              stretchFactor: clip.stretchFactor,
              pitchSemitones: clip.pitchSemitones,
              preservePitch: true,
            );
            srcLeft = stretched.left;
            srcRight = stretched.right;
          } else {
            rateRatio =
                (wav.sampleRate / sampleRate) *
                pow(2.0, clip.pitchSemitones / 12.0) *
                clip.stretchFactor.clamp(0.25, 4.0);
          }

          final int srcFrameCount = srcLeft.length;
          if (srcFrameCount == 0) continue;
          final double srcStartSec = clip.startOffset / unitsPerSecond;
          final double loopSpanUnits = useWsola
              ? clip.originalLength / max(0.25, clip.stretchFactor)
              : clip.originalLength;
          final int loopSpanFrames = max(
            1,
            ((loopSpanUnits / unitsPerSecond) * wav.sampleRate)
                .round()
                .clamp(1, srcFrameCount),
          );
          final int fadeInFrames =
              ((clip.fadeIn / unitsPerSecond) * sampleRate).round();
          final int fadeOutFrames =
              ((clip.fadeOut / unitsPerSecond) * sampleRate).round();

          for (int i = 0; i < clipLenFrames; i++) {
            final int dst = clipStartFrame + i;
            if (dst < 0 || dst >= totalFrames) continue;

            double srcPos = (srcStartSec * wav.sampleRate) + (i * rateRatio);
            if (clip.isLooped && loopSpanFrames > 8 && srcPos >= loopSpanFrames) {
              srcPos = srcPos % loopSpanFrames;
            }
            final int s0 = srcPos.floor();
            if (s0 < 0 || s0 >= srcFrameCount) continue;
            final int s1 = (s0 + 1).clamp(0, srcFrameCount - 1);
            final double frac = srcPos - s0;

            double env = clip.gain.clamp(0.0, 2.5);
            if (fadeInFrames > 0 && i < fadeInFrames) {
              env *= (i / fadeInFrames);
            }
            if (fadeOutFrames > 0 && i >= clipLenFrames - fadeOutFrames) {
              env *= ((clipLenFrames - i) / fadeOutFrames).clamp(0.0, 1.0);
            }
            if (xfadeInFrames > 0 && i < xfadeInFrames) {
              env *= 0.5 * (1.0 - cos(pi * i / xfadeInFrames));
            }
            if (xfadeOutFrames > 0 && i >= clipLenFrames - xfadeOutFrames) {
              final rem = (clipLenFrames - i).clamp(0, xfadeOutFrames);
              env *= 0.5 * (1.0 - cos(pi * rem / xfadeOutFrames));
            }

            final l =
                (srcLeft[s0] * (1.0 - frac) + srcLeft[s1] * frac) * env;
            final r =
                (srcRight[s0] * (1.0 - frac) + srcRight[s1] * frac) * env;
            trackL[dst] += l;
            trackR[dst] += r;
          }
          trackHasAudio = true;
          anyAudioRendered = true;
        } else if (clip is MidiClip && clip.notes.isNotEmpty) {
          if (track.type == TrackType.sampler) {
            final sortedNotes = clip.notes
                .where(
                  (n) =>
                      n.start >= clip.startOffset &&
                      n.start < clip.startOffset + clip.length,
                )
                .toList()
              ..sort((a, b) => a.start.compareTo(b.start));

            for (int nIdx = 0; nIdx < sortedNotes.length; nIdx++) {
              final note = sortedNotes[nIdx];
              SamplerPad? pad;
              for (final p in track.samplerPads.values) {
                if (p.midiNote == note.pitch) {
                  pad = p;
                  break;
                }
              }
              if (pad == null || pad.filePath == null) continue;
              final wav = await loadAudio(
                pad.filePath!,
                isAsset: pad.filePath!.startsWith('assets/'),
              );
              if (wav == null || wav.frameCount == 0) continue;

              final double absStartUnits =
                  clip.start + (note.start - clip.startOffset);
              final int noteStartFrame =
                  (timelineToSec(absStartUnits) * sampleRate).round();

              // Respect pad choke group if another pad in same group triggers later
              int? chokeStopFrame;
              if (pad.chokeGroup > 0) {
                for (int nextIdx = nIdx + 1; nextIdx < sortedNotes.length; nextIdx++) {
                  final nextNote = sortedNotes[nextIdx];
                  if (nextNote.start <= note.start) continue;
                  SamplerPad? nextPad;
                  for (final p in track.samplerPads.values) {
                    if (p.midiNote == nextNote.pitch) {
                      nextPad = p;
                      break;
                    }
                  }
                  if (nextPad != null && nextPad.chokeGroup == pad.chokeGroup) {
                    final double nextUnits =
                        clip.start + (nextNote.start - clip.startOffset);
                    chokeStopFrame = (timelineToSec(nextUnits) * sampleRate).round();
                    break;
                  }
                }
              }

              final int startSample =
                  (pad.trimStart.clamp(0.0, 1.0) * wav.frameCount).round();
              final int endSample =
                  (pad.trimEnd.clamp(0.0, 1.0) * wav.frameCount).round();
              if (endSample <= startSample) continue;

              final double ratio =
                  (wav.sampleRate / sampleRate) * pad.pitch.clamp(0.25, 4.0);
              final int outFrames =
                  ((endSample - startSample) / ratio).round().clamp(1, totalFrames);
              final int fadeInFrames = (pad.fadeIn * sampleRate).round();
              final int fadeOutFrames = (pad.fadeOut * sampleRate).round();
              final double velGain =
                  pad.volume * (note.velocity.clamp(1, 127) / 127.0);

              for (int i = 0; i < outFrames; i++) {
                final int dst = noteStartFrame + i;
                if (dst < 0 || dst >= totalFrames) continue;
                if (chokeStopFrame != null && dst >= chokeStopFrame + 128) {
                  break;
                }
                final double srcPos = startSample + i * ratio;
                final int s0 = srcPos.floor().clamp(0, wav.frameCount - 1);
                final int s1 = (s0 + 1).clamp(0, wav.frameCount - 1);
                final double frac = srcPos - s0;
                double env = velGain;
                if (fadeInFrames > 0 && i < fadeInFrames) {
                  env *= i / fadeInFrames;
                }
                if (fadeOutFrames > 0 && i >= outFrames - fadeOutFrames) {
                  env *= ((outFrames - i) / fadeOutFrames).clamp(0.0, 1.0);
                }
                if (chokeStopFrame != null && dst >= chokeStopFrame) {
                  env *= (1.0 - (dst - chokeStopFrame) / 128.0).clamp(0.0, 1.0);
                }
                trackL[dst] +=
                    (wav.left[s0] * (1.0 - frac) + wav.left[s1] * frac) * env;
                trackR[dst] +=
                    (wav.right[s0] * (1.0 - frac) + wav.right[s1] * frac) * env;
              }
              trackHasAudio = true;
              anyAudioRendered = true;
            }
          } else {
            final preset = getInstrumentPreset(track.instrumentIndex);
            final wav = await loadAudio(preset.assetPath, isAsset: true);
            if (wav == null || wav.frameCount == 0) continue;

            final synth = track.synthSettings;
            final int loopFrame =
                ((preset.loopPointMs / 1000.0) * wav.sampleRate).round().clamp(
                  0,
                  max(0, wav.frameCount - 2),
                );
            final double effectiveReleaseSec =
                (synth.releaseSec - 0.14).abs() < 1e-4
                    ? preset.releaseMs / 1000.0
                    : synth.releaseSec;
            final int releaseFrames =
                ((max(0.02, effectiveReleaseSec)) * sampleRate).round().clamp(
                  200,
                  sampleRate * 3,
                );
            final int attackFrames =
                ((synth.attackSec * sampleRate).round()).clamp(32, sampleRate * 2);
            final int decayFrames =
                ((synth.decaySec * sampleRate).round()).clamp(32, sampleRate * 2);

            final synthNotes = track.arpSettings.enabled
                ? track.arpSettings.expandNotes(clip.notes, resolvedBeatWidth)
                : clip.notes;
            for (final note in synthNotes) {
              if (note.start < clip.startOffset ||
                  note.start >= clip.startOffset + clip.length) {
                continue;
              }
              final double absStartUnits =
                  clip.start + (note.start - clip.startOffset);
              final int noteStartFrame =
                  (timelineToSec(absStartUnits) * sampleRate).round();
              final double noteDurSec = max(
                0.05,
                timelineToSec(absStartUnits + note.length) -
                    timelineToSec(absStartUnits),
              );
              final int holdFrames = (noteDurSec * sampleRate).round();
              final int totalNoteFrames = holdFrames + releaseFrames;
              final double semitoneOffset =
                  (note.pitch - preset.basePitch) +
                  (synth.octave * 12.0) +
                  (synth.detuneCents / 100.0);
              final double speed = pow(
                2.0,
                semitoneOffset / 12.0,
              ).toDouble().clamp(0.05, 16.0);
              final double ratio = (wav.sampleRate / sampleRate) * speed;
              final double velGain =
                  (note.velocity.clamp(1, 127) / 127.0) *
                  preset.volumeMultiplier;

              double srcCursor = 0.0;
              final int loopSpan = max(1, wav.frameCount - 1 - loopFrame);
              for (int i = 0; i < totalNoteFrames; i++) {
                final int dst = noteStartFrame + i;
                if (dst < 0 || dst >= totalFrames) {
                  srcCursor += ratio;
                  continue;
                }
                double pos = srcCursor;
                if (pos >= wav.frameCount - 1 && loopSpan > 8) {
                  pos = loopFrame + ((pos - loopFrame) % loopSpan);
                }
                final int s0 = pos.floor().clamp(0, wav.frameCount - 1);
                final int s1 = (s0 + 1).clamp(0, wav.frameCount - 1);
                final double frac = pos - s0;

                double env = velGain;
                if (i < attackFrames) {
                  env *= i / attackFrames;
                } else if (i < holdFrames) {
                  final dProgress = ((i - attackFrames) / decayFrames).clamp(0.0, 1.0);
                  env *= (1.0 - (1.0 - synth.sustain.clamp(0.0, 1.0)) * dProgress);
                } else {
                  env *= synth.sustain.clamp(0.05, 1.0) *
                      (1.0 - (i - holdFrames) / releaseFrames).clamp(0.0, 1.0);
                }
                trackL[dst] +=
                    (wav.left[s0] * (1.0 - frac) + wav.left[s1] * frac) * env;
                trackR[dst] +=
                    (wav.right[s0] * (1.0 - frac) + wav.right[s1] * frac) * env;
                srcCursor += ratio;
              }
              trackHasAudio = true;
              anyAudioRendered = true;
            }
          }
        }
      }

      if (trackHasAudio) {
        final bool hasOdOrAmp = track.effectsChain.any(
          (f) =>
              !f.isBypassed &&
              (f.name == 'Overdrive' ||
                  f.name == 'TubeScreamer' ||
                  f.name == 'GuitarAmp'),
        );
        final bool hasCutoffAuto =
            track.automation['Synth Cutoff']?.isNotEmpty ?? false;
        final bool hasResoAuto =
            track.automation['Synth Reso']?.isNotEmpty ?? false;
        // Live DAW biquadFilter is shared with Overdrive/GuitarAmp cab LPF,
        // so synth lowpass applies when OD/Amp aren't active and cutoff < 0.99 or automated.
        if (track.type == TrackType.midi &&
            !hasOdOrAmp &&
            (track.synthSettings.filterCutoff < 0.99 ||
                hasCutoffAuto ||
                hasResoAuto)) {
          _applySynthLowpass(
            trackL,
            trackR,
            track: track,
            cutoffNorm: track.synthSettings.filterCutoff,
            resonance: track.synthSettings.filterResonance,
            frameToTimeline: (frame) => secToTimeline(frame / sampleRate),
          );
        }
        trackDryL[track.id] = trackL;
        trackDryR[track.id] = trackR;
      }
    }

    if (!anyAudioRendered) return false;

    // Ensure group bus accumulators exist even when group itself has no clips
    for (final grp in activeTracks.where((t) => t.type == TrackType.group)) {
      trackDryL.putIfAbsent(grp.id, () => Float64List(totalFrames));
      trackDryR.putIfAbsent(grp.id, () => Float64List(totalFrames));
    }

    void routeProcessedTrack(Track track, Float64List targetL, Float64List targetR) {
      final trackL = trackDryL[track.id];
      final trackR = trackDryR[track.id];
      if (trackL == null || trackR == null) return;

      final procL = Float64List.fromList(trackL);
      final procR = Float64List.fromList(trackR);

      final bool hasVolAuto = track.automation['Volume']?.isNotEmpty ?? false;
      final bool hasPanAuto = track.automation['Pan']?.isNotEmpty ?? false;
      final bool hasRevAuto =
          track.automation['Reverb Send']?.isNotEmpty ?? false;
      final bool hasDlyAuto =
          track.automation['Delay Send']?.isNotEmpty ?? false;

      // Live DAW applies MIDI & Sampler track volume at the voice before bus FX,
      // whereas Audio tracks apply fader gain post-FX on Bus.soundHandle.
      final bool preFxVol = track.type != TrackType.audio && !hasVolAuto;
      if (preFxVol && (track.volume - 1.0).abs() > 1e-4) {
        final double v = track.volume.clamp(0.0, 4.0);
        for (int i = 0; i < totalFrames; i++) {
          procL[i] *= v;
          procR[i] *= v;
        }
      }

      _applyEffectsToBuffer(
        track.effectsChain,
        procL,
        procR,
        track: track,
        frameToTimeline: (frame) => secToTimeline(frame / sampleRate),
        sidechainBuffers: trackDryL,
        sidechainBuffersR: trackDryR,
      );

      for (int i = 0; i < totalFrames; i++) {
        final double posUnits = (hasVolAuto || hasPanAuto || hasRevAuto || hasDlyAuto)
            ? secToTimeline(i / sampleRate)
            : 0.0;
        double vol = preFxVol ? 1.0 : track.volume;
        if (hasVolAuto) {
          final av = track.getInterpolatedAutomation('Volume', posUnits);
          if (av >= 0.0) vol = av;
        }
        double pan = track.pan;
        if (hasPanAuto) {
          final ap = track.getInterpolatedAutomation('Pan', posUnits);
          if (ap >= 0.0) pan = ap * 2.0 - 1.0;
        }
        double revSend = track.reverbSend;
        if (hasRevAuto) {
          final ar = track.getInterpolatedAutomation('Reverb Send', posUnits);
          if (ar >= 0.0) revSend = ar;
        }
        double dlySend = track.delaySend;
        if (hasDlyAuto) {
          final ad = track.getInterpolatedAutomation('Delay Send', posUnits);
          if (ad >= 0.0) dlySend = ad;
        }
        pan = pan.clamp(-1.0, 1.0);
        final double panL = pan > 0 ? (1.0 - pan) : 1.0;
        final double panR = pan < 0 ? (1.0 + pan) : 1.0;
        final double sL = procL[i] * vol * panL;
        final double sR = procR[i] * vol * panR;
        targetL[i] += sL;
        targetR[i] += sR;

        if (revSend > 0.01) {
          final preL = track.reverbPreFader ? procL[i] * panL : sL;
          final preR = track.reverbPreFader ? procR[i] * panR : sR;
          auxRevL[i] += preL * revSend;
          auxRevR[i] += preR * revSend;
        }
        if (dlySend > 0.01) {
          final preL = track.delayPreFader ? procL[i] * panL : sL;
          final preR = track.delayPreFader ? procR[i] * panR : sR;
          auxDlyL[i] += preL * dlySend;
          auxDlyR[i] += preR * dlySend;
        }
      }
    }

    // Pass 2a: Route non-group child tracks into their parent group buffer or Master
    for (final track in activeTracks) {
      if (track.type == TrackType.group) continue;
      final group = (onlyTrack == null && track.groupTrackId != null)
          ? groupTracksMap[track.groupTrackId]
          : null;
      if (group != null && activeTracks.contains(group)) {
        routeProcessedTrack(track, trackDryL[group.id]!, trackDryR[group.id]!);
      } else {
        routeProcessedTrack(track, masterL, masterR);
      }
    }

    // Pass 2b: Process Group Bus tracks (with their bus FX & sends) into Master
    for (final grp in activeTracks.where((t) => t.type == TrackType.group)) {
      routeProcessedTrack(grp, masterL, masterR);
    }

    final bool anyAuxSolo = auxReverbSolo || auxDelaySolo;
    if (anyAuxSolo) {
      masterL.fillRange(0, totalFrames, 0.0);
      masterR.fillRange(0, totalFrames, 0.0);
    }

    // Process aux return buses (100% wet-only matching SoLoud auxReverbBus & auxDelayBus)
    if ((!anyAuxSolo || auxReverbSolo) && auxRevL.any((v) => v.abs() > 1e-6)) {
      FreeverbProcessor(sampleRate: sampleRate).processRange(
        left: auxRevL,
        right: auxRevR,
        start: 0,
        end: totalFrames,
        roomSize: 0.78,
        damp: 0.32,
        mix: auxReverbMix.clamp(0.0, 1.5),
        wetOnly: true,
      );
      for (int i = 0; i < totalFrames; i++) {
        masterL[i] += auxRevL[i];
        masterR[i] += auxRevR[i];
      }
    }
    if ((!anyAuxSolo || auxDelaySolo) && auxDlyL.any((v) => v.abs() > 1e-6)) {
      EchoProcessor(sampleRate: sampleRate).processRange(
        left: auxDlyL,
        right: auxDlyR,
        start: 0,
        end: totalFrames,
        sampleRate: sampleRate,
        delaySec: 0.34,
        decay: 0.45,
        filterDamp: 0.40,
        mix: auxDelayMix.clamp(0.0, 1.5),
        wetOnly: true,
      );
      for (int i = 0; i < totalFrames; i++) {
        masterL[i] += auxDlyL[i];
        masterR[i] += auxDlyR[i];
      }
    }

    if (masterEffectsChain.isNotEmpty) {
      _applyEffectsToBuffer(masterEffectsChain, masterL, masterR);
    }

    // Write final WAV with master volume & soft limiter
    final writer = WavWriter(outWavPath, sampleRate: sampleRate, channels: 2);
    const int chunkSize = 4096;
    final byteBuf = ByteData(chunkSize * 4);
    for (int base = 0; base < totalFrames; base += chunkSize) {
      final int n = min(chunkSize, totalFrames - base);
      for (int i = 0; i < n; i++) {
        double l = masterL[base + i] * masterVolume;
        double r = masterR[base + i] * masterVolume;
        if (masterLimiter) {
          l = _softClip(l);
          r = _softClip(r);
        }
        final int il = (l.clamp(-1.0, 1.0) * 32767.0).round();
        final int ir = (r.clamp(-1.0, 1.0) * 32767.0).round();
        byteBuf.setInt16(i * 4, il, Endian.little);
        byteBuf.setInt16(i * 4 + 2, ir, Endian.little);
      }
      writer.write(byteBuf.buffer.asUint8List(0, n * 4));
    }
    writer.close();
    return true;
  }

  static double _softClip(double x) {
    if (x.abs() <= 0.85) return x;
    final sign = x >= 0 ? 1.0 : -1.0;
    final over = x.abs() - 0.85;
    return sign * (0.85 + 0.15 * (1.0 - exp(-over * 4.0)));
  }

  static void _forEachControlBlock(
    int length,
    bool hasAutomation,
    void Function(int start, int end, int midFrame) processBlock,
  ) {
    if (!hasAutomation || length <= 256) {
      processBlock(0, length, length ~/ 2);
      return;
    }
    const int blockSize = 256;
    for (int start = 0; start < length; start += blockSize) {
      final int end = min(length, start + blockSize);
      processBlock(start, end, (start + end) >> 1);
    }
  }

  static bool _hasAnyParamAuto(
    Track? track,
    DawEffect? fx,
    List<String> paramKeys,
  ) {
    if (track == null || fx == null) return false;
    for (final k in paramKeys) {
      if (track.automation['${fx.name}_$k']?.isNotEmpty ?? false) return true;
    }
    for (final k in fx.parameters.keys) {
      if (track.automation['${fx.name}_$k']?.isNotEmpty ?? false) return true;
    }
    return false;
  }

  static void _applySynthLowpass(
    Float64List left,
    Float64List right, {
    Track? track,
    required double cutoffNorm,
    required double resonance,
    double Function(int frame)? frameToTimeline,
  }) {
    final bool hasAuto = track != null &&
        frameToTimeline != null &&
        ((track.automation['Synth Cutoff']?.isNotEmpty ?? false) ||
            (track.automation['Synth Reso']?.isNotEmpty ?? false));
    final state = StereoBiquadState();
    _forEachControlBlock(left.length, hasAuto, (start, end, midFrame) {
      double c = cutoffNorm;
      double r = resonance;
      if (hasAuto) {
        final double posUnits = frameToTimeline(midFrame);
        final double ac = track.getInterpolatedAutomation('Synth Cutoff', posUnits);
        if (ac >= 0.0) c = ac;
        final double ar = track.getInterpolatedAutomation('Synth Reso', posUnits);
        if (ar >= 0.0) r = ar;
      }
      final double hz = (120.0 * pow(140.0, c.clamp(0.0, 1.0))).clamp(
        100.0,
        18000.0,
      );
      final double q = (0.7 + r.clamp(0.0, 1.0) * 4.5).clamp(0.5, 6.0);
      final coeffs = designLowpassBiquad(
        sampleRate: sampleRate.toDouble(),
        freqHz: hz,
        q: q,
      );
      state.processRange(left, right, start, end, coeffs);
    });
  }

  static void _applyEffectsToBuffer(
    List<DawEffect> chain,
    Float64List left,
    Float64List right, {
    Track? track,
    double Function(int frame)? frameToTimeline,
    Map<String, Float64List> sidechainBuffers = const {},
    Map<String, Float64List> sidechainBuffersR = const {},
  }) {
    final activeChain = chain.where((f) => !f.isBypassed).toList();
    if (activeChain.isEmpty) return;

    final bool hasDedicatedEq = activeChain.any((f) => f.name == 'EQ');
    final bool hasDedicatedComp =
        activeChain.any((f) => f.name == 'Compressor');
    DawEffect? odFx;
    DawEffect? ampFx;
    for (final f in activeChain) {
      if (f.name == 'Overdrive' || f.name == 'TubeScreamer') odFx ??= f;
      if (f.name == 'GuitarAmp') ampFx ??= f;
    }
    bool processedOdAmp = false;

    double? timelineAt(int midFrame) =>
        (track != null && frameToTimeline != null)
            ? frameToTimeline(midFrame)
            : null;

    for (final fx in activeChain) {
      if (fx.pluginFormat == 'LV2' && fx.pluginUri != null) {
        PluginHost.processLv2StereoInPlace(
          pluginUri: fx.pluginUri!,
          left: left,
          right: right,
          parameters: fx.parameters,
          sampleRate: sampleRate.toDouble(),
        );
        continue;
      }

      if (fx.name == 'EQ') {
        final bool hasAuto = _hasAnyParamAuto(track, fx, const [
          'lowFreq',
          'lowGain',
          'lowMidFreq',
          'lowMidGain',
          'lowMidQ',
          'highMidFreq',
          'highMidGain',
          'highMidQ',
          'highFreq',
          'highGain',
          'Low',
          'Mid',
          'High',
        ]);
        final eqProc = EqProcessor();
        _forEachControlBlock(left.length, hasAuto, (start, end, midFrame) {
          eqProc.processRange(
            left: left,
            right: right,
            start: start,
            end: end,
            sampleRate: sampleRate,
            params: resolveEffectParamMap(
              track,
              fx,
              hasAuto ? timelineAt(midFrame) : null,
            ),
          );
        });
      } else if (fx.name == 'BassBoost') {
        final bool hasAuto = _hasAnyParamAuto(track, fx, const ['Mix', 'Boost']);
        final shelfState = StereoBiquadState();
        _forEachControlBlock(left.length, hasAuto, (start, end, midFrame) {
          final double? pos = hasAuto ? timelineAt(midFrame) : null;
          final double mix = resolveEffectParam(track, fx, 'Mix', 1.0, pos);
          final double boost = resolveEffectParam(track, fx, 'Boost', 0.5, pos);
          final coeffs = BiquadCoeffs.design(
            kind: EqBandKind.lowShelf,
            sampleRate: sampleRate.toDouble(),
            freqHz: 110.0,
            gainDb: (boost * 8.0 * mix).clamp(0.0, 12.0),
            q: 0.707,
          );
          shelfState.processRange(left, right, start, end, coeffs);
        });
      } else if (fx.name == 'Overdrive' ||
          fx.name == 'TubeScreamer' ||
          fx.name == 'GuitarAmp') {
        if (processedOdAmp) continue;
        processedOdAmp = true;
        final bool hasAuto =
            _hasAnyParamAuto(track, odFx, const ['Drive', 'Tone', 'Level']) ||
            _hasAnyParamAuto(track, ampFx, const ['Drive', 'Tone', 'Level']);
        final odAmpProc = OverdriveAndAmpProcessor();
        _forEachControlBlock(left.length, hasAuto, (start, end, midFrame) {
          final double? pos = hasAuto ? timelineAt(midFrame) : null;
          odAmpProc.processRange(
            left: left,
            right: right,
            start: start,
            end: end,
            sampleRate: sampleRate,
            odParams: odFx == null
                ? null
                : {
                    'Drive': resolveEffectParam(track, odFx, 'Drive', 0.5, pos),
                    'Tone': resolveEffectParam(track, odFx, 'Tone', 0.5, pos),
                    'Level': resolveEffectParam(track, odFx, 'Level', 0.5, pos),
                  },
            ampParams: ampFx == null
                ? null
                : {
                    'Drive': resolveEffectParam(track, ampFx, 'Drive', 0.7, pos),
                    'Tone': resolveEffectParam(track, ampFx, 'Tone', 0.6, pos),
                    'Level': resolveEffectParam(track, ampFx, 'Level', 0.5, pos),
                  },
            hasDedicatedEq: hasDedicatedEq,
            hasDedicatedComp: hasDedicatedComp,
          );
        });
      } else if (fx.name == 'Compressor') {
        final scBufL = fx.sidechainTrackId != null
            ? sidechainBuffers[fx.sidechainTrackId!]
            : null;
        final scBufR = fx.sidechainTrackId != null
            ? sidechainBuffersR[fx.sidechainTrackId!]
            : null;
        final bool hasAuto =
            _hasAnyParamAuto(track, fx, const ['Mix', 'Thresh', 'Ratio', 'Gain']);
        final compProc = CompressorProcessor();
        _forEachControlBlock(left.length, hasAuto, (start, end, midFrame) {
          final double? pos = hasAuto ? timelineAt(midFrame) : null;
          final double mix = resolveEffectParam(track, fx, 'Mix', 1.0, pos);
          final double thresh =
              resolveEffectParam(track, fx, 'Thresh', 0.5, pos);
          final double ratio = resolveEffectParam(track, fx, 'Ratio', 0.5, pos);
          final double gain = resolveEffectParam(track, fx, 'Gain', 0.5, pos);
          compProc.processRange(
            left: left,
            right: right,
            start: start,
            end: end,
            sampleRate: sampleRate,
            threshDb: (-4.0 - thresh * 46.0).clamp(-60.0, 0.0),
            ratio: (1.0 + ratio * 9.0).clamp(1.0, 10.0),
            makeupDb: ((gain - 0.5) * 24.0).clamp(-24.0, 24.0),
            mix: mix,
            attackMs: 10.0,
            releaseMs: 100.0,
            scLeft: scBufL,
            scRight: scBufR,
          );
        });
      } else if (fx.name == 'Chorus') {
        final bool hasAuto =
            _hasAnyParamAuto(track, fx, const ['Mix', 'Depth', 'Rate']);
        final modProc = ModulatedDelayProcessor(sampleRate: sampleRate);
        _forEachControlBlock(left.length, hasAuto, (start, end, midFrame) {
          final double? pos = hasAuto ? timelineAt(midFrame) : null;
          final double mix = resolveEffectParam(track, fx, 'Mix', 0.5, pos);
          final double depth = resolveEffectParam(track, fx, 'Depth', 0.6, pos);
          final double rate = resolveEffectParam(track, fx, 'Rate', 0.4, pos);
          modProc.processRange(
            left: left,
            right: right,
            start: start,
            end: end,
            sampleRate: sampleRate,
            baseDelaySec: (0.015 + depth * 0.020).clamp(0.005, 0.05),
            modDepthSec: 0.0035 * (0.25 + 0.75 * depth),
            rateHz: (0.15 + rate * 2.2).clamp(0.05, 10.0),
            mix: mix,
            feedback: 0.0,
            dryScaleOffset: 0.35,
            wetGain: 0.75,
          );
        });
      } else if (fx.name == 'Flanger') {
        final bool hasAuto =
            _hasAnyParamAuto(track, fx, const ['Mix', 'Delay', 'Rate']);
        final modProc = ModulatedDelayProcessor(sampleRate: sampleRate);
        _forEachControlBlock(left.length, hasAuto, (start, end, midFrame) {
          final double? pos = hasAuto ? timelineAt(midFrame) : null;
          final double mix = resolveEffectParam(track, fx, 'Mix', 0.5, pos);
          final double delay = resolveEffectParam(track, fx, 'Delay', 0.5, pos);
          final double rate = resolveEffectParam(track, fx, 'Rate', 0.2, pos);
          final double baseDelay = (0.001 + delay * 0.009).clamp(0.001, 0.02);
          modProc.processRange(
            left: left,
            right: right,
            start: start,
            end: end,
            sampleRate: sampleRate,
            baseDelaySec: baseDelay,
            modDepthSec: baseDelay * 0.65,
            rateHz: (0.08 + rate * 3.5).clamp(0.05, 10.0),
            mix: mix,
            feedback: 0.35,
            dryScaleOffset: 0.4,
            wetGain: 0.7,
          );
        });
      } else if (fx.name == 'Robotize') {
        final bool hasAuto = _hasAnyParamAuto(track, fx, const ['Mix', 'Freq']);
        final roboProc = RobotizeProcessor();
        _forEachControlBlock(left.length, hasAuto, (start, end, midFrame) {
          final double? pos = hasAuto ? timelineAt(midFrame) : null;
          final double mix = resolveEffectParam(track, fx, 'Mix', 1.0, pos);
          final double freq = resolveEffectParam(track, fx, 'Freq', 0.3, pos);
          roboProc.processRange(
            left: left,
            right: right,
            start: start,
            end: end,
            sampleRate: sampleRate,
            freqParam: freq,
            mix: mix,
          );
        });
      } else if (fx.name == 'Lofi') {
        final bool hasAuto =
            _hasAnyParamAuto(track, fx, const ['Mix', 'Rate', 'Bits']);
        final lofiProc = LofiProcessor();
        _forEachControlBlock(left.length, hasAuto, (start, end, midFrame) {
          final double? pos = hasAuto ? timelineAt(midFrame) : null;
          final double mix = resolveEffectParam(track, fx, 'Mix', 1.0, pos);
          final double rate = resolveEffectParam(track, fx, 'Rate', 0.2, pos);
          final double bits = resolveEffectParam(track, fx, 'Bits', 0.3, pos);
          lofiProc.processRange(
            left: left,
            right: right,
            start: start,
            end: end,
            sampleRate: sampleRate,
            rateParam: rate,
            bitsParam: bits,
            mix: mix,
          );
        });
      } else if (fx.name == 'Echo') {
        final bool hasAuto =
            _hasAnyParamAuto(track, fx, const ['Mix', 'Delay', 'Decay']);
        final echoProc = EchoProcessor(sampleRate: sampleRate);
        _forEachControlBlock(left.length, hasAuto, (start, end, midFrame) {
          final double? pos = hasAuto ? timelineAt(midFrame) : null;
          final double mix = resolveEffectParam(track, fx, 'Mix', 0.5, pos);
          final double delay = resolveEffectParam(track, fx, 'Delay', 0.3, pos);
          final double decay = resolveEffectParam(track, fx, 'Decay', 0.5, pos);
          echoProc.processRange(
            left: left,
            right: right,
            start: start,
            end: end,
            sampleRate: sampleRate,
            delaySec: (0.04 + delay * 0.96).clamp(0.01, 2.0),
            decay: (0.10 + decay * 0.80).clamp(0.01, 0.95),
            filterDamp: 0.35,
            mix: mix,
          );
        });
      } else if (fx.name == 'Reverb') {
        final bool hasAuto =
            _hasAnyParamAuto(track, fx, const ['Mix', 'Size', 'Decay']);
        final revProc = FreeverbProcessor(sampleRate: sampleRate);
        _forEachControlBlock(left.length, hasAuto, (start, end, midFrame) {
          final double? pos = hasAuto ? timelineAt(midFrame) : null;
          final double mix = resolveEffectParam(track, fx, 'Mix', 0.5, pos);
          final double size = resolveEffectParam(track, fx, 'Size', 0.5, pos);
          final double decay = resolveEffectParam(track, fx, 'Decay', 0.5, pos);
          revProc.processRange(
            left: left,
            right: right,
            start: start,
            end: end,
            roomSize: (0.25 + size * 0.50 + decay * 0.23).clamp(0.1, 0.98),
            damp: (0.85 - decay * 0.75).clamp(0.05, 0.95),
            mix: mix,
          );
        });
      }
    }
  }

  /// Ensures [rawPath] ends with `.[format]` without duplicating the extension.
  static String normalizeExportPath(String rawPath, String format) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) return trimmed;
    final cleanFmt = format.trim().toLowerCase().replaceAll('.', '');
    if (cleanFmt.isEmpty) return trimmed;
    final ext = '.$cleanFmt';
    return trimmed.toLowerCase().endsWith(ext) ? trimmed : '$trimmed$ext';
  }

  /// Decodes non-WAV audio files (`.mp3`, `.flac`, `.ogg`, `.aiff`, `.m4a`,
  /// etc.) to 44.1 kHz stereo PCM via `ffmpeg` so mixdowns never silently
  /// drop compressed audio clips.
  static Future<DecodedWav?> decodeAudioFileWithFfmpeg(String path) async {
    try {
      final res = await Process.run(
        'ffmpeg',
        [
          '-v',
          'error',
          '-y',
          '-i',
          path,
          '-ar',
          '$sampleRate',
          '-ac',
          '2',
          '-c:a',
          'pcm_s16le',
          '-f',
          'wav',
          'pipe:1',
        ],
        stdoutEncoding: null,
      );
      if (res.exitCode != 0 || res.stdout is! List<int>) return null;
      final bytes = res.stdout is Uint8List
          ? res.stdout as Uint8List
          : Uint8List.fromList(res.stdout as List<int>);
      return decodeWavBytes(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Transcodes a rendered WAV file into [outPath] (.mp3 or .flac) via ffmpeg
  /// and returns whether encoding succeeded alongside any stderr diagnostic.
  static Future<({bool ok, String? error})> transcodeWithFfmpegDetailed(
    String wavPath,
    String outPath, {
    String? format,
  }) async {
    try {
      final fmt = (format ??
              (outPath.toLowerCase().endsWith('.mp3')
                  ? 'mp3'
                  : (outPath.toLowerCase().endsWith('.flac') ? 'flac' : '')))
          .toLowerCase();
      final args = fmt == 'mp3'
          ? <String>[
              '-y',
              '-i',
              wavPath,
              '-vn',
              '-ar',
              '$sampleRate',
              '-ac',
              '2',
              '-c:a',
              'libmp3lame',
              '-b:a',
              '320k',
              '-id3v2_version',
              '3',
              outPath,
            ]
          : <String>['-y', '-i', wavPath, '-vn', outPath];
      final res = await Process.run('ffmpeg', args);
      final outFile = File(outPath);
      final ok =
          res.exitCode == 0 && outFile.existsSync() && outFile.lengthSync() > 0;
      if (ok) {
        return (ok: true, error: null);
      }
      final err = res.stderr.toString().trim();
      return (
        ok: false,
        error: err.isNotEmpty
            ? err
            : 'ffmpeg exited with code ${res.exitCode}',
      );
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  /// Transcodes a rendered WAV file into [outPath] (.mp3 or .flac) via ffmpeg.
  static Future<bool> transcodeWithFfmpeg(String wavPath, String outPath) async {
    final res = await transcodeWithFfmpegDetailed(wavPath, outPath);
    return res.ok;
  }
}

