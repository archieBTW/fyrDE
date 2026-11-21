import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:fyrdaw/models/daw_clip.dart';
import 'package:fyrdaw/models/daw_effect.dart';
import 'package:fyrdaw/models/enums.dart';
import 'package:fyrdaw/models/midi_mapping.dart';
import 'package:fyrdaw/models/song_marker.dart';
import 'package:fyrdaw/models/tempo_marker.dart';
import 'package:fyrdaw/models/track.dart';
import 'package:fyrdaw/utils/dsp_isolate.dart';
import 'package:path_provider/path_provider.dart';

String _basename(String filePath) {
  final normalized = filePath.replaceAll('\\', '/');
  final idx = normalized.lastIndexOf('/');
  return idx >= 0 ? normalized.substring(idx + 1) : normalized;
}

/// Encapsulates `.adaw` ZIP project archiving, extraction, media-path
/// normalization, and crash auto-save recovery outside UI widget code.
class ProjectArchiveService {
  static Future<File> _autoSaveFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final dawDir = Directory('${dir.path}/SoundBooth');
    if (!dawDir.existsSync()) dawDir.createSync(recursive: true);
    return File('${dawDir.path}/autosave.json');
  }

  static Future<void> writeAutoSave(String stateJson) async {
    try {
      final file = await _autoSaveFile();
      await file.writeAsString(stateJson);
    } catch (_) {}
  }

  static Future<File?> findExistingAutoSaveFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/SoundBooth/autosave.json');
      if (await file.exists()) return file;
    } catch (_) {}
    return null;
  }

  static Future<void> clearAutoSave() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/SoundBooth/autosave.json');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// Builds a portable JSON-serializable map for saving into `project.json`
  /// alongside the list of absolute disk media files to bundle into `.adaw`.
  static ({Map<String, dynamic> projectData, List<String> mediaFilePaths})
  buildArchivePayload({
    required int bpm,
    required int timeSigTop,
    required int timeSigBottom,
    required double metronomeVolume,
    required double masterVolume,
    required bool masterLimiter,
    required double masterLufsTarget,
    required List<DawEffect> masterEffectsChain,
    required List<MidiCcMapping> midiMappings,
    required double auxReverbMix,
    required double auxDelayMix,
    required List<SongMarker> songMarkers,
    required List<TempoMarker> tempoMarkers,
    required List<Track> tracks,
    required Map<String, List<DawClip>> trackClips,
  }) {
    final mediaFiles = <String>{};

    final tracksJson = tracks.map((t) {
      final j = t.toJson();
      if (j['type'] == TrackType.sampler.index) {
        final newPads = <String, dynamic>{};
        (j['samplerPads'] as Map).forEach((k, v) {
          final padData = Map<String, dynamic>.from(v);
          final fp = padData['filePath']?.toString();
          if (fp != null && fp.isNotEmpty && !fp.startsWith('assets/')) {
            mediaFiles.add(fp);
            padData['filePath'] = _basename(fp);
          }
          newPads[k.toString()] = padData;
        });
        j['samplerPads'] = newPads;
      }
      return j;
    }).toList();

    final clipsJson = <String, List<Map<String, dynamic>>>{};
    trackClips.forEach((k, clips) {
      clipsJson[k] = clips.map((c) {
        final j = c.toJson();
        if (c is AudioClip) {
          if (c.filePath.isNotEmpty) {
            mediaFiles.add(c.filePath);
          }
          j['filePath'] = _basename(c.filePath);
        }
        return j;
      }).toList();
    });

    final projectData = <String, dynamic>{
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

    return (projectData: projectData, mediaFilePaths: mediaFiles.toList());
  }

  /// Compresses [projectData] and all existing [mediaFilePaths] into a `.adaw`
  /// ZIP archive at [outputPath] on a background isolate.
  static Future<void> saveArchiveToPath({
    required String outputPath,
    required Map<String, dynamic> projectData,
    required List<String> mediaFilePaths,
    bool useIsolate = true,
  }) {
    final jsonStr = jsonEncode(projectData);
    return runInBackgroundIsolate(() {
      final archive = Archive();
      final jsonBytes = utf8.encode(jsonStr);
      archive.addFile(ArchiveFile('project.json', jsonBytes.length, jsonBytes));

      final addedBasenames = <String>{};
      for (final filePath in mediaFilePaths) {
        final f = File(filePath);
        if (!f.existsSync()) continue;
        final base = _basename(filePath);
        if (!addedBasenames.add(base)) continue;
        final bytes = f.readAsBytesSync();
        archive.addFile(ArchiveFile(base, bytes.length, bytes));
      }

      final zipData = ZipEncoder().encode(archive);
      File(outputPath).writeAsBytesSync(zipData);
    }, useIsolate: useIsolate);
  }

  /// Reads a `.adaw` ZIP (or legacy raw JSON) project file from [path],
  /// extracts bundled audio files into [mediaDirPath], and returns the decoded
  /// `project.json` map with relative media paths resolved to [mediaDirPath].
  static Future<Map<String, dynamic>> loadArchiveFromPath({
    required String path,
    required String mediaDirPath,
    bool useIsolate = true,
  }) {
    return runInBackgroundIsolate(() {
      final fileBytes = File(path).readAsBytesSync();
      String jsonStr;

      if (fileBytes.isNotEmpty && fileBytes[0] == '{'.codeUnitAt(0)) {
        jsonStr = utf8.decode(fileBytes);
      } else {
        final archive = ZipDecoder().decodeBytes(fileBytes);
        final jsonArchiveFile = archive.findFile('project.json');
        if (jsonArchiveFile == null) {
          throw Exception('Invalid adaw file: missing project.json');
        }
        jsonStr = utf8.decode(jsonArchiveFile.content as List<int>);

        final mediaDir = Directory(mediaDirPath);
        if (!mediaDir.existsSync()) {
          mediaDir.createSync(recursive: true);
        }
        for (final file in archive) {
          if (file.name != 'project.json' && file.isFile) {
            final outFile = File('$mediaDirPath/${file.name}');
            outFile.writeAsBytesSync(file.content as List<int>);
          }
        }
      }

      final projectData = Map<String, dynamic>.from(jsonDecode(jsonStr) as Map);
      resolveRelativeMediaPaths(projectData, mediaDirPath);
      return projectData;
    }, useIsolate: useIsolate);
  }

  /// Mutates relative sampler pad & audio clip paths in [projectData] so they
  /// point to extracted files inside [mediaDirPath].
  static void resolveRelativeMediaPaths(
    Map<String, dynamic> projectData,
    String mediaDirPath,
  ) {
    final tracks = projectData['tracks'];
    if (tracks is List) {
      for (final t in tracks) {
        if (t is Map &&
            t['type'] == TrackType.sampler.index &&
            t['samplerPads'] is Map) {
          (t['samplerPads'] as Map).forEach((_, v) {
            if (v is Map && v['filePath'] != null) {
              final fp = v['filePath'].toString();
              if (fp.isNotEmpty &&
                  !fp.startsWith('/') &&
                  !fp.startsWith('assets/')) {
                v['filePath'] = '$mediaDirPath/$fp';
              }
            }
          });
        }
      }
    }

    final tc = projectData['trackClips'];
    if (tc is Map) {
      tc.forEach((_, v) {
        if (v is List) {
          for (final c in v) {
            if (c is Map && c['filePath'] != null) {
              final fp = c['filePath'].toString();
              if (fp.isNotEmpty &&
                  !fp.startsWith('/') &&
                  !fp.startsWith('assets/')) {
                c['filePath'] = '$mediaDirPath/$fp';
              }
            }
          }
        }
      });
    }
  }
}
