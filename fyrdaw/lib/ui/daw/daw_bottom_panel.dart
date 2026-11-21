part of '../../main.dart';

extension _DawBottomPanelView on _DawMainScreenState {

  void _addEffectToTrack(String val) {
    _setState(() {
      DawEffect effect;
      if (val == 'EQ') {
        effect = DawEffect('EQ', {'Low': 0.5, 'Mid': 0.5, 'High': 0.5});
      } else if (val == 'Compressor') {
        effect = DawEffect('Compressor', {
          'Thresh': 0.5,
          'Ratio': 0.5,
          'Gain': 0.5,
          'Mix': 1.0,
        });
      } else if (val == 'Overdrive' || val == 'TubeScreamer') {
        effect = DawEffect('Overdrive', {
          'Drive': 0.5,
          'Tone': 0.5,
          'Level': 0.5,
        });
      } else if (val == 'Reverb') {
        effect = DawEffect('Reverb', {'Size': 0.5, 'Decay': 0.5, 'Mix': 0.5});
      } else if (val == 'Echo') {
        effect = DawEffect('Echo', {'Delay': 0.3, 'Decay': 0.5, 'Mix': 0.5});
      } else if (val == 'Flanger') {
        effect = DawEffect('Flanger', {'Rate': 0.2, 'Delay': 0.5, 'Mix': 0.5});
      } else if (val == 'Chorus') {
        effect = DawEffect('Chorus', {'Rate': 0.4, 'Depth': 0.6, 'Mix': 0.5});
      } else if (val == 'Lofi') {
        effect = DawEffect('Lofi', {'Rate': 0.2, 'Bits': 0.3, 'Mix': 1.0});
      } else if (val == 'Robotize') {
        effect = DawEffect('Robotize', {'Freq': 0.3, 'Mix': 1.0});
      } else if (val == 'BassBoost') {
        effect = DawEffect('BassBoost', {'Boost': 0.5, 'Mix': 1.0});
      } else if (val == 'GuitarAmp') {
        effect = DawEffect('GuitarAmp', {
          'Drive': 0.7,
          'Tone': 0.6,
          'Level': 0.5,
        });
      } else {
        effect = DawEffect('Unknown', {});
      }
      if (_isMasterFxSelected) {
        masterEffectsChain.add(effect);
        _syncMasterAndAuxFilters();
      } else if (selectedTrackIndex != null &&
          selectedTrackIndex! < tracks.length) {
        tracks[selectedTrackIndex!].effectsChain.add(effect);
        _updateTrackFilters(tracks[selectedTrackIndex!]);
      }
    });
  }

  void _showAddEffectDialog() {
    final List<Map<String, dynamic>> availableEffects = [
      {
        'name': 'EQ',
        'color': Colors.blue[800]!,
        'desc': '3-band Equalizer to cut or boost frequencies.',
      },
      {
        'name': 'Compressor',
        'color': Colors.green[800]!,
        'desc': 'Reduces the dynamic range of the audio.',
      },
      {
        'name': 'Overdrive',
        'color': Colors.red[800]!,
        'desc': 'Classic warm overdrive distortion effect.',
      },
      {
        'name': 'Reverb',
        'color': Colors.deepPurple[800]!,
        'desc': 'Simulates acoustic spaces and echoes.',
      },
      {
        'name': 'Echo',
        'color': Colors.deepPurple[800]!,
        'desc': 'Simple repeating delay effect.',
      },
      {
        'name': 'Flanger',
        'color': Colors.deepPurple[800]!,
        'desc': 'Sweeping comb filter effect.',
      },
      {
        'name': 'Chorus',
        'color': Colors.deepPurple[800]!,
        'desc': 'Thickens sound by layering delayed copies.',
      },
      {
        'name': 'Lofi',
        'color': Colors.deepPurple[800]!,
        'desc': 'Reduces sample rate and bit depth.',
      },
      {
        'name': 'Robotize',
        'color': Colors.deepPurple[800]!,
        'desc': 'Metallic, robotic ringing effect.',
      },
      {
        'name': 'BassBoost',
        'color': Colors.deepPurple[800]!,
        'desc': 'Enhances low-frequency bass.',
      },
      {
        'name': 'GuitarAmp',
        'color': Colors.grey[900]!,
        'desc': 'Simulates a guitar amplifier head.',
      },
    ];

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: panelDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: 500,
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add Effect',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 16),
                SizedBox(
                  height: 400,
                  child: ListView.builder(
                    itemCount: availableEffects.length,
                    itemBuilder: (context, index) {
                      final effectInfo = availableEffects[index];
                      final name = effectInfo['name'];
                      final color = effectInfo['color'];
                      final desc = effectInfo['desc'];
                      bool isAmp = name == 'GuitarAmp';

                      return InkWell(
                        onTap: () {
                          Navigator.of(context).pop();
                          _addEffectToTrack(name);
                        },
                        child: Container(
                          margin: EdgeInsets.only(bottom: 12),
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: panelLight,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: textFaint),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: isAmp ? 80 : 40,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(
                                    isAmp ? 2 : 4,
                                  ),
                                  border: Border.all(color: Colors.black54),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 2,
                                      offset: Offset(1, 1),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Container(
                                    width: isAmp ? 30 : 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: isAmp
                                          ? Colors.black87
                                          : Colors.grey[400],
                                      shape: isAmp
                                          ? BoxShape.rectangle
                                          : BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.grey[600]!,
                                      ),
                                    ),
                                    child: isAmp
                                        ? Center(
                                            child: Container(
                                              width: 3,
                                              height: 3,
                                              decoration: BoxDecoration(
                                                color: Colors.red,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                              SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      desc,
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
  }

  Widget _buildBottomPanel() {
    final maxH = max(240.0, MediaQuery.of(context).size.height - 140.0);
    final panelH = !isBottomPanelExpanded
        ? 54.0
        : (_isBottomPanelMaximized ? maxH : _bottomPanelHeight.clamp(100.0, maxH));
    return Container(
      height: panelH,
      decoration: BoxDecoration(
        color: panelDark,
        border: Border(top: BorderSide(color: textMuted, width: 2)),
      ),
      child: Column(
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.resizeUpDown,
            child: GestureDetector(
              onVerticalDragUpdate: (details) {
                _setState(() {
                  _isBottomPanelMaximized = false;
                  _bottomPanelHeight -= details.delta.dy;
                  if (_bottomPanelHeight < 100) _bottomPanelHeight = 100;
                  if (_bottomPanelHeight > 800) _bottomPanelHeight = 800;
                });
              },
              child: Container(
                height: 12,
                color: textFaint,
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: textMuted,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(
            height: 40,
            color: panelLight,
            child: tracks.isNotEmpty
                ? Row(
                    children: [
                      if (tracks[selectedTrackIndex!].type == TrackType.midi ||
                          tracks[selectedTrackIndex!].type == TrackType.sampler)
                        _buildPanelTab('Editor', 0),
                      if (tracks[selectedTrackIndex!].type == TrackType.audio ||
                          selectedClip is AudioClip)
                        _buildPanelTab('Audio Editor', 4),
                      _buildPanelTab('Mixer', 1),
                      _buildPanelTab('Effects', 2),
                      if (tracks[selectedTrackIndex!].type == TrackType.sampler)
                        _buildPanelTab('Sampler', 3),
                      Spacer(),
                      IconButton(
                        tooltip: _isBottomPanelMaximized
                            ? 'Restore Console Size'
                            : 'Maximize Dockable Console',
                        icon: Icon(
                          _isBottomPanelMaximized
                              ? Icons.fullscreen_exit
                              : Icons.fullscreen,
                          size: 18,
                          color: _isBottomPanelMaximized
                              ? lavenderAccent
                              : textMuted,
                        ),
                        onPressed: () => _setState(() {
                          if (!isBottomPanelExpanded) {
                            isBottomPanelExpanded = true;
                          }
                          _isBottomPanelMaximized = !_isBottomPanelMaximized;
                        }),
                      ),
                      IconButton(
                        icon: Icon(
                          isBottomPanelExpanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_up,
                          color: textMuted,
                        ),
                        onPressed: () => _setState(() {
                          isBottomPanelExpanded = !isBottomPanelExpanded;
                          if (!isBottomPanelExpanded) {
                            _isBottomPanelMaximized = false;
                          }
                        }),
                      ),
                      SizedBox(width: 8),
                    ],
                  )
                : Container(),
          ),
          if (isBottomPanelExpanded && tracks.isNotEmpty)
            Expanded(child: _buildBottomPanelContent()),
        ],
      ),
    );
  }

  Widget _buildPanelTab(String title, int index) {
    final isActive = selectedBottomTab == index;
    return GestureDetector(
      onTap: () => _setState(() => selectedBottomTab = index),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: isActive ? panelDark : Colors.transparent,
          border: Border(
            top: BorderSide(
              color: isActive ? lavenderAccent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Center(
          child: Text(
            title,
            style: TextStyle(
              color: isActive ? textMain : textMuted,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  void _applyEffectChainPreset(Track track, String presetName) {
    final chain = buildEffectChainForPreset(presetName);
    if (chain == null) return;
    _saveState();
    _setState(() {
      track.effectsChain = chain;
    });
    if (_isMasterFxSelected) {
      masterEffectsChain = track.effectsChain;
      _syncMasterAndAuxFilters();
    } else {
      _updateTrackFilters(track);
    }
  }

  Widget _buildBottomPanelContent() {
    switch (selectedBottomTab) {
      case 0:
        if (selectedClip is MidiClip) {
          final midiClip = selectedClip as MidiClip;
          Track? t;
          for (var tr in tracks) {
            if (trackClips[tr.id]?.contains(midiClip) == true) t = tr;
          }
          // Collect ghost notes from other MIDI tracks overlapping this clip window
          final List<MidiNote> ghostNotes = [];
          final clipEnd = midiClip.start + midiClip.length;
          for (final otherTrack in tracks) {
            if (otherTrack == t) continue;
            for (final c in trackClips[otherTrack.id] ?? const <DawClip>[]) {
              if (c is MidiClip && c.start < clipEnd && (c.start + c.length) > midiClip.start) {
                for (final n in c.notes) {
                  final worldStart = n.start - c.startOffset + c.start;
                  final localStart = worldStart - midiClip.start + midiClip.startOffset;
                  if (localStart + n.length > 0 && localStart < midiClip.length) {
                    ghostNotes.add(
                      MidiNote(
                        pitch: n.pitch,
                        start: localStart,
                        length: n.length,
                        velocity: n.velocity,
                      ),
                    );
                  }
                }
              }
            }
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              double autoZoom =
                  (constraints.maxWidth - 60) / midiClip.length;
              if (autoZoom <= 0) autoZoom = 1.0;
              return MidiEditorWidget(
                clip: midiClip,
                track: t,
                snapToGrid: snapToGrid,
                snapResolution: snapResolution,
                zoomX: autoZoom * _midiZoomMultiplier,
                bpm: bpm,
                timeSigTop: timeSigTop,
                selectedMidiNotes: selectedMidiNotes,
                ghostNotes: ghostNotes,
                grooveAudioClips: tracks
                    .expand((tr) => trackClips[tr.id] ?? const <DawClip>[])
                    .whereType<AudioClip>()
                    .toList(),
                onSelectionChanged: (notes) =>
                    _setState(() => selectedMidiNotes = notes),
                onChangeStart: _saveState,
                onNotesChanged: () {
                  _syncLinkedMidiClips(midiClip);
                  _setState(() {});
                },
                onSynthSettingsChanged: () {
                  if (t != null) _updateTrackFilters(t);
                  _setState(() {});
                },
                onZoomIn: () => _setState(
                  () => _midiZoomMultiplier = min(
                    16.0,
                    _midiZoomMultiplier * 1.35,
                  ),
                ),
                onZoomOut: () => _setState(
                  () => _midiZoomMultiplier = max(
                    0.05,
                    _midiZoomMultiplier / 1.35,
                  ),
                ),
                playheadPosition: playheadPosition,
                onPlayheadChanged: (v) => _seekPlayhead(v),
                midiDevices: _midiDevices,
                onCopy: _copy,
                onPaste: _paste,
                onInstrumentDialogRequested: () => _showInstrumentDialog(t!),
                onMidiInputDialogRequested: () => _showMidiInputDialog(t!),
                onImportMidi: () => _importMidiFile(targetTrack: t),
                onExportMidi: _exportSelectedMidiClip,
                markers: songMarkers,
                tempoMarkers: tempoMarkers,
              );
            },
          );
        } else {
          return Center(
            child: Text(
              'Double click a MIDI track to create a clip, then select it to edit.',
              style: TextStyle(color: textMuted),
            ),
          );
        }
      case 1:
        return MixerConsoleView(
          tracks: tracks,
          trackLevels: _trackLevels,
          trackPeaks: _trackPeaks,
          auxReverbMix: auxReverbMix,
          auxDelayMix: auxDelayMix,
          auxRevLevel: _auxRevLevel,
          auxDlyLevel: _auxDlyLevel,
          auxReverbSolo: auxReverbSolo,
          auxDelaySolo: auxDelaySolo,
          masterVolume: masterVolume,
          masterLimiter: masterLimiter,
          masterLevel: _masterLevel,
          masterPeak: _masterPeak,
          masterVizSamples: _masterVizSamples,
          masterLufs: _masterLufs,
          masterLufsTarget: masterLufsTarget,
          stereoCorrelation: _stereoCorrelation,
          referenceTrackName: _referenceTrackPath != null
              ? p.basename(_referenceTrackPath!)
              : null,
          isAuditioningReference: _isAuditioningReference,
          midiLearnActive: _midiLearnActive,
          midiLearnTarget: _midiLearnTarget,
          onSaveState: _saveState,
          onTrackVolumeChanged: (t, v) => _onTrackVolumeChanged(t, v),
          onTrackPanChanged: (t, v) {
            _setState(() => t.pan = v);
            if (_isSoloudReady) {
              for (final c in trackClips[t.id] ?? []) {
                if (c is AudioClip && c.currentHandle != null) {
                  try {
                    SoLoud.instance.setPan(c.currentHandle!, v.clamp(-1.0, 1.0));
                  } catch (_) {}
                }
              }
            }
            _syncTrackMonitoringHandles();
          },
          onTrackRevSendChanged: (t, v) {
            _setState(() => t.reverbSend = v);
            if (_isSoloudReady) {
              for (final c in trackClips[t.id] ?? []) {
                if (c is AudioClip && c.reverbSendHandle != null) {
                  try {
                    SoLoud.instance.setVolume(
                      c.reverbSendHandle!,
                      v * (t.reverbPreFader ? 1.0 : t.volume) * c.gain,
                    );
                  } catch (_) {}
                }
              }
            }
          },
          onTrackDlySendChanged: (t, v) {
            _setState(() => t.delaySend = v);
            if (_isSoloudReady) {
              for (final c in trackClips[t.id] ?? []) {
                if (c is AudioClip && c.delaySendHandle != null) {
                  try {
                    SoLoud.instance.setVolume(
                      c.delaySendHandle!,
                      v * (t.delayPreFader ? 1.0 : t.volume) * c.gain,
                    );
                  } catch (_) {}
                }
              }
            }
          },
          onToggleReverbPreFader: (t) {
            _saveState();
            _setState(() => t.reverbPreFader = !t.reverbPreFader);
          },
          onToggleDelayPreFader: (t) {
            _saveState();
            _setState(() => t.delayPreFader = !t.delayPreFader);
          },
          onToggleMute: (t) {
            _saveState();
            _setState(() => t.isMuted = !t.isMuted);
            _syncTrackMonitoringHandles();
          },
          onToggleSolo: (t) {
            _saveState();
            _setState(() => t.isSolo = !t.isSolo);
            _syncTrackMonitoringHandles();
          },
          onAuxReverbMixChanged: (v) {
            _setState(() => auxReverbMix = v);
            _syncMasterAndAuxFilters();
          },
          onAuxDelayMixChanged: (v) {
            _setState(() => auxDelayMix = v);
            _syncMasterAndAuxFilters();
          },
          onToggleAuxReverbSolo: () =>
              _setState(() => auxReverbSolo = !auxReverbSolo),
          onToggleAuxDelaySolo: () =>
              _setState(() => auxDelaySolo = !auxDelaySolo),
          onMasterVolumeChanged: (v) {
            _setState(() => masterVolume = v);
            _syncMasterAndAuxFilters();
          },
          onToggleMasterLimiter: () {
            _saveState();
            _setState(() => masterLimiter = !masterLimiter);
            _syncMasterAndAuxFilters();
          },
          onCycleLufsTarget: () {
            _setState(() {
              if (masterLufsTarget <= -13.5) {
                masterLufsTarget = -11.0;
              } else if (masterLufsTarget <= -10.5) {
                masterLufsTarget = -9.0;
              } else {
                masterLufsTarget = -14.0;
              }
            });
          },
          onLoadReference: _loadReferenceTrack,
          onToggleReferenceAB: _toggleReferenceAB,
          onMidiLearnSelect: (trackId, param) {
            _setState(() {
              _midiLearnTarget = '$trackId:$param';
              _midiLearnActive = true;
            });
          },
        );
      case 2:
        if (!_isMasterFxSelected &&
            (selectedTrackIndex == null ||
                selectedTrackIndex! >= tracks.length)) {
          return Center(
            child: Text(
              'No track selected',
              style: TextStyle(color: textMuted),
            ),
          );
        }
        final fxTrack = _isMasterFxSelected
            ? (Track(
                id: '__master__',
                name: 'MASTER BUS',
                type: TrackType.group,
                colorValue: Colors.redAccent.toARGB32(),
              )..effectsChain = masterEffectsChain)
            : tracks[selectedTrackIndex!];
        void syncFx() {
          if (_isMasterFxSelected) {
            _syncMasterAndAuxFilters();
          } else {
            _updateTrackFilters(fxTrack);
          }
        }
        return EffectsRackView(
          track: fxTrack,
          allTracks: tracks,
          inputDevices: _inputDevices,
          selectedInputDevice: _selectedInputDevice,
          inputChannelOptions: _inputChannelOptionsForSelectedDevice(),
          selectedInputChannelId: _isMasterFxSelected
              ? _defaultInputChannelId
              : _channelOptionForTrack(fxTrack).id,
          outputDevices: _outputDevices,
          selectedOutputDeviceKey: _selectedOutputDeviceKey,
          systemDefaultOutputLabel: _systemDefaultOutputLabel,
          recordingLatencyMs: _recordingLatencyMs,
          trackLevel: _isMasterFxSelected
              ? _masterLevel.$1
              : (_trackLevels[fxTrack.id]?.$1 ?? 0.0),
          sidechainGr: _sidechainGr[fxTrack.id] ?? 0.0,
          detectedPitch: _detectedPitch,
          tunerEnabled: _tunerEnabled,
          isMasterRack: _isMasterFxSelected,
          onToggleMasterRack: () =>
              _setState(() => _isMasterFxSelected = !_isMasterFxSelected),
          onSaveState: _saveState,
          onInputDeviceChanged: (newValue) {
            if (newValue != null) {
              _setState(() {
                _selectedInputDevice = newValue;
                final chCount = _channelCountForDevice(newValue);
                _defaultInputChannelId = resolveInputChannelOption(
                  _defaultInputChannelId,
                  chCount,
                ).id;
              });
              _restartMicCapture();
            }
          },
          onInputChannelChanged: (chId) {
            if (chId != null) {
              _selectTrackInputChannel(
                _isMasterFxSelected ? null : fxTrack,
                chId,
              );
            }
          },
          onOutputDeviceChanged: (outKey) {
            if (outKey != null) {
              _selectOutputDevice(outKey);
            }
          },
          onRecordingLatencyChanged: _setRecordingLatencyMs,
          onRefreshInputDevices: () {
            _initInputDevices();
            _initOutputRouting(applyRoute: true);
          },
          onToggleTuner: () async {
            _setState(() {
              _tunerEnabled = !_tunerEnabled;
              _detectedPitch = null;
              _tunerTracker.reset();
            });
            await _updateMicState();
          },
          onNoiseGateChanged: (v) =>
              _setState(() => fxTrack.noiseGateThreshold = v),
          onReorderEffect: (oldIndex, newIndex) {
            if (newIndex > oldIndex) newIndex -= 1;
            _saveState();
            _setState(() {
              final item = fxTrack.effectsChain.removeAt(oldIndex);
              fxTrack.effectsChain.insert(newIndex, item);
              syncFx();
            });
          },
          onRemoveEffect: (idx) {
            _saveState();
            _setState(() {
              fxTrack.effectsChain.removeAt(idx);
              syncFx();
            });
          },
          onToggleBypass: (fx) {
            _saveState();
            _setState(() {
              fx.isBypassed = !fx.isBypassed;
              syncFx();
            });
          },
          onParamChanged: (fx, k, v) {
            _setState(() {
              fx.parameters[k] = v;
              syncFx();
            });
          },
          onSidechainChanged: (fx, sourceId) {
            _saveState();
            _setState(() {
              fx.sidechainTrackId = sourceId;
            });
          },
          onApplyPreset: (presetName) =>
              _applyEffectChainPreset(fxTrack, presetName),
          onAddEffectPressed: _showAddEffectDialog,
          fftSpectrum: _cachedFftBins,
          onAddExternalPluginPressed: () =>
              _showExternalPluginBrowserDialog(fxTrack, syncFx),
        );
      case 3:
        if (selectedTrackIndex != null) {
          return SamplerEditorWidget(
            track: tracks[selectedTrackIndex!],
            onStateChanged: () { _saveState(); _setState(() {}); },
            onRecordSample: () => _recordSampleDialog(),
          );
        }
        return SizedBox();
      case 4:
        AudioClip? targetAudioClip;
        Track? audioOwnerTrack;
        if (selectedClip is AudioClip) {
          targetAudioClip = selectedClip as AudioClip;
          for (final tr in tracks) {
            if (trackClips[tr.id]?.contains(targetAudioClip) == true) {
              audioOwnerTrack = tr;
              break;
            }
          }
        } else if (selectedTrackIndex != null &&
            selectedTrackIndex! < tracks.length) {
          audioOwnerTrack = tracks[selectedTrackIndex!];
          final candidates = trackClips[audioOwnerTrack.id]
              ?.whereType<AudioClip>()
              .toList();
          if (candidates != null && candidates.isNotEmpty) {
            targetAudioClip = candidates.first;
          }
        }
        if (targetAudioClip == null) {
          return Center(
            child: Text(
              'Select or double-click an audio segment on the timeline to trim, split, fade, and process it.',
              style: TextStyle(color: textMuted),
            ),
          );
        }
        final activeAudioClip = targetAudioClip;
        final ownerId = audioOwnerTrack?.id ?? tracks[selectedTrackIndex!].id;
        return AudioClipEditorWidget(
          clip: activeAudioClip,
          track: audioOwnerTrack,
          bpm: bpm,
          beatWidth: beatWidth,
          snapToGrid: snapToGrid,
          snapResolution: snapResolution,
          playheadPosition: playheadPosition,
          onPlayheadChanged: (pos) => _seekPlayhead(pos),
          onChangeStart: _saveState,
          onClipChanged: () {
            _ensureAudioClipProcessed(activeAudioClip);
            if (_isSoloudReady && activeAudioClip.currentHandle != null) {
              try {
                final tr = audioOwnerTrack;
                if (tr != null) {
                  _syncTrackBusOutputVolume(tr);
                }
                final env = tr != null
                    ? _computeClipEnvelope(
                        activeAudioClip,
                        playheadPosition,
                        track: tr,
                      )
                    : activeAudioClip.gain;
                final vol = (tr != null && tr.type != TrackType.audio
                        ? (_effectiveTrackVolume(tr) * env)
                        : env)
                    .clamp(0.0, 4.0);
                SoLoud.instance.setVolume(activeAudioClip.currentHandle!, vol);
              } catch (_) {}
            }
            _setState(() {});
          },
          onSplitClip: (splitPos) =>
              _splitClipAtTimelinePos(ownerId, activeAudioClip, splitPos),
          isPlaying: isPlaying,
          onPlayPause: _togglePlay,
          onNormalize: () => _normalizeAudioClip(activeAudioClip),
          onReverse: () async {
            _saveState();
            await activeAudioClip.toggleReverse();
            _setState(() {});
          },
          onStripSilence: () => _stripSilenceAudioClip(ownerId, activeAudioClip),
          onAutoMatchBpm: () => _autoMatchClipBpm(activeAudioClip),
          onAudioToMidi: () => _extractMelodyFromClip(activeAudioClip),
          onSliceToSampler: () => _sliceClipToSampler(activeAudioClip),
        );
      default:
        return SizedBox();
    }
  }

}
