import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

typedef _SetDirsNative = Void Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _SetDirsDart = void Function(Pointer<Utf8>, Pointer<Utf8>);

typedef _GetLastErrorNative = Pointer<Utf8> Function();
typedef _GetLastErrorDart = Pointer<Utf8> Function();

typedef _UnloadNative = Void Function();
typedef _UnloadDart = void Function();

typedef _LoadNative = Int32 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _LoadDart = int Function(Pointer<Utf8>, Pointer<Utf8>);

typedef _RunFrameNative = Void Function();
typedef _RunFrameDart = void Function();

typedef _ResetNative = Void Function();
typedef _ResetDart = void Function();

typedef _SetJoypadMaskNative = Void Function(Int32, Uint32);
typedef _SetJoypadMaskDart = void Function(int, int);

typedef _SetAudioNative = Void Function(Float, Int32);
typedef _SetAudioDart = void Function(double, int);

typedef _GetDoubleNative = Double Function();
typedef _GetDoubleDart = double Function();

typedef _GetIntNative = Int32 Function();
typedef _GetIntDart = int Function();

typedef _GetUint64Native = Uint64 Function();
typedef _GetUint64Dart = int Function();

typedef _CopyFrameNative = Int32 Function(Pointer<Uint8>, Int32);
typedef _CopyFrameDart = int Function(Pointer<Uint8>, int);

typedef _PathOpNative = Int32 Function(Pointer<Utf8>);
typedef _PathOpDart = int Function(Pointer<Utf8>);

typedef _PollControllersNative = Void Function();
typedef _PollControllersDart = void Function();

typedef _GetCtrlIntNative = Int32 Function(Int32);
typedef _GetCtrlIntDart = int Function(int);

typedef _GetCtrlNameNative = Void Function(Int32, Pointer<Utf8>, Int32);
typedef _GetCtrlNameDart = void Function(int, Pointer<Utf8>, int);

typedef _GetCtrlStateNative = Int32 Function(Int32, Int32);
typedef _GetCtrlStateDart = int Function(int, int);

class ConnectedControllerInfo {
  final int index;
  final String name;
  final int buttonCount;
  final int axisCount;
  final List<bool> buttons;
  final List<int> axes;

  ConnectedControllerInfo({
    required this.index,
    required this.name,
    required this.buttonCount,
    required this.axisCount,
    required this.buttons,
    required this.axes,
  });
}

class FyrEmuFfi {
  DynamicLibrary? _lib;
  bool get isAvailable => _lib != null;

  late _SetDirsDart _setDirs;
  late _GetLastErrorDart _getLastError;
  late _UnloadDart _unload;
  late _LoadDart _load;
  late _RunFrameDart _runFrame;
  late _ResetDart _reset;
  late _SetJoypadMaskDart _setJoypadMask;
  late _SetAudioDart _setAudio;
  late _GetDoubleDart _getFps;
  late _GetDoubleDart _getAspectRatio;
  late _GetIntDart _getVideoWidth;
  late _GetIntDart _getVideoHeight;
  late _GetUint64Dart _getFrameSeq;
  late _CopyFrameDart _copyFrameRgba;
  late _PathOpDart _saveSrm;
  late _PathOpDart _loadSrm;
  late _PathOpDart _saveState;
  late _PathOpDart _loadState;
  late _PollControllersDart _pollControllers;
  late _GetCtrlIntDart _getControllerConnected;
  late _GetCtrlNameDart _getControllerName;
  late _GetCtrlIntDart _getControllerButtonCount;
  late _GetCtrlIntDart _getControllerAxisCount;
  late _GetCtrlStateDart _getControllerButton;
  late _GetCtrlStateDart _getControllerAxis;

  Pointer<Uint8>? _frameNativeBuf;
  int _frameNativeCap = 0;

  bool initialize() {
    if (_lib != null) return true;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = [
      p.join(exeDir, 'lib', 'libfyremu_host.so'),
      p.join(Directory.current.path, 'build', 'linux', 'x64', 'release', 'bundle', 'lib', 'libfyremu_host.so'),
      p.join(Directory.current.path, 'build', 'linux', 'x64', 'debug', 'bundle', 'lib', 'libfyremu_host.so'),
      '/opt/fyremu/lib/libfyremu_host.so',
      'libfyremu_host.so',
    ];

    for (final path in candidates) {
      try {
        if (path != 'libfyremu_host.so' && !File(path).existsSync()) {
          continue;
        }
        _lib = DynamicLibrary.open(path);
        break;
      } catch (_) {}
    }
    if (_lib == null) return false;

    final lib = _lib!;
    _setDirs = lib.lookupFunction<_SetDirsNative, _SetDirsDart>('fyremu_set_dirs');
    _getLastError =
        lib.lookupFunction<_GetLastErrorNative, _GetLastErrorDart>('fyremu_get_last_error');
    _unload = lib.lookupFunction<_UnloadNative, _UnloadDart>('fyremu_unload');
    _load = lib.lookupFunction<_LoadNative, _LoadDart>('fyremu_load');
    _runFrame =
        lib.lookupFunction<_RunFrameNative, _RunFrameDart>('fyremu_run_frame');
    _reset = lib.lookupFunction<_ResetNative, _ResetDart>('fyremu_reset');
    _setJoypadMask = lib.lookupFunction<_SetJoypadMaskNative, _SetJoypadMaskDart>(
        'fyremu_set_joypad_mask');
    _setAudio =
        lib.lookupFunction<_SetAudioNative, _SetAudioDart>('fyremu_set_audio');
    _getFps = lib.lookupFunction<_GetDoubleNative, _GetDoubleDart>('fyremu_get_fps');
    _getAspectRatio = lib.lookupFunction<_GetDoubleNative, _GetDoubleDart>(
        'fyremu_get_aspect_ratio');
    _getVideoWidth = lib.lookupFunction<_GetIntNative, _GetIntDart>(
        'fyremu_get_video_width');
    _getVideoHeight = lib.lookupFunction<_GetIntNative, _GetIntDart>(
        'fyremu_get_video_height');
    _getFrameSeq =
        lib.lookupFunction<_GetUint64Native, _GetUint64Dart>('fyremu_get_frame_seq');
    _copyFrameRgba = lib.lookupFunction<_CopyFrameNative, _CopyFrameDart>(
        'fyremu_copy_frame_rgba');
    _saveSrm = lib.lookupFunction<_PathOpNative, _PathOpDart>('fyremu_save_srm');
    _loadSrm = lib.lookupFunction<_PathOpNative, _PathOpDart>('fyremu_load_srm');
    _saveState =
        lib.lookupFunction<_PathOpNative, _PathOpDart>('fyremu_save_state');
    _loadState =
        lib.lookupFunction<_PathOpNative, _PathOpDart>('fyremu_load_state');
    _pollControllers =
        lib.lookupFunction<_PollControllersNative, _PollControllersDart>(
            'fyremu_poll_controllers');
    _getControllerConnected =
        lib.lookupFunction<_GetCtrlIntNative, _GetCtrlIntDart>(
            'fyremu_get_controller_connected');
    _getControllerName =
        lib.lookupFunction<_GetCtrlNameNative, _GetCtrlNameDart>(
            'fyremu_get_controller_name');
    _getControllerButtonCount =
        lib.lookupFunction<_GetCtrlIntNative, _GetCtrlIntDart>(
            'fyremu_get_controller_button_count');
    _getControllerAxisCount =
        lib.lookupFunction<_GetCtrlIntNative, _GetCtrlIntDart>(
            'fyremu_get_controller_axis_count');
    _getControllerButton =
        lib.lookupFunction<_GetCtrlStateNative, _GetCtrlStateDart>(
            'fyremu_get_controller_button');
    _getControllerAxis =
        lib.lookupFunction<_GetCtrlStateNative, _GetCtrlStateDart>(
            'fyremu_get_controller_axis');
    return true;
  }

  void setDirs(String sysDir, String saveDir) {
    if (!isAvailable) return;
    final p1 = sysDir.toNativeUtf8();
    final p2 = saveDir.toNativeUtf8();
    try {
      _setDirs(p1, p2);
    } finally {
      calloc.free(p1);
      calloc.free(p2);
    }
  }

  String getLastError() {
    if (!isAvailable) return 'Native host library not loaded';
    return _getLastError().toDartString();
  }

  int loadGame(String corePath, String romPath) {
    if (!isAvailable) return -99;
    final pCore = corePath.toNativeUtf8();
    final pRom = romPath.toNativeUtf8();
    try {
      return _load(pCore, pRom);
    } finally {
      calloc.free(pCore);
      calloc.free(pRom);
    }
  }

  void unloadGame() {
    if (!isAvailable) return;
    _unload();
  }

  void runFrame() {
    if (!isAvailable) return;
    _runFrame();
  }

  void resetGame() {
    if (!isAvailable) return;
    _reset();
  }

  void setJoypadMask(int port, int mask) {
    if (!isAvailable) return;
    _setJoypadMask(port, mask);
  }

  void setAudio(double volume, bool muted) {
    if (!isAvailable) return;
    _setAudio(volume, muted ? 1 : 0);
  }

  double get fps => isAvailable ? _getFps() : 60.0;
  double get aspectRatio => isAvailable ? _getAspectRatio() : 4 / 3;
  int get videoWidth => isAvailable ? _getVideoWidth() : 0;
  int get videoHeight => isAvailable ? _getVideoHeight() : 0;
  int get frameSeq => isAvailable ? _getFrameSeq() : 0;

  Uint8List? copyFrameRgba() {
    if (!isAvailable) return null;
    final w = _getVideoWidth();
    final h = _getVideoHeight();
    if (w <= 0 || h <= 0) return null;
    final needed = w * h * 4;
    if (needed > _frameNativeCap || _frameNativeBuf == null) {
      if (_frameNativeBuf != null) calloc.free(_frameNativeBuf!);
      _frameNativeBuf = calloc<Uint8>(needed);
      _frameNativeCap = needed;
    }
    final copied = _copyFrameRgba(_frameNativeBuf!, needed);
    if (copied <= 0) return null;
    return Uint8List.fromList(_frameNativeBuf!.asTypedList(copied));
  }

  bool saveSrm(String path) {
    if (!isAvailable) return false;
    final pPath = path.toNativeUtf8();
    try {
      return _saveSrm(pPath) >= 0;
    } finally {
      calloc.free(pPath);
    }
  }

  bool loadSrm(String path) {
    if (!isAvailable) return false;
    final pPath = path.toNativeUtf8();
    try {
      return _loadSrm(pPath) >= 0;
    } finally {
      calloc.free(pPath);
    }
  }

  bool saveState(String path) {
    if (!isAvailable) return false;
    final pPath = path.toNativeUtf8();
    try {
      return _saveState(pPath) == 0;
    } finally {
      calloc.free(pPath);
    }
  }

  bool loadState(String path) {
    if (!isAvailable) return false;
    final pPath = path.toNativeUtf8();
    try {
      return _loadState(pPath) == 0;
    } finally {
      calloc.free(pPath);
    }
  }

  List<ConnectedControllerInfo> pollControllers() {
    if (!isAvailable) return [];
    _pollControllers();
    final out = <ConnectedControllerInfo>[];
    final nameBuf = calloc<Uint8>(128).cast<Utf8>();
    try {
      for (int i = 0; i < 4; i++) {
        if (_getControllerConnected(i) == 0) continue;
        _getControllerName(i, nameBuf, 128);
        final bCount = _getControllerButtonCount(i).clamp(0, 64);
        final aCount = _getControllerAxisCount(i).clamp(0, 32);
        final btns = List<bool>.generate(
            bCount, (b) => _getControllerButton(i, b) != 0);
        final axes =
            List<int>.generate(aCount, (a) => _getControllerAxis(i, a));
        out.add(ConnectedControllerInfo(
          index: i,
          name: nameBuf.toDartString(),
          buttonCount: bCount,
          axisCount: aCount,
          buttons: btns,
          axes: axes,
        ));
      }
    } finally {
      calloc.free(nameBuf);
    }
    return out;
  }

  void dispose() {
    if (_frameNativeBuf != null) {
      calloc.free(_frameNativeBuf!);
      _frameNativeBuf = null;
      _frameNativeCap = 0;
    }
  }
}
