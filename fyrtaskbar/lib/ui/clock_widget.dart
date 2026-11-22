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
        ValueListenableBuilder<bool>(
          valueListenable: SystemState.doNotDisturb,
          builder: (context, dnd, _) {
            return ValueListenableBuilder<List<FyrNotification>>(
              valueListenable: SystemState.notifications,
              builder: (context, notifications, _) {
                if (!dnd && notifications.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        dnd
                            ? Icons.notifications_off_outlined
                            : Icons.notifications_active,
                        color: dnd
                            ? FyrTheme.textColorMuted
                            : FyrTheme.accentColor,
                        size: 14,
                      ),
                      if (notifications.isNotEmpty) ...[
                        const SizedBox(width: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: dnd
                                ? FyrTheme.textColorMuted.withOpacity(0.22)
                                : FyrTheme.accentColor.withOpacity(0.22),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${notifications.length}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: dnd
                                  ? FyrTheme.textColorMuted
                                  : FyrTheme.accentColor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
