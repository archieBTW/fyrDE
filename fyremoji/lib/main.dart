import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'fyr_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  
  WindowOptions windowOptions = const WindowOptions(
    size: Size(400, 250),
    minimumSize: Size(400, 250),
    maximumSize: Size(400, 250),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
  );
  
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.setBackgroundColor(Colors.transparent);
    await windowManager.setResizable(false);
    await windowManager.show();
  });

  FyrTheme.initialize();
  runApp(const FyrEmojiApp());
}

class FyrEmojiApp extends StatelessWidget {
  const FyrEmojiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([FyrTheme.accentColorNotifier, FyrTheme.themeModeNotifier]),
      builder: (context, child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Fyr Emoji',
        themeMode: FyrTheme.themeMode,
        darkTheme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: Colors.transparent,
          colorScheme: ColorScheme.dark(primary: FyrTheme.accentColor),
        ),
        theme: ThemeData.light().copyWith(
          scaffoldBackgroundColor: Colors.transparent,
          colorScheme: ColorScheme.light(primary: FyrTheme.accentColor),
        ),
        home: const EmojiPickerScreen(),
      ),
    );
  }
}

class EmojiPickerScreen extends StatefulWidget {
  const EmojiPickerScreen({super.key});

  @override
  State<EmojiPickerScreen> createState() => _EmojiPickerScreenState();
}

class _EmojiPickerScreenState extends State<EmojiPickerScreen> {
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _focusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _hidePicker() {
    Process.start('swaymsg', ['move', 'scratchpad'], mode: ProcessStartMode.detached);
  }

  void _onEmojiSelected(Category? category, Emoji emoji) {
    Clipboard.setData(ClipboardData(text: emoji.emoji));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Copied ${emoji.emoji} to clipboard!', style: TextStyle(color: FyrTheme.textColor)),
          backgroundColor: FyrTheme.hoverColor,
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) _hidePicker();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
            _hidePicker();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Container(
          decoration: BoxDecoration(
            color: FyrTheme.bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: FyrTheme.hoverColor),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: EmojiPicker(
              textEditingController: _searchController,
              onEmojiSelected: _onEmojiSelected,
              config: Config(
                checkPlatformCompatibility: true,
                emojiViewConfig: EmojiViewConfig(
                  columns: 7,
                  emojiSizeMax: 32 * (Platform.isIOS ? 1.30 : 1.0),
                  verticalSpacing: 0,
                  horizontalSpacing: 0,
                  gridPadding: EdgeInsets.zero,
                  recentsLimit: 28,
                  replaceEmojiOnLimitExceed: false,
                  noRecents: Text(
                    'No Recents',
                    style: TextStyle(fontSize: 20, color: FyrTheme.textColor.withOpacity(0.3)),
                    textAlign: TextAlign.center,
                  ),
                  loadingIndicator: const SizedBox.shrink(),
                  buttonMode: ButtonMode.MATERIAL,
                  backgroundColor: FyrTheme.bgColor,
                ),
                categoryViewConfig: CategoryViewConfig(
                  initCategory: Category.RECENT,
                  backgroundColor: FyrTheme.bgColor,
                  indicatorColor: FyrTheme.accentColor,
                  iconColor: FyrTheme.textColor.withOpacity(0.5),
                  iconColorSelected: FyrTheme.accentColor,
                  backspaceColor: FyrTheme.accentColor,
                  categoryIcons: const CategoryIcons(),
                  tabIndicatorAnimDuration: kTabScrollDuration,
                  recentTabBehavior: RecentTabBehavior.RECENT,
                ),
                skinToneConfig: SkinToneConfig(
                  dialogBackgroundColor: FyrTheme.bgColor,
                  indicatorColor: FyrTheme.textColor.withOpacity(0.5),
                  enabled: true,
                ),
                searchViewConfig: SearchViewConfig(
                  backgroundColor: FyrTheme.bgColor,
                  buttonIconColor: FyrTheme.textColor,
                ),
                bottomActionBarConfig: BottomActionBarConfig(
                  showSearchViewButton: true,
                  backgroundColor: FyrTheme.bgColor,
                  buttonColor: FyrTheme.bgColor,
                  buttonIconColor: FyrTheme.textColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
