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

  bool isLooping = false;
  double loopStart = 0.0;
  double loopEnd = 400.0;

  late final AudioRecorder _audioRecorder;
  String? _currentRecordPath;
  StreamSubscription<Uint8List>? _micStreamSub;
  AudioSource? _micSource;
  WavWriter? _wavWriter;
  final FocusNode _focusNode = FocusNode();
  final FocusNode _bpmFocus = FocusNode();
  final List<DateTime> _tapTimestamps = [];

  final ScrollController _headerScrollController = ScrollController();
  final ScrollController _timelineScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  bool _isSyncingScroll = false;
  int? _draggingAutoPointIndex;
  String? _draggingAutoTrackId;

  List<String> undoStack = [];
  List<String> redoStack = [];

  final MidiCommand _midiCommand = MidiCommand();
  StreamSubscription? _midiSubscription;
  List<MidiDevice> _midiDevices = [];

  List<InputDevice> _inputDevices = [];
  InputDevice? _selectedInputDevice;

  Future<void> _writeAutoSave() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dawDir = Directory('${dir.path}/FyrDAW');
      if (!dawDir.existsSync()) dawDir.createSync(recursive: true);
      final file = File('${dawDir.path}/autosave.json');
      await file.writeAsString(_getCurrentStateJson());
    } catch (_) {}
  }

  Future<void> _clearAutoSave() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/FyrDAW/autosave.json');
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
    final file = File('${dir.path}/FyrDAW/autosave.json');
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
          if (t.bus != null) {
            try { t.bus!.dispose(); } catch (_) {}
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
      if (t.bus != null) {
        try { t.bus!.dispose(); } catch (_) {}
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
      if (track.type == TrackType.midi && track.synthSourcePath != null) {
        if (SoLoud.instance.isInitialized) {
          try {
            if (track.synthSourcePath!.startsWith('assets/')) {
              track.synthSource = null;
            } else {
              track.synthSource = await SoLoud.instance.loadFile(
                track.synthSourcePath!,
              );
            }
            _updateTrackFilters(track);
          } catch (_) {}
        }
      }
      for (var c in trackClips[track.id] ?? []) {
        if (c is AudioClip && SoLoud.instance.isInitialized) {
          try {
            c.source = await SoLoud.instance.loadFile(c.filePath);
          } catch (_) {}
        }
      }
      if (track.type == TrackType.sampler) {
        for (var pad in track.samplerPads.values) {
          if (pad.filePath != null && SoLoud.instance.isInitialized) {
            try {
              pad.source = await SoLoud.instance.loadFile(pad.filePath!);
              pad.source!.filters.pitchShiftFilter.activate();
              pad.extractWaveform();
            } catch (_) {}
          }
        }
      }
    }
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

  final Map<int, List<SoundHandle>> _activeMidiNotes = {};
  final Map<int, _RecordingNote> _recordingMidiNotes = {};

  void _changeInstrument(Track track, int v) async {
    final dir = await getProjectMediaDirectory();
    String path;
    switch (v) {
      case 1:
        path = '${dir.path}/saw_v2.wav';
        break;
      case 2:
        path = '${dir.path}/sine_v2.wav';
        break;
      case 3:
        path = 'assets/samples/piano_c4.wav';
        break;
      case 4:
        path = 'assets/samples/cello_c3.wav';
        break;
      case 5:
        path = 'assets/samples/violin_c4.wav';
        break;
      default:
        path = '${dir.path}/synth_v2.wav';
        break;
    }
    track.synthSourcePath = path;
    if (SoLoud.instance.isInitialized) {
      if (track.synthSource != null) {
        try {
          SoLoud.instance.disposeSource(track.synthSource!);
        } catch (_) {}
      }
      if (v >= 3 && v <= 5) {
        track.synthSource = null;
      } else {
        track.synthSource = await SoLoud.instance.loadFile(path);
      }
      try {
        track.bus!.filters.echoFilter.deactivate();
      } catch (_) {}
      try {
        track.bus!.filters.robotizeFilter.deactivate();
      } catch (_) {}
      try {
        track.bus!.filters.compressorFilter.deactivate();
      } catch (_) {}
      try {
        track.bus!.filters.biquadFilter.deactivate();
      } catch (_) {}
      try {
        track.bus!.filters.parametricEqFilter.deactivate();
      } catch (_) {}
      try {
        track.bus!.filters.waveShaperFilter.deactivate();
      } catch (_) {}
      try {
        track.bus!.filters.flangerFilter.deactivate();
      } catch (_) {}
      try {
        track.bus!.filters.freeverbFilter.deactivate();
      } catch (_) {}
      try {
        track.bus!.filters.lofiFilter.deactivate();
      } catch (_) {}
      try {
        track.bus!.filters.bassBoostFilter.deactivate();
      } catch (_) {}

      for (var fx in track.effectsChain) {
        try {
          if (fx.name == 'Reverb') track.bus!.filters.echoFilter.activate();
          if (fx.name == 'Distortion') {
            track.bus!.filters.robotizeFilter.activate();
          }
          if (fx.name == 'Compressor') {
            track.bus!.filters.compressorFilter.activate();
          }
          if (fx.name == 'EQ') track.bus!.filters.biquadFilter.activate();
          if (fx.name == '3-Band EQ') {
            track.bus!.filters.parametricEqFilter.activate();
          }
          if (fx.name == 'Echo') track.bus!.filters.echoFilter.activate();
          if (fx.name == 'Flanger') track.bus!.filters.flangerFilter.activate();
          if (fx.name == 'Chorus') track.bus!.filters.freeverbFilter.activate();
          if (fx.name == 'Lofi') track.bus!.filters.lofiFilter.activate();
          if (fx.name == 'Robotize') {
            track.bus!.filters.robotizeFilter.activate();
          }
          if (fx.name == 'Bass Boost') {
            track.bus!.filters.bassBoostFilter.activate();
          }
        } catch (_) {}
      }
    }
    setState(() {
      track.instrumentIndex = v;
    });
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
    final instruments = [
      {
        'index': 0,
        'name': 'Square Lead',
        'desc': 'Retro arcade square wave.',
        'icon': Icons.gamepad,
      },
      {
        'index': 1,
        'name': 'Sawtooth Bass',
        'desc': 'Gritty electronic bass.',
        'icon': Icons.waves,
      },
      {
        'index': 2,
        'name': 'Sine Sub',
        'desc': 'Deep, pure sub-bass.',
        'icon': Icons.blur_on,
      },
      {
        'index': 3,
        'name': 'Piano',
        'desc': 'Synthesized acoustic piano.',
        'icon': Icons.piano,
      },
      {
        'index': 4,
        'name': 'Cello',
        'desc': 'Rich bowed strings.',
        'icon': Icons.music_note,
      },
      {
        'index': 5,
        'name': 'Violin',
        'desc': 'Bright orchestral violin.',
        'icon': Icons.music_note,
      },
    ];

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
                  'Select Instrument',
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
                    itemCount: instruments.length,
                    itemBuilder: (context, index) {
                      final inst = instruments[index];
                      return InkWell(
                        onTap: () {
                          Navigator.of(context).pop();
                          _changeInstrument(track, inst['index'] as int);
                        },
                        child: Container(
                          margin: EdgeInsets.only(bottom: 12),
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: panelLight,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: track.instrumentIndex == inst['index']
                                  ? lavenderAccent
                                  : textFaint,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                inst['icon'] as IconData,
                                color: lavenderAccent,
                                size: 32,
                              ),
                              SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      inst['name'] as String,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      inst['desc'] as String,
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

  void _handleMidiNoteOn(int note, int velocity, String? deviceId) {
    if (isRecording) {
      for (var t in tracks) {
        if (t.isArmed &&
            (t.midiInputId == null || t.midiInputId == deviceId) &&
            (t.type == TrackType.midi || t.type == TrackType.sampler)) {
          var clips = trackClips[t.id] ?? [];
          var activeClip = clips
              .where(
                (c) =>
                    c.start <= playheadPosition &&
                    c.start + c.length >= playheadPosition,
              )
              .firstOrNull;
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
      if (track.type == TrackType.midi) {
        AudioSource src = track.synthSource ?? globalSynthSound!;
        if (track.synthSource == null) {
          if (track.instrumentIndex == 1) {
            src = globalSawSound!;
          } else if (track.instrumentIndex == 2)
            src = globalSineSound!;
          else if (track.instrumentIndex == 3)
            src = globalPianoSound!;
          else if (track.instrumentIndex == 4)
            src = globalCelloSound!;
          else if (track.instrumentIndex == 5)
            src = globalViolinSound!;
        }
        double volMultiplier = 1.0;
        if (track.instrumentIndex == 3) {
          volMultiplier = 3.0;
        } else if (track.instrumentIndex == 4)
          volMultiplier = 2.0;
        else if (track.instrumentIndex == 5)
          volMultiplier = 1.5;
        final handle = track.bus!.play(
          src,
          volume: (velocity / 127.0) * volMultiplier * track.volume,
        );
        SoLoud.instance.setLooping(handle, true);
        if (track.instrumentIndex >= 3) {
          SoLoud.instance.setLoopPoint(
            handle,
            const Duration(milliseconds: 500),
          );
        }
        int basePitch = 69;
        if (track.instrumentIndex == 3) {
          basePitch = 60;
        } else if (track.instrumentIndex == 4)
          basePitch = 48;
        else if (track.instrumentIndex == 5)
          basePitch = 60;
        double rate = pow(2.0, (note - basePitch) / 12.0).toDouble();
        SoLoud.instance.setRelativePlaySpeed(handle, rate);
        _activeMidiNotes.putIfAbsent(note, () => []).add(handle);
        track.activeMidiHandles.removeWhere(
          (h) => !SoLoud.instance.getIsValidVoiceHandle(h),
        );
        track.activeMidiHandles.add(handle);
      } else if (track.type == TrackType.sampler) {
        var pad = track.samplerPads.values
            .where((p) => p.midiNote == note)
            .firstOrNull;
        if (pad != null) {
          pad.play(velocity.toDouble());
        }
      }
    }
  }

  void _handleMidiNoteOff(int note) {
    if (isRecording && _recordingMidiNotes.containsKey(note)) {
      var r = _recordingMidiNotes[note]!;
      double len = playheadPosition - r.absoluteStartPlayhead;
      if (len < beatWidth / 8) len = beatWidth / 8;
      r.note.length = len;
      _recordingMidiNotes.remove(note);
    }

    if (_activeMidiNotes.containsKey(note)) {
      for (var h in _activeMidiNotes[note]!) {
        try {
          SoLoud.instance.stop(h);
        } catch (_) {}
      }
      _activeMidiNotes.remove(note);
    }
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
    try {
      final dir = await getApplicationDocumentsDirectory();
      final outPath =
          '${dir.path}/export_${DateTime.now().millisecondsSinceEpoch}.wav';
      List<String> inputs = [];
      List<String> filterComplex = [];
      int inputIndex = 0;

      for (var t in tracks) {
        if (t.type == TrackType.audio && !t.isMuted) {
          for (var c in trackClips[t.id] ?? []) {
            if (c is AudioClip) {
              inputs.add('-i');
              inputs.add(c.filePath);
              int delayMs = (c.start * 10).toInt();
              filterComplex.add(
                '[$inputIndex]adelay=$delayMs|$delayMs[a$inputIndex];',
              );
              inputIndex++;
            }
          }
        }
      }
      if (inputIndex == 0) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No audio clips to export!')));
        return;
      }
      String mixArgs = '';
      for (int i = 0; i < inputIndex; i++) {
        mixArgs += '[a$i]';
      }
      mixArgs += 'amix=inputs=$inputIndex:duration=longest[out]';
      filterComplex.add(mixArgs);

      List<String> args = [
        ...inputs,
        '-filter_complex',
        filterComplex.join(' '),
        '-map',
        '[out]',
        outPath,
      ];
      final res = await Process.run('ffmpeg', args);
      if (res.exitCode == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported to $outPath'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: ${res.stderr}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export error: $e'),
          backgroundColor: Colors.red,
        ),
      );
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
        '--title=Save fyrDAW Project',
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
            if (padData['filePath'] != null) {
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
            if (pad.filePath != null && !addedFiles.contains(pad.filePath!)) {
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

          tracks.clear();
          if (projectData['tracks'] != null) {
            for (var t in projectData['tracks']) {
              if (t['type'] == TrackType.sampler.index &&
                  t['samplerPads'] != null) {
                (t['samplerPads'] as Map).forEach((k, v) {
                  if (v['filePath'] != null) {
                    if (!v['filePath'].startsWith('/')) {
                      v['filePath'] = '${mediaDir.path}/${v['filePath']}';
                    }
                  }
                });
              }
              var track = Track.fromJson(t);
              if (track.type == TrackType.midi) {
                getProjectMediaDirectory().then((dir) async {
                  String spath = track.instrumentIndex == 1
                      ? '${dir.path}/saw_v2.wav'
                      : (track.instrumentIndex == 2
                            ? '${dir.path}/sine_v2.wav'
                            : '${dir.path}/synth_v2.wav');
                  if (track.instrumentIndex == 3)
                    spath = 'assets/samples/piano_c4.wav';
                  if (track.instrumentIndex == 4)
                    spath = 'assets/samples/cello_c3.wav';
                  if (track.instrumentIndex == 5)
                    spath = 'assets/samples/violin_c4.wav';

                  track.synthSourcePath = spath;
                  if (SoLoud.instance.isInitialized) {
                    if (track.instrumentIndex >= 3 &&
                        track.instrumentIndex <= 5) {
                      track.synthSource = null;
                    } else {
                      track.synthSource = await SoLoud.instance.loadFile(
                        track.synthSourcePath!,
                      );
                    }
                  }
                });
              }
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
              if (pad.filePath != null && SoLoud.instance.isInitialized) {
                try {
                  pad.source = await SoLoud.instance.loadFile(pad.filePath!);
                  pad.source!.filters.pitchShiftFilter.activate();
                  pad.extractWaveform();
                } catch (_) {}
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

        final newTrack = Track(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: path.split('/').last,
          type: TrackType.audio,
        );

        final src = await SoLoud.instance.loadFile(path);
        final lengthSecs = SoLoud.instance.getLength(src);
        final clip = AudioClip(
          start: playheadPosition,
          length: lengthSecs.inMilliseconds * 100.0 / 1000.0,
          color: lavenderAccent,
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

      for (var t in tracks) {
        if (t.type == TrackType.audio && !t.isMuted) {
          List<String> inputs = [];
          List<String> filterComplex = [];
          int inputIndex = 0;
          for (var c in trackClips[t.id] ?? []) {
            if (c is AudioClip) {
              inputs.add('-i');
              inputs.add(c.filePath);
              int delayMs = (c.start * 10).toInt();
              filterComplex.add(
                '[$inputIndex]adelay=$delayMs|$delayMs[a$inputIndex];',
              );
              inputIndex++;
            }
          }
          if (inputIndex > 0) {
            String mixArgs = '';
            for (int i = 0; i < inputIndex; i++) {
              mixArgs += '[a$i]';
            }
            mixArgs += 'amix=inputs=$inputIndex:duration=longest[out]';
            filterComplex.add(mixArgs);
            final outPath = '$folderPath/${t.name.replaceAll(' ', '_')}.wav';
            List<String> args = [
              ...inputs,
              '-filter_complex',
              filterComplex.join(' '),
              '-map',
              '[out]',
              outPath,
            ];
            await Process.run('ffmpeg', args);
            anyExported = true;
          }
        }
      }

      if (anyExported) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Stems exported to $folderPath'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No active audio tracks to export!')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export Stems error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _audioRecorder = AudioRecorder();
    _initInputDevices();
    _checkAutoSave();
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
      if (status == 0x90 && velocity > 0) {
        _handleMidiNoteOn(note, velocity, packet.device.id);
      } else if (status == 0x80 || (status == 0x90 && velocity == 0)) {
        _handleMidiNoteOff(note);
      }
    });
  }

  Future<void> _initInputDevices() async {
    try {
      final devices = await _audioRecorder.listInputDevices();
      setState(() {
        _inputDevices = devices;
        if (_inputDevices.isNotEmpty) {
          _selectedInputDevice = _inputDevices.first;
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    playTimer?.cancel();
    _audioRecorder.dispose();
    _focusNode.dispose();
    _bpmFocus.dispose();
    _headerScrollController.dispose();
    _timelineScrollController.dispose();
    _midiSubscription?.cancel();
    super.dispose();
  }

  @override
  void onWindowClose() async {
    await _promptSaveAndExecute(() async {
      await _clearAutoSave();
      await windowManager.destroy();
    });
  }

  void _updateTrackFilters(Track track) {
    if (track.bus == null) return;
    try {
      track.bus!.filters.echoFilter.deactivate();
    } catch (_) {}
    try {
      track.bus!.filters.robotizeFilter.deactivate();
    } catch (_) {}
    try {
      track.bus!.filters.compressorFilter.deactivate();
    } catch (_) {}
    try {
      track.bus!.filters.biquadFilter.deactivate();
    } catch (_) {}
    try {
      track.bus!.filters.parametricEqFilter.deactivate();
    } catch (_) {}
    try {
      track.bus!.filters.waveShaperFilter.deactivate();
    } catch (_) {}
    try {
      track.bus!.filters.flangerFilter.deactivate();
    } catch (_) {}
    try {
      track.bus!.filters.freeverbFilter.deactivate();
    } catch (_) {}
    try {
      track.bus!.filters.lofiFilter.deactivate();
    } catch (_) {}
    try {
      track.bus!.filters.bassBoostFilter.deactivate();
    } catch (_) {}

    for (var fx in track.effectsChain) {
      try {
        if (fx.name == 'Reverb') {
          track.bus!.filters.freeverbFilter.activate();
          track.bus!.filters.freeverbFilter.wet().value = fx.parameters['Mix']!;
          track.bus!.filters.freeverbFilter.roomSize().value =
              fx.parameters['Size']!;
          track.bus!.filters.freeverbFilter.damp().value =
              fx.parameters['Decay']!;
        } else if (fx.name == 'Compressor') {
          track.bus!.filters.compressorFilter.activate();
          track.bus!.filters.compressorFilter.wet().value =
              fx.parameters['Mix']!;
          track.bus!.filters.compressorFilter.threshold().value =
              fx.parameters['Thresh']! * -60;
          track.bus!.filters.compressorFilter.ratio().value =
              1 + (fx.parameters['Ratio']! * 20);
        } else if (fx.name == 'EQ') {
          track.bus!.filters.parametricEqFilter.activate();
          track.bus!.filters.parametricEqFilter.numBands().value = 3;
          track.bus!.filters.parametricEqFilter.bandGain(0).value =
              fx.parameters['Low']! * 4;
          track.bus!.filters.parametricEqFilter.bandGain(1).value =
              fx.parameters['Mid']! * 4;
          track.bus!.filters.parametricEqFilter.bandGain(2).value =
              fx.parameters['High']! * 4;
        } else if (fx.name == 'TubeScreamer' || fx.name == 'GuitarAmp') {
          track.bus!.filters.waveShaperFilter.activate();
          track.bus!.filters.waveShaperFilter.wet().value =
              fx.parameters['Mix'] ?? fx.parameters['Level'] ?? 0.5;
          track.bus!.filters.waveShaperFilter.amount().value =
              (fx.parameters['Drive'] ?? 0.5) * 10;
        } else if (fx.name == 'Echo') {
          track.bus!.filters.echoFilter.activate();
          track.bus!.filters.echoFilter.wet().value = fx.parameters['Mix']!;
          track.bus!.filters.echoFilter.delay().value = fx.parameters['Delay']!;
          track.bus!.filters.echoFilter.decay().value = fx.parameters['Decay']!;
        } else if (fx.name == 'Flanger') {
          track.bus!.filters.flangerFilter.activate();
          track.bus!.filters.flangerFilter.wet().value = fx.parameters['Mix']!;
          track.bus!.filters.flangerFilter.delay().value =
              fx.parameters['Delay']!;
          track.bus!.filters.flangerFilter.freq().value =
              fx.parameters['Rate']! * 10;
        } else if (fx.name == 'Chorus') {
          track.bus!.filters.flangerFilter.activate();
          track.bus!.filters.flangerFilter.wet().value = fx.parameters['Mix']!;
          track.bus!.filters.flangerFilter.delay().value =
              0.02 + (fx.parameters['Depth']! * 0.03);
          track.bus!.filters.flangerFilter.freq().value =
              fx.parameters['Rate']! * 5;
        } else if (fx.name == 'Lofi') {
          track.bus!.filters.lofiFilter.activate();
          track.bus!.filters.lofiFilter.wet().value = fx.parameters['Mix']!;
          track.bus!.filters.lofiFilter.samplerate().value =
              1000 + (fx.parameters['Rate']! * 8000);
          track.bus!.filters.lofiFilter.bitdepth().value =
              1 + (fx.parameters['Bits']! * 15);
        } else if (fx.name == 'Robotize') {
          track.bus!.filters.robotizeFilter.activate();
          track.bus!.filters.robotizeFilter.wet().value = fx.parameters['Mix']!;
          track.bus!.filters.robotizeFilter.frequency().value =
              10 + (fx.parameters['Freq']! * 100);
        } else if (fx.name == 'BassBoost') {
          track.bus!.filters.bassBoostFilter.activate();
          track.bus!.filters.bassBoostFilter.wet().value =
              fx.parameters['Mix']!;
          track.bus!.filters.bassBoostFilter.boost().value =
              fx.parameters['Boost']! * 10;
        }
      } catch (e) {
        print('Error updating filter: $e');
      }
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

  Future<void> _togglePlay() async {
    if (!isPlaying) {
      final dir = await getProjectMediaDirectory();
      for (var track in tracks) {
        if (track.type == TrackType.midi) {
          String path = track.instrumentIndex == 1
              ? '${dir.path}/saw_v2.wav'
              : (track.instrumentIndex == 2
                    ? '${dir.path}/sine_v2.wav'
                    : '${dir.path}/synth_v2.wav');
          if (track.instrumentIndex == 3) path = 'assets/samples/piano_c4.wav';
          if (track.instrumentIndex == 4) path = 'assets/samples/cello_c3.wav';
          if (track.instrumentIndex == 5) path = 'assets/samples/violin_c4.wav';

          if (track.synthSourcePath != path ||
              (track.synthSource == null && track.instrumentIndex < 3)) {
            if (track.synthSource != null) {
              try {
                SoLoud.instance.disposeSource(track.synthSource!);
              } catch (_) {}
            }
            try {
              if (track.instrumentIndex >= 3 && track.instrumentIndex <= 5) {
                track.synthSource = null;
              } else {
                track.synthSource = await SoLoud.instance.loadFile(path);
              }
              track.synthSourcePath = path;
            } catch (e) {
              print('Failed to load synth source: $e');
            }
          }
        }
      }
    }

    setState(() {
      isPlaying = !isPlaying;
      if (isPlaying) {
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

        bool anySolo = tracks.any((t) => t.isSolo);
        for (var track in tracks) {
          if (track.isMuted) continue;
          if (anySolo && !track.isSolo) continue;

          if (track.type == TrackType.midi && track.synthSource != null) {
            try {
              track.synthSource!.filters.echoFilter.deactivate();
            } catch (_) {}
            try {
              track.synthSource!.filters.robotizeFilter.deactivate();
            } catch (_) {}
            try {
              track.synthSource!.filters.compressorFilter.deactivate();
            } catch (_) {}
            try {
              track.synthSource!.filters.biquadFilter.deactivate();
            } catch (_) {}
            try {
              track.synthSource!.filters.parametricEqFilter.deactivate();
            } catch (_) {}
            for (var fx in track.effectsChain) {
              try {
                if (fx.name == 'Reverb') {
                  track.synthSource!.filters.echoFilter.activate();
                }
                if (fx.name == 'Distortion') {
                  track.synthSource!.filters.robotizeFilter.activate();
                }
                if (fx.name == 'Compressor') {
                  track.synthSource!.filters.compressorFilter.activate();
                }
                if (fx.name == 'EQ') {
                  track.synthSource!.filters.parametricEqFilter.activate();
                }
              } catch (_) {}
            }
          }

          for (var clip in trackClips[track.id] ?? []) {
            if (clip is AudioClip && clip.source != null) {
              try {
                clip.source!.filters.echoFilter.deactivate();
              } catch (_) {}
              try {
                clip.source!.filters.robotizeFilter.deactivate();
              } catch (_) {}
              try {
                clip.source!.filters.compressorFilter.deactivate();
              } catch (_) {}
              try {
                clip.source!.filters.biquadFilter.deactivate();
              } catch (_) {}
              try {
                clip.source!.filters.parametricEqFilter.deactivate();
              } catch (_) {}
              try {
                clip.source!.filters.waveShaperFilter.deactivate();
              } catch (_) {}
              try {
                clip.source!.filters.biquadFilter.deactivate();
              } catch (_) {}

              for (var fx in track.effectsChain) {
                try {
                  if (fx.name == 'Reverb') {
                    clip.source!.filters.echoFilter.activate();
                  }
                  if (fx.name == 'Compressor') {
                    clip.source!.filters.compressorFilter.activate();
                  }
                  if (fx.name == 'EQ') {
                    clip.source!.filters.parametricEqFilter.activate();
                  }
                  if (fx.name == 'TubeScreamer') {
                    clip.source!.filters.waveShaperFilter.activate();
                    clip.source!.filters.biquadFilter.activate();
                  }
                } catch (_) {}
              }

              if (playheadPosition >= clip.start &&
                  playheadPosition < clip.start + clip.length) {
                double offsetMs =
                    (playheadPosition - clip.start + clip.startOffset) * 10.0;
                clip.currentHandle = track.bus!.play(
                  clip.source!,
                  volume: track.volume,
                  pan: track.pan,
                );
                SoLoud.instance.seek(
                  clip.currentHandle!,
                  Duration(milliseconds: offsetMs.toInt()),
                );
              }
            }
          }
        }

        playTimer = Timer.periodic(Duration(milliseconds: 50), (timer) {
          setState(() {
            double oldPos = playheadPosition;
            playheadPosition += 5.0;

            if (isMetronomeEnabled &&
                globalSawSound != null &&
                SoLoud.instance.isInitialized) {
              int oldBeat = (oldPos / beatWidth).floor();
              int newBeat = (playheadPosition / beatWidth).floor();
              if (newBeat > oldBeat) {
                bool isDownbeat = newBeat % timeSigTop == 0;
                double speed = isDownbeat ? 4.0 : 2.0;
                double volume = isDownbeat ? 0.3 : 0.1;
                try {
                  final h = SoLoud.instance.play(
                    globalSawSound!,
                    volume: volume,
                  );
                  SoLoud.instance.setRelativePlaySpeed(h, speed);
                  Timer(Duration(milliseconds: 50), () {
                    if (SoLoud.instance.getIsValidVoiceHandle(h)) {
                      SoLoud.instance.stop(h);
                    }
                  });
                } catch (_) {}
              }
            }

            bool anySolo = tracks.any((t) => t.isSolo);
            for (var track in tracks) {
              double autoVol = track.getInterpolatedAutomation(
                'Volume',
                playheadPosition,
              );
              if (autoVol >= 0.0) {
                track.volume = autoVol;
                for (var c in trackClips[track.id] ?? []) {
                  if (c is AudioClip &&
                      c.currentHandle != null &&
                      SoLoud.instance.getIsValidVoiceHandle(c.currentHandle!)) {
                    try {
                      SoLoud.instance.setVolume(c.currentHandle!, track.volume);
                    } catch (_) {}
                  }
                }
              }
              double autoPan = track.getInterpolatedAutomation(
                'Pan',
                playheadPosition,
              );
              if (autoPan >= 0.0) {
                track.pan = (autoPan * 2.0) - 1.0;
                for (var c in trackClips[track.id] ?? []) {
                  if (c is AudioClip &&
                      c.currentHandle != null &&
                      SoLoud.instance.getIsValidVoiceHandle(c.currentHandle!)) {
                    try {
                      SoLoud.instance.setPan(c.currentHandle!, track.pan);
                    } catch (_) {}
                  }
                }
              }

              if (track.isMuted) continue;
              if (anySolo && !track.isSolo) continue;

              for (var fx in track.effectsChain) {
                for (var paramName in fx.parameters.keys) {
                  String autoKey = '${fx.name}_$paramName';
                  double autoVal = track.getInterpolatedAutomation(
                    autoKey,
                    playheadPosition,
                  );
                  double val = autoVal >= 0.0
                      ? autoVal
                      : fx.parameters[paramName]!;

                  if (track.type == TrackType.midi &&
                      track.synthSource != null) {
                    if (fx.name == 'TubeScreamer') {
                      if (paramName == 'Drive') {
                        track.synthSource!.filters.waveShaperFilter
                                .amount()
                                .value =
                            val;
                      }
                      if (paramName == 'Level') {
                        track.synthSource!.filters.waveShaperFilter
                                .wet()
                                .value =
                            val;
                      }
                      if (paramName == 'Tone') {
                        track.synthSource!.filters.biquadFilter.type().value =
                            0;
                        track.synthSource!.filters.biquadFilter
                                .frequency()
                                .value =
                            500 + val * 5000;
                      }
                    }
                    if (fx.name == 'Reverb') {
                      if (paramName == 'Mix') {
                        track.synthSource!.filters.echoFilter.wet().value = val;
                      }
                      if (paramName == 'Decay') {
                        track.synthSource!.filters.echoFilter.decay().value =
                            val;
                      }
                      if (paramName == 'Size') {
                        track.synthSource!.filters.echoFilter.delay().value =
                            val * 2.0;
                      }
                    }
                    if (fx.name == 'Compressor') {
                      if (paramName == 'Thresh') {
                        track.synthSource!.filters.compressorFilter
                                .threshold()
                                .value =
                            -80.0 + (val * 80.0);
                      }
                      if (paramName == 'Ratio') {
                        track.synthSource!.filters.compressorFilter
                                .ratio()
                                .value =
                            1.0 + (val * 9.0);
                      }
                      if (paramName == 'Gain') {
                        track.synthSource!.filters.compressorFilter
                                .makeupGain()
                                .value =
                            -40.0 + (val * 80.0);
                      }
                    }
                    if (fx.name == 'EQ') {
                      if (paramName == 'Low') {
                        track.synthSource!.filters.parametricEqFilter
                                .bandGain(0)
                                .value =
                            val * 4.0;
                      }
                      if (paramName == 'Mid') {
                        track.synthSource!.filters.parametricEqFilter
                                .bandGain(1)
                                .value =
                            val * 4.0;
                      }
                      if (paramName == 'High') {
                        track.synthSource!.filters.parametricEqFilter
                                .bandGain(2)
                                .value =
                            val * 4.0;
                      }
                    }
                  } else if (track.type == TrackType.audio) {
                    for (var c in trackClips[track.id] ?? []) {
                      if (c is AudioClip && c.source != null) {
                        if (fx.name == 'TubeScreamer') {
                          if (paramName == 'Drive') {
                            c.source!.filters.waveShaperFilter.amount().value =
                                val;
                            if (c.currentHandle != null &&
                                SoLoud.instance.getIsValidVoiceHandle(
                                  c.currentHandle!,
                                )) {
                              c.source!.filters.waveShaperFilter
                                      .amount(soundHandle: c.currentHandle)
                                      .value =
                                  val;
                            }
                          }
                          if (paramName == 'Level') {
                            c.source!.filters.waveShaperFilter.wet().value =
                                val;
                            if (c.currentHandle != null &&
                                SoLoud.instance.getIsValidVoiceHandle(
                                  c.currentHandle!,
                                )) {
                              c.source!.filters.waveShaperFilter
                                      .wet(soundHandle: c.currentHandle)
                                      .value =
                                  val;
                            }
                          }
                          if (paramName == 'Tone') {
                            c.source!.filters.biquadFilter.type().value = 0;
                            c.source!.filters.biquadFilter.frequency().value =
                                500 + val * 5000;
                            if (c.currentHandle != null &&
                                SoLoud.instance.getIsValidVoiceHandle(
                                  c.currentHandle!,
                                )) {
                              c.source!.filters.biquadFilter
                                      .type(soundHandle: c.currentHandle)
                                      .value =
                                  0;
                              c.source!.filters.biquadFilter
                                      .frequency(soundHandle: c.currentHandle)
                                      .value =
                                  500 + val * 5000;
                            }
                          }
                        }
                        if (fx.name == 'Reverb') {
                          if (paramName == 'Mix') {
                            c.source!.filters.echoFilter.wet().value = val;
                            if (c.currentHandle != null &&
                                SoLoud.instance.getIsValidVoiceHandle(
                                  c.currentHandle!,
                                )) {
                              c.source!.filters.echoFilter
                                      .wet(soundHandle: c.currentHandle)
                                      .value =
                                  val;
                            }
                          }
                          if (paramName == 'Decay') {
                            c.source!.filters.echoFilter.decay().value = val;
                            if (c.currentHandle != null &&
                                SoLoud.instance.getIsValidVoiceHandle(
                                  c.currentHandle!,
                                )) {
                              c.source!.filters.echoFilter
                                      .decay(soundHandle: c.currentHandle)
                                      .value =
                                  val;
                            }
                          }
                          if (paramName == 'Size') {
                            c.source!.filters.echoFilter.delay().value =
                                val * 2.0;
                            if (c.currentHandle != null &&
                                SoLoud.instance.getIsValidVoiceHandle(
                                  c.currentHandle!,
                                )) {
                              c.source!.filters.echoFilter
                                      .delay(soundHandle: c.currentHandle)
                                      .value =
                                  val * 2.0;
                            }
                          }
                        }
                        if (fx.name == 'Compressor') {
                          if (paramName == 'Thresh') {
                            c.source!.filters.compressorFilter
                                    .threshold()
                                    .value =
                                -80.0 + (val * 80.0);
                            if (c.currentHandle != null &&
                                SoLoud.instance.getIsValidVoiceHandle(
                                  c.currentHandle!,
                                )) {
                              c.source!.filters.compressorFilter
                                      .threshold(soundHandle: c.currentHandle)
                                      .value =
                                  -80.0 + (val * 80.0);
                            }
                          }
                          if (paramName == 'Ratio') {
                            c.source!.filters.compressorFilter.ratio().value =
                                1.0 + (val * 9.0);
                            if (c.currentHandle != null &&
                                SoLoud.instance.getIsValidVoiceHandle(
                                  c.currentHandle!,
                                )) {
                              c.source!.filters.compressorFilter
                                      .ratio(soundHandle: c.currentHandle)
                                      .value =
                                  1.0 + (val * 9.0);
                            }
                          }
                          if (paramName == 'Gain') {
                            c.source!.filters.compressorFilter
                                    .makeupGain()
                                    .value =
                                -40.0 + (val * 80.0);
                            if (c.currentHandle != null &&
                                SoLoud.instance.getIsValidVoiceHandle(
                                  c.currentHandle!,
                                )) {
                              c.source!.filters.compressorFilter
                                      .makeupGain(soundHandle: c.currentHandle)
                                      .value =
                                  -40.0 + (val * 80.0);
                            }
                          }
                        }
                        if (fx.name == 'EQ') {
                          if (paramName == 'Low') {
                            c.source!.filters.parametricEqFilter
                                    .bandGain(0)
                                    .value =
                                val * 4.0;
                            if (c.currentHandle != null &&
                                SoLoud.instance.getIsValidVoiceHandle(
                                  c.currentHandle!,
                                )) {
                              c.source!.filters.parametricEqFilter
                                      .bandGain(0, soundHandle: c.currentHandle)
                                      .value =
                                  val * 4.0;
                            }
                          }
                          if (paramName == 'Mid') {
                            c.source!.filters.parametricEqFilter
                                    .bandGain(1)
                                    .value =
                                val * 4.0;
                            if (c.currentHandle != null &&
                                SoLoud.instance.getIsValidVoiceHandle(
                                  c.currentHandle!,
                                )) {
                              c.source!.filters.parametricEqFilter
                                      .bandGain(1, soundHandle: c.currentHandle)
                                      .value =
                                  val * 4.0;
                            }
                          }
                          if (paramName == 'High') {
                            c.source!.filters.parametricEqFilter
                                    .bandGain(2)
                                    .value =
                                val * 4.0;
                            if (c.currentHandle != null &&
                                SoLoud.instance.getIsValidVoiceHandle(
                                  c.currentHandle!,
                                )) {
                              c.source!.filters.parametricEqFilter
                                      .bandGain(2, soundHandle: c.currentHandle)
                                      .value =
                                  val * 4.0;
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }

              for (var clip in trackClips[track.id] ?? []) {
                if (clip.start + clip.length >= oldPos &&
                    clip.start + clip.length < playheadPosition) {
                  if (clip is AudioClip &&
                      clip.currentHandle != null &&
                      SoLoud.instance.getIsValidVoiceHandle(
                        clip.currentHandle!,
                      )) {
                    try {
                      SoLoud.instance.stop(clip.currentHandle!);
                    } catch (_) {}
                  }
                }

                if (clip.start >= oldPos && clip.start < playheadPosition) {
                  if (clip is AudioClip && clip.source != null) {
                    if (clip.currentHandle == null ||
                        !SoLoud.instance.getIsValidVoiceHandle(
                          clip.currentHandle!,
                        )) {
                      clip.currentHandle = track.bus!.play(
                        clip.source!,
                        volume: track.volume,
                        pan: track.pan,
                        paused: true,
                      );
                      double offsetMs =
                          (playheadPosition - clip.start + clip.startOffset) *
                          10.0;
                      if (offsetMs > 0) {
                        try {
                          SoLoud.instance.seek(
                            clip.currentHandle!,
                            Duration(milliseconds: offsetMs.toInt()),
                          );
                        } catch (_) {}
                      }
                      try {
                        SoLoud.instance.setPause(clip.currentHandle!, false);
                      } catch (_) {}
                    }
                  }
                }

                if (clip is MidiClip && SoLoud.instance.isInitialized) {
                  double localOld = oldPos - clip.start + clip.startOffset;
                  double localNew =
                      playheadPosition - clip.start + clip.startOffset;
                  double maxLocal = clip.startOffset + clip.length;
                  if (localNew > maxLocal) localNew = maxLocal;
                  if (localNew >= 0 && localOld <= maxLocal) {
                    for (var note in clip.notes) {
                      if (note.start >= localOld && note.start < localNew) {
                        if (track.type == TrackType.sampler) {
                          var pad = track.samplerPads.values
                              .where((p) => p.midiNote == note.pitch)
                              .firstOrNull;
                          if (pad != null) {
                            pad.play(note.velocity.toDouble());
                          }
                        } else if (globalSynthSound != null) {
                          AudioSource src =
                              track.synthSource ?? globalSynthSound!;
                          if (track.synthSource == null) {
                            if (track.instrumentIndex == 1) {
                              src = globalSawSound!;
                            } else if (track.instrumentIndex == 2)
                              src = globalSineSound!;
                            else if (track.instrumentIndex == 3)
                              src = globalPianoSound!;
                            else if (track.instrumentIndex == 4)
                              src = globalCelloSound!;
                            else if (track.instrumentIndex == 5)
                              src = globalViolinSound!;
                          }
                          track.activeMidiHandles.removeWhere(
                            (h) => !SoLoud.instance.getIsValidVoiceHandle(h),
                          );
                          double volMultiplier = 1.0;
                          if (track.instrumentIndex == 3) {
                            volMultiplier = 3.0;
                          } else if (track.instrumentIndex == 4)
                            volMultiplier = 2.0;
                          else if (track.instrumentIndex == 5)
                            volMultiplier = 1.5;

                          final handle = track.bus!.play(
                            src,
                            volume:
                                (note.velocity / 127.0) *
                                track.volume *
                                volMultiplier,
                            pan: track.pan,
                          );
                          track.activeMidiHandles.add(handle);

                          SoLoud.instance.setLooping(handle, true);
                          if (track.instrumentIndex >= 3) {
                            SoLoud.instance.setLoopPoint(
                              handle,
                              const Duration(milliseconds: 500),
                            );
                          }

                          int basePitch = 69;
                          if (track.instrumentIndex == 3) {
                            basePitch = 60;
                          } else if (track.instrumentIndex == 4)
                            basePitch = 48;
                          else if (track.instrumentIndex == 5)
                            basePitch = 60;
                          double speed =
                              pow(2.0, (note.pitch - basePitch) / 12.0)
                                  as double;
                          SoLoud.instance.setRelativePlaySpeed(handle, speed);
                          Timer(
                            Duration(
                              milliseconds: max(
                                (note.length / beatWidth * (60.0 / bpm) * 1000)
                                    .toInt(),
                                50,
                              ),
                            ),
                            () {
                              if (SoLoud.instance.isInitialized) {
                                SoLoud.instance.fadeVolume(
                                  handle,
                                  0.0,
                                  Duration(milliseconds: 20),
                                );
                                Timer(
                                  Duration(milliseconds: 20),
                                  () => SoLoud.instance.stop(handle),
                                );
                              }
                            },
                          );
                        }
                      }
                    }
                  }
                }
              }
            }
            if (isLooping && playheadPosition >= loopEnd) {
              playheadPosition = loopStart;
              for (var track in tracks) {
                for (var clip in trackClips[track.id] ?? []) {
                  if (clip is AudioClip &&
                      clip.currentHandle != null &&
                      SoLoud.instance.getIsValidVoiceHandle(
                        clip.currentHandle!,
                      )) {
                    try {
                      SoLoud.instance.stop(clip.currentHandle!);
                    } catch (_) {}
                  }
                }
              }
            } else if (!isLooping) {
              double maxPos = 0.0;
              for (var t in tracks) {
                for (var c in trackClips[t.id] ?? []) {
                  if (c.start + c.length > maxPos) maxPos = c.start + c.length;
                }
              }
              if (maxPos < 2000.0) maxPos = 2000.0;

              if (playheadPosition > maxPos) {
                playheadPosition = 0.0;
                _togglePlay();
              }
            }

            if (_horizontalScrollController.hasClients) {
              double playheadX = playheadPosition * _zoomX;
              double offset = _horizontalScrollController.offset;
              double width = MediaQuery.of(context).size.width - 250;
              if (playheadX > offset + width - 100) {
                _horizontalScrollController.jumpTo(playheadX - width + 100);
              } else if (playheadX < offset) {
                _horizontalScrollController.jumpTo(playheadX);
              }
            }
          });
        });
      } else {
        playTimer?.cancel();
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
        for (var track in tracks) {
          for (var clip in trackClips[track.id] ?? []) {
            if (clip is AudioClip && clip.currentHandle != null) {
              if (SoLoud.instance.getIsValidVoiceHandle(clip.currentHandle!)) {
                SoLoud.instance.stop(clip.currentHandle!);
              }
            }
          }
          for (var h in track.activeMidiHandles) {
            if (SoLoud.instance.getIsValidVoiceHandle(h)) {
              SoLoud.instance.stop(h);
            }
          }
          track.activeMidiHandles.clear();
          for (var pad in track.samplerPads.values) {
            if (pad.currentHandle != null &&
                SoLoud.instance.getIsValidVoiceHandle(pad.currentHandle!)) {
              SoLoud.instance.stop(pad.currentHandle!);
            }
          }
        }
        for (var list in _activeMidiNotes.values) {
          for (var h in list) {
            if (SoLoud.instance.getIsValidVoiceHandle(h))
              SoLoud.instance.stop(h);
          }
        }
        _activeMidiNotes.clear();
      }
    });
  }

  Future<void> _updateMicState() async {
    bool wantsRecord = isRecording;
    bool wantsMonitor = tracks.any(
      (t) => t.type == TrackType.audio && t.isMonitoring,
    );
    bool needsMic = wantsRecord || wantsMonitor;

    if (needsMic && _micStreamSub == null) {
      bool hasPerm = await _audioRecorder.hasPermission();
      if (!hasPerm) return;

      if (SoLoud.instance.isInitialized) {
        _micSource = SoLoud.instance.setBufferStream(
          maxBufferSizeBytes: 1024 * 1024 * 10,
          sampleRate: 44100,
          channels: Channels.mono,
          format: BufferType.s16le,
          bufferingTimeNeeds: 0,
        );
        for (var t in tracks) {
          if (t.type == TrackType.audio && t.isMonitoring && t.bus != null) {
            t.bus!.play(_micSource!);
          }
        }
      }

      final stream = await _audioRecorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          device: _selectedInputDevice,
          sampleRate: 44100,
          numChannels: 1,
        ),
      );

      int packetCount = 0;
      _micStreamSub = stream.listen((data) {
        packetCount++;
        if (packetCount < 3) return;
        if (_micSource != null && wantsMonitor) {
          try {
            SoLoud.instance.addAudioDataStream(_micSource!, data);
          } catch (_) {}
        }
        if (isRecording && _wavWriter != null) {
          _wavWriter!.write(data);
        }
      });
    } else if (!needsMic && _micStreamSub != null) {
      await _micStreamSub!.cancel();
      _micStreamSub = null;
      await _audioRecorder.stop();
      if (_micSource != null) {
        try {
          SoLoud.instance.setDataIsEnded(_micSource!);
        } catch (_) {}
        _micSource = null;
      }
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
          double length = finalPlayhead - recordingStartPos!;
          if (length < 10) length = 10;

          if (SoLoud.instance.isInitialized) {
            try {
              final tempSource = await SoLoud.instance.loadFile(
                _currentRecordPath!,
              );
              double sec =
                  SoLoud.instance.getLength(tempSource).inMilliseconds / 1000.0;
              double actualLength = sec * (bpm / 60.0) * beatWidth;
              if (actualLength > 0) length = actualLength;
              SoLoud.instance.disposeSource(tempSource);
            } catch (e) {}
          }

          List<AudioClip> newClips = [];
          for (var t in armedTracks) {
            final clip = AudioClip(
              start: recordingStartPos!,
              length: length,
              color: lavenderAccent,
              filePath: _currentRecordPath!,
              id: UniqueKey().toString(),
            );
            if (SoLoud.instance.isInitialized) {
              clip.source = await SoLoud.instance.loadFile(_currentRecordPath!);
            }
            newClips.add(clip);
          }

          setState(() {
            for (int i = 0; i < armedTracks.length; i++) {
              var t = armedTracks[i];
              if (!trackClips.containsKey(t.id)) trackClips[t.id] = [];
              trackClips[t.id]!.add(newClips[i]);
            }
          });
        }
      }
      recordingStartPos = null;
      _currentRecordPath = null;
    } else {
      bool hasPermission = await _audioRecorder.hasPermission();
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
            _wavWriter = WavWriter(_currentRecordPath!);
          }

          _saveState();
          setState(() {
            isRecording = true;
            recordingStartPos = snapToGrid
                ? (playheadPosition / snapResolution).round() * snapResolution
                : playheadPosition;
            if (!isPlaying) _togglePlay();
          });
          if (hasArmedAudio) {
            await _updateMicState();
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
    final newTrack = Track(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: type == TrackType.audio
          ? 'Audio Track ${tracks.length + 1}'
          : (type == TrackType.sampler
                ? 'Sampler Track ${tracks.length + 1}'
                : 'MIDI Track ${tracks.length + 1}'),
      type: type,
    );
    newTrack.bus = Bus();
    newTrack.bus!.playOnEngine();

    if (type == TrackType.midi) {
      final dir = await getProjectMediaDirectory();
      newTrack.synthSourcePath = '${dir.path}/synth_v2.wav';
      if (SoLoud.instance.isInitialized) {
        newTrack.synthSource = await SoLoud.instance.loadFile(
          newTrack.synthSourcePath!,
        );
      }
    }
    _saveState();
    setState(() {
      tracks.add(newTrack);
      trackClips[newTrack.id] = [];
      if (type == TrackType.midi || type == TrackType.sampler) {
        final newClip = MidiClip(
          id: UniqueKey().toString(),
          start: 0.0,
          length: beatWidth * timeSigTop * 4,
          color: lavenderAccent,
        );
        trackClips[newTrack.id]!.add(newClip);
        selectedClip = newClip;
      }
      selectedTrackIndex = tracks.length - 1;
      if (type == TrackType.audio && selectedBottomTab == 0) {
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
  }

  void _executeDeleteTrack(Track track) {
    _saveState();
    setState(() {
      if (track.bus != null) {
        try { track.bus!.dispose(); } catch (_) {}
      }
      if (track.synthSource != null) {
        try { SoLoud.instance.disposeSource(track.synthSource!); } catch (_) {}
      }
      for (var c in trackClips[track.id] ?? []) {
        if (c is AudioClip && c.source != null) {
          try { SoLoud.instance.disposeSource(c.source!); } catch (_) {}
        }
      }
      tracks.remove(track);
      trackClips.remove(track.id);
      if (selectedTrackIndex != null && selectedTrackIndex! >= tracks.length) {
        selectedTrackIndex = tracks.isNotEmpty ? tracks.length - 1 : null;
      }
      if (selectedClip != null && !trackClips.values.expand((x) => x).contains(selectedClip)) {
        selectedClip = null;
      }
      multiSelectedClips.removeWhere((c) => !trackClips.values.expand((x) => x).contains(c));
    });
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

  void _showClipMenu(Offset pos, String trackId, DawClip clip) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        PopupMenuItem(value: 'copy', child: Text('Copy')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'delete', child: Text('Delete Clip')),
        PopupMenuItem(value: 'split', child: Text('Split at Playhead')),
        if (clip is AudioClip)
          PopupMenuItem(value: 'reverse', child: Text('Reverse Audio')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'color_blue', child: Text('Color: Blue')),
        PopupMenuItem(value: 'color_red', child: Text('Color: Red')),
        PopupMenuItem(value: 'color_green', child: Text('Color: Green')),
        PopupMenuItem(value: 'color_purple', child: Text('Color: Purple')),
      ],
    );
    if (result == 'copy') {
      _copy();
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
      double splitPoint = playheadPosition;
      if (splitPoint > clip.start && splitPoint < clip.start + clip.length) {
        double newLen1 = splitPoint - clip.start;
        double newLen2 = clip.length - newLen1;
        DawClip newClip;
        if (clip is AudioClip) {
          newClip = AudioClip(
            id: UniqueKey().toString(),
            start: splitPoint,
            length: newLen2,
            color: clip.color,
            filePath: clip.filePath,
            originalLength: clip.originalLength,
            startOffset: clip.startOffset + newLen1,
          );
          if (clip.source != null) {
            (newClip as AudioClip).source = clip.source;
          }
        } else {
          newClip = MidiClip(
            id: UniqueKey().toString(),
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
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Playhead must be intersecting the clip to split it',
              ),
            ),
          );
        }
      }
    } else if (result == 'reverse' && clip is AudioClip) {
      _saveState();
      await clip.toggleReverse();
      setState(() {});
    } else if (result == 'color_blue') {
      setState(() => clip.color = Colors.blueAccent);
    } else if (result == 'color_red') {
      setState(() => clip.color = Colors.redAccent);
    } else if (result == 'color_green') {
      setState(() => clip.color = Colors.green);
    } else if (result == 'color_purple') {
      setState(() => clip.color = lavenderAccent);
    }
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
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
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
                    SizedBox(width: 24),
                    Text(
                      'fyrDAW',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: lavenderAccent,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.undo, color: textMuted),
                      onPressed: _undo,
                      tooltip: 'Undo (Ctrl+Z)',
                    ),
                    IconButton(
                      icon: Icon(Icons.redo, color: textMuted),
                      onPressed: _redo,
                      tooltip: 'Redo (Ctrl+Shift+Z)',
                    ),
                    SizedBox(width: 8),
                    IconButton(
                      icon: Icon(Icons.zoom_out, color: textMuted),
                      onPressed: _zoomOut,
                      tooltip: 'Zoom Out (Ctrl-)',
                    ),
                    IconButton(
                      icon: Icon(Icons.zoom_in, color: textMuted),
                      onPressed: _zoomIn,
                      tooltip: 'Zoom In (Ctrl+)',
                    ),
                    SizedBox(width: 16),
                    IconButton(
                      icon: Icon(
                        snapToGrid ? Icons.grid_on : Icons.grid_off,
                        color: snapToGrid ? lavenderAccent : textMuted,
                      ),
                      tooltip: 'Snap to Grid',
                      onPressed: () => setState(() => snapToGrid = !snapToGrid),
                    ),
                    SizedBox(width: 8),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.settings, color: textMuted),
                      onSelected: (val) {
                        if (val == 'new') _newProject();
                        if (val == 'open') _openProject();
                        if (val == 'save') _saveProject();
                        if (val == 'save_as') _saveProjectAs();
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
                          value: 'export',
                          child: Text('Export to WAV'),
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
          Align(
            alignment: Alignment.center,
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
                        SoLoud.instance.filters.biquadResonantFilter
                            .deactivate();
                      } catch (_) {}
                      for (var track in tracks) {
                        for (var clip in trackClips[track.id] ?? []) {
                          if (clip is AudioClip && clip.currentHandle != null) {
                            SoLoud.instance.stop(clip.currentHandle!);
                          }
                        }
                      }
                    });
                  },
                ),
                IconButton(
                  icon: Icon(
                    isRecording
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: activeRecord,
                  ),
                  onPressed: _toggleRecord,
                ),
                SizedBox(width: 16),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: textFaint,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: textFaint),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.timer, size: 14, color: textMuted),
                      SizedBox(width: 8),
                      SizedBox(
                        width: 30,
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
                      SizedBox(width: 8),
                      InkWell(
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
                      SizedBox(width: 12),
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
        ],
      ),
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
                    PopupMenuItem(value: 'import', child: Text('Import WAV')),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              controller: _headerScrollController,
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                final isSelected = selectedTrackIndex == index;
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
                        PopupMenuItem(value: 'delete', child: Text('Delete Track', style: TextStyle(color: Colors.red))),
                      ],
                    ).then((value) {
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
                      if (track.type == TrackType.audio &&
                          (selectedBottomTab == 0 || selectedBottomTab == 3)) {
                        selectedBottomTab = 2;
                      } else if (track.type == TrackType.midi &&
                          selectedBottomTab == 3) {
                        selectedBottomTab = 0;
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
                      border: Border(bottom: BorderSide(color: textFaint)),
                    ),
                    padding: EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (track.type == TrackType.audio)
                              Icon(Icons.mic, size: 16, color: lavenderAccent)
                            else
                              Row(
                                children: [
                                  InkWell(
                                    onTap: () => _showInstrumentDialog(track),
                                    child: Icon(
                                      Icons.piano,
                                      size: 16,
                                      color: lavenderAccent,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  InkWell(
                                    onTap: () => _showMidiInputDialog(track),
                                    child: Icon(
                                      Icons.cable,
                                      size: 16,
                                      color: track.midiInputId == null
                                          ? lavenderAccent
                                          : Colors.cyanAccent,
                                    ),
                                  ),
                                ],
                              ),
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
                              () => setState(
                                () => track.isMuted = !track.isMuted,
                              ),
                              Colors.redAccent,
                            ),
                            SizedBox(width: 4),
                            _buildTrackButton(
                              'S',
                              track.isSolo,
                              () =>
                                  setState(() => track.isSolo = !track.isSolo),
                              Colors.amber,
                            ),
                            SizedBox(width: 4),
                            _buildTrackButton(
                              'R',
                              track.isArmed,
                              () => setState(
                                () => track.isArmed = !track.isArmed,
                              ),
                              activeRecord,
                            ),
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
                                  final items = [
                                    'Volume',
                                    'Pan',
                                    ...track.effectsChain.expand(
                                      (fx) => fx.parameters.keys.map(
                                        (p) => '${fx.name}_$p',
                                      ),
                                    ),
                                  ];
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

  Widget _buildClip(String trackId, DawClip clip) {
    final isSelected =
        selectedClip == clip || multiSelectedClips.contains(clip);
    return Positioned(
      left: clip.start * _zoomX,
      top: 10,
      bottom: 10,
      width: clip.length * _zoomX,
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
        onSecondaryTapUp: (details) =>
            _showClipMenu(details.globalPosition, trackId, clip),
        onHorizontalDragStart: (d) => _saveState(),
        onHorizontalDragUpdate: (d) => setState(() {
          List<DawClip> targets = multiSelectedClips.contains(clip)
              ? multiSelectedClips
              : [clip];
          for (var c in targets) {
            c.start += (d.delta.dx / _zoomX);
            if (c.start < 0) c.start = 0;
          }
        }),
        onHorizontalDragEnd: (d) => setState(() {
          if (snapToGrid) {
            List<DawClip> targets = multiSelectedClips.contains(clip)
                ? multiSelectedClips
                : [clip];
            for (var c in targets) {
              c.start = (c.start / snapResolution).round() * snapResolution;
            }
          }
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
                LayoutBuilder(
                  builder: (context, constraints) {
                    return ClipRect(
                      child: Stack(
                        children: clip.notes.map((n) {
                          return Positioned(
                            left: (n.start - clip.startOffset) * _zoomX,
                            top: ((127 - n.pitch) / 128.0) * 80.0,
                            width: n.length * _zoomX,
                            height: 4,
                            child: Container(color: textMuted),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
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
                      clip.length += (d.delta.dx / _zoomX);
                      if (clip.length < 10) clip.length = 10;
                      if (clip.length >
                          clip.originalLength - clip.startOffset) {
                        clip.length = clip.originalLength - clip.startOffset;
                      }
                    }),
                    onHorizontalDragEnd: (d) => setState(() {
                      if (snapToGrid) {
                        clip.length = max(
                          10.0,
                          (clip.length / snapResolution).round() *
                              snapResolution,
                        );
                        if (clip.length >
                            clip.originalLength - clip.startOffset) {
                          clip.length = clip.originalLength - clip.startOffset;
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
    );
  }

  Widget _buildTimeline() {
    return Expanded(
      child: Container(
        color: bgDark,
        child: SingleChildScrollView(
          controller: _horizontalScrollController,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: max(MediaQuery.of(context).size.width, 2000.0 * _zoomX),
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
                        onTapDown: (d) => setState(() {
                          playheadPosition = (d.localPosition.dx / _zoomX)
                              .clamp(0.0, 2000.0);
                          if (snapToGrid) {
                            playheadPosition =
                                (playheadPosition / snapResolution).round() *
                                snapResolution;
                          }
                        }),
                        onPanUpdate: (d) => setState(
                          () => playheadPosition =
                              (playheadPosition + (d.delta.dx / _zoomX)).clamp(
                                0.0,
                                2000.0,
                              ),
                        ),
                        onPanEnd: (d) => setState(() {
                          if (snapToGrid) {
                            playheadPosition =
                                (playheadPosition / snapResolution).round() *
                                snapResolution;
                          }
                        }),
                        child: CustomPaint(
                          painter: RulerPainter(
                            zoomX: _zoomX,
                            bpm: bpm,
                            timeSigTop: timeSigTop,
                          ),
                          size: Size(double.infinity, 40),
                        ),
                      ),
                      if (isLooping)
                        Positioned(
                          left: loopStart * _zoomX,
                          width: (loopEnd - loopStart) * _zoomX,
                          top: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: Container(
                              color: lavenderAccent.withOpacity(0.2),
                            ),
                          ),
                        ),
                      Positioned(
                        left: loopStart * _zoomX,
                        width: max(10.0, (loopEnd - loopStart) * _zoomX),
                        top: 0,
                        height: 6,
                        child: GestureDetector(
                          onTap: () => setState(() => isLooping = !isLooping),
                          child: Container(
                            color: isLooping
                                ? lavenderAccent
                                : Colors.grey.withOpacity(0.5),
                          ),
                        ),
                      ),
                      Positioned(
                        left: (loopStart * _zoomX) - 5,
                        top: 0,
                        width: 10,
                        height: 10,
                        child: GestureDetector(
                          onPanUpdate: (d) => setState(() {
                            loopStart += (d.delta.dx / _zoomX);
                            if (loopStart < 0) loopStart = 0;
                          }),
                          onPanEnd: (d) => setState(() {
                            if (snapToGrid) {
                              loopStart =
                                  (loopStart / snapResolution).round() *
                                  snapResolution;
                            }
                          }),
                          child: Container(
                            color: Colors.transparent,
                            child: Center(
                              child: Container(
                                width: 2,
                                height: 10,
                                color: textMain,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: (loopEnd * _zoomX) - 5,
                        top: 0,
                        width: 10,
                        height: 10,
                        child: GestureDetector(
                          supportedDevices: {
                            PointerDeviceKind.mouse,
                            PointerDeviceKind.touch,
                            PointerDeviceKind.stylus,
                          },
                          onPanUpdate: (d) => setState(() {
                            loopEnd += (d.delta.dx / _zoomX);
                            if (loopEnd <= loopStart) loopEnd = loopStart + 10;
                          }),
                          onPanEnd: (d) => setState(() {
                            if (snapToGrid) {
                              loopEnd = max(
                                loopStart + snapResolution,
                                (loopEnd / snapResolution).round() *
                                    snapResolution,
                              );
                            }
                          }),
                          child: Container(
                            color: Colors.transparent,
                            child: Center(
                              child: Container(
                                width: 2,
                                height: 10,
                                color: textMain,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      ListView.builder(
                        padding: EdgeInsets.zero,
                        controller: _timelineScrollController,
                        itemCount: tracks.length,
                        itemBuilder: (context, index) {
                          final track = tracks[index];
                          return GestureDetector(
                            onTapDown: (d) => setState(() {
                              selectedClip = null;
                              multiSelectedClips.clear();
                              selectedTrackIndex = index;
                            }),
                            onSecondaryTapUp: (d) {
                              playheadPosition = d.localPosition.dx / _zoomX;
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
                                    color: lavenderAccent,
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
                                border: Border(
                                  bottom: BorderSide(
                                    color: panelLight,
                                    width: 2,
                                  ),
                                ),
                              ),
                              child: Stack(
                                children: [
                                  ...(trackClips[track.id] ?? []).map(
                                    (clip) => _buildClip(track.id, clip),
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
                                      child: GestureDetector(
                                        onTapDown: (d) {
                                          double time =
                                              d.localPosition.dx / _zoomX;
                                          double val =
                                              1.0 -
                                              (d.localPosition.dy / 140.0);
                                          var list =
                                              track.automation[track
                                                  .currentAutomationParam] ??
                                              [];
                                          for (var p in list) {
                                            double px = p.time * _zoomX;
                                            double py = (1.0 - p.value) * 140.0;
                                            double dist = sqrt(
                                              pow(px - d.localPosition.dx, 2) +
                                                  pow(
                                                    py - d.localPosition.dy,
                                                    2,
                                                  ),
                                            );
                                            if (dist < 30.0) return;
                                          }
                                          _saveState();
                                          setState(() {
                                            if (!track.automation.containsKey(
                                              track.currentAutomationParam,
                                            )) {
                                              track.automation[track
                                                      .currentAutomationParam] =
                                                  [];
                                            }
                                            track
                                                .automation[track
                                                    .currentAutomationParam]!
                                                .add(
                                                  AutomationPoint(
                                                    time,
                                                    val.clamp(0.0, 1.0),
                                                  ),
                                                );
                                            track
                                                .automation[track
                                                    .currentAutomationParam]!
                                                .sort(
                                                  (a, b) =>
                                                      a.time.compareTo(b.time),
                                                );
                                          });
                                        },
                                        onPanStart: (d) {
                                          var list =
                                              track.automation[track
                                                  .currentAutomationParam] ??
                                              [];
                                          int closest = -1;
                                          double minDist = 30.0;
                                          for (
                                            int i = 0;
                                            i < list.length;
                                            i++
                                          ) {
                                            double px = list[i].time * _zoomX;
                                            double py =
                                                (1.0 - list[i].value) * 140.0;
                                            double dist = sqrt(
                                              pow(px - d.localPosition.dx, 2) +
                                                  pow(
                                                    py - d.localPosition.dy,
                                                    2,
                                                  ),
                                            );
                                            if (dist < minDist) {
                                              minDist = dist;
                                              closest = i;
                                            }
                                          }
                                          if (closest != -1) {
                                            _saveState();
                                            setState(() {
                                              _draggingAutoPointIndex = closest;
                                              _draggingAutoTrackId = track.id;
                                            });
                                          }
                                        },
                                        onPanUpdate: (d) {
                                          if (_draggingAutoTrackId ==
                                                  track.id &&
                                              _draggingAutoPointIndex != null) {
                                            setState(() {
                                              var list =
                                                  track.automation[track
                                                      .currentAutomationParam]!;
                                              double newTime =
                                                  list[_draggingAutoPointIndex!]
                                                      .time +
                                                  (d.delta.dx / _zoomX);
                                              double minTime =
                                                  _draggingAutoPointIndex! > 0
                                                  ? list[_draggingAutoPointIndex! -
                                                                1]
                                                            .time +
                                                        0.1
                                                  : 0.0;
                                              double maxTime =
                                                  _draggingAutoPointIndex! <
                                                      list.length - 1
                                                  ? list[_draggingAutoPointIndex! +
                                                                1]
                                                            .time -
                                                        0.1
                                                  : 2000.0;
                                              list[_draggingAutoPointIndex!]
                                                  .time = newTime.clamp(
                                                minTime,
                                                maxTime,
                                              );

                                              double newVal =
                                                  list[_draggingAutoPointIndex!]
                                                      .value -
                                                  (d.delta.dy / 140.0);
                                              list[_draggingAutoPointIndex!]
                                                  .value = newVal.clamp(
                                                0.0,
                                                1.0,
                                              );
                                            });
                                          }
                                        },
                                        onPanEnd: (d) => setState(() {
                                          _draggingAutoPointIndex = null;
                                          _draggingAutoTrackId = null;
                                        }),
                                        child: Container(
                                          color: Colors.cyanAccent.withAlpha(
                                            20,
                                          ),
                                          child: CustomPaint(
                                            painter: AutomationPainter(
                                              points:
                                                  track.automation[track
                                                      .currentAutomationParam] ??
                                                  [],
                                              zoomX: _zoomX,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
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
                          onPanUpdate: (d) => setState(() {
                            playheadPosition =
                                (playheadPosition + (d.delta.dx / _zoomX))
                                    .clamp(0.0, 2000.0);
                          }),
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
      } else if (val == 'TubeScreamer') {
        effect = DawEffect('TubeScreamer', {
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
      tracks[selectedTrackIndex!].effectsChain.add(effect);
      _updateTrackFilters(tracks[selectedTrackIndex!]);
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
        'name': 'TubeScreamer',
        'color': Colors.red[800]!,
        'desc': 'Classic overdrive distortion effect.',
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
    return Container(
      height: isBottomPanelExpanded ? _bottomPanelHeight : 54,
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
                      _buildPanelTab('Mixer', 1),
                      _buildPanelTab('Effects', 2),
                      if (tracks[selectedTrackIndex!].type == TrackType.sampler)
                        _buildPanelTab('Sampler', 3),
                      Spacer(),
                      IconButton(
                        icon: Icon(
                          isBottomPanelExpanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_up,
                          color: textMuted,
                        ),
                        onPressed: () => setState(
                          () => isBottomPanelExpanded = !isBottomPanelExpanded,
                        ),
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

  Widget _buildBottomPanelContent() {
    switch (selectedBottomTab) {
      case 0:
        if (selectedClip is MidiClip) {
          Track? t;
          for (var tr in tracks) {
            if (trackClips[tr.id]?.contains(selectedClip) == true) t = tr;
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              double autoZoom =
                  (constraints.maxWidth - 60) / selectedClip!.length;
              if (autoZoom <= 0) autoZoom = 1.0;
              return MidiEditorWidget(
                clip: selectedClip as MidiClip,
                track: t,
                snapToGrid: snapToGrid,
                snapResolution: snapResolution,
                zoomX: autoZoom * _midiZoomMultiplier,
                bpm: bpm,
                timeSigTop: timeSigTop,
                selectedMidiNotes: selectedMidiNotes,
                onSelectionChanged: (notes) =>
                    setState(() => selectedMidiNotes = notes),
                onChangeStart: _saveState,
                onNotesChanged: () => setState(() {}),
                onZoomIn: () => setState(() => _midiZoomMultiplier += 0.2),
                onZoomOut: () => setState(
                  () =>
                      _midiZoomMultiplier = max(0.2, _midiZoomMultiplier - 0.2),
                ),
                playheadPosition: playheadPosition,
                onPlayheadChanged: (v) => setState(() => playheadPosition = v),
                midiDevices: _midiDevices,
                onCopy: _copy,
                onPaste: _paste,
                onInstrumentDialogRequested: () => _showInstrumentDialog(t!),
                onMidiInputDialogRequested: () => _showMidiInputDialog(t!),
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
        return ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: tracks.length,
          itemBuilder: (context, index) {
            final t = tracks[index];
            return Container(
              width: 100,
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: panelLight)),
              ),
              child: Column(
                children: [
                  SizedBox(height: 16),
                  Text(
                    t.name,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Spacer(),
                  PanDial(
                    onChangeStart: _saveState,
                    pan: t.pan,
                    onChanged: (v) => setState(() {
                      t.pan = v;
                      for (var c in trackClips[t.id] ?? []) {
                        if (c is AudioClip && c.currentHandle != null) {
                          SoLoud.instance.setPan(c.currentHandle!, v);
                        }
                      }
                    }),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Pan L/R',
                    style: TextStyle(fontSize: 10, color: textMuted),
                  ),
                  SizedBox(height: 8),
                  Expanded(
                    flex: 3,
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: SliderTheme(
                        data: SliderThemeData(
                          thumbShape: RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: SliderComponentShape.noOverlay,
                        ),
                        child: Slider(
                          onChangeStart: (_) => _saveState(),
                          value: t.volume,
                          activeColor: lavenderAccent,
                          onChanged: (v) => setState(() {
                            t.volume = v;
                            for (var c in trackClips[t.id] ?? []) {
                              if (c is AudioClip && c.currentHandle != null) {
                                SoLoud.instance.setVolume(c.currentHandle!, v);
                              }
                            }
                          }),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    (t.volume * 100).toInt().toString(),
                    style: TextStyle(fontSize: 10),
                  ),
                  SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      case 2:
        if (selectedTrackIndex == null ||
            selectedTrackIndex! >= tracks.length) {
          return Center(
            child: Text(
              'No track selected',
              style: TextStyle(color: textMuted),
            ),
          );
        }
        final track = tracks[selectedTrackIndex!];
        return Row(
          children: [
            if (track.type == TrackType.audio)
              Container(
                width: 200,
                color: panelDark,
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Input Source',
                      style: TextStyle(
                        color: textMuted,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    SizedBox(height: 8),
                    if (_inputDevices.isEmpty)
                      Text(
                        'No inputs found',
                        style: TextStyle(color: textFaint, fontSize: 10),
                      )
                    else
                      DropdownButton<InputDevice>(
                        value: _selectedInputDevice,
                        isExpanded: true,
                        dropdownColor: bgDark,
                        icon: Icon(Icons.mic, color: textMuted, size: 16),
                        underline: Container(height: 1, color: lavenderAccent),
                        style: TextStyle(color: textMain, fontSize: 12),
                        onChanged: (InputDevice? newValue) {
                          if (newValue != null) {
                            setState(() => _selectedInputDevice = newValue);
                          }
                        },
                        items: _inputDevices.map<DropdownMenuItem<InputDevice>>(
                          (InputDevice value) {
                            return DropdownMenuItem<InputDevice>(
                              value: value,
                              child: Text(
                                value.label.isNotEmpty
                                    ? value.label
                                    : 'Microphone ${value.id}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          },
                        ).toList(),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: ReorderableListView(
                      scrollDirection: Axis.horizontal,
                      onReorder: (oldIndex, newIndex) {
                        if (newIndex > oldIndex) newIndex -= 1;
                        setState(() {
                          final item = tracks[selectedTrackIndex!].effectsChain
                              .removeAt(oldIndex);
                          tracks[selectedTrackIndex!].effectsChain.insert(
                            newIndex,
                            item,
                          );
                          _updateTrackFilters(tracks[selectedTrackIndex!]);
                        });
                      },
                      children: tracks[selectedTrackIndex!].effectsChain
                          .asMap()
                          .entries
                          .map((e) {
                            int idx = e.key;
                            DawEffect fx = e.value;
                            Color pedalColor = fx.name == 'EQ'
                                ? Colors.blue[800]!
                                : (fx.name == 'Compressor'
                                      ? Colors.green[800]!
                                      : (fx.name == 'TubeScreamer'
                                            ? Colors.red[800]!
                                            : (fx.name == 'GuitarAmp'
                                                  ? Colors.grey[900]!
                                                  : Colors.deepPurple[800]!)));
                            bool isAmp = fx.name == 'GuitarAmp';
                            return Center(
                              key: ValueKey('${fx.name}_$idx'),
                              child: Container(
                                width: isAmp ? 240 : 120,
                                height: 180,
                                margin: EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: pedalColor,
                                  borderRadius: BorderRadius.circular(
                                    isAmp ? 4 : 8,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: textMuted,
                                      blurRadius: 4,
                                      offset: Offset(2, 2),
                                    ),
                                  ],
                                  border: Border.all(
                                    color: textFaint,
                                    width: isAmp ? 4 : 2,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Container(
                                      color: textFaint,
                                      padding: EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      child: Row(
                                        children: [
                                          SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              fx.name,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                                color: Colors.white,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () => setState(() {
                                              tracks[selectedTrackIndex!]
                                                  .effectsChain
                                                  .removeAt(idx);
                                              _updateTrackFilters(
                                                tracks[selectedTrackIndex!],
                                              );
                                            }),
                                            child: Icon(
                                              Icons.close,
                                              size: 14,
                                              color: textMuted,
                                            ),
                                          ),
                                          SizedBox(width: 4),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: Wrap(
                                        alignment: WrapAlignment.center,
                                        runAlignment: WrapAlignment.center,
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: fx.parameters.keys.map((k) {
                                          return Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              PanDial(
                                                onChangeStart: _saveState,
                                                pan:
                                                    fx.parameters[k]! * 2 - 1.0,
                                                onChanged: (v) => setState(
                                                  () => fx.parameters[k] =
                                                      (v + 1.0) / 2.0,
                                                ),
                                              ),
                                              SizedBox(height: 4),
                                              Text(
                                                k,
                                                style: TextStyle(
                                                  fontSize: 8,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ],
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                    Container(
                                      margin: EdgeInsets.only(bottom: 12),
                                      width: isAmp ? 80 : 20,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        color: isAmp
                                            ? Colors.black87
                                            : Colors.grey[400],
                                        shape: isAmp
                                            ? BoxShape.rectangle
                                            : BoxShape.circle,
                                        border: Border.all(
                                          color: textMuted,
                                          width: 2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: textFaint,
                                            blurRadius: 2,
                                            offset: Offset(1, 1),
                                          ),
                                        ],
                                      ),
                                      child: isAmp
                                          ? Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceEvenly,
                                              children: [
                                                Container(
                                                  width: 6,
                                                  height: 6,
                                                  decoration: BoxDecoration(
                                                    color: Colors.red,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                              ],
                                            )
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          })
                          .toList(),
                    ),
                  ),
                  Center(
                    child: InkWell(
                      onTap: _showAddEffectDialog,
                      child: Container(
                        margin: EdgeInsets.all(16),
                        child: DottedBorder(
                          options: RoundedRectDottedBorderOptions(
                            color: textMuted,
                            strokeWidth: 2,
                            dashPattern: [6, 4],
                            radius: Radius.circular(8),
                          ),
                          child: Container(
                            width: 120,
                            height: 180,
                            decoration: BoxDecoration(
                              color: textFaint.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add, color: textMuted, size: 32),
                                SizedBox(height: 8),
                                Text(
                                  'Add Effect',
                                  style: TextStyle(
                                    color: textMuted,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
            setState(() {
              playheadPosition = isLooping ? loopStart : 0.0;
              for (var track in tracks) {
                for (var clip in trackClips[track.id] ?? []) {
                  if (clip is AudioClip && clip.currentHandle != null) {
                    SoLoud.instance.stop(clip.currentHandle!);
                  }
                }
              }
            });
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
              child: Row(children: [_buildTrackHeaders(), _buildTimeline()]),
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
