part of '../../main.dart';

extension _DawEditingController on _DawMainScreenState {
  Future<void> _sliceClipToSampler(AudioClip clip) async {
    final slices = await detectAudioTransients(clip.filePath, maxSlices: 16);
    if (slices.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not detect transients in audio clip.')),
        );
      }
      return;
    }

    _saveState();
    final samplerTrack = Track(
      id: 'sliced_${DateTime.now().millisecondsSinceEpoch}',
      name: '${clip.name.isNotEmpty ? clip.name : "Sliced"} Kit',
      type: TrackType.sampler,
      colorValue: clip.color.toARGB32(),
    );

    AudioSource? sharedSrc;
    if (SoLoud.instance.isInitialized) {
      try {
        sharedSrc = await SoLoud.instance.loadFile(clip.filePath);
      } catch (_) {}
    }

    final stepLen = (clip.length / slices.length).clamp(15.0, beatWidth);
    final notes = <MidiNote>[];
    for (int i = 0; i < slices.length && i < 16; i++) {
      final (s, e) = slices[i];
      final pad = samplerTrack.samplerPads[i]!;
      pad.filePath = clip.filePath;
      pad.trimStart = s;
      pad.trimEnd = e;
      pad.fadeIn = 0.004;
      pad.fadeOut = 0.012;
      pad.source = sharedSrc;
      pad.extractWaveform();

      notes.add(
        MidiNote(
          pitch: pad.midiNote,
          start: i * stepLen,
          length: max(12.0, stepLen * 0.9),
          velocity: 105,
        ),
      );
    }

    final midiClip = MidiClip(
      id: UniqueKey().toString(),
      name: 'Sliced Pattern',
      start: clip.start,
      length: max(clip.length, slices.length * stepLen),
      color: samplerTrack.color,
      notes: notes,
    );

    _setState(() {
      tracks.add(samplerTrack);
      trackClips[samplerTrack.id] = [midiClip];
      selectedTrackIndex = tracks.length - 1;
      selectedClip = midiClip;
      selectedBottomTab = 3;
      isBottomPanelExpanded = true;
      if (_bottomPanelHeight < 400) _bottomPanelHeight = 400;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sliced into ${slices.length} Sampler pads!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _addTrack(TrackType type) async {
    final trackColor =
        kTrackColorPalette[tracks.length % kTrackColorPalette.length];
    final trackName = switch (type) {
      TrackType.audio => 'Audio Track ${tracks.length + 1}',
      TrackType.midi => 'MIDI Track ${tracks.length + 1}',
      TrackType.sampler => 'Sampler Track ${tracks.length + 1}',
      TrackType.group => 'Group Bus ${tracks.length + 1}',
    };
    final newTrack = Track(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: trackName,
      type: type,
      colorValue: trackColor.toARGB32(),
    );
    if (_isSoloudReady) {
      newTrack.bus = ensureActiveBus(newTrack.bus);
    }

    if (type == TrackType.midi) {
      final preset = getInstrumentPreset(0);
      newTrack.synthSourcePath = preset.assetPath;
      newTrack.synthSource = globalInstrumentSounds[0];
    }
    _saveState();
    _setState(() {
      tracks.add(newTrack);
      trackClips[newTrack.id] = [];
      if (type == TrackType.midi || type == TrackType.sampler) {
        final newClip = MidiClip(
          id: UniqueKey().toString(),
          name: type == TrackType.sampler ? 'Beat 1' : 'Pattern 1',
          start: 0.0,
          length: beatWidth * timeSigTop * 4,
          color: newTrack.color,
        );
        trackClips[newTrack.id]!.add(newClip);
        selectedClip = newClip;
      }
      selectedTrackIndex = tracks.length - 1;
      if ((type == TrackType.audio || type == TrackType.group) &&
          selectedBottomTab == 0) {
        selectedBottomTab = 2;
      } else if (type == TrackType.midi) {
        selectedBottomTab = 0;
      } else if (type == TrackType.sampler) {
        selectedBottomTab = 3;
        isBottomPanelExpanded = true;
        if (_bottomPanelHeight < 400) {
          _bottomPanelHeight = 400;
        }
      }
    });
    if (type == TrackType.sampler) {
      await applyDrumKitToPads(newTrack.samplerPads, kDrumKits.first);
      if (mounted) {
        _setState(() {});
      }
    }
  }

  void _reorderTrack(int oldIndex, int newIndex) {
    final preview = [...tracks];
    final check = reorderTrackList(
      preview,
      oldIndex: oldIndex,
      newIndex: newIndex,
      selectedIndex: selectedTrackIndex,
      anchorIndex: _trackSelectionAnchorIndex,
    );
    if (check == null) return;
    _saveState();
    _setState(() {
      final res = reorderTrackList(
        tracks,
        oldIndex: oldIndex,
        newIndex: newIndex,
        selectedIndex: selectedTrackIndex,
        anchorIndex: _trackSelectionAnchorIndex,
      );
      if (res != null) {
        selectedTrackIndex = res.selectedIndex;
        _trackSelectionAnchorIndex = res.anchorIndex;
      }
    });
  }

  void _executeDeleteTrack(Track track) {
    _saveState();
    _setState(() {
      if (track.monitorHandle != null) {
        try {
          if (SoLoud.instance.getIsValidVoiceHandle(track.monitorHandle!)) {
            SoLoud.instance.stop(track.monitorHandle!);
          }
        } catch (_) {}
        track.monitorHandle = null;
      }
      if (track.monitorSource != null) {
        try {
          SoLoud.instance.disposeSource(track.monitorSource!);
        } catch (_) {}
        track.monitorSource = null;
      }
      if (track.bus != null) {
        try {
          track.bus!.dispose();
        } catch (_) {}
      }
      if (track.synthSource != null &&
          !globalInstrumentSounds.values.contains(track.synthSource)) {
        try {
          SoLoud.instance.disposeSource(track.synthSource!);
        } catch (_) {}
      }
      for (var c in trackClips[track.id] ?? []) {
        if (c is AudioClip && c.source != null) {
          try {
            SoLoud.instance.disposeSource(c.source!);
          } catch (_) {}
        }
      }
      tracks.remove(track);
      trackClips.remove(track.id);
      multiSelectedTrackIds.remove(track.id);
      if (selectedTrackIndex != null && selectedTrackIndex! >= tracks.length) {
        selectedTrackIndex = tracks.isNotEmpty ? tracks.length - 1 : null;
      }
      if (selectedClip != null &&
          !trackClips.values.expand((x) => x).contains(selectedClip)) {
        selectedClip = null;
      }
      multiSelectedClips.removeWhere(
        (c) => !trackClips.values.expand((x) => x).contains(c),
      );
    });
    _updateMicState();
  }

  void _deleteTrack(Track track) {
    if ((trackClips[track.id] ?? []).isNotEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete Track'),
          content: Text('This track contains clips. Are you sure you want to delete it?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _executeDeleteTrack(track);
              },
              child: Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
    } else {
      _executeDeleteTrack(track);
    }
  }

  void _showTimelineMenu(Offset pos) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [PopupMenuItem(value: 'paste', child: Text('Paste'))],
    );
    if (result == 'paste') {
      _paste();
    }
  }

  Future<void> _showRenameClipDialog(DawClip clip) async {
    final ctrl = TextEditingController(text: clip.name);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: panelDark,
        title: Text('Rename Clip', style: TextStyle(color: textMain)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: textMain),
          decoration: InputDecoration(
            hintText: 'Clip name...',
            filled: true,
            fillColor: bgDark,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _saveState();
              _setState(() => clip.name = ctrl.text.trim());
              Navigator.pop(ctx);
            },
            child: Text('Save', style: TextStyle(color: lavenderAccent)),
          ),
        ],
      ),
    );
  }

  Future<void> _showClipGainPitchDialog(AudioClip clip) async {
    double tmpGain = clip.gain;
    double tmpPitch = clip.pitchSemitones;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: panelDark,
          title: Text('Clip Gain & Pitch', style: TextStyle(color: textMain)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Gain', style: TextStyle(color: textMuted)),
                  Text('${(tmpGain * 100).round()}%', style: TextStyle(color: textMain)),
                ],
              ),
              Slider(
                value: tmpGain.clamp(0.0, 2.0),
                min: 0.0,
                max: 2.0,
                activeColor: lavenderAccent,
                onChanged: (v) => setModalState(() => tmpGain = v),
              ),
              SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Pitch Shift', style: TextStyle(color: textMuted)),
                  Text(
                    '${tmpPitch >= 0 ? "+" : ""}${tmpPitch.round()} st',
                    style: TextStyle(color: textMain),
                  ),
                ],
              ),
              Slider(
                value: tmpPitch.clamp(-12.0, 12.0),
                min: -12.0,
                max: 12.0,
                divisions: 24,
                activeColor: Colors.cyanAccent,
                onChanged: (v) => setModalState(() => tmpPitch = v.roundToDouble()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                _saveState();
                _setState(() {
                  clip.gain = tmpGain;
                  clip.pitchSemitones = tmpPitch;
                });
                Navigator.pop(ctx);
              },
              child: Text('Apply', style: TextStyle(color: lavenderAccent)),
            ),
          ],
        ),
      ),
    );
  }

  void _syncLinkedMidiClips(MidiClip edited) {
    final groupId = edited.patternGroupId;
    if (groupId == null) return;
    for (final list in trackClips.values) {
      for (final c in list) {
        if (c is MidiClip && c.patternGroupId == groupId && !identical(c, edited)) {
          c.notes = edited.notes
              .map(
                (n) => MidiNote(
                  pitch: n.pitch,
                  start: n.start,
                  length: n.length,
                  velocity: n.velocity,
                ),
              )
              .toList();
          c.length = edited.length;
        }
      }
    }
  }

  Future<void> _showStretchClipDialog(AudioClip clip) async {
    int targetBars = max(1, (clip.length / (beatWidth * timeSigTop)).round());
    double stretch = clip.stretchFactor;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: panelDark,
          title: Text('Stretch / Fit Clip', style: TextStyle(color: textMain)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Speed Multiplier: ${stretch.toStringAsFixed(2)}x',
                style: TextStyle(color: textMuted, fontSize: 12),
              ),
              Slider(
                value: stretch.clamp(0.5, 2.0),
                min: 0.5,
                max: 2.0,
                divisions: 30,
                activeColor: lavenderAccent,
                onChanged: (v) => setDlgState(() => stretch = v),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [1, 2, 4, 8].map((bars) {
                  return ActionChip(
                    label: Text('Fit $bars Bar${bars > 1 ? 's' : ''}'),
                    onPressed: () {
                      final desiredPx = bars * timeSigTop * beatWidth;
                      setDlgState(() {
                        targetBars = bars;
                        stretch = (clip.originalLength / desiredPx).clamp(0.5, 2.0);
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 6),
              Text(
                'Target: $targetBars bar(s) at $bpm BPM',
                style: TextStyle(color: textFaint, fontSize: 11),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                _saveState();
                _setState(() {
                  clip.stretchFactor = stretch;
                  clip.length = (clip.originalLength / stretch).clamp(20.0, 20000.0);
                });
                Navigator.pop(ctx);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _autoMatchClipBpm(AudioClip clip) async {
    double? detectedBpm;
    try {
      final file = File(clip.filePath);
      if (file.existsSync()) {
        final decoded = decodeWavBytes(await file.readAsBytes());
        if (decoded != null && decoded.left.isNotEmpty) {
          final durSec = decoded.left.length / decoded.sampleRate;
          final transients = detectTransientsFromSamples(
            decoded.left,
            decoded.right,
            decoded.sampleRate,
            maxSlices: 32,
          );
          if (transients.length >= 2) {
            final deltas = <double>[];
            for (int i = 1; i < transients.length; i++) {
              final dt = (transients[i].$1 - transients[i - 1].$1) * durSec;
              if (dt >= 0.25 && dt <= 1.5) deltas.add(dt);
            }
            if (deltas.isNotEmpty) {
              deltas.sort();
              final medBeatSec = deltas[deltas.length ~/ 2];
              detectedBpm = (60.0 / medBeatSec).clamp(60.0, 190.0);
            }
          }
          if (detectedBpm == null && durSec > 0.5) {
            // Fallback: fit nearest power-of-2 bar count to project BPM
            final rawBars = (durSec * (bpm / 60.0)) / timeSigTop;
            final snappedBars = max(1, rawBars.round());
            final targetDurSec = (snappedBars * timeSigTop * 60.0) / bpm;
            final ratio = (durSec / targetDurSec).clamp(0.5, 2.0);
            _saveState();
            _setState(() {
              clip.stretchFactor = ratio;
              clip.length = snappedBars * timeSigTop * beatWidth;
            });
            return;
          }
        }
      }
    } catch (_) {}

    if (detectedBpm != null) {
      final ratio = (bpm / detectedBpm).clamp(0.5, 2.0);
      _saveState();
      _setState(() {
        clip.stretchFactor = ratio;
        clip.length = (clip.originalLength / ratio).clamp(20.0, 20000.0);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Detected ~${detectedBpm.round()} BPM -> stretched ${ratio.toStringAsFixed(2)}x to $bpm BPM',
            ),
          ),
        );
      }
    }
  }

  void _showClipMenu(Offset pos, String trackId, DawClip clip) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        PopupMenuItem(value: 'rename', child: Text('Rename Clip')),
        PopupMenuItem(value: 'copy', child: Text('Copy')),
        PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
        if (clip is MidiClip) ...[
          PopupMenuItem(
            value: 'duplicate_linked',
            child: Text('Duplicate as Linked Alias'),
          ),
          if (clip.patternGroupId != null)
            PopupMenuItem(value: 'make_unique', child: Text('Make Unique')),
        ],
        PopupMenuDivider(),
        PopupMenuItem(value: 'delete', child: Text('Delete Clip')),
        PopupMenuItem(value: 'split', child: Text('Split at Playhead')),
        if (clip is AudioClip) ...[
          PopupMenuItem(value: 'gain_pitch', child: Text('Gain & Pitch...')),
          PopupMenuItem(value: 'stretch_bars', child: Text('Stretch / Fit to Bars...')),
          PopupMenuItem(value: 'auto_bpm', child: Text('Auto-Match Project BPM')),
          PopupMenuItem(value: 'normalize', child: Text('Normalize (-1 dBFS)')),
          PopupMenuItem(value: 'strip_silence', child: Text('Strip Silence')),
          PopupMenuItem(value: 'audio_to_midi', child: Text('Extract Melody to MIDI Track')),
          PopupMenuItem(value: 'reverse', child: Text('Reverse Audio')),
          PopupMenuItem(value: 'slice_sampler', child: Text('Slice to Sampler Track')),
          if (clip.takes.isNotEmpty) ...[
            const PopupMenuDivider(),
            for (int ti = 0; ti < clip.takes.length; ti++)
              PopupMenuItem(
                value: 'take_$ti',
                child: Row(
                  children: [
                    Icon(
                      ti == clip.activeTakeIndex
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 14,
                      color: ti == clip.activeTakeIndex ? Colors.cyanAccent : textMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(clip.takes[ti].name),
                  ],
                ),
              ),
          ],
        ],
        PopupMenuDivider(),
        PopupMenuItem(value: 'clip_color', child: Text('Change Clip Color...')),
        PopupMenuItem(value: 'track_color', child: Text('Change Track Color...')),
      ],
    );
    if (result == 'rename') {
      await _showRenameClipDialog(clip);
    } else if (result == 'copy') {
      _copy();
    } else if (result == 'duplicate') {
      _saveState();
      final json = clip.toJson();
      final dup = DawClip.fromJson(json);
      dup.id = UniqueKey().toString();
      if (dup is MidiClip) dup.patternGroupId = null;
      dup.start = clip.start + clip.length;
      if (dup is AudioClip && SoLoud.instance.isInitialized) {
        try {
          dup.source = await SoLoud.instance.loadFile(dup.filePath);
        } catch (_) {}
      }
      _setState(() {
        trackClips[trackId]?.add(dup);
        selectedClip = dup;
      });
    } else if (result == 'duplicate_linked' && clip is MidiClip) {
      _saveState();
      clip.patternGroupId ??= UniqueKey().toString();
      final dup = DawClip.fromJson(clip.toJson()) as MidiClip;
      dup.id = UniqueKey().toString();
      dup.start = clip.start + clip.length;
      dup.patternGroupId = clip.patternGroupId;
      _setState(() {
        trackClips[trackId]?.add(dup);
        selectedClip = dup;
      });
    } else if (result == 'make_unique' && clip is MidiClip) {
      _saveState();
      _setState(() => clip.patternGroupId = null);
    } else if (result == 'gain_pitch' && clip is AudioClip) {
      await _showClipGainPitchDialog(clip);
    } else if (result == 'stretch_bars' && clip is AudioClip) {
      await _showStretchClipDialog(clip);
    } else if (result == 'auto_bpm' && clip is AudioClip) {
      await _autoMatchClipBpm(clip);
    } else if (result != null && result.startsWith('take_') && clip is AudioClip) {
      final idx = int.tryParse(result.substring(5));
      if (idx != null) {
        _saveState();
        clip.selectTake(idx);
        if (SoLoud.instance.isInitialized) {
          try {
            clip.source = await SoLoud.instance.loadFile(clip.filePath);
          } catch (_) {}
        }
        _setState(() {});
      }
    } else if (result == 'normalize' && clip is AudioClip) {
      await _normalizeAudioClip(clip);
    } else if (result == 'strip_silence' && clip is AudioClip) {
      await _stripSilenceAudioClip(trackId, clip);
    } else if (result == 'audio_to_midi' && clip is AudioClip) {
      await _extractMelodyFromClip(clip);
    } else if (result == 'slice_sampler' && clip is AudioClip) {
      await _sliceClipToSampler(clip);
    } else if (result == 'delete') {
      _saveState();
      _setState(() {
        if (clip is AudioClip && clip.currentHandle != null) {
          SoLoud.instance.stop(clip.currentHandle!);
        }
        if (multiSelectedClips.contains(clip)) {
          for (var c in multiSelectedClips) {
            trackClips[trackId]?.remove(c);
          }
          multiSelectedClips.clear();
        } else {
          trackClips[trackId]?.remove(clip);
        }
        if (selectedClip == clip) selectedClip = null;
      });
    } else if (result == 'split') {
      final ok = _splitClipAtTimelinePos(trackId, clip, playheadPosition);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Playhead must be intersecting the clip to split it',
            ),
          ),
        );
      }
    } else if (result == 'reverse' && clip is AudioClip) {
      _saveState();
      await clip.toggleReverse();
      _setState(() {});
    } else if (result == 'clip_color') {
      _showClipColorPicker(clip);
    } else if (result == 'track_color') {
      final track = tracks.where((t) => t.id == trackId).firstOrNull;
      if (track != null) _showTrackColorPicker(track);
    }
  }

  /// Splits [clip] on [trackId] at [splitPoint] in timeline units.
  /// Returns true if the split succeeded.
  bool _splitClipAtTimelinePos(String trackId, DawClip clip, double splitPoint) {
    if (splitPoint <= clip.start || splitPoint >= clip.start + clip.length) {
      return false;
    }
    final double newLen1 = splitPoint - clip.start;
    final double newLen2 = clip.length - newLen1;
    DawClip newClip;
    if (clip is AudioClip) {
      newClip = AudioClip(
        id: UniqueKey().toString(),
        name: clip.name,
        start: splitPoint,
        length: newLen2,
        color: clip.color,
        filePath: clip.filePath,
        originalLength: clip.originalLength,
        startOffset: clip.startOffset + newLen1,
        fadeIn: 0.0,
        fadeOut: clip.fadeOut,
        gain: clip.gain,
        pitchSemitones: clip.pitchSemitones,
        stretchFactor: clip.stretchFactor,
        reversed: clip.reversed,
        originalFilePath: clip.originalFilePath,
      );
      clip.fadeOut = 0.0;
      clip.fadeIn = clip.fadeIn.clamp(0.0, newLen1);
      if (clip.source != null) {
        (newClip as AudioClip).source = clip.source;
      }
    } else {
      newClip = MidiClip(
        id: UniqueKey().toString(),
        name: clip.name,
        start: splitPoint,
        length: newLen2,
        color: clip.color,
        notes: [],
        originalLength: clip.originalLength,
        startOffset: clip.startOffset + newLen1,
      );
      for (var n in List.from((clip as MidiClip).notes)) {
        if (n.start >= clip.startOffset + newLen1) {
          (newClip as MidiClip).notes.add(n);
          clip.notes.remove(n);
        }
      }
    }
    _saveState();
    _setState(() {
      clip.length = newLen1;
      trackClips[trackId]?.add(newClip);
    });
    return true;
  }

  Future<void> _normalizeAudioClip(AudioClip clip) async {
    final normPath = await normalizeWavPeak(clip.filePath);
    if (normPath == null) return;
    _saveState();
    clip.filePath = normPath;
    if (SoLoud.instance.isInitialized) {
      try {
        clip.source = await SoLoud.instance.loadFile(normPath);
      } catch (_) {}
    }
    clip.refreshWaveform();
    _setState(() {});
  }

  Future<void> _stripSilenceAudioClip(String trackId, AudioClip clip) async {
    final ranges = await detectAudioNonSilentRanges(clip.filePath);
    if (ranges.length <= 1 &&
        (ranges.isEmpty || (ranges.first.$1 < 0.02 && ranges.first.$2 > 0.98))) {
      return;
    }
    _saveState();
    final replacement = <DawClip>[];
    for (final (sFrac, eFrac) in ranges) {
      final segStart = clip.start + sFrac * clip.length;
      final segLen = (eFrac - sFrac) * clip.length;
      final segOffset = clip.startOffset + sFrac * clip.length;
      final seg = AudioClip(
        id: UniqueKey().toString(),
        name: '${clip.name} ${replacement.length + 1}',
        start: segStart,
        length: segLen,
        originalLength: clip.originalLength,
        startOffset: segOffset,
        color: clip.color,
        filePath: clip.filePath,
        gain: clip.gain,
        pitchSemitones: clip.pitchSemitones,
        stretchFactor: clip.stretchFactor,
      )..source = clip.source;
      replacement.add(seg);
    }
    _setState(() {
      final list = trackClips[trackId];
      if (list != null) {
        list.remove(clip);
        list.addAll(replacement);
        selectedClip = replacement.isNotEmpty ? replacement.first : null;
      }
    });
  }

  Future<void> _extractMelodyFromClip(AudioClip clip) async {
    final notes = await extractMelodyMidiNotes(clip.filePath, clip.length);
    if (notes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No clear pitched melody detected in ${clip.name}')),
        );
      }
      return;
    }
    _saveState();
    final trackColor = kTrackColorPalette[tracks.length % kTrackColorPalette.length];
    final midiTrack = Track(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: '${clip.name} MIDI',
      type: TrackType.midi,
      colorValue: trackColor.toARGB32(),
    );
    if (_isSoloudReady) {
      midiTrack.bus = ensureActiveBus(midiTrack.bus);
      final preset = getInstrumentPreset(0);
      midiTrack.synthSourcePath = preset.assetPath;
      midiTrack.synthSource = globalInstrumentSounds[0];
    }
    final newClip = MidiClip(
      id: UniqueKey().toString(),
      name: '${clip.name} Melody',
      start: clip.start,
      length: clip.length,
      color: midiTrack.color,
      notes: notes,
    );
    _setState(() {
      tracks.add(midiTrack);
      trackClips[midiTrack.id] = [newClip];
      selectedTrackIndex = tracks.length - 1;
      selectedClip = newClip;
      selectedBottomTab = 0;
    });
  }

  bool _isTrackVisibleInArrange(Track track) {
    if (track.groupTrackId == null) return true;
    final grp = _groupForTrack(track);
    return grp == null || !grp.isGroupCollapsed;
  }

  void _assignTrackToGroupDialog(Track track) {
    final groups = tracks.where((t) => t.type == TrackType.group).toList();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: panelDark,
        title: Text('Route ${track.name} to Group Bus'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Direct to Master Bus'),
              trailing: track.groupTrackId == null
                  ? Icon(Icons.check, color: Colors.cyanAccent)
                  : null,
              onTap: () {
                _saveState();
                _setState(() => track.groupTrackId = null);
                Navigator.pop(ctx);
              },
            ),
            for (final g in groups)
              ListTile(
                leading: CircleAvatar(radius: 6, backgroundColor: g.color),
                title: Text(g.name),
                trailing: track.groupTrackId == g.id
                    ? Icon(Icons.check, color: Colors.cyanAccent)
                    : null,
                onTap: () {
                  _saveState();
                  _setState(() => track.groupTrackId = g.id);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _applyTrackColor(Track track, Color color) {
    _setState(() {
      track.colorValue = color.toARGB32();
      for (final clip in trackClips[track.id] ?? const <DawClip>[]) {
        clip.color = color;
      }
    });
  }

  void _applyClipColor(DawClip clip, Color color) {
    _saveState();
    _setState(() {
      final targets = multiSelectedClips.contains(clip)
          ? multiSelectedClips
          : [clip];
      for (final c in targets) {
        c.color = color;
      }
    });
  }

  void _showColorPickerDialog({
    required String title,
    required Color initialColor,
    required ValueChanged<Color> onColorSelected,
  }) {
    HSLColor customHsl = HSLColor.fromColor(initialColor);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final customColor = customHsl.toColor();
          return AlertDialog(
            backgroundColor: panelDark,
            title: Text(title, style: TextStyle(color: textMain)),
            content: SizedBox(
              width: 316,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(kTrackColorPalette.length, (i) {
                      final c = kTrackColorPalette[i];
                      final label = i < kTrackColorNames.length
                          ? kTrackColorNames[i]
                          : 'Color ${i + 1}';
                      final isCur = initialColor.toARGB32() == c.toARGB32();
                      return Tooltip(
                        message: label,
                        child: GestureDetector(
                          onTap: () {
                            onColorSelected(c);
                            Navigator.pop(ctx);
                          },
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isCur ? Colors.white : Colors.black38,
                                width: isCur ? 3 : 1,
                              ),
                            ),
                            child: isCur
                                ? const Icon(
                                    Icons.check,
                                    size: 16,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 14),
                  Divider(color: textMuted.withValues(alpha: 0.25), height: 1),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        'Custom Color',
                        style: TextStyle(
                          color: textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: customColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white70, width: 1.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      SizedBox(
                        width: 32,
                        child: Text(
                          'Hue',
                          style: TextStyle(color: textMuted, fontSize: 10),
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: customHsl.hue,
                          min: 0.0,
                          max: 360.0,
                          activeColor: customColor,
                          onChanged: (v) => setModalState(
                            () => customHsl = customHsl.withHue(v),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      SizedBox(
                        width: 32,
                        child: Text(
                          'Sat',
                          style: TextStyle(color: textMuted, fontSize: 10),
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: customHsl.saturation.clamp(0.0, 1.0),
                          min: 0.0,
                          max: 1.0,
                          activeColor: customColor,
                          onChanged: (v) => setModalState(
                            () => customHsl = customHsl.withSaturation(v),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      SizedBox(
                        width: 32,
                        child: Text(
                          'Light',
                          style: TextStyle(color: textMuted, fontSize: 10),
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: customHsl.lightness.clamp(0.2, 0.85),
                          min: 0.2,
                          max: 0.85,
                          activeColor: customColor,
                          onChanged: (v) => setModalState(
                            () => customHsl = customHsl.withLightness(v),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: customColor,
                  foregroundColor: Colors.black,
                ),
                onPressed: () {
                  onColorSelected(customColor);
                  Navigator.pop(ctx);
                },
                child: const Text('Apply Custom'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showTrackColorPicker(Track track) {
    _showColorPickerDialog(
      title: 'Track Color',
      initialColor: track.color,
      onColorSelected: (c) {
        _saveState();
        _applyTrackColor(track, c);
      },
    );
  }

  void _showClipColorPicker(DawClip clip) {
    _showColorPickerDialog(
      title: 'Clip Color',
      initialColor: clip.color,
      onColorSelected: (c) => _applyClipColor(clip, c),
    );
  }

  bool _isTrackSelected(Track track, int index) =>
      multiSelectedTrackIds.contains(track.id) ||
      (multiSelectedTrackIds.isEmpty && selectedTrackIndex == index);

  List<Track> _targetTracksForTrackAction(Track clickedTrack) {
    if (multiSelectedTrackIds.length > 1 &&
        multiSelectedTrackIds.contains(clickedTrack.id)) {
      return tracks.where((t) => multiSelectedTrackIds.contains(t.id)).toList();
    }
    return [clickedTrack];
  }

  void _deleteTracks(List<Track> toDelete) {
    if (toDelete.length <= 1) {
      if (toDelete.isNotEmpty) _deleteTrack(toDelete.first);
      return;
    }
    final bool hasAnyClips = toDelete.any(
      (t) => (trackClips[t.id] ?? []).isNotEmpty,
    );
    void runDeleteAll() {
      for (final t in [...toDelete]) {
        if (tracks.contains(t)) {
          _executeDeleteTrack(t);
        }
      }
    }

    if (hasAnyClips) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete ${toDelete.length} Tracks'),
          content: Text(
            'Selected tracks contain clips. Are you sure you want to delete them?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                runDeleteAll();
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
    } else {
      runDeleteAll();
    }
  }

  void _handleTrackSelectionClick(int index, {bool clearClipsOnSingle = false}) {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final bool isShift =
        HardwareKeyboard.instance.isShiftPressed ||
        keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
    final bool isCtrlOrMeta =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight) ||
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);

    final Set<String> baseIds = multiSelectedTrackIds.isNotEmpty
        ? multiSelectedTrackIds
        : (selectedTrackIndex != null && selectedTrackIndex! < tracks.length
              ? {tracks[selectedTrackIndex!].id}
              : const <String>{});

    final res = resolveTrackClickSelection(
      trackIds: tracks.map((t) => t.id).toList(),
      trackVisible: tracks.map(_isTrackVisibleInArrange).toList(),
      currentSelectedIds: baseIds,
      anchorIndex: _trackSelectionAnchorIndex ?? selectedTrackIndex,
      clickedIndex: index,
      isShiftPressed: isShift,
      isCtrlOrMetaPressed: isCtrlOrMeta,
    );

    final bool wasSingleSame =
        !isShift &&
        !isCtrlOrMeta &&
        selectedTrackIndex == index &&
        multiSelectedTrackIds.length <= 1;

    multiSelectedTrackIds = res.selectedTrackIds;
    _trackSelectionAnchorIndex = res.anchorIndex;
    selectedTrackIndex = res.primaryIndex;

    if (clearClipsOnSingle || (!isShift && !isCtrlOrMeta && !wasSingleSame)) {
      selectedClip = null;
      multiSelectedClips.clear();
    }

    if (selectedTrackIndex != null && selectedTrackIndex! < tracks.length) {
      final track = tracks[selectedTrackIndex!];
      if ((track.type == TrackType.audio || track.type == TrackType.group) &&
          (selectedBottomTab == 0 || selectedBottomTab == 3)) {
        selectedBottomTab = track.type == TrackType.audio ? 4 : 2;
      } else if (track.type == TrackType.midi &&
          (selectedBottomTab == 3 || selectedBottomTab == 4)) {
        selectedBottomTab = 0;
      } else if (track.type == TrackType.group && selectedBottomTab == 4) {
        selectedBottomTab = 2;
      }
      if (!wasSingleSame && track.type == TrackType.sampler) {
        selectedBottomTab = 3;
        isBottomPanelExpanded = true;
        if (_bottomPanelHeight < 400) {
          _bottomPanelHeight = 400;
        }
      }
    }
  }

  Offset? _globalToTimelineContentPoint(Offset globalPos) {
    final box =
        _timelineLaneListKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final local = box.globalToLocal(globalPos);
    final double scrollOffset = _timelineScrollController.hasClients
        ? _timelineScrollController.offset
        : 0.0;
    final double timelineX =
        (local.dx / _zoomX).clamp(0.0, _timelineTotalUnits);
    final double contentY = max(0.0, local.dy + scrollOffset);
    return Offset(timelineX, contentY);
  }

  void _applyMarqueeSelection() {
    if (_marqueeStart == null || _marqueeEnd == null) return;
    final double minX = min(_marqueeStart!.dx, _marqueeEnd!.dx);
    final double maxX = max(_marqueeStart!.dx, _marqueeEnd!.dx);
    final double minY = min(_marqueeStart!.dy, _marqueeEnd!.dy);
    final double maxY = max(_marqueeStart!.dy, _marqueeEnd!.dy);

    final rows = <TimelineTrackRowLayout>[];
    double yCursor = 0.0;
    for (final t in tracks) {
      if (!_isTrackVisibleInArrange(t)) continue;
      final double rowH = t.showAutomation ? 140.0 : 100.0;
      final clips = (trackClips[t.id] ?? const <DawClip>[])
          .map(
            (c) => TimelineClipLayout(
              clipId: c.id,
              start: c.start,
              length: c.length,
            ),
          )
          .toList();
      rows.add(
        TimelineTrackRowLayout(
          trackId: t.id,
          top: yCursor,
          bottom: yCursor + rowH,
          clips: clips,
        ),
      );
      yCursor += rowH;
    }

    final result = computeTimelineMarqueeSelection(
      rows,
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
    );

    final nextTracks = {..._marqueeBaseTrackIds, ...result.trackIds};
    multiSelectedTrackIds = nextTracks;
    if (nextTracks.isNotEmpty) {
      if (selectedTrackIndex == null ||
          selectedTrackIndex! >= tracks.length ||
          !nextTracks.contains(tracks[selectedTrackIndex!].id)) {
        final idx = tracks.indexWhere((t) => nextTracks.contains(t.id));
        if (idx != -1) {
          selectedTrackIndex = idx;
          _trackSelectionAnchorIndex = idx;
        }
      }
    }

    final nextClips = <DawClip>[..._marqueeBaseClips];
    for (final t in tracks) {
      for (final c in trackClips[t.id] ?? const <DawClip>[]) {
        if (result.clipIds.contains(c.id) && !nextClips.contains(c)) {
          nextClips.add(c);
        }
      }
    }
    multiSelectedClips = nextClips;
    selectedClip = nextClips.isNotEmpty ? nextClips.last : null;
  }

  void _startTimelineMarquee(Offset globalPos) {
    final startPt = _globalToTimelineContentPoint(
      _lastTimelinePointerDownGlobal ?? globalPos,
    );
    final endPt = _globalToTimelineContentPoint(globalPos) ?? startPt;
    _lastTimelinePointerDownGlobal = null;
    if (startPt == null || endPt == null) return;
    final bool additive = HardwareKeyboard.instance.isShiftPressed;
    _setState(() {
      if (additive) {
        _marqueeBaseClips = [...multiSelectedClips];
        _marqueeBaseTrackIds = {...multiSelectedTrackIds};
      } else {
        _marqueeBaseClips = [];
        _marqueeBaseTrackIds = {};
        multiSelectedClips.clear();
        multiSelectedTrackIds.clear();
        selectedClip = null;
      }
      isSelecting = true;
      _marqueeStart = startPt;
      _marqueeEnd = endPt;
      _applyMarqueeSelection();
    });
  }

  void _updateTimelineMarquee(Offset globalPos) {
    if (!isSelecting || _marqueeStart == null) return;
    final pt = _globalToTimelineContentPoint(globalPos);
    if (pt == null) return;
    _setState(() {
      _marqueeEnd = pt;
      _applyMarqueeSelection();
    });
  }

  void _endTimelineMarquee() {
    if (!isSelecting && _marqueeStart == null && _marqueeEnd == null) return;
    _setState(() {
      isSelecting = false;
      _marqueeStart = null;
      _marqueeEnd = null;
      _marqueeBaseClips = [];
      _marqueeBaseTrackIds = {};
    });
  }

  bool _canMoveClipToTrack(DawClip clip, Track targetTrack) {
    if (targetTrack.type == TrackType.group) return false;
    if (clip is AudioClip) return targetTrack.type == TrackType.audio;
    return targetTrack.type == TrackType.midi ||
        targetTrack.type == TrackType.sampler;
  }

  Track? _trackAtGlobalY(double globalY) {
    final box =
        _timelineLaneListKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final double localY = box.globalToLocal(Offset(0, globalY)).dy;
    if (localY < 0 || localY > box.size.height) return null;
    final double contentY = localY +
        (_timelineScrollController.hasClients
            ? _timelineScrollController.offset
            : 0.0);
    double yCursor = 0.0;
    for (final t in tracks) {
      if (!_isTrackVisibleInArrange(t)) continue;
      final double rowH = t.showAutomation ? 140.0 : 100.0;
      if (contentY >= yCursor && contentY < yCursor + rowH) {
        return t;
      }
      yCursor += rowH;
    }
    return null;
  }

  String? _ownerTrackIdForClip(DawClip clip) {
    for (final t in tracks) {
      if (trackClips[t.id]?.contains(clip) == true) {
        return t.id;
      }
    }
    return null;
  }

  void _moveClipsToTrack(List<DawClip> targets, Track destinationTrack) {
    for (final c in targets) {
      if (!_canMoveClipToTrack(c, destinationTrack)) continue;
      final oldOwnerId = _ownerTrackIdForClip(c);
      if (oldOwnerId == null || oldOwnerId == destinationTrack.id) continue;
      final oldTrack = tracks.where((t) => t.id == oldOwnerId).firstOrNull;
      trackClips[oldOwnerId]?.remove(c);
      trackClips.putIfAbsent(destinationTrack.id, () => []).add(c);
      if (oldTrack != null && c.color.toARGB32() == oldTrack.colorValue) {
        c.color = destinationTrack.color;
      }
      if (c is AudioClip) {
        _stopAudioClipHandles(c);
        if (isPlaying &&
            c.source != null &&
            playheadPosition >= c.start &&
            playheadPosition < c.start + c.length) {
          final anySolo = tracks.any((t) => t.isSolo);
          if (_isTrackAudible(destinationTrack, anySolo)) {
            _playAudioClipWithSends(destinationTrack, c, playheadPosition);
          }
        }
      }
    }
    final destIdx = tracks.indexOf(destinationTrack);
    if (destIdx != -1) {
      selectedTrackIndex = destIdx;
    }
  }

  DawClip _cloneClipForDragCopy(String trackId, DawClip sourceClip) {
    final dup = DawClip.fromJson(sourceClip.toJson());
    dup.id = UniqueKey().toString();
    if (dup is MidiClip) {
      dup.patternGroupId = null;
    } else if (dup is AudioClip && sourceClip is AudioClip) {
      dup.waveformData = sourceClip.waveformData;
      dup.processedFilePath = sourceClip.processedFilePath;
      dup.processedCacheKey = sourceClip.processedCacheKey;
      dup.source = sourceClip.source;
      try {
        if (SoLoud.instance.isInitialized) {
          final loadPath = dup.playbackFilePath;
          Future(() async {
            try {
              final src = loadPath.startsWith('assets/')
                  ? await SoLoud.instance.loadAsset(loadPath)
                  : await SoLoud.instance.loadFile(loadPath);
              dup.source = src;
            } catch (_) {}
          });
        }
      } catch (_) {}
    }
    trackClips.putIfAbsent(trackId, () => []).add(dup);
    return dup;
  }

}
