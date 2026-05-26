import 'package:flutter/material.dart';
import 'package:fyrtaskbar/features/quick_settings/models/audio_device.dart';
import 'package:fyrtaskbar/features/quick_settings/models/bluetooth_device.dart';
import 'package:fyrtaskbar/features/quick_settings/models/wifi_network.dart';
import 'package:fyrtaskbar/features/quick_settings/services/quick_settings_service.dart';
import 'package:fyrtaskbar/fyr_theme.dart';
import 'package:fyrtaskbar/state/system_state.dart';

enum QuickSettingsMenu { main, wifi, bluetooth, screenshot, audio }

class QuickSettingsController extends ChangeNotifier {
  final VoidCallback onClose;

  QuickSettingsMenu _currentMenu = QuickSettingsMenu.main;
  List<WifiNetwork> _wifiNetworks = [];
  List<BluetoothDevice> _btDevices = [];
  List<AudioDevice> _sinks = [];
  List<AudioDevice> _sources = [];
  String _defaultSink = '';
  String _defaultSource = '';
  bool _isScanning = false;

  late final AnimationController _animCtrl;
  late final Animation<Offset> _slideAnim;

  QuickSettingsController({required TickerProvider vsync, required this.onClose}) {
    _animCtrl = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: vsync,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0.0, -1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOutQuart,
    ));
    _animCtrl.forward();

    SystemState.brightness.addListener(_onSysChange);
    SystemState.bluetoothEnabled.addListener(_onSysChange);
    SystemState.volume.addListener(_onSysChange);
    SystemState.nightLight.addListener(_onSysChange);
    SystemState.wifiSsid.addListener(_onSysChange);
    SystemState.airplaneMode.addListener(_onSysChange);
    SystemState.isRecording.addListener(_onSysChange);
    SystemState.dockAutohide.addListener(_onSysChange);
    FyrTheme.themeModeNotifier.addListener(_onSysChange);

    _checkRecording();
  }

  void _onSysChange() => notifyListeners();

  // --- Getters: SystemState-backed values ---

  double get brightness => SystemState.brightness.value;
  double get volume => SystemState.volume.value;
  bool get wifiEnabled => SystemState.wifiSsid.value != null;
  String get wifiLabel => SystemState.wifiSsid.value ?? 'Wi-Fi';
  bool get bluetoothEnabled => SystemState.bluetoothEnabled.value;
  List<String> get connectedBtDevices => SystemState.bluetoothDevices.value;
  bool get hasConnectedBt => SystemState.bluetoothDevices.value.isNotEmpty;
  String get bluetoothLabel =>
      hasConnectedBt ? SystemState.bluetoothDevices.value.first : 'Bluetooth';
  bool get nightLightEnabled => SystemState.nightLight.value;
  bool get airplaneModeEnabled => SystemState.airplaneMode.value;
  bool get dockAutohideEnabled => SystemState.dockAutohide.value;
  bool get isRecording => SystemState.isRecording.value;
  bool get isDarkMode =>
      FyrTheme.themeModeNotifier.value == ThemeMode.dark;

  // --- Getters: local state ---

  QuickSettingsMenu get currentMenu => _currentMenu;
  List<WifiNetwork> get wifiNetworks => _wifiNetworks;
  List<BluetoothDevice> get btDevices => _btDevices;
  List<AudioDevice> get sinks => _sinks;
  List<AudioDevice> get sources => _sources;
  String get defaultSink => _defaultSink;
  String get defaultSource => _defaultSource;
  bool get isScanning => _isScanning;
  Animation<Offset> get slideAnimation => _slideAnim;

  // --- Navigation ---

  void goTo(QuickSettingsMenu menu) {
    _currentMenu = menu;
    notifyListeners();
  }

  void goBack() {
    _currentMenu = QuickSettingsMenu.main;
    notifyListeners();
  }

  // --- Toggles ---

  void toggleWifi() {
    final on = !wifiEnabled;
    QuickSettingsService.setWifiRadio(on);
    notifyListeners();
  }

  void toggleBluetooth() {
    final on = !bluetoothEnabled;
    QuickSettingsService.setBluetoothPower(on);
    notifyListeners();
  }

  void toggleNightLight() {
    final on = !nightLightEnabled;
    QuickSettingsService.setNightLight(on);
    notifyListeners();
  }

  void toggleAirplaneMode() {
    final on = !airplaneModeEnabled;
    QuickSettingsService.setAirplaneMode(on);
    notifyListeners();
  }

  Future<void> toggleDockAutohide() async {
    final newVal = !SystemState.dockAutohide.value;
    SystemState.dockAutohide.value = newVal;
    await QuickSettingsService.writeDockConfig(newVal);
    notifyListeners();
  }

  void toggleTheme() {
    FyrTheme.setThemeMode(
      isDarkMode ? ThemeMode.light : ThemeMode.dark,
    );
  }

  // --- Brightness / Volume ---

  void setBrightness(double value) {
    QuickSettingsService.setBrightness(value);
  }

  void setVolume(double value) {
    QuickSettingsService.setVolume(value);
  }

  void onVolumeChangeEnd(double _) {
    QuickSettingsService.playVolumeChangeSound();
  }

  // --- WiFi ---

  Future<void> scanWifi() async {
    _isScanning = true;
    _currentMenu = QuickSettingsMenu.wifi;
    notifyListeners();

    final networks = await QuickSettingsService.scanWifi();
    _wifiNetworks = networks;
    _isScanning = false;
    notifyListeners();
  }

  void connectWifi(String ssid, [String? password]) {
    QuickSettingsService.connectWifi(ssid, password);
    _currentMenu = QuickSettingsMenu.main;
    notifyListeners();
  }

  // --- Bluetooth ---

  Future<void> scanBluetooth() async {
    _isScanning = true;
    _currentMenu = QuickSettingsMenu.bluetooth;
    notifyListeners();

    final devices = await QuickSettingsService.scanBluetooth();
    _btDevices = devices;
    _isScanning = false;
    notifyListeners();
  }

  void connectBluetooth(String address) {
    QuickSettingsService.connectBluetooth(address);
    _currentMenu = QuickSettingsMenu.main;
    notifyListeners();
  }

  // --- Screenshot / Recording ---

  Future<void> takeScreenshot(bool cropped) async {
    onClose();
    await Future.delayed(const Duration(milliseconds: 200));
    await QuickSettingsService.takeScreenshot(cropped);
  }

  Future<void> toggleRecording() async {
    if (isRecording) {
      await QuickSettingsService.stopRecording();
      SystemState.isRecording.value = false;
    } else {
      onClose();
      await Future.delayed(const Duration(milliseconds: 200));
      QuickSettingsService.startRecording();
      SystemState.isRecording.value = true;
    }
    notifyListeners();
  }

  // --- Audio ---

  Future<void> loadAudioDevices() async {
    _isScanning = true;
    notifyListeners();

    final list = await QuickSettingsService.loadAudioDevices();
    _sinks = list.sinks;
    _sources = list.sources;
    _defaultSink = list.defaultSink;
    _defaultSource = list.defaultSource;
    _isScanning = false;
    notifyListeners();
  }

  void setDefaultSink(String name) {
    QuickSettingsService.setDefaultSink(name);
    _defaultSink = name;
    notifyListeners();
  }

  void setDefaultSource(String name) {
    QuickSettingsService.setDefaultSource(name);
    _defaultSource = name;
    notifyListeners();
  }

  // --- Settings ---

  void openSettings() {
    QuickSettingsService.launchSettings();
    onClose();
  }

  void _checkRecording() async {
    final isRec = await QuickSettingsService.checkRecordingStatus();
    SystemState.isRecording.value = isRec;
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    SystemState.brightness.removeListener(_onSysChange);
    SystemState.bluetoothEnabled.removeListener(_onSysChange);
    SystemState.volume.removeListener(_onSysChange);
    SystemState.nightLight.removeListener(_onSysChange);
    SystemState.wifiSsid.removeListener(_onSysChange);
    SystemState.airplaneMode.removeListener(_onSysChange);
    SystemState.isRecording.removeListener(_onSysChange);
    SystemState.dockAutohide.removeListener(_onSysChange);
    FyrTheme.themeModeNotifier.removeListener(_onSysChange);
    super.dispose();
  }
}
