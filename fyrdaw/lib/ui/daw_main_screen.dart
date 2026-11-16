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
  double? selectionStartDx;
  double? selectionEndDx;

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

  List<String> undoStack = [];
  List<String> redoStack = [];

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

  Future<void> _writeAutoSave() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dawDir = Directory('${dir.path}/SoundBooth');
      if (!dawDir.existsSync()) dawDir.createSync(recursive: true);
      final file = File('${dawDir.path}/autosave.json');
      await file.writeAsString(_getCurrentStateJson());
    } catch (_) {}
  }

  Future<void> _clearAutoSave() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/SoundBooth/autosave.json');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  void _saveState({bool skipAutoSave = false}) {
    undoStack.add(_getCurrentStateJson());
    if (undoStack.length > 50) undoStack.removeAt(0);
    redoStack.clear();
    if (!skipAutoSave) {
      _writeAutoSave();
    }
  }

  void _checkAutoSave() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/SoundBooth/autosave.json');
    if (await file.exists()) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text('Recover Project'),
          content: Text('An unsaved project recovery file was found. Would you like to restore it?'),
          actions: [
            TextButton(
              onPressed: () {
                file.deleteSync();
                Navigator.pop(context);
              },
              child: Text('Discard'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                String state = await file.readAsString();
                await _loadStateJson(state);
              },
              child: Text('Recover'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _promptSaveAndExecute(Future<void> Function() onProceed) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Unsaved Changes'),
        content: Text('You may have unsaved changes. Do you want to save before proceeding?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await onProceed();
            },
            child: Text('Discard', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              bool saved = await _saveProject();
              if (saved) {
                await onProceed();
              }
            },
            child: Text('Save', style: TextStyle(color: lavenderAccent)),
          ),
        ],
      ),
    );
  }

  void _newProject() {
    _promptSaveAndExecute(() async {
      _saveState(skipAutoSave: true);
      setState(() {
        for (var t in tracks) {
          if (t.monitorHandle != null) {
            try {
              if (SoLoud.instance.getIsValidVoiceHandle(t.monitorHandle!)) {
                SoLoud.instance.stop(t.monitorHandle!);
              }
            } catch (_) {}
            t.monitorHandle = null;
          }
          if (t.monitorSource != null) {
            try {
              SoLoud.instance.disposeSource(t.monitorSource!);
            } catch (_) {}
            t.monitorSource = null;
          }
          if (t.bus != null) {
            try {
              t.bus!.dispose();
            } catch (_) {}
          }
        }
        for (var clipList in trackClips.values) {
          for (var c in clipList) {
            if (c is AudioClip && c.source != null) {
              try { SoLoud.instance.disposeSource(c.source!); } catch (_) {}
            }
          }
        }
        tracks.clear();
        trackClips.clear();
        songMarkers.clear();
        tempoMarkers.clear();
        selectedTrackIndex = null;
        selectedClip = null;
        multiSelectedClips.clear();
        currentProjectPath = null;
        bpm = 120;
        timeSigTop = 4;
        timeSigBottom = 4;
      });
      await _clearAutoSave();
    });
  }

  void _undo() async {
    if (undoStack.isNotEmpty) {
      redoStack.add(_getCurrentStateJson());
      await _loadStateJson(undoStack.removeLast());
    }
  }

  void _redo() async {
    if (redoStack.isNotEmpty) {
      undoStack.add(_getCurrentStateJson());
      await _loadStateJson(redoStack.removeLast());
    }
  }

  String _getCurrentStateJson() {
    Map<String, dynamic> projectData = {
      'bpm': bpm,
      'timeSigTop': timeSigTop,
      'timeSigBottom': timeSigBottom,
      'metronomeVolume': metronomeVolume,
      'masterVolume': masterVolume,
      'masterLimiter': masterLimiter,
      'auxReverbMix': auxReverbMix,
      'auxDelayMix': auxDelayMix,
      'markers': songMarkers.map((m) => m.toJson()).toList(),
      'tempoMarkers': tempoMarkers.map((m) => m.toJson()).toList(),
      'tracks': tracks.map((t) => t.toJson()).toList(),
      'trackClips': trackClips.map(
        (k, v) => MapEntry(k, v.map((c) => c.toJson()).toList()),
      ),
    };
    return jsonEncode(projectData);
  }

  Future<void> _loadStateJson(String state) async {
    Map<String, dynamic> projectData = jsonDecode(state);
    
    // Cleanup active Soloud handles before replacing tracks
    for (var t in tracks) {
      if (t.monitorHandle != null) {
        try {
          if (SoLoud.instance.getIsValidVoiceHandle(t.monitorHandle!)) {
            SoLoud.instance.stop(t.monitorHandle!);
          }
        } catch (_) {}
        t.monitorHandle = null;
      }
      if (t.monitorSource != null) {
        try {
          SoLoud.instance.disposeSource(t.monitorSource!);
        } catch (_) {}
        t.monitorSource = null;
      }
      if (t.bus != null) {
        try {
          t.bus!.dispose();
        } catch (_) {}
      }
    }
    for (var clipList in trackClips.values) {
      for (var c in clipList) {
        if (c is AudioClip && c.source != null) {
          try { SoLoud.instance.disposeSource(c.source!); } catch (_) {}
        }
      }
    }

    setState(() {
      bpm = projectData['bpm'] ?? 120;
      timeSigTop = projectData['timeSigTop'] ?? 4;
      timeSigBottom = projectData['timeSigBottom'] ?? 4;
      metronomeVolume =
          (projectData['metronomeVolume'] as num?)?.toDouble() ?? 0.85;
      masterVolume = (projectData['masterVolume'] as num?)?.toDouble() ?? 1.0;
      masterLimiter = projectData['masterLimiter'] ?? true;
      auxReverbMix = (projectData['auxReverbMix'] as num?)?.toDouble() ?? 0.85;
      auxDelayMix = (projectData['auxDelayMix'] as num?)?.toDouble() ?? 0.75;

      songMarkers.clear();
      if (projectData['markers'] != null) {
        for (var m in projectData['markers']) {
          songMarkers.add(SongMarker.fromJson(m));
        }
      }
      tempoMarkers.clear();
      if (projectData['tempoMarkers'] != null) {
        for (var tm in projectData['tempoMarkers']) {
          tempoMarkers.add(TempoMarker.fromJson(tm));
        }
      }

      tracks.clear();
      trackClips.clear();
      for (var t in projectData['tracks']) {
        tracks.add(Track.fromJson(t));
      }
      for (var k in projectData['trackClips'].keys) {
        trackClips[k] = (projectData['trackClips'][k] as List)
            .map((c) => DawClip.fromJson(c))
            .toList();
      }

      if (selectedClip != null) {
        DawClip? found;
        for (var clips in trackClips.values) {
          found = clips.where((c) => c.id == selectedClip!.id).firstOrNull;
          if (found != null) break;
        }
        selectedClip = found;
      }
      List<DawClip> newMulti = [];
      for (var c in multiSelectedClips) {
        for (var clips in trackClips.values) {
          var found = clips.where((x) => x.id == c.id).firstOrNull;
          if (found != null) {
            newMulti.add(found);
            break;
          }
        }
      }
      multiSelectedClips = newMulti;
      if (selectedTrackIndex != null && selectedTrackIndex! >= tracks.length) {
        selectedTrackIndex = tracks.isNotEmpty ? tracks.length - 1 : null;
      }
      if (selectedTrackIndex == null && tracks.isNotEmpty) {
        selectedTrackIndex = 0;
      }
    });

    for (var track in tracks) {
      if (track.type == TrackType.midi) {
        final preset = getInstrumentPreset(track.instrumentIndex);
        track.synthSourcePath = preset.assetPath;
        track.synthSource = globalInstrumentSounds[track.instrumentIndex];
      }
      _updateTrackFilters(track);
      for (var c in trackClips[track.id] ?? []) {
        if (c is AudioClip && SoLoud.instance.isInitialized) {
          try {
            c.source = await SoLoud.instance.loadFile(c.filePath);
          } catch (_) {}
        }
      }
      if (track.type == TrackType.sampler) {
        for (var pad in track.samplerPads.values) {
          if (pad.filePath != null) {
            await pad.loadSample(pad.filePath!);
          }
        }
      }
    }
    await _updateMicState();
  }

  void _updateMidiDevices() async {
    _midiDevices = await _midiCommand.devices ?? [];
    if (_midiDevices.isNotEmpty) {
      for (var d in _midiDevices) {
        if (!(d.name.toLowerCase().contains('through'))) {
          try {
            _midiCommand.connectToDevice(d);
          } catch (e) {
            print("Could not connect to MIDI device ${d.name}: $e");
          }
        }
      }
    }
    setState(() {});
  }

  final Map<int, List<({SoundHandle handle, int releaseMs})>> _activeMidiNotes =
      {};
  final Map<int, _RecordingNote> _recordingMidiNotes = {};

  void _changeInstrument(Track track, int v) async {
    final preset = getInstrumentPreset(v);
    track.synthSourcePath = preset.assetPath;
    track.synthSource = globalInstrumentSounds[v];
    setState(() {
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
                          setState(() => track.midiInputId = null);
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
                            setState(() => track.midiInputId = d.id);
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
      setState(() {
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
      setState(() {
        if (m.trackId == '__master__' && m.param == 'volume') {
          masterVolume = scaled.clamp(0.0, 1.0);
          _syncMasterAndAuxFilters();
          return;
        }
        final track = tracks.where((t) => t.id == m.trackId).firstOrNull;
        if (track == null) return;
        if (m.param == 'volume') {
          track.volume = scaled.clamp(0.0, 1.0);
          _syncTrackMonitoringHandles();
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

  Future<void> _exportAudio() async {
    String? format = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: panelDark,
        title: Text('Export Full Mixdown', style: TextStyle(color: textMain)),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'wav'),
            child: ListTile(
              leading: Icon(Icons.audio_file, color: lavenderAccent),
              title: Text('WAV (16-bit / 44.1 kHz)', style: TextStyle(color: textMain)),
              subtitle: Text('Uncompressed lossless master', style: TextStyle(color: textMuted, fontSize: 11)),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'flac'),
            child: ListTile(
              leading: Icon(Icons.high_quality, color: Colors.cyanAccent),
              title: Text('FLAC (Lossless Compressed)', style: TextStyle(color: textMain)),
              subtitle: Text('Encoded via ffmpeg', style: TextStyle(color: textMuted, fontSize: 11)),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'mp3'),
            child: ListTile(
              leading: Icon(Icons.music_note, color: Colors.amberAccent),
              title: Text('MP3 (320 kbps)', style: TextStyle(color: textMain)),
              subtitle: Text('Ready for sharing', style: TextStyle(color: textMuted, fontSize: 11)),
            ),
          ),
        ],
      ),
    );
    if (format == null) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final wavPath = '${dir.path}/mixdown_$ts.wav';
      final ok = await MixdownRenderer.renderToWav(
        tracks: tracks,
        trackClips: trackClips,
        outWavPath: wavPath,
        bpm: bpm,
        beatWidth: beatWidth,
        masterVolume: masterVolume,
        masterLimiter: masterLimiter,
        auxReverbMix: auxReverbMix,
        auxDelayMix: auxDelayMix,
        auxReverbSolo: auxReverbSolo,
        auxDelaySolo: auxDelaySolo,
        masterEffectsChain: masterEffectsChain,
        tempoMarkers: tempoMarkers,
      );
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Nothing to export — add audio or MIDI clips first!')),
          );
        }
        return;
      }

      String finalPath = wavPath;
      if (format == 'mp3' || format == 'flac') {
        final target = '${dir.path}/mixdown_$ts.$format';
        final args = format == 'mp3'
            ? ['-y', '-i', wavPath, '-b:a', '320k', target]
            : ['-y', '-i', wavPath, target];
        final res = await Process.run('ffmpeg', args);
        if (res.exitCode == 0 && File(target).existsSync()) {
          finalPath = target;
          try {
            File(wavPath).deleteSync();
          } catch (_) {}
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported mixdown to $finalPath'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool> _saveProject() async {
    if (currentProjectPath != null) {
      return await _saveToPath(currentProjectPath!);
    } else {
      return await _saveProjectAs();
    }
  }

  Future<bool> _saveProjectAs() async {
    try {
      List<String> args = [
        '--file-selection',
        '--save',
        '--title=Save Sound Booth Project',
        '--file-filter=*.adaw',
      ];
      final result = await Process.run('zenity', args);
      if (result.exitCode == 0) {
        String path = result.stdout.toString().trim();
        if (path.isEmpty) return false;
        if (!path.endsWith('.adaw')) path += '.adaw';
        currentProjectPath = path;
        return await _saveToPath(path);
      }
      return false;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save error: $e'), backgroundColor: Colors.red),
      );
      return false;
    }
  }

  Future<bool> _saveToPath(String path) async {
    try {
      List<Map<String, dynamic>> tracksJson = tracks.map((t) {
        var j = t.toJson();
        if (j['type'] == TrackType.sampler.index) {
          Map<String, dynamic> newPads = {};
          (j['samplerPads'] as Map).forEach((k, v) {
            Map<String, dynamic> padData = Map<String, dynamic>.from(v);
            if (padData['filePath'] != null &&
                !padData['filePath'].toString().startsWith('assets/')) {
              padData['filePath'] = p.basename(padData['filePath']);
            }
            newPads[k] = padData;
          });
          j['samplerPads'] = newPads;
        }
        return j;
      }).toList();

      Map<String, List<Map<String, dynamic>>> clipsJson = {};
      trackClips.forEach((k, clips) {
        clipsJson[k] = clips.map((c) {
          var j = c.toJson();
          if (c is AudioClip) {
            j['filePath'] = p.basename(c.filePath);
          }
          return j;
        }).toList();
      });

      Map<String, dynamic> projectData = {
        'bpm': bpm,
        'timeSigTop': timeSigTop,
        'timeSigBottom': timeSigBottom,
        'metronomeVolume': metronomeVolume,
        'masterVolume': masterVolume,
        'masterLimiter': masterLimiter,
        'masterLufsTarget': masterLufsTarget,
        'masterEffectsChain':
            masterEffectsChain.map((e) => e.toJson()).toList(),
        'midiMappings': midiMappings.map((m) => m.toJson()).toList(),
        'auxReverbMix': auxReverbMix,
        'auxDelayMix': auxDelayMix,
        'markers': songMarkers.map((m) => m.toJson()).toList(),
        'tempoMarkers': tempoMarkers.map((m) => m.toJson()).toList(),
        'tracks': tracksJson,
        'trackClips': clipsJson,
      };

      String jsonStr = jsonEncode(projectData);

      final archive = Archive();
      final jsonFile = ArchiveFile(
        'project.json',
        jsonStr.length,
        utf8.encode(jsonStr),
      );
      archive.addFile(jsonFile);

      Set<String> addedFiles = {};
      for (var clips in trackClips.values) {
        for (var c in clips) {
          if (c is AudioClip) {
            if (!addedFiles.contains(c.filePath)) {
              final f = File(c.filePath);
              if (f.existsSync()) {
                final bytes = f.readAsBytesSync();
                archive.addFile(
                  ArchiveFile(p.basename(c.filePath), bytes.length, bytes),
                );
                addedFiles.add(c.filePath);
              }
            }
          }
        }
      }
      for (var t in tracks) {
        if (t.type == TrackType.sampler) {
          for (var pad in t.samplerPads.values) {
            if (pad.filePath != null &&
                !pad.filePath!.startsWith('assets/') &&
                !addedFiles.contains(pad.filePath!)) {
              final f = File(pad.filePath!);
              if (f.existsSync()) {
                final bytes = f.readAsBytesSync();
                archive.addFile(
                  ArchiveFile(p.basename(pad.filePath!), bytes.length, bytes),
                );
                addedFiles.add(pad.filePath!);
              }
            }
          }
        }
      }

      final zipData = ZipEncoder().encode(archive);
      await File(path).writeAsBytes(zipData);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Project saved to $path'),
          backgroundColor: Colors.green,
        ),
      );
      return true;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save error: $e'), backgroundColor: Colors.red),
      );
      return false;
    }
  }

  Future<void> _openProject() async {
    try {
      final result = await Process.run('zenity', [
        '--file-selection',
        '--title=Open Project',
        '--file-filter=*.adaw',
      ]);
      if (result.exitCode == 0) {
        String path = result.stdout.toString().trim();
        if (path.isEmpty) return;
        currentProjectPath = path;

        final fileBytes = await File(path).readAsBytes();
        String jsonStr;

        final mediaDir = await getProjectMediaDirectory();

        if (fileBytes.isNotEmpty && fileBytes[0] == '{'.codeUnitAt(0)) {
          jsonStr = utf8.decode(fileBytes);
        } else {
          final archive = ZipDecoder().decodeBytes(fileBytes);
          ArchiveFile? jsonArchiveFile = archive.findFile('project.json');
          if (jsonArchiveFile == null)
            throw Exception("Invalid adaw file: missing project.json");

          jsonStr = utf8.decode(jsonArchiveFile.content as List<int>);

          for (var file in archive) {
            if (file.name != 'project.json' && file.isFile) {
              final outFile = File('${mediaDir.path}/${file.name}');
              outFile.writeAsBytesSync(file.content as List<int>);
            }
          }
        }

        Map<String, dynamic> projectData = jsonDecode(jsonStr);

        setState(() {
          bpm = projectData['bpm'] ?? 120;
          timeSigTop = projectData['timeSigTop'] ?? 4;
          timeSigBottom = projectData['timeSigBottom'] ?? 4;
          metronomeVolume =
              (projectData['metronomeVolume'] as num?)?.toDouble() ?? 0.85;
          masterVolume = (projectData['masterVolume'] as num?)?.toDouble() ?? 1.0;
          masterLimiter = projectData['masterLimiter'] ?? true;
          masterLufsTarget =
              (projectData['masterLufsTarget'] as num?)?.toDouble() ?? -14.0;
          masterEffectsChain.clear();
          if (projectData['masterEffectsChain'] != null) {
            for (final fx in projectData['masterEffectsChain']) {
              masterEffectsChain.add(DawEffect.fromJson(fx));
            }
          }
          midiMappings.clear();
          if (projectData['midiMappings'] != null) {
            for (final m in projectData['midiMappings']) {
              midiMappings.add(MidiCcMapping.fromJson(m));
            }
          }
          auxReverbMix = (projectData['auxReverbMix'] as num?)?.toDouble() ?? 0.85;
          auxDelayMix = (projectData['auxDelayMix'] as num?)?.toDouble() ?? 0.75;

          songMarkers.clear();
          if (projectData['markers'] != null) {
            for (var m in projectData['markers']) {
              songMarkers.add(SongMarker.fromJson(m));
            }
          }
          tempoMarkers.clear();
          if (projectData['tempoMarkers'] != null) {
            for (var tm in projectData['tempoMarkers']) {
              tempoMarkers.add(TempoMarker.fromJson(tm));
            }
          }

          tracks.clear();
          if (projectData['tracks'] != null) {
            for (var t in projectData['tracks']) {
              if (t['type'] == TrackType.sampler.index &&
                  t['samplerPads'] != null) {
                (t['samplerPads'] as Map).forEach((k, v) {
                  if (v['filePath'] != null) {
                    final fp = v['filePath'].toString();
                    if (!fp.startsWith('/') && !fp.startsWith('assets/')) {
                      v['filePath'] = '${mediaDir.path}/$fp';
                    }
                  }
                });
              }
              var track = Track.fromJson(t);
              if (track.type == TrackType.midi) {
                final preset = getInstrumentPreset(track.instrumentIndex);
                track.synthSourcePath = preset.assetPath;
                track.synthSource =
                    globalInstrumentSounds[track.instrumentIndex];
              }
              _updateTrackFilters(track);
              tracks.add(track);
            }
          }

          trackClips.clear();
          if (projectData['trackClips'] != null) {
            Map<String, dynamic> tc = projectData['trackClips'];
            tc.forEach((k, v) {
              trackClips[k] = (v as List).map((c) {
                if (c['filePath'] != null &&
                    !c['filePath'].toString().startsWith('/')) {
                  c['filePath'] = '${mediaDir.path}/${c['filePath']}';
                }
                return DawClip.fromJson(c);
              }).toList();
            });
          }

          playheadPosition = 0;
          selectedClip = null;
          multiSelectedClips.clear();
          if (selectedTrackIndex != null &&
              selectedTrackIndex! >= tracks.length) {
            selectedTrackIndex = tracks.isNotEmpty ? tracks.length - 1 : null;
          }
          if (selectedTrackIndex == null && tracks.isNotEmpty) {
            selectedTrackIndex = 0;
          }
        });

        for (var t in tracks) {
          for (var c in trackClips[t.id] ?? []) {
            if (c is AudioClip && SoLoud.instance.isInitialized) {
              try {
                c.source = await SoLoud.instance.loadFile(c.filePath);
              } catch (_) {}
            }
          }
          if (t.type == TrackType.sampler) {
            for (var pad in t.samplerPads.values) {
              if (pad.filePath != null) {
                await pad.loadSample(pad.filePath!);
              }
            }
          }
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Open error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _openPreferences() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: panelDark,
              title: Text('Preferences', style: TextStyle(color: textMain)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Default Save Location:',
                      style: TextStyle(color: textMuted),
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            defaultSaveLocation.isEmpty
                                ? 'Not Set'
                                : defaultSaveLocation,
                            style: TextStyle(color: textMain, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final result = await Process.run('zenity', [
                              '--file-selection',
                              '--directory',
                              '--title=Select Default Save Directory',
                            ]);
                            if (result.exitCode == 0) {
                              String path = result.stdout.toString().trim();
                              if (path.isNotEmpty) {
                                setModalState(() {
                                  defaultSaveLocation = path;
                                });
                                SharedPreferences prefs =
                                    await SharedPreferences.getInstance();
                                prefs.setString('defaultSaveLocation', path);
                              }
                            }
                          },
                          child: Text(
                            'Browse',
                            style: TextStyle(color: textMain),
                          ),
                        ),
                      ],
                    ),
                    Divider(color: textFaint),
                    Text('Accent Color:', style: TextStyle(color: textMuted)),
                    SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          [
                                Colors.purpleAccent,
                                Colors.blueAccent,
                                Colors.tealAccent,
                                Colors.orangeAccent,
                                Colors.redAccent,
                              ]
                              .map(
                                (color) => GestureDetector(
                                  onTap: () async {
                                    setModalState(() {
                                      lavenderAccent = color;
                                    });
                                    SharedPreferences prefs =
                                        await SharedPreferences.getInstance();
                                    prefs.setInt('lavenderAccent', color.value);
                                    dawAppKey.currentState?.setState(() {});
                                  },
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: color,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: lavenderAccent == color
                                            ? textMain
                                            : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Close', style: TextStyle(color: textMain)),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      setState(() {});
    });
  }

  Future<void> _importAudioTrack() async {
    try {
      final result = await Process.run('zenity', [
        '--file-selection',
        '--title=Import WAV File',
        '--file-filter=*.wav *.mp3 *.flac',
      ]);
      if (result.exitCode == 0) {
        String path = result.stdout.toString().trim();
        if (path.isEmpty) return;

        final trackColor =
            kTrackColorPalette[tracks.length % kTrackColorPalette.length];
        final newTrack = Track(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: path.split('/').last,
          type: TrackType.audio,
          colorValue: trackColor.toARGB32(),
        );

        final src = await SoLoud.instance.loadFile(path);
        final lengthSecs = SoLoud.instance.getLength(src);
        final clip = AudioClip(
          start: playheadPosition,
          length: lengthSecs.inMilliseconds * 100.0 / 1000.0,
          color: newTrack.color,
          filePath: path,
          id: UniqueKey().toString(),
        );
        clip.source = src;

        setState(() {
          tracks.add(newTrack);
          trackClips[newTrack.id] = [clip];
          selectedTrackIndex = tracks.length - 1;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Import error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _exportStems() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final folderPath = '${dir.path}/stems_$timestamp';
      await Directory(folderPath).create();

      bool anyExported = false;
      final bool anySolo = tracks.any((t) => t.isSolo);

      for (var t in tracks) {
        if (t.isMuted) continue;
        if (anySolo && !t.isSolo) continue;
        final safeName = t.name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
        final outPath = '$folderPath/$safeName.wav';
        final ok = await MixdownRenderer.renderToWav(
          tracks: tracks,
          trackClips: trackClips,
          outWavPath: outPath,
          bpm: bpm,
          onlyTrack: t,
          masterVolume: 1.0,
          masterLimiter: false,
          tempoMarkers: tempoMarkers,
        );
        if (ok) anyExported = true;
      }

      if (mounted) {
        if (anyExported) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Stems exported to $folderPath'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No active tracks with clips to export!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export Stems error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _bounceTrackToAudio(Track track) async {
    try {
      final dir = await getProjectMediaDirectory();
      final outPath =
          '${dir.path}/bounce_${track.id}_${DateTime.now().millisecondsSinceEpoch}.wav';
      final ok = await MixdownRenderer.renderToWav(
        tracks: tracks,
        trackClips: trackClips,
        outWavPath: outPath,
        bpm: bpm,
        onlyTrack: track,
        masterVolume: 1.0,
        masterLimiter: false,
        tempoMarkers: tempoMarkers,
      );
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No clips on "${track.name}" to bounce!')),
          );
        }
        return;
      }
      final wav = await decodeWavFile(outPath);
      final clipLen = (wav?.durationSeconds ?? 4.0) * 100.0;
      AudioSource? src;
      if (SoLoud.instance.isInitialized) {
        src = await SoLoud.instance.loadFile(outPath);
      }
      _saveState();
      final bouncedTrack = Track(
        id: 'bounce_${DateTime.now().millisecondsSinceEpoch}',
        name: '${track.name} (Audio)',
        type: TrackType.audio,
        colorValue: track.colorValue,
      );
      final bouncedClip = AudioClip(
        id: UniqueKey().toString(),
        name: '${track.name} Mix',
        start: 0.0,
        length: clipLen,
        color: track.color,
        filePath: outPath,
      )..source = src;
      setState(() {
        tracks.add(bouncedTrack);
        trackClips[bouncedTrack.id] = [bouncedClip];
        selectedTrackIndex = tracks.length - 1;
        selectedClip = bouncedClip;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bounced "${track.name}" to new Audio track'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bounce error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

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
        sharedSrc.filters.pitchShiftFilter.activate();
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

    setState(() {
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

  Future<void> _openTemplates() async {
    final res = await showTemplatesDialog(context);
    if (res == null) return;
    _saveState();
    setState(() {
      for (final t in tracks) {
        try {
          t.bus?.dispose();
        } catch (_) {}
      }
      tracks = res.tracks;
      trackClips = res.trackClips;
      songMarkers = res.markers;
      tempoMarkers.clear();
      bpm = res.bpm;
      playheadPosition = 0.0;
      selectedTrackIndex = tracks.isNotEmpty ? 0 : null;
      selectedClip = tracks.isNotEmpty && (trackClips[tracks.first.id]?.isNotEmpty ?? false)
          ? trackClips[tracks.first.id]!.first
          : null;
      for (final t in tracks) {
        if (t.type == TrackType.midi) {
          t.synthSourcePath = getInstrumentPreset(t.instrumentIndex).assetPath;
          t.synthSource = globalInstrumentSounds[t.instrumentIndex];
        }
        _updateTrackFilters(t);
      }
    });
  }

  void _playMetronomeClick(bool isDownbeat) {
    if (!SoLoud.instance.isInitialized) return;
    final src = isDownbeat
        ? (globalMetronomeAccentSound ?? globalSawSound)
        : (globalMetronomeBeatSound ?? globalSawSound);
    if (src == null) return;
    final vol = MetronomeSynth.computeClickVolume(
      metronomeVolume,
      isDownbeat: isDownbeat,
    );
    if (vol <= 0.005) return;
    try {
      final h = SoLoud.instance.play(src, volume: vol);
      if (src == globalSawSound) {
        SoLoud.instance.setRelativePlaySpeed(h, isDownbeat ? 4.0 : 2.0);
        Timer(const Duration(milliseconds: 45), () {
          if (SoLoud.instance.getIsValidVoiceHandle(h)) {
            SoLoud.instance.stop(h);
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _loadUserSampleFolders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('sb_sample_folders') ?? [];
      final metVol = prefs.getDouble('sb_metronome_volume');
      if (mounted) {
        setState(() {
          _userSampleFolders = saved;
          if (metVol != null) metronomeVolume = metVol.clamp(0.0, 1.5);
        });
      }
    } catch (_) {}
  }

  Future<void> _saveMetronomeVolumePref(double v) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('sb_metronome_volume', v);
    } catch (_) {}
  }

  Future<void> _addUserSampleFolder() async {
    try {
      final res = await Process.run('zenity', [
        '--file-selection',
        '--directory',
        '--title=Select Sample / MIDI Folder',
      ]);
      if (res.exitCode != 0) return;
      final dirPath = res.stdout.toString().trim();
      if (dirPath.isEmpty || _userSampleFolders.contains(dirPath)) return;
      final next = [..._userSampleFolders, dirPath];
      setState(() => _userSampleFolders = next);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('sb_sample_folders', next);
    } catch (_) {}
  }

  Future<void> _removeUserSampleFolder(String folder) async {
    final next = _userSampleFolders.where((f) => f != folder).toList();
    setState(() => _userSampleFolders = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('sb_sample_folders', next);
    } catch (_) {}
  }

  Future<void> _ensureAudioClipProcessed(AudioClip clip) async {
    if (!clip.needsTimeStretchProcessing) {
      if (clip.processedFilePath != null) {
        clip.processedFilePath = null;
        clip.processedCacheKey = null;
        if (SoLoud.instance.isInitialized && File(clip.filePath).existsSync()) {
          try {
            if (clip.source != null) SoLoud.instance.disposeSource(clip.source!);
            clip.source = await SoLoud.instance.loadFile(clip.filePath);
          } catch (_) {}
        }
      }
      return;
    }
    final sig =
        '${clip.filePath}|${clip.pitchSemitones.toStringAsFixed(2)}|${clip.stretchFactor.toStringAsFixed(3)}|${clip.preservePitch}';
    if (clip.processedCacheKey == sig &&
        clip.processedFilePath != null &&
        File(clip.processedFilePath!).existsSync()) {
      return;
    }
    try {
      final dir = await getProjectMediaDirectory();
      final outPath =
          '${dir.path}/ts_${clip.id.hashCode}_${DateTime.now().millisecondsSinceEpoch}.wav';
      final ok = await TimeStretchEngine.processWavFile(
        inputPath: clip.filePath,
        outputPath: outPath,
        stretchFactor: clip.stretchFactor,
        pitchSemitones: clip.pitchSemitones,
        preservePitch: clip.preservePitch,
      );
      if (!ok) return;
      clip.processedFilePath = outPath;
      clip.processedCacheKey = sig;
      if (SoLoud.instance.isInitialized) {
        if (clip.source != null) {
          try {
            SoLoud.instance.disposeSource(clip.source!);
          } catch (_) {}
        }
        clip.source = await SoLoud.instance.loadFile(outPath);
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _toggleBrowserPreview(SampleBrowserItem item) async {
    try {
      if (_browserPreviewHandle != null &&
          SoLoud.instance.isInitialized &&
          SoLoud.instance.getIsValidVoiceHandle(_browserPreviewHandle!)) {
        SoLoud.instance.stop(_browserPreviewHandle!);
      }
    } catch (_) {}
    if (_browserPreviewPath == item.path) {
      setState(() {
        _browserPreviewPath = null;
        _browserPreviewHandle = null;
      });
      return;
    }
    setState(() => _browserPreviewPath = item.path);
    if (!SoLoud.instance.isInitialized) return;
    try {
      if (_browserPreviewSource != null) {
        SoLoud.instance.disposeSource(_browserPreviewSource!);
      }
      _browserPreviewSource = item.isAsset
          ? await SoLoud.instance.loadAsset(item.path)
          : await SoLoud.instance.loadFile(item.path);
      _browserPreviewHandle = SoLoud.instance.play(
        _browserPreviewSource!,
        volume: 0.85,
      );
    } catch (_) {}
  }

  Future<void> _addBrowserItemToTrack(
    SampleBrowserItem item, {
    Track? targetTrack,
    double? startPos,
  }) async {
    final double insertStart = max(
      0.0,
      snapToGrid && startPos != null
          ? (startPos / snapResolution).round() * snapResolution
          : (startPos ?? playheadPosition),
    );
    if (item.isMidi) {
      try {
        final bytes = await File(item.path).readAsBytes();
        final imported = MidiFileCodec.decodeBytes(bytes, beatWidth: beatWidth);
        if (imported.notes.isEmpty) return;
        final double maxEnd = imported.notes
            .map((n) => n.start + n.length)
            .fold(beatWidth * timeSigTop, max);
        Track t;
        if (targetTrack != null &&
            (targetTrack.type == TrackType.midi ||
                targetTrack.type == TrackType.sampler)) {
          t = targetTrack;
        } else {
          t = Track(
            id: UniqueKey().toString(),
            name: imported.trackName,
            type: TrackType.midi,
            colorValue: kTrackColorPalette[tracks.length % kTrackColorPalette.length]
                .toARGB32(),
          );
          if (globalInstrumentSounds.isNotEmpty) {
            t.synthSource = globalInstrumentSounds[t.instrumentIndex];
          }
          tracks.add(t);
        }
        final clip = MidiClip(
          id: UniqueKey().toString(),
          name: p.basenameWithoutExtension(item.name),
          start: insertStart,
          length: max(beatWidth, maxEnd),
          color: t.color,
          notes: imported.notes,
        );
        _saveState();
        setState(() {
          trackClips.putIfAbsent(t.id, () => []).add(clip);
          selectedTrackIndex = tracks.indexOf(t);
          selectedClip = clip;
          selectedBottomTab = 0;
        });
      } catch (_) {}
      return;
    }

    try {
      String resolvedPath = item.path;
      if (item.isAsset) {
        final dir = await getProjectMediaDirectory();
        final dstPath = '${dir.path}/${p.basename(item.path)}';
        final data = await rootBundle.load(item.path);
        await File(dstPath).writeAsBytes(data.buffer.asUint8List(), flush: true);
        resolvedPath = dstPath;
      }
      final wav = await decodeWavFile(resolvedPath);
      final double durUnits = max(beatWidth, (wav?.durationSeconds ?? 2.0) * 100.0);
      Track t;
      if (targetTrack != null && targetTrack.type == TrackType.audio) {
        t = targetTrack;
      } else {
        t = Track(
          id: UniqueKey().toString(),
          name: p.basenameWithoutExtension(item.name),
          type: TrackType.audio,
          colorValue: kTrackColorPalette[tracks.length % kTrackColorPalette.length]
              .toARGB32(),
        );
        tracks.add(t);
      }
      AudioSource? src;
      try {
        if (SoLoud.instance.isInitialized) {
          src = await SoLoud.instance.loadFile(resolvedPath);
        }
      } catch (_) {}
      final clip = AudioClip(
        id: UniqueKey().toString(),
        name: p.basenameWithoutExtension(item.name),
        start: insertStart,
        length: durUnits,
        color: t.color,
        filePath: resolvedPath,
      )..source = src;
      _saveState();
      setState(() {
        trackClips.putIfAbsent(t.id, () => []).add(clip);
        selectedTrackIndex = tracks.indexOf(t);
        selectedClip = clip;
      });
    } catch (e) {
      debugPrint('Add browser item error: $e');
    }
  }

  Future<void> _importMidiFile({Track? targetTrack, double? startPos}) async {
    try {
      final result = await Process.run('zenity', [
        '--file-selection',
        '--title=Import Standard MIDI File (.mid)',
        '--file-filter=MIDI Files (*.mid, *.midi) | *.mid *.midi',
      ]);
      if (result.exitCode != 0) return;
      final path = result.stdout.toString().trim();
      if (path.isEmpty) return;
      await _addBrowserItemToTrack(
        SampleBrowserItem(
          name: p.basename(path),
          path: path,
          isAsset: false,
          isMidi: true,
          category: 'MIDI',
        ),
        targetTrack: targetTrack,
        startPos: startPos,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('MIDI import failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _exportSelectedMidiClip() async {
    if (selectedClip is! MidiClip) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a MIDI clip to export as .mid')),
      );
      return;
    }
    final mc = selectedClip as MidiClip;
    try {
      final result = await Process.run('zenity', [
        '--file-selection',
        '--save',
        '--title=Export MIDI Clip (.mid)',
        '--file-filter=*.mid',
      ]);
      if (result.exitCode != 0) return;
      String path = result.stdout.toString().trim();
      if (path.isEmpty) return;
      if (!path.toLowerCase().endsWith('.mid')) path += '.mid';
      final bytes = MidiFileCodec.encodeNotes(
        mc.notes,
        bpm: bpm.toDouble(),
        timeSigNum: timeSigTop,
        timeSigDen: timeSigBottom,
        beatWidth: beatWidth,
        trackName: mc.name.isNotEmpty ? mc.name : 'Sound Booth MIDI',
      );
      await File(path).writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exported MIDI to $path'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('MIDI export failed: $e'), backgroundColor: Colors.red),
      );
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
                        setState(() {
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

  int _channelCountForDevice(InputDevice? device) => device == null
      ? 2
      : resolveInputDeviceChannelCount(device.id, _inputDeviceChannels);

  List<AudioInputChannelOption> _inputChannelOptionsForSelectedDevice() =>
      buildInputChannelOptions(_channelCountForDevice(_selectedInputDevice));

  AudioInputChannelOption _channelOptionForTrack(Track? track) =>
      resolveInputChannelOption(
        track?.inputChannelId ?? _defaultInputChannelId,
        _channelCountForDevice(_selectedInputDevice),
      );

  AudioInputChannelOption _primaryInputChannelOption() {
    Track? active = tracks
        .where((t) => t.type == TrackType.audio && t.isArmed)
        .firstOrNull;
    active ??= tracks
        .where((t) => t.type == TrackType.audio && t.isMonitoring)
        .firstOrNull;
    if (active == null &&
        selectedTrackIndex != null &&
        selectedTrackIndex! < tracks.length &&
        tracks[selectedTrackIndex!].type == TrackType.audio) {
      active = tracks[selectedTrackIndex!];
    }
    return _channelOptionForTrack(active);
  }

  Future<void> _initOutputRouting({bool applyRoute = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedKey = prefs.getString('sb_output_device') ?? 'system_default';
      final savedLatency = prefs.getDouble('sb_rec_latency_ms') ?? 35.0;

      List<PlaybackDevice> devices = [];
      try {
        if (SoLoud.instance.isInitialized) {
          devices = SoLoud.instance.listPlaybackDevices();
        }
      } catch (_) {}

      String? defSinkName;
      List<LinuxAudioSink> sinks = [];
      if (Platform.isLinux) {
        defSinkName = await LinuxOutputRouter.getDefaultSinkName();
        sinks = await LinuxOutputRouter.listSinks();
      }

      LinuxAudioSink? sysSink;
      if (defSinkName != null) {
        sysSink =
            sinks.where((s) => s.name == defSinkName).firstOrNull ??
            LinuxAudioSink(name: defSinkName, description: defSinkName);
      }

      final defaultPlayDev = matchPlaybackDeviceForSink(devices, sysSink);
      final sysLabel = sysSink?.displayName ?? defaultPlayDev?.name;

      PlaybackDevice? targetPlayDev = defaultPlayDev;
      LinuxAudioSink? targetSink = sysSink;
      if (savedKey.startsWith('dev:')) {
        final wantName = savedKey.substring(4);
        final explicitDev =
            devices.where((d) => d.name == wantName).firstOrNull;
        if (explicitDev != null) {
          targetPlayDev = explicitDev;
          targetSink = matchSinkForPlaybackDevice(sinks, explicitDev) ?? sysSink;
        }
      }

      if (mounted) {
        setState(() {
          _outputDevices = devices;
          _linuxSinks = sinks;
          _selectedOutputDeviceKey = savedKey;
          _systemDefaultOutputLabel = sysLabel;
          _recordingLatencyMs = savedLatency.clamp(0.0, 200.0);
        });
      }

      if (applyRoute) {
        await _applyResolvedOutputRoute(targetPlayDev, targetSink);
      }
    } catch (_) {}
  }

  Future<void> _applyResolvedOutputRoute(
    PlaybackDevice? targetPlayDev,
    LinuxAudioSink? targetSink,
  ) async {
    try {
      if (SoLoud.instance.isInitialized && targetPlayDev != null) {
        if (_lastAppliedOutputDeviceName != targetPlayDev.name) {
          SoLoud.instance.changeDevice(newDevice: targetPlayDev);
          _lastAppliedOutputDeviceName = targetPlayDev.name;
        }
      }
    } catch (_) {}

    if (Platform.isLinux && targetSink != null) {
      _lastRoutedSinkName = targetSink.name;
      await LinuxOutputRouter.routeProcessAudioToSink(
        targetSink.name,
        targetSinkIndex: targetSink.index,
      );
      Future.delayed(const Duration(milliseconds: 140), () {
        if (!mounted) return;
        LinuxOutputRouter.routeProcessAudioToSink(
          targetSink.name,
          targetSinkIndex: targetSink.index,
        );
      });
    }
  }

  Future<void> _selectOutputDevice(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sb_output_device', key);
    } catch (_) {}

    PlaybackDevice? targetPlayDev;
    LinuxAudioSink? targetSink;
    if (key == 'system_default') {
      final defName = Platform.isLinux
          ? await LinuxOutputRouter.getDefaultSinkName()
          : null;
      if (Platform.isLinux) {
        _linuxSinks = await LinuxOutputRouter.listSinks();
      }
      if (defName != null) {
        targetSink =
            _linuxSinks.where((s) => s.name == defName).firstOrNull ??
            LinuxAudioSink(name: defName, description: defName);
      }
      targetPlayDev = matchPlaybackDeviceForSink(_outputDevices, targetSink);
    } else if (key.startsWith('dev:')) {
      final wantName = key.substring(4);
      targetPlayDev =
          _outputDevices.where((d) => d.name == wantName).firstOrNull;
      targetSink = matchSinkForPlaybackDevice(_linuxSinks, targetPlayDev);
    }

    if (mounted) {
      setState(() {
        _selectedOutputDeviceKey = key;
        if (key == 'system_default' && targetSink != null) {
          _systemDefaultOutputLabel = targetSink.displayName;
        }
      });
    }

    _lastAppliedOutputDeviceName = null;
    await _applyResolvedOutputRoute(targetPlayDev, targetSink);
  }

  Future<void> _initInputDevices() async {
    try {
      final rawDevices = await _audioRecorder.listInputDevices();
      final seenIds = <String>{};
      final devices = <InputDevice>[];
      for (final d in rawDevices) {
        final cleanId = normalizeAudioInputDeviceId(d.id);
        final effectiveId = cleanId.isNotEmpty ? cleanId : d.id;
        if (seenIds.add(effectiveId)) {
          devices.add(InputDevice(id: effectiveId, label: d.label));
        }
      }
      Map<String, int> channelMap = {};
      if (Platform.isLinux) {
        try {
          final res = await Process.run('pactl', ['list', 'sources']);
          if (res.exitCode == 0) {
            channelMap = parsePactlSourceChannels(
              res.stdout.toString().split('\n'),
            );
          }
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _inputDevices = devices;
        if (channelMap.isNotEmpty) {
          _inputDeviceChannels = channelMap;
        }
        if (_inputDevices.isNotEmpty) {
          final prevId = _selectedInputDevice != null
              ? normalizeAudioInputDeviceId(_selectedInputDevice!.id)
              : null;
          _selectedInputDevice = _inputDevices
                  .where((d) => d.id == prevId)
                  .firstOrNull ??
              _inputDevices.first;
        } else {
          _selectedInputDevice = null;
        }
      });
    } catch (_) {}
  }

  void _initAudioVisualizationAndBuses() {
    bool soloudAvailable = false;
    try {
      soloudAvailable = SoLoud.instance.isInitialized;
      if (soloudAvailable) {
        SoLoud.instance.setVisualizationEnabled(true);
        _masterAudioData = AudioData(GetSamplesKind.linear);

        auxReverbBus = ensureActiveBus(auxReverbBus, name: 'AuxReverb');
        auxReverbBus!.filters.freeverbFilter.activate();
        auxReverbBus!.filters.freeverbFilter.wet().value = 1.0;
        auxReverbBus!.filters.freeverbFilter.roomSize().value = 0.78;
        auxReverbBus!.filters.freeverbFilter.damp().value = 0.32;

        auxDelayBus = ensureActiveBus(auxDelayBus, name: 'AuxDelay');
        auxDelayBus!.filters.echoFilter.activate();
        auxDelayBus!.filters.echoFilter.wet().value = 1.0;
        auxDelayBus!.filters.echoFilter.delay().value = 0.34;
        auxDelayBus!.filters.echoFilter.decay().value = 0.45;
        auxDelayBus!.filters.echoFilter.filter().value = 0.4;

        _syncMasterAndAuxFilters();
      }
    } catch (e) {
      debugPrint('Aux/Viz init error: $e');
      return;
    }
    if (!soloudAvailable) return;

    bool busHasActiveVoices(Bus? b) {
      if (b == null) return false;
      try {
        return b.getActiveVoiceCount() > 0;
      } catch (_) {
        return false;
      }
    }

    _meterTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      try {
        if (!mounted || !SoLoud.instance.isInitialized) return;
      } catch (_) {
        return;
      }
      final bool activeAudio =
          isPlaying ||
          tracks.any((t) => t.isMonitoring || busHasActiveVoices(t.bus)) ||
          busHasActiveVoices(auxReverbBus) ||
          busHasActiveVoices(auxDelayBus) ||
          _activeMidiNotes.isNotEmpty;

      try {
        if (_masterAudioData != null && activeAudio) {
          _masterAudioData!.updateSamples();
          _masterVizSamples = _masterAudioData!.getAudioData(
            alwaysReturnData: false,
          );
          _cachedFftBins = ParametricEqDsp.computeFftBinsFromSamples(
            _masterVizSamples,
          );
        } else if (!activeAudio && _masterVizSamples != null) {
          // Decay spectrum gracefully when stopped
          bool nonZero = false;
          for (int i = 0; i < _masterVizSamples!.length; i++) {
            _masterVizSamples![i] *= 0.75;
            if (_masterVizSamples![i].abs() > 0.005) nonZero = true;
          }
          if (!nonZero) {
            _masterVizSamples = null;
            _cachedFftBins = const [];
          } else {
            _cachedFftBins = ParametricEqDsp.computeFftBinsFromSamples(
              _masterVizSamples,
            );
          }
        }
      } catch (_) {}

      double decay(double prev, double cur) =>
          cur > prev ? cur : (prev * 0.88).clamp(0.0, 1.0);
      double peakDecay(double prev, double cur) =>
          cur > prev ? cur : (prev - 0.012).clamp(0.0, 1.0);

      bool anyMeterActive = activeAudio || _masterVizSamples != null;
      final Map<String, (double, double)> rawTrackAmps = {};

      // Measure individual non-group tracks first so Group buses can aggregate them.
      for (final t in tracks) {
        if (t.type == TrackType.group) continue;
        double rawL = 0.0;
        double rawR = 0.0;
        if (t.bus != null &&
            !t.isMuted &&
            (activeAudio || busHasActiveVoices(t.bus))) {
          try {
            enableBusVisualization(t.bus!);
            rawL = t.bus!.getChannelVolume(0);
            rawR = t.bus!.getChannelVolume(1);
          } catch (_) {}
        }
        rawTrackAmps[t.id] = (rawL, rawR);

        final double l = linearAmpToDbMeter(rawL);
        final double r = linearAmpToDbMeter(rawR);
        final prev = _trackLevels[t.id] ?? (0.0, 0.0);
        final nextL = decay(prev.$1, l);
        final nextR = decay(prev.$2, r);
        _trackLevels[t.id] = (nextL, nextR);

        final prevP = _trackPeaks[t.id] ?? (0.0, 0.0);
        final nextPL = peakDecay(prevP.$1, nextL);
        final nextPR = peakDecay(prevP.$2, nextR);
        _trackPeaks[t.id] = (nextPL, nextPR);

        if (prev.$1 > 0.001 ||
            prev.$2 > 0.001 ||
            prevP.$1 > 0.001 ||
            prevP.$2 > 0.001 ||
            nextL > 0.001 ||
            nextR > 0.001) {
          anyMeterActive = true;
        }
      }

      // Group bus tracks aggregate amplitudes from their unmuted member tracks.
      for (final g in tracks) {
        if (g.type != TrackType.group) continue;
        double rawL = 0.0;
        double rawR = 0.0;
        if (!g.isMuted) {
          if (g.bus != null && (activeAudio || busHasActiveVoices(g.bus))) {
            try {
              enableBusVisualization(g.bus!);
              rawL += g.bus!.getChannelVolume(0);
              rawR += g.bus!.getChannelVolume(1);
            } catch (_) {}
          }
          for (final child in tracks) {
            if (child.groupTrackId == g.id &&
                child.type != TrackType.group &&
                !child.isMuted) {
              final childRaw = rawTrackAmps[child.id];
              if (childRaw != null) {
                rawL += childRaw.$1 * g.volume;
                rawR += childRaw.$2 * g.volume;
              }
            }
          }
        }
        final double l = linearAmpToDbMeter(rawL);
        final double r = linearAmpToDbMeter(rawR);
        final prev = _trackLevels[g.id] ?? (0.0, 0.0);
        final nextL = decay(prev.$1, l);
        final nextR = decay(prev.$2, r);
        _trackLevels[g.id] = (nextL, nextR);

        final prevP = _trackPeaks[g.id] ?? (0.0, 0.0);
        final nextPL = peakDecay(prevP.$1, nextL);
        final nextPR = peakDecay(prevP.$2, nextR);
        _trackPeaks[g.id] = (nextPL, nextPR);

        if (prev.$1 > 0.001 ||
            prev.$2 > 0.001 ||
            prevP.$1 > 0.001 ||
            prevP.$2 > 0.001 ||
            nextL > 0.001 ||
            nextR > 0.001) {
          anyMeterActive = true;
        }
      }

      double mL = 0.0, mR = 0.0;
      double revL = 0.0, revR = 0.0;
      double dlyL = 0.0, dlyR = 0.0;
      try {
        if (activeAudio) {
          mL = linearAmpToDbMeter(SoLoud.instance.getApproximateVolume(0));
          mR = linearAmpToDbMeter(SoLoud.instance.getApproximateVolume(1));
          if (auxReverbBus != null) {
            enableBusVisualization(auxReverbBus!);
            revL = linearAmpToDbMeter(auxReverbBus!.getChannelVolume(0));
            revR = linearAmpToDbMeter(auxReverbBus!.getChannelVolume(1));
          }
          if (auxDelayBus != null) {
            enableBusVisualization(auxDelayBus!);
            dlyL = linearAmpToDbMeter(auxDelayBus!.getChannelVolume(0));
            dlyR = linearAmpToDbMeter(auxDelayBus!.getChannelVolume(1));
          }
        }
      } catch (_) {}

      final prevMaster = _masterLevel;
      final prevMasterPeak = _masterPeak;
      _masterLevel = (decay(_masterLevel.$1, mL), decay(_masterLevel.$2, mR));
      _masterPeak = (
        peakDecay(_masterPeak.$1, _masterLevel.$1),
        peakDecay(_masterPeak.$2, _masterLevel.$2),
      );
      final prevRev = _auxRevLevel;
      final prevDly = _auxDlyLevel;
      _auxRevLevel = (decay(_auxRevLevel.$1, revL), decay(_auxRevLevel.$2, revR));
      _auxDlyLevel = (decay(_auxDlyLevel.$1, dlyL), decay(_auxDlyLevel.$2, dlyR));

      if (prevMaster.$1 > 0.001 ||
          prevMaster.$2 > 0.001 ||
          prevMasterPeak.$1 > 0.001 ||
          prevMasterPeak.$2 > 0.001 ||
          _masterLevel.$1 > 0.001 ||
          _masterLevel.$2 > 0.001 ||
          prevRev.$1 > 0.001 ||
          prevRev.$2 > 0.001 ||
          prevDly.$1 > 0.001 ||
          prevDly.$2 > 0.001) {
        anyMeterActive = true;
      }

      _masterLufs = activeAudio
          ? estimateLufsFromWaveform(_masterVizSamples)
          : -60.0;
      final targetCorr = activeAudio
          ? (1.0 - (mL - mR).abs() * 1.4).clamp(-1.0, 1.0)
          : 1.0;
      _stereoCorrelation = _stereoCorrelation * 0.8 + targetCorr * 0.2;

      for (final track in tracks) {
        final compFx = track.effectsChain
            .where(
              (f) =>
                  !f.isBypassed &&
                  f.name == 'Compressor' &&
                  f.sidechainTrackId != null,
            )
            .firstOrNull;
        if (compFx == null) {
          _sidechainGr.remove(track.id);
          continue;
        }
        final scLvl = _trackLevels[compFx.sidechainTrackId];
        final trig = scLvl == null ? 0.0 : max(scLvl.$1, scLvl.$2);
        final thresh = compFx.parameters['Thresh'] ?? 0.5;
        final ratio = compFx.parameters['Ratio'] ?? 0.4;
        final drive = (trig - (1.0 - thresh) * 0.45).clamp(0.0, 1.0);
        final gr = (drive * (0.35 + ratio * 0.65) * 1.35).clamp(0.0, 0.9);
        final prevGr = _sidechainGr[track.id] ?? 0.0;
        final smoothedGr = gr > prevGr ? gr : prevGr * 0.82;
        _sidechainGr[track.id] = smoothedGr;

        final scGain = (1.0 - smoothedGr).clamp(0.08, 1.0);
        for (final c in trackClips[track.id] ?? const <DawClip>[]) {
          if (c is AudioClip &&
              c.currentHandle != null &&
              SoLoud.instance.getIsValidVoiceHandle(c.currentHandle!)) {
            final baseEnv = _computeClipEnvelope(c, playheadPosition);
            try {
              SoLoud.instance.setVolume(
                c.currentHandle!,
                (track.volume * baseEnv * scGain).clamp(0.0, 2.5),
              );
            } catch (_) {}
          }
        }
        for (final h in track.activeMidiHandles) {
          if (SoLoud.instance.getIsValidVoiceHandle(h)) {
            try {
              SoLoud.instance.setVolume(
                h,
                (track.volume * scGain).clamp(0.0, 1.5),
              );
            } catch (_) {}
          }
        }
      }

      if (anyMeterActive) {
        setState(() {});
      }
    });
  }

  bool get _isSoloudReady {
    try {
      return SoLoud.instance.isInitialized;
    } catch (_) {
      return false;
    }
  }

  Track? _groupForTrack(Track t) {
    if (t.groupTrackId == null) return null;
    return tracks
        .where((g) => g.id == t.groupTrackId && g.type == TrackType.group)
        .firstOrNull;
  }

  double _effectiveTrackVolume(Track t) {
    final g = _groupForTrack(t);
    return (t.volume * (g?.volume ?? 1.0)).clamp(0.0, 1.5);
  }

  bool _isTrackAudible(Track t, bool anySolo) {
    if (_isAuditioningReference) return false;
    final g = _groupForTrack(t);
    if (t.isMuted || (g != null && g.isMuted)) return false;
    if (anySolo && !t.isSolo && (g == null || !g.isSolo)) return false;
    if (auxReverbSolo || auxDelaySolo) return false;
    return true;
  }

  Future<void> _loadReferenceTrack() async {
    try {
      final result = await Process.run('zenity', [
        '--file-selection',
        '--title=Load Reference Track',
        '--file-filter=*.wav *.mp3 *.flac *.ogg',
      ]);
      if (result.exitCode != 0) return;
      final path = result.stdout.toString().trim();
      if (path.isEmpty) return;
      double offsetGain = 1.0;
      if (path.toLowerCase().endsWith('.wav')) {
        final refLufs = await estimateWavIntegratedLufs(path);
        final dbDiff = masterLufsTarget - refLufs;
        offsetGain = pow(10.0, dbDiff.clamp(-18.0, 12.0) / 20.0).toDouble();
      }
      if (_referenceSource != null && _isSoloudReady) {
        try {
          SoLoud.instance.disposeSource(_referenceSource!);
        } catch (_) {}
      }
      AudioSource? src;
      if (_isSoloudReady) {
        src = await SoLoud.instance.loadFile(path);
      }
      setState(() {
        _referenceTrackPath = path;
        _referenceSource = src;
        _referenceGain = offsetGain;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Loaded reference: ${p.basename(path)}')),
        );
      }
    } catch (e) {
      debugPrint('Reference load error: $e');
    }
  }

  void _toggleReferenceAB() {
    if (_referenceTrackPath == null) {
      _loadReferenceTrack();
      return;
    }
    setState(() {
      _isAuditioningReference = !_isAuditioningReference;
    });
    if (_isSoloudReady) {
      try {
        if (_isAuditioningReference && _referenceSource != null && isPlaying) {
          _referenceHandle = SoLoud.instance.play(
            _referenceSource!,
            volume: (_referenceGain * masterVolume).clamp(0.0, 1.5),
            paused: true,
          );
          final seekMs = ((playheadPosition / 100.0) * 1000.0).round();
          if (seekMs > 0) {
            SoLoud.instance.seek(_referenceHandle!, Duration(milliseconds: seekMs));
          }
          SoLoud.instance.setPause(_referenceHandle!, false);
        } else if (_referenceHandle != null) {
          if (SoLoud.instance.getIsValidVoiceHandle(_referenceHandle!)) {
            SoLoud.instance.stop(_referenceHandle!);
          }
          _referenceHandle = null;
        }
      } catch (_) {}
    }
    _syncMasterAndAuxFilters();
  }

  void _syncMasterAndAuxFilters() {
    if (!_isSoloudReady) return;
    try {
      SoLoud.instance.setGlobalVolume(masterVolume.clamp(0.0, 1.5));
      final filters = SoLoud.instance.filters;
      final lim = filters.limiterFilter;
      final activeMasterFx =
          masterEffectsChain.where((f) => !f.isBypassed).toList();
      final masterLimFx = activeMasterFx
          .where((f) => f.name == 'Compressor')
          .firstOrNull;
      final masterEqFx =
          activeMasterFx.where((f) => f.name == 'EQ').firstOrNull;

      if (masterLimiter || masterLimFx != null) {
        if (!lim.isActive) lim.activate();
        lim.wet.value = 1.0;
        lim.threshold.value = masterLimFx != null
            ? -((masterLimFx.parameters['Thresh'] ?? 0.5) * 12.0 + 1.0)
            : -1.0;
      } else if (lim.isActive) {
        lim.deactivate();
      }
      if (masterEqFx != null) {
        if (!filters.biquadResonantFilter.isActive) {
          filters.biquadResonantFilter.activate();
        }
        final high = masterEqFx.parameters['High'] ?? 0.5;
        filters.biquadResonantFilter.frequency.value =
            (2500.0 + high * 14000.0).clamp(1500.0, 18000.0);
        filters.biquadResonantFilter.wet.value = 0.6;
      } else if (filters.biquadResonantFilter.isActive) {
        filters.biquadResonantFilter.deactivate();
      }

      final bool anyAuxSolo = auxReverbSolo || auxDelaySolo;
      final double revVol = _isAuditioningReference
          ? 0.0
          : (anyAuxSolo && !auxReverbSolo ? 0.0 : auxReverbMix.clamp(0.0, 1.5));
      final double dlyVol = _isAuditioningReference
          ? 0.0
          : (anyAuxSolo && !auxDelaySolo ? 0.0 : auxDelayMix.clamp(0.0, 1.5));

      if (auxReverbBus?.soundHandle != null) {
        SoLoud.instance.setVolume(auxReverbBus!.soundHandle!, revVol);
      }
      if (auxDelayBus?.soundHandle != null) {
        SoLoud.instance.setVolume(auxDelayBus!.soundHandle!, dlyVol);
      }
    } catch (_) {}
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

  Future<void> _syncLinuxSystemDefaultRoute() async {
    if (!Platform.isLinux || _selectedOutputDeviceKey != 'system_default') {
      return;
    }
    try {
      final defSink = await LinuxOutputRouter.getDefaultSinkName();
      if (!mounted || defSink == null) return;
      if (defSink != _lastRoutedSinkName) {
        await _initOutputRouting(applyRoute: true);
      } else {
        final sink = _linuxSinks.where((s) => s.name == defSink).firstOrNull;
        await LinuxOutputRouter.routeProcessAudioToSink(
          defSink,
          targetSinkIndex: sink?.index,
        );
      }
    } catch (_) {}
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

  double _getEffectiveEffectParam(
    Track track,
    DawEffect fx,
    String paramName,
    double fallback,
    double? atPlayhead,
  ) {
    final baseVal = fx.parameters[paramName] ?? fallback;
    if (atPlayhead == null) return baseVal.clamp(0.0, 1.0);
    final autoVal = track.getInterpolatedAutomation(
      '${fx.name}_$paramName',
      atPlayhead,
    );
    return (autoVal >= 0.0 ? autoVal : baseVal).clamp(0.0, 1.0);
  }

  void _updateTrackFilters(Track track, {double? atPlayhead}) {
    if (!_isSoloudReady) return;
    track.bus = ensureActiveBus(track.bus);
    final filters = track.bus!.filters;
    final activeFx = track.effectsChain.where((f) => !f.isBypassed).toList();

    final hasReverb = activeFx.any((f) => f.name == 'Reverb');
    final hasCompressor = activeFx.any(
      (f) => f.name == 'Compressor' || f.name == 'GuitarAmp',
    );
    final hasEq = activeFx.any(
      (f) =>
          f.name == 'EQ' ||
          f.name == 'Overdrive' ||
          f.name == 'TubeScreamer' ||
          f.name == 'GuitarAmp',
    );
    final hasWaveShaper = activeFx.any(
      (f) =>
          f.name == 'Overdrive' ||
          f.name == 'TubeScreamer' ||
          f.name == 'GuitarAmp',
    );
    final cutoffAuto = atPlayhead != null
        ? track.getInterpolatedAutomation('Synth Cutoff', atPlayhead)
        : -1.0;
    final resoAuto = atPlayhead != null
        ? track.getInterpolatedAutomation('Synth Reso', atPlayhead)
        : -1.0;
    final effCutoff = cutoffAuto >= 0.0
        ? cutoffAuto.clamp(0.0, 1.0)
        : track.synthSettings.filterCutoff;
    final effReso = resoAuto >= 0.0
        ? resoAuto.clamp(0.0, 1.0)
        : track.synthSettings.filterResonance;
    final hasSynthFilter = track.type == TrackType.midi &&
        (effCutoff < 0.99 || cutoffAuto >= 0.0 || resoAuto >= 0.0);
    final hasBiquad =
        hasSynthFilter ||
        activeFx.any(
          (f) =>
              f.name == 'Overdrive' ||
              f.name == 'TubeScreamer' ||
              f.name == 'GuitarAmp',
        );
    final hasLimiter = activeFx.any(
      (f) =>
          f.name == 'Overdrive' ||
          f.name == 'TubeScreamer' ||
          f.name == 'GuitarAmp',
    );
    final hasEcho = activeFx.any((f) => f.name == 'Echo');
    final hasFlanger = activeFx.any(
      (f) => f.name == 'Flanger' || f.name == 'Chorus',
    );
    final hasLofi = activeFx.any((f) => f.name == 'Lofi');
    final hasRobotize = activeFx.any((f) => f.name == 'Robotize');
    final hasBassBoost = activeFx.any((f) => f.name == 'BassBoost');

    void setFilterActive(dynamic filter, bool active) {
      try {
        if (active && !filter.isActive) {
          filter.activate();
        } else if (!active && filter.isActive) {
          filter.deactivate();
        }
      } catch (_) {}
    }

    setFilterActive(filters.freeverbFilter, hasReverb);
    setFilterActive(filters.compressorFilter, hasCompressor);
    setFilterActive(filters.parametricEqFilter, hasEq);
    setFilterActive(filters.waveShaperFilter, hasWaveShaper);
    setFilterActive(filters.biquadFilter, hasBiquad);
    setFilterActive(filters.limiterFilter, hasLimiter);
    setFilterActive(filters.echoFilter, hasEcho);
    setFilterActive(filters.flangerFilter, hasFlanger);
    setFilterActive(filters.lofiFilter, hasLofi);
    setFilterActive(filters.robotizeFilter, hasRobotize);
    setFilterActive(filters.bassBoostFilter, hasBassBoost);

    DawEffect? odFx;
    DawEffect? ampFx;
    DawEffect? eqFx;
    for (final fx in activeFx) {
      if (fx.name == 'Overdrive' || fx.name == 'TubeScreamer') odFx = fx;
      if (fx.name == 'GuitarAmp') ampFx = fx;
      if (fx.name == 'EQ') eqFx = fx;
    }

    // 1. Realistic Overdrive (TS-style asymmetric diode clipper) & GuitarAmp (Tube Preamp + Power Amp Sag + 4x12 Cab)
    if (odFx != null || ampFx != null) {
      try {
        final double odDrive = odFx != null
            ? _getEffectiveEffectParam(track, odFx, 'Drive', 0.5, atPlayhead)
            : 0.0;
        final double odTone = odFx != null
            ? _getEffectiveEffectParam(track, odFx, 'Tone', 0.5, atPlayhead)
            : 0.5;
        final double odLevel = odFx != null
            ? _getEffectiveEffectParam(track, odFx, 'Level', 0.5, atPlayhead)
            : 0.5;

        final double ampDrive = ampFx != null
            ? _getEffectiveEffectParam(track, ampFx, 'Drive', 0.7, atPlayhead)
            : 0.0;
        final double ampTone = ampFx != null
            ? _getEffectiveEffectParam(track, ampFx, 'Tone', 0.6, atPlayhead)
            : 0.6;
        final double ampLevel = ampFx != null
            ? _getEffectiveEffectParam(track, ampFx, 'Level', 0.5, atPlayhead)
            : 0.5;

        double wsAmount;
        double wsWet;
        double lpfCutoff;
        double lpfResonance;

        if (odFx != null && ampFx != null) {
          // Stacked Overdrive into GuitarAmp
          final double combinedDrive =
              (1.0 - (1.0 - odDrive * 0.85) * (1.0 - ampDrive * 0.92)).clamp(
                0.0,
                1.0,
              );
          wsAmount =
              (0.58 + 0.412 * (1.0 - pow(1.0 - combinedDrive, 2.5))).clamp(
                0.0,
                0.992,
              );
          wsWet = (0.93 + 0.07 * combinedDrive).clamp(0.0, 1.0);
          final double blendedTone = (0.55 * odTone + 0.45 * ampTone).clamp(
            0.0,
            1.0,
          );
          lpfCutoff = (1400.0 + blendedTone * 2800.0).clamp(1100.0, 4400.0);
          lpfResonance = (1.20 + 0.55 * odDrive).clamp(0.7, 2.2);
        } else if (odFx != null) {
          // Standalone Overdrive
          wsAmount = (0.35 + 0.635 * (1.0 - pow(1.0 - odDrive, 2.2))).clamp(
            0.0,
            0.99,
          );
          wsWet = (0.85 + 0.15 * odDrive).clamp(0.0, 1.0);
          lpfCutoff = (900.0 * pow(4.8, odTone)).clamp(800.0, 4800.0);
          lpfResonance = (0.90 + 0.55 * odDrive + 0.30 * odTone).clamp(
            0.5,
            2.2,
          );
        } else {
          // Standalone GuitarAmp
          wsAmount = (0.52 + 0.468 * (1.0 - pow(1.0 - ampDrive, 2.4))).clamp(
            0.0,
            0.992,
          );
          wsWet = (0.92 + 0.08 * ampDrive).clamp(0.0, 1.0);
          lpfCutoff = (1650.0 + ampTone * 2550.0).clamp(1200.0, 4500.0);
          lpfResonance = 1.30;
        }

        filters.waveShaperFilter.amount().value = wsAmount;
        filters.waveShaperFilter.wet().value = wsWet;

        filters.biquadFilter.type().value = 0; // Lowpass
        filters.biquadFilter.frequency().value = lpfCutoff;
        filters.biquadFilter.resonance().value = lpfResonance;
        filters.biquadFilter.wet().value = 1.0;

        // Output peak limiter so high drive never digitally clips
        filters.limiterFilter.threshold().value = -1.5;
        filters.limiterFilter.outputCeiling().value = -0.5;
        filters.limiterFilter.releaseTime().value = 40.0;
        filters.limiterFilter.wet().value = 1.0;

        // If no dedicated EQ pedal is overriding parametricEqFilter, use 5-band EQ
        // to model the TS808 720 Hz mid-hump + bass tightener and/or 4x12 cabinet voicings
        if (eqFx == null) {
          filters.parametricEqFilter.numBands().value = 5;
          filters.parametricEqFilter.wet().value = 1.0;
          if (odFx != null && ampFx != null) {
            final double gain =
                (0.45 + 1.15 * odLevel) * (0.55 + 1.05 * ampLevel);
            filters.parametricEqFilter.bandGain(0).value = (0.35 * gain).clamp(
              0.05,
              4.0,
            ); // 30 Hz sub cut
            filters.parametricEqFilter.bandGain(1).value = (1.15 * gain).clamp(
              0.05,
              4.0,
            ); // 144 Hz cab punch
            filters.parametricEqFilter.bandGain(2).value =
                ((1.55 + 0.85 * odDrive) * gain).clamp(
                  0.05,
                  4.0,
                ); // 693 Hz OD mid-hump
            filters.parametricEqFilter.bandGain(3).value =
                ((0.95 + 0.65 * (0.5 * odTone + 0.5 * ampTone)) * gain).clamp(
                  0.05,
                  4.0,
                ); // 3330 Hz bite
            filters.parametricEqFilter.bandGain(4).value = (0.18 * gain).clamp(
              0.05,
              4.0,
            ); // 16 kHz cab roll-off
          } else if (odFx != null) {
            final double gain = 0.35 + 1.45 * odLevel;
            filters.parametricEqFilter.bandGain(0).value = (0.35 * gain).clamp(
              0.05,
              4.0,
            ); // 30 Hz tight bass cut
            filters.parametricEqFilter.bandGain(1).value = (0.85 * gain).clamp(
              0.05,
              4.0,
            ); // 144 Hz low-mid
            filters.parametricEqFilter.bandGain(2).value =
                ((1.35 + 0.85 * odDrive) * gain).clamp(
                  0.05,
                  4.0,
                ); // 693 Hz signature mid hump
            filters.parametricEqFilter.bandGain(3).value =
                ((0.75 + 0.75 * odTone) * gain).clamp(
                  0.05,
                  4.0,
                ); // 3330 Hz active tone
            filters.parametricEqFilter.bandGain(4).value =
                ((0.22 + 0.30 * odTone) * gain).clamp(
                  0.05,
                  4.0,
                ); // 16 kHz fizz rolloff
          } else if (ampFx != null) {
            final double gain = 0.40 + 1.40 * ampLevel;
            filters.parametricEqFilter.bandGain(0).value = (0.45 * gain).clamp(
              0.05,
              4.0,
            );
            filters.parametricEqFilter.bandGain(1).value = (1.35 * gain).clamp(
              0.05,
              4.0,
            ); // 4x12 low resonance
            filters.parametricEqFilter.bandGain(2).value =
                ((0.95 + 0.45 * ampTone) * gain).clamp(0.05, 4.0);
            filters.parametricEqFilter.bandGain(3).value =
                ((1.10 + 0.65 * ampTone) * gain).clamp(0.05, 4.0);
            filters.parametricEqFilter.bandGain(4).value = (0.18 * gain).clamp(
              0.05,
              4.0,
            );
          }
        }

        // GuitarAmp power-tube sag & compression (unless overridden by standalone Compressor)
        if (ampFx != null &&
            !activeFx.any((f) => f.name == 'Compressor')) {
          filters.compressorFilter.wet().value = 1.0;
          filters.compressorFilter.threshold().value =
              (-14.0 - ampDrive * 18.0).clamp(-45.0, -5.0);
          filters.compressorFilter.ratio().value = (3.0 + ampDrive * 4.5).clamp(
            1.0,
            10.0,
          );
          filters.compressorFilter.makeupGain().value =
              ((ampLevel - 0.5) * 16.0 + ampDrive * 3.5).clamp(-20.0, 24.0);
          filters.compressorFilter.kneeWidth().value = 8.0;
          filters.compressorFilter.attackTime().value = 8.0;
          filters.compressorFilter.releaseTime().value = 110.0;
        }
      } catch (_) {}
    }

    // 2. Remaining effects in chain
    for (var fx in activeFx) {
      try {
        if (fx.name == 'Reverb') {
          final mix = _getEffectiveEffectParam(
            track,
            fx,
            'Mix',
            0.5,
            atPlayhead,
          );
          final size = _getEffectiveEffectParam(
            track,
            fx,
            'Size',
            0.5,
            atPlayhead,
          );
          final decay = _getEffectiveEffectParam(
            track,
            fx,
            'Decay',
            0.5,
            atPlayhead,
          );
          filters.freeverbFilter.wet().value = mix.clamp(0.0, 1.0);
          filters.freeverbFilter.roomSize().value =
              (0.25 + size * 0.50 + decay * 0.23).clamp(0.1, 0.98);
          // In Freeverb, lower damp = less high-frequency absorption = longer reverb decay
          filters.freeverbFilter.damp().value = (0.85 - decay * 0.75).clamp(
            0.05,
            0.95,
          );
          filters.freeverbFilter.width().value = 1.0;
        } else if (fx.name == 'Compressor') {
          final mix = _getEffectiveEffectParam(
            track,
            fx,
            'Mix',
            1.0,
            atPlayhead,
          );
          final thresh = _getEffectiveEffectParam(
            track,
            fx,
            'Thresh',
            0.5,
            atPlayhead,
          );
          final ratio = _getEffectiveEffectParam(
            track,
            fx,
            'Ratio',
            0.5,
            atPlayhead,
          );
          final gain = _getEffectiveEffectParam(
            track,
            fx,
            'Gain',
            0.5,
            atPlayhead,
          );
          filters.compressorFilter.wet().value = mix.clamp(0.0, 1.0);
          filters.compressorFilter.threshold().value =
              (-4.0 - thresh * 46.0).clamp(-60.0, 0.0);
          filters.compressorFilter.ratio().value = (1.0 + ratio * 9.0).clamp(
            1.0,
            10.0,
          );
          filters.compressorFilter.makeupGain().value =
              ((gain - 0.5) * 24.0).clamp(-24.0, 24.0);
          filters.compressorFilter.kneeWidth().value = 6.0;
          filters.compressorFilter.attackTime().value = 10.0;
          filters.compressorFilter.releaseTime().value = 100.0;
        } else if (fx.name == 'EQ') {
          final low = _getEffectiveEffectParam(
            track,
            fx,
            'Low',
            0.5,
            atPlayhead,
          );
          final mid = _getEffectiveEffectParam(
            track,
            fx,
            'Mid',
            0.5,
            atPlayhead,
          );
          final high = _getEffectiveEffectParam(
            track,
            fx,
            'High',
            0.5,
            atPlayhead,
          );
          double mapEqGain(double v) => v <= 0.5
              ? (0.12 + (v / 0.5) * 0.88)
              : (1.0 + ((v - 0.5) / 0.5) * 2.5);
          filters.parametricEqFilter.wet().value = 1.0;
          filters.parametricEqFilter.numBands().value = 3;
          filters.parametricEqFilter.bandGain(0).value = mapEqGain(
            low,
          ).clamp(0.05, 4.0);
          filters.parametricEqFilter.bandGain(1).value = mapEqGain(
            mid,
          ).clamp(0.05, 4.0);
          filters.parametricEqFilter.bandGain(2).value = mapEqGain(
            high,
          ).clamp(0.05, 4.0);
        } else if (fx.name == 'Echo') {
          final mix = _getEffectiveEffectParam(
            track,
            fx,
            'Mix',
            0.5,
            atPlayhead,
          );
          final delay = _getEffectiveEffectParam(
            track,
            fx,
            'Delay',
            0.3,
            atPlayhead,
          );
          final decay = _getEffectiveEffectParam(
            track,
            fx,
            'Decay',
            0.5,
            atPlayhead,
          );
          filters.echoFilter.wet().value = mix.clamp(0.0, 1.0);
          filters.echoFilter.delay().value = (0.04 + delay * 0.96).clamp(
            0.01,
            2.0,
          );
          filters.echoFilter.decay().value = (0.10 + decay * 0.80).clamp(
            0.01,
            0.95,
          );
          filters.echoFilter.filter().value = 0.35;
        } else if (fx.name == 'Flanger') {
          final mix = _getEffectiveEffectParam(
            track,
            fx,
            'Mix',
            0.5,
            atPlayhead,
          );
          final delay = _getEffectiveEffectParam(
            track,
            fx,
            'Delay',
            0.5,
            atPlayhead,
          );
          final rate = _getEffectiveEffectParam(
            track,
            fx,
            'Rate',
            0.2,
            atPlayhead,
          );
          filters.flangerFilter.wet().value = mix.clamp(0.0, 1.0);
          filters.flangerFilter.delay().value = (0.001 + delay * 0.009).clamp(
            0.001,
            0.02,
          );
          filters.flangerFilter.freq().value = (0.08 + rate * 3.5).clamp(
            0.05,
            10.0,
          );
        } else if (fx.name == 'Chorus') {
          final mix = _getEffectiveEffectParam(
            track,
            fx,
            'Mix',
            0.5,
            atPlayhead,
          );
          final depth = _getEffectiveEffectParam(
            track,
            fx,
            'Depth',
            0.6,
            atPlayhead,
          );
          final rate = _getEffectiveEffectParam(
            track,
            fx,
            'Rate',
            0.4,
            atPlayhead,
          );
          filters.flangerFilter.wet().value = mix.clamp(0.0, 1.0);
          filters.flangerFilter.delay().value = (0.015 + depth * 0.020).clamp(
            0.005,
            0.05,
          );
          filters.flangerFilter.freq().value = (0.15 + rate * 2.2).clamp(
            0.05,
            10.0,
          );
        } else if (fx.name == 'Lofi') {
          final mix = _getEffectiveEffectParam(
            track,
            fx,
            'Mix',
            1.0,
            atPlayhead,
          );
          final rate = _getEffectiveEffectParam(
            track,
            fx,
            'Rate',
            0.2,
            atPlayhead,
          );
          final bits = _getEffectiveEffectParam(
            track,
            fx,
            'Bits',
            0.3,
            atPlayhead,
          );
          filters.lofiFilter.wet().value = mix.clamp(0.0, 1.0);
          filters.lofiFilter.samplerate().value =
              (1200.0 + rate * 14000.0).clamp(500.0, 22000.0);
          filters.lofiFilter.bitdepth().value = (2.0 + bits * 12.0).clamp(
            1.0,
            16.0,
          );
        } else if (fx.name == 'Robotize') {
          final mix = _getEffectiveEffectParam(
            track,
            fx,
            'Mix',
            1.0,
            atPlayhead,
          );
          final freq = _getEffectiveEffectParam(
            track,
            fx,
            'Freq',
            0.3,
            atPlayhead,
          );
          filters.robotizeFilter.wet().value = mix.clamp(0.0, 1.0);
          filters.robotizeFilter.frequency().value =
              (15.0 + freq * 80.0).clamp(1.0, 100.0);
        } else if (fx.name == 'BassBoost') {
          final mix = _getEffectiveEffectParam(
            track,
            fx,
            'Mix',
            1.0,
            atPlayhead,
          );
          final boost = _getEffectiveEffectParam(
            track,
            fx,
            'Boost',
            0.5,
            atPlayhead,
          );
          filters.bassBoostFilter.wet().value = mix.clamp(0.0, 1.0);
          filters.bassBoostFilter.boost().value = (boost * 8.0).clamp(
            0.0,
            10.0,
          );
        }
      } catch (e) {
        debugPrint('Error updating filter: $e');
      }
    }

    if (hasSynthFilter &&
        !activeFx.any(
          (f) =>
              f.name == 'Overdrive' ||
              f.name == 'TubeScreamer' ||
              f.name == 'GuitarAmp',
        )) {
      try {
        final hz = 120.0 * pow(140.0, effCutoff.clamp(0.0, 1.0)).toDouble();
        filters.biquadFilter.type().value = 0; // Lowpass
        filters.biquadFilter.frequency().value = hz.clamp(100.0, 18000.0);
        filters.biquadFilter.resonance().value =
            (0.7 + effReso * 4.5).clamp(0.5, 6.0);
        filters.biquadFilter.wet().value = 1.0;
      } catch (_) {}
    }
  }

  void _zoomIn() => setState(() => _zoomX = min(5.0, _zoomX + 0.2));
  void _zoomOut() => setState(() => _zoomX = max(0.2, _zoomX - 0.2));

  void _changeTempo(int newBpm) {
    if (newBpm == bpm) return;
    double ratio = bpm / newBpm;
    setState(() {
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
    final env = _computeClipEnvelope(clip, atPlayhead, track: track);
    final trackEffVol = _effectiveTrackVolume(track);
    final effVol = (trackEffVol * env).clamp(0.0, 2.5);
    final revVol = ((track.reverbPreFader ? env : effVol) * track.reverbSend)
        .clamp(0.0, 2.5);
    final dlyVol = ((track.delayPreFader ? env : effVol) * track.delaySend)
        .clamp(0.0, 2.5);
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
          : effVol,
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
    setState(() => _recordingLatencyMs = clamped);
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
          if (pad.currentHandle != null &&
              SoLoud.instance.getIsValidVoiceHandle(pad.currentHandle!)) {
            SoLoud.instance.stop(pad.currentHandle!);
          }
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

  void _triggerVoicesAtPosition(double pos) {
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
    setState(() {
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

    setState(() {
      isPlaying = !isPlaying;
      if (isPlaying) {
        _triggerVoicesAtPosition(playheadPosition);

        // Fire Beat 1 metronome click immediately when starting on a beat boundary
        if (isMetronomeEnabled && _isSoloudReady && _countInBeatsLeft == 0) {
          final double bw = max(1.0, beatWidth);
          final double rem = playheadPosition % bw;
          if (rem < 1.0 || (bw - rem) < 1.0) {
            final curMeter = TempoMarker.effectiveMeterAt(
              playheadPosition,
              tempoMarkers,
              timeSigTop,
              timeSigBottom,
            );
            final int beatIdx = (playheadPosition / bw).round();
            final bool isDownbeat = beatIdx % max(1, curMeter.numerator) == 0;
            _playMetronomeClick(isDownbeat);
          }
        }

        _playStopwatch
          ..reset()
          ..start();
        _lastStopwatchMicros = 0;

        playTimer = Timer.periodic(const Duration(milliseconds: 10), (timer) {
          final int nowMicros = _playStopwatch.elapsedMicroseconds;
          final double dtSec = (nowMicros - _lastStopwatchMicros) / 1000000.0;
          _lastStopwatchMicros = nowMicros;
          if (dtSec <= 0) return;

          setState(() {
            double oldPos = playheadPosition;
            final double curBpm = TempoMarker.effectiveBpmAt(
              playheadPosition,
              tempoMarkers,
              bpm.toDouble(),
            );
            playheadPosition += dtSec * 100.0 * (curBpm / max(20, bpm));

            // Punch-in / Punch-out auto stop when leaving loopEnd
            if (isRecording &&
                punchInLoop &&
                isLooping &&
                playheadPosition >= loopEnd) {
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
            if (isMetronomeEnabled && _isSoloudReady) {
              int oldBeat = (oldPos / beatWidth).floor();
              int newBeat = (playheadPosition / beatWidth).floor();
              if (newBeat > oldBeat) {
                bool isDownbeat = newBeat % max(1, curMeter.numerator) == 0;
                _playMetronomeClick(isDownbeat);
              }
            }

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

              // Keep audio clip fade/gain/automation envelopes live
              for (var c in trackClips[track.id] ?? []) {
                if (c is AudioClip &&
                    c.currentHandle != null &&
                    SoLoud.instance.getIsValidVoiceHandle(c.currentHandle!)) {
                  final env = _computeClipEnvelope(c, playheadPosition, track: track);
                  final trackEffVol = _effectiveTrackVolume(track);
                  final effVol = (trackEffVol * env).clamp(0.0, 2.5);
                  final dryPlayVol =
                      (_isAuditioningReference || auxReverbSolo || auxDelaySolo)
                          ? 0.0
                          : effVol;
                  final revVol =
                      ((track.reverbPreFader ? env : effVol) * track.reverbSend)
                          .clamp(0.0, 2.5);
                  final dlyVol =
                      ((track.delayPreFader ? env : effVol) * track.delaySend)
                          .clamp(0.0, 2.5);
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
                if (clip.start + clip.length >= oldPos &&
                    clip.start + clip.length < playheadPosition) {
                  if (clip is AudioClip) {
                    _stopAudioClipHandles(clip);
                  }
                }

                if (clip.start >= oldPos && clip.start < playheadPosition) {
                  if (clip is AudioClip && clip.source != null) {
                    if (clip.currentHandle == null ||
                        !SoLoud.instance.getIsValidVoiceHandle(
                          clip.currentHandle!,
                        )) {
                      _playAudioClipWithSends(track, clip, playheadPosition);
                    }
                  }
                }

                if (clip is MidiClip && _isSoloudReady) {
                  double localOld = oldPos - clip.start + clip.startOffset;
                  double localNew =
                      playheadPosition - clip.start + clip.startOffset;
                  double maxLocal = clip.startOffset + clip.length;
                  if (localNew > maxLocal) localNew = maxLocal;
                  if (localNew >= 0 && localOld <= maxLocal) {
                    final playNotes = (track.type == TrackType.midi &&
                            track.arpSettings.enabled)
                        ? track.arpSettings.expandNotes(clip.notes, beatWidth)
                        : clip.notes;
                    for (var note in playNotes) {
                      if (note.start >= localOld && note.start < localNew) {
                        if (track.type == TrackType.sampler) {
                          var pad = track.samplerPads.values
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
                            if (track.reverbSend > 0.01 &&
                                auxReverbBus != null) {
                              pad.play(
                                note.velocity.toDouble(),
                                auxReverbBus,
                                track.volume * track.reverbSend,
                                track.pan,
                              );
                            }
                            if (track.delaySend > 0.01 &&
                                auxDelayBus != null) {
                              pad.play(
                                note.velocity.toDouble(),
                                auxDelayBus,
                                track.volume * track.delaySend,
                                track.pan,
                              );
                            }
                          }
                        } else {
                          track.activeMidiHandles.removeWhere(
                            (h) => !SoLoud.instance.getIsValidVoiceHandle(h),
                          );
                          final preset = getInstrumentPreset(
                            track.instrumentIndex,
                          );
                          final handle = triggerInstrumentNote(
                            track,
                            note.pitch,
                            note.velocity,
                          );
                          SoundHandle? revHandle;
                          SoundHandle? dlyHandle;
                          if (track.reverbSend > 0.01 &&
                              auxReverbBus != null) {
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
                              (note.length / beatWidth * (60.0 / bpm) * 1000)
                                  .round(),
                              50,
                            );
                            Timer(Duration(milliseconds: noteMs), () {
                              releaseInstrumentNote(
                                handle,
                                releaseMs: preset.releaseMs,
                              );
                              if (revHandle != null) {
                                releaseInstrumentNote(
                                  revHandle,
                                  releaseMs: preset.releaseMs,
                                );
                              }
                              if (dlyHandle != null) {
                                releaseInstrumentNote(
                                  dlyHandle,
                                  releaseMs: preset.releaseMs,
                                );
                              }
                            });
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
            if (isLooping && playheadPosition >= loopEnd) {
              _stopAllActivePlaybackVoices();
              playheadPosition = loopStart;
              _triggerVoicesAtPosition(loopStart);
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

  void _syncTrackMonitoringHandles() {
    if (!SoLoud.instance.isInitialized) return;
    final bool anySolo = tracks.any((t) => t.isSolo);
    for (final t in tracks) {
      if (t.type != TrackType.audio) continue;
      if (t.isMonitoring) {
        t.bus = ensureActiveBus(t.bus);
        if (t.monitorSource == null) {
          try {
            t.monitorSource = SoLoud.instance.setBufferStream(
              maxBufferSizeBytes: 1024 * 64,
              bufferingType: BufferingType.released,
              bufferingTimeNeeds: 0.0,
              sampleRate: 44100,
              channels: Channels.stereo,
              format: BufferType.f32le,
            );
            _updateTrackFilters(t);
          } catch (e) {
            debugPrint('Failed to create monitor stream: $e');
          }
        }
        if (t.monitorSource != null) {
          final double effVol =
              (t.isMuted || (anySolo && !t.isSolo)) ? 0.0 : t.volume;
          if (t.monitorHandle == null ||
              !SoLoud.instance.getIsValidVoiceHandle(t.monitorHandle!)) {
            try {
              t.monitorHandle = t.bus!.play(
                t.monitorSource!,
                volume: effVol,
                pan: t.pan.clamp(-1.0, 1.0),
              );
            } catch (_) {}
          } else {
            try {
              SoLoud.instance.setVolume(t.monitorHandle!, effVol);
              SoLoud.instance.setPan(
                t.monitorHandle!,
                t.pan.clamp(-1.0, 1.0),
              );
              if (SoLoud.instance.getPause(t.monitorHandle!)) {
                SoLoud.instance.setPause(t.monitorHandle!, false);
              }
            } catch (_) {}
          }
        }
      } else {
        if (t.monitorHandle != null) {
          try {
            if (SoLoud.instance.getIsValidVoiceHandle(t.monitorHandle!)) {
              SoLoud.instance.stop(t.monitorHandle!);
            }
          } catch (_) {}
          t.monitorHandle = null;
        }
        if (t.monitorSource != null) {
          try {
            SoLoud.instance.disposeSource(t.monitorSource!);
          } catch (_) {}
          t.monitorSource = null;
        }
      }
    }
  }

  ({Uint8List pcmBytes, Float32List floatSamples}) _processStereoPcmWithGate(
    Uint8List stereoBytes,
    double gateThreshold,
  ) {
    final int numSamples = stereoBytes.length >> 1;
    final ByteData bdIn = ByteData.sublistView(stereoBytes);
    final Float32List floatSamples = Float32List(numSamples);
    double peak = 0.0;
    for (int i = 0; i < numSamples; i++) {
      final s = bdIn.getInt16(i << 1, Endian.little) * (1.0 / 32768.0);
      floatSamples[i] = s;
      final a = s.abs();
      if (a > peak) peak = a;
    }

    Uint8List outBytes = stereoBytes;
    if (gateThreshold > 0.001 && peak < gateThreshold) {
      final attenuated = Uint8List(stereoBytes.length);
      final bdOut = ByteData.sublistView(attenuated);
      for (int i = 0; i < numSamples; i++) {
        floatSamples[i] *= 0.02;
        bdOut.setInt16(
          i << 1,
          (floatSamples[i] * 32767.0).round().clamp(-32768, 32767),
          Endian.little,
        );
      }
      outBytes = attenuated;
    }
    return (pcmBytes: outBytes, floatSamples: floatSamples);
  }

  void _onMicPcmChunk(List<int> rawChunk) {
    if (_micWarmupCompleter != null && !_micWarmupCompleter!.isCompleted) {
      _micWarmupCompleter!.complete();
    }
    if (rawChunk.isEmpty) return;

    final int capCh = _activeCaptureChannels.clamp(1, 32);
    final aligned = alignPcm16Frames(
      rawChunk,
      _micRemainderBytes,
      captureChannels: capCh,
    );
    _micRemainderBytes = aligned.nextRemainder;
    if (aligned.alignedFrames.isEmpty) return;

    final Map<String, ({Uint8List pcmBytes, Float32List floatSamples})>
        mappedCache = {};

    ({Uint8List pcmBytes, Float32List floatSamples}) getProcessed(
      AudioInputChannelOption opt,
      double gateThreshold,
    ) {
      final key = '${opt.id}|${gateThreshold.toStringAsFixed(4)}';
      return mappedCache.putIfAbsent(key, () {
        final stereo = mapAlignedPcm16ToStereo(
          aligned.alignedFrames,
          captureChannels: capCh,
          selection: opt,
        );
        return _processStereoPcmWithGate(stereo, gateThreshold);
      });
    }

    final primaryOpt = _primaryInputChannelOption();
    double activeGate = 0.0;
    for (final t in tracks) {
      if (t.type == TrackType.audio && (t.isArmed || t.isMonitoring)) {
        if (activeGate == 0.0 ||
            (t.noiseGateThreshold > 0.0 && t.noiseGateThreshold < activeGate)) {
          activeGate = t.noiseGateThreshold;
        }
      }
    }
    if (activeGate == 0.0 &&
        selectedTrackIndex != null &&
        selectedTrackIndex! < tracks.length) {
      activeGate = tracks[selectedTrackIndex!].noiseGateThreshold;
    }

    // Feed real-time pitch detector with the UN-GATED selected input channel
    // so cranking the Noise Gate never blinds the tuner.
    if (_tunerEnabled) {
      final tunerFloat = getProcessed(primaryOpt, 0.0).floatSamples;
      final monoSamples = Float64List(tunerFloat.length >> 1);
      for (int i = 0, j = 0; i + 1 < tunerFloat.length; i += 2, j++) {
        monoSamples[j] = (tunerFloat[i] + tunerFloat[i + 1]) * 0.5;
      }
      if (_tunerTracker.addSamples(monoSamples)) {
        final nextPitch = _tunerTracker.current;
        if (mounted) {
          setState(() => _detectedPitch = nextPitch);
        } else {
          _detectedPitch = nextPitch;
        }
      }
    }

    if (isRecording && _wavWriter != null) {
      final armedTrack = tracks
          .where((t) => t.type == TrackType.audio && t.isArmed)
          .firstOrNull;
      final recOpt = armedTrack != null
          ? _channelOptionForTrack(armedTrack)
          : primaryOpt;
      final recGate = armedTrack?.noiseGateThreshold ?? activeGate;
      final recBytes = getProcessed(recOpt, recGate).pcmBytes;
      if (_recordingFirstChunkPos == null && recBytes.isNotEmpty) {
        _recordingFirstChunkPos = playheadPosition;
        _recordingFirstChunkFrames = recBytes.length >> 2;
      }
      _wavWriter!.write(recBytes);
    }

    if (!SoLoud.instance.isInitialized) return;
    final bool anyMonitoring = tracks.any(
      (t) => t.type == TrackType.audio && t.isMonitoring,
    );
    if (!anyMonitoring) return;

    final bool anySolo = tracks.any((t) => t.isSolo);
    for (final t in tracks) {
      if (t.type != TrackType.audio || !t.isMonitoring) continue;
      if (t.monitorSource == null) {
        _syncTrackMonitoringHandles();
      }
      final src = t.monitorSource;
      if (src == null) continue;
      try {
        final trackProcessed = getProcessed(
          _channelOptionForTrack(t),
          t.noiseGateThreshold,
        );
        final Uint8List floatBytes =
            trackProcessed.floatSamples.buffer.asUint8List();
        // Bound buffered monitoring audio to < 18ms (6350 bytes of stereo f32le at 44.1kHz)
        // so live monitoring stays ultra-low-latency and never accumulates lag
        final int bufferedBytes = SoLoud.instance.getBufferSize(src);
        if (bufferedBytes > 6350) {
          SoLoud.instance.resetBufferStream(src);
        }
        SoLoud.instance.addAudioDataStream(src, floatBytes);

        final double effVol =
            (t.isMuted || (anySolo && !t.isSolo)) ? 0.0 : t.volume;
        if (t.monitorHandle == null ||
            !SoLoud.instance.getIsValidVoiceHandle(t.monitorHandle!)) {
          t.bus = ensureActiveBus(t.bus);
          t.monitorHandle = t.bus!.play(
            src,
            volume: effVol,
            pan: t.pan.clamp(-1.0, 1.0),
          );
        } else if (SoLoud.instance.getPause(t.monitorHandle!)) {
          SoLoud.instance.setPause(t.monitorHandle!, false);
        }
      } catch (_) {}
    }
  }

  Future<void> _runSerializedMicOp(Future<void> Function() action) {
    final next = _micLifecycleChain.then((_) => action(), onError: (_) => action());
    _micLifecycleChain = next.catchError((_) {});
    return next;
  }

  Future<void> _stopMicCaptureInternal() async {
    _micCaptureGeneration++;
    // Terminate parecord before cancelling stdout so a stalled child process
    // (e.g. disconnected/busy PipeWire node) cannot block stream cancellation.
    final proc = _parecordProcess;
    _parecordProcess = null;
    if (proc != null) {
      try {
        proc.kill(ProcessSignal.sigterm);
      } catch (_) {}
    }

    final sub = _micStreamSub;
    _micStreamSub = null;
    if (sub != null) {
      try {
        await sub.cancel().timeout(
          const Duration(milliseconds: 250),
          onTimeout: () {},
        );
      } catch (_) {}
    }

    final wasRecorder = _usingAudioRecorderCapture;
    _usingAudioRecorderCapture = false;
    if (wasRecorder) {
      try {
        await _audioRecorder.stop().timeout(
          const Duration(milliseconds: 250),
          onTimeout: () => null,
        );
      } catch (_) {}
    }
    _micRemainderBytes = Uint8List(0);
  }

  void _selectTrackInputChannel(Track? track, String channelId) {
    _saveState();
    setState(() {
      _defaultInputChannelId = channelId;
      if (track != null) {
        track.inputChannelId = channelId;
      }
      _tunerTracker.reset();
      _detectedPitch = null;
    });
  }

  Future<void> _restartMicCapture() => _runSerializedMicOp(() async {
    await _stopMicCaptureInternal();
    if (_tunerEnabled) {
      _tunerTracker.reset();
      if (mounted) setState(() => _detectedPitch = null);
    }
    await _updateMicStateInternal();
  });

  Future<void> _updateMicState({bool forceMic = false}) =>
      _runSerializedMicOp(() => _updateMicStateInternal(forceMic: forceMic));

  Future<void> _updateMicStateInternal({bool forceMic = false}) async {
    final bool wantsRecord =
        isRecording &&
        tracks.any((t) => t.type == TrackType.audio && t.isArmed);
    final bool wantsMonitor = tracks.any(
      (t) => t.type == TrackType.audio && t.isMonitoring,
    );
    final bool needsMic = forceMic || wantsRecord || wantsMonitor || _tunerEnabled;

    _syncTrackMonitoringHandles();

    final int desiredChannels = _channelCountForDevice(_selectedInputDevice).clamp(1, 32);

    if (needsMic &&
        _micStreamSub != null &&
        _activeCaptureChannels != desiredChannels) {
      await _stopMicCaptureInternal();
    }

    if (needsMic && _micStreamSub == null) {
      _micRemainderBytes = Uint8List(0);
      final String cleanDeviceId = _selectedInputDevice != null
          ? normalizeAudioInputDeviceId(_selectedInputDevice!.id)
          : '';
      final int gen = ++_micCaptureGeneration;
      bool startedLowLatencyLinux = false;
      if (Platform.isLinux) {
        try {
          _activeCaptureChannels = desiredChannels;
          final args = <String>[
            '--raw',
            '--format=s16le',
            '--rate=44100',
            '--channels=$_activeCaptureChannels',
            '--latency-msec=5',
            '--process-time-msec=2',
            if (cleanDeviceId.isNotEmpty) '--device=$cleanDeviceId',
          ];
          final proc = await Process.start('parecord', args);
          if (_micCaptureGeneration != gen || !mounted) {
            try {
              proc.kill(ProcessSignal.sigterm);
            } catch (_) {}
            return;
          }
          // Continuously drain stderr so PulseAudio/PipeWire diagnostics never
          // fill the pipe buffer and stall parecord.
          proc.stderr.drain<void>().then((_) {}, onError: (_) {});
          _parecordProcess = proc;
          _usingAudioRecorderCapture = false;
          _micStreamSub = proc.stdout.listen(
            _onMicPcmChunk,
            onDone: () {
              if (_micCaptureGeneration == gen) {
                _micStreamSub = null;
                _parecordProcess = null;
              }
            },
            onError: (_) {
              if (_micCaptureGeneration == gen) {
                _micStreamSub = null;
                _parecordProcess = null;
              }
            },
          );
          startedLowLatencyLinux = true;
        } catch (e) {
          debugPrint('Low-latency parecord fallback to AudioRecorder: $e');
          _parecordProcess = null;
        }
      }

      if (!startedLowLatencyLinux) {
        bool hasPerm = await _audioRecorder.hasPermission();
        if (!hasPerm || _micCaptureGeneration != gen || !mounted) return;
        _activeCaptureChannels = desiredChannels.clamp(1, 2);
        final InputDevice? cleanDevice = _selectedInputDevice == null
            ? null
            : InputDevice(
                id: cleanDeviceId.isNotEmpty
                    ? cleanDeviceId
                    : _selectedInputDevice!.id,
                label: _selectedInputDevice!.label,
              );
        final stream = await _audioRecorder.startStream(
          RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            device: cleanDevice,
            sampleRate: 44100,
            numChannels: _activeCaptureChannels,
          ),
        );
        if (_micCaptureGeneration != gen || !mounted) {
          try {
            await _audioRecorder.stop().timeout(
              const Duration(milliseconds: 250),
              onTimeout: () => null,
            );
          } catch (_) {}
          return;
        }
        _usingAudioRecorderCapture = true;
        _micStreamSub = stream.listen(
          _onMicPcmChunk,
          onDone: () {
            if (_micCaptureGeneration == gen) {
              _micStreamSub = null;
              _usingAudioRecorderCapture = false;
            }
          },
          onError: (_) {
            if (_micCaptureGeneration == gen) {
              _micStreamSub = null;
              _usingAudioRecorderCapture = false;
            }
          },
        );
      }
    } else if (!needsMic && _micStreamSub != null) {
      await _stopMicCaptureInternal();
    }
  }

  Future<void> _toggleRecord() async {
    if (isRecording) {
      double finalPlayhead = playheadPosition;
      setState(() => isRecording = false);
      if (_wavWriter != null) {
        _wavWriter!.close();
        _wavWriter = null;
      }
      await _updateMicState();

      if (_currentRecordPath != null && recordingStartPos != null) {
        final file = File(_currentRecordPath!);
        if (file.existsSync() && file.lengthSync() < 100) {
          file.deleteSync();
          setState(() {
            recordingStartPos = null;
            _currentRecordPath = null;
          });
          return;
        }

        List<Track> armedTracks = tracks
            .where((t) => t.type == TrackType.audio && t.isArmed)
            .toList();
        if (armedTracks.isNotEmpty) {
          final double recAnchor = recordingStartPos!;
          double rawSec = max(0.1, (finalPlayhead - recAnchor) / 100.0);

          if (_isSoloudReady) {
            try {
              final tempSource = await SoLoud.instance.loadFile(
                _currentRecordPath!,
              );
              double sec =
                  SoLoud.instance.getLength(tempSource).inMilliseconds / 1000.0;
              if (sec > 0) rawSec = sec;
              SoLoud.instance.disposeSource(tempSource);
            } catch (_) {}
          }

          final double curBpm = TempoMarker.effectiveBpmAt(
            recAnchor,
            tempoMarkers,
            bpm.toDouble(),
          );
          final double unitsPerSec = 100.0 * (curBpm / max(20, bpm));
          final syncPlacement = computeRecordingSyncPlacement(
            recordingStartPos: recAnchor,
            firstChunkArrivedPlayhead: _recordingFirstChunkPos,
            firstChunkFrames: _recordingFirstChunkFrames,
            rawWavDurationSeconds: rawSec,
            unitsPerSecond: unitsPerSec,
            latencyCompensationMs: _recordingLatencyMs,
          );
          final double rawOrigLen = max(
            syncPlacement.startOffset + syncPlacement.clipLength,
            rawSec * unitsPerSec,
          );

          List<AudioClip> newClips = [];
          for (final armedTrack in armedTracks) {
            final clip = AudioClip(
              start: syncPlacement.clipStart,
              length: syncPlacement.clipLength,
              originalLength: rawOrigLen,
              startOffset: syncPlacement.startOffset,
              color: armedTrack.color,
              filePath: _currentRecordPath!,
              id: UniqueKey().toString(),
            );
            if (_isSoloudReady) {
              clip.source = await SoLoud.instance.loadFile(_currentRecordPath!);
            }
            newClips.add(clip);
          }

          setState(() {
            for (int i = 0; i < armedTracks.length; i++) {
              var t = armedTracks[i];
              final existingClips = trackClips.putIfAbsent(t.id, () => []);
              final newClip = newClips[i];
              final overlapping = existingClips
                  .whereType<AudioClip>()
                  .where(
                    (c) =>
                        c.start < newClip.start + newClip.length &&
                        c.start + c.length > newClip.start,
                  )
                  .firstOrNull;
              if (overlapping != null) {
                final takeNum = overlapping.takes.isEmpty
                    ? 2
                    : overlapping.takes.length + 1;
                overlapping.addTake(
                  AudioTake(
                    id: UniqueKey().toString(),
                    name: 'Take $takeNum',
                    filePath: _currentRecordPath!,
                  ),
                );
                overlapping.source = newClip.source;
                selectedClip = overlapping;
              } else {
                existingClips.add(newClip);
              }
            }
          });
        }
      }
      recordingStartPos = null;
      _recordingFirstChunkPos = null;
      _recordingFirstChunkFrames = 0;
      _currentRecordPath = null;
    } else {
      bool hasPermission =
          Platform.isLinux || await _audioRecorder.hasPermission();
      if (hasPermission) {
        bool hasArmedAudio = tracks.any(
          (t) => t.type == TrackType.audio && t.isArmed,
        );
        bool hasArmedMidi = tracks.any(
          (t) => t.type != TrackType.audio && t.isArmed,
        );

        if (hasArmedAudio || hasArmedMidi) {
          if (hasArmedAudio) {
            final dir = await getProjectMediaDirectory();
            _currentRecordPath =
                '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.wav';
            // Warm up mic capture BEFORE starting playback/metronome so parecord/ADC
            // doesn't start late behind Beat 1.
            if (_micStreamSub == null) {
              _micWarmupCompleter = Completer<void>();
            }
            await _updateMicState(forceMic: true);
            if (_micWarmupCompleter != null && countInBars == 0 && !isPlaying) {
              await Future.any([
                _micWarmupCompleter!.future,
                Future.delayed(const Duration(milliseconds: 120)),
              ]);
            }
            _micWarmupCompleter = null;
          }

          if (punchInLoop && isLooping) {
            setState(() => playheadPosition = loopStart);
          }

          Future<void> beginRecordNow() async {
            _saveState();
            _recordingFirstChunkPos = null;
            _recordingFirstChunkFrames = 0;
            if (hasArmedAudio && _currentRecordPath != null) {
              _wavWriter = WavWriter(_currentRecordPath!);
            }
            setState(() {
              isRecording = true;
              _countInBeatsLeft = 0;
              recordingStartPos = playheadPosition;
              if (!isPlaying) _togglePlay();
            });
          }

          if (countInBars > 0 && !isPlaying) {
            _countInTimer?.cancel();
            int remaining = countInBars * timeSigTop;
            setState(() => _countInBeatsLeft = remaining);

            void playClick(bool accent) {
              _playMetronomeClick(accent);
            }

            playClick(true);
            final beatMs = (60000 / bpm).round();
            _countInTimer = Timer.periodic(Duration(milliseconds: beatMs), (t) async {
              remaining--;
              if (!mounted) {
                t.cancel();
                return;
              }
              if (remaining <= 0) {
                t.cancel();
                await beginRecordNow();
              } else {
                final beatIdx = (countInBars * timeSigTop) - remaining;
                playClick(beatIdx % timeSigTop == 0);
                setState(() => _countInBeatsLeft = remaining);
              }
            });
          } else {
            await beginRecordNow();
          }
        } else {
          if (_wavWriter != null) {
            _wavWriter!.close();
            _wavWriter = null;
          }
          _currentRecordPath = null;
        }
      }
    }
  }

  Future<String?> _recordSampleDialog() async {
    String? finalPath;
    await showDialog(
      context: context,
      builder: (context) {
        bool isRecordingSample = false;
        String? tempPath;
        StreamSubscription? sub;
        WavWriter? writer;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: panelDark,
              title: Text('Record Sample', style: TextStyle(color: textMain)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.mic,
                    size: 48,
                    color: isRecordingSample ? Colors.red : textMuted,
                  ),
                  SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isRecordingSample
                          ? panelLight
                          : Colors.red,
                    ),
                    onPressed: () async {
                      if (isRecordingSample) {
                        setModalState(() => isRecordingSample = false);
                        sub?.cancel();
                        sub = null;
                        await _audioRecorder.stop();
                        writer?.close();
                        writer = null;
                        finalPath = tempPath;
                        if (mounted && Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }
                      } else {
                        if (!await _audioRecorder.hasPermission()) return;
                        final dir = await getProjectMediaDirectory();
                        tempPath =
                            '${dir.path}/rec_sample_${DateTime.now().millisecondsSinceEpoch}.wav';
                        writer = WavWriter(tempPath!);
                        final stream = await _audioRecorder.startStream(
                          RecordConfig(
                            encoder: AudioEncoder.pcm16bits,
                            sampleRate: 44100,
                            numChannels: 1,
                          ),
                        );
                        sub = stream.listen((data) {
                          writer?.write(data);
                        });
                        setModalState(() => isRecordingSample = true);
                      }
                    },
                    child: Text(
                      isRecordingSample ? 'Stop Recording' : 'Start Recording',
                      style: TextStyle(color: textMain),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    if (isRecordingSample) {
                      sub?.cancel();
                      _audioRecorder.stop();
                      writer?.close();
                    }
                    Navigator.of(context).pop();
                  },
                  child: Text('Cancel', style: TextStyle(color: textMuted)),
                ),
              ],
            );
          },
        );
      },
    );
    return finalPath;
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
    setState(() {
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
        setState(() {});
      }
    }
  }

  void _executeDeleteTrack(Track track) {
    _saveState();
    setState(() {
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
              setState(() => clip.name = ctrl.text.trim());
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
                setState(() {
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
                setState(() {
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
            setState(() {
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
      setState(() {
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
      setState(() {
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
      setState(() {
        trackClips[trackId]?.add(dup);
        selectedClip = dup;
      });
    } else if (result == 'make_unique' && clip is MidiClip) {
      _saveState();
      setState(() => clip.patternGroupId = null);
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
        setState(() {});
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
      setState(() {
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
      setState(() {});
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
    setState(() {
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
    setState(() {});
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
    setState(() {
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
    setState(() {
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
                setState(() => track.groupTrackId = null);
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
                  setState(() => track.groupTrackId = g.id);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _triggerSessionClip(Track track, DawClip clip) {
    setState(() {
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
    setState(() {
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
    setState(() {
      for (final c in trackClips[track.id] ?? const <DawClip>[]) {
        _activeSessionClipIds.remove(c.id);
        _queuedSessionClipIds.remove(c.id);
        if (c is AudioClip) _stopAudioClipHandles(c);
      }
    });
  }

  Widget _buildTopBar() {
    return Container(
      height: 68,
      padding: EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: panelDark,
        border: Border(bottom: BorderSide(color: textMuted, width: 2)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onPanStart: (d) => windowManager.startDragging(),
              onDoubleTap: () async {
                bool isMax = await windowManager.isMaximized();
                if (isMax) {
                  windowManager.unmaximize();
                } else {
                  windowManager.maximize();
                }
              },
              behavior: HitTestBehavior.translucent,
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () => windowManager.close(),
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.red.shade300,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => windowManager.minimize(),
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.amber.shade300,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => windowManager.isMaximized().then(
                        (m) => m
                            ? windowManager.unmaximize()
                            : windowManager.maximize(),
                      ),
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.green.shade300,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    SizedBox(width: 18),
                    Text(
                      'Sound Booth',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: lavenderAccent,
                      ),
                    ),
                  ],
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              isPlaying ? Icons.pause : Icons.play_arrow,
                              color: textMuted,
                            ),
                            onPressed: _togglePlay,
                          ),
                          IconButton(
                            icon: Icon(Icons.stop, color: textMuted),
                            onPressed: () {
                              if (isRecording) _toggleRecord();
                              setState(() {
                                if (isPlaying) _togglePlay();
                                playheadPosition = isLooping ? loopStart : 0.0;
                                try {
                                  SoLoud.instance.filters.echoFilter.deactivate();
                                } catch (_) {}
                                try {
                                  SoLoud.instance.filters.robotizeFilter.deactivate();
                                } catch (_) {}
                                try {
                                  SoLoud.instance.filters.compressorFilter.deactivate();
                                } catch (_) {}
                                try {
                                  SoLoud.instance.filters.biquadResonantFilter.deactivate();
                                } catch (_) {}
                                _stopAllActivePlaybackVoices();
                              });
                            },
                          ),
                          IconButton(
                            icon: Icon(
                              isRecording
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              color: _countInBeatsLeft > 0
                                  ? Colors.amberAccent
                                  : activeRecord,
                            ),
                            tooltip: 'Record (R)',
                            onPressed: _toggleRecord,
                          ),
                          if (_countInBeatsLeft > 0)
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amberAccent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '$_countInBeatsLeft',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          SizedBox(width: 4),
                          Tooltip(
                            message: 'Count-In Bars before recording (Off / 1 Bar / 2 Bars)',
                            child: InkWell(
                              onTap: () => setState(() => countInBars = (countInBars + 1) % 3),
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: countInBars > 0
                                      ? Colors.amberAccent.withValues(alpha: 0.22)
                                      : textFaint,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: countInBars > 0 ? Colors.amberAccent : borderMain,
                                  ),
                                ),
                                child: Text(
                                  countInBars == 0 ? '1-2' : '${countInBars}B',
                                  style: TextStyle(
                                    color: countInBars > 0 ? Colors.amberAccent : textMuted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 4),
                          Tooltip(
                            message: 'Loop Punch-In/Out (Records inside loop brace)',
                            child: InkWell(
                              onTap: () => setState(() => punchInLoop = !punchInLoop),
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: punchInLoop
                                      ? activeRecord.withValues(alpha: 0.25)
                                      : textFaint,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: punchInLoop ? activeRecord : borderMain,
                                  ),
                                ),
                                child: Text(
                                  'PUNCH',
                                  style: TextStyle(
                                    color: punchInLoop ? activeRecord : textMuted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 10),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: textFaint,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: textFaint),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.timer, size: 14, color: textMuted),
                                SizedBox(width: 6),
                                SizedBox(
                                  width: 28,
                                  child: TextField(
                                    controller: TextEditingController(
                                      text: bpm.toString(),
                                    ),
                                    focusNode: _bpmFocus,
                                    style: TextStyle(
                                      color: textMain,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      isDense: true,
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    onSubmitted: (v) {
                                      int? nb = int.tryParse(v);
                                      if (nb != null && nb > 20 && nb < 300) {
                                        _changeTempo(nb);
                                      }
                                      _focusNode.requestFocus();
                                    },
                                    onTapOutside: (e) => _focusNode.requestFocus(),
                                  ),
                                ),
                                Text(
                                  'BPM',
                                  style: TextStyle(color: textMuted, fontSize: 10),
                                ),
                                TextButton(
                                  onPressed: _tapTempo,
                                  child: Text(
                                    'Tap',
                                    style: TextStyle(color: lavenderLight, fontSize: 10),
                                  ),
                                ),
                                SizedBox(width: 6),
                                Tooltip(
                                  message: 'Toggle Metronome',
                                  child: InkWell(
                                    onTap: () {
                                      setState(() {
                                        isMetronomeEnabled = !isMetronomeEnabled;
                                      });
                                    },
                                    child: Icon(
                                      Icons.notifications_active,
                                      size: 16,
                                      color: isMetronomeEnabled
                                          ? lavenderAccent
                                          : textMuted,
                                    ),
                                  ),
                                ),
                                Tooltip(
                                  message:
                                      'Metronome Volume (${(metronomeVolume * 100).round()}%)',
                                  child: SizedBox(
                                    width: 58,
                                    height: 22,
                                    child: SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        trackHeight: 2.5,
                                        thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 5,
                                        ),
                                        overlayShape:
                                            const RoundSliderOverlayShape(
                                              overlayRadius: 9,
                                            ),
                                      ),
                                      child: Slider(
                                        key: const Key('metronome_volume_slider'),
                                        value: metronomeVolume.clamp(0.0, 1.5),
                                        min: 0.0,
                                        max: 1.5,
                                        activeColor: lavenderAccent,
                                        inactiveColor: borderMain,
                                        onChanged: (v) {
                                          setState(() => metronomeVolume = v);
                                        },
                                        onChangeEnd: _saveMetronomeVolumePref,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 6),
                                DropdownButton<int>(
                                  value: timeSigTop,
                                  underline: SizedBox(),
                                  dropdownColor: panelDark,
                                  icon: SizedBox(),
                                  items: [3, 4, 5, 6, 7]
                                      .map(
                                        (i) => DropdownMenuItem(
                                          value: i,
                                          child: Text(
                                            '$i / $timeSigBottom',
                                            style: TextStyle(
                                              color: textMain,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) {
                                    if (v != null) setState(() => timeSigTop = v);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.undo, color: textMuted),
                      onPressed: _undo,
                      tooltip: 'Undo (Ctrl+Z)',
                      constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.all(4),
                    ),
                    IconButton(
                      icon: Icon(Icons.redo, color: textMuted),
                      onPressed: _redo,
                      tooltip: 'Redo (Ctrl+Shift+Z)',
                      constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.all(4),
                    ),
                    IconButton(
                      icon: Icon(Icons.zoom_out, color: textMuted),
                      onPressed: _zoomOut,
                      tooltip: 'Zoom Out (Ctrl-)',
                      constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.all(4),
                    ),
                    IconButton(
                      icon: Icon(Icons.zoom_in, color: textMuted),
                      onPressed: _zoomIn,
                      tooltip: 'Zoom In (Ctrl+)',
                      constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.all(4),
                    ),
                    IconButton(
                      icon: Icon(
                        snapToGrid ? Icons.grid_on : Icons.grid_off,
                        color: snapToGrid ? lavenderAccent : textMuted,
                      ),
                      tooltip: 'Snap to Grid',
                      onPressed: () => setState(() => snapToGrid = !snapToGrid),
                      constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.all(4),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.center_focus_strong,
                        size: 18,
                        color: autoScrollPlayhead ? Colors.cyanAccent : textMuted,
                      ),
                      tooltip: 'Auto-Follow Playhead',
                      onPressed: () => setState(
                        () => autoScrollPlayhead = !autoScrollPlayhead,
                      ),
                      constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.all(4),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.keyboard,
                        size: 18,
                        color: isMusicalTypingEnabled
                            ? lavenderAccent
                            : textMuted,
                      ),
                      tooltip: 'QWERTY Musical Typing Keyboard',
                      onPressed: () => setState(
                        () => isMusicalTypingEnabled = !isMusicalTypingEnabled,
                      ),
                      constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.all(4),
                    ),
                    IconButton(
                      icon: Icon(
                        _isSessionView ? Icons.view_timeline : Icons.grid_view,
                        size: 18,
                        color: _isSessionView ? Colors.cyanAccent : textMuted,
                      ),
                      tooltip: _isSessionView
                          ? 'Switch to Timeline View'
                          : 'Switch to Session Clip Launcher',
                      onPressed: () =>
                          setState(() => _isSessionView = !_isSessionView),
                      constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.all(4),
                    ),
                    IconButton(
                      key: const Key('toggle_sample_browser'),
                      icon: Icon(
                        Icons.library_music,
                        size: 18,
                        color: _showSampleBrowser
                            ? Colors.cyanAccent
                            : textMuted,
                      ),
                      tooltip: 'Toggle Sample & MIDI Browser',
                      onPressed: () => setState(
                        () => _showSampleBrowser = !_showSampleBrowser,
                      ),
                      constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.all(4),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.sensors,
                        size: 18,
                        color: _midiLearnActive ? Colors.amberAccent : textMuted,
                      ),
                      tooltip: _midiLearnActive
                          ? 'MIDI Learn Active (Click mixer control then move HW knob/fader)'
                          : 'MIDI Learn Mode (${midiMappings.length} mapped)',
                      onPressed: () => setState(() {
                        _midiLearnActive = !_midiLearnActive;
                        if (!_midiLearnActive) _midiLearnTarget = null;
                      }),
                      constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.all(4),
                    ),
                    SizedBox(width: 4),
                    MasterSpectrumWidget(
                      samples: _masterVizSamples,
                      width: 96,
                      height: 28,
                      accentColor: lavenderAccent,
                    ),
                    SizedBox(width: 4),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.settings, color: textMuted),
                      onSelected: (val) {
                        if (val == 'new') _newProject();
                        if (val == 'templates') _openTemplates();
                        if (val == 'open') _openProject();
                        if (val == 'save') _saveProject();
                        if (val == 'save_as') _saveProjectAs();
                        if (val == 'import_midi') _importMidiFile();
                        if (val == 'export_midi') _exportSelectedMidiClip();
                        if (val == 'export') _exportAudio();
                        if (val == 'export_stems') _exportStems();
                        if (val == 'preferences') _openPreferences();
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'new',
                          child: Text('New Project'),
                        ),
                        PopupMenuItem(
                          value: 'templates',
                          child: Text('New from Template...'),
                        ),
                        PopupMenuItem(
                          value: 'open',
                          child: Text('Open Project'),
                        ),
                        PopupMenuItem(
                          value: 'save',
                          enabled: currentProjectPath != null,
                          child: Text('Save Project'),
                        ),
                        PopupMenuItem(
                          value: 'save_as',
                          child: Text('Save As...'),
                        ),
                        PopupMenuItem(
                          value: 'import_midi',
                          child: Text('Import MIDI (.mid)...'),
                        ),
                        PopupMenuItem(
                          value: 'export_midi',
                          enabled: selectedClip is MidiClip,
                          child: Text('Export Selected Clip as .mid'),
                        ),
                        PopupMenuItem(
                          value: 'export',
                          child: Text('Export Mixdown (WAV/FLAC/MP3)'),
                        ),
                        PopupMenuItem(
                          value: 'export_stems',
                          child: Text('Export Stems'),
                        ),
                        PopupMenuItem(
                          value: 'preferences',
                          child: Text('Preferences'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _applyTrackColor(Track track, Color color) {
    setState(() {
      track.colorValue = color.toARGB32();
      for (final clip in trackClips[track.id] ?? const <DawClip>[]) {
        clip.color = color;
      }
    });
  }

  void _applyClipColor(DawClip clip, Color color) {
    _saveState();
    setState(() {
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

  Widget _buildTrackHeaders() {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: panelDark,
        border: Border(right: BorderSide(color: textMuted, width: 2)),
      ),
      child: Column(
        children: [
          Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: bgDark,
              border: Border(bottom: BorderSide(color: borderMain, width: 1)),
            ),
            child: Text(
              'OVERVIEW',
              style: TextStyle(
                color: textFaint,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ),
          Container(
            height: 40,
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Text('Tracks', style: TextStyle(fontWeight: FontWeight.bold)),
                Spacer(),
                PopupMenuButton<String>(
                  icon: Icon(Icons.add, size: 20),
                  onSelected: (v) {
                    if (v == 'audio') _addTrack(TrackType.audio);
                    if (v == 'midi') _addTrack(TrackType.midi);
                    if (v == 'sampler') _addTrack(TrackType.sampler);
                    if (v == 'group') _addTrack(TrackType.group);
                    if (v == 'import') _importAudioTrack();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'audio',
                      child: Text('Add Audio Track'),
                    ),
                    PopupMenuItem(value: 'midi', child: Text('Add MIDI Track')),
                    PopupMenuItem(
                      value: 'sampler',
                      child: Text('Add Sampler Track'),
                    ),
                    PopupMenuItem(
                      value: 'group',
                      child: Text('Add Group Bus'),
                    ),
                    PopupMenuItem(value: 'import', child: Text('Import WAV')),
                  ],
                ),
              ],
            ),
          ),
          Container(
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: bgDark,
              border: Border(
                top: BorderSide(color: borderMain, width: 1),
                bottom: BorderSide(color: borderMain, width: 1),
              ),
            ),
            child: Text(
              'TEMPO / SIG',
              style: TextStyle(
                color: textFaint,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              controller: _headerScrollController,
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                if (!_isTrackVisibleInArrange(track)) {
                  return const SizedBox.shrink();
                }
                final isSelected = selectedTrackIndex == index;
                final parentGroup = _groupForTrack(track);
                return GestureDetector(
                  onSecondaryTapUp: (d) {
                    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
                    showMenu<String>(
                      context: context,
                      position: RelativeRect.fromRect(
                        d.globalPosition & Size(40, 40),
                        Offset.zero & overlay.size,
                      ),
                      items: [
                        PopupMenuItem(value: 'color', child: Text('Change Track Color')),
                        if (track.type != TrackType.group &&
                            tracks.any((t) => t.type == TrackType.group))
                          PopupMenuItem(
                            value: 'assign_group',
                            child: Text('Route to Group Bus...'),
                          ),
                        PopupMenuItem(value: 'bounce', child: Text('Bounce Track to Audio')),
                        PopupMenuDivider(),
                        PopupMenuItem(value: 'delete', child: Text('Delete Track', style: TextStyle(color: Colors.red))),
                      ],
                    ).then((value) {
                      if (value == 'color') _showTrackColorPicker(track);
                      if (value == 'assign_group') _assignTrackToGroupDialog(track);
                      if (value == 'bounce') _bounceTrackToAudio(track);
                      if (value == 'delete') _deleteTrack(track);
                    });
                  },
                  onTap: () {
                    setState(() {
                      bool wasSelected = selectedTrackIndex == index;
                      if (!wasSelected) {
                        selectedClip = null;
                        multiSelectedClips.clear();
                      }
                      selectedTrackIndex = index;
                      if ((track.type == TrackType.audio ||
                              track.type == TrackType.group) &&
                          (selectedBottomTab == 0 || selectedBottomTab == 3)) {
                        selectedBottomTab = track.type == TrackType.audio ? 4 : 2;
                      } else if (track.type == TrackType.midi &&
                          (selectedBottomTab == 3 || selectedBottomTab == 4)) {
                        selectedBottomTab = 0;
                      } else if (track.type == TrackType.group &&
                          selectedBottomTab == 4) {
                        selectedBottomTab = 2;
                      }
                      if (!wasSelected && track.type == TrackType.sampler) {
                        selectedBottomTab = 3;
                        isBottomPanelExpanded = true;
                        if (_bottomPanelHeight < 400) {
                          _bottomPanelHeight = 400;
                        }
                      }
                    });
                  },
                  child: Container(
                    height: track.showAutomation ? 140 : 100,
                    decoration: BoxDecoration(
                      color: isSelected ? panelLight : Colors.transparent,
                      border: Border(
                        left: BorderSide(color: track.color, width: 4),
                        bottom: BorderSide(color: textFaint),
                      ),
                    ),
                    padding: EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            InkWell(
                              onTap: () => _showTrackColorPicker(track),
                              child: Container(
                                width: 10,
                                height: 10,
                                margin: EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: track.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            if (track.type == TrackType.group)
                              Row(
                                children: [
                                  InkWell(
                                    onTap: () => setState(
                                      () => track.isGroupCollapsed =
                                          !track.isGroupCollapsed,
                                    ),
                                    child: Icon(
                                      track.isGroupCollapsed
                                          ? Icons.chevron_right
                                          : Icons.expand_more,
                                      size: 16,
                                      color: Colors.amberAccent,
                                    ),
                                  ),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.amberAccent.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      'BUS',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.amberAccent,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            else if (track.type == TrackType.audio)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.mic, size: 16, color: track.color),
                                  const SizedBox(width: 4),
                                  PopupMenuButton<String>(
                                    tooltip: 'Select Audio Input Channel',
                                    initialValue: _channelOptionForTrack(track).id,
                                    onSelected: (chId) =>
                                        _selectTrackInputChannel(track, chId),
                                    itemBuilder: (_) => _inputChannelOptionsForSelectedDevice()
                                        .map(
                                          (opt) => PopupMenuItem<String>(
                                            value: opt.id,
                                            child: Row(
                                              children: [
                                                Icon(
                                                  opt.id == _channelOptionForTrack(track).id
                                                      ? Icons.radio_button_checked
                                                      : Icons.radio_button_unchecked,
                                                  size: 13,
                                                  color: opt.id == _channelOptionForTrack(track).id
                                                      ? Colors.cyanAccent
                                                      : textMuted,
                                                ),
                                                const SizedBox(width: 6),
                                                Flexible(
                                                  child: Text(
                                                    opt.label,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    child: Container(
                                      key: Key('track_channel_pill_${track.id}'),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: bgDark,
                                        borderRadius: BorderRadius.circular(3),
                                        border: Border.all(
                                          color: track.inputChannelId != 'stereo:0'
                                              ? Colors.cyanAccent
                                              : borderMain,
                                        ),
                                      ),
                                      child: Text(
                                        _channelOptionForTrack(track).shortLabel,
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: track.inputChannelId != 'stereo:0'
                                              ? Colors.cyanAccent
                                              : textMuted,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            else
                              Row(
                                children: [
                                  InkWell(
                                    onTap: () => _showInstrumentDialog(track),
                                    child: Icon(
                                      Icons.piano,
                                      size: 16,
                                      color: track.color,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  InkWell(
                                    onTap: () => _showMidiInputDialog(track),
                                    child: Icon(
                                      Icons.cable,
                                      size: 16,
                                      color: track.midiInputId == null
                                          ? track.color
                                          : Colors.cyanAccent,
                                    ),
                                  ),
                                ],
                              ),
                            if (parentGroup != null) ...[
                              SizedBox(width: 4),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 3,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: parentGroup.color.withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  'GRP',
                                  style: TextStyle(
                                    fontSize: 8,
                                    color: parentGroup.color,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                            SizedBox(width: 8),
                            Expanded(
                              child: GestureDetector(
                                onDoubleTap: () {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) {
                                      TextEditingController ctrl =
                                          TextEditingController(
                                            text: track.name,
                                          );
                                      return AlertDialog(
                                        title: Text('Rename Track'),
                                        content: TextField(
                                          controller: ctrl,
                                          autofocus: true,
                                          decoration: InputDecoration(
                                            filled: true,
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx),
                                            child: Text('Cancel'),
                                          ),
                                          TextButton(
                                            onPressed: () {
                                              setState(
                                                () => track.name = ctrl.text,
                                              );
                                              Navigator.pop(ctx);
                                            },
                                            child: Text('Save'),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                },
                                child: Text(
                                  track.name,
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Spacer(),

                        Row(
                          children: [
                            _buildTrackButton(
                              'A',
                              track.showAutomation,
                              () => setState(
                                () => track.showAutomation =
                                    !track.showAutomation,
                              ),
                              Colors.cyanAccent,
                            ),
                            SizedBox(width: 4),
                            _buildTrackButton(
                              'M',
                              track.isMuted,
                              () {
                                setState(
                                  () => track.isMuted = !track.isMuted,
                                );
                                _syncTrackMonitoringHandles();
                              },
                              Colors.redAccent,
                            ),
                            SizedBox(width: 4),
                            _buildTrackButton(
                              'S',
                              track.isSolo,
                              () {
                                setState(() => track.isSolo = !track.isSolo);
                                _syncTrackMonitoringHandles();
                              },
                              Colors.amber,
                            ),
                            if (track.type != TrackType.group) ...[
                              SizedBox(width: 4),
                              _buildTrackButton(
                                'R',
                                track.isArmed,
                                () async {
                                  setState(
                                    () => track.isArmed = !track.isArmed,
                                  );
                                  await _updateMicState();
                                },
                                activeRecord,
                              ),
                            ],
                            if (track.type == TrackType.audio) ...[
                              SizedBox(width: 4),
                              _buildTrackButton(
                                '',
                                track.isMonitoring,
                                () async {
                                  setState(() {
                                    track.isMonitoring = !track.isMonitoring;
                                  });
                                  await _updateMicState();
                                },
                                Colors.green,
                                icon: Icons.headphones,
                              ),
                            ],
                            Spacer(),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.volume_up,
                                      size: 12,
                                      color: textMuted,
                                    ),
                                    SizedBox(
                                      width: 60,
                                      child: SliderTheme(
                                        data: SliderThemeData(
                                          thumbShape: RoundSliderThumbShape(
                                            enabledThumbRadius: 6,
                                          ),
                                          overlayShape:
                                              SliderComponentShape.noOverlay,
                                        ),
                                        child: Slider(
                                          onChangeStart: (_) => _saveState(),
                                          value: track.volume,
                                          activeColor: lavenderAccent,
                                          onChanged: (v) => setState(() {
                                            track.volume = v;
                                            for (var c
                                                in trackClips[track.id] ?? []) {
                                              if (c is AudioClip &&
                                                  c.currentHandle != null) {
                                                SoLoud.instance.setVolume(
                                                  c.currentHandle!,
                                                  v,
                                                );
                                              }
                                            }
                                            _syncTrackMonitoringHandles();
                                          }),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      'L ',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: textMuted,
                                      ),
                                    ),
                                    PanDial(
                                      onChangeStart: _saveState,
                                      pan: track.pan,
                                      onChanged: (v) => setState(() {
                                        track.pan = v;
                                        for (var c
                                            in trackClips[track.id] ?? []) {
                                          if (c is AudioClip &&
                                              c.currentHandle != null) {
                                            SoLoud.instance.setPan(
                                              c.currentHandle!,
                                              v,
                                            );
                                          }
                                        }
                                        _syncTrackMonitoringHandles();
                                      }),
                                    ),
                                    Text(
                                      ' R',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (track.showAutomation) ...[
                          SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.show_chart,
                                size: 14,
                                color: Colors.cyanAccent,
                              ),
                              SizedBox(width: 8),
                              Builder(
                                builder: (context) {
                                  final items = track.availableAutomationParams;
                                  if (!items.contains(
                                    track.currentAutomationParam,
                                  )) {
                                    track.currentAutomationParam = 'Volume';
                                  }
                                  return DropdownButton<String>(
                                    value: track.currentAutomationParam,
                                    dropdownColor: panelDark,
                                    underline: SizedBox(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: textMain,
                                    ),
                                    items: items
                                        .map(
                                          (e) => DropdownMenuItem(
                                            value: e,
                                            child: Text(e),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) {
                                      if (v != null) {
                                        setState(
                                          () =>
                                              track.currentAutomationParam = v,
                                        );
                                      }
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackButton(
    String label,
    bool isActive,
    VoidCallback onTap,
    Color activeColor, {
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: isActive ? activeColor.withOpacity(0.3) : bgDark,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isActive ? activeColor : textFaint),
        ),
        child: Center(
          child: icon != null
              ? Icon(icon, size: 14, color: isActive ? activeColor : textMain)
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isActive ? activeColor : textMain,
                  ),
                ),
        ),
      ),
    );
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

  Widget _buildClip(String trackId, DawClip clip) {
    final isSelected =
        selectedClip == clip || multiSelectedClips.contains(clip);
    final bool isMovingOffTrack = _activeDragClips.contains(clip) &&
        _dragTargetTrackId != null &&
        _dragTargetTrackId != trackId;
    return Positioned(
      key: ValueKey('clip_${clip.id}'),
      left: clip.start * _zoomX,
      top: 10,
      bottom: 10,
      width: clip.length * _zoomX,
      child: Opacity(
        opacity: isMovingOffTrack ? 0.35 : 1.0,
        child: GestureDetector(
        supportedDevices: {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
        },
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          selectedClip = clip;
          multiSelectedClips.clear();
          int tIdx = tracks.indexWhere((t) => t.id == trackId);
          if (tIdx != -1) {
            selectedTrackIndex = tIdx;
          }
        }),
        onDoubleTapDown: (_) {},
        onDoubleTap: () => setState(() {
          selectedClip = clip;
          multiSelectedClips.clear();
          int tIdx = tracks.indexWhere((t) => t.id == trackId);
          if (tIdx != -1) {
            selectedTrackIndex = tIdx;
          }
          isBottomPanelExpanded = true;
          if (_bottomPanelHeight < 360) {
            _bottomPanelHeight = 360;
          }
          if (clip is MidiClip) {
            selectedBottomTab = 0;
          } else if (clip is AudioClip) {
            selectedBottomTab = 4;
          }
        }),
        onSecondaryTapUp: (details) =>
            _showClipMenu(details.globalPosition, trackId, clip),
        onPanStart: (d) {
          _saveState();
          final sourceTargets = multiSelectedClips.contains(clip)
              ? [...multiSelectedClips]
              : [clip];
          _dragSourceTrackId = trackId;
          _dragTargetTrackId = trackId;
          if (HardwareKeyboard.instance.isAltPressed) {
            final clones = <DawClip>[];
            DawClip? clonedPrimary;
            for (final orig in sourceTargets) {
              final ownerId = _ownerTrackIdForClip(orig);
              final clone = _cloneClipForDragCopy(ownerId ?? trackId, orig);
              clones.add(clone);
              if (identical(orig, clip)) clonedPrimary = clone;
            }
            setState(() {
              _activeDragClips = clones;
              if (multiSelectedClips.contains(clip)) {
                multiSelectedClips
                  ..clear()
                  ..addAll(clones);
                selectedClip = clonedPrimary ?? clones.first;
              } else {
                multiSelectedClips.clear();
                selectedClip = clonedPrimary ?? clones.first;
              }
            });
          } else {
            _activeDragClips = sourceTargets;
          }
        },
        onPanUpdate: (d) => setState(() {
          final targets = _activeDragClips.isNotEmpty
              ? _activeDragClips
              : (multiSelectedClips.contains(clip)
                    ? multiSelectedClips
                    : [clip]);
          for (var c in targets) {
            c.start += (d.delta.dx / _zoomX);
            if (c.start < 0) c.start = 0;
          }
          final hovered = _trackAtGlobalY(d.globalPosition.dy);
          if (hovered != null && _canMoveClipToTrack(clip, hovered)) {
            _dragTargetTrackId = hovered.id;
          }
        }),
        onPanEnd: (d) => setState(() {
          final targets = _activeDragClips.isNotEmpty
              ? _activeDragClips
              : (multiSelectedClips.contains(clip)
                    ? multiSelectedClips
                    : [clip]);
          if (snapToGrid) {
            for (var c in targets) {
              c.start = (c.start / snapResolution).round() * snapResolution;
            }
          }
          if (_dragTargetTrackId != null && _dragTargetTrackId != trackId) {
            final destTrack =
                tracks.where((t) => t.id == _dragTargetTrackId).firstOrNull;
            if (destTrack != null) {
              _moveClipsToTrack(targets, destTrack);
            }
          }
          _activeDragClips = [];
          _dragSourceTrackId = null;
          _dragTargetTrackId = null;
        }),
        onPanCancel: () => setState(() {
          _activeDragClips = [];
          _dragSourceTrackId = null;
          _dragTargetTrackId = null;
        }),
        child: Container(
          decoration: BoxDecoration(
            color: clip.color.withOpacity(isSelected ? 0.8 : 0.5),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? textMain : textMuted,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (clip is AudioClip)
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (clip.waveformData != null &&
                        clip.waveformData!.isNotEmpty) {
                      return ClipRect(
                        child: Stack(
                          children: [
                            Positioned(
                              left: -clip.startOffset * _zoomX,
                              width: clip.originalLength * _zoomX,
                              top: 0,
                              bottom: 0,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: clip.waveformData!
                                    .map(
                                      (amp) => Container(
                                        width: max(
                                          1.0,
                                          (clip.originalLength * _zoomX) /
                                                  clip.waveformData!.length -
                                              0.5,
                                        ),
                                        height: max(
                                          2.0,
                                          amp * constraints.maxHeight,
                                        ),
                                        color: textMuted,
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return ClipRect(
                      child: Stack(
                        children: [
                          Positioned(
                            left: -clip.startOffset * _zoomX,
                            width: clip.originalLength * _zoomX,
                            top: 0,
                            bottom: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: List.generate(
                                ((clip.originalLength * _zoomX) / 6).floor(),
                                (i) {
                                  final rnd = Random(
                                    clip.filePath.hashCode + i,
                                  ).nextDouble();
                                  return Container(
                                    width: 2,
                                    height: 4.0 + rnd * 24.0,
                                    color: textMuted,
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              if (clip is MidiClip)
                Positioned.fill(
                  child: ClipRect(
                    child: CustomPaint(
                      painter: MidiClipThumbnailPainter(
                        notes: clip.notes,
                        clipLength: clip.length,
                        originalLength: clip.originalLength,
                        startOffset: clip.startOffset,
                        color: textMain,
                      ),
                    ),
                  ),
                ),
              if (clip is AudioClip)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: LoopNotchesPainter(
                        clipLength: clip.length,
                        originalLength: clip.originalLength / clip.stretchFactor,
                      ),
                    ),
                  ),
                ),
              if (clip is AudioClip)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: ClipFadePainter(
                        fadeInRatio: clip.length > 0
                            ? (clip.fadeIn / clip.length).clamp(0.0, 0.9)
                            : 0.0,
                        fadeOutRatio: clip.length > 0
                            ? (clip.fadeOut / clip.length).clamp(0.0, 0.9)
                            : 0.0,
                        accentColor: Colors.white,
                      ),
                    ),
                  ),
                ),
              if (clip.length * _zoomX > 36)
                Positioned(
                  left: 12,
                  right: 12,
                  top: 2,
                  child: IgnorePointer(
                    child: Row(
                      children: [
                        if (clip is MidiClip && clip.patternGroupId != null)
                          Container(
                            margin: EdgeInsets.only(right: 4),
                            padding: EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              '∞',
                              style: TextStyle(
                                color: Colors.cyanAccent,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            clip.name.isNotEmpty
                                ? clip.name
                                : (clip is AudioClip
                                      ? p.basenameWithoutExtension(clip.filePath)
                                      : 'MIDI'),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(color: Colors.black54, blurRadius: 2),
                              ],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (clip is AudioClip && clip.takes.length > 1)
                          Container(
                            margin: EdgeInsets.only(left: 4),
                            padding: EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              'T${clip.activeTakeIndex + 1}/${clip.takes.length}',
                              style: TextStyle(
                                color: Colors.lightGreenAccent,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        if (clip is AudioClip && clip.isLooped)
                          Container(
                            margin: EdgeInsets.only(left: 4),
                            padding: EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              'LOOP',
                              style: TextStyle(
                                color: Colors.amberAccent,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        if (clip is AudioClip &&
                            (clip.stretchFactor - 1.0).abs() > 0.02)
                          Container(
                            margin: EdgeInsets.only(left: 4),
                            padding: EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              '${clip.stretchFactor.toStringAsFixed(2)}x',
                              style: TextStyle(
                                color: Colors.cyanAccent,
                                fontSize: 8,
                              ),
                            ),
                          ),
                        if (clip is AudioClip && clip.pitchSemitones != 0)
                          Container(
                            margin: EdgeInsets.only(left: 4),
                            padding: EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              '${clip.pitchSemitones > 0 ? "+" : ""}${clip.pitchSemitones.round()}st',
                              style: TextStyle(color: Colors.cyanAccent, fontSize: 8),
                            ),
                          ),
                        if (clip is AudioClip && (clip.gain - 1.0).abs() > 0.05)
                          Container(
                            margin: EdgeInsets.only(left: 4),
                            padding: EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              '${(clip.gain * 100).round()}%',
                              style: TextStyle(color: Colors.amberAccent, fontSize: 8),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (clip is AudioClip && clip.length * _zoomX > 28) ...[
                Positioned(
                  left: ((clip.fadeIn * _zoomX) - 6).clamp(
                    6.0,
                    max(6.0, clip.length * _zoomX - 18),
                  ),
                  top: 0,
                  child: Tooltip(
                    message: 'Drag Fade-In',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeLeftRight,
                      child: GestureDetector(
                        onHorizontalDragStart: (_) => _saveState(),
                        onHorizontalDragUpdate: (d) => setState(() {
                          clip.fadeIn = (clip.fadeIn + d.delta.dx / _zoomX)
                              .clamp(0.0, max(0.0, clip.length - clip.fadeOut));
                        }),
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.only(
                              bottomRight: Radius.circular(6),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: ((clip.fadeOut * _zoomX) - 6).clamp(
                    6.0,
                    max(6.0, clip.length * _zoomX - 18),
                  ),
                  top: 0,
                  child: Tooltip(
                    message: 'Drag Fade-Out',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeLeftRight,
                      child: GestureDetector(
                        onHorizontalDragStart: (_) => _saveState(),
                        onHorizontalDragUpdate: (d) => setState(() {
                          clip.fadeOut = (clip.fadeOut - d.delta.dx / _zoomX)
                              .clamp(0.0, max(0.0, clip.length - clip.fadeIn));
                        }),
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(6),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 10,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    supportedDevices: {
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.touch,
                      PointerDeviceKind.stylus,
                    },
                    onHorizontalDragStart: (d) => _saveState(),
                    onHorizontalDragUpdate: (d) => setState(() {
                      double dx = d.delta.dx / _zoomX;
                      double newLength = clip.length - dx;
                      if (newLength < 10) {
                        dx = clip.length - 10;
                        newLength = 10;
                      }
                      if (clip.startOffset + dx < 0) {
                        dx = -clip.startOffset;
                        newLength = clip.length - dx;
                      }
                      clip.start += dx;
                      clip.length = newLength;
                      clip.startOffset += dx;
                    }),
                    onHorizontalDragEnd: (d) => setState(() {
                      if (snapToGrid) {
                        double oldStart = clip.start;
                        clip.start =
                            (clip.start / snapResolution).round() *
                            snapResolution;
                        double diff = clip.start - oldStart;
                        clip.length -= diff;
                        clip.startOffset += diff;
                        if (clip.startOffset < 0) {
                          clip.length += clip.startOffset;
                          clip.start -= clip.startOffset;
                          clip.startOffset = 0;
                        }
                      }
                    }),
                    child: Container(
                      decoration: BoxDecoration(
                        color: textFaint,
                        borderRadius: BorderRadius.horizontal(
                          left: Radius.circular(4),
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.drag_indicator,
                          size: 10,
                          color: textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 10,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    supportedDevices: {
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.touch,
                      PointerDeviceKind.stylus,
                    },
                    onHorizontalDragStart: (d) => _saveState(),
                    onHorizontalDragUpdate: (d) => setState(() {
                      clip.length = max(10.0, clip.length + d.delta.dx / _zoomX);
                      if (clip is MidiClip) {
                        clip.originalLength = max(
                          clip.originalLength,
                          clip.startOffset + clip.length,
                        );
                      } else if (clip is AudioClip && !clip.isLooped) {
                        clip.length = min(
                          clip.length,
                          clip.originalLength - clip.startOffset,
                        );
                      }
                    }),
                    onHorizontalDragEnd: (d) => setState(() {
                      if (snapToGrid) {
                        clip.length = max(
                          10.0,
                          (clip.length / snapResolution).round() *
                              snapResolution,
                        );
                        if (clip is MidiClip) {
                          clip.originalLength = max(
                            clip.originalLength,
                            clip.startOffset + clip.length,
                          );
                        } else if (clip is AudioClip && !clip.isLooped) {
                          clip.length = min(
                            clip.length,
                            clip.originalLength - clip.startOffset,
                          );
                        }
                      }
                    }),
                    child: Container(
                      decoration: BoxDecoration(
                        color: textFaint,
                        borderRadius: BorderRadius.horizontal(
                          right: Radius.circular(4),
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.drag_indicator,
                          size: 10,
                          color: textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Future<void> _showAddMarkerDialog(double pos) async {
    final ctrl = TextEditingController(text: 'Section');
    int pickedColor = 0xFF00E5FF;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: panelDark,
          title: Text('Add Arrangement Marker', style: TextStyle(color: textMain)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                style: TextStyle(color: textMain),
                decoration: InputDecoration(
                  hintText: 'Intro, Verse, Chorus, Drop...',
                  filled: true,
                  fillColor: bgDark,
                ),
              ),
              SizedBox(height: 10),
              Wrap(
                spacing: 6,
                children: ['Intro', 'Verse', 'Chorus', 'Bridge', 'Drop', 'Outro']
                    .map(
                      (preset) => ActionChip(
                        label: Text(preset, style: TextStyle(fontSize: 11)),
                        onPressed: () => ctrl.text = preset,
                      ),
                    )
                    .toList(),
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
                final label = ctrl.text.trim().isEmpty ? 'Marker' : ctrl.text.trim();
                _saveState();
                setState(() {
                  songMarkers.add(
                    SongMarker(
                      id: UniqueKey().toString(),
                      label: label,
                      position: pos,
                      colorValue: pickedColor,
                    ),
                  );
                  songMarkers.sort((a, b) => a.position.compareTo(b.position));
                });
                Navigator.pop(ctx);
              },
              child: Text('Add', style: TextStyle(color: lavenderAccent)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineMinimap() {
    final double totalTimelineUnits = _timelineTotalUnits;
    return Container(
      height: 22,
      decoration: BoxDecoration(
        color: bgDark,
        border: Border(bottom: BorderSide(color: borderMain)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final mapW = max(1.0, constraints.maxWidth);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              final targetPos =
                  (d.localPosition.dx / mapW) * totalTimelineUnits;
              _seekPlayhead(targetPos);
              if (_horizontalScrollController.hasClients) {
                final viewW = mapW;
                _horizontalScrollController.jumpTo(
                  (playheadPosition * _zoomX - viewW * 0.35).clamp(
                    0.0,
                    _horizontalScrollController.position.maxScrollExtent,
                  ),
                );
              }
            },
            onHorizontalDragUpdate: (d) {
              final targetPos =
                  (d.localPosition.dx / mapW) * totalTimelineUnits;
              _seekPlayhead(targetPos, retriggerAudio: false);
            },
            onHorizontalDragEnd: (_) => _seekPlayhead(playheadPosition),
            child: Stack(
              children: [
                for (int ti = 0; ti < tracks.length; ti++)
                  for (final c in trackClips[tracks[ti].id] ?? const <DawClip>[])
                    Positioned(
                      left: (c.start / totalTimelineUnits) * mapW,
                      width: max(2.0, (c.length / totalTimelineUnits) * mapW),
                      top: tracks.isEmpty
                          ? 2
                          : 2.0 + (ti / max(1, tracks.length)) * 18.0,
                      height: max(2.0, 16.0 / max(1, tracks.length)),
                      child: Container(
                        color: c.color.withValues(alpha: 0.75),
                      ),
                    ),
                Positioned(
                  left: (playheadPosition / totalTimelineUnits) * mapW,
                  top: 0,
                  bottom: 0,
                  width: 2,
                  child: Container(color: Colors.redAccent),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTimeline() {
    final double timelineUnits = _timelineTotalUnits;
    return Expanded(
      child: Column(
        children: [
          _buildTimelineMinimap(),
          Expanded(
            child: Container(
              color: bgDark,
              child: SingleChildScrollView(
                controller: _horizontalScrollController,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: max(MediaQuery.of(context).size.width, timelineUnits * _zoomX),
                  child: Column(
                    children: [
                      Container(
                        height: 40,
                        color: panelDark,
                        width: double.infinity,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            GestureDetector(
                              onTapDown: (d) => _seekPlayhead(
                                d.localPosition.dx / _zoomX,
                                snap: true,
                              ),
                              onDoubleTapDown: (d) {
                                double pos = (d.localPosition.dx / _zoomX)
                                    .clamp(0.0, timelineUnits);
                                if (snapToGrid) {
                                  pos = (pos / snapResolution).round() *
                                      snapResolution;
                                }
                                _showAddMarkerDialog(pos);
                              },
                              onSecondaryTapUp: (d) {
                                double pos = (d.localPosition.dx / _zoomX)
                                    .clamp(0.0, timelineUnits);
                                if (snapToGrid) {
                                  pos = (pos / snapResolution).round() *
                                      snapResolution;
                                }
                                final RenderBox overlay = Overlay.of(context)
                                    .context
                                    .findRenderObject() as RenderBox;
                                showMenu<String>(
                                  context: context,
                                  position: RelativeRect.fromRect(
                                    d.globalPosition & Size(40, 40),
                                    Offset.zero & overlay.size,
                                  ),
                                  items: [
                                    PopupMenuItem(
                                      value: 'add_marker',
                                      child: Text('Add Marker Here'),
                                    ),
                                    if (songMarkers.isNotEmpty)
                                      PopupMenuDivider(),
                                    ...songMarkers.map(
                                      (m) => PopupMenuItem(
                                        value: 'jump_${m.id}',
                                        child: Text('Jump to: ${m.label}'),
                                      ),
                                    ),
                                    if (songMarkers.isNotEmpty)
                                      PopupMenuDivider(),
                                    if (songMarkers.isNotEmpty)
                                      PopupMenuItem(
                                        value: 'clear_markers',
                                        child: Text(
                                          'Clear All Markers',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ),
                                  ],
                                ).then((val) {
                                  if (val == 'add_marker') {
                                    _showAddMarkerDialog(pos);
                                  } else if (val == 'clear_markers') {
                                    _saveState();
                                    setState(() => songMarkers.clear());
                                  } else if (val != null &&
                                      val.startsWith('jump_')) {
                                    final id = val.substring(5);
                                    final m = songMarkers
                                        .where((x) => x.id == id)
                                        .firstOrNull;
                                    if (m != null) {
                                      _seekPlayhead(m.position);
                                    }
                                  }
                                });
                              },
                              onPanUpdate: (d) => _seekPlayhead(
                                playheadPosition + (d.delta.dx / _zoomX),
                                retriggerAudio: false,
                              ),
                              onPanEnd: (d) => _seekPlayhead(
                                playheadPosition,
                                snap: true,
                              ),
                              child: CustomPaint(
                                painter: RulerPainter(
                                  zoomX: _zoomX,
                                  bpm: bpm,
                                  timeSigTop: timeSigTop,
                                  markers: songMarkers,
                                  tempoMarkers: tempoMarkers,
                                ),
                                size: Size(double.infinity, 40),
                              ),
                            ),
                      Positioned.fill(
                        child: TimelineLoopBar(
                          loopStart: loopStart,
                          loopEnd: loopEnd,
                          isLooping: isLooping,
                          zoomX: _zoomX,
                          beatWidth: beatWidth,
                          snapToGrid: snapToGrid,
                          snapResolution: snapResolution,
                          accentColor: lavenderAccent,
                          handleColor: textMain,
                          maxTimelineUnits: timelineUnits,
                          onDragStart: _saveState,
                          onToggleLoop: () =>
                              setState(() => isLooping = !isLooping),
                          onLoopRangeChanged: (newStart, newEnd) =>
                              setState(() {
                                loopStart = newStart;
                                loopEnd = newEnd;
                              }),
                        ),
                      ),
                    ],
                  ),
                ),
                TempoSignatureLane(
                  baseBpm: bpm.toDouble(),
                  baseNum: timeSigTop,
                  baseDen: timeSigBottom,
                  markers: tempoMarkers,
                  zoomX: _zoomX,
                  snapResolution: snapResolution,
                  snapToGrid: snapToGrid,
                  onAddOrUpdateMarker: (m) {
                    _saveState();
                    setState(() {
                      tempoMarkers.removeWhere((e) => e.id == m.id);
                      tempoMarkers.add(m);
                      tempoMarkers.sort(
                        (a, b) => a.position.compareTo(b.position),
                      );
                    });
                  },
                  onDeleteMarker: (id) {
                    _saveState();
                    setState(() {
                      tempoMarkers.removeWhere((e) => e.id == id);
                    });
                  },
                ),
                Expanded(
                  key: _timelineLaneListKey,
                  child: Stack(
                    children: [
                      ListView.builder(
                        padding: EdgeInsets.zero,
                        controller: _timelineScrollController,
                        itemCount: tracks.length,
                        itemBuilder: (context, index) {
                          final track = tracks[index];
                          if (!_isTrackVisibleInArrange(track)) {
                            return const SizedBox.shrink();
                          }
                          return Builder(
                            builder: (laneCtx) => DragTarget<SampleBrowserItem>(
                              onAcceptWithDetails: (details) {
                                final box = laneCtx.findRenderObject() as RenderBox?;
                                final localX = box != null
                                    ? box.globalToLocal(details.offset).dx
                                    : playheadPosition * _zoomX;
                                _addBrowserItemToTrack(
                                  details.data,
                                  targetTrack: track,
                                  startPos: (localX / _zoomX).clamp(
                                    0.0,
                                    timelineUnits,
                                  ),
                                );
                              },
                              builder: (ctx, cand, rej) => GestureDetector(
                            onTapDown: (d) => setState(() {
                              selectedClip = null;
                              multiSelectedClips.clear();
                              selectedTrackIndex = index;
                            }),
                            onSecondaryTapUp: (d) {
                              _seekPlayhead(d.localPosition.dx / _zoomX);
                              _showTimelineMenu(d.globalPosition);
                            },
                            onLongPressStart: (d) => setState(() {
                              isSelecting = true;
                              selectionStartDx = d.localPosition.dx / _zoomX;
                              selectionEndDx = d.localPosition.dx / _zoomX;
                              multiSelectedClips.clear();
                            }),
                            onLongPressMoveUpdate: (d) => setState(() {
                              selectionEndDx = d.localPosition.dx / _zoomX;
                              multiSelectedClips.clear();
                              double minX = min(
                                selectionStartDx!,
                                selectionEndDx!,
                              );
                              double maxX = max(
                                selectionStartDx!,
                                selectionEndDx!,
                              );
                              for (var t in tracks) {
                                for (var c in trackClips[t.id] ?? []) {
                                  if (c.start < maxX &&
                                      c.start + c.length > minX) {
                                    multiSelectedClips.add(c);
                                  }
                                }
                              }
                            }),
                            onLongPressEnd: (d) =>
                                setState(() => isSelecting = false),
                            onDoubleTapDown: (d) {
                              final double clickX = d.localPosition.dx / _zoomX;
                              final bool hitExisting =
                                  (trackClips[track.id] ?? []).any(
                                (c) =>
                                    clickX >= c.start &&
                                    clickX <= c.start + c.length,
                              );
                              if (hitExisting) return;
                              if (track.type == TrackType.midi ||
                                  track.type == TrackType.sampler) {
                                _saveState();
                                setState(() {
                                  double start = snapToGrid
                                      ? ((d.localPosition.dx / _zoomX) /
                                                    snapResolution)
                                                .round() *
                                            snapResolution
                                      : (d.localPosition.dx / _zoomX);
                                  final newClip = MidiClip(
                                    id: UniqueKey().toString(),
                                    start: start,
                                    length: beatWidth * timeSigTop,
                                    color: track.color,
                                  );
                                  if (!trackClips.containsKey(track.id)) {
                                    trackClips[track.id] = [];
                                  }
                                  trackClips[track.id]!.add(newClip);
                                  selectedClip = newClip;
                                  selectedBottomTab = 0;
                                });
                              }
                            },
                            child: Container(
                              height: track.showAutomation ? 140 : 100,
                              decoration: BoxDecoration(
                                color: (_dragTargetTrackId == track.id &&
                                        _dragTargetTrackId != _dragSourceTrackId)
                                    ? Colors.cyanAccent.withValues(alpha: 0.14)
                                    : (track.type == TrackType.group
                                          ? panelDark.withValues(alpha: 0.45)
                                          : null),
                                border: Border(
                                  bottom: BorderSide(
                                    color: (_dragTargetTrackId == track.id &&
                                            _dragTargetTrackId !=
                                                _dragSourceTrackId)
                                        ? Colors.cyanAccent
                                        : panelLight,
                                    width: 2,
                                  ),
                                ),
                              ),
                              child: Stack(
                                children: [
                                  ...(trackClips[track.id] ?? []).map(
                                    (clip) => _buildClip(track.id, clip),
                                  ),
                                  if (_dragTargetTrackId == track.id &&
                                      _dragTargetTrackId != _dragSourceTrackId)
                                    for (final ghostClip in _activeDragClips)
                                      if (_canMoveClipToTrack(ghostClip, track))
                                        Positioned(
                                          left: ghostClip.start * _zoomX,
                                          top: 10,
                                          bottom: 10,
                                          width: ghostClip.length * _zoomX,
                                          child: IgnorePointer(
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: track.color.withValues(
                                                  alpha: 0.45,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: Colors.cyanAccent,
                                                  width: 1.5,
                                                ),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              child: Text(
                                                ghostClip.name.isNotEmpty
                                                    ? ghostClip.name
                                                    : 'Clip',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                  if (isSelecting &&
                                      selectionStartDx != null &&
                                      selectionEndDx != null)
                                    Positioned(
                                      left:
                                          min(
                                            selectionStartDx!,
                                            selectionEndDx!,
                                          ) *
                                          _zoomX,
                                      width:
                                          (selectionEndDx! - selectionStartDx!)
                                              .abs() *
                                          _zoomX,
                                      top: 0,
                                      bottom: 0,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.blueAccent.withOpacity(
                                            0.3,
                                          ),
                                          border: Border.all(
                                            color: Colors.blueAccent,
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (track.type == TrackType.audio &&
                                      isRecording &&
                                      track.isArmed &&
                                      recordingStartPos != null)
                                    Positioned(
                                      left: recordingStartPos! * _zoomX,
                                      top: 20,
                                      bottom: 20,
                                      width: max(
                                        10.0,
                                        (playheadPosition -
                                                recordingStartPos!) *
                                            _zoomX,
                                      ),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.redAccent.withOpacity(
                                            0.5,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text('Recording...'),
                                        ),
                                      ),
                                    ),
                                  if (track.showAutomation)
                                    Positioned.fill(
                                      child: AutomationLaneOverlay(
                                        track: track,
                                        laneHeight: 140.0,
                                        zoomX: _zoomX,
                                        snapResolution: snapResolution,
                                        snapToGrid: snapToGrid,
                                        onSaveState: _saveState,
                                        onChanged: () => setState(() {}),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                      ),
                      Positioned(
                        left: playheadPosition * _zoomX - 10,
                        top: 0,
                        bottom: 0,
                        width: 22,
                        child: GestureDetector(
                          onPanUpdate: (d) => _seekPlayhead(
                            playheadPosition + (d.delta.dx / _zoomX),
                            retriggerAudio: false,
                          ),
                          onPanEnd: (_) => _seekPlayhead(
                            playheadPosition,
                            snap: true,
                          ),
                          child: Container(
                            color: Colors.transparent,
                            alignment: Alignment.center,
                            child: Container(width: 2, color: Colors.red),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
        ),
      ],
    ),
    );
  }

  double _bottomPanelHeight = 300.0;

  void _addEffectToTrack(String val) {
    setState(() {
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
                setState(() {
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
                        onPressed: () => setState(() {
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
                        onPressed: () => setState(() {
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
      onTap: () => setState(() => selectedBottomTab = index),
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
    _saveState();
    setState(() {
      if (presetName == 'Clear Chain') {
        track.effectsChain.clear();
      } else if (presetName == 'Crunch Guitar') {
        track.effectsChain = [
          DawEffect('EQ', {'Low': 0.45, 'Mid': 0.65, 'High': 0.60}),
          DawEffect('Overdrive', {
            'Drive': 0.62,
            'Tone': 0.55,
            'Level': 0.70,
          }),
          DawEffect('GuitarAmp', {'Gain': 0.65, 'Reverb': 0.35}),
        ];
      } else if (presetName == 'Vocal Polish') {
        track.effectsChain = [
          DawEffect('EQ', {'Low': 0.35, 'Mid': 0.55, 'High': 0.72}),
          DawEffect('Compressor', {'Thresh': 0.45, 'Ratio': 0.55}),
          DawEffect('Reverb', {'Mix': 0.25, 'Size': 0.55}),
        ];
      } else if (presetName == 'Lo-Fi Tape') {
        track.effectsChain = [
          DawEffect('EQ', {'Low': 0.55, 'Mid': 0.60, 'High': 0.25}),
          DawEffect('Echo', {'Mix': 0.25, 'Delay': 0.35, 'Decay': 0.40}),
          DawEffect('Compressor', {'Thresh': 0.35, 'Ratio': 0.70}),
        ];
      } else if (presetName == 'Wide Ambient') {
        track.effectsChain = [
          DawEffect('Reverb', {'Mix': 0.65, 'Size': 0.85}),
          DawEffect('Echo', {'Mix': 0.45, 'Delay': 0.50, 'Decay': 0.65}),
        ];
      }
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
                    setState(() => selectedMidiNotes = notes),
                onChangeStart: _saveState,
                onNotesChanged: () {
                  _syncLinkedMidiClips(midiClip);
                  setState(() {});
                },
                onSynthSettingsChanged: () {
                  if (t != null) _updateTrackFilters(t);
                  setState(() {});
                },
                onZoomIn: () => setState(() => _midiZoomMultiplier += 0.2),
                onZoomOut: () => setState(
                  () =>
                      _midiZoomMultiplier = max(0.2, _midiZoomMultiplier - 0.2),
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
          onTrackVolumeChanged: (t, v) {
            setState(() => t.volume = v);
            if (_isSoloudReady) {
              for (final c in trackClips[t.id] ?? []) {
                if (c is AudioClip && c.currentHandle != null) {
                  try {
                    SoLoud.instance.setVolume(
                      c.currentHandle!,
                      (_effectiveTrackVolume(t) *
                              _computeClipEnvelope(c, playheadPosition, track: t))
                          .clamp(0.0, 2.5),
                    );
                  } catch (_) {}
                }
              }
            }
            _syncTrackMonitoringHandles();
          },
          onTrackPanChanged: (t, v) {
            setState(() => t.pan = v);
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
            setState(() => t.reverbSend = v);
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
            setState(() => t.delaySend = v);
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
            setState(() => t.reverbPreFader = !t.reverbPreFader);
          },
          onToggleDelayPreFader: (t) {
            _saveState();
            setState(() => t.delayPreFader = !t.delayPreFader);
          },
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
          onAuxReverbMixChanged: (v) {
            setState(() => auxReverbMix = v);
            _syncMasterAndAuxFilters();
          },
          onAuxDelayMixChanged: (v) {
            setState(() => auxDelayMix = v);
            _syncMasterAndAuxFilters();
          },
          onToggleAuxReverbSolo: () =>
              setState(() => auxReverbSolo = !auxReverbSolo),
          onToggleAuxDelaySolo: () =>
              setState(() => auxDelaySolo = !auxDelaySolo),
          onMasterVolumeChanged: (v) {
            setState(() => masterVolume = v);
            _syncMasterAndAuxFilters();
          },
          onToggleMasterLimiter: () {
            _saveState();
            setState(() => masterLimiter = !masterLimiter);
            _syncMasterAndAuxFilters();
          },
          onCycleLufsTarget: () {
            setState(() {
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
            setState(() {
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
              setState(() => _isMasterFxSelected = !_isMasterFxSelected),
          onSaveState: _saveState,
          onInputDeviceChanged: (newValue) {
            if (newValue != null) {
              setState(() {
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
            setState(() {
              _tunerEnabled = !_tunerEnabled;
              _detectedPitch = null;
              _tunerTracker.reset();
            });
            await _updateMicState();
          },
          onNoiseGateChanged: (v) =>
              setState(() => fxTrack.noiseGateThreshold = v),
          onReorderEffect: (oldIndex, newIndex) {
            if (newIndex > oldIndex) newIndex -= 1;
            _saveState();
            setState(() {
              final item = fxTrack.effectsChain.removeAt(oldIndex);
              fxTrack.effectsChain.insert(newIndex, item);
              syncFx();
            });
          },
          onRemoveEffect: (idx) {
            _saveState();
            setState(() {
              fxTrack.effectsChain.removeAt(idx);
              syncFx();
            });
          },
          onToggleBypass: (fx) {
            _saveState();
            setState(() {
              fx.isBypassed = !fx.isBypassed;
              syncFx();
            });
          },
          onParamChanged: (fx, k, v) {
            setState(() {
              fx.parameters[k] = v;
              syncFx();
            });
          },
          onSidechainChanged: (fx, sourceId) {
            _saveState();
            setState(() {
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
            onStateChanged: () { _saveState(); setState(() {}); },
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
                final vol = tr != null
                    ? (_effectiveTrackVolume(tr) *
                            _computeClipEnvelope(
                              activeAudioClip,
                              playheadPosition,
                              track: tr,
                            ))
                        .clamp(0.0, 2.5)
                    : activeAudioClip.gain.clamp(0.0, 2.5);
                SoLoud.instance.setVolume(activeAudioClip.currentHandle!, vol);
              } catch (_) {}
            }
            setState(() {});
          },
          onSplitClip: (splitPos) =>
              _splitClipAtTimelinePos(ownerId, activeAudioClip, splitPos),
          isPlaying: isPlaying,
          onPlayPause: _togglePlay,
          onNormalize: () => _normalizeAudioClip(activeAudioClip),
          onReverse: () async {
            _saveState();
            await activeAudioClip.toggleReverse();
            setState(() {});
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
            print('Failed to load pasted audio clip: $e');
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
