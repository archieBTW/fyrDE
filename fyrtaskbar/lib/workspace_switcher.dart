import 'dart:io';
import 'package:flutter/material.dart';
import 'main.dart';
import 'fyr_theme.dart';

class WorkspaceSwitcher extends StatelessWidget {
  const WorkspaceSwitcher({super.key});

  void _switchWorkspace(String name) {
    Process.start('swaymsg', ['workspace', name]);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: SystemState.workspaces,
      builder: (context, workspaces, _) {
        if (workspaces.isEmpty) return const SizedBox();

        final sortedWorkspaces = List<Map<String, dynamic>>.from(workspaces)
          ..sort((a, b) => (a['num'] as int).compareTo(b['num'] as int));

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: sortedWorkspaces.map((ws) {
            final bool isFocused = ws['focused'] == true;
            final bool isVisible = ws['visible'] == true;
            final String name = ws['name'].toString();

            return InkWell(
              onTap: () => _switchWorkspace(name),
              hoverColor: FyrTheme.hoverColor,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isFocused
                      ? FyrTheme.accentColor.withOpacity(0.2)
                      : (isVisible ? FyrTheme.cardColor : Colors.transparent),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isFocused
                        ? FyrTheme.accentColor.withOpacity(0.5)
                        : (isVisible
                            ? FyrTheme.textColor.withOpacity(0.1)
                            : Colors.transparent),
                  ),
                ),
                child: Text(
                  name,
                  style: TextStyle(
                    color: isFocused
                        ? FyrTheme.accentColor
                        : FyrTheme.textColor.withOpacity(isVisible ? 0.9 : 0.6),
                    fontWeight: isFocused ? FontWeight.bold : FontWeight.w500,
                    fontSize: 13,
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
