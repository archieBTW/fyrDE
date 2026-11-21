part of '../../main.dart';

extension _DawRecordingController on _DawMainScreenState {
  void _syncTrackMonitoringHandles() {
    if (!_isSoloudReady) return;
    try {
      if (!SoLoud.instance.isInitialized) return;
    } catch (_) {
      return;
    }
    final bool anySolo = tracks.any((t) => t.isSolo);
    for (final t in tracks) {
      if (t.type != TrackType.audio) continue;
      _syncTrackBusOutputVolume(t);
      if (t.isMonitoring) {
        t.bus = ensureActiveBus(t.bus);
        if (t.monitorSource == null) {
          try {
            t.monitorSource = SoLoud.instance.setBufferStream(
              maxBufferSizeBytes: 1024 * 256,
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
          _syncTrackBusOutputVolume(t);
          final double effVol =
              (t.isMuted || (anySolo && !t.isSolo)) ? 0.0 : 1.0;
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
          _setState(() => _detectedPitch = nextPitch);
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
        // Bound buffered monitoring audio to <= 16KB (~46ms of stereo f32le at
        // 44.1kHz) via tail-slicing/backpressure instead of resetBufferStream,
        // because flutter_soloud's resetBuffer() acquires buffer_lock_mutex then
        // soloud.seek() (AB-BA deadlock against the audio mixing thread).
        final int bufferedBytes = SoLoud.instance.getBufferSize(src);
        final Uint8List toQueue = sliceLatestStereoFloatPcmFrames(
          floatBytes,
          currentlyBufferedBytes: bufferedBytes,
        );
        if (toQueue.isNotEmpty) {
          SoLoud.instance.addAudioDataStream(src, toQueue);
        }

        final double effVol =
            (t.isMuted || (anySolo && !t.isSolo)) ? 0.0 : 1.0;
        if (t.monitorHandle == null ||
            !SoLoud.instance.getIsValidVoiceHandle(t.monitorHandle!)) {
          t.bus = ensureActiveBus(t.bus);
          _syncTrackBusOutputVolume(t);
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
    _setState(() {
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
      if (mounted) _setState(() => _detectedPitch = null);
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
            '--latency-msec=8',
            '--process-time-msec=4',
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
      _setState(() => isRecording = false);
      if (_wavWriter != null) {
        _wavWriter!.close();
        _wavWriter = null;
      }
      await _updateMicState();

      if (_currentRecordPath != null && recordingStartPos != null) {
        final file = File(_currentRecordPath!);
        if (file.existsSync() && file.lengthSync() < 100) {
          file.deleteSync();
          _setState(() {
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

          _setState(() {
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
            _setState(() => playheadPosition = loopStart);
          }

          Future<void> beginRecordNow() async {
            _saveState();
            _recordingFirstChunkPos = null;
            _recordingFirstChunkFrames = 0;
            if (hasArmedAudio && _currentRecordPath != null) {
              _wavWriter = WavWriter(_currentRecordPath!);
            }
            _setState(() {
              isRecording = true;
              _countInBeatsLeft = 0;
              recordingStartPos = playheadPosition;
              if (!isPlaying) _togglePlay();
            });
          }

          if (countInBars > 0 && !isPlaying) {
            _countInTimer?.cancel();
            int remaining = countInBars * timeSigTop;
            _setState(() => _countInBeatsLeft = remaining);

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
                _setState(() => _countInBeatsLeft = remaining);
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

}
