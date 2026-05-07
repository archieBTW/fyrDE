import 'dart:io';
import 'package:flutter/material.dart';
import 'main.dart';
import 'fyr_theme.dart';

class WorkspaceSwitcher extends StatefulWidget {
  const WorkspaceSwitcher({super.key});

  @override
  State<WorkspaceSwitcher> createState() => _WorkspaceSwitcherState();
}

class _WorkspaceSwitcherState extends State<WorkspaceSwitcher> {
  int _maxWorkspace = 3;

  void _switchWorkspace(String name) {
    Process.start('swaymsg', ['workspace', name], mode: ProcessStartMode.detached);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: SystemState.workspaces,
      builder: (context, workspaces, _) {
        List<Map<String, dynamic>> allWorkspaces = [];

        for (var w in workspaces) {
          if (w['num'] is int && w['num'] > _maxWorkspace) {
            _maxWorkspace = w['num'];
          }
        }

        for (int i = 1; i <= _maxWorkspace; i++) {
          final ws = workspaces.cast<Map<String, dynamic>?>().firstWhere(
            (w) => w != null && w['num'] == i,
            orElse: () => null,
          );

          if (ws != null) {
            allWorkspaces.add(ws);
          } else {
            allWorkspaces.add({
              'num': i,
              'name': i.toString(),
              'focused': false,
              'visible': false,
              'empty': true,
            });
          }
        }

        for (var w in workspaces) {
          if (w['num'] is int && w['num'] < 1) {
            allWorkspaces.add(w);
          }
        }

        allWorkspaces.sort((a, b) => (a['num'] as int).compareTo(b['num'] as int));

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...allWorkspaces.map((ws) {
              final bool isFocused = ws['focused'] == true;
              final bool isEmpty = ws['empty'] == true;
              final String name = ws['name'].toString();

              return GestureDetector(
                onTap: () => _switchWorkspace(name),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    width: isFocused ? 28 : 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: isFocused
                          ? FyrTheme.textColor
                          : FyrTheme.textColor.withOpacity(isEmpty ? 0.2 : 0.6),
                      borderRadius: BorderRadius.circular(5),
                      boxShadow: isFocused ? [
                        BoxShadow(
                          color: FyrTheme.textColor.withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      ] : null,
                    ),
                  ),
                ),
              );
            }),
            GestureDetector(
              onTap: () => _switchWorkspace((_maxWorkspace + 1).toString()),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: FyrTheme.textColor.withOpacity(0.5),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.add,
                      size: 10,
                      color: FyrTheme.textColor.withOpacity(0.5),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
