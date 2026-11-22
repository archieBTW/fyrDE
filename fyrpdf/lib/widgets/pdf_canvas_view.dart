import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/pdf_models.dart';
import '../state/pdf_app_controller.dart';
import 'search_bar_overlay.dart';

/// Softened inversion matrix for comfortable dark-mode PDF reading.
/// Maps pure white pages to deep dark slate (~#111113) and black text to warm
/// off-white (~#ECECEE).
const List<double> kDarkReadingColorMatrix = <double>[
  -0.86, 0, 0, 0, 236,
  0, -0.86, 0, 0, 236,
  0, 0, -0.86, 0, 238,
  0, 0, 0, 1, 0,
];

/// Renders open PDF documents in an [IndexedStack] so tab scroll/zoom state
/// persists when switching tabs, overlaid with the floating search bar.
class PdfCanvasView extends StatelessWidget {
  const PdfCanvasView({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<PdfAppController>();
    if (ctrl.tabs.isEmpty || ctrl.activeTabIndex < 0) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        IndexedStack(
          index: ctrl.activeTabIndex,
          children: [
            for (final tab in ctrl.tabs)
              _SinglePdfTabView(
                key: ValueKey(tab.id),
                tab: tab,
                darkReadingMode: ctrl.darkReadingMode,
              ),
          ],
        ),
        const Positioned(
          top: 12,
          right: 16,
          child: SearchBarOverlay(),
        ),
      ],
    );
  }
}

class _SinglePdfTabView extends StatelessWidget {
  final PdfTabState tab;
  final bool darkReadingMode;

  const _SinglePdfTabView({
    super.key,
    required this.tab,
    required this.darkReadingMode,
  });

  @override
  Widget build(BuildContext context) {
    final ctrl = context.read<PdfAppController>();
    final canvasBg = darkReadingMode
        ? const Color(0xFF0E0E10)
        : (FyrTheme.isDark ? const Color(0xFF121215) : const Color(0xFFE8E9EE));

    Widget viewer = PdfViewer.file(
      tab.filePath,
      controller: tab.viewerController,
      params: PdfViewerParams(
        backgroundColor: canvasBg,
        textSelectionParams: const PdfTextSelectionParams(enabled: true),
        pagePaintCallbacks: [
          tab.textSearcher.pageTextMatchPaintCallback,
        ],
        onViewerReady: (document, controller) {
          ctrl.onViewerReady(tab, document, controller);
        },
        onPageChanged: (pageNumber) {
          ctrl.onPageChanged(tab, pageNumber);
        },
        linkHandlerParams: PdfLinkHandlerParams(
          onLinkTap: (link) {
            if (link.dest != null) {
              ctrl.goToDest(link.dest);
            }
          },
        ),
        loadingBannerBuilder: (context, bytesDownloaded, totalBytes) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  color: FyrTheme.accentColor,
                  value: totalBytes != null && totalBytes > 0
                      ? bytesDownloaded / totalBytes
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  'Opening ${tab.fileName}...',
                  style: TextStyle(
                    fontSize: 13,
                    color: FyrTheme.textColorMuted,
                  ),
                ),
              ],
            ),
          );
        },
        errorBannerBuilder: (context, error, stackTrace, documentRef) {
          return Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: FyrTheme.surfaceColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: FyrTheme.dividerColor),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 40,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Unable to Open PDF',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: FyrTheme.textColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$error',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: FyrTheme.textColorMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (tab.rotationQuarterTurns % 4 != 0) {
      viewer = RotatedBox(
        quarterTurns: tab.rotationQuarterTurns % 4,
        child: viewer,
      );
    }

    if (darkReadingMode) {
      viewer = ColorFiltered(
        colorFilter: const ColorFilter.matrix(kDarkReadingColorMatrix),
        child: viewer,
      );
    }

    return Container(
      color: canvasBg,
      child: viewer,
    );
  }
}
