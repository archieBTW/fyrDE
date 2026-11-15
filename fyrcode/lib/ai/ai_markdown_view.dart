import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../fyr_theme.dart';

/// Lightweight, streaming-friendly Markdown renderer tailored for FyrCode AI chat,
/// featuring fenced code blocks with Copy and Insert-to-Editor actions.
class AiMarkdownView extends StatelessWidget {
  final String data;
  final void Function(String code, String? language)? onInsertCode;
  final TextStyle? baseStyle;

  const AiMarkdownView({
    super.key,
    required this.data,
    this.onInsertCode,
    this.baseStyle,
  });

  @override
  Widget build(BuildContext context) {
    final blocks = _parseBlocks(data);
    final defaultStyle = baseStyle ??
        TextStyle(
          color: FyrTheme.textColor,
          fontSize: 13,
          height: 1.48,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _buildBlock(context, blocks[i], defaultStyle),
        ],
      ],
    );
  }

  Widget _buildBlock(
    BuildContext context,
    _MdBlock block,
    TextStyle defaultStyle,
  ) {
    switch (block.type) {
      case _MdBlockType.code:
        return _CodeBlockCard(
          code: block.text,
          language: block.language,
          onInsertCode: onInsertCode,
        );
      case _MdBlockType.heading:
        final size = switch (block.level) {
          1 => 17.0,
          2 => 15.0,
          _ => 13.5,
        };
        return SelectableText.rich(
          _parseInlineSpans(
            block.text,
            defaultStyle.copyWith(
              fontSize: size,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        );
      case _MdBlockType.blockquote:
        return Container(
          padding: const EdgeInsets.only(left: 10, top: 4, bottom: 4),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: FyrTheme.accentColor, width: 2.5),
            ),
          ),
          child: SelectableText.rich(
            _parseInlineSpans(
              block.text,
              defaultStyle.copyWith(color: FyrTheme.textColorMuted),
            ),
          ),
        );
      case _MdBlockType.listItem:
        return Padding(
          padding: EdgeInsets.only(left: (block.level * 12).toDouble()),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1, right: 6),
                child: Text(
                  block.marker ?? '•',
                  style: defaultStyle.copyWith(
                    color: FyrTheme.accentColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: SelectableText.rich(
                  _parseInlineSpans(block.text, defaultStyle),
                ),
              ),
            ],
          ),
        );
      case _MdBlockType.divider:
        return Divider(color: FyrTheme.dividerColor, height: 12);
      case _MdBlockType.paragraph:
        return SelectableText.rich(
          _parseInlineSpans(block.text, defaultStyle),
        );
    }
  }

  static List<_MdBlock> _parseBlocks(String input) {
    final lines = input.split('\n');
    final blocks = <_MdBlock>[];
    var i = 0;

    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        i++;
        continue;
      }

      // Fenced code block (```lang ... ```), also tolerates unclosed fence during streaming.
      if (trimmed.startsWith('```')) {
        final lang = trimmed.substring(3).trim();
        final codeLines = <String>[];
        i++;
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          codeLines.add(lines[i]);
          i++;
        }
        if (i < lines.length && lines[i].trim().startsWith('```')) {
          i++;
        }
        blocks.add(
          _MdBlock(
            type: _MdBlockType.code,
            text: codeLines.join('\n'),
            language: lang.isEmpty ? null : lang,
          ),
        );
        continue;
      }

      if (trimmed == '---' || trimmed == '***' || trimmed == '___') {
        blocks.add(const _MdBlock(type: _MdBlockType.divider, text: ''));
        i++;
        continue;
      }

      final headingMatch = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
      if (headingMatch != null) {
        blocks.add(
          _MdBlock(
            type: _MdBlockType.heading,
            text: headingMatch.group(2) ?? '',
            level: headingMatch.group(1)!.length,
          ),
        );
        i++;
        continue;
      }

      if (trimmed.startsWith('>')) {
        final quoteLines = <String>[];
        while (i < lines.length && lines[i].trim().startsWith('>')) {
          quoteLines.add(lines[i].trim().replaceFirst(RegExp(r'^>\s?'), ''));
          i++;
        }
        blocks.add(
          _MdBlock(type: _MdBlockType.blockquote, text: quoteLines.join('\n')),
        );
        continue;
      }

      final bulletMatch = RegExp(r'^(\s*)([-*+])\s+(.*)$').firstMatch(line);
      if (bulletMatch != null) {
        final indent = (bulletMatch.group(1)?.length ?? 0) ~/ 2;
        blocks.add(
          _MdBlock(
            type: _MdBlockType.listItem,
            text: bulletMatch.group(3) ?? '',
            level: indent,
            marker: '•',
          ),
        );
        i++;
        continue;
      }

      final orderedMatch = RegExp(r'^(\s*)(\d+\.)\s+(.*)$').firstMatch(line);
      if (orderedMatch != null) {
        final indent = (orderedMatch.group(1)?.length ?? 0) ~/ 2;
        blocks.add(
          _MdBlock(
            type: _MdBlockType.listItem,
            text: orderedMatch.group(3) ?? '',
            level: indent,
            marker: orderedMatch.group(2),
          ),
        );
        i++;
        continue;
      }

      final paraLines = <String>[line];
      i++;
      while (i < lines.length) {
        final next = lines[i].trim();
        if (next.isEmpty ||
            next.startsWith('```') ||
            next.startsWith('#') ||
            next.startsWith('>') ||
            RegExp(r'^([-*+]|\d+\.)\s+').hasMatch(next)) {
          break;
        }
        paraLines.add(lines[i]);
        i++;
      }
      blocks.add(
        _MdBlock(type: _MdBlockType.paragraph, text: paraLines.join('\n')),
      );
    }

    return blocks;
  }

  static TextSpan _parseInlineSpans(String text, TextStyle baseStyle) {
    final spans = <InlineSpan>[];
    final tokenRegex = RegExp(
      r'(`[^`]+`|\*\*[^*]+\*\*|__[^_]+__|(?<!\*)\*[^*\n]+\*(?!\*))',
    );
    var lastEnd = 0;

    for (final match in tokenRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(
            text: text.substring(lastEnd, match.start),
            style: baseStyle,
          ),
        );
      }
      final token = match.group(0)!;
      if (token.startsWith('`') && token.endsWith('`')) {
        spans.add(
          TextSpan(
            text: ' ${token.substring(1, token.length - 1)} ',
            style: GoogleFonts.jetBrainsMono(
              color: FyrTheme.accentColor,
              backgroundColor: FyrTheme.cardColor,
              fontSize: (baseStyle.fontSize ?? 13) - 1,
            ),
          ),
        );
      } else if ((token.startsWith('**') && token.endsWith('**')) ||
          (token.startsWith('__') && token.endsWith('__'))) {
        spans.add(
          TextSpan(
            text: token.substring(2, token.length - 2),
            style: baseStyle.copyWith(fontWeight: FontWeight.bold),
          ),
        );
      } else if (token.startsWith('*') && token.endsWith('*')) {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: baseStyle.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      } else {
        spans.add(TextSpan(text: token, style: baseStyle));
      }
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd), style: baseStyle));
    }

    return TextSpan(children: spans, style: baseStyle);
  }
}

enum _MdBlockType {
  paragraph,
  code,
  heading,
  blockquote,
  listItem,
  divider,
}

class _MdBlock {
  final _MdBlockType type;
  final String text;
  final String? language;
  final int level;
  final String? marker;

  const _MdBlock({
    required this.type,
    required this.text,
    this.language,
    this.level = 0,
    this.marker,
  });
}

class _CodeBlockCard extends StatefulWidget {
  final String code;
  final String? language;
  final void Function(String code, String? language)? onInsertCode;

  const _CodeBlockCard({
    required this.code,
    this.language,
    this.onInsertCode,
  });

  @override
  State<_CodeBlockCard> createState() => _CodeBlockCardState();
}

class _CodeBlockCardState extends State<_CodeBlockCard> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: FyrTheme.bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FyrTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: FyrTheme.cardColor,
              border: Border(
                bottom: BorderSide(color: FyrTheme.dividerColor),
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(5),
              ),
            ),
            child: Row(
              children: [
                Text(
                  widget.language ?? 'code',
                  style: GoogleFonts.jetBrainsMono(
                    color: FyrTheme.textColorMuted,
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                if (widget.onInsertCode != null)
                  InkWell(
                    onTap: () =>
                        widget.onInsertCode!(widget.code, widget.language),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.input,
                            size: 13,
                            color: FyrTheme.accentColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Insert',
                            style: TextStyle(
                              color: FyrTheme.accentColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: widget.code));
                    if (!mounted) return;
                    setState(() => _copied = true);
                    Future.delayed(const Duration(seconds: 2), () {
                      if (mounted) setState(() => _copied = false);
                    });
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _copied ? Icons.check : Icons.copy,
                          size: 13,
                          color: _copied
                              ? Colors.greenAccent
                              : FyrTheme.textColorMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _copied ? 'Copied' : 'Copy',
                          style: TextStyle(
                            color: _copied
                                ? Colors.greenAccent
                                : FyrTheme.textColorMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(10),
            child: SelectableText(
              widget.code,
              style: GoogleFonts.jetBrainsMono(
                color: FyrTheme.textColor,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Color-coded unified diff preview widget used in tool cards and approvals.
class DiffPreviewWidget extends StatelessWidget {
  final String unifiedDiff;
  final double maxHeight;

  const DiffPreviewWidget({
    super.key,
    required this.unifiedDiff,
    this.maxHeight = 240,
  });

  @override
  Widget build(BuildContext context) {
    final lines = unifiedDiff.split('\n');
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      width: double.infinity,
      decoration: BoxDecoration(
        color: FyrTheme.isDark
            ? const Color(0xFF0C0D10)
            : const Color(0xFFF6F8FA),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FyrTheme.dividerColor),
      ),
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: lines.map((line) {
                final isAdded = line.startsWith('+');
                final isRemoved = line.startsWith('-');
                final isHunk = line.startsWith('@@');
                final bgColor = isAdded
                    ? const Color(0xFF2EA043).withValues(alpha: 0.18)
                    : (isRemoved
                        ? const Color(0xFFF85149).withValues(alpha: 0.18)
                        : Colors.transparent);
                final textColor = isAdded
                    ? (FyrTheme.isDark
                        ? const Color(0xFF7EE787)
                        : const Color(0xFF1A7F37))
                    : (isRemoved
                        ? (FyrTheme.isDark
                            ? const Color(0xFFFFA198)
                            : const Color(0xFFCF222E))
                        : (isHunk
                            ? FyrTheme.accentColor
                            : FyrTheme.textColorMuted));
                return Container(
                  color: bgColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 1,
                  ),
                  child: Text(
                    line.isEmpty ? ' ' : line,
                    style: GoogleFonts.jetBrainsMono(
                      color: textColor,
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}
