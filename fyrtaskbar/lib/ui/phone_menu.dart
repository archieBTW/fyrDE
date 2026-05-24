import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fyrtaskbar/fyr_theme.dart';
import 'package:fyrtaskbar/phone_service.dart';
import 'package:fyrtaskbar/state/system_state.dart';

class PhoneMenuPopup extends StatefulWidget {
  final VoidCallback onClose;
  const PhoneMenuPopup({super.key, required this.onClose});

  @override
  State<PhoneMenuPopup> createState() => _PhoneMenuPopupState();
}

class _PhoneMenuPopupState extends State<PhoneMenuPopup>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

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
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        width: 300,
        decoration: BoxDecoration(
          color: FyrTheme.bgColor,
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(color: FyrTheme.cardColor),
        ),
        child: ValueListenableBuilder<PhoneInfo?>(
          valueListenable: SystemState.primaryPhone,
          builder: (context, phone, _) {
            if (phone == null) return const SizedBox.shrink();
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.smartphone,
                        color: FyrTheme.accentColor,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              phone.name,
                              style: TextStyle(
                                color: FyrTheme.textColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              phone.isConnected
                                  ? "Connected • ${phone.batteryLevel}%"
                                  : "Disconnected",
                              style: TextStyle(
                                color: FyrTheme.textColorMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings, size: 20),
                        onPressed: () {
                          widget.onClose();
                          Process.run('fyrphone', []);
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                _buildMenuItem(
                  icon: Icons.notifications,
                  label: "Ping Phone",
                  onTap: () => PhoneService.ping(phone.id),
                ),
                _buildMenuItem(
                  icon: Icons.folder_open,
                  label: "Browse Files",
                  onTap: () => PhoneService.mountSftp(phone.id),
                ),
                _buildMenuItem(
                  icon: Icons.content_paste,
                  label: "Sync Clipboard",
                  onTap: () async {
                    final res = await Process.run('xclip', [
                      '-o',
                      '-selection',
                      'clipboard',
                    ]);
                    if (res.exitCode == 0) {
                      PhoneService.shareText(phone.id, res.stdout.toString());
                    }
                  },
                ),
                const SizedBox(height: 8),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        onTap();
        widget.onClose();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: FyrTheme.textColor.withOpacity(0.7), size: 20),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(color: FyrTheme.textColor, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
