part of '../../main.dart';

extension _DawAudioEngineController on _DawMainScreenState {
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
        _setState(() {
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
      _setState(() {
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
      _setState(() {
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
            final double postScale = t.type == TrackType.audio
                ? _effectiveTrackVolume(
                    t,
                    sidechainGain: (1.0 - (_sidechainGr[t.id] ?? 0.0)).clamp(
                      0.08,
                      1.0,
                    ),
                  )
                : 1.0;
            rawL = t.bus!.getChannelVolume(0) * postScale;
            rawR = t.bus!.getChannelVolume(1) * postScale;
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
        if (track.type == TrackType.audio) {
          _syncTrackBusOutputVolume(track);
        } else {
          for (final h in track.activeMidiHandles) {
            if (SoLoud.instance.getIsValidVoiceHandle(h)) {
              try {
                SoLoud.instance.setVolume(
                  h,
                  (track.volume * scGain).clamp(0.0, 4.0),
                );
              } catch (_) {}
            }
          }
        }
      }

      if (anyMeterActive) {
        _setState(() {});
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

  double _effectiveTrackVolume(Track t, {double sidechainGain = 1.0}) {
    final g = _groupForTrack(t);
    return (t.volume * (g?.volume ?? 1.0) * sidechainGain).clamp(0.0, 4.0);
  }

  /// Applies post-FX fader & group gain directly to [t]'s audio [Bus] output
  /// handle so effects like Overdrive/GuitarAmp/Compressor cannot clamp away
  /// track fader boosts.
  void _syncTrackBusOutputVolume(Track t) {
    if (!_isSoloudReady || t.type != TrackType.audio || t.bus == null) return;
    t.bus = ensureActiveBus(t.bus);
    final handle = t.bus!.soundHandle;
    if (handle == null) return;
    final bool anySolo = tracks.any((tr) => tr.isSolo);
    final bool audible = _isTrackAudible(t, anySolo);
    final double scGain =
        (1.0 - (_sidechainGr[t.id] ?? 0.0)).clamp(0.08, 1.0);
    final double busVol = audible
        ? _effectiveTrackVolume(t, sidechainGain: scGain)
        : 0.0;
    try {
      if (SoLoud.instance.getIsValidVoiceHandle(handle)) {
        SoLoud.instance.setVolume(handle, busVol);
      }
    } catch (_) {}
  }

  void _onTrackVolumeChanged(
    Track t,
    double nextVolume, {
    bool updateState = true,
  }) {
    final double clamped = nextVolume.clamp(0.0, kMaxTrackVolume);
    if (updateState) {
      _setState(() => t.volume = clamped);
    } else {
      t.volume = clamped;
    }

    if (t.type == TrackType.group) {
      for (final child in tracks) {
        if (child.groupTrackId == t.id) {
          _syncTrackBusOutputVolume(child);
        }
      }
    } else {
      _syncTrackBusOutputVolume(t);
    }

    if (_isSoloudReady) {
      final double effTrackVol = _effectiveTrackVolume(t);
      for (final c in trackClips[t.id] ?? const <DawClip>[]) {
        if (c is AudioClip) {
          final double env = _computeClipEnvelope(
            c,
            playheadPosition,
            track: t,
          );
          if (c.currentHandle != null) {
            try {
              final double voiceVol = t.type == TrackType.audio
                  ? env.clamp(0.0, 2.5)
                  : (effTrackVol * env).clamp(0.0, 4.0);
              SoLoud.instance.setVolume(c.currentHandle!, voiceVol);
            } catch (_) {}
          }
          if (c.reverbSendHandle != null) {
            try {
              SoLoud.instance.setVolume(
                c.reverbSendHandle!,
                ((t.reverbPreFader ? env : effTrackVol * env) * t.reverbSend)
                    .clamp(0.0, 4.0),
              );
            } catch (_) {}
          }
          if (c.delaySendHandle != null) {
            try {
              SoLoud.instance.setVolume(
                c.delaySendHandle!,
                ((t.delayPreFader ? env : effTrackVol * env) * t.delaySend)
                    .clamp(0.0, 4.0),
              );
            } catch (_) {}
          }
        }
      }
      if (t.type != TrackType.audio) {
        for (final h in t.activeMidiHandles) {
          try {
            if (SoLoud.instance.getIsValidVoiceHandle(h)) {
              SoLoud.instance.setVolume(h, clamped.clamp(0.0, 4.0));
            }
          } catch (_) {}
        }
      }
    }
    _syncTrackMonitoringHandles();
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
      _setState(() {
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
    _setState(() {
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
      SoLoud.instance.setGlobalVolume(masterVolume.clamp(0.0, kMaxMasterVolume));
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

}
