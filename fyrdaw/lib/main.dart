import 'dart:ui';
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
    await SoLoud.instance.init();
    SoLoud.instance.setGlobalVolume(1.0);
    final dir = await getProjectMediaDirectory();
    final fileSq = File('${dir.path}/synth_v2.wav');
    final fileSaw = File('${dir.path}/saw_v2.wav');
    final fileSine = File('${dir.path}/sine_v2.wav');
    final filePiano = File('${dir.path}/piano_v2.wav');
    final fileCello = File('${dir.path}/cello_v2.wav');
    final fileViolin = File('${dir.path}/violin_v2.wav');
    if (!fileSq.existsSync() || !filePiano.existsSync()) {
      List<int> pcmSq = [];
      List<int> pcmSaw = [];
      List<int> pcmSine = [];
      List<int> pcmPiano = [];
      List<int> pcmCello = [];
      List<int> pcmViolin = [];
      for (int i = 0; i < 44100 * 4; i++) {
        double t = i / 44100;
        double f = 440.0;
        double valSq = (sin(2 * pi * f * t) > 0) ? 0.25 : -0.25;
        double valSaw = 2.0 * (t * f - (t * f + 0.5).floor()) * 0.25;
        double valSine = sin(2 * pi * f * t) * 0.25;

        double pianoEnv = exp(-t * 3);
        double valPiano =
            (sin(2 * pi * f * t) +
                0.3 * sin(2 * pi * f * 2 * t) +
                0.1 * sin(2 * pi * f * 3 * t)) *
            pianoEnv *
            0.25;

        double celloVib = sin(2 * pi * 5 * t) * 0.01;
        double celloEnv = (1 - exp(-t * 10)) * exp(-t * 1);
        double tCello = t + celloVib;
        double valCello =
            2.0 * (tCello * f - (tCello * f + 0.5).floor()) * celloEnv * 0.25;

        double violinVib = sin(2 * pi * 6 * t) * 0.015;
        double violinEnv = (1 - exp(-t * 15)) * exp(-t * 0.5);
        double tViolin = t + violinVib;
        double valViolin =
            2.0 *
            (tViolin * f - (tViolin * f + 0.5).floor()) *
            violinEnv *
            0.25;

        int sSq = (valSq * 32767).toInt();
        pcmSq.add(sSq & 0xff);
        pcmSq.add((sSq >> 8) & 0xff);
        pcmSq.add(sSq & 0xff);
        pcmSq.add((sSq >> 8) & 0xff);
        int sSaw = (valSaw * 32767).toInt();
        pcmSaw.add(sSaw & 0xff);
        pcmSaw.add((sSaw >> 8) & 0xff);
        pcmSaw.add(sSaw & 0xff);
        pcmSaw.add((sSaw >> 8) & 0xff);
        int sSine = (valSine * 32767).toInt();
        pcmSine.add(sSine & 0xff);
        pcmSine.add((sSine >> 8) & 0xff);
        pcmSine.add(sSine & 0xff);
        pcmSine.add((sSine >> 8) & 0xff);

        int sPiano = (valPiano * 32767).toInt();
        pcmPiano.add(sPiano & 0xff);
        pcmPiano.add((sPiano >> 8) & 0xff);
        pcmPiano.add(sPiano & 0xff);
        pcmPiano.add((sPiano >> 8) & 0xff);
        int sCello = (valCello * 32767).toInt();
        pcmCello.add(sCello & 0xff);
        pcmCello.add((sCello >> 8) & 0xff);
        pcmCello.add(sCello & 0xff);
        pcmCello.add((sCello >> 8) & 0xff);
        int sViolin = (valViolin * 32767).toInt();
        pcmViolin.add(sViolin & 0xff);
        pcmViolin.add((sViolin >> 8) & 0xff);
        pcmViolin.add(sViolin & 0xff);
        pcmViolin.add((sViolin >> 8) & 0xff);
      }
      void writeWav(File f, List<int> pcm) {
        int byteRate = 44100 * 4;
        var dataSize = pcm.length;
        var fileSize = dataSize + 36;
        List<int> wav = [
          82,
          73,
          70,
          70,
          fileSize & 0xff,
          (fileSize >> 8) & 0xff,
          (fileSize >> 16) & 0xff,
          (fileSize >> 24) & 0xff,
          87,
          65,
          86,
          69,
          102,
          109,
          116,
          32,
          16,
          0,
          0,
          0,
          1,
          0,
          2,
          0,
          68,
          172,
          0,
          0,
          16,
          177,
          2,
          0,
          4,
          0,
          16,
          0,
          100,
          97,
          116,
          97,
          dataSize & 0xff,
          (dataSize >> 8) & 0xff,
          (dataSize >> 16) & 0xff,
          (dataSize >> 24) & 0xff,
        ];
        wav.addAll(pcm);
        f.writeAsBytesSync(wav);
      }

      writeWav(fileSq, pcmSq);
      writeWav(fileSaw, pcmSaw);
      writeWav(fileSine, pcmSine);
      writeWav(filePiano, pcmPiano);
      writeWav(fileCello, pcmCello);
      writeWav(fileViolin, pcmViolin);
    }
    globalSynthSound = await SoLoud.instance.loadFile(fileSq.path);
    globalSawSound = await SoLoud.instance.loadFile(fileSaw.path);
    globalSineSound = await SoLoud.instance.loadFile(fileSine.path);
    globalPianoSound = await SoLoud.instance.loadAsset(
      'assets/samples/piano_c4.wav',
    );
    globalCelloSound = await SoLoud.instance.loadAsset(
      'assets/samples/cello_c3.wav',
    );
    globalViolinSound = await SoLoud.instance.loadAsset(
      'assets/samples/violin_c4.wav',
    );
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
