import 'package:flutter/material.dart';
import 'package:fyrtaskbar/models/notification.dart';
import 'package:fyrtaskbar/state/system_state.dart';
import 'package:fyrtaskbar/ui/notification_card.dart';

class NotificationPopupOverlay extends StatelessWidget {
  const NotificationPopupOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 66,
      right: 20,
      child: ValueListenableBuilder<List<FyrNotification>>(
        valueListenable: SystemState.activePopups,
        builder: (context, popups, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: popups.take(3).map((n) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: NotificationCard(notification: n, isPopup: true),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
