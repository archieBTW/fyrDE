part of '../main.dart';

class _RecordingNote {
  final MidiClip clip;
  final MidiNote note;
  final double absoluteStartPlayhead;
  _RecordingNote(this.clip, this.note, this.absoluteStartPlayhead);
}

class DawMainScreen extends StatefulWidget {
  const DawMainScreen({super.key});
  @override
  State<DawMainScreen> createState() => _DawMainScreenState();
}

class _DawMainScreenState extends State<DawMainScreen> with WindowListener {
  List<Track> tracks = [];
  int? selectedTrackIndex;
  Set<String> multiSelectedTrackIds = {};
  int? _trackSelectionAnchorIndex;
  int selectedBottomTab = 0;
  bool isBottomPanelExpanded = true;

  String? currentProjectPath;

  bool isPlaying = false;
  bool isMetronomeEnabled = false;
  double metronomeVolume = 0.85;
  bool isRecording = false;
  double? recordingStartPos;
  double playheadPosition = 0.0;
  Timer? playTimer;

  Map<String, List<DawClip>> trackClips = {};
  DawClip? selectedClip;
  List<DawClip> multiSelectedClips = [];
  List<MidiNote> selectedMidiNotes = [];
  List<MidiNote> clipboardMidiNotes = [];
  List<Map<String, dynamic>> clipboardClips = [];
  bool isSelecting = false;
  Offset? _lastTimelinePointerDownGlobal;
  Offset? _marqueeStart;
  Offset? _marqueeEnd;
  Set<String> _marqueeBaseTrackIds = {};
  List<DawClip> _marqueeBaseClips = [];

  bool snapToGrid = true;
  double _zoomX = 1.0;
  double _midiZoomMultiplier = 1.0;

  int bpm = 120;
  int timeSigTop = 4;
  int timeSigBottom = 4;

  double get beatWidth => 100.0 * 60.0 / bpm;
  double get snapResolution => beatWidth / 4.0;

  double get _timelineTotalUnits {
    final double barUnits = beatWidth * max(1, timeSigTop);
    double maxUnits = max(6400.0, barUnits * 32.0);
    for (final clips in trackClips.values) {
      for (final c in clips) {
        if (c.start + c.length + 1600.0 > maxUnits) {
          maxUnits = c.start + c.length + 1600.0;
        }
      }
    }
    for (final m in songMarkers) {
      if (m.position + 1600.0 > maxUnits) {
        maxUnits = m.position + 1600.0;
      }
    }
    if (isLooping && loopEnd + 800.0 > maxUnits) {
      maxUnits = loopEnd + 800.0;
    }
    if (playheadPosition + 1600.0 > maxUnits) {
      maxUnits = playheadPosition + 1600.0;
    }
    return maxUnits;
  }

  bool isLooping = false;
  double loopStart = 0.0;
  double loopEnd = 400.0;

  List<SongMarker> songMarkers = [];
  List<TempoMarker> tempoMarkers = [];
  bool _showSampleBrowser = false;
  List<String> _userSampleFolders = [];
  String? _browserPreviewPath;
  SoundHandle? _browserPreviewHandle;
  AudioSource? _browserPreviewSource;
  List<double> _cachedFftBins = const [];
  double masterVolume = 1.0;
  bool masterLimiter = true;
  Bus? auxReverbBus;
  Bus? auxDelayBus;
  double auxReverbMix = 0.85;
  double auxDelayMix = 0.75;

  bool autoScrollPlayhead = true;
  int countInBars = 0; // 0, 1, 2
  bool punchInLoop = false;
  int _countInBeatsLeft = 0;
  Timer? _countInTimer;

  AudioData? _masterAudioData;
  Float32List? _masterVizSamples;
  Timer? _meterTimer;
  final Map<String, (double, double)> _trackLevels = {};
  final Map<String, (double, double)> _trackPeaks = {};
  (double, double) _masterLevel = (0.0, 0.0);
  (double, double) _masterPeak = (0.0, 0.0);
  (double, double) _auxRevLevel = (0.0, 0.0);
  (double, double) _auxDlyLevel = (0.0, 0.0);

  bool isMusicalTypingEnabled = false;
  int _qwertyOctave = 4;
  int _qwertyVelocity = 100;
  final Set<int> _qwertyActiveNotes = {};
  bool _tunerEnabled = false;
  PitchDetectionResult? _detectedPitch;
  final RealtimePitchTracker _tunerTracker = RealtimePitchTracker();
  bool _isBottomPanelMaximized = false;
  double _masterLufs = -60.0;
  double _stereoCorrelation = 1.0;
  final Map<String, double> _sidechainGr = {};

  bool auxReverbSolo = false;
  bool auxDelaySolo = false;
  List<DawEffect> masterEffectsChain = [];
  double masterLufsTarget = -14.0;
  bool _isMasterFxSelected = false;

  String? _referenceTrackPath;
  AudioSource? _referenceSource;
  SoundHandle? _referenceHandle;
  bool _isAuditioningReference = false;
  double _referenceGain = 1.0;

  bool _midiLearnActive = false;
  String? _midiLearnTarget;
  List<MidiCcMapping> midiMappings = [];
  List<DawClip> _activeDragClips = [];
  String? _dragSourceTrackId;
  String? _dragTargetTrackId;
  final GlobalKey _timelineLaneListKey = GlobalKey();

  bool _isSessionView = false;
  final Set<String> _activeSessionClipIds = {};
  final Set<String> _queuedSessionClipIds = {};

  Timer? _arpTimer;
  final Set<int> _heldArpNotes = {};
  int _arpStepIdx = 0;
  int? _lastArpTriggeredPitch;

  late final AudioRecorder _audioRecorder;
  String? _currentRecordPath;
  StreamSubscription<List<int>>? _micStreamSub;
  Process? _parecordProcess;
  bool _usingAudioRecorderCapture = false;
  int _micCaptureGeneration = 0;
  Future<void> _micLifecycleChain = Future<void>.value();
  Uint8List _micRemainderBytes = Uint8List(0);
  WavWriter? _wavWriter;
  final Stopwatch _playStopwatch = Stopwatch();
  int _lastStopwatchMicros = 0;
  final FocusNode _focusNode = FocusNode();
  final FocusNode _bpmFocus = FocusNode();
  final List<DateTime> _tapTimestamps = [];

  final ScrollController _headerScrollController = ScrollController();
  final ScrollController _timelineScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  bool _isSyncingScroll = false;

  final UndoRedoStack<String> _history = UndoRedoStack<String>(maxEntries: 50);

  final MidiCommand _midiCommand = MidiCommand();
  StreamSubscription? _midiSubscription;
  List<MidiDevice> _midiDevices = [];

  List<InputDevice> _inputDevices = [];
  InputDevice? _selectedInputDevice;
  Map<String, int> _inputDeviceChannels = {};
  String _defaultInputChannelId = 'stereo:0';
  int _activeCaptureChannels = 2;

  List<PlaybackDevice> _outputDevices = [];
  List<LinuxAudioSink> _linuxSinks = [];
  String _selectedOutputDeviceKey = 'system_default';
  String? _systemDefaultOutputLabel;
  String? _lastAppliedOutputDeviceName;
  String? _lastRoutedSinkName;
  double _recordingLatencyMs = 35.0;
  double? _recordingFirstChunkPos;
  int _recordingFirstChunkFrames = 0;
  Completer<void>? _micWarmupCompleter;


  final Map<int, List<({SoundHandle handle, int releaseMs})>> _activeMidiNotes =
      {};
  final Map<int, _RecordingNote> _recordingMidiNotes = {};
  static const double kMinTimelineZoom = 0.02;
  static const double kMaxTimelineZoom = 8.0;
  double _bottomPanelHeight = 300.0;

  void _setState(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _audioRecorder = AudioRecorder();
    _initInputDevices();
    _initOutputRouting(applyRoute: true);
    _loadUserSampleFolders();
    _checkAutoSave();
    _initAudioVisualizationAndBuses();
    _headerScrollController.addListener(() {
      if (_isSyncingScroll) return;
      if (_timelineScrollController.hasClients) {
        if (_headerScrollController.position.outOfRange) return;
        _isSyncingScroll = true;
        _timelineScrollController.jumpTo(_headerScrollController.offset);
        _isSyncingScroll = false;
      }
    });
    _timelineScrollController.addListener(() {
      if (_isSyncingScroll) return;
      if (_headerScrollController.hasClients) {
        if (_timelineScrollController.position.outOfRange) return;
        _isSyncingScroll = true;
        _headerScrollController.jumpTo(_timelineScrollController.offset);
        _isSyncingScroll = false;
      }
    });
    windowManager.ensureInitialized();
    _updateMidiDevices();
    int lastStatus = 0;
    _midiSubscription = _midiCommand.onMidiDataReceived?.listen((packet) {
      if (packet.data.isEmpty) return;
      int statusByte = packet.data[0];
      int note = 0;
      int velocity = 0;

      if (statusByte >= 0x80) {
        lastStatus = statusByte;
        if (packet.data.length >= 3) {
          note = packet.data[1];
          velocity = packet.data[2];
        } else {
          return;
        }
      } else {
        if (lastStatus == 0) return;
        if (packet.data.length >= 2) {
          note = packet.data[0];
          velocity = packet.data[1];
        } else {
          return;
        }
      }

      int status = lastStatus & 0xF0;
      if (status == 0xB0) {
        _handleMidiCc(note, velocity, lastStatus & 0x0F);
      } else if (status == 0x90 && velocity > 0) {
        _handleMidiNoteOn(note, velocity, packet.device.id);
      } else if (status == 0x80 || (status == 0x90 && velocity == 0)) {
        _handleMidiNoteOff(note);
      }
    });
  }


  @override
  void dispose() {
    windowManager.removeListener(this);
    _meterTimer?.cancel();
    _countInTimer?.cancel();
    _arpTimer?.cancel();
    try {
      if (_referenceSource != null) {
        SoLoud.instance.disposeSource(_referenceSource!);
      }
      if (_browserPreviewSource != null) {
        SoLoud.instance.disposeSource(_browserPreviewSource!);
      }
      _masterAudioData?.dispose();
    } catch (_) {}
    try {
      auxReverbBus?.dispose();
      auxDelayBus?.dispose();
    } catch (_) {}
    playTimer?.cancel();
    _playStopwatch.stop();
    _parecordProcess?.kill();
    _parecordProcess = null;
    _micStreamSub?.cancel();
    _micStreamSub = null;
    _audioRecorder.dispose();
    _focusNode.dispose();
    _bpmFocus.dispose();
    _headerScrollController.dispose();
    _timelineScrollController.dispose();
    _midiSubscription?.cancel();
    super.dispose();
  }


  @override
  void onWindowFocus() {
    unawaited(_syncLinuxSystemDefaultRoute());
  }

  @override
  void onWindowClose() async {
    await _promptSaveAndExecute(() async {
      await _clearAutoSave();
      await windowManager.destroy();
    });
  }


  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (_bpmFocus.hasFocus) return KeyEventResult.ignored;
        if (FocusManager.instance.primaryFocus?.context?.widget
            is EditableText) {
          return KeyEventResult.ignored;
        }
        if (isMusicalTypingEnabled &&
            !HardwareKeyboard.instance.isControlPressed) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.keyZ) {
              setState(() => _qwertyOctave = max(1, _qwertyOctave - 1));
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.keyX) {
              setState(() => _qwertyOctave = min(7, _qwertyOctave + 1));
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.keyC) {
              setState(() => _qwertyVelocity = max(20, _qwertyVelocity - 15));
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.keyV) {
              setState(() => _qwertyVelocity = min(127, _qwertyVelocity + 15));
              return KeyEventResult.handled;
            }
            final offset = kQwertyNoteOffsets[event.logicalKey];
            if (offset != null) {
              final midi = ((_qwertyOctave + 1) * 12 + offset).clamp(0, 127);
              if (!_qwertyActiveNotes.contains(midi)) {
                setState(() => _qwertyActiveNotes.add(midi));
                _handleMidiNoteOn(midi, _qwertyVelocity, null);
              }
              return KeyEventResult.handled;
            }
          } else if (event is KeyUpEvent) {
            final offset = kQwertyNoteOffsets[event.logicalKey];
            if (offset != null) {
              final midi = ((_qwertyOctave + 1) * 12 + offset).clamp(0, 127);
              setState(() => _qwertyActiveNotes.remove(midi));
              _handleMidiNoteOff(midi);
              return KeyEventResult.handled;
            }
          }
        }
        if (event is KeyDownEvent) {
          if (HardwareKeyboard.instance.isControlPressed) {
            if (HardwareKeyboard.instance.isShiftPressed &&
                event.logicalKey == LogicalKeyboardKey.keyZ) {
              _redo();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.keyZ) {
              _undo();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.keyC) {
              _copy();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.keyV) {
              _paste();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.equal ||
                event.logicalKey == LogicalKeyboardKey.add) {
              _zoomIn();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.minus ||
                event.logicalKey == LogicalKeyboardKey.numpadSubtract) {
              _zoomOut();
              return KeyEventResult.handled;
            }
          }
          if (event.logicalKey == LogicalKeyboardKey.space) {
            bool wasPlayingOrRecording = isPlaying || isRecording;
            if (isRecording) _toggleRecord();
            if (isPlaying) _togglePlay();
            if (!wasPlayingOrRecording) _togglePlay();
            return KeyEventResult.handled;
          } else if (HardwareKeyboard.instance.isControlPressed &&
              event.logicalKey == LogicalKeyboardKey.keyS) {
            _saveProject();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.keyR) {
            _toggleRecord();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            _seekPlayhead(isLooping ? loopStart : 0.0);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.delete ||
              event.logicalKey == LogicalKeyboardKey.backspace) {
            setState(() {
              if (selectedMidiNotes.isNotEmpty && selectedClip is MidiClip) {
                (selectedClip as MidiClip).notes.removeWhere(
                  (n) => selectedMidiNotes.contains(n),
                );
                selectedMidiNotes.clear();
                return;
              }
              List<DawClip> toDelete = [...multiSelectedClips];
              if (selectedClip != null && !toDelete.contains(selectedClip)) {
                toDelete.add(selectedClip!);
              }
              for (var track in tracks) {
                for (var c in toDelete) {
                  if (trackClips[track.id]?.contains(c) == true) {
                    if (c is AudioClip && c.currentHandle != null) {
                      SoLoud.instance.stop(c.currentHandle!);
                    }
                    trackClips[track.id]?.remove(c);
                  }
                }
              }
              selectedClip = null;
              multiSelectedClips.clear();
            });
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        body: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: _isSessionView
                  ? SessionLauncherView(
                      tracks: tracks,
                      trackClips: trackClips,
                      playheadPosition: playheadPosition,
                      isPlaying: isPlaying,
                      activeSessionClipIds: _activeSessionClipIds,
                      queuedSessionClipIds: _queuedSessionClipIds,
                      onTriggerClip: _triggerSessionClip,
                      onTriggerScene: _triggerSessionScene,
                      onStopTrack: _stopSessionTrack,
                      onToggleMute: (t) {
                        _saveState();
                        setState(() => t.isMuted = !t.isMuted);
                        _syncTrackMonitoringHandles();
                      },
                      onToggleSolo: (t) {
                        _saveState();
                        setState(() => t.isSolo = !t.isSolo);
                        _syncTrackMonitoringHandles();
                      },
                      onOpenClipEditor: (t, c) {
                        final idx = tracks.indexOf(t);
                        setState(() {
                          selectedClip = c;
                          if (idx >= 0) selectedTrackIndex = idx;
                          if (c is MidiClip) {
                            selectedBottomTab =
                                t.type == TrackType.sampler ? 3 : 0;
                          } else {
                            selectedBottomTab = 2;
                          }
                          isBottomPanelExpanded = true;
                        });
                      },
                    )
                  : Row(
                      children: [
                        if (_showSampleBrowser)
                          SampleBrowserDrawer(
                            userFolders: _userSampleFolders,
                            previewingPath: _browserPreviewPath,
                            onAddFolderPressed: _addUserSampleFolder,
                            onRemoveFolder: _removeUserSampleFolder,
                            onTogglePreview: _toggleBrowserPreview,
                            onAddToProject: (item) =>
                                _addBrowserItemToTrack(item),
                            onClose: () =>
                                setState(() => _showSampleBrowser = false),
                          ),
                        _buildTrackHeaders(),
                        _buildTimeline(),
                      ],
                    ),
            ),
            if (isMusicalTypingEnabled)
              MusicalKeyboardBar(
                octave: _qwertyOctave,
                velocity: _qwertyVelocity,
                activeNotes: _qwertyActiveNotes,
                onOctaveChanged: (o) =>
                    setState(() => _qwertyOctave = o.clamp(1, 7)),
                onVelocityChanged: (v) =>
                    setState(() => _qwertyVelocity = v.clamp(20, 127)),
                onNoteDown: (midi) {
                  setState(() => _qwertyActiveNotes.add(midi));
                  _handleMidiNoteOn(midi, _qwertyVelocity, null);
                },
                onNoteUp: (midi) {
                  setState(() => _qwertyActiveNotes.remove(midi));
                  _handleMidiNoteOff(midi);
                },
                onClose: () => setState(() => isMusicalTypingEnabled = false),
              ),
            tracks.isNotEmpty ? _buildBottomPanel() : Container(),
          ],
        ),
      ),
    );
  }

  void _copy() {
    if (FocusManager.instance.primaryFocus?.context?.widget is EditableText) {
      return;
    }

    if (selectedMidiNotes.isNotEmpty && selectedClip is MidiClip) {
      clipboardMidiNotes = selectedMidiNotes
          .map((n) => MidiNote.fromJson(n.toJson()))
          .toList();
      clipboardClips.clear();
      return;
    }

    List<DawClip> toCopy = [...multiSelectedClips];
    if (selectedClip != null && !toCopy.contains(selectedClip)) {
      toCopy.add(selectedClip!);
    }
    if (toCopy.isNotEmpty) {
      clipboardClips.clear();
      for (var c in toCopy) {
        String? tId;
        for (var t in tracks) {
          if (trackClips[t.id]?.contains(c) == true) {
            tId = t.id;
            break;
          }
        }
        if (tId != null) {
          clipboardClips.add({'clip': c.toJson(), 'trackId': tId});
        }
      }
      clipboardMidiNotes.clear();
    }
  }

  Future<void> _paste() async {
    if (FocusManager.instance.primaryFocus?.context?.widget is EditableText) {
      return;
    }

    _saveState();

    List<MidiNote> newMidiNotes = [];
    List<DawClip> newDawClips = [];
    List<String> destTrackIds = [];

    if (clipboardMidiNotes.isNotEmpty && selectedClip is MidiClip) {
      double minStart = clipboardMidiNotes.map((n) => n.start).reduce(min);
      double pasteStart = max(0.0, playheadPosition - selectedClip!.start);
      if (pasteStart > selectedClip!.length) pasteStart = selectedClip!.length;
      double offset = pasteStart - minStart;

      for (var n in clipboardMidiNotes) {
        var newNote = MidiNote.fromJson(n.toJson());
        newNote.start += offset;
        if (newNote.start >= 0 && newNote.start < selectedClip!.length) {
          newMidiNotes.add(newNote);
        }
      }
    } else if (clipboardClips.isNotEmpty) {
      double minStart = clipboardClips
          .map((c) => DawClip.fromJson(c['clip']).start)
          .reduce(min);
      double offset = playheadPosition - minStart;

      String? targetTrackId;
      if (selectedTrackIndex != null && selectedTrackIndex! < tracks.length) {
        targetTrackId = tracks[selectedTrackIndex!].id;
      }

      for (var item in clipboardClips) {
        DawClip newClip = DawClip.fromJson(item['clip']);
        String originalTrackId = item['trackId'];

        newClip.id = UniqueKey().toString();
        newClip.start += offset;
        if (newClip.start < 0) newClip.start = 0;

        String destId = originalTrackId;
        if (targetTrackId != null && clipboardClips.length == 1) {
          var targetTrack = tracks.firstWhere((t) => t.id == targetTrackId);
          bool targetIsAudio = targetTrack.type == TrackType.audio;
          bool clipIsAudio = newClip is AudioClip;
          if (targetIsAudio == clipIsAudio) {
            destId = targetTrackId;
          }
        }
        if (newClip is AudioClip && SoLoud.instance.isInitialized) {
          try {
            newClip.source = await SoLoud.instance.loadFile(newClip.filePath);
          } catch (e) {
            debugPrint('Failed to load pasted audio clip: $e');
          }
        }

        newDawClips.add(newClip);
        destTrackIds.add(destId);
      }
    }

    setState(() {
      if (newMidiNotes.isNotEmpty && selectedClip is MidiClip) {
        for (var n in newMidiNotes) {
          (selectedClip as MidiClip).notes.add(n);
        }
        selectedMidiNotes = newMidiNotes;
      } else if (newDawClips.isNotEmpty) {
        multiSelectedClips.clear();
        for (int i = 0; i < newDawClips.length; i++) {
          String destId = destTrackIds[i];
          DawClip newClip = newDawClips[i];
          trackClips[destId] ??= [];
          trackClips[destId]!.add(newClip);
          multiSelectedClips.add(newClip);
        }
        if (multiSelectedClips.isNotEmpty) {
          selectedClip = multiSelectedClips.last;
        }
      }
    });
  }
}
