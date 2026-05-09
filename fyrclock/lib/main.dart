import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fyr_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  FyrTheme.initialize();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(400, 350),
    minimumSize: Size(300, 350),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const FyrClockApp());
}

class FyrClockApp extends StatelessWidget {
  const FyrClockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        FyrTheme.accentColorNotifier,
        FyrTheme.themeModeNotifier,
      ]),
      builder: (context, child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Clock',
        themeMode: FyrTheme.themeMode,
        darkTheme: ThemeData.dark().copyWith(
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.black,
          colorScheme: ColorScheme.dark(
            primary: FyrTheme.accentColor,
            secondary: FyrTheme.accentColor,
            surface: Colors.black,
          ),
        ),
        theme: ThemeData.light().copyWith(
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.white,
          colorScheme: ColorScheme.light(
            primary: FyrTheme.accentColor,
            secondary: FyrTheme.accentColor,
            surface: Colors.white,
          ),
        ),
        home: const ClockHomeScreen(),
      ),
    );
  }
}

class ClockHomeScreen extends StatefulWidget {
  const ClockHomeScreen({super.key});

  @override
  State<ClockHomeScreen> createState() => _ClockHomeScreenState();
}

class _ClockHomeScreenState extends State<ClockHomeScreen> {
  int _selectedIndex = 0;
  final AudioPlayer _audioPlayer = AudioPlayer();

  // World Clocks
  List<WorldClockModel> _worldClocks = [];

  // Alarms
  List<AlarmModel> _alarms = [];
  Timer? _alarmTimer;

  // Stopwatch
  Stopwatch _stopwatch = Stopwatch();
  Timer? _stopwatchTimer;
  List<String> _laps = [];

  // Timer
  Duration _timerDuration = Duration.zero;
  Timer? _countDownTimer;
  bool _isTimerRunning = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _startAlarmCheck();
  }

  void _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    final alarmsJson = prefs.getStringList('alarms') ?? [];
    final clocksJson = prefs.getStringList('world_clocks') ?? [];

    setState(() {
      _alarms = alarmsJson.map((a) => AlarmModel.fromJson(a)).toList();
      _worldClocks =
          clocksJson.map((c) => WorldClockModel.fromJson(c)).toList();

      if (_worldClocks.isEmpty) {
        _worldClocks.add(WorldClockModel(
            id: 'local', name: 'Local Time', offsetHours: 0, isLocal: true));
      }
    });
  }

  void _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'alarms', _alarms.map((a) => a.toJson()).toList());
    await prefs.setStringList(
        'world_clocks', _worldClocks.map((c) => c.toJson()).toList());
  }

  void _startAlarmCheck() {
    _alarmTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      for (var alarm in _alarms) {
        if (alarm.isEnabled &&
            alarm.time.hour == now.hour &&
            alarm.time.minute == now.minute &&
            now.second == 0) {
          _ringAlarm(alarm);
        }
      }
    });
  }

  void _ringAlarm(AlarmModel alarm) {
    _audioPlayer.play(AssetSource('sounds/alarm.wav'));
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor:
            FyrTheme.themeMode == ThemeMode.dark ? Colors.black : Colors.white,
        title: Text('Alarm', style: TextStyle(color: FyrTheme.textColor)),
        content: Text('It\'s ${DateFormat('HH:mm').format(alarm.time)}!',
            style: TextStyle(color: FyrTheme.textColor)),
        actions: [
          TextButton(
            onPressed: () {
              _audioPlayer.stop();
              Navigator.pop(context);
            },
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _alarmTimer?.cancel();
    _stopwatchTimer?.cancel();
    _countDownTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Widget _buildTrafficLight(Color color, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = FyrTheme.themeMode == ThemeMode.dark;
    final bgColor = isDark ? Colors.black : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      body: Column(
        children: [
          // Top Bar & Navigation
          Container(
            padding: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: bgColor,
              border: Border(
                  bottom: BorderSide(color: FyrTheme.dividerColor, width: 0.5)),
            ),
            child: Column(
              children: [
                DragToMoveArea(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Row(
                      children: [
                        _buildTrafficLight(
                            Colors.redAccent, () => windowManager.close()),
                        const SizedBox(width: 8),
                        _buildTrafficLight(Colors.orangeAccent,
                            () => windowManager.minimize()),
                        const SizedBox(width: 8),
                        _buildTrafficLight(Colors.greenAccent, () async {
                          if (await windowManager.isMaximized()) {
                            windowManager.unmaximize();
                          } else {
                            windowManager.maximize();
                          }
                        }),
                        const Spacer(),
                        Text(
                          [
                            'World Clock',
                            'Alarm',
                            'Stopwatch',
                            'Timer'
                          ][_selectedIndex],
                          style: TextStyle(
                              color: FyrTheme.textColorMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        const SizedBox(width: 60), // Balance
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildNavItem(0, Icons.public),
                      _buildNavItem(1, Icons.alarm),
                      _buildNavItem(2, Icons.timer_outlined),
                      _buildNavItem(3, Icons.hourglass_bottom),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Main Content
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                _buildWorldClock(),
                _buildAlarms(),
                _buildStopwatch(),
                _buildTimer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon) {
    final isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        color: Colors.transparent,
        child: Icon(
          icon,
          size: 20,
          color: isSelected
              ? FyrTheme.accentColor
              : FyrTheme.textColorMuted.withOpacity(0.4),
        ),
      ),
    );
  }

  // --- World Clock ---
  Widget _buildWorldClock() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: _addWorldClock,
        mini: true,
        backgroundColor: FyrTheme.accentColor,
        child: const Icon(Icons.add, color: Colors.white, size: 18),
      ),
      body: StreamBuilder(
        stream: Stream.periodic(const Duration(seconds: 1)),
        builder: (context, snapshot) {
          final now = DateTime.now();
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _worldClocks.length,
            itemBuilder: (context, index) {
              final clock = _worldClocks[index];
              final time = clock.isLocal
                  ? now
                  : now.toUtc().add(Duration(hours: clock.offsetHours));

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  border: Border(
                      bottom:
                          BorderSide(color: FyrTheme.dividerColor, width: 0.5)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(clock.name,
                            style: TextStyle(
                                color: FyrTheme.textColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w500)),
                        Text(
                          clock.isLocal
                              ? 'Current Location'
                              : 'UTC ${clock.offsetHours >= 0 ? '+' : ''}${clock.offsetHours}',
                          style: TextStyle(
                              color: FyrTheme.textColorMuted, fontSize: 11),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          DateFormat('HH:mm:ss').format(time),
                          style: TextStyle(
                              color: FyrTheme.accentColor,
                              fontSize: 24,
                              fontWeight: FontWeight.w200,
                              fontFamily: 'monospace'),
                        ),
                        if (!clock.isLocal) ...[
                          const SizedBox(width: 12),
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () {
                              setState(() => _worldClocks.removeAt(index));
                              _saveData();
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            color: FyrTheme.textColorMuted,
                          ),
                        ]
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _addWorldClock() {
    String name = '';
    int offset = 0;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor:
            FyrTheme.themeMode == ThemeMode.dark ? Colors.black : Colors.white,
        title: Text('Add World Clock',
            style: TextStyle(color: FyrTheme.textColor)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: InputDecoration(
                  hintText: 'City Name',
                  hintStyle: TextStyle(color: FyrTheme.textColorMuted)),
              style: TextStyle(color: FyrTheme.textColor),
              onChanged: (v) => name = v,
            ),
            TextField(
              decoration: InputDecoration(
                  hintText: 'UTC Offset (e.g. -5, 2)',
                  hintStyle: TextStyle(color: FyrTheme.textColorMuted)),
              style: TextStyle(color: FyrTheme.textColor),
              keyboardType: TextInputType.number,
              onChanged: (v) => offset = int.tryParse(v) ?? 0,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (name.isNotEmpty) {
                setState(() => _worldClocks.add(WorldClockModel(
                      id: const Uuid().v4(),
                      name: name,
                      offsetHours: offset,
                    )));
                _saveData();
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  // --- Alarms ---
  Widget _buildAlarms() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: _addAlarm,
        mini: true,
        backgroundColor: FyrTheme.accentColor,
        child: const Icon(Icons.add, color: Colors.white, size: 18),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _alarms.length,
        itemBuilder: (context, index) {
          final alarm = _alarms[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.transparent,
              border: Border(
                  bottom: BorderSide(color: FyrTheme.dividerColor, width: 0.5)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              title: Text(
                DateFormat('HH:mm').format(alarm.time),
                style: TextStyle(
                    color: FyrTheme.textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w600),
              ),
              subtitle: Text(alarm.label,
                  style:
                      TextStyle(color: FyrTheme.textColorMuted, fontSize: 11)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: alarm.isEnabled,
                    onChanged: (val) {
                      setState(() => alarm.isEnabled = val);
                      _saveData();
                    },
                    activeColor: FyrTheme.accentColor,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () {
                      setState(() => _alarms.removeAt(index));
                      _saveData();
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _addAlarm() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time != null) {
      final now = DateTime.now();
      final alarmTime =
          DateTime(now.year, now.month, now.day, time.hour, time.minute);
      setState(() {
        _alarms.add(AlarmModel(
          id: const Uuid().v4(),
          time: alarmTime,
          isEnabled: true,
          label: 'Alarm',
        ));
      });
      _saveData();
    }
  }

  // --- Stopwatch ---
  Widget _buildStopwatch() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 20),
        Text(
          _formatDuration(_stopwatch.elapsed),
          style: TextStyle(
            color: FyrTheme.textColor,
            fontSize: 48,
            fontWeight: FontWeight.w100,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 30),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildCircularButton(
              _stopwatch.isRunning ? Icons.pause : Icons.play_arrow,
              () {
                setState(() {
                  if (_stopwatch.isRunning) {
                    _stopwatch.stop();
                    _stopwatchTimer?.cancel();
                  } else {
                    _stopwatch.start();
                    _stopwatchTimer = Timer.periodic(
                        const Duration(milliseconds: 30), (timer) {
                      setState(() {});
                    });
                  }
                });
              },
            ),
            const SizedBox(width: 16),
            _buildCircularButton(Icons.flag_outlined, () {
              if (_stopwatch.isRunning) {
                setState(() {
                  _laps.insert(0, _formatDuration(_stopwatch.elapsed));
                });
              }
            }),
            const SizedBox(width: 16),
            _buildCircularButton(Icons.refresh, () {
              setState(() {
                _stopwatch.reset();
                _stopwatch.stop();
                _stopwatchTimer?.cancel();
                _laps.clear();
              });
            }),
          ],
        ),
        const SizedBox(height: 24),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            itemCount: _laps.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Lap ${_laps.length - index}',
                        style: TextStyle(
                            color: FyrTheme.textColorMuted, fontSize: 12)),
                    Text(_laps[index],
                        style: TextStyle(
                            color: FyrTheme.textColor,
                            fontFamily: 'monospace',
                            fontSize: 13)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCircularButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: FyrTheme.accentColor.withOpacity(0.3)),
        ),
        child: Icon(icon, color: FyrTheme.accentColor, size: 20),
      ),
    );
  }

  // --- Timer ---
  Widget _buildTimer() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!_isTimerRunning)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildTimePickerUnit(
                  'H',
                  (v) => _timerDuration = Duration(
                      hours: v,
                      minutes: _timerDuration.inMinutes % 60,
                      seconds: _timerDuration.inSeconds % 60)),
              _buildTimePickerUnit(
                  'M',
                  (v) => _timerDuration = Duration(
                      hours: _timerDuration.inHours,
                      minutes: v,
                      seconds: _timerDuration.inSeconds % 60)),
              _buildTimePickerUnit(
                  'S',
                  (v) => _timerDuration = Duration(
                      hours: _timerDuration.inHours,
                      minutes: _timerDuration.inMinutes % 60,
                      seconds: v)),
            ],
          )
        else
          Text(
            _formatDuration(_timerDuration),
            style: TextStyle(
                color: FyrTheme.textColor,
                fontSize: 48,
                fontWeight: FontWeight.w100,
                fontFamily: 'monospace'),
          ),
        const SizedBox(height: 40),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildCircularButton(
              _isTimerRunning ? Icons.pause : Icons.play_arrow,
              () {
                if (_timerDuration == Duration.zero) return;
                setState(() {
                  _isTimerRunning = !_isTimerRunning;
                  if (_isTimerRunning) {
                    _countDownTimer =
                        Timer.periodic(const Duration(seconds: 1), (timer) {
                      setState(() {
                        if (_timerDuration.inSeconds > 0) {
                          _timerDuration -= const Duration(seconds: 1);
                        } else {
                          _isTimerRunning = false;
                          _countDownTimer?.cancel();
                          _audioPlayer.play(AssetSource('sounds/alarm.wav'));
                        }
                      });
                    });
                  } else {
                    _countDownTimer?.cancel();
                  }
                });
              },
            ),
            const SizedBox(width: 16),
            _buildCircularButton(Icons.refresh, () {
              setState(() {
                _isTimerRunning = false;
                _countDownTimer?.cancel();
                _timerDuration = Duration.zero;
              });
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildTimePickerUnit(String label, Function(int) onChanged) {
    return Column(
      children: [
        SizedBox(
          width: 50,
          child: TextField(
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            style: TextStyle(color: FyrTheme.textColor, fontSize: 20),
            decoration: InputDecoration(
              counterText: '',
              enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: FyrTheme.dividerColor)),
            ),
            onChanged: (v) => onChanged(int.tryParse(v) ?? 0),
            maxLength: 2,
          ),
        ),
        Text(label,
            style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 10)),
      ],
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(d.inHours);
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }
}

class AlarmModel {
  final String id;
  final DateTime time;
  bool isEnabled;
  final String label;

  AlarmModel(
      {required this.id,
      required this.time,
      required this.isEnabled,
      required this.label});

  Map<String, dynamic> toMap() => {
        'id': id,
        'time': time.toIso8601String(),
        'isEnabled': isEnabled,
        'label': label,
      };

  String toJson() => jsonEncode(toMap());

  factory AlarmModel.fromJson(String source) {
    final map = jsonDecode(source);
    return AlarmModel(
      id: map['id'],
      time: DateTime.parse(map['time']),
      isEnabled: map['isEnabled'],
      label: map['label'],
    );
  }
}

class WorldClockModel {
  final String id;
  final String name;
  final int offsetHours;
  final bool isLocal;

  WorldClockModel(
      {required this.id,
      required this.name,
      required this.offsetHours,
      this.isLocal = false});

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'offsetHours': offsetHours,
        'isLocal': isLocal,
      };

  String toJson() => jsonEncode(toMap());

  factory WorldClockModel.fromJson(String source) {
    final map = jsonDecode(source);
    return WorldClockModel(
      id: map['id'],
      name: map['name'],
      offsetHours: map['offsetHours'],
      isLocal: map['isLocal'] ?? false,
    );
  }
}
