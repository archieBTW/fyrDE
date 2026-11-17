import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../engine/core_manager.dart';
import '../fyr_theme.dart';
import '../models/emu_types.dart';
import '../state/emu_controller.dart';
import 'core_manager_dialog.dart';

class LibraryView extends StatelessWidget {
  const LibraryView({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<EmuController>();
    final games = ctrl.filteredLibrary;

    return Expanded(
      child: Row(
        children: [
          // Left Sidebar
          Container(
            width: 240,
            decoration: BoxDecoration(
              color: FyrTheme.sidebarColor,
              border: Border(right: BorderSide(color: FyrTheme.dividerColor)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                _sectionLabel('LIBRARY'),
                _navTile(
                  icon: Icons.apps_rounded,
                  label: 'All Games',
                  count: ctrl.library.length,
                  selected: ctrl.libraryFilter == LibraryFilter.all &&
                      ctrl.platformFilter == null,
                  onTap: () {
                    ctrl.libraryFilter = LibraryFilter.all;
                    ctrl.platformFilter = null;
                    ctrl.refresh();
                  },
                ),
                _navTile(
                  icon: Icons.history_rounded,
                  label: 'Recently Played',
                  count: ctrl.library.where((r) => r.lastPlayed != null).length,
                  selected: ctrl.libraryFilter == LibraryFilter.recent &&
                      ctrl.platformFilter == null,
                  onTap: () {
                    ctrl.libraryFilter = LibraryFilter.recent;
                    ctrl.platformFilter = null;
                    ctrl.refresh();
                  },
                ),
                _navTile(
                  icon: Icons.star_rounded,
                  label: 'Favorites',
                  count: ctrl.library.where((r) => r.favorite).length,
                  selected: ctrl.libraryFilter == LibraryFilter.favorites &&
                      ctrl.platformFilter == null,
                  onTap: () {
                    ctrl.libraryFilter = LibraryFilter.favorites;
                    ctrl.platformFilter = null;
                    ctrl.refresh();
                  },
                ),
                const SizedBox(height: 12),
                _sectionLabel('PLATFORMS'),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      ...ConsolePlatform.values.map((plat) {
                        final hasCore =
                            CoreManager.findBestCoreForPlatform(plat) != null;
                        final count = ctrl.library
                            .where((r) => r.platform == plat)
                            .length;
                        final selected = ctrl.platformFilter == plat;
                        return _navTile(
                          icon: Icons.videogame_asset_rounded,
                          iconColor: plat.accent,
                          label: plat.label,
                          count: count,
                          trailingDotColor:
                              hasCore ? Colors.greenAccent : Colors.orangeAccent,
                          selected: selected,
                          onTap: () {
                            ctrl.libraryFilter = LibraryFilter.all;
                            ctrl.platformFilter = plat;
                            ctrl.refresh();
                          },
                        );
                      }),
                      const SizedBox(height: 12),
                      _sectionLabel('ROM FOLDERS'),
                      ...ctrl.romFolders.map((folder) => Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 2),
                            child: Row(
                              children: [
                                Icon(Icons.folder_outlined,
                                    size: 14, color: FyrTheme.textColorMuted),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    p.basename(folder),
                                    style: TextStyle(
                                        fontSize: 11.5,
                                        color: FyrTheme.textColorMuted),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.close,
                                      size: 13, color: FyrTheme.textColorMuted),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: 20, minHeight: 20),
                                  onPressed: () =>
                                      ctrl.removeRomFolder(folder),
                                ),
                              ],
                            ),
                          )),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final dir = await FilePicker.getDirectoryPath(
                            dialogTitle: 'Select ROMs Folder',
                          );
                          if (dir != null) {
                            await ctrl.addRomFolder(dir);
                          }
                        },
                        icon: const Icon(Icons.create_new_folder_outlined,
                            size: 15),
                        label: const Text('Add ROM Folder',
                            style: TextStyle(fontSize: 11.5)),
                      ),
                      const SizedBox(height: 6),
                      TextButton.icon(
                        onPressed: ctrl.scanRomFolders,
                        icon: const Icon(Icons.refresh_rounded, size: 15),
                        label: const Text('Rescan Library',
                            style: TextStyle(fontSize: 11.5)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Main Grid Area
          Expanded(
            child: Container(
              color: FyrTheme.contentColor,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        ctrl.platformFilter?.label ??
                            switch (ctrl.libraryFilter) {
                              LibraryFilter.all => 'All Games',
                              LibraryFilter.favorites => 'Favorites',
                              LibraryFilter.recent => 'Recently Played',
                            },
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: FyrTheme.textColor,
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: 260,
                        height: 34,
                        child: TextField(
                          onChanged: (v) {
                            ctrl.searchQuery = v;
                            ctrl.refresh();
                          },
                          style: const TextStyle(fontSize: 12.5),
                          decoration: InputDecoration(
                            hintText: 'Search ROMs...',
                            prefixIcon: const Icon(Icons.search, size: 16),
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 8),
                            filled: true,
                            fillColor: FyrTheme.cardColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(9),
                              borderSide:
                                  BorderSide(color: FyrTheme.dividerColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(9),
                              borderSide:
                                  BorderSide(color: FyrTheme.dividerColor),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: games.isEmpty
                        ? _buildEmptyState(context, ctrl)
                        : GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 230,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 14,
                              childAspectRatio: 0.92,
                            ),
                            itemCount: games.length,
                            itemBuilder: (_, i) =>
                                _RomCard(rom: games[i], ctrl: ctrl),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, EmuController ctrl) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: FyrTheme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: FyrTheme.dividerColor),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sports_esports_rounded,
                size: 48, color: FyrTheme.accentColor),
            const SizedBox(height: 14),
            Text(
              'Ready to Play',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: FyrTheme.textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Drag & drop any .gb, .gbc, .gba, .nes, .sfc, .smc, or .zip ROM onto this window, or add your ROMs folder.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: FyrTheme.textColorMuted),
            ),
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: FyrTheme.accentColor,
                    foregroundColor:
                        FyrTheme.getContrastingColor(FyrTheme.accentColor),
                  ),
                  onPressed: () async {
                    final dir = await FilePicker.getDirectoryPath(
                        dialogTitle: 'Select ROMs Folder');
                    if (dir != null) await ctrl.addRomFolder(dir);
                  },
                  icon: const Icon(Icons.folder_open_rounded, size: 16),
                  label: const Text('Add ROM Folder'),
                ),
                OutlinedButton.icon(
                  onPressed: () => CoreManagerDialog.show(context),
                  icon: const Icon(Icons.memory_rounded, size: 16),
                  label: const Text('Check Cores'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: FyrTheme.textColorMuted,
        ),
      ),
    );
  }

  Widget _navTile({
    required IconData icon,
    Color? iconColor,
    required String label,
    required int count,
    Color? trailingDotColor,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? FyrTheme.accentColor.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: selected
                ? Border.all(color: FyrTheme.accentColor.withValues(alpha: 0.45))
                : null,
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 16,
                  color: iconColor ??
                      (selected ? FyrTheme.accentColor : FyrTheme.textColorMuted)),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected ? FyrTheme.textColor : FyrTheme.textColorMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailingDotColor != null)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: trailingDotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              if (count > 0)
                Text(
                  '$count',
                  style:
                      TextStyle(fontSize: 10.5, color: FyrTheme.textColorMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RomCard extends StatelessWidget {
  final RomEntry rom;
  final EmuController ctrl;

  const _RomCard({required this.rom, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final plat = rom.platform;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final ok = await ctrl.launchRomEntry(rom);
        if (!ok && context.mounted) {
          await CoreManagerDialog.show(context);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: FyrTheme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: FyrTheme.dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      plat.accent.withValues(alpha: 0.35),
                      plat.accent.withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: plat.accent.withValues(alpha: 0.3)),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.videogame_asset_rounded,
                              size: 38, color: plat.accent),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              plat.shortLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: plat.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IconButton(
                        icon: Icon(
                          rom.favorite
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 18,
                          color: rom.favorite
                              ? Colors.amberAccent
                              : FyrTheme.textColorMuted,
                        ),
                        onPressed: () => ctrl.toggleFavorite(rom),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rom.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: FyrTheme.textColor,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    plat.label,
                    style: TextStyle(
                        fontSize: 10.5, color: FyrTheme.textColorMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
