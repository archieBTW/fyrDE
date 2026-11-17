import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../engine/core_manager.dart';
import '../engine/fyremu_ffi.dart';
import '../models/emu_types.dart';

enum LibraryFilter { all, favorites, recent }

class EmuController extends ChangeNotifier {
  final FyrEmuFfi ffi = FyrEmuFfi();

  // Library state
  final List<RomEntry> library = [];
  final List<String> romFolders = [];
  LibraryFilter libraryFilter = LibraryFilter.all;
  ConsolePlatform? platformFilter;
  String searchQuery = '';

  // Input state
  InputProfile inputProfile = InputProfile.defaults();
  final Set<int> pressedKeys = {};
  final Set<RetroButton> virtualPressedButtons = {};
  List<ConnectedControllerInfo> connectedControllers = [];
  Timer? _controllerPollTimer;

  // Interactive rebinding capture state
  RetroButton? capturingButton;
  bool capturingGamepad = false;

  // Emulation session state
  RomEntry? activeRom;
  String? activeCorePath;
  bool isRunning = false;
  bool isPaused = false;
  int speedMultiplier = 1; // 1, 2, 4
  int saveStateSlot = 0;

  // Video & Audio options
  bool crtScanlines = false;
  bool integerScale = false;
  bool smoothFilter = false;
  bool showOnScreenPad = false;
  double volume = 0.85;
  bool muted = false;

  // Live Frame State
  ui.Image? currentFrameImage;
  int frameWidth = 0;
  int frameHeight = 0;
  double coreFps = 60.0;
  double coreAspectRatio = 4 / 3;
  int _lastFrameSeq = -1;
  bool _decodingFrame = false;
  Timer? _emulationTimer;
  Timer? _srmAutoSaveTimer;
  DateTime? _sessionStartTime;

  // Core download progress tracking
  final Set<String> downloadingCores = {};
  String? statusMessage;
  Timer? _statusTimer;

  String get _configDir => p.join(CoreManager.homeDir, '.config', 'fyr');
  String get _libraryFile => p.join(_configDir, 'fyremu_library.json');
  String get _inputFile => p.join(_configDir, 'fyremu_input.json');

  Future<void> initialize({String? initialRomPath}) async {
    CoreManager.ensureDirs();
    ffi.initialize();
    ffi.setDirs(CoreManager.systemDir, CoreManager.savesDir);
    ffi.setAudio(volume, muted);

    await _loadInputProfile();
    await _loadLibrary();
    await scanRomFolders();

    _controllerPollTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _pollControllersTick(),
    );

    if (initialRomPath != null &&
        initialRomPath.isNotEmpty &&
        File(initialRomPath).existsSync()) {
      await launchRomFile(initialRomPath);
    }
  }

  void refresh() => notifyListeners();

  void setStatus(String msg) {
    statusMessage = msg;
    _statusTimer?.cancel();
    _statusTimer = Timer(const Duration(seconds: 4), () {
      statusMessage = null;
      notifyListeners();
    });
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Library & ROM Folder Management
  // ---------------------------------------------------------------------------

  List<RomEntry> get filteredLibrary {
    Iterable<RomEntry> items = library;
    if (libraryFilter == LibraryFilter.favorites) {
      items = items.where((r) => r.favorite);
    } else if (libraryFilter == LibraryFilter.recent) {
      items = items.where((r) => r.lastPlayed != null);
    }
    if (platformFilter != null) {
      items = items.where((r) => r.platform == platformFilter);
    }
    if (searchQuery.trim().isNotEmpty) {
      final q = searchQuery.toLowerCase().trim();
      items = items.where((r) =>
          r.title.toLowerCase().contains(q) ||
          r.platform.shortLabel.toLowerCase().contains(q));
    }
    final list = items.toList();
    if (libraryFilter == LibraryFilter.recent) {
      list.sort((a, b) => (b.lastPlayed ?? DateTime(1970))
          .compareTo(a.lastPlayed ?? DateTime(1970)));
    } else {
      list.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    return list;
  }

  Future<void> addRomFolder(String dirPath) async {
    if (!romFolders.contains(dirPath)) {
      romFolders.add(dirPath);
      await _saveLibrary();
      await scanRomFolders();
    }
  }

  Future<void> removeRomFolder(String dirPath) async {
    romFolders.remove(dirPath);
    await _saveLibrary();
    notifyListeners();
  }

  Future<void> scanRomFolders() async {
    final existingPaths = {for (final r in library) r.path: r};
    final dirsToScan = <String>{
      ...romFolders,
      p.join(CoreManager.homeDir, 'ROMs'),
      p.join(CoreManager.homeDir, 'Games'),
    };

    for (final dirPath in dirsToScan) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;
      try {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          final ext = p.extension(entity.path).toLowerCase();
          final plat = ConsolePlatform.fromExtension(ext);
          if (plat == null) continue;
          if (!existingPaths.containsKey(entity.path)) {
            final entry = RomEntry(
              id: entity.path,
              title: p.basenameWithoutExtension(entity.path),
              path: entity.path,
              platform: plat,
            );
            library.add(entry);
            existingPaths[entity.path] = entry;
          }
        }
      } catch (_) {}
    }

    // Remove stale paths that no longer exist
    library.removeWhere((r) => !File(r.path).existsSync());
    await _saveLibrary();
    notifyListeners();
  }

  void toggleFavorite(RomEntry rom) {
    rom.favorite = !rom.favorite;
    _saveLibrary();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Input & Gamepad Polling
  // ---------------------------------------------------------------------------

  void handleKeyboardEvent(KeyEvent event) {
    final keyId = event.logicalKey.keyId;
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (capturingButton != null && !capturingGamepad) {
        inputProfile.keyboardMap[capturingButton!] = keyId;
        final boundBtn = capturingButton!;
        capturingButton = null;
        _saveInputProfile();
        setStatus('Bound ${boundBtn.label} to ${InputProfile.keyLabel(keyId)}');
        return;
      }
      pressedKeys.add(keyId);
    } else if (event is KeyUpEvent) {
      pressedKeys.remove(keyId);
    }
    _pushInputMask();
  }

  void setVirtualButton(RetroButton btn, bool down) {
    if (down) {
      virtualPressedButtons.add(btn);
    } else {
      virtualPressedButtons.remove(btn);
    }
    _pushInputMask();
    notifyListeners();
  }

  void _pollControllersTick() {
    if (!ffi.isAvailable) return;
    final list = ffi.pollControllers();
    final changedCount = list.length != connectedControllers.length;
    connectedControllers = list;

    if (capturingButton != null && capturingGamepad && list.isNotEmpty) {
      final portIdx =
          inputProfile.controllerPortIndex.clamp(0, list.length - 1);
      final ctrl = list[portIdx];
      for (int b = 0; b < ctrl.buttons.length; b++) {
        if (ctrl.buttons[b]) {
          _finishGamepadCapture(
              GamepadSource(kind: GamepadInputKind.button, index: b));
          return;
        }
      }
      for (int a = 0; a < ctrl.axes.length; a++) {
        final v = ctrl.axes[a];
        if (v < -18000) {
          _finishGamepadCapture(
              GamepadSource(kind: GamepadInputKind.axisNeg, index: a));
          return;
        }
        if (v > 18000) {
          _finishGamepadCapture(
              GamepadSource(kind: GamepadInputKind.axisPos, index: a));
          return;
        }
      }
    }

    _pushInputMask();
    if (changedCount || capturingButton != null) {
      notifyListeners();
    }
  }

  void _finishGamepadCapture(GamepadSource source) {
    final btn = capturingButton!;
    inputProfile.gamepadMap[btn] = source;
    capturingButton = null;
    capturingGamepad = false;
    _saveInputProfile();
    setStatus('Bound ${btn.label} to ${source.displayLabel}');
  }

  void beginCapture(RetroButton btn, {required bool gamepad}) {
    capturingButton = btn;
    capturingGamepad = gamepad;
    notifyListeners();
  }

  void cancelCapture() {
    capturingButton = null;
    notifyListeners();
  }

  void applyControllerPreset(String preset) {
    if (preset == 'nintendo') {
      inputProfile.gamepadMap
        ..clear()
        ..addAll(InputProfile.nintendoPreset());
    } else if (preset == 'xbox') {
      inputProfile.gamepadMap
        ..clear()
        ..addAll(InputProfile.xboxPreset());
    } else if (preset == 'reset') {
      inputProfile = InputProfile.defaults();
    }
    _saveInputProfile();
    notifyListeners();
  }

  int computeJoypadMask() {
    int mask = 0;
    for (final btn in RetroButton.values) {
      bool active = virtualPressedButtons.contains(btn);
      final kbId = inputProfile.keyboardMap[btn];
      if (!active && kbId != null && pressedKeys.contains(kbId)) {
        active = true;
      }
      if (!active && connectedControllers.isNotEmpty) {
        final portIdx = inputProfile.controllerPortIndex
            .clamp(0, connectedControllers.length - 1);
        final gp = connectedControllers[portIdx];
        final src = inputProfile.gamepadMap[btn];
        if (src != null) {
          switch (src.kind) {
            case GamepadInputKind.button:
              if (src.index < gp.buttons.length && gp.buttons[src.index]) {
                active = true;
              }
              break;
            case GamepadInputKind.axisNeg:
              if (src.index < gp.axes.length && gp.axes[src.index] < -12000) {
                active = true;
              }
              break;
            case GamepadInputKind.axisPos:
              if (src.index < gp.axes.length && gp.axes[src.index] > 12000) {
                active = true;
              }
              break;
          }
        }
        // Always also allow left analog stick (axes 0/1) for D-pad directions
        if (!active && gp.axes.length >= 2) {
          if (btn == RetroButton.left && gp.axes[0] < -14000) active = true;
          if (btn == RetroButton.right && gp.axes[0] > 14000) active = true;
          if (btn == RetroButton.up && gp.axes[1] < -14000) active = true;
          if (btn == RetroButton.down && gp.axes[1] > 14000) active = true;
        }
      }
      if (active) {
        mask |= (1 << btn.retroId);
      }
    }
    return mask;
  }

  void _pushInputMask() {
    if (!ffi.isAvailable || !isRunning) return;
    ffi.setJoypadMask(0, computeJoypadMask());
  }

  // ---------------------------------------------------------------------------
  // Emulation Control (Load, Run, Pause, Reset, Save States)
  // ---------------------------------------------------------------------------

  /// Returns `true` if started, `false` if a core is missing (caller can open Core Manager).
  Future<bool> launchRomFile(String rawPath) async {
    final resolved = await CoreManager.resolveRomPath(rawPath);
    if (resolved == null) {
      setStatus('Unsupported ROM format: ${p.basename(rawPath)}');
      return false;
    }

    // Ensure entry exists in library
    RomEntry? entry = library.where((r) => r.path == rawPath).firstOrNull;
    if (entry == null) {
      entry = RomEntry(
        id: rawPath,
        title: p.basenameWithoutExtension(rawPath),
        path: rawPath,
        platform: resolved.platform,
      );
      library.add(entry);
    }
    return launchRomEntry(entry, resolvedRomPath: resolved.romPath);
  }

  Future<bool> launchRomEntry(RomEntry entry, {String? resolvedRomPath}) async {
    if (!ffi.isAvailable) {
      setStatus('Native emulation host library (libfyremu_host.so) not loaded');
      return false;
    }

    final corePath = CoreManager.findBestCoreForPlatform(entry.platform);
    if (corePath == null) {
      setStatus(
          'No core installed for ${entry.platform.label}. Install one in Core Manager.');
      return false;
    }

    String romToLoad = resolvedRomPath ?? entry.path;
    if (p.extension(romToLoad).toLowerCase() == '.zip') {
      final res = await CoreManager.resolveRomPath(romToLoad);
      if (res == null) {
        setStatus('ZIP did not contain a supported ROM');
        return false;
      }
      romToLoad = res.romPath;
    }

    await stopEmulation();

    final rc = ffi.loadGame(corePath, romToLoad);
    if (rc != 0) {
      setStatus('Failed to load game: ${ffi.getLastError()}');
      return false;
    }

    activeRom = entry;
    activeCorePath = corePath;
    entry.lastPlayed = DateTime.now();
    isRunning = true;
    isPaused = false;
    speedMultiplier = 1;
    coreFps = ffi.fps;
    coreAspectRatio = entry.platform.aspectRatio;
    _lastFrameSeq = -1;
    _sessionStartTime = DateTime.now();

    ffi.loadSrm(_srmPathFor(entry));
    ffi.setAudio(volume, muted);
    _saveLibrary();

    final intervalUs = (1000000.0 / coreFps.clamp(30.0, 75.0)).round();
    _emulationTimer = Timer.periodic(
      Duration(microseconds: intervalUs),
      (_) => _emulationTick(),
    );
    _srmAutoSaveTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => saveBatteryRam(),
    );

    setStatus('Running ${entry.title} (${p.basename(corePath)})');
    notifyListeners();
    return true;
  }

  void _emulationTick() {
    if (!isRunning || isPaused) return;
    _pushInputMask();
    for (int i = 0; i < speedMultiplier; i++) {
      ffi.runFrame();
    }
    final seq = ffi.frameSeq;
    if (seq != _lastFrameSeq && !_decodingFrame) {
      _lastFrameSeq = seq;
      _decodeLatestFrame();
    }
  }

  Future<void> _decodeLatestFrame() async {
    final w = ffi.videoWidth;
    final h = ffi.videoHeight;
    if (w <= 0 || h <= 0) return;
    final bytes = ffi.copyFrameRgba();
    if (bytes == null) return;

    _decodingFrame = true;
    try {
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        bytes,
        w,
        h,
        ui.PixelFormat.rgba8888,
        (img) => completer.complete(img),
      );
      final img = await completer.future;
      final prev = currentFrameImage;
      currentFrameImage = img;
      frameWidth = w;
      frameHeight = h;
      prev?.dispose();
      notifyListeners();
    } finally {
      _decodingFrame = false;
    }
  }

  void togglePause() {
    if (!isRunning) return;
    isPaused = !isPaused;
    if (isPaused) saveBatteryRam();
    ffi.setAudio(volume, muted || isPaused);
    notifyListeners();
  }

  void resetGame() {
    if (!isRunning) return;
    saveBatteryRam();
    ffi.resetGame();
    isPaused = false;
    setStatus('Reset ${activeRom?.title ?? ''}');
  }

  void cycleSpeed() {
    speedMultiplier = switch (speedMultiplier) {
      1 => 2,
      2 => 4,
      _ => 1,
    };
    setStatus('Speed: ${speedMultiplier}x');
    notifyListeners();
  }

  void setVolume(double v) {
    volume = v.clamp(0.0, 1.0);
    ffi.setAudio(volume, muted || isPaused);
    notifyListeners();
  }

  void toggleMute() {
    muted = !muted;
    ffi.setAudio(volume, muted || isPaused);
    notifyListeners();
  }

  void saveBatteryRam() {
    if (!isRunning || activeRom == null) return;
    ffi.saveSrm(_srmPathFor(activeRom!));
  }

  void saveQuickState([int? slot]) {
    if (!isRunning || activeRom == null) return;
    final s = slot ?? saveStateSlot;
    final path = _statePathFor(activeRom!, s);
    if (ffi.saveState(path)) {
      setStatus('Saved State to Slot $s');
    } else {
      setStatus('Core failed to save state');
    }
  }

  void loadQuickState([int? slot]) {
    if (!isRunning || activeRom == null) return;
    final s = slot ?? saveStateSlot;
    final path = _statePathFor(activeRom!, s);
    if (!File(path).existsSync()) {
      setStatus('No Save State in Slot $s');
      return;
    }
    if (ffi.loadState(path)) {
      setStatus('Loaded State from Slot $s');
    } else {
      setStatus('Failed to load state from Slot $s');
    }
  }

  bool hasStateInSlot(int slot) {
    if (activeRom == null) return false;
    return File(_statePathFor(activeRom!, slot)).existsSync();
  }

  Future<void> stopEmulation() async {
    _emulationTimer?.cancel();
    _emulationTimer = null;
    _srmAutoSaveTimer?.cancel();
    _srmAutoSaveTimer = null;

    if (isRunning && activeRom != null) {
      saveBatteryRam();
      if (_sessionStartTime != null) {
        activeRom!.playTimeSeconds +=
            DateTime.now().difference(_sessionStartTime!).inSeconds;
        _saveLibrary();
      }
      ffi.unloadGame();
    }

    isRunning = false;
    isPaused = false;
    activeRom = null;
    activeCorePath = null;
    _sessionStartTime = null;
    currentFrameImage?.dispose();
    currentFrameImage = null;
    frameWidth = 0;
    frameHeight = 0;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Core Management
  // ---------------------------------------------------------------------------

  Future<void> downloadRecommendedCore(CoreDownloadSpec spec) async {
    if (downloadingCores.contains(spec.id)) return;
    downloadingCores.add(spec.id);
    notifyListeners();
    try {
      final path = await CoreManager.downloadCore(spec);
      setStatus('Installed ${spec.name} (${p.basename(path)})');
    } catch (e) {
      setStatus('Failed to download ${spec.name}: $e');
    } finally {
      downloadingCores.remove(spec.id);
      notifyListeners();
    }
  }

  Future<void> importCoreFile(String path) async {
    try {
      final dst = await CoreManager.importLocalCore(path);
      setStatus('Imported core: ${p.basename(dst)}');
      notifyListeners();
    } catch (e) {
      setStatus('Failed to import core: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  String _romKey(RomEntry rom) =>
      rom.title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

  String _srmPathFor(RomEntry rom) =>
      p.join(CoreManager.savesDir, '${_romKey(rom)}.srm');

  String _statePathFor(RomEntry rom, int slot) =>
      p.join(CoreManager.statesDir, '${_romKey(rom)}_slot$slot.state');

  Future<void> _loadLibrary() async {
    try {
      final f = File(_libraryFile);
      if (!f.existsSync()) return;
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      romFolders
        ..clear()
        ..addAll((data['folders'] as List<dynamic>? ?? []).cast<String>());
      library.clear();
      for (final item in (data['roms'] as List<dynamic>? ?? [])) {
        library.add(RomEntry.fromJson(item as Map<String, dynamic>));
      }
    } catch (_) {}
  }

  Future<void> _saveLibrary() async {
    try {
      final dir = Directory(_configDir);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      await File(_libraryFile).writeAsString(jsonEncode({
        'folders': romFolders,
        'roms': library.map((e) => e.toJson()).toList(),
      }));
    } catch (_) {}
  }

  Future<void> _loadInputProfile() async {
    try {
      final f = File(_inputFile);
      if (!f.existsSync()) return;
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      inputProfile = InputProfile.fromJson(data);
    } catch (_) {}
  }

  Future<void> _saveInputProfile() async {
    try {
      final dir = Directory(_configDir);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      await File(_inputFile).writeAsString(jsonEncode(inputProfile.toJson()));
    } catch (_) {}
  }

  @override
  void dispose() {
    _controllerPollTimer?.cancel();
    _emulationTimer?.cancel();
    _srmAutoSaveTimer?.cancel();
    _statusTimer?.cancel();
    if (isRunning) {
      saveBatteryRam();
      ffi.unloadGame();
    }
    ffi.dispose();
    currentFrameImage?.dispose();
    super.dispose();
  }
}
