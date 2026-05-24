import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fyrtaskbar/fyr_theme.dart';
import 'package:fyrtaskbar/models/notification.dart';
import 'package:fyrtaskbar/state/system_state.dart';
import 'package:intl/intl.dart';

class ClockWidget extends StatefulWidget {
  const ClockWidget({super.key});

  @override
  State<ClockWidget> createState() => _ClockWidgetState();
}

class _ClockWidgetState extends State<ClockWidget> {
  late Timer _timer;
  String _timeString = "";

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (Timer t) => _updateTime(),
    );
  }

  void _updateTime() {
    final String formattedDateTime = DateFormat(
      'EEE, MMM d  •  h:mm a',
    ).format(DateTime.now());
    if (mounted) {
      setState(() {
        _timeString = formattedDateTime;
      });
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ValueListenableBuilder<double?>(
          valueListenable: SystemState.weatherTemp,
          builder: (context, temp, _) {
            if (temp == null) return const SizedBox();
            return Row(
              children: [
                ValueListenableBuilder<IconData>(
                  valueListenable: SystemState.weatherIcon,
                  builder: (context, icon, _) {
                    return Icon(icon, color: FyrTheme.textColor, size: 14);
                  },
                ),
                SizedBox(width: 4),
                Text(
                  '${temp.round()}°F',
                  style: TextStyle(
                    color: FyrTheme.textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: 12),
              ],
            );
          },
        ),
        Text(
          _timeString,
          style: TextStyle(
            color: FyrTheme.textColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        ValueListenableBuilder<List<FyrNotification>>(
          valueListenable: SystemState.notifications,
          builder: (context, notifications, _) {
            if (notifications.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Icon(
                Icons.notifications_active,
                color: FyrTheme.accentColor,
                size: 14,
              ),
            );
          },
        ),
      ],
    );
  }
}
