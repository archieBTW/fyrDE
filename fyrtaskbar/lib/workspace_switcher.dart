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
  void _switchWorkspace(String name) {
    Process.start('swaymsg', ['workspace', name]);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: SystemState.workspaces,
      builder: (context, workspaces, _) {
        List<Map<String, dynamic>> allWorkspaces = [];
        int maxWorkspace = 3;

        for (var w in workspaces) {
          if (w['num'] is int && w['num'] > maxWorkspace) {
            maxWorkspace = w['num'];
          }
        }

        for (int i = 1; i <= maxWorkspace; i++) {
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
          children: allWorkspaces.map((ws) {
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
                        ? Colors.white
                        : Colors.white.withOpacity(isEmpty ? 0.25 : 0.7),
                    borderRadius: BorderRadius.circular(5),
                    boxShadow: isFocused ? [
                      BoxShadow(
                        color: Colors.white.withOpacity(0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ] : null,
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
