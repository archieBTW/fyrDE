part of '../../main.dart';

extension _DawProjectController on _DawMainScreenState {
  Future<void> _writeAutoSave() =>
      ProjectArchiveService.writeAutoSave(_getCurrentStateJson());

  Future<void> _clearAutoSave() => ProjectArchiveService.clearAutoSave();

  void _saveState({bool skipAutoSave = false}) {
    _history.push(_getCurrentStateJson());
    if (!skipAutoSave) {
      _writeAutoSave();
    }
  }

  void _checkAutoSave() async {
    final file = await ProjectArchiveService.findExistingAutoSaveFile();
    if (file != null && mounted) {
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
      _setState(() {
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
        multiSelectedTrackIds.clear();
        _trackSelectionAnchorIndex = null;
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
    final prev = _history.undo(_getCurrentStateJson());
    if (prev != null) {
      await _loadStateJson(prev);
    }
  }

  void _redo() async {
    final next = _history.redo(_getCurrentStateJson());
    if (next != null) {
      await _loadStateJson(next);
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

    _setState(() {
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

  Future<String?> _pickExportSavePath(String format) async {
    final defaultName = 'mixdown.$format';
    if (Platform.isLinux) {
      try {
        final docsDir = await getApplicationDocumentsDirectory();
        final suggested = '${docsDir.path}/$defaultName';
        final result = await Process.run('zenity', [
          '--file-selection',
          '--save',
          '--confirm-overwrite',
          '--title=Export Mixdown (.${format.toUpperCase()})',
          '--filename=$suggested',
          '--file-filter=*.$format',
        ]);
        if (result.exitCode != 0) return null;
        final chosen = result.stdout.toString().trim();
        if (chosen.isEmpty) return null;
        return MixdownRenderer.normalizeExportPath(chosen, format);
      } catch (_) {}
    }
    final picked = await FilePicker.saveFile(
      dialogTitle: 'Export Mixdown (.${format.toUpperCase()})',
      fileName: defaultName,
      type: FileType.custom,
      allowedExtensions: [format],
    );
    if (picked == null || picked.trim().isEmpty) return null;
    return MixdownRenderer.normalizeExportPath(picked, format);
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
      final String? finalPath = await _pickExportSavePath(format);
      if (finalPath == null) return;

      final ts = DateTime.now().millisecondsSinceEpoch;
      final bool needsTranscode = format == 'mp3' || format == 'flac';
      final String wavPath = needsTranscode
          ? '${Directory.systemTemp.path}/fyrdaw_mixdown_$ts.wav'
          : finalPath;

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
        try {
          if (needsTranscode && File(wavPath).existsSync()) {
            File(wavPath).deleteSync();
          }
        } catch (_) {}
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Nothing to export — add audio or MIDI clips first!')),
          );
        }
        return;
      }

      if (needsTranscode) {
        final transcodeRes = await MixdownRenderer.transcodeWithFfmpegDetailed(
          wavPath,
          finalPath,
          format: format,
        );
        try {
          if (File(wavPath).existsSync()) {
            File(wavPath).deleteSync();
          }
        } catch (_) {}
        if (!transcodeRes.ok) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${format.toUpperCase()} export failed: ${transcodeRes.error ?? 'ffmpeg unavailable'}',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save error: $e'), backgroundColor: Colors.red),
        );
      }
      return false;
    }
  }

  Future<bool> _saveToPath(String path) async {
    try {
      final payload = ProjectArchiveService.buildArchivePayload(
        bpm: bpm,
        timeSigTop: timeSigTop,
        timeSigBottom: timeSigBottom,
        metronomeVolume: metronomeVolume,
        masterVolume: masterVolume,
        masterLimiter: masterLimiter,
        masterLufsTarget: masterLufsTarget,
        masterEffectsChain: masterEffectsChain,
        midiMappings: midiMappings,
        auxReverbMix: auxReverbMix,
        auxDelayMix: auxDelayMix,
        songMarkers: songMarkers,
        tempoMarkers: tempoMarkers,
        tracks: tracks,
        trackClips: trackClips,
      );

      await ProjectArchiveService.saveArchiveToPath(
        outputPath: path,
        projectData: payload.projectData,
        mediaFilePaths: payload.mediaFilePaths,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Project saved to $path'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save error: $e'), backgroundColor: Colors.red),
        );
      }
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

        final mediaDir = await getProjectMediaDirectory();
        final projectData = await ProjectArchiveService.loadArchiveFromPath(
          path: path,
          mediaDirPath: mediaDir.path,
        );

        _setState(() {
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
                return DawClip.fromJson(c);
              }).toList();
            });
          }

          playheadPosition = 0;
          selectedClip = null;
          multiSelectedClips.clear();
          multiSelectedTrackIds.clear();
          _trackSelectionAnchorIndex = null;
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Open error: $e'), backgroundColor: Colors.red),
        );
      }
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
                                    prefs.setInt('lavenderAccent', color.toARGB32());
                                    dawAppKey.currentState?.rebuild();
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
      _setState(() {});
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

        _setState(() {
          tracks.add(newTrack);
          trackClips[newTrack.id] = [clip];
          selectedTrackIndex = tracks.length - 1;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
          beatWidth: beatWidth,
          onlyTrack: t,
          masterVolume: 1.0,
          masterLimiter: false,
          auxReverbMix: auxReverbMix,
          auxDelayMix: auxDelayMix,
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
        beatWidth: beatWidth,
        onlyTrack: track,
        masterVolume: 1.0,
        masterLimiter: false,
        auxReverbMix: auxReverbMix,
        auxDelayMix: auxDelayMix,
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
      _setState(() {
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

  Future<void> _openTemplates() async {
    final res = await showTemplatesDialog(context);
    if (res == null) return;
    _saveState();
    _setState(() {
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
        _setState(() {
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
      _setState(() => _userSampleFolders = next);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('sb_sample_folders', next);
    } catch (_) {}
  }

  Future<void> _removeUserSampleFolder(String folder) async {
    final next = _userSampleFolders.where((f) => f != folder).toList();
    _setState(() => _userSampleFolders = next);
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
      if (mounted) _setState(() {});
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
      _setState(() {
        _browserPreviewPath = null;
        _browserPreviewHandle = null;
      });
      return;
    }
    _setState(() => _browserPreviewPath = item.path);
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
        _setState(() {
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
      _setState(() {
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

}
