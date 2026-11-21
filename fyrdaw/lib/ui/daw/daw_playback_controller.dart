part of '../../main.dart';

extension _DawPlaybackController on _DawMainScreenState {

  void _zoomIn() => _setState(() {
    _zoomX = min(
      _DawMainScreenState.kMaxTimelineZoom,
      (_zoomX * 1.25).clamp(_DawMainScreenState.kMinTimelineZoom, _DawMainScreenState.kMaxTimelineZoom),
    );
  });

  void _zoomOut() => _setState(() {
    _zoomX = max(
      _DawMainScreenState.kMinTimelineZoom,
      (_zoomX / 1.25).clamp(_DawMainScreenState.kMinTimelineZoom, _DawMainScreenState.kMaxTimelineZoom),
    );
  });

  void _changeTempo(int newBpm) {
    if (newBpm == bpm) return;
    double ratio = bpm / newBpm;
    _setState(() {
      for (var track in tracks) {
        if (track.type == TrackType.midi) {
          for (var clip in trackClips[track.id] ?? []) {
            clip.start *= ratio;
            clip.length *= ratio;
            if (clip is MidiClip) {
              for (var note in clip.notes) {
                note.start *= ratio;
                note.length *= ratio;
              }
            }
          }
        }
      }
      bpm = newBpm;
    });
  }

  double _computeClipEnvelope(
    AudioClip clip,
    double atPlayhead, {
    Track? track,
  }) {
    final localPos = atPlayhead - clip.start;
    double env = clip.gain.clamp(0.0, 2.5);
    if (clip.fadeIn > 0.0 && localPos < clip.fadeIn) {
      env *= (localPos / clip.fadeIn).clamp(0.0, 1.0);
    }
    final remaining = clip.length - localPos;
    if (clip.fadeOut > 0.0 && remaining < clip.fadeOut) {
      env *= (remaining / clip.fadeOut).clamp(0.0, 1.0);
    }
    if (track != null) {
      final siblings = (trackClips[track.id] ?? const <DawClip>[])
          .whereType<AudioClip>()
          .toList();
      for (final other in siblings) {
        if (identical(other, clip)) continue;
        final ovStart = max(clip.start, other.start);
        final ovEnd = min(clip.start + clip.length, other.start + other.length);
        if (ovEnd > ovStart && atPlayhead >= ovStart && atPlayhead <= ovEnd) {
          final frac = ((atPlayhead - ovStart) / (ovEnd - ovStart)).clamp(0.0, 1.0);
          if (other.start <= clip.start) {
            // Incoming clip cosine fade-in across overlap
            env *= 0.5 * (1.0 - cos(pi * frac));
          } else {
            // Outgoing clip cosine fade-out across overlap
            env *= 0.5 * (1.0 + cos(pi * frac));
          }
        }
      }
    }
    return env;
  }

  void _playAudioClipWithSends(Track track, AudioClip clip, double atPlayhead) {
    if (clip.source == null || !SoLoud.instance.isInitialized) return;
    track.bus = ensureActiveBus(track.bus);
    _syncTrackBusOutputVolume(track);
    final env = _computeClipEnvelope(clip, atPlayhead, track: track);
    final trackEffVol = _effectiveTrackVolume(track);
    final effVol = (trackEffVol * env).clamp(0.0, 4.0);
    final double dryVoiceVol = track.type == TrackType.audio
        ? env.clamp(0.0, 2.5)
        : effVol;
    final revVol = ((track.reverbPreFader ? env : effVol) * track.reverbSend)
        .clamp(0.0, 4.0);
    final dlyVol = ((track.delayPreFader ? env : effVol) * track.delaySend)
        .clamp(0.0, 4.0);
    final bool usingCachedWsola =
        clip.preservePitch && clip.processedFilePath != null;
    final speed = usingCachedWsola
        ? 1.0
        : (pow(2.0, clip.pitchSemitones / 12.0).toDouble() * clip.stretchFactor)
            .clamp(0.25, 4.0);
    final rawOffsetMs =
        ((atPlayhead - clip.start + clip.startOffset) * 10.0 * speed).round();
    final int loopUnitMs = max(1, (clip.originalLength * 10.0).round());
    final offsetMs = clip.isLooped ? (rawOffsetMs % loopUnitMs) : rawOffsetMs;

    clip.currentHandle = track.bus!.play(
      clip.source!,
      volume: (_isAuditioningReference || auxReverbSolo || auxDelaySolo)
          ? 0.0
          : dryVoiceVol,
      pan: track.pan.clamp(-1.0, 1.0),
      paused: true,
      looping: clip.isLooped,
    );
    try {
      SoLoud.instance.setRelativePlaySpeed(clip.currentHandle!, speed);
      if (offsetMs > 0) {
        SoLoud.instance.seek(
          clip.currentHandle!,
          Duration(milliseconds: offsetMs),
        );
      }
      SoLoud.instance.setPause(clip.currentHandle!, false);
    } catch (_) {}

    if (track.reverbSend > 0.01 && auxReverbBus != null) {
      try {
        clip.reverbSendHandle = auxReverbBus!.play(
          clip.source!,
          volume: revVol,
          pan: track.pan.clamp(-1.0, 1.0),
          paused: true,
          looping: clip.isLooped,
        );
        SoLoud.instance.setRelativePlaySpeed(clip.reverbSendHandle!, speed);
        if (offsetMs > 0) {
          SoLoud.instance.seek(
            clip.reverbSendHandle!,
            Duration(milliseconds: offsetMs),
          );
        }
        SoLoud.instance.setPause(clip.reverbSendHandle!, false);
      } catch (_) {}
    }

    if (track.delaySend > 0.01 && auxDelayBus != null) {
      try {
        clip.delaySendHandle = auxDelayBus!.play(
          clip.source!,
          volume: dlyVol,
          pan: track.pan.clamp(-1.0, 1.0),
          paused: true,
          looping: clip.isLooped,
        );
        SoLoud.instance.setRelativePlaySpeed(clip.delaySendHandle!, speed);
        if (offsetMs > 0) {
          SoLoud.instance.seek(
            clip.delaySendHandle!,
            Duration(milliseconds: offsetMs),
          );
        }
        SoLoud.instance.setPause(clip.delaySendHandle!, false);
      } catch (_) {}
    }
  }

  void _stopAudioClipHandles(AudioClip clip) {
    for (final h in [
      clip.currentHandle,
      clip.reverbSendHandle,
      clip.delaySendHandle,
    ]) {
      if (h != null) {
        try {
          if (SoLoud.instance.getIsValidVoiceHandle(h)) {
            SoLoud.instance.stop(h);
          }
        } catch (_) {}
      }
    }
    clip.currentHandle = null;
    clip.reverbSendHandle = null;
    clip.delaySendHandle = null;
  }

  Future<void> _setRecordingLatencyMs(double ms) async {
    final clamped = ms.clamp(0.0, 200.0);
    _setState(() => _recordingLatencyMs = clamped);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('sb_rec_latency_ms', clamped);
    } catch (_) {}
  }

  void _stopAllActivePlaybackVoices() {
    for (final track in tracks) {
      for (final clip in trackClips[track.id] ?? []) {
        if (clip is AudioClip) {
          _stopAudioClipHandles(clip);
        }
      }
      final releaseMs = getInstrumentPreset(track.instrumentIndex).releaseMs;
      for (final h in track.activeMidiHandles) {
        releaseInstrumentNote(h, releaseMs: releaseMs);
      }
      track.activeMidiHandles.clear();
      if (_isSoloudReady) {
        for (final pad in track.samplerPads.values) {
          pad.stopActive();
        }
      }
    }
    for (final list in _activeMidiNotes.values) {
      for (final entry in list) {
        releaseInstrumentNote(entry.handle, releaseMs: entry.releaseMs);
      }
    }
    _activeMidiNotes.clear();
    if (_referenceHandle != null) {
      try {
        SoLoud.instance.stop(_referenceHandle!);
      } catch (_) {}
      _referenceHandle = null;
    }
  }

  void _triggerMetronomeInWindow(
    double fromPos,
    double toPos, {
    bool includeStart = false,
  }) {
    if (!isMetronomeEnabled || !_isSoloudReady || _countInBeatsLeft != 0) {
      return;
    }
    final events = collectMetronomeBeatsInWindow(
      fromPos,
      toPos,
      baseBpm: bpm,
      baseTimeSigTop: timeSigTop,
      tempoMarkers: tempoMarkers,
      includeStart: includeStart,
    );
    for (final ev in events) {
      _playMetronomeClick(ev.isDownbeat);
    }
  }

  void _triggerTrackNotesInWindow(
    Track track,
    double fromPos,
    double toPos, {
    bool includeStart = false,
  }) {
    if (!_isSoloudReady) return;
    for (var clip in trackClips[track.id] ?? []) {
      if (clip is! MidiClip) continue;
      final double localOld = fromPos - clip.start + clip.startOffset;
      double localNew = toPos - clip.start + clip.startOffset;
      final double maxLocal = clip.startOffset + clip.length;
      if (localNew > maxLocal) localNew = maxLocal;
      if (localNew < clip.startOffset || localOld > maxLocal) continue;

      final playNotes = (track.type == TrackType.midi &&
              track.arpSettings.enabled)
          ? track.arpSettings.expandNotes(clip.notes, beatWidth)
          : clip.notes;
      for (final note in playNotes) {
        if (note.start < clip.startOffset || note.start >= maxLocal) continue;
        if (!shouldTriggerMidiNoteInWindow(
          noteStart: note.start,
          windowStart: localOld,
          windowEnd: localNew,
          includeStart: includeStart,
        )) {
          continue;
        }
        if (track.type == TrackType.sampler) {
          final pad = track.samplerPads.values
              .where((p) => p.midiNote == note.pitch)
              .firstOrNull;
          if (pad != null) {
            pad.play(
              note.velocity.toDouble(),
              track.bus,
              track.volume,
              track.pan,
              track.samplerPads.values,
            );
            if (track.reverbSend > 0.01 && auxReverbBus != null) {
              pad.play(
                note.velocity.toDouble(),
                auxReverbBus,
                track.volume * track.reverbSend,
                track.pan,
                null,
                null,
                true,
              );
            }
            if (track.delaySend > 0.01 && auxDelayBus != null) {
              pad.play(
                note.velocity.toDouble(),
                auxDelayBus,
                track.volume * track.delaySend,
                track.pan,
                null,
                null,
                true,
              );
            }
          }
        } else {
          track.activeMidiHandles.removeWhere(
            (h) => !SoLoud.instance.getIsValidVoiceHandle(h),
          );
          final preset = getInstrumentPreset(track.instrumentIndex);
          final handle = triggerInstrumentNote(
            track,
            note.pitch,
            note.velocity,
          );
          SoundHandle? revHandle;
          SoundHandle? dlyHandle;
          if (track.reverbSend > 0.01 && auxReverbBus != null) {
            revHandle = triggerInstrumentNote(
              track,
              note.pitch,
              note.velocity,
              volumeScale: track.reverbSend,
              targetBus: auxReverbBus,
            );
          }
          if (track.delaySend > 0.01 && auxDelayBus != null) {
            dlyHandle = triggerInstrumentNote(
              track,
              note.pitch,
              note.velocity,
              volumeScale: track.delaySend,
              targetBus: auxDelayBus,
            );
          }
          if (handle != null) {
            track.activeMidiHandles.add(handle);
            final int noteMs = max(
              (note.length / beatWidth * (60.0 / bpm) * 1000).round(),
              50,
            );
            Timer(Duration(milliseconds: noteMs), () {
              releaseInstrumentNote(handle, releaseMs: preset.releaseMs);
              if (revHandle != null) {
                releaseInstrumentNote(revHandle, releaseMs: preset.releaseMs);
              }
              if (dlyHandle != null) {
                releaseInstrumentNote(dlyHandle, releaseMs: preset.releaseMs);
              }
            });
          }
        }
      }
    }
  }

  void _triggerVoicesAtPosition(
    double pos, {
    double? windowEnd,
  }) {
    if (_isAuditioningReference && _referenceSource != null && _isSoloudReady) {
      try {
        _referenceHandle = SoLoud.instance.play(
          _referenceSource!,
          volume: (_referenceGain * masterVolume).clamp(0.0, 1.5),
          paused: true,
        );
        final seekMs = ((pos / 100.0) * 1000.0).round();
        if (seekMs > 0) {
          SoLoud.instance.seek(_referenceHandle!, Duration(milliseconds: seekMs));
        }
        SoLoud.instance.setPause(_referenceHandle!, false);
      } catch (_) {}
    }

    final double endPos = windowEnd ?? pos;
    final bool anySolo = tracks.any((t) => t.isSolo);
    for (final track in tracks) {
      if (track.type == TrackType.group) continue;
      if (_isSoloudReady) {
        track.bus = ensureActiveBus(track.bus);
      }
      _updateTrackFilters(track, atPlayhead: pos);
      if (!_isTrackAudible(track, anySolo)) continue;

      for (final clip in trackClips[track.id] ?? []) {
        if (clip is AudioClip && clip.source != null) {
          if (pos >= clip.start && pos < clip.start + clip.length) {
            _playAudioClipWithSends(track, clip, pos);
          }
        }
      }
      _triggerTrackNotesInWindow(track, pos, endPos, includeStart: true);
    }
  }

  void _seekPlayhead(
    double targetPos, {
    bool retriggerAudio = true,
    bool snap = false,
  }) {
    double pos = targetPos.clamp(0.0, _timelineTotalUnits);
    if (snap && snapToGrid) {
      pos = (pos / snapResolution).round() * snapResolution;
    }
    _setState(() {
      if (isPlaying) {
        _stopAllActivePlaybackVoices();
      }
      playheadPosition = pos;
      if (isPlaying) {
        _playStopwatch
          ..reset()
          ..start();
        _lastStopwatchMicros = 0;
        if (retriggerAudio) {
          _triggerVoicesAtPosition(pos);
          _triggerMetronomeInWindow(pos, pos, includeStart: true);
        }
      }
    });
  }

  Future<void> _togglePlay() async {
    if (!isPlaying) {
      unawaited(_syncLinuxSystemDefaultRoute());
      for (var track in tracks) {
        if (track.type == TrackType.midi) {
          final preset = getInstrumentPreset(track.instrumentIndex);
          track.synthSourcePath = preset.assetPath;
          track.synthSource = globalInstrumentSounds[track.instrumentIndex];
        }
        _updateTrackFilters(track, atPlayhead: playheadPosition);
      }
    }

    _setState(() {
      isPlaying = !isPlaying;
      if (isPlaying) {
        _triggerVoicesAtPosition(playheadPosition);
        _triggerMetronomeInWindow(
          playheadPosition,
          playheadPosition,
          includeStart: true,
        );

        _playStopwatch
          ..reset()
          ..start();
        _lastStopwatchMicros = 0;

        playTimer = Timer.periodic(const Duration(milliseconds: 5), (timer) {
          final int nowMicros = _playStopwatch.elapsedMicroseconds;
          final double dtSec = (nowMicros - _lastStopwatchMicros) / 1000000.0;
          _lastStopwatchMicros = nowMicros;
          if (dtSec <= 0) return;

          _setState(() {
            double oldPos = playheadPosition;
            final double curBpm = TempoMarker.effectiveBpmAt(
              playheadPosition,
              tempoMarkers,
              bpm.toDouble(),
            );
            final double rawNextPos =
                oldPos + dtSec * 100.0 * (curBpm / max(20, bpm));
            final bool willWrap = isLooping && rawNextPos >= loopEnd;
            playheadPosition = willWrap
                ? max(oldPos, loopEnd - 1e-4)
                : rawNextPos;

            // Punch-in / Punch-out auto stop when leaving loopEnd
            if (isRecording &&
                punchInLoop &&
                isLooping &&
                rawNextPos >= loopEnd) {
              Future.microtask(() {
                if (isRecording) _toggleRecord();
              });
            }

            final curMeter = TempoMarker.effectiveMeterAt(
              playheadPosition,
              tempoMarkers,
              timeSigTop,
              timeSigBottom,
            );
            _triggerMetronomeInWindow(oldPos, playheadPosition);

            // Quantized next-bar Session Launcher clip promotions
            final double barLen = beatWidth * max(1, curMeter.numerator);
            if (barLen > 0 &&
                (playheadPosition / barLen).floor() > (oldPos / barLen).floor() &&
                _queuedSessionClipIds.isNotEmpty) {
              for (final qId in _queuedSessionClipIds.toList()) {
                for (final t in tracks) {
                  final match = (trackClips[t.id] ?? [])
                      .where((c) => c.id == qId)
                      .firstOrNull;
                  if (match != null) {
                    _activeSessionClipIds.removeWhere(
                      (id) => (trackClips[t.id] ?? []).any((c) => c.id == id),
                    );
                    _activeSessionClipIds.add(match.id);
                    playheadPosition = match.start;
                    isLooping = true;
                    loopStart = match.start;
                    loopEnd = match.start + match.length;
                  }
                }
              }
              _queuedSessionClipIds.clear();
            }

            bool anySolo = tracks.any((t) => t.isSolo);
            for (var track in tracks) {
              if (track.type == TrackType.group) continue;
              double autoVol = track.getInterpolatedAutomation(
                'Volume',
                playheadPosition,
              );
              if (autoVol >= 0.0) {
                track.volume = autoVol;
              }
              double autoPan = track.getInterpolatedAutomation(
                'Pan',
                playheadPosition,
              );
              if (autoPan >= 0.0) {
                track.pan = (autoPan * 2.0) - 1.0;
              }
              double autoRevSend = track.getInterpolatedAutomation(
                'Reverb Send',
                playheadPosition,
              );
              if (autoRevSend >= 0.0) {
                track.reverbSend = autoRevSend.clamp(0.0, 1.0);
              }
              double autoDlySend = track.getInterpolatedAutomation(
                'Delay Send',
                playheadPosition,
              );
              if (autoDlySend >= 0.0) {
                track.delaySend = autoDlySend.clamp(0.0, 1.0);
              }

              // Keep audio clip fade/gain/automation envelopes & post-FX bus fader live
              if (track.type == TrackType.audio) {
                _syncTrackBusOutputVolume(track);
              }
              for (var c in trackClips[track.id] ?? []) {
                if (c is AudioClip &&
                    c.currentHandle != null &&
                    SoLoud.instance.getIsValidVoiceHandle(c.currentHandle!)) {
                  final env = _computeClipEnvelope(c, playheadPosition, track: track);
                  final trackEffVol = _effectiveTrackVolume(track);
                  final effVol = (trackEffVol * env).clamp(0.0, 4.0);
                  final dryPlayVol =
                      (_isAuditioningReference || auxReverbSolo || auxDelaySolo)
                          ? 0.0
                          : (track.type == TrackType.audio
                                ? env.clamp(0.0, 2.5)
                                : effVol);
                  final revVol =
                      ((track.reverbPreFader ? env : effVol) * track.reverbSend)
                          .clamp(0.0, 4.0);
                  final dlyVol =
                      ((track.delayPreFader ? env : effVol) * track.delaySend)
                          .clamp(0.0, 4.0);
                  try {
                    SoLoud.instance.setVolume(c.currentHandle!, dryPlayVol);
                    SoLoud.instance.setPan(
                      c.currentHandle!,
                      track.pan.clamp(-1.0, 1.0),
                    );
                    if (c.reverbSendHandle != null &&
                        SoLoud.instance.getIsValidVoiceHandle(
                          c.reverbSendHandle!,
                        )) {
                      SoLoud.instance.setVolume(c.reverbSendHandle!, revVol);
                    }
                    if (c.delaySendHandle != null &&
                        SoLoud.instance.getIsValidVoiceHandle(
                          c.delaySendHandle!,
                        )) {
                      SoLoud.instance.setVolume(c.delaySendHandle!, dlyVol);
                    }
                  } catch (_) {}
                }
              }

              if (!_isTrackAudible(track, anySolo)) continue;

              bool hasEffectAutomation = false;
              for (var fx in track.effectsChain) {
                for (var paramName in fx.parameters.keys) {
                  String autoKey = '${fx.name}_$paramName';
                  if ((track.automation[autoKey]?.isNotEmpty ?? false)) {
                    hasEffectAutomation = true;
                    break;
                  }
                }
                if (hasEffectAutomation) break;
              }
              if (hasEffectAutomation) {
                _updateTrackFilters(track, atPlayhead: playheadPosition);
              }

              for (var clip in trackClips[track.id] ?? []) {
                if (clip.start + clip.length > oldPos &&
                    clip.start + clip.length <= playheadPosition) {
                  if (clip is AudioClip) {
                    _stopAudioClipHandles(clip);
                  }
                }

                if (clip.start > oldPos && clip.start <= playheadPosition) {
                  if (clip is AudioClip && clip.source != null) {
                    if (clip.currentHandle == null ||
                        !SoLoud.instance.getIsValidVoiceHandle(
                          clip.currentHandle!,
                        )) {
                      _playAudioClipWithSends(track, clip, playheadPosition);
                    }
                  }
                }
              }
              _triggerTrackNotesInWindow(track, oldPos, playheadPosition);
            }
            if (willWrap) {
              final double loopSpan = max(0.0, loopEnd - loopStart);
              final double overshoot = loopSpan > 0
                  ? (rawNextPos - loopEnd).clamp(0.0, loopSpan * 0.5)
                  : 0.0;
              _stopAllActivePlaybackVoices();
              playheadPosition = loopStart + overshoot;
              _triggerVoicesAtPosition(loopStart, windowEnd: playheadPosition);
              _triggerMetronomeInWindow(
                loopStart,
                playheadPosition,
                includeStart: true,
              );
            }

            if (autoScrollPlayhead && _horizontalScrollController.hasClients) {
              final double playheadX = playheadPosition * _zoomX;
              final double offset = _horizontalScrollController.offset;
              final double width = MediaQuery.of(context).size.width - 250;
              final double maxExtent =
                  _horizontalScrollController.position.maxScrollExtent;
              if (playheadX > offset + width - 100) {
                _horizontalScrollController.jumpTo(
                  (playheadX - width + 100).clamp(0.0, maxExtent),
                );
              } else if (playheadX < offset) {
                _horizontalScrollController.jumpTo(
                  playheadX.clamp(0.0, maxExtent),
                );
              }
            }
          });
        });
      } else {
        playTimer?.cancel();
        _playStopwatch.stop();
        _stopAllActivePlaybackVoices();
      }
    });
  }

  void _triggerSessionClip(Track track, DawClip clip) {
    _setState(() {
      final trackClipIds =
          (trackClips[track.id] ?? const <DawClip>[]).map((c) => c.id).toSet();
      if (!isPlaying) {
        _activeSessionClipIds.removeAll(trackClipIds);
        _queuedSessionClipIds.removeAll(trackClipIds);
        _activeSessionClipIds.add(clip.id);
        playheadPosition = clip.start;
        loopStart = clip.start;
        loopEnd = clip.start + max(beatWidth, clip.length);
        isLooping = true;
      } else {
        _queuedSessionClipIds.removeAll(trackClipIds);
        _queuedSessionClipIds.add(clip.id);
      }
    });
    if (!isPlaying) _togglePlay();
  }

  void _triggerSessionScene(int sceneIndex) {
    final sceneClips = <DawClip>[];
    for (final t in tracks) {
      if (t.type == TrackType.group) continue;
      final list = trackClips[t.id] ?? const <DawClip>[];
      if (sceneIndex < list.length) sceneClips.add(list[sceneIndex]);
    }
    if (sceneClips.isEmpty) return;
    _setState(() {
      if (!isPlaying) {
        _activeSessionClipIds
          ..clear()
          ..addAll(sceneClips.map((c) => c.id));
        _queuedSessionClipIds.clear();
        double minStart = sceneClips.first.start;
        double maxEnd = sceneClips.first.start + sceneClips.first.length;
        for (final c in sceneClips) {
          if (c.start < minStart) minStart = c.start;
          if (c.start + c.length > maxEnd) maxEnd = c.start + c.length;
        }
        playheadPosition = minStart;
        loopStart = minStart;
        loopEnd = max(minStart + beatWidth, maxEnd);
        isLooping = true;
      } else {
        _queuedSessionClipIds
          ..clear()
          ..addAll(sceneClips.map((c) => c.id));
      }
    });
    if (!isPlaying) _togglePlay();
  }

  void _stopSessionTrack(Track track) {
    _setState(() {
      for (final c in trackClips[track.id] ?? const <DawClip>[]) {
        _activeSessionClipIds.remove(c.id);
        _queuedSessionClipIds.remove(c.id);
        if (c is AudioClip) _stopAudioClipHandles(c);
      }
    });
  }

}
