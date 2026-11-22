import 'package:flutter/material.dart';
import 'package:fyrtaskbar/models/notification.dart';
import 'package:fyrtaskbar/state/system_state.dart';
import 'package:fyrtaskbar/ui/notification_card.dart';

class NotificationPopupOverlay extends StatelessWidget {
  const NotificationPopupOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 12,
      left: 0,
      right: 0,
      child: ValueListenableBuilder<List<FyrNotification>>(
        valueListenable: SystemState.activePopups,
        builder: (context, popups, _) {
          if (popups.isEmpty) return const SizedBox.shrink();
          return Align(
            alignment: Alignment.topCenter,
            child: GestureDetector(
              onTap: () {},
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: popups.take(3).map((n) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: NotificationCard(notification: n, isPopup: true),
                  );
                }).toList(),
              ),
            ),
          );
        },
      ),
    );
  }
}
