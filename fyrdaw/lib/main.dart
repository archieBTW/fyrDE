import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:fyrdaw/wav_writer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fyrdaw/services/project_archive_service.dart';
import 'package:fyrdaw/services/undo_history.dart';
import 'package:fyrdaw/models/enums.dart';
import 'package:fyrdaw/models/daw_clip.dart';
import 'package:fyrdaw/models/daw_effect.dart';
import 'package:fyrdaw/models/track.dart';
import 'package:fyrdaw/models/sampler_pad.dart';
import 'package:fyrdaw/models/midi_note.dart';
import 'package:fyrdaw/models/midi_mapping.dart';
import 'package:fyrdaw/models/song_marker.dart';
import 'package:fyrdaw/models/tempo_marker.dart';
import 'package:fyrdaw/ui/automation_lane_overlay.dart';
import 'package:fyrdaw/ui/dial.dart';
import 'package:fyrdaw/ui/painters.dart';
import 'package:fyrdaw/ui/meters.dart';
import 'package:fyrdaw/ui/midi_editor.dart';
import 'package:fyrdaw/ui/sampler_editor.dart';
import 'package:fyrdaw/ui/sample_browser_drawer.dart';
import 'package:fyrdaw/ui/templates_dialog.dart';
import 'package:fyrdaw/ui/mixer_console.dart';
import 'package:fyrdaw/ui/effects_rack.dart';
import 'package:fyrdaw/ui/musical_keyboard_bar.dart';
import 'package:fyrdaw/ui/session_launcher.dart';
import 'package:fyrdaw/ui/tempo_signature_lane.dart';
import 'package:fyrdaw/ui/timeline_loop_bar.dart';
import 'package:fyrdaw/ui/audio_clip_editor.dart';
import 'package:fyrdaw/utils/audio_input_channel.dart';
import 'package:fyrdaw/utils/audio_output_routing.dart';
import 'package:fyrdaw/utils/recording_sync.dart';
import 'package:fyrdaw/utils/selection_helpers.dart';
import 'package:fyrdaw/utils/audio_utils.dart';
import 'package:fyrdaw/utils/bus_metering.dart';
import 'package:fyrdaw/utils/effect_presets.dart';
import 'package:fyrdaw/utils/metronome_synth.dart';
import 'package:fyrdaw/utils/midi_file_codec.dart';
import 'package:fyrdaw/utils/mixdown_renderer.dart';
import 'package:fyrdaw/utils/parametric_eq_dsp.dart';
import 'package:fyrdaw/utils/playback_sync.dart';
import 'package:fyrdaw/utils/pitch_detector.dart';
import 'package:fyrdaw/utils/plugin_host.dart';
import 'package:fyrdaw/utils/time_stretch.dart';
import 'fyr_theme.dart';

part 'ui/daw_main_screen.dart';
part 'ui/daw/daw_project_controller.dart';
part 'ui/daw/daw_midi_controller.dart';
part 'ui/daw/daw_audio_engine_controller.dart';
part 'ui/daw/daw_playback_controller.dart';
part 'ui/daw/daw_recording_controller.dart';
part 'ui/daw/daw_editing_controller.dart';
part 'ui/daw/daw_top_bar.dart';
part 'ui/daw/daw_track_headers.dart';
part 'ui/daw/daw_timeline_view.dart';
part 'ui/daw/daw_bottom_panel.dart';

AudioSource? globalSynthSound;
AudioSource? globalSawSound;
AudioSource? globalSineSound;
AudioSource? globalPianoSound;
AudioSource? globalCelloSound;
AudioSource? globalViolinSound;
AudioSource? globalMetronomeAccentSound;
AudioSource? globalMetronomeBeatSound;
final Map<int, AudioSource> globalInstrumentSounds = {};

AudioSource? getInstrumentAudioSource(Track track) {
  return globalInstrumentSounds[track.instrumentIndex] ??
      track.synthSource ??
      globalSynthSound;
}

SoundHandle? triggerInstrumentNote(
  Track track,
  int midiPitch,
  int velocity, {
  double volumeScale = 1.0,
  Bus? targetBus,
}) {
  try {
    if (!SoLoud.instance.isInitialized) return null;
  } catch (_) {
    return null;
  }
  final preset = getInstrumentPreset(track.instrumentIndex);
  final src = getInstrumentAudioSource(track);
  if (src == null) return null;

  final s = track.synthSettings;
  final busToUse = targetBus ?? (track.bus = ensureActiveBus(track.bus));
  final double targetVol =
      ((velocity.clamp(1, 127) / 127.0) *
              track.volume *
              preset.volumeMultiplier *
              volumeScale)
          .clamp(0.0, 4.0);
  final double semitoneOffset =
      (midiPitch - preset.basePitch) +
      (s.octave * 12.0) +
      (s.detuneCents / 100.0);
  final double speed = pow(2.0, semitoneOffset / 12.0)
      .toDouble()
      .clamp(0.05, 16.0);

  final bool hasAttack = s.attackSec > 0.01;
  final handle = busToUse.play(
    src,
    volume: hasAttack ? 0.001 : targetVol,
    pan: track.pan.clamp(-1.0, 1.0),
    paused: true,
  );
  SoLoud.instance.setLooping(handle, true);
  SoLoud.instance.setLoopPoint(
    handle,
    Duration(milliseconds: preset.loopPointMs),
  );
  SoLoud.instance.setRelativePlaySpeed(handle, speed);
  SoLoud.instance.setPause(handle, false);

  final attackMs = (s.attackSec * 1000).round();
  if (hasAttack) {
    SoLoud.instance.fadeVolume(
      handle,
      targetVol,
      Duration(milliseconds: attackMs),
    );
  }
  if (s.sustain < 0.99 && s.decaySec > 0.01) {
    Timer(Duration(milliseconds: max(10, attackMs)), () {
      try {
        if (SoLoud.instance.getIsValidVoiceHandle(handle)) {
          SoLoud.instance.fadeVolume(
            handle,
            targetVol * s.sustain.clamp(0.0, 1.0),
            Duration(milliseconds: (s.decaySec * 1000).round().clamp(20, 4000)),
          );
        }
      } catch (_) {}
    });
  }
  return handle;
}

void releaseInstrumentNote(SoundHandle handle, {int releaseMs = 140}) {
  try {
    if (!SoLoud.instance.isInitialized) return;
    if (SoLoud.instance.getIsValidVoiceHandle(handle)) {
      final dur = Duration(milliseconds: max(20, releaseMs));
      SoLoud.instance.fadeVolume(handle, 0.0, dur);
      SoLoud.instance.scheduleStop(handle, dur);
    }
  } catch (_) {}
}

Future<Directory> getProjectMediaDirectory() async {
  Directory baseDir;
  try {
    baseDir = await getApplicationDocumentsDirectory();
  } catch (_) {
    baseDir = Directory.systemTemp;
  }
  final dir = Directory('${baseDir.path}/SoundBooth/Media');
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  return dir;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FyrTheme.initialize();
  await windowManager.ensureInitialized();
  WindowOptions windowOptions = WindowOptions(
    size: Size(1280, 720),
    center: true,
    titleBarStyle: TitleBarStyle.hidden,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setPreventClose(true);
    await windowManager.show();
    await windowManager.focus();
  });

  try {
    PlaybackDevice? initialDevice;
    LinuxAudioSink? targetLinuxSink;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedOut = prefs.getString('sb_output_device') ?? 'system_default';
      final devices = SoLoud.instance.listPlaybackDevices();
      if (Platform.isLinux) {
        final defName = await LinuxOutputRouter.getDefaultSinkName();
        final sinks = await LinuxOutputRouter.listSinks();
        if (savedOut.startsWith('dev:')) {
          final wantName = savedOut.substring(4);
          final devMatch =
              devices.where((d) => d.name == wantName).firstOrNull;
          if (devMatch != null) {
            initialDevice = devMatch;
            targetLinuxSink = matchSinkForPlaybackDevice(sinks, devMatch);
          }
        }
        if (targetLinuxSink == null && defName != null) {
          targetLinuxSink =
              sinks.where((s) => s.name == defName).firstOrNull ??
              LinuxAudioSink(name: defName, description: defName);
        }
        initialDevice ??= matchPlaybackDeviceForSink(devices, targetLinuxSink);
      } else if (savedOut.startsWith('dev:')) {
        final wantName = savedOut.substring(4);
        initialDevice =
            devices.where((d) => d.name == wantName).firstOrNull;
      }
    } catch (_) {}

    try {
      await SoLoud.instance.init(
        sampleRate: 44100,
        bufferSize: 256,
        channels: Channels.stereo,
        device: initialDevice,
      );
    } catch (_) {
      await SoLoud.instance.init(device: initialDevice);
    }
    if (Platform.isLinux && targetLinuxSink != null) {
      unawaited(
        LinuxOutputRouter.routeProcessAudioToSink(
          targetLinuxSink.name,
          targetSinkIndex: targetLinuxSink.index,
        ),
      );
    }
    SoLoud.instance.setGlobalVolume(1.0);
    try {
      SoLoud.instance.setVisualizationEnabled(true);
    } catch (_) {}
    try {
      SoLoud.instance.setMaxActiveVoiceCount(64);
    } catch (_) {}

    for (final preset in kInstrumentPresets) {
      try {
        final src = await SoLoud.instance.loadAsset(preset.assetPath);
        globalInstrumentSounds[preset.index] = src;
      } catch (e) {
        debugPrint('Failed to load instrument ${preset.name}: $e');
      }
    }

    globalSynthSound = globalInstrumentSounds[0];
    globalSawSound = globalInstrumentSounds[1];
    globalSineSound = globalInstrumentSounds[2];
    globalPianoSound = globalInstrumentSounds[3];
    globalCelloSound = globalInstrumentSounds[4];
    globalViolinSound = globalInstrumentSounds[5];

    // Synthesize punchy metronome click buffers (downbeat accent + regular beat)
    try {
      globalMetronomeAccentSound = await SoLoud.instance.loadMem(
        'sb_metronome_accent.wav',
        MetronomeSynth.generateClickWav(isDownbeat: true),
      );
      globalMetronomeBeatSound = await SoLoud.instance.loadMem(
        'sb_metronome_beat.wav',
        MetronomeSynth.generateClickWav(isDownbeat: false),
      );
    } catch (_) {}

    // Also keep legacy media directory files updated with the realistic samples
    final dir = await getProjectMediaDirectory();
    final legacyMap = {
      '${dir.path}/synth_v2.wav': 'assets/samples/synth_c4.wav',
      '${dir.path}/saw_v2.wav': 'assets/samples/saw_c3.wav',
      '${dir.path}/sine_v2.wav': 'assets/samples/sine_c3.wav',
      '${dir.path}/piano_v2.wav': 'assets/samples/piano_c4.wav',
      '${dir.path}/cello_v2.wav': 'assets/samples/cello_c3.wav',
      '${dir.path}/violin_v2.wav': 'assets/samples/violin_c4.wav',
    };
    for (final entry in legacyMap.entries) {
      try {
        final data = await rootBundle.load(entry.value);
        await File(entry.key).writeAsBytes(data.buffer.asUint8List());
      } catch (_) {}
    }
  } catch (e) {
    debugPrint("SoLoud Init failed: $e");
  }

  SharedPreferences prefs = await SharedPreferences.getInstance();
  defaultSaveLocation = prefs.getString('defaultSaveLocation') ?? '';
  _applyThemeColors();

  runApp(DawApp(key: dawAppKey));
}

GlobalKey<_DawAppState> dawAppKey = GlobalKey();

void _applyThemeColors() {
  isDarkMode = FyrTheme.isDark;
  lavenderAccent = FyrTheme.accentColor;
  if (isDarkMode) {
    bgDark = const Color(0xFF121216);
    panelDark = const Color(0xFF1C1C22);
    panelLight = const Color(0xFF282832);
    textMain = Colors.white;
    textMuted = Colors.white54;
    textFaint = Colors.white24;
    borderMain = Colors.white12;
  } else {
    bgDark = const Color(0xFFF0F0F5);
    panelDark = const Color(0xFFE0E0E8);
    panelLight = const Color(0xFFD0D0D8);
    textMain = Colors.black87;
    textMuted = Colors.black54;
    textFaint = Colors.black26;
    borderMain = Colors.black12;
  }
}

Color bgDark = const Color(0xFF2A282C);
Color panelDark = const Color(0xFF1C1C22);
Color panelLight = const Color(0xFF282832);
Color lavenderAccent = const Color(0xFFB57EDC);
Color lavenderLight = const Color(0xFFE6E6FA);
Color activeRecord = const Color(0xFFFF4B4B);

Color textMain = Colors.white;
Color textMuted = Colors.white54;
Color textFaint = Colors.white24;
Color borderMain = Colors.white12;

bool isDarkMode = true;
String defaultSaveLocation = '';

class DawApp extends StatefulWidget {
  const DawApp({super.key});
  @override
  State<DawApp> createState() => _DawAppState();
}

class _DawAppState extends State<DawApp> {
  void rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([FyrTheme.accentColorNotifier, FyrTheme.themeModeNotifier]),
      builder: (context, child) {
        _applyThemeColors();
        return MaterialApp(
          title: 'Sound Booth',
          debugShowCheckedModeBanner: false,
          theme: isDarkMode
              ? ThemeData.dark().copyWith(
                  scaffoldBackgroundColor: bgDark,
                  primaryColor: lavenderAccent,
                  colorScheme: ColorScheme.dark(
                    primary: lavenderAccent,
                    secondary: lavenderLight,
                    surface: panelDark,
                  ),
                  iconTheme: IconThemeData(color: textMuted),
                  textTheme: ThemeData.dark().textTheme.apply(
                    fontFamily: 'Inter',
                    bodyColor: textMuted,
                    displayColor: textMain,
                  ),
                )
              : ThemeData.light().copyWith(
                  scaffoldBackgroundColor: bgDark,
                  primaryColor: lavenderAccent,
                  colorScheme: ColorScheme.light(
                    primary: lavenderAccent,
                    secondary: lavenderLight,
                    surface: panelDark,
                  ),
                  iconTheme: IconThemeData(color: textMain),
                  textTheme: ThemeData.light().textTheme.apply(
                    fontFamily: 'Inter',
                    bodyColor: textMain,
                    displayColor: textMain,
                  ),
                ),
          home: DawMainScreen(),
        );
      },
    );
  }
}
