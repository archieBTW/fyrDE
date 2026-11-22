import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:fyrtaskbar/fyr_theme.dart';
import 'package:fyrtaskbar/state/system_state.dart';

class ScreenshotToastOverlay extends StatelessWidget {
  const ScreenshotToastOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ScreenshotPreview?>(
      valueListenable: SystemState.activeScreenshotToast,
      builder: (context, preview, _) {
        if (preview == null) return const SizedBox.shrink();
        return Positioned(
          top: 12,
          right: 20,
          child: GestureDetector(
            onTap: () {},
            child: _ScreenshotToastCard(preview: preview),
          ),
        );
      },
    );
  }
}

class _ScreenshotToastCard extends StatefulWidget {
  final ScreenshotPreview preview;
  const _ScreenshotToastCard({required this.preview});

  @override
  State<_ScreenshotToastCard> createState() => _ScreenshotToastCardState();
}

class _ScreenshotToastCardState extends State<_ScreenshotToastCard> {
  bool _copiedFeedback = false;

  Future<void> _copyToClipboard() async {
    final path = widget.preview.filePath;
    if (!File(path).existsSync()) return;
    try {
      await Process.run('sh', ['-c', 'wl-copy -t image/png < "\$1"', '--', path]);
      if (mounted) {
        setState(() => _copiedFeedback = true);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _copiedFeedback = false);
        });
      }
    } catch (_) {}
  }

  Future<void> _openInPhotos() async {
    final path = widget.preview.filePath;
    if (!File(path).existsSync()) return;
    SystemState.dismissScreenshotPreview();
    if (File('/opt/fyrphotos/fyrphotos').existsSync()) {
      await Process.start(
        '/opt/fyrphotos/fyrphotos',
        [path],
        mode: ProcessStartMode.detached,
      );
      return;
    }
    try {
      await Process.start('gio', ['open', path], mode: ProcessStartMode.detached);
    } catch (_) {
      await Process.start(
        'xdg-open',
        [path],
        mode: ProcessStartMode.detached,
      );
    }
  }

  Future<void> _editInGraphics() async {
    final path = widget.preview.filePath;
    if (!File(path).existsSync()) return;
    SystemState.dismissScreenshotPreview();
    if (File('/opt/fyrgraphics/fyrgraphics').existsSync()) {
      await Process.start(
        '/opt/fyrgraphics/fyrgraphics',
        [path],
        mode: ProcessStartMode.detached,
      );
      return;
    }
    try {
      await Process.start(
        'fyrgraphics',
        [path],
        mode: ProcessStartMode.detached,
      );
    } catch (_) {
      await _openInPhotos();
    }
  }

  Future<void> _deleteScreenshot() async {
    final file = File(widget.preview.filePath);
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
    SystemState.dismissScreenshotPreview();
  }

  @override
  Widget build(BuildContext context) {
    final file = File(widget.preview.filePath);
    final fileName = widget.preview.filePath.split('/').last;

    return MouseRegion(
      onEnter: (_) => SystemState.pauseScreenshotPreviewTimer(),
      onExit: (_) => SystemState.resumeScreenshotPreviewTimer(),
      child: Container(
        width: 320,
        decoration: BoxDecoration(
          color: FyrTheme.panelBgColor.withOpacity(0.94),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: FyrTheme.cardColor, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.screenshot_monitor,
                      size: 16,
                      color: FyrTheme.accentColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.preview.label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: FyrTheme.textColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            fileName,
                            style: TextStyle(
                              fontSize: 10,
                              color: FyrTheme.textColorMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        Icons.close,
                        size: 16,
                        color: FyrTheme.textColorMuted,
                      ),
                      onPressed: SystemState.dismissScreenshotPreview,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _openInPhotos,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      height: 148,
                      width: double.infinity,
                      color: Colors.black26,
                      child: file.existsSync()
                          ? Image.file(
                              file,
                              key: ValueKey(widget.preview.filePath),
                              fit: BoxFit.cover,
                              cacheWidth: 640,
                              errorBuilder: (_, __, ___) => Center(
                                child: Icon(
                                  Icons.image_outlined,
                                  color: FyrTheme.textColorMuted,
                                  size: 36,
                                ),
                              ),
                            )
                          : Center(
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                color: FyrTheme.textColorMuted,
                                size: 32,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _ActionPill(
                        icon: _copiedFeedback ? Icons.check : Icons.copy,
                        label: _copiedFeedback ? 'Copied' : 'Copy',
                        accent: _copiedFeedback,
                        onTap: _copyToClipboard,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _ActionPill(
                        icon: Icons.open_in_new,
                        label: 'Open',
                        onTap: _openInPhotos,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _ActionPill(
                        icon: Icons.edit_outlined,
                        label: 'Edit',
                        onTap: _editInGraphics,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _ActionPill(
                      icon: Icons.delete_outline,
                      label: '',
                      danger: true,
                      tooltip: 'Delete screenshot',
                      onTap: _deleteScreenshot,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool accent;
  final bool danger;
  final String? tooltip;

  const _ActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
    this.danger = false,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final fg = danger
        ? Colors.redAccent
        : (accent ? FyrTheme.accentColor : FyrTheme.textColor);
    final bg = danger
        ? Colors.redAccent.withOpacity(0.14)
        : (accent
              ? FyrTheme.accentColor.withOpacity(0.2)
              : FyrTheme.cardColor.withOpacity(0.8));

    final child = Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: label.isEmpty ? 8 : 6,
            vertical: 7,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: child);
    }
    return child;
  }
}
