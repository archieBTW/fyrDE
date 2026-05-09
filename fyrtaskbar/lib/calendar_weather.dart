import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'fyr_theme.dart';
import 'main.dart';
import 'phone_service.dart';

class CalendarEvent {
  final String id;
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final String source;

  CalendarEvent({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.source,
  });

  factory CalendarEvent.fromJson(Map<String, dynamic> json) => CalendarEvent(
        id: json['id'],
        title: json['title'],
        startTime: DateTime.parse(json['startTime']),
        endTime: DateTime.parse(json['endTime']),
        source: json['source'] ?? 'local',
      );
}

class CalendarMenuPopup extends StatefulWidget {
  final VoidCallback onClose;
  const CalendarMenuPopup({super.key, required this.onClose});

  @override
  State<CalendarMenuPopup> createState() => _CalendarMenuPopupState();
}

class _CalendarMenuPopupState extends State<CalendarMenuPopup>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  DateTime _selectedDate = DateTime.now();
  final TextEditingController _locationController = TextEditingController();
  List<CalendarEvent> _events = [];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0.0, -1.0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutQuart,
          ),
        );
    _animationController.forward();
    
    _locationController.text = SystemState.weatherLocation.value;
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    try {
      final file = File('${Platform.environment['HOME']}/.config/fyr/calendar_events.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> data = jsonDecode(content);
        setState(() {
          _events = data.map((e) => CalendarEvent.fromJson(e)).toList();
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _animationController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _showLocationDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: FyrTheme.bgColor,
          title: Text('Set Location', style: TextStyle(color: FyrTheme.textColor)),
          content: TextField(
            controller: _locationController,
            style: TextStyle(color: FyrTheme.textColor),
            decoration: InputDecoration(
              hintText: 'City Name',
              hintStyle: TextStyle(color: FyrTheme.textColorMuted),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: FyrTheme.cardColor)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: FyrTheme.accentColor)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: FyrTheme.textColorMuted)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                SystemState.saveWeatherLocation(_locationController.text);
              },
              child: Text('Save', style: TextStyle(color: FyrTheme.accentColor)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        width: 380,
        constraints: const BoxConstraints(maxHeight: 800),
        decoration: BoxDecoration(
          color: FyrTheme.bgColor,
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          border: Border(
            left: BorderSide(color: FyrTheme.cardColor),
            right: BorderSide(color: FyrTheme.cardColor),
            bottom: BorderSide(color: FyrTheme.cardColor),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Calendar Section
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: ColorScheme.dark(
                    primary: FyrTheme.accentColor,
                    onPrimary: Colors.white,
                    surface: FyrTheme.bgColor,
                    onSurface: FyrTheme.textColor,
                  ),
                ),
                child: CalendarDatePicker(
                  initialDate: _selectedDate,
                  firstDate: DateTime.now().subtract(const Duration(days: 3650)),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                  onDateChanged: (date) {
                    setState(() {
                      _selectedDate = date;
                    });
                  },
                ),
              ),
            ),
            // Events Section
            if (_events.any((e) =>
                e.startTime.year == _selectedDate.year &&
                e.startTime.month == _selectedDate.month &&
                e.startTime.day == _selectedDate.day)) ...[
              Divider(height: 1, color: FyrTheme.cardColor),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EVENTS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: FyrTheme.textColorMuted,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._events
                        .where((e) =>
                            e.startTime.year == _selectedDate.year &&
                            e.startTime.month == _selectedDate.month &&
                            e.startTime.day == _selectedDate.day)
                        .map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  Container(
                                    width: 4,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color: FyrTheme.accentColor,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      e.title,
                                      style: TextStyle(
                                        color: FyrTheme.textColor,
                                        fontSize: 13,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    DateFormat('HH:mm').format(e.startTime),
                                    style: TextStyle(
                                      color: FyrTheme.textColorMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            )),
                  ],
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextButton(
                onPressed: () {
                  Process.run('fyrcalender', []);
                  widget.onClose();
                },
                child: Text('Open Calendar', style: TextStyle(color: FyrTheme.accentColor, fontSize: 12)),
              ),
            ),
            Divider(height: 1, color: FyrTheme.cardColor),
            // Weather Section
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ValueListenableBuilder<String>(
                valueListenable: SystemState.weatherLocation,
                builder: (context, location, _) {
                  return ValueListenableBuilder<double?>(
                    valueListenable: SystemState.weatherTemp,
                    builder: (context, temp, _) {
                      return ValueListenableBuilder<String?>(
                        valueListenable: SystemState.weatherDesc,
                        builder: (context, desc, _) {
                          return ValueListenableBuilder<IconData>(
                            valueListenable: SystemState.weatherIcon,
                            builder: (context, icon, _) {
                              return Row(
                                children: [
                                  Icon(
                                    icon,
                                    size: 48,
                                    color: FyrTheme.textColor.withOpacity(0.8),
                                  ),
                                  SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              location,
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: FyrTheme.textColor,
                                              ),
                                            ),
                                            SizedBox(width: 8),
                                            InkWell(
                                              onTap: _showLocationDialog,
                                              child: Icon(
                                                Icons.edit,
                                                size: 14,
                                                color: FyrTheme.textColorMuted,
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 4),
                                        if (temp != null)
                                          Text(
                                            '${temp}°F • ${desc ?? "Unknown"}',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: FyrTheme.textColor.withOpacity(0.8),
                                            ),
                                          )
                                        else
                                          Text(
                                            'Weather unavailable',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: FyrTheme.textColorMuted,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
            Divider(height: 1, color: FyrTheme.cardColor),
            // Phone Section
            ValueListenableBuilder<PhoneInfo?>(
              valueListenable: SystemState.primaryPhone,
              builder: (context, phone, _) {
                if (phone == null || !phone.isPaired) return const SizedBox.shrink();
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Icon(
                            phone.isConnected ? Icons.smartphone : Icons.phonelink_erase,
                            size: 24,
                            color: phone.isConnected ? FyrTheme.accentColor : FyrTheme.textColorMuted,
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  phone.name,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: FyrTheme.textColor,
                                  ),
                                ),
                                Text(
                                  phone.isConnected 
                                    ? 'Connected • ${phone.batteryLevel}% Battery'
                                    : 'Disconnected',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: FyrTheme.textColorMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (phone.isConnected)
                            IconButton(
                              onPressed: () => PhoneService.ring(phone.id),
                              icon: Icon(Icons.notifications_active_outlined, size: 20),
                              color: FyrTheme.accentColor,
                              tooltip: 'Find my phone',
                            ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: FyrTheme.cardColor),
                  ],
                );
              },
            ),
            ValueListenableBuilder<List<FyrNotification>>(
              valueListenable: SystemState.notifications,
              builder: (context, notifications, _) {
                if (notifications.isEmpty) return const SizedBox.shrink();
                return Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Divider(height: 1, color: FyrTheme.cardColor),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'NOTIFICATIONS',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: FyrTheme.textColorMuted,
                                letterSpacing: 1.2,
                              ),
                            ),
                            InkWell(
                              onTap: () => SystemState.clearAllNotifications(),
                              child: Text(
                                'Clear All',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: FyrTheme.accentColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: notifications.length,
                          itemBuilder: (context, index) {
                            final n = notifications[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: NotificationCard(notification: n),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
