import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'fyr_theme.dart';

void main() {
  FyrTheme.initialize();
  runApp(const HelpApp());
}

class HelpApp extends StatelessWidget {
  const HelpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([FyrTheme.accentColorNotifier, FyrTheme.themeModeNotifier]),
      builder: (context, child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Sway Help',
        themeMode: FyrTheme.themeMode,
        darkTheme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: Colors.transparent,
          textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'San Francisco'),
          colorScheme: ColorScheme.dark(
            primary: FyrTheme.accentColor,
            secondary: FyrTheme.accentColor,
          ),
        ),
        theme: ThemeData.light().copyWith(
          scaffoldBackgroundColor: Colors.transparent,
          textTheme: ThemeData.light().textTheme.apply(fontFamily: 'San Francisco'),
          colorScheme: ColorScheme.light(
            primary: FyrTheme.accentColor,
            secondary: FyrTheme.accentColor,
          ),
        ),
        home: const HelpScreen(),
      ),
    );
  }
}

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _hideHelp() {
    Process.start('swaymsg', ['move', 'scratchpad'], mode: ProcessStartMode.detached);
  }

  Widget _buildShortcut(String keys, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              description,
              style: TextStyle(
                color: FyrTheme.textColor.withOpacity(0.9),
                fontSize: 16,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: FyrTheme.hoverColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: FyrTheme.textColor.withOpacity(0.1)),
            ),
            child: Text(
              keys,
              style: TextStyle(
                color: FyrTheme.accentColor,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Focus(
        focusNode: _focusNode,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
            _hideHelp();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Center(
          child: Container(
            width: 650,
            height: 600,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: FyrTheme.bgColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: FyrTheme.accentColor.withOpacity(0.5), width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 40,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Keyboard Shortcuts',
                      style: TextStyle(
                        color: FyrTheme.textColor,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: FyrTheme.textColor, size: 28),
                      onPressed: _hideHelp,
                      hoverColor: FyrTheme.hoverColor,
                      splashRadius: 24,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: ListView(
                    children: [
                      _buildShortcut('Super + Q', 'Close Focused Window'),
                      _buildShortcut('Alt + Tab', 'Focus Next Window'),
                      _buildShortcut('Alt + Shift + Tab', 'Focus Previous Window'),
                      _buildShortcut('Super + T', 'Open Terminal (fyrterm)'),
                      _buildShortcut('Super + F', 'Open File Manager (fyr_files)'),
                      _buildShortcut('Super + M', 'Toggle Floating Mode'),
                      _buildShortcut('Super + Space', 'Open App Launcher (fyrsearch)'),
                      _buildShortcut('Super + Tab', 'Open Overview (fyroverview)'),
                      _buildShortcut('Super + Ctrl', 'Show This Cheatsheet (fyrhelp)'),
                      _buildShortcut('Super + .', 'Open Emoji Picker (fyremoji)'),
                      _buildShortcut('Super + V', 'Split Vertical'),
                      _buildShortcut('Super + H', 'Split Horizontal'),
                      _buildShortcut('Super + 1..0', 'Switch to Workspace 1..10'),
                      _buildShortcut('Super + Shift + 1..0', 'Move Window to Workspace 1..10'),
                      _buildShortcut('Super + Arrows', 'Change Focus'),
                      _buildShortcut('Super + Shift + Arrows', 'Resize Window'),
                      _buildShortcut('Swipe 3 L/R', 'Prev/Next Workspace'),
                      _buildShortcut('Swipe 3 D/U', 'Show/Hide Overview'),
                      _buildShortcut('Print Screen', 'Take Screenshot'),
                      _buildShortcut('Super + Print Screen', 'Toggle Screen Recording'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
