import 'package:flutter/material.dart';
import 'package:fyrtaskbar/models/notification.dart';
import 'package:fyrtaskbar/state/system_state.dart';
import 'package:fyrtaskbar/ui/notification_card.dart';

class NotificationPopupOverlay extends StatelessWidget {
  const NotificationPopupOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ScreenshotPreview?>(
      valueListenable: SystemState.activeScreenshotToast,
      builder: (context, screenshot, _) {
        return Positioned(
          top: screenshot != null ? 290 : 12,
          right: 20,
          child: ValueListenableBuilder<List<FyrNotification>>(
            valueListenable: SystemState.activePopups,
            builder: (context, popups, _) {
              if (popups.isEmpty) return const SizedBox.shrink();
              return GestureDetector(
                onTap: () {},
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: popups.take(3).map((n) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: NotificationCard(notification: n, isPopup: true),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
