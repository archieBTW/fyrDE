import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:fyrtaskbar/fyr_theme.dart';
import 'package:fyrtaskbar/models/notification.dart';
import 'package:fyrtaskbar/notification_service.dart';
import 'package:fyrtaskbar/state/system_state.dart';
import 'package:intl/intl.dart';

class NotificationCard extends StatelessWidget {
  final FyrNotification notification;
  final bool isPopup;

  const NotificationCard({
    super.key,
    required this.notification,
    this.isPopup = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (notification.actions.contains('default')) {
          NotificationService.sendActionInvoked(notification.id, 'default');
          SystemState.dismissNotification(notification.id);
        }
      },
      child: Container(
        width: 320,
        decoration: BoxDecoration(
          color: FyrTheme.bgColor.withOpacity(0.9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: FyrTheme.cardColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildIcon(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              notification.appName.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: FyrTheme.accentColor,
                                letterSpacing: 1.2,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            DateFormat('HH:mm').format(notification.timestamp),
                            style: TextStyle(
                              fontSize: 10,
                              color: FyrTheme.textColorMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notification.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: FyrTheme.textColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        notification.body,
                        style: TextStyle(
                          fontSize: 13,
                          color: FyrTheme.textColor.withOpacity(0.8),
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (notification.actions.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: notification.actions
                                .asMap()
                                .entries
                                .where(
                                  (entry) =>
                                      entry.key % 2 == 0 &&
                                      entry.value != 'default',
                                )
                                .map((entry) {
                                  final key = entry.value;
                                  final label =
                                      notification.actions[entry.key + 1];
                                  return TextButton(
                                    onPressed: () {
                                      NotificationService.sendActionInvoked(
                                        notification.id,
                                        key,
                                      );
                                      SystemState.dismissNotification(
                                        notification.id,
                                      );
                                    },
                                    style: TextButton.styleFrom(
                                      backgroundColor: FyrTheme.accentColor
                                          .withOpacity(0.1),
                                      foregroundColor: FyrTheme.accentColor,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                    child: Text(
                                      label,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  );
                                })
                                .toList(),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    Icons.close,
                    size: 16,
                    color: FyrTheme.textColorMuted,
                  ),
                  onPressed: () {
                    if (isPopup) {
                      SystemState.dismissPopup(notification.id);
                    } else {
                      SystemState.dismissNotification(notification.id);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    if (notification.icon == 'phone') {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: FyrTheme.accentColor.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.smartphone, color: FyrTheme.accentColor, size: 24),
      );
    }

    if (notification.icon.isEmpty) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: FyrTheme.accentColor.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.notifications, color: FyrTheme.accentColor, size: 24),
      );
    }

    if (notification.icon.startsWith('/')) {
      final file = File(notification.icon);
      if (file.existsSync()) {
        if (notification.icon.endsWith('.svg')) {
          return SvgPicture.file(file, width: 40, height: 40);
        } else {
          return Image.file(file, width: 40, height: 40, fit: BoxFit.contain);
        }
      }
    }

    // Try to find icon in theme if it's just a name
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: FyrTheme.accentColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.notifications, color: FyrTheme.accentColor, size: 24),
    );
  }
}
