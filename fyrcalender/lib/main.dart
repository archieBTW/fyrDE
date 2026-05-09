import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'fyr_theme.dart';
import 'calendar_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  FyrTheme.initialize();
  await CalendarService.initialize();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(650, 400),
    minimumSize: Size(600, 400),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const FyrCalendarApp());
}

class FyrCalendarApp extends StatelessWidget {
  const FyrCalendarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        FyrTheme.accentColorNotifier,
        FyrTheme.themeModeNotifier,
      ]),
      builder: (context, child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'FyrCalendar',
        themeMode: FyrTheme.themeMode,
        darkTheme: ThemeData.dark().copyWith(
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.transparent,
          colorScheme: ColorScheme.dark(
            primary: FyrTheme.accentColor,
            secondary: FyrTheme.accentColor,
            surface: FyrTheme.surfaceColor,
          ),
        ),
        theme: ThemeData.light().copyWith(
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.transparent,
          colorScheme: ColorScheme.light(
            primary: FyrTheme.accentColor,
            secondary: FyrTheme.accentColor,
            surface: FyrTheme.surfaceColor,
          ),
        ),
        home: const CalendarHomeScreen(),
      ),
    );
  }
}

class CalendarHomeScreen extends StatefulWidget {
  const CalendarHomeScreen({super.key});

  @override
  State<CalendarHomeScreen> createState() => _CalendarHomeScreenState();
}

class _CalendarHomeScreenState extends State<CalendarHomeScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  final DateTime _firstDay = DateTime.utc(2000, 1, 1);
  final DateTime _lastDay = DateTime.utc(2100, 12, 31);

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
  }

  List<CalendarEvent> _getEventsForDay(DateTime day) {
    return CalendarService.events.value.where((event) {
      return isSameDay(event.startTime, day);
    }).toList();
  }

  void _showAddEventDialog() {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    DateTime startTime = _selectedDay ?? DateTime.now();
    DateTime endTime = startTime.add(const Duration(hours: 1));

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: FyrTheme.surfaceColor,
          title: Text('New Event', style: TextStyle(color: FyrTheme.textColor)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                style: TextStyle(color: FyrTheme.textColor),
                decoration: InputDecoration(
                  labelText: 'Title',
                  labelStyle: TextStyle(color: FyrTheme.textColorMuted),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descController,
                style: TextStyle(color: FyrTheme.textColor),
                decoration: InputDecoration(
                  labelText: 'Description',
                  labelStyle: TextStyle(color: FyrTheme.textColorMuted),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                title: Text('Time', style: TextStyle(color: FyrTheme.textColorMuted)),
                subtitle: Text(
                  '${DateFormat('HH:mm').format(startTime)} - ${DateFormat('HH:mm').format(endTime)}',
                  style: TextStyle(color: FyrTheme.textColor),
                ),
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(startTime),
                  );
                  if (time != null) {
                    setDialogState(() {
                      startTime = DateTime(startTime.year, startTime.month, startTime.day, time.hour, time.minute);
                      endTime = startTime.add(const Duration(hours: 1));
                    });
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: FyrTheme.textColorMuted)),
            ),
            ElevatedButton(
              onPressed: () {
                if (titleController.text.isNotEmpty) {
                  CalendarService.addEvent(CalendarEvent(
                    id: const Uuid().v4(),
                    title: titleController.text,
                    description: descController.text,
                    startTime: startTime,
                    endTime: endTime,
                    source: 'local',
                  ));
                  Navigator.pop(context);
                  setState(() {});
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FyrTheme.surfaceColor,
        title: Text('Settings', style: TextStyle(color: FyrTheme.textColor)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: CalendarService.isGoogleSignedIn,
              builder: (context, isSignedIn, _) {
                return Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        Icons.cloud_outlined,
                        color: isSignedIn ? FyrTheme.accentColor : FyrTheme.textColorMuted,
                      ),
                      title: Text(
                        'Google Calendar',
                        style: TextStyle(color: FyrTheme.textColor),
                      ),
                      subtitle: Text(
                        isSignedIn ? 'Signed In' : 'Not Signed In',
                        style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12),
                      ),
                      trailing: Switch(
                        value: isSignedIn,
                        onChanged: (value) {
                          if (value) {
                            CalendarService.signInGoogle();
                          } else {
                            CalendarService.signOutGoogle();
                          }
                        },
                        activeColor: FyrTheme.accentColor,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: FyrTheme.textColorMuted)),
          ),
        ],
      ),
    );
  }

  void _showMonthYearPicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FyrTheme.surfaceColor,
        title: Text('Select Date', style: TextStyle(color: FyrTheme.textColor)),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                    IconButton(
                      icon: Icon(Icons.chevron_left, color: FyrTheme.textColor),
                      onPressed: () {
                        if (_focusedDay.year > _firstDay.year) {
                          setState(() {
                            _focusedDay = DateTime(_focusedDay.year - 1, _focusedDay.month);
                          });
                          Navigator.pop(context);
                          _showMonthYearPicker();
                        }
                      },
                    ),
                    Text(
                      _focusedDay.year.toString(),
                      style: TextStyle(color: FyrTheme.textColor, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: Icon(Icons.chevron_right, color: FyrTheme.textColor),
                      onPressed: () {
                        if (_focusedDay.year < _lastDay.year) {
                          setState(() {
                            _focusedDay = DateTime(_focusedDay.year + 1, _focusedDay.month);
                          });
                          Navigator.pop(context);
                          _showMonthYearPicker();
                        }
                      },
                    ),
                ],
              ),
              const Divider(),
              GridView.builder(
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 2,
                ),
                itemCount: 12,
                itemBuilder: (context, index) {
                  final month = index + 1;
                  final isSelected = _focusedDay.month == month;
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _focusedDay = DateTime(_focusedDay.year, month);
                      });
                      Navigator.pop(context);
                    },
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected ? FyrTheme.accentColor : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        DateFormat('MMM').format(DateTime(2024, month)),
                        style: TextStyle(
                          color: isSelected ? Colors.white : FyrTheme.textColor,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrafficLight(Color color, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black26, width: 0.5),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        color: FyrTheme.bgColor,
        child: Column(
          children: [
            DragToMoveArea(
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    _buildTrafficLight(Colors.redAccent, () => windowManager.close()),
                    const SizedBox(width: 8),
                    _buildTrafficLight(Colors.orangeAccent, () => windowManager.minimize()),
                    const SizedBox(width: 8),
                    _buildTrafficLight(Colors.greenAccent, () async {
                      if (await windowManager.isMaximized()) {
                        windowManager.unmaximize();
                      } else {
                        windowManager.maximize();
                      }
                    }),
                    const SizedBox(width: 20),
                    IconButton(
                      icon: Icon(Icons.chevron_left, color: FyrTheme.textColorMuted, size: 18),
                      onPressed: () {
                        final prevMonth = DateTime(_focusedDay.year, _focusedDay.month - 1);
                        if (prevMonth.isAfter(_firstDay) || isSameDay(prevMonth, _firstDay)) {
                          setState(() {
                            _focusedDay = prevMonth;
                          });
                        }
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: _showMonthYearPicker,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        DateFormat('MMMM yyyy').format(_focusedDay),
                        style: TextStyle(
                          color: FyrTheme.textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(Icons.chevron_right, color: FyrTheme.textColorMuted, size: 18),
                      onPressed: () {
                        final nextMonth = DateTime(_focusedDay.year, _focusedDay.month + 1);
                        if (nextMonth.isBefore(_lastDay) || isSameDay(nextMonth, _lastDay)) {
                          setState(() {
                            _focusedDay = nextMonth;
                          });
                        }
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.today, color: FyrTheme.textColorMuted, size: 18),
                      onPressed: () {
                        setState(() {
                          _focusedDay = DateTime.now();
                          _selectedDay = _focusedDay;
                        });
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Today',
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: Icon(Icons.add, color: FyrTheme.accentColor, size: 18),
                      onPressed: _showAddEventDialog,
                      tooltip: 'New Event',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: ValueListenableBuilder<List<CalendarEvent>>(
                      valueListenable: CalendarService.events,
                      builder: (context, events, _) {
                        return TableCalendar(
                          firstDay: _firstDay,
                          lastDay: _lastDay,
                          focusedDay: _focusedDay,
                          calendarFormat: _calendarFormat,
                          rowHeight: 54,
                          daysOfWeekHeight: 28,
                          sixWeekMonthsEnforced: true,
                          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                          onDaySelected: (selectedDay, focusedDay) {
                            setState(() {
                              _selectedDay = selectedDay;
                              _focusedDay = focusedDay;
                            });
                          },
                          onFormatChanged: (format) {
                            setState(() {
                              _calendarFormat = format;
                            });
                          },
                          onPageChanged: (focusedDay) {
                            _focusedDay = focusedDay;
                          },
                          eventLoader: _getEventsForDay,
                          calendarStyle: CalendarStyle(
                            defaultTextStyle: TextStyle(color: FyrTheme.textColor),
                            weekendTextStyle: TextStyle(color: FyrTheme.textColorMuted),
                            selectedDecoration: BoxDecoration(
                              color: FyrTheme.accentColor,
                              shape: BoxShape.circle,
                            ),
                            todayDecoration: BoxDecoration(
                              color: FyrTheme.accentColor.withOpacity(0.3),
                              shape: BoxShape.circle,
                            ),
                            markerDecoration: BoxDecoration(
                              color: FyrTheme.accentColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          headerVisible: false,
                        );
                      },
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(left: BorderSide(color: FyrTheme.dividerColor)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(
                              _selectedDay == null ? 'Select' : DateFormat('E, MMM d').format(_selectedDay!),
                              style: TextStyle(
                                color: FyrTheme.textColor,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Expanded(
                            child: ValueListenableBuilder<List<CalendarEvent>>(
                              valueListenable: CalendarService.events,
                              builder: (context, events, _) {
                                final dayEvents = _getEventsForDay(_selectedDay ?? DateTime.now());
                                if (dayEvents.isEmpty) {
                                  return Center(
                                    child: Text(
                                      'No events',
                                      style: TextStyle(color: FyrTheme.textColorMuted),
                                    ),
                                  );
                                }
                                return ListView.builder(
                                  itemCount: dayEvents.length,
                                  itemBuilder: (context, index) {
                                    final event = dayEvents[index];
                                    return ListTile(
                                      title: Text(
                                        event.title,
                                        style: TextStyle(color: FyrTheme.textColor),
                                      ),
                                      subtitle: Text(
                                        '${DateFormat('HH:mm').format(event.startTime)} - ${DateFormat('HH:mm').format(event.endTime)}',
                                        style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12),
                                      ),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 20),
                                        onPressed: () => CalendarService.deleteEvent(event.id),
                                        color: Colors.redAccent.withOpacity(0.7),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem(String label, IconData icon, bool active, {VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: active ? FyrTheme.accentColor : FyrTheme.textColorMuted, size: 16),
      title: Text(
        label,
        style: TextStyle(
          color: active ? FyrTheme.textColor : FyrTheme.textColorMuted,
          fontSize: 12,
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      onTap: onTap,
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
