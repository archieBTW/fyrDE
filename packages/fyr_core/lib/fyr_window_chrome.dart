import 'dart:io';
import 'package:flutter/material.dart';
import 'fyr_theme.dart';

/// Standard traffic-light window controls shared across fyrDE Flutter apps.
class FyrWindowControls extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback? onMinimize;
  final VoidCallback? onMaximize;
  final double dotSize;
  final double spacing;

  const FyrWindowControls({
    super.key,
    required this.onClose,
    this.onMinimize,
    this.onMaximize,
    this.dotSize = 16.0,
    this.spacing = 8.0,
  });

  static void defaultMinimizeToScratchpad() {
    Process.run('swaymsg', ['[pid="$pid"] move scratchpad']);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Close',
          child: InkWell(
            borderRadius: BorderRadius.circular(dotSize),
            onTap: onClose,
            child: Icon(Icons.circle, color: Colors.red.shade300, size: dotSize),
          ),
        ),
        SizedBox(width: spacing),
        Tooltip(
          message: 'Minimize',
          child: InkWell(
            borderRadius: BorderRadius.circular(dotSize),
            onTap: onMinimize ?? defaultMinimizeToScratchpad,
            child: Icon(Icons.circle, color: Colors.amber.shade300, size: dotSize),
          ),
        ),
        if (onMaximize != null) ...[
          SizedBox(width: spacing),
          Tooltip(
            message: 'Maximize / Restore',
            child: InkWell(
              borderRadius: BorderRadius.circular(dotSize),
              onTap: onMaximize,
              child: Icon(Icons.circle, color: Colors.green.shade300, size: dotSize),
            ),
          ),
        ],
      ],
    );
  }
}

/// Shared draggable client-side title bar for fyrDE applications.
class FyrTitleBar extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback? onMinimize;
  final VoidCallback? onMaximize;
  final VoidCallback? onDragStart;
  final Widget? title;
  final List<Widget> actions;
  final double height;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Border? border;

  const FyrTitleBar({
    super.key,
    required this.onClose,
    this.onMinimize,
    this.onMaximize,
    this.onDragStart,
    this.title,
    this.actions = const [],
    this.height = 48.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.backgroundColor,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final dragArea = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: onDragStart == null ? null : (_) => onDragStart!(),
      onDoubleTap: onMaximize,
      child: Align(
        alignment: Alignment.centerLeft,
        child: title ?? const SizedBox.expand(),
      ),
    );

    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        border: border,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          FyrWindowControls(
            onClose: onClose,
            onMinimize: onMinimize,
            onMaximize: onMaximize,
          ),
          const SizedBox(width: 16),
          Expanded(child: dragArea),
          ...actions,
        ],
      ),
    );
  }
}

/// Shows a themed single-line text input dialog with automatic focus and
/// Enter-to-submit behavior. Returns the trimmed value or `null` if cancelled.
Future<String?> showFyrInputDialog({
  required BuildContext context,
  required String title,
  String hintText = '',
  String initialValue = '',
  String confirmLabel = 'OK',
  String cancelLabel = 'Cancel',
  TextSelection? initialSelection,
}) async {
  final controller = TextEditingController(text: initialValue);
  if (initialSelection != null) {
    controller.selection = initialSelection;
  }

  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      void submit() {
        final value = controller.text.trim();
        if (value.isNotEmpty) {
          Navigator.pop(dialogContext, value);
        }
      }

      return AlertDialog(
        backgroundColor: FyrTheme.surfaceColor,
        title: Text(title, style: TextStyle(color: FyrTheme.textColor)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: FyrTheme.textColor),
          onSubmitted: (_) => submit(),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(color: FyrTheme.textColorMuted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(cancelLabel),
          ),
          TextButton(
            onPressed: submit,
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
}
