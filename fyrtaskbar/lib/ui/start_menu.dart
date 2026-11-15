import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:fyrtaskbar/fyr_theme.dart';
import 'package:fyrtaskbar/models/app_entry.dart';
import 'package:fyrtaskbar/services/app_service.dart';
import 'package:fyrtaskbar/ui/power_button.dart';

class StartMenuPopup extends StatefulWidget {
  final VoidCallback onClose;
  const StartMenuPopup({super.key, required this.onClose});

  @override
  State<StartMenuPopup> createState() => _StartMenuPopupState();
}

class _StartMenuPopupState extends State<StartMenuPopup>
    with SingleTickerProviderStateMixin {
  List<DesktopApp> _apps = AppService.cachedApps ?? [];
  late List<DesktopApp> _filteredApps;
  final TextEditingController _searchController = TextEditingController();
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
        Tween<Offset>(begin: const Offset(-1.0, 0.0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutQuart,
          ),
        );
    _animationController.forward();

    _filteredApps = _apps;
    if (_apps.isEmpty) {
      _loadApps();
    }
    _searchController.addListener(_filterApps);
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadApps() async {
    AppService.cachedApps = null;
    final apps = await AppService.getInstalledApps();
    if (mounted) {
      setState(() {
        _apps = apps;
        _filteredApps = apps;
      });
    }
  }

  void _filterApps() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredApps = _apps;
      } else {
        _filteredApps = _apps.where((app) {
          final name = app.name.toLowerCase();
          final exec = app.exec.toLowerCase();
          final path = app.path.toLowerCase();
          return name.contains(query) || exec.contains(query) || path.contains(query);
        }).toList()..sort((a, b) {
          final aName = a.name.toLowerCase();
          final bName = b.name.toLowerCase();
          bool aStarts = aName.startsWith(query);
          bool bStarts = bName.startsWith(query);
          if (aStarts && !bStarts) return -1;
          if (!aStarts && bStarts) return 1;
          return aName.compareTo(bName);
        });
      }
    });
  }

  void _launchApp(String exec) {
    widget.onClose();
    try {
      Process.start(
        'sh',
        ['-c', exec],
        mode: ProcessStartMode.detached,
      );
    } catch (e) {
      print('Failed to launch: \$e');
    }
  }

  void _runCommand(String command, List<String> args) {
    widget.onClose();
    Process.start(command, args, mode: ProcessStartMode.detached);
  }

  Future<void> _confirmPowerAction({
    required String title,
    required String message,
    required String confirmLabel,
    required IconData icon,
    required String command,
    required List<String> args,
    bool isDanger = false,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: FyrTheme.panelBgColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: FyrTheme.cardColor),
        ),
        title: Row(
          children: [
            Icon(
              icon,
              color: isDanger ? Colors.redAccent : FyrTheme.accentColor,
              size: 24,
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                color: FyrTheme.textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(
            color: FyrTheme.textColor.withOpacity(0.85),
            fontSize: 15,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: FyrTheme.textColor.withOpacity(0.7)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDanger
                  ? Colors.redAccent
                  : FyrTheme.accentColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _runCommand(command, args);
    }
  }

  void _pinApp(DesktopApp app) async {
    final dir = Directory('${Platform.environment['HOME']}/.config/fyrdock');
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}/pinned_apps.json');
    List<dynamic> pinned = [];
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        pinned = jsonDecode(content);
      } catch (_) {}
    }
    if (!pinned.any((p) => p['exec'] == app.exec)) {
      pinned.add({'name': app.name, 'exec': app.exec, 'icon': app.icon});
      await file.writeAsString(jsonEncode(pinned));
      if (mounted) {}
    } else {
      pinned.removeWhere((p) => p['exec'] == app.exec);
      await file.writeAsString(jsonEncode(pinned));
      if (mounted) {}
    }
  }

  void _renameApp(DesktopApp app) async {
    final TextEditingController _nameController = TextEditingController(
      text: app.name,
    );
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FyrTheme.panelBgColor,
        title: Text('Rename App', style: TextStyle(color: FyrTheme.textColor)),
        content: TextField(
          controller: _nameController,
          style: TextStyle(color: FyrTheme.textColor),
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'New Name',
            hintStyle: TextStyle(color: FyrTheme.textColor.withOpacity(0.4)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _nameController.text),
            child: Text(
              'Rename',
              style: TextStyle(color: FyrTheme.accentColor),
            ),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != app.name) {
      bool needsSudo = app.path.startsWith('/usr/share/applications');
      if (needsSudo) {
        // For system files, we still use sed but with better escaping
        final escapedName = newName.replaceAll("'", "'\\''");
        String script =
            "sed -i \"s/^Name=.*/Name=$escapedName/\" \"${app.path}\"";
        _runWithAuth(script);
      } else {
        try {
          final file = File(app.path);
          final lines = await file.readAsLines();
          final newLines = lines.map((line) {
            if (line.startsWith('Name=')) {
              return 'Name=$newName';
            }
            return line;
          }).toList();
          await file.writeAsString(newLines.join('\n'));
          _loadApps();
        } catch (e) {
          debugPrint('Failed to rename local app: $e');
        }
      }
    }
  }

  void _removeApp(DesktopApp app) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FyrTheme.panelBgColor,
        title: Text('Remove App', style: TextStyle(color: FyrTheme.textColor)),
        content: Text(
          'Are you sure you want to remove ${app.name}?',
          style: TextStyle(color: FyrTheme.textColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Remove', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      bool needsSudo = app.path.startsWith('/usr/share/applications');
      if (needsSudo) {
        _runWithAuth("rm \"${app.path}\"");
      } else {
        await File(app.path).delete();
        _loadApps();
      }
    }
  }

  void _runWithAuth(String command) async {
    final TextEditingController _passController = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FyrTheme.panelBgColor,
        title: Text(
          'Authentication Required',
          style: TextStyle(color: FyrTheme.textColor),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter password to perform this action:',
              style: TextStyle(color: FyrTheme.textColor, fontSize: 14),
            ),
            SizedBox(height: 16),
            TextField(
              controller: _passController,
              obscureText: true,
              autofocus: true,
              style: TextStyle(color: FyrTheme.textColor),
              decoration: InputDecoration(
                hintText: 'Password',
                hintStyle: TextStyle(
                  color: FyrTheme.textColor.withOpacity(0.4),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _passController.text),
            child: Text(
              'Authorize',
              style: TextStyle(color: FyrTheme.accentColor),
            ),
          ),
        ],
      ),
    );

    if (password != null) {
      final res = await Process.run('sh', [
        '-c',
        'echo "$password" | sudo -S $command',
      ]);
      if (res.exitCode == 0) {
        _loadApps();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Action failed: check password'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        width: 400,
        decoration: BoxDecoration(
          color: FyrTheme.panelBgColor,
          border: Border(right: BorderSide(color: FyrTheme.cardColor)),
        ),
        child: Column(
          children: [
            SizedBox(height: 24),
            Expanded(
              child: _apps.isEmpty
                  ? Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      itemCount: _filteredApps.length,
                      itemBuilder: (context, index) {
                        final app = _filteredApps[index];
                        return GestureDetector(
                          onSecondaryTapDown: (details) {
                            showMenu(
                              context: context,
                              position: RelativeRect.fromLTRB(
                                details.globalPosition.dx,
                                details.globalPosition.dy,
                                details.globalPosition.dx,
                                details.globalPosition.dy,
                              ),
                              items: [
                                PopupMenuItem(
                                  value: 'pin',
                                  child: Text('Toggle Pin to Dock'),
                                  onTap: () => _pinApp(app),
                                ),
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text('Rename App'),
                                  onTap: () => _renameApp(app),
                                ),
                                PopupMenuItem(
                                  value: 'remove',
                                  child: Text(
                                    'Remove App',
                                    style: TextStyle(color: Colors.redAccent),
                                  ),
                                  onTap: () => _removeApp(app),
                                ),
                              ],
                            );
                          },
                          child: InkWell(
                            onTap: () => _launchApp(app.exec),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: FyrTheme.cardColor,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: app.icon.startsWith('/')
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            child:
                                                app.icon.toLowerCase().endsWith(
                                                  '.svg',
                                                )
                                                ? SvgPicture.file(
                                                    File(app.icon),
                                                    width: 24,
                                                    height: 24,
                                                    fit: BoxFit.contain,
                                                  )
                                                : Image.file(
                                                    File(app.icon),
                                                    width: 24,
                                                    height: 24,
                                                    errorBuilder:
                                                        (
                                                          context,
                                                          error,
                                                          stackTrace,
                                                        ) => Icon(
                                                          Icons.widgets,
                                                          color: FyrTheme
                                                              .textColor
                                                              .withOpacity(0.8),
                                                          size: 20,
                                                        ),
                                                  ),
                                          )
                                        : Icon(
                                            Icons.widgets,
                                            color: FyrTheme.textColor
                                                .withOpacity(0.8),
                                            size: 20,
                                          ),
                                  ),
                                  SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      app.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: FyrTheme.textColor.withOpacity(0.02),
                border: Border(top: BorderSide(color: FyrTheme.cardColor)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  PowerButton(
                    icon: Icons.lock_outline,
                    label: "Lock",
                    onTap: () => _runCommand('dbus-send', [
                      '--system',
                      '--type=method_call',
                      '--dest=org.freedesktop.DisplayManager',
                      '/org/freedesktop/DisplayManager/Seat0',
                      'org.freedesktop.DisplayManager.Seat.SwitchToGreeter',
                    ]),
                  ),
                  PowerButton(
                    icon: Icons.logout,
                    label: "Logout",
                    onTap: () => _confirmPowerAction(
                      title: 'Log Out',
                      message:
                          'Are you sure you want to log out of your current session?',
                      confirmLabel: 'Log Out',
                      icon: Icons.logout,
                      command: 'swaymsg',
                      args: ['exit'],
                    ),
                  ),
                  PowerButton(
                    icon: Icons.restart_alt,
                    label: "Restart",
                    onTap: () => _confirmPowerAction(
                      title: 'Restart Computer',
                      message:
                          'Are you sure you want to restart your computer? Any unsaved work will be lost.',
                      confirmLabel: 'Restart',
                      icon: Icons.restart_alt,
                      command: 'systemctl',
                      args: ['reboot'],
                    ),
                  ),
                  PowerButton(
                    icon: Icons.power_settings_new,
                    label: "Shutdown",
                    onTap: () => _confirmPowerAction(
                      title: 'Shut Down Computer',
                      message:
                          'Are you sure you want to shut down your computer? Any unsaved work will be lost.',
                      confirmLabel: 'Shut Down',
                      icon: Icons.power_settings_new,
                      command: 'systemctl',
                      args: ['poweroff'],
                      isDanger: true,
                    ),
                    isDanger: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
