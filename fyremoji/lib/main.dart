import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'fyr_theme.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  FyrTheme.initialize();
  runApp(FyrEmojiApp(initiallyVisible: args.contains('--show')));
}

class FyrEmojiApp extends StatelessWidget {
  final bool initiallyVisible;
  const FyrEmojiApp({super.key, this.initiallyVisible = false});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        FyrTheme.accentColorNotifier,
        FyrTheme.themeModeNotifier,
      ]),
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
        home: EmojiPickerScreen(initiallyVisible: initiallyVisible),
      ),
    );
  }
}

class EmojiPickerScreen extends StatefulWidget {
  final bool initiallyVisible;
  const EmojiPickerScreen({super.key, this.initiallyVisible = false});

  @override
  State<EmojiPickerScreen> createState() => _EmojiPickerScreenState();
}

class _EmojiPickerScreenState extends State<EmojiPickerScreen> {
  final FocusNode _focusNode = FocusNode();
  late final OverlayWindowController _overlayController;
  int _pickerSession = 0;

  @override
  void initState() {
    super.initState();
    _overlayController = OverlayWindowController(
      appName: 'fyremoji',
      onShow: () {
        if (mounted) _focusNode.requestFocus();
      },
      onHide: () {
        if (mounted) {
          setState(() => _pickerSession++);
        }
      },
    );
    _overlayController.start(initiallyVisible: widget.initiallyVisible);
  }

  @override
  void dispose() {
    _overlayController.stop();
    _focusNode.dispose();
    super.dispose();
  }

  void _hidePicker() {
    _overlayController.hide();
  }

  void _onEmojiSelected(Category? category, Emoji emoji) {
    Clipboard.setData(ClipboardData(text: emoji.emoji));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Copied ${emoji.emoji} to clipboard!',
            style: TextStyle(color: FyrTheme.textColor),
          ),
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
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
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
              key: ValueKey(_pickerSession),
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
                    style: TextStyle(
                      fontSize: 20,
                      color: FyrTheme.textColor.withValues(alpha: 0.3),
                    ),
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
                  iconColor: FyrTheme.textColor.withValues(alpha: 0.5),
                  iconColorSelected: FyrTheme.accentColor,
                  backspaceColor: FyrTheme.accentColor,
                  categoryIcons: const CategoryIcons(),
                  tabIndicatorAnimDuration: kTabScrollDuration,
                  recentTabBehavior: RecentTabBehavior.RECENT,
                ),
                skinToneConfig: SkinToneConfig(
                  dialogBackgroundColor: FyrTheme.bgColor,
                  indicatorColor: FyrTheme.textColor.withValues(alpha: 0.5),
                  enabled: true,
                ),
                searchViewConfig: SearchViewConfig(
                  backgroundColor: FyrTheme.bgColor,
                  buttonIconColor: FyrTheme.textColor,
                  inputTextStyle: TextStyle(
                    color: FyrTheme.textColor,
                    fontSize: 14,
                  ),
                  hintTextStyle: TextStyle(
                    color: FyrTheme.textColorMuted,
                    fontSize: 14,
                  ),
                  customSearchView: (config, state, showEmojiView) =>
                      _FyrEmojiSearchView(config, state, showEmojiView),
                ),
                bottomActionBarConfig: BottomActionBarConfig(
                  showSearchViewButton: true,
                  showBackspaceButton: false,
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

class _FyrEmojiSearchView extends SearchView {
  const _FyrEmojiSearchView(super.config, super.state, super.showEmojiView);

  @override
  _FyrEmojiSearchViewState createState() => _FyrEmojiSearchViewState();
}

class _FyrEmojiSearchViewState extends SearchViewState<_FyrEmojiSearchView> {
  final TextEditingController _queryController = TextEditingController();
  late final List<Emoji> _allEmojis;
  String _query = '';

  @override
  void initState() {
    super.initState();
    final seen = <String>{};
    _allEmojis = [];
    for (final cat in widget.state.categoryEmoji) {
      if (cat.category == Category.RECENT) continue;
      for (final emoji in cat.emoji) {
        if (seen.add(emoji.emoji)) {
          _allEmojis.add(emoji);
        }
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  void onTextInputChanged(String text) {
    final trimmed = text.trim().toLowerCase();
    setState(() {
      _query = trimmed;
    });
    if (trimmed.isEmpty) {
      utils.getRecentEmojis().then((recents) {
        if (!mounted || _query.isNotEmpty) return;
        setState(() {
          results
            ..clear()
            ..addAll(recents.map((e) => e.emoji));
        });
      });
      return;
    }

    final terms =
        trimmed.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final matches = _allEmojis.where((emoji) {
      if (emoji.emoji == trimmed) return true;
      final hay = emoji.name.toLowerCase();
      return terms.every((term) => hay.contains(term));
    }).toList();

    setState(() {
      results
        ..clear()
        ..addAll(matches);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = widget.config.emojiViewConfig.columns;
        final emojiSize =
            widget.config.emojiViewConfig.getEmojiSize(constraints.maxWidth);
        final emojiBoxSize =
            widget.config.emojiViewConfig.getEmojiBoxSize(constraints.maxWidth);

        return Container(
          color: widget.config.searchViewConfig.backgroundColor,
          child: Column(
            children: [
              // Search input bar at top
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: FyrTheme.dividerColor),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: widget.showEmojiView,
                      color: widget.config.searchViewConfig.buttonIconColor,
                      icon: const Icon(Icons.arrow_back, size: 18),
                      tooltip: 'Back to emojis',
                    ),
                    Expanded(
                      child: TextField(
                        controller: _queryController,
                        focusNode: focusNode,
                        autofocus: true,
                        onChanged: onTextInputChanged,
                        onSubmitted: (_) {
                          if (results.isNotEmpty) {
                            widget.state.onEmojiSelected(null, results.first);
                          }
                        },
                        style: TextStyle(
                          color: FyrTheme.textColor,
                          fontSize: 14,
                        ),
                        cursorColor: FyrTheme.accentColor,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Search emojis (e.g. smile, fire, heart)...',
                          hintStyle: TextStyle(
                            color: FyrTheme.textColorMuted,
                            fontSize: 13,
                          ),
                          isDense: true,
                        ),
                      ),
                    ),
                    if (_query.isNotEmpty)
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          size: 16,
                          color: FyrTheme.textColorMuted,
                        ),
                        onPressed: () {
                          _queryController.clear();
                          onTextInputChanged('');
                          focusNode.requestFocus();
                        },
                      ),
                  ],
                ),
              ),
              // Scrollable grid of matching emojis
              Expanded(
                child: results.isEmpty
                    ? Center(
                        child: Text(
                          _query.isEmpty
                              ? 'Type to search emojis...'
                              : 'No emojis found for "$_query"',
                          style: TextStyle(
                            fontSize: 13,
                            color: FyrTheme.textColorMuted,
                          ),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(6),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: 2,
                          crossAxisSpacing: 2,
                        ),
                        itemCount: results.length,
                        itemBuilder: (context, index) => buildEmoji(
                          results[index],
                          emojiSize,
                          emojiBoxSize,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
