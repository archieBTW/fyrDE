import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:async';
import 'dart:io';
import 'package:dotted_border/dotted_border.dart';
import 'dart:convert';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:fyrdaw/wav_writer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fyrdaw/models/enums.dart';
import 'package:fyrdaw/models/daw_clip.dart';
import 'package:fyrdaw/models/daw_effect.dart';
import 'package:fyrdaw/models/automation_point.dart';
import 'package:fyrdaw/models/track.dart';
import 'package:fyrdaw/models/midi_note.dart';
import 'package:fyrdaw/ui/dial.dart';
import 'package:fyrdaw/ui/painters.dart';
import 'package:fyrdaw/ui/midi_editor.dart';
import 'package:fyrdaw/ui/sampler_editor.dart';
import 'fyr_theme.dart';

part 'ui/daw_main_screen.dart';

AudioSource? globalSynthSound;
AudioSource? globalSawSound;
AudioSource? globalSineSound;
AudioSource? globalPianoSound;
AudioSource? globalCelloSound;
AudioSource? globalViolinSound;
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
}) {
  if (!SoLoud.instance.isInitialized) return null;
  final preset = getInstrumentPreset(track.instrumentIndex);
  final src = getInstrumentAudioSource(track);
  if (src == null) return null;

  track.bus ??= Bus()..playOnEngine();
  final double targetVol =
      ((velocity.clamp(1, 127) / 127.0) *
              track.volume *
              preset.volumeMultiplier *
              volumeScale)
          .clamp(0.0, 2.5);
  final double speed = pow(2.0, (midiPitch - preset.basePitch) / 12.0)
      .toDouble()
      .clamp(0.05, 16.0);

  final handle = track.bus!.play(
    src,
    volume: targetVol,
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
  return handle;
}

void releaseInstrumentNote(SoundHandle handle, {int releaseMs = 140}) {
  if (!SoLoud.instance.isInitialized) return;
  try {
    if (SoLoud.instance.getIsValidVoiceHandle(handle)) {
      final dur = Duration(milliseconds: max(20, releaseMs));
      SoLoud.instance.fadeVolume(handle, 0.0, dur);
      SoLoud.instance.scheduleStop(handle, dur);
    }
  } catch (_) {}
}

Future<Directory> getProjectMediaDirectory() async {
  final docsDir = await getApplicationDocumentsDirectory();
  final dir = Directory('${docsDir.path}/FyrDAW/Media');
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
    try {
      await SoLoud.instance.init(
        sampleRate: 44100,
        bufferSize: 256,
        channels: Channels.stereo,
      );
    } catch (_) {
      await SoLoud.instance.init();
    }
    SoLoud.instance.setGlobalVolume(1.0);
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
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([FyrTheme.accentColorNotifier, FyrTheme.themeModeNotifier]),
      builder: (context, child) {
        _applyThemeColors();
        return MaterialApp(
          title: 'fyrDAW',
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
