part of '../../main.dart';

extension _DawMidiController on _DawMainScreenState {
  void _updateMidiDevices() async {
    _midiDevices = await _midiCommand.devices ?? [];
    if (_midiDevices.isNotEmpty) {
      for (var d in _midiDevices) {
        if (!(d.name.toLowerCase().contains('through'))) {
          try {
            _midiCommand.connectToDevice(d);
          } catch (e) {
            debugPrint("Could not connect to MIDI device ${d.name}: $e");
          }
        }
      }
    }
    _setState(() {});
  }


  void _changeInstrument(Track track, int v) async {
    final preset = getInstrumentPreset(v);
    track.synthSourcePath = preset.assetPath;
    track.synthSource = globalInstrumentSounds[v];
    _setState(() {
      track.instrumentIndex = v;
    });
    _updateTrackFilters(track);

    // Audition a short preview chord/note of the newly selected instrument
    if (SoLoud.instance.isInitialized) {
      final h = triggerInstrumentNote(track, preset.basePitch, 100);
      if (h != null) {
        Timer(const Duration(milliseconds: 550), () {
          releaseInstrumentNote(h, releaseMs: preset.releaseMs);
        });
      }
    }
  }

  void _showMidiInputDialog(Track track) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: panelDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: 400,
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select MIDI Input',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 16),
                SizedBox(
                  height: 300,
                  child: ListView(
                    children: [
                      InkWell(
                        onTap: () {
                          _setState(() => track.midiInputId = null);
                          Navigator.pop(context);
                        },
                        child: Container(
                          padding: EdgeInsets.all(12),
                          margin: EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: panelLight,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: track.midiInputId == null
                                  ? lavenderAccent
                                  : textFaint,
                            ),
                          ),
                          child: Text(
                            'All Inputs',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                      ..._midiDevices.map((d) {
                        return InkWell(
                          onTap: () {
                            _setState(() => track.midiInputId = d.id);
                            _midiCommand.connectToDevice(d);
                            Navigator.pop(context);
                          },
                          child: Container(
                            padding: EdgeInsets.all(12),
                            margin: EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: panelLight,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: track.midiInputId == d.id
                                    ? lavenderAccent
                                    : textFaint,
                              ),
                            ),
                            child: Text(
                              d.name,
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showInstrumentDialog(Track track) {
    final categories = <String>['All'];
    for (final inst in kInstrumentPresets) {
      if (!categories.contains(inst.category)) {
        categories.add(inst.category);
      }
    }
    String selectedCategory = 'All';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = selectedCategory == 'All'
                ? kInstrumentPresets
                : kInstrumentPresets
                      .where((p) => p.category == selectedCategory)
                      .toList();
            return Dialog(
              backgroundColor: panelDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                width: 540,
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Select Instrument',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '${filtered.length} sounds',
                          style: TextStyle(color: textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      'All instruments feature realistic stereo voicing and unlimited sustain.',
                      style: TextStyle(color: textMuted, fontSize: 12),
                    ),
                    SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: categories.map((cat) {
                          final active = selectedCategory == cat;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(
                                cat,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: active ? Colors.black : Colors.white70,
                                  fontWeight: active
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              selected: active,
                              selectedColor: lavenderAccent,
                              backgroundColor: panelLight,
                              side: BorderSide(
                                color: active ? lavenderAccent : textFaint,
                              ),
                              onSelected: (_) {
                                setModalState(() => selectedCategory = cat);
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    SizedBox(height: 14),
                    SizedBox(
                      height: 420,
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final inst = filtered[index];
                          final isSelected = track.instrumentIndex == inst.index;
                          return InkWell(
                            onTap: () {
                              Navigator.of(context).pop();
                              _changeInstrument(track, inst.index);
                            },
                            child: Container(
                              margin: EdgeInsets.only(bottom: 10),
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: panelLight,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected ? lavenderAccent : textFaint,
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    inst.icon,
                                    color: lavenderAccent,
                                    size: 30,
                                  ),
                                  SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                inst.name,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: bgDark,
                                                borderRadius: BorderRadius.circular(
                                                  4,
                                                ),
                                              ),
                                              child: Text(
                                                inst.category,
                                                style: TextStyle(
                                                  color: lavenderLight,
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          inst.description,
                                          style: TextStyle(
                                            color: textMuted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _triggerNoteOnTrack(Track track, int note, int velocity) {
    if (track.type == TrackType.midi) {
      final preset = getInstrumentPreset(track.instrumentIndex);
      final handle = triggerInstrumentNote(track, note, velocity);
      if (handle != null) {
        _activeMidiNotes.putIfAbsent(note, () => []).add((
          handle: handle,
          releaseMs: preset.releaseMs,
        ));
        track.activeMidiHandles.removeWhere(
          (h) => !SoLoud.instance.getIsValidVoiceHandle(h),
        );
        track.activeMidiHandles.add(handle);
      }
    } else if (track.type == TrackType.sampler) {
      var pad = track.samplerPads.values
          .where((p) => p.midiNote == note)
          .firstOrNull;
      if (pad != null) {
        if (_isSoloudReady) {
          track.bus = ensureActiveBus(track.bus);
        }
        pad.play(
          velocity.toDouble(),
          track.bus,
          track.volume,
          track.pan,
          track.samplerPads.values,
        );
      }
    }
  }

  void _syncLiveArpTimer() {
    if (_heldArpNotes.isEmpty) {
      _arpTimer?.cancel();
      _arpTimer = null;
      if (_lastArpTriggeredPitch != null) {
        _releaseActiveMidiPitch(_lastArpTriggeredPitch!);
        _lastArpTriggeredPitch = null;
      }
      return;
    }
    if (selectedTrackIndex == null || selectedTrackIndex! >= tracks.length) {
      return;
    }
    final track = tracks[selectedTrackIndex!];
    if (!track.arpSettings.enabled || track.type != TrackType.midi) return;
    if (_arpTimer != null && _arpTimer!.isActive) return;

    final stepMs =
        ((track.arpSettings.rateBeats * (60000.0 / bpm)).round()).clamp(40, 2000);
    _arpStepIdx = 0;
    void tick() {
      if (!mounted || _heldArpNotes.isEmpty) {
        _arpTimer?.cancel();
        _arpTimer = null;
        return;
      }
      if (selectedTrackIndex == null || selectedTrackIndex! >= tracks.length) {
        return;
      }
      final t = tracks[selectedTrackIndex!];
      final base = _heldArpNotes.toList()..sort();
      final pitches = <int>[];
      for (int o = 0; o < t.arpSettings.octaves.clamp(1, 3); o++) {
        for (final p in base) {
          if (p + o * 12 <= 127) pitches.add(p + o * 12);
        }
      }
      if (pitches.isEmpty) return;
      List<int> seq;
      switch (t.arpSettings.mode) {
        case ArpMode.up:
          seq = pitches;
        case ArpMode.down:
          seq = pitches.reversed.toList();
        case ArpMode.upDown:
          seq = [
            ...pitches,
            if (pitches.length > 2) ...pitches.sublist(1, pitches.length - 1).reversed,
          ];
        case ArpMode.random:
          seq = pitches;
      }
      final nextPitch = t.arpSettings.mode == ArpMode.random
          ? seq[Random().nextInt(seq.length)]
          : seq[_arpStepIdx % seq.length];
      _arpStepIdx++;
      if (_lastArpTriggeredPitch != null) {
        _releaseActiveMidiPitch(_lastArpTriggeredPitch!);
      }
      _triggerNoteOnTrack(t, nextPitch, _qwertyVelocity);
      _lastArpTriggeredPitch = nextPitch;
    }

    tick();
    _arpTimer = Timer.periodic(Duration(milliseconds: stepMs), (_) => tick());
  }

  void _releaseActiveMidiPitch(int note) {
    if (_activeMidiNotes.containsKey(note)) {
      for (var entry in _activeMidiNotes[note]!) {
        releaseInstrumentNote(entry.handle, releaseMs: entry.releaseMs);
      }
      _activeMidiNotes.remove(note);
    }
  }

  void _handleMidiCc(int cc, int value, int channel) {
    if (_midiLearnActive && _midiLearnTarget != null) {
      final parts = _midiLearnTarget!.split(':');
      final trackId = parts.first;
      final param = parts.length > 1 ? parts.sublist(1).join(':') : 'volume';
      _setState(() {
        midiMappings.removeWhere((m) => m.cc == cc && m.channel == channel);
        midiMappings.add(
          MidiCcMapping(
            cc: cc,
            channel: channel,
            trackId: trackId,
            param: param,
          ),
        );
        _midiLearnActive = false;
        _midiLearnTarget = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mapped MIDI CC $cc -> $param')),
        );
      }
      return;
    }

    for (final m in midiMappings) {
      if (m.cc != cc) continue;
      if (m.channel != null && m.channel != channel) continue;
      final scaled = m.mapMidiValue(value);
      _setState(() {
        if (m.trackId == '__master__' && m.param == 'volume') {
          masterVolume = (scaled * kMaxMasterVolume).clamp(0.0, kMaxMasterVolume);
          _syncMasterAndAuxFilters();
          return;
        }
        final track = tracks.where((t) => t.id == m.trackId).firstOrNull;
        if (track == null) return;
        if (m.param == 'volume') {
          _onTrackVolumeChanged(
            track,
            (scaled * kMaxTrackVolume).clamp(0.0, kMaxTrackVolume),
            updateState: false,
          );
        } else if (m.param == 'pan') {
          track.pan = (scaled * 2.0 - 1.0).clamp(-1.0, 1.0);
        } else if (m.param == 'reverbSend') {
          track.reverbSend = scaled.clamp(0.0, 1.0);
        } else if (m.param == 'delaySend') {
          track.delaySend = scaled.clamp(0.0, 1.0);
        } else if (m.param == 'synth:cutoff') {
          track.synthSettings.filterCutoff = scaled.clamp(0.0, 1.0);
          _updateTrackFilters(track);
        } else if (m.param.startsWith('fx:')) {
          final pParts = m.param.split(':');
          if (pParts.length >= 3) {
            final fxIdx = int.tryParse(pParts[1]);
            if (fxIdx != null && fxIdx >= 0 && fxIdx < track.effectsChain.length) {
              track.effectsChain[fxIdx].parameters[pParts[2]] = scaled.clamp(0.0, 1.0);
              _updateTrackFilters(track);
            }
          }
        }
      });
    }
  }

  void _handleMidiNoteOn(int note, int velocity, String? deviceId) {
    if (isRecording) {
      for (var t in tracks) {
        if (t.isArmed &&
            (t.midiInputId == null || t.midiInputId == deviceId) &&
            (t.type == TrackType.midi || t.type == TrackType.sampler)) {
          final clips = trackClips.putIfAbsent(t.id, () => []);
          var activeClip = clips
              .where(
                (c) =>
                    c.start <= playheadPosition &&
                    c.start + c.length >= playheadPosition,
              )
              .firstOrNull;
          if (activeClip == null) {
            final double barUnits = beatWidth * max(1, timeSigTop);
            final precedingMidi = clips
                .whereType<MidiClip>()
                .where(
                  (c) =>
                      c.start <= playheadPosition &&
                      (recordingStartPos == null ||
                          c.start + c.length >= recordingStartPos!),
                )
                .lastOrNull;
            if (precedingMidi != null) {
              final double minNewLen =
                  (playheadPosition - precedingMidi.start) + barUnits;
              if (minNewLen > precedingMidi.length) {
                precedingMidi.length = minNewLen;
              }
              activeClip = precedingMidi;
            } else {
              final double clipStart = recordingStartPos != null &&
                      recordingStartPos! <= playheadPosition
                  ? recordingStartPos!
                  : (playheadPosition / barUnits).floor() * barUnits;
              final newClip = MidiClip(
                id: UniqueKey().toString(),
                start: clipStart,
                length: max(
                  barUnits * 4,
                  (playheadPosition - clipStart) + barUnits,
                ),
                color: t.color,
              );
              clips.add(newClip);
              activeClip = newClip;
            }
          }
          if (activeClip is MidiClip) {
            double localStart =
                playheadPosition - activeClip.start + activeClip.startOffset;
            var newNote = MidiNote(
              pitch: note,
              start: localStart,
              length: beatWidth / 4,
              velocity: velocity,
            );
            activeClip.notes.add(newNote);
            _recordingMidiNotes[note] = _RecordingNote(
              activeClip,
              newNote,
              playheadPosition,
            );
          }
        }
      }
    }

    List<Track> tracksToPlay = [];
    if (selectedTrackIndex != null) {
      tracksToPlay.add(tracks[selectedTrackIndex!]);
    }
    for (var t in tracks) {
      if (t.isArmed && !tracksToPlay.contains(t)) {
        tracksToPlay.add(t);
      }
    }

    for (var track in tracksToPlay) {
      if (track.midiInputId != null && track.midiInputId != deviceId) continue;
      if (track.type == TrackType.midi && track.arpSettings.enabled) {
        _heldArpNotes.add(note);
        _syncLiveArpTimer();
        continue;
      }
      _triggerNoteOnTrack(track, note, velocity);
    }
  }

  void _handleMidiNoteOff(int note) {
    if (_heldArpNotes.remove(note)) {
      _syncLiveArpTimer();
    }
    if (isRecording && _recordingMidiNotes.containsKey(note)) {
      var r = _recordingMidiNotes[note]!;
      double len = playheadPosition - r.absoluteStartPlayhead;
      if (len < beatWidth / 8) len = beatWidth / 8;
      r.note.length = len;
      _recordingMidiNotes.remove(note);
    }

    _releaseActiveMidiPitch(note);
  }

  void _tapTempo() {
    final now = DateTime.now();
    _tapTimestamps.add(now);
    _tapTimestamps.removeWhere((t) => now.difference(t).inSeconds > 3);
    if (_tapTimestamps.length >= 2) {
      double avgDiff = 0;
      for (int i = 1; i < _tapTimestamps.length; i++) {
        avgDiff += _tapTimestamps[i]
            .difference(_tapTimestamps[i - 1])
            .inMilliseconds;
      }
      avgDiff /= (_tapTimestamps.length - 1);
      int tappedBpm = (60000 / avgDiff).round();
      if (tappedBpm > 20 && tappedBpm < 300) {
        _changeTempo(tappedBpm);
      }
    }
  }

  void _showExternalPluginBrowserDialog(Track fxTrack, VoidCallback syncFx) {
    final plugins = PluginHost.scanInstalledPlugins();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: panelDark,
        title: Row(
          children: [
            const Icon(Icons.extension, color: Colors.tealAccent, size: 18),
            const SizedBox(width: 8),
            Text(
              'External LV2 / VST3 Plugins (${plugins.length})',
              style: TextStyle(color: textMain, fontSize: 15),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          height: 290,
          child: plugins.isEmpty
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.folder_off, color: textMuted, size: 32),
                    const SizedBox(height: 10),
                    Text(
                      'No external LV2 or VST3 bundles found.',
                      style: TextStyle(
                        color: textMain,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Searched paths:\n${PluginHost.searchPaths.join('\n')}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: textMuted, fontSize: 11),
                    ),
                  ],
                )
              : ListView.builder(
                  itemCount: plugins.length,
                  itemBuilder: (_, idx) {
                    final pl = plugins[idx];
                    return ListTile(
                      dense: true,
                      leading: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.tealAccent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.tealAccent),
                        ),
                        child: Text(
                          pl.format,
                          style: const TextStyle(
                            color: Colors.tealAccent,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        pl.name,
                        style: TextStyle(color: textMain, fontSize: 12),
                      ),
                      subtitle: Text(
                        pl.category,
                        style: TextStyle(color: textMuted, fontSize: 10),
                      ),
                      onTap: () {
                        _saveState();
                        final params = <String, double>{};
                        for (final c in pl.controls.take(6)) {
                          final span = (c.max - c.min).abs();
                          final norm = span > 1e-6
                              ? ((c.defaultVal - c.min) / span).clamp(0.0, 1.0)
                              : 0.5;
                          params[c.name] = norm;
                        }
                        if (params.isEmpty) params['Mix'] = 1.0;
                        _setState(() {
                          fxTrack.effectsChain.add(
                            DawEffect(
                              pl.name,
                              params,
                              pluginFormat: pl.format,
                              pluginUri: pl.id,
                            ),
                          );
                          syncFx();
                        });
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: TextStyle(color: textMuted)),
          ),
        ],
      ),
    );
  }

}
