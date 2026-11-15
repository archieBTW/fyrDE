import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:fyrdaw/models/daw_clip.dart';
import 'package:fyrdaw/models/daw_effect.dart';
import 'package:fyrdaw/models/enums.dart';
import 'package:fyrdaw/models/sampler_pad.dart';
import 'package:fyrdaw/models/track.dart';
import 'package:fyrdaw/utils/audio_utils.dart';
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
    double beatWidth = 100.0,
    Track? onlyTrack,
    double masterVolume = 1.0,
    bool masterLimiter = true,
    double auxReverbMix = 0.85,
    double auxDelayMix = 0.75,
    bool auxReverbSolo = false,
    bool auxDelaySolo = false,
    List<DawEffect> masterEffectsChain = const [],
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

    // Add 1.5s tail for reverb/delay/release tails
    final int totalFrames =
        ((maxTimelinePos / unitsPerSecond) * sampleRate).ceil() +
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
      }
      wavCache[pathOrAsset] = decoded;
      return decoded;
    }

    final double beatWidth = 100.0 * 60.0 / bpm;
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
              ((clip.start / unitsPerSecond) * sampleRate).round();
          final int clipLenFrames =
              ((clip.length / unitsPerSecond) * sampleRate).round();
          final double srcStartSec = clip.startOffset / unitsPerSecond;
          final double rateRatio =
              (wav.sampleRate / sampleRate) *
              pow(2.0, clip.pitchSemitones / 12.0) *
              clip.stretchFactor.clamp(0.25, 4.0);
          final int fadeInFrames =
              ((clip.fadeIn / unitsPerSecond) * sampleRate).round();
          final int fadeOutFrames =
              ((clip.fadeOut / unitsPerSecond) * sampleRate).round();

          for (int i = 0; i < clipLenFrames; i++) {
            final int dst = clipStartFrame + i;
            if (dst < 0 || dst >= totalFrames) continue;

            final double srcPos =
                (srcStartSec * wav.sampleRate) + (i * rateRatio);
            final int s0 = srcPos.floor();
            if (s0 < 0 || s0 >= wav.frameCount) continue;
            final int s1 = (s0 + 1).clamp(0, wav.frameCount - 1);
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
                (wav.left[s0] * (1.0 - frac) + wav.left[s1] * frac) * env;
            final r =
                (wav.right[s0] * (1.0 - frac) + wav.right[s1] * frac) * env;
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
                  ((absStartUnits / unitsPerSecond) * sampleRate).round();

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
                    chokeStopFrame =
                        ((nextUnits / unitsPerSecond) * sampleRate).round();
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
            final int releaseFrames =
                ((max(0.02, synth.releaseSec)) * sampleRate).round().clamp(
                  200,
                  sampleRate * 3,
                );
            final int attackFrames =
                ((synth.attackSec * sampleRate).round()).clamp(32, sampleRate * 2);
            final int decayFrames =
                ((synth.decaySec * sampleRate).round()).clamp(32, sampleRate * 2);

            final synthNotes = track.arpSettings.enabled
                ? track.arpSettings.expandNotes(clip.notes, beatWidth)
                : clip.notes;
            for (final note in synthNotes) {
              if (note.start < clip.startOffset ||
                  note.start >= clip.startOffset + clip.length) {
                continue;
              }
              final double absStartUnits =
                  clip.start + (note.start - clip.startOffset);
              final int noteStartFrame =
                  ((absStartUnits / unitsPerSecond) * sampleRate).round();
              final double noteDurSec =
                  max(0.05, (note.length / beatWidth) * (60.0 / bpm));
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
        // Apply per-track synth low-pass filter if cutoff < 0.98
        if (track.type == TrackType.midi && track.synthSettings.filterCutoff < 0.98) {
          _applySynthLowpass(
            trackL,
            trackR,
            cutoffNorm: track.synthSettings.filterCutoff,
            resonance: track.synthSettings.filterResonance,
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

      _applyEffectsToBuffer(
        track.effectsChain,
        procL,
        procR,
        sidechainBuffers: trackDryL,
      );

      final bool hasVolAuto = track.automation['Volume']?.isNotEmpty ?? false;
      final bool hasPanAuto = track.automation['Pan']?.isNotEmpty ?? false;
      final bool hasRevAuto =
          track.automation['Reverb Send']?.isNotEmpty ?? false;
      final bool hasDlyAuto =
          track.automation['Delay Send']?.isNotEmpty ?? false;

      for (int i = 0; i < totalFrames; i++) {
        final double posUnits = (i / sampleRate) * unitsPerSecond;
        double vol = track.volume;
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

    // Process aux return buses
    if ((!anyAuxSolo || auxReverbSolo) && auxRevL.any((v) => v.abs() > 1e-6)) {
      _applyReverb(auxRevL, auxRevR, size: 0.72, decay: 0.68, mix: auxReverbMix);
      for (int i = 0; i < totalFrames; i++) {
        masterL[i] += auxRevL[i];
        masterR[i] += auxRevR[i];
      }
    }
    if ((!anyAuxSolo || auxDelaySolo) && auxDlyL.any((v) => v.abs() > 1e-6)) {
      _applyEcho(auxDlyL, auxDlyR, delaySec: 0.34, decay: 0.45, mix: auxDelayMix);
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

  static void _applySynthLowpass(
    Float64List left,
    Float64List right, {
    required double cutoffNorm,
    required double resonance,
  }) {
    final double alpha = (0.015 + cutoffNorm * cutoffNorm * 0.85).clamp(0.01, 0.95);
    double lpL = 0.0, lpR = 0.0;
    double bpL = 0.0, bpR = 0.0;
    final double q = resonance.clamp(0.05, 0.92);
    for (int i = 0; i < left.length; i++) {
      lpL += alpha * (left[i] - lpL + bpL * q);
      lpR += alpha * (right[i] - lpR + bpR * q);
      bpL = (left[i] - lpL) * 0.35;
      bpR = (right[i] - lpR) * 0.35;
      left[i] = lpL;
      right[i] = lpR;
    }
  }

  static void _applyEffectsToBuffer(
    List<DawEffect> chain,
    Float64List left,
    Float64List right, {
    Map<String, Float64List> sidechainBuffers = const {},
  }) {
    for (final fx in chain) {
      if (fx.isBypassed) continue;
      if (fx.name == 'TubeScreamer' || fx.name == 'GuitarAmp') {
        final drive = fx.parameters['Drive'] ?? 0.6;
        final level = fx.parameters['Level'] ?? 0.5;
        final preGain = 1.0 + drive * 8.0;
        final outGain = 0.35 + level * 1.1;
        for (int i = 0; i < left.length; i++) {
          left[i] = _tanhApprox(left[i] * preGain) * outGain;
          right[i] = _tanhApprox(right[i] * preGain) * outGain;
        }
      } else if (fx.name == 'EQ' || fx.name == 'BassBoost') {
        final lowGain = fx.name == 'BassBoost'
            ? 1.0 + (fx.parameters['Boost'] ?? 0.5) * 1.4
            : 0.4 + (fx.parameters['Low'] ?? 0.5) * 1.2;
        final highGain = fx.name == 'BassBoost'
            ? 1.0
            : 0.4 + (fx.parameters['High'] ?? 0.5) * 1.2;
        double lpL = 0.0, lpR = 0.0;
        const alpha = 0.06;
        for (int i = 0; i < left.length; i++) {
          lpL += alpha * (left[i] - lpL);
          lpR += alpha * (right[i] - lpR);
          final hpL = left[i] - lpL;
          final hpR = right[i] - lpR;
          left[i] = lpL * lowGain + hpL * highGain;
          right[i] = lpR * lowGain + hpR * highGain;
        }
      } else if (fx.name == 'Compressor') {
        final scBuf = fx.sidechainTrackId != null
            ? sidechainBuffers[fx.sidechainTrackId!]
            : null;
        final threshDb = -4.0 - (fx.parameters['Thresh'] ?? 0.5) * 40.0;
        final threshLin = pow(10.0, threshDb / 20.0).toDouble();
        final ratio = 1.0 + (fx.parameters['Ratio'] ?? 0.5) * 9.0;
        final makeup = pow(
          10.0,
          ((fx.parameters['Gain'] ?? 0.5) - 0.5) * 20.0 / 20.0,
        ).toDouble();
        final mix = (fx.parameters['Mix'] ?? 1.0).clamp(0.0, 1.0);
        double env = 0.0;
        for (int i = 0; i < left.length; i++) {
          final peak = scBuf != null
              ? scBuf[i].abs()
              : max(left[i].abs(), right[i].abs());
          env = peak > env ? env * 0.98 + peak * 0.02 : env * 0.9995 + peak * 0.0005;
          double gain = 1.0;
          if (env > threshLin && env > 1e-6) {
            final compressed = threshLin + (env - threshLin) / ratio;
            gain = compressed / env;
          }
          final compL = left[i] * gain * makeup;
          final compR = right[i] * gain * makeup;
          left[i] = left[i] * (1.0 - mix) + compL * mix;
          right[i] = right[i] * (1.0 - mix) + compR * mix;
        }
      } else if (fx.name == 'Lofi') {
        final step = (1 + ((fx.parameters['Rate'] ?? 0.2) * 18).round()).clamp(1, 24);
        final levels = pow(2.0, (16.0 - (fx.parameters['Bits'] ?? 0.3) * 11.0).clamp(3.0, 16.0));
        final mix = (fx.parameters['Mix'] ?? 1.0).clamp(0.0, 1.0);
        double holdL = 0.0, holdR = 0.0;
        for (int i = 0; i < left.length; i++) {
          if (i % step == 0) {
            holdL = (left[i] * levels).round() / levels;
            holdR = (right[i] * levels).round() / levels;
          }
          left[i] = left[i] * (1.0 - mix) + holdL * mix;
          right[i] = right[i] * (1.0 - mix) + holdR * mix;
        }
      } else if (fx.name == 'Echo') {
        _applyEcho(
          left,
          right,
          delaySec: 0.08 + (fx.parameters['Delay'] ?? 0.3) * 0.65,
          decay: (fx.parameters['Decay'] ?? 0.5).clamp(0.05, 0.85),
          mix: (fx.parameters['Mix'] ?? 0.5).clamp(0.0, 1.0),
        );
      } else if (fx.name == 'Reverb') {
        _applyReverb(
          left,
          right,
          size: fx.parameters['Size'] ?? 0.5,
          decay: fx.parameters['Decay'] ?? 0.5,
          mix: fx.parameters['Mix'] ?? 0.5,
        );
      }
    }
  }

  static double _tanhApprox(double x) {
    final e2x = exp(2.0 * x.clamp(-6.0, 6.0));
    return (e2x - 1.0) / (e2x + 1.0);
  }

  static void _applyEcho(
    Float64List left,
    Float64List right, {
    required double delaySec,
    required double decay,
    required double mix,
  }) {
    final delayFrames = (delaySec * sampleRate).round().clamp(1, sampleRate * 2);
    final wetL = Float64List(left.length);
    final wetR = Float64List(right.length);
    for (int i = 0; i < left.length; i++) {
      final double prevL = i >= delayFrames ? wetL[i - delayFrames] : 0.0;
      final double prevR = i >= delayFrames ? wetR[i - delayFrames] : 0.0;
      wetL[i] = (i >= delayFrames ? left[i - delayFrames] : 0.0) + prevR * decay;
      wetR[i] = (i >= delayFrames ? right[i - delayFrames] : 0.0) + prevL * decay;
    }
    for (int i = 0; i < left.length; i++) {
      left[i] = left[i] * (1.0 - mix * 0.5) + wetL[i] * mix;
      right[i] = right[i] * (1.0 - mix * 0.5) + wetR[i] * mix;
    }
  }

  static void _applyReverb(
    Float64List left,
    Float64List right, {
    required double size,
    required double decay,
    required double mix,
  }) {
    final delaysL = [1116, 1356, 1557, 1777].map((d) => (d * (0.6 + size * 0.8)).round()).toList();
    final delaysR = [1139, 1379, 1580, 1800].map((d) => (d * (0.6 + size * 0.8)).round()).toList();
    final fb = (0.35 + decay * 0.48).clamp(0.1, 0.86);
    final wetL = Float64List(left.length);
    final wetR = Float64List(right.length);

    for (final d in delaysL) {
      final buf = Float64List(d);
      int idx = 0;
      for (int i = 0; i < left.length; i++) {
        final out = buf[idx];
        buf[idx] = left[i] * 0.25 + out * fb;
        wetL[i] += out;
        idx = (idx + 1) % d;
      }
    }
    for (final d in delaysR) {
      final buf = Float64List(d);
      int idx = 0;
      for (int i = 0; i < right.length; i++) {
        final out = buf[idx];
        buf[idx] = right[i] * 0.25 + out * fb;
        wetR[i] += out;
        idx = (idx + 1) % d;
      }
    }
    final m = mix.clamp(0.0, 1.0);
    for (int i = 0; i < left.length; i++) {
      left[i] = left[i] * (1.0 - m * 0.5) + wetL[i] * m;
      right[i] = right[i] * (1.0 - m * 0.5) + wetR[i] * m;
    }
  }

  /// Transcodes a rendered WAV file into [outPath] (.mp3 or .flac) via ffmpeg.
  static Future<bool> transcodeWithFfmpeg(String wavPath, String outPath) async {
    final res = await Process.run('ffmpeg', ['-y', '-i', wavPath, outPath]);
    return res.exitCode == 0 && File(outPath).existsSync();
  }
}

