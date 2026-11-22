import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fyrtaskbar/fyr_theme.dart';
import 'package:fyrtaskbar/services/mpris_service.dart';

class TaskbarMediaPill extends StatelessWidget {
  final VoidCallback? onOpenDetails;
  const TaskbarMediaPill({super.key, this.onOpenDetails});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MprisPlayer?>(
      valueListenable: MprisService.activePlayer,
      builder: (context, player, _) {
        if (player == null || !player.hasTrack) {
          return const SizedBox.shrink();
        }
        return Container(
          margin: const EdgeInsets.only(left: 10),
          constraints: const BoxConstraints(maxWidth: 230),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: FyrTheme.isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: player.isPlaying
                  ? FyrTheme.accentColor.withOpacity(0.45)
                  : FyrTheme.textColor.withOpacity(0.1),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => MprisService.playPause(player.busName),
                behavior: HitTestBehavior.opaque,
                child: Icon(
                  player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 16,
                  color: player.isPlaying
                      ? FyrTheme.accentColor
                      : FyrTheme.textColor.withOpacity(0.85),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: GestureDetector(
                  onTap: onOpenDetails ?? () => MprisService.playPause(player.busName),
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    player.artist.isNotEmpty
                        ? '${player.displayTitle} • ${player.artist}'
                        : player.displayTitle,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: FyrTheme.textColor.withOpacity(0.9),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (player.canGoNext) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => MprisService.next(player.busName),
                  behavior: HitTestBehavior.opaque,
                  child: Icon(
                    Icons.skip_next_rounded,
                    size: 15,
                    color: FyrTheme.textColorMuted,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class QuickSettingsMediaCard extends StatelessWidget {
  const QuickSettingsMediaCard({super.key});

  Widget _buildArt(String artUrl) {
    if (artUrl.startsWith('file://')) {
      final path = Uri.tryParse(artUrl)?.toFilePath();
      if (path != null && File(path).existsSync()) {
        return Image.file(
          File(path),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallbackArt(),
        );
      }
    } else if (artUrl.startsWith('http://') || artUrl.startsWith('https://')) {
      return Image.network(
        artUrl,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackArt(),
      );
    }
    return _fallbackArt();
  }

  Widget _fallbackArt() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: FyrTheme.accentColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        Icons.music_note_rounded,
        color: FyrTheme.accentColor,
        size: 24,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<MprisPlayer>>(
      valueListenable: MprisService.players,
      builder: (context, allPlayers, _) {
        return ValueListenableBuilder<MprisPlayer?>(
          valueListenable: MprisService.activePlayer,
          builder: (context, player, _) {
            if (player == null) return const SizedBox.shrink();
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: FyrTheme.isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: FyrTheme.textColor.withOpacity(0.08),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: _buildArt(player.artUrl),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              player.displayTitle,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: FyrTheme.textColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (player.artist.isNotEmpty)
                              Text(
                                player.artist,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: FyrTheme.textColorMuted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            else
                              Text(
                                player.identity.isNotEmpty
                                    ? player.identity
                                    : player.shortBusLabel,
                                style: TextStyle(
                                  fontSize: 11,
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
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        icon: Icon(
                          Icons.skip_previous_rounded,
                          color: player.canGoPrevious
                              ? FyrTheme.textColor
                              : FyrTheme.textColorMuted.withOpacity(0.4),
                          size: 20,
                        ),
                        onPressed: player.canGoPrevious
                            ? () => MprisService.previous(player.busName)
                            : null,
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: FyrTheme.accentColor,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 34,
                            minHeight: 34,
                          ),
                          icon: Icon(
                            player.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: () =>
                              MprisService.playPause(player.busName),
                        ),
                      ),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        icon: Icon(
                          Icons.skip_next_rounded,
                          color: player.canGoNext
                              ? FyrTheme.textColor
                              : FyrTheme.textColorMuted.withOpacity(0.4),
                          size: 20,
                        ),
                        onPressed: player.canGoNext
                            ? () => MprisService.next(player.busName)
                            : null,
                      ),
                    ],
                  ),
                  if (allPlayers.length > 1) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: allPlayers.map((p) {
                        final selected = p.busName == player.busName;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () => MprisService.selectPlayer(p.busName),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? FyrTheme.accentColor.withOpacity(0.22)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selected
                                      ? FyrTheme.accentColor
                                      : FyrTheme.textColor.withOpacity(0.12),
                                ),
                              ),
                              child: Text(
                                p.identity.isNotEmpty
                                    ? p.identity
                                    : p.shortBusLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: selected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: selected
                                      ? FyrTheme.accentColor
                                      : FyrTheme.textColorMuted,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}
