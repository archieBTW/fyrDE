import 'dart:ui' as ui;
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
      final isDark = FyrTheme.isDark;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji.emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(
                'Copied to clipboard',
                style: TextStyle(
                  color: FyrTheme.textColor,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          backgroundColor: isDark
              ? const Color(0xFF1F1D26).withValues(alpha: 0.92)
              : Colors.white.withValues(alpha: 0.94),
          duration: const Duration(milliseconds: 650),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: FyrTheme.accentColor, width: 1.2),
          ),
        ),
      );
    }
    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted) _hidePicker();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = FyrTheme.isDark;
    final glassBg = isDark
        ? const Color(0xFF18171D).withValues(alpha: 0.60)
        : Colors.white.withValues(alpha: 0.72);
    final rimColor = FyrTheme.accentColor.withValues(alpha: 0.32);

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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: glassBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: rimColor, width: 1.1),
              ),
              child: EmojiPicker(
                key: ValueKey(_pickerSession),
                onEmojiSelected: _onEmojiSelected,
                config: Config(
                  checkPlatformCompatibility: true,
                  emojiViewConfig: EmojiViewConfig(
                    columns: 8,
                    emojiSizeMax: 28,
                    verticalSpacing: 2,
                    horizontalSpacing: 2,
                    gridPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    recentsLimit: 28,
                    replaceEmojiOnLimitExceed: false,
                    noRecents: Text(
                      'No Recents',
                      style: TextStyle(
                        fontSize: 15,
                        color: FyrTheme.textColorMuted.withValues(alpha: 0.6),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    loadingIndicator: const SizedBox.shrink(),
                    buttonMode: ButtonMode.MATERIAL,
                    backgroundColor: Colors.transparent,
                  ),
                  categoryViewConfig: CategoryViewConfig(
                    initCategory: Category.RECENT,
                    backgroundColor: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.black.withValues(alpha: 0.04),
                    indicatorColor: FyrTheme.accentColor,
                    iconColor: FyrTheme.textColorMuted.withValues(alpha: 0.65),
                    iconColorSelected: FyrTheme.accentColor,
                    backspaceColor: FyrTheme.accentColor,
                    dividerColor: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.08),
                    categoryIcons: const CategoryIcons(),
                    tabIndicatorAnimDuration: kTabScrollDuration,
                    recentTabBehavior: RecentTabBehavior.RECENT,
                  ),
                  skinToneConfig: SkinToneConfig(
                    dialogBackgroundColor: isDark
                        ? const Color(0xFF1F1D26)
                        : Colors.white,
                    indicatorColor: FyrTheme.accentColor,
                    enabled: true,
                  ),
                  searchViewConfig: SearchViewConfig(
                    backgroundColor: Colors.transparent,
                    buttonIconColor: FyrTheme.accentColor,
                    inputTextStyle: TextStyle(
                      color: FyrTheme.textColor,
                      fontSize: 13.5,
                    ),
                    hintTextStyle: TextStyle(
                      color: FyrTheme.textColorMuted,
                      fontSize: 13,
                    ),
                    customSearchView: (config, state, showEmojiView) =>
                        _FyrEmojiSearchView(config, state, showEmojiView),
                  ),
                  bottomActionBarConfig: BottomActionBarConfig(
                    showSearchViewButton: true,
                    showBackspaceButton: false,
                    backgroundColor: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.black.withValues(alpha: 0.04),
                    buttonColor: Colors.transparent,
                    buttonIconColor: FyrTheme.accentColor,
                  ),
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

  int _hoveredIndex = -1;

  @override
  Widget build(BuildContext context) {
    final isDark = FyrTheme.isDark;
    final searchFill = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.05);

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = widget.config.emojiViewConfig.columns;
        final emojiSize =
            widget.config.emojiViewConfig.getEmojiSize(constraints.maxWidth);

        return Container(
          color: Colors.transparent,
          child: Column(
            children: [
              // Frosted pill search input bar at top
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                child: Row(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: widget.showEmojiView,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: searchFill,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Icon(
                          Icons.arrow_back_rounded,
                          size: 16,
                          color: FyrTheme.accentColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: searchFill,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: FyrTheme.accentColor.withValues(alpha: 0.55),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.search_rounded,
                              size: 16,
                              color: FyrTheme.accentColor,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _queryController,
                                focusNode: focusNode,
                                autofocus: true,
                                onChanged: (v) {
                                  _hoveredIndex = -1;
                                  onTextInputChanged(v);
                                },
                                onSubmitted: (_) {
                                  if (results.isNotEmpty) {
                                    widget.state.onEmojiSelected(
                                      null,
                                      results.first,
                                    );
                                  }
                                },
                                style: TextStyle(
                                  color: FyrTheme.textColor,
                                  fontSize: 13.5,
                                ),
                                cursorColor: FyrTheme.accentColor,
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  hintText: 'Search emojis...',
                                  hintStyle: TextStyle(
                                    color: FyrTheme.textColorMuted,
                                    fontSize: 13,
                                  ),
                                  isDense: true,
                                ),
                              ),
                            ),
                            if (_query.isNotEmpty)
                              InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () {
                                  _queryController.clear();
                                  onTextInputChanged('');
                                  focusNode.requestFocus();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(3),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 15,
                                    color: FyrTheme.textColorMuted,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                thickness: 1,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.08),
              ),
              // Scrollable grid of matching emojis with accent hover border
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
                        padding: const EdgeInsets.all(8),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                        ),
                        itemCount: results.length,
                        itemBuilder: (context, index) {
                          final emoji = results[index];
                          final hovered = index == _hoveredIndex;
                          return MouseRegion(
                            cursor: SystemMouseCursors.click,
                            onEnter: (_) =>
                                setState(() => _hoveredIndex = index),
                            onExit: (_) {
                              if (_hoveredIndex == index) {
                                setState(() => _hoveredIndex = -1);
                              }
                            },
                            child: GestureDetector(
                              onTap: () =>
                                  widget.state.onEmojiSelected(null, emoji),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 100),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: hovered
                                      ? (isDark
                                          ? Colors.white.withValues(alpha: 0.08)
                                          : Colors.black.withValues(alpha: 0.05))
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: hovered
                                        ? FyrTheme.accentColor
                                        : Colors.transparent,
                                    width: 1.5,
                                  ),
                                ),
                                child: Text(
                                  emoji.emoji,
                                  style: TextStyle(fontSize: emojiSize * 0.78),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
