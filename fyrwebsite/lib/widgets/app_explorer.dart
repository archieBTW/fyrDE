import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../data/fyr_catalog.dart';
import '../theme/fyr_theme.dart';

class TabbedAppExplorer extends StatefulWidget {
  final FyrCategory selectedCategory;
  final ValueChanged<FyrCategory> onCategoryChanged;

  const TabbedAppExplorer({
    super.key,
    required this.selectedCategory,
    required this.onCategoryChanged,
  });

  @override
  State<TabbedAppExplorer> createState() => _TabbedAppExplorerState();
}

class _TabbedAppExplorerState extends State<TabbedAppExplorer> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 680;
    final isSearching = _query.trim().isNotEmpty;
    final activeCategory = widget.selectedCategory;

    final visibleApps = isSearching
        ? fyrAppsCatalog.where((app) => app.matchesQuery(_query)).toList()
        : appsForCategory(activeCategory);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 14 : 32,
        vertical: isMobile ? 12 : 24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1160),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Compact header + inline search
              if (isMobile) ...[
                _ExplorerHeader(
                  activeCategory: activeCategory,
                  isSearching: isSearching,
                  matchCount: visibleApps.length,
                  isMobile: true,
                ),
                const SizedBox(height: 12),
                _SearchBar(
                  controller: _searchController,
                  query: _query,
                  onChanged: (value) => setState(() => _query = value),
                  onClear: _clearSearch,
                ),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: _ExplorerHeader(
                        activeCategory: activeCategory,
                        isSearching: isSearching,
                        matchCount: visibleApps.length,
                        isMobile: false,
                      ),
                    ),
                    const SizedBox(width: 24),
                    SizedBox(
                      width: 320,
                      child: _SearchBar(
                        controller: _searchController,
                        query: _query,
                        onChanged: (value) => setState(() => _query = value),
                        onClear: _clearSearch,
                      ),
                    ),
                  ],
                ),

              SizedBox(height: isMobile ? 14 : 20),

              // Horizontally scrollable pill tab bar
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: FyrCategory.values.map((category) {
                    final selected = !isSearching && category == activeCategory;
                    final count = appsForCategory(category).length;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _CategoryTabPill(
                        category: category,
                        count: count,
                        selected: selected,
                        compact: isMobile,
                        onTap: () {
                          if (_query.isNotEmpty) {
                            _searchController.clear();
                            setState(() => _query = '');
                          }
                          widget.onCategoryChanged(category);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),

              SizedBox(height: isMobile ? 14 : 22),

              // Active tab panel
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                child: visibleApps.isEmpty
                    ? _EmptySearchState(
                        key: const ValueKey('empty'),
                        query: _query,
                        onReset: _clearSearch,
                      )
                    : isMobile
                        ? _MobileCompactAppList(
                            key: ValueKey(
                              isSearching ? 'search-$_query' : activeCategory.name,
                            ),
                            apps: visibleApps,
                            onSelectApp: (app) =>
                                showAppDetailModal(context, app),
                          )
                        : _DesktopAppGrid(
                            key: ValueKey(
                              isSearching ? 'search-$_query' : activeCategory.name,
                            ),
                            apps: visibleApps,
                            onSelectApp: (app) =>
                                showAppDetailModal(context, app),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExplorerHeader extends StatelessWidget {
  final FyrCategory activeCategory;
  final bool isSearching;
  final int matchCount;
  final bool isMobile;

  const _ExplorerHeader({
    required this.activeCategory,
    required this.isSearching,
    required this.matchCount,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                isSearching
                    ? 'SEARCHING ALL ${fyrAppsCatalog.length} APPS'
                    : 'SUITE EXPLORER · ${activeCategory.eyebrow.toUpperCase()}',
                overflow: TextOverflow.ellipsis,
                style: FyrFonts.mono(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.8,
                  color:
                      isSearching ? FyrColors.accentCyan : activeCategory.accent,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: FyrColors.borderSubtle),
              ),
              child: Text(
                '$matchCount',
                style: FyrFonts.mono(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          isSearching ? 'Search Results' : activeCategory.label,
          style: FyrFonts.display(
            fontSize: isMobile ? 26 : 36,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          isSearching
              ? 'Matching across Shell, System, Creative, Office, Dev, and CLI & Mobile.'
              : activeCategory.subtitle,
          style: FyrFonts.display(
            fontSize: isMobile ? 13 : 14.5,
            color: Colors.white60,
          ),
        ),
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchBar({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: FyrColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: query.isNotEmpty
              ? FyrColors.accentCyan.withValues(alpha: 0.6)
              : FyrColors.borderSubtle,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(
            Icons.search_rounded,
            size: 18,
            color: query.isNotEmpty ? FyrColors.accentCyan : Colors.white38,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const Key('app-explorer-search'),
              controller: controller,
              onChanged: onChanged,
              style: FyrFonts.mono(fontSize: 12.5, color: Colors.white),
              cursorColor: FyrColors.accentCyan,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Filter 44 apps (e.g. pdf, daw, aur)...',
                hintStyle: FyrFonts.mono(fontSize: 12, color: Colors.white38),
              ),
            ),
          ),
          if (query.isNotEmpty)
            IconButton(
              iconSize: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded, color: Colors.white60),
            ),
        ],
      ),
    );
  }
}

class _CategoryTabPill extends StatefulWidget {
  final FyrCategory category;
  final int count;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  const _CategoryTabPill({
    required this.category,
    required this.count,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  @override
  State<_CategoryTabPill> createState() => _CategoryTabPillState();
}

class _CategoryTabPillState extends State<_CategoryTabPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.category.accent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        key: Key('category-tab-${widget.category.name}'),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 11 : 14,
            vertical: widget.compact ? 8 : 9,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: widget.selected
                ? accent.withValues(alpha: 0.18)
                : _hovered
                    ? Colors.white.withValues(alpha: 0.07)
                    : FyrColors.surface.withValues(alpha: 0.85),
            border: Border.all(
              color: widget.selected
                  ? accent.withValues(alpha: 0.72)
                  : _hovered
                      ? Colors.white.withValues(alpha: 0.24)
                      : FyrColors.borderSubtle,
            ),
            boxShadow: widget.selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.2),
                      blurRadius: 18,
                      spreadRadius: -4,
                    ),
                  ]
                : const [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.category.icon,
                size: 15,
                color: widget.selected ? accent : Colors.white54,
              ),
              const SizedBox(width: 7),
              Text(
                widget.category.label,
                style: FyrFonts.mono(
                  fontSize: widget.compact ? 11.5 : 12.5,
                  fontWeight:
                      widget.selected ? FontWeight.w700 : FontWeight.w500,
                  color: widget.selected ? Colors.white : Colors.white70,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: widget.selected
                      ? accent.withValues(alpha: 0.25)
                      : Colors.white.withValues(alpha: 0.06),
                ),
                child: Text(
                  '${widget.count}',
                  style: FyrFonts.mono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: widget.selected ? Colors.white : Colors.white54,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopAppGrid extends StatelessWidget {
  final List<FyrAppItem> apps;
  final ValueChanged<FyrAppItem> onSelectApp;

  const _DesktopAppGrid({
    super.key,
    required this.apps,
    required this.onSelectApp,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final cols = maxW >= 1020 ? 3 : 2;
        const spacing = 18.0;
        final cardWidth = (maxW - spacing * (cols - 1)) / cols;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: apps.map((app) {
            return SizedBox(
              width: cardWidth,
              child: _DesktopAppCard(
                app: app,
                onTap: () => onSelectApp(app),
              ),
            );
          }).toList(),
        );
      },
    ).animate().fadeIn(duration: 240.ms);
  }
}

class _DesktopAppCard extends StatefulWidget {
  final FyrAppItem app;
  final VoidCallback onTap;

  const _DesktopAppCard({required this.app, required this.onTap});

  @override
  State<_DesktopAppCard> createState() => _DesktopAppCardState();
}

class _DesktopAppCardState extends State<_DesktopAppCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final accent = app.category.accent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        key: Key('app-card-${app.id}'),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, _hovered ? -4 : 0, 0),
          decoration: BoxDecoration(
            color: _hovered ? FyrColors.surfaceElevated : FyrColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _hovered
                  ? accent.withValues(alpha: 0.65)
                  : FyrColors.borderSubtle,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.18),
                      blurRadius: 28,
                      spreadRadius: -8,
                      offset: const Offset(0, 12),
                    ),
                  ]
                : const [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(17),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9.2,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (app.screenshotAsset != null)
                        AnimatedScale(
                          scale: _hovered ? 1.03 : 1.0,
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          child: Image.asset(
                            app.screenshotAsset!,
                            fit: BoxFit.cover,
                            cacheWidth: 640,
                            filterQuality: FilterQuality.medium,
                            gaplessPlayback: true,
                            errorBuilder: (context, error, stackTrace) =>
                                _SyntheticPreviewBanner(app: app),
                          ),
                        )
                      else
                        _SyntheticPreviewBanner(app: app),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 44,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                (_hovered
                                        ? FyrColors.surfaceElevated
                                        : FyrColors.surface)
                                    .withValues(alpha: 0.94),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Top-left badge & optional NEW pill
                      Positioned(
                        top: 10,
                        left: 10,
                        right: 10,
                        child: Row(
                          children: [
                            _GlassMicroPill(
                              label: app.badge,
                              accent: accent,
                            ),
                            if (app.isNew) ...[
                              const SizedBox(width: 6),
                              const _NewPill(),
                            ],
                            const Spacer(),
                            if (app.shortcut != null)
                              _GlassMicroPill(
                                label: app.shortcut!,
                                accent: Colors.white70,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: accent.withValues(alpha: 0.14),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Icon(app.icon, size: 15, color: accent),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    app.name,
                                    style: FyrFonts.mono(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (app.alias != null) ...[
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      '(${app.alias})',
                                      style: FyrFonts.mono(
                                        fontSize: 11,
                                        color: Colors.white38,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          AnimatedOpacity(
                            opacity: _hovered ? 1.0 : 0.4,
                            duration: const Duration(milliseconds: 160),
                            child: Icon(
                              Icons.north_east_rounded,
                              size: 16,
                              color: accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        app.description,
                        style: FyrFonts.display(
                          fontSize: 12.8,
                          color: Colors.white60,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
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

class _MobileCompactAppList extends StatelessWidget {
  final List<FyrAppItem> apps;
  final ValueChanged<FyrAppItem> onSelectApp;

  const _MobileCompactAppList({
    super.key,
    required this.apps,
    required this.onSelectApp,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: apps.map((app) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _MobileCompactAppCard(
            app: app,
            onTap: () => onSelectApp(app),
          ),
        );
      }).toList(),
    ).animate().fadeIn(duration: 200.ms);
  }
}

class _MobileCompactAppCard extends StatelessWidget {
  final FyrAppItem app;
  final VoidCallback onTap;

  const _MobileCompactAppCard({required this.app, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = app.category.accent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('app-card-${app.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: FyrColors.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: FyrColors.borderSubtle),
          ),
          child: Row(
            children: [
              // Compact glowing icon badge
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent.withValues(alpha: 0.24),
                      accent.withValues(alpha: 0.08),
                    ],
                  ),
                  border: Border.all(color: accent.withValues(alpha: 0.42)),
                ),
                child: Icon(app.icon, size: 19, color: accent),
              ),
              const SizedBox(width: 11),
              // Title + badge + concise 2-line description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            app.name,
                            style: FyrFonts.mono(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: accent.withValues(alpha: 0.14),
                          ),
                          child: Text(
                            app.badge,
                            style: FyrFonts.mono(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: accent,
                            ),
                          ),
                        ),
                        if (app.isNew) ...[
                          const SizedBox(width: 5),
                          const _NewPill(compact: true),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      app.description,
                      style: FyrFonts.display(
                        fontSize: 12,
                        color: Colors.white60,
                        height: 1.32,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Optional compact screenshot thumbnail on right
              if (app.screenshotAsset != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 64,
                    height: 44,
                    decoration: BoxDecoration(
                      border: Border.all(color: FyrColors.borderSubtle),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Image.asset(
                      app.screenshotAsset!,
                      fit: BoxFit.cover,
                      cacheWidth: 200,
                      filterQuality: FilterQuality.low,
                      gaplessPlayback: true,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: FyrColors.surfaceElevated,
                        child: Icon(app.icon, size: 16, color: accent),
                      ),
                    ),
                  ),
                )
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: Colors.white38,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyntheticPreviewBanner extends StatelessWidget {
  final FyrAppItem app;

  const _SyntheticPreviewBanner({required this.app});

  @override
  Widget build(BuildContext context) {
    final accent = app.category.accent;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.2),
            const Color(0xFF0B0B14),
            FyrColors.accentVibrant.withValues(alpha: 0.14),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            bottom: -18,
            child: Icon(
              app.icon,
              size: 112,
              color: accent.withValues(alpha: 0.08),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    color: FyrColors.surface.withValues(alpha: 0.88),
                    border: Border.all(color: accent.withValues(alpha: 0.5)),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.28),
                        blurRadius: 24,
                      ),
                    ],
                  ),
                  child: Icon(app.icon, size: 26, color: accent),
                ),
                const SizedBox(height: 8),
                Text(
                  app.category.eyebrow.toUpperCase(),
                  style: FyrFonts.mono(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: accent.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassMicroPill extends StatelessWidget {
  final String label;
  final Color accent;

  const _GlassMicroPill({required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: FyrFonts.mono(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: accent,
        ),
      ),
    );
  }
}

class _NewPill extends StatelessWidget {
  final bool compact;
  const _NewPill({this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 7,
        vertical: compact ? 1.5 : 3,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: const LinearGradient(
          colors: [FyrColors.accentVibrant, FyrColors.accentCyan],
        ),
      ),
      child: Text(
        'NEW',
        style: FyrFonts.mono(
          fontSize: compact ? 8.5 : 9.5,
          fontWeight: FontWeight.w800,
          color: Colors.black,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _EmptySearchState extends StatelessWidget {
  final String query;
  final VoidCallback onReset;

  const _EmptySearchState({
    super.key,
    required this.query,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 34),
      decoration: BoxDecoration(
        color: FyrColors.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: FyrColors.borderSubtle),
      ),
      child: Column(
        children: [
          const Icon(Icons.search_off_rounded, size: 32, color: Colors.white38),
          const SizedBox(height: 10),
          Text(
            'No apps match "$query"',
            style: FyrFonts.mono(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 12),
          GhostPillButton(
            label: 'Clear search',
            compact: true,
            onPressed: onReset,
          ),
        ],
      ),
    );
  }
}

void showAppDetailModal(BuildContext context, FyrAppItem app) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.86),
    builder: (dialogContext) => _AppDetailDialog(app: app),
  );
}

class _AppDetailDialog extends StatefulWidget {
  final FyrAppItem app;
  const _AppDetailDialog({required this.app});

  @override
  State<_AppDetailDialog> createState() => _AppDetailDialogState();
}

class _AppDetailDialogState extends State<_AppDetailDialog> {
  int _shotIndex = 0;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final accent = app.category.accent;
    final shots = app.allScreenshotAssets;
    final isMobile = MediaQuery.of(context).size.width < 680;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.all(isMobile ? 14 : 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Container(
          decoration: BoxDecoration(
            color: FyrColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withValues(alpha: 0.45)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.2),
                blurRadius: 48,
                spreadRadius: -12,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(19),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header bar
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0A0A12),
                      border: Border(
                        bottom: BorderSide(color: FyrColors.borderSubtle),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: accent.withValues(alpha: 0.16),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Icon(app.icon, size: 18, color: accent),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    app.name,
                                    style: FyrFonts.mono(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                  if (app.alias != null)
                                    Text(
                                      app.alias!,
                                      style: FyrFonts.mono(
                                        fontSize: 12,
                                        color: Colors.white54,
                                      ),
                                    ),
                                  _GlassMicroPill(
                                    label: app.badge,
                                    accent: accent,
                                  ),
                                  if (app.shortcut != null)
                                    _GlassMicroPill(
                                      label: app.shortcut!,
                                      accent: FyrColors.accentCyan,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Screenshot area if available
                  if (shots.isNotEmpty)
                    Container(
                      color: Colors.black,
                      child: Column(
                        children: [
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: isMobile ? 260 : 460,
                            ),
                            child: Image.asset(
                              shots[_shotIndex],
                              fit: BoxFit.contain,
                              width: double.infinity,
                              errorBuilder: (context, error, stackTrace) =>
                                  SizedBox(
                                height: 180,
                                child: _SyntheticPreviewBanner(app: app),
                              ),
                            ),
                          ),
                          if (shots.length > 1)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(shots.length, (i) {
                                  final selected = i == _shotIndex;
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    child: GestureDetector(
                                      onTap: () =>
                                          setState(() => _shotIndex = i),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          color: selected
                                              ? accent.withValues(alpha: 0.25)
                                              : Colors.white
                                                  .withValues(alpha: 0.08),
                                          border: Border.all(
                                            color: selected
                                                ? accent
                                                : FyrColors.borderSubtle,
                                          ),
                                        ),
                                        child: Text(
                                          'View ${i + 1}',
                                          style: FyrFonts.mono(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: selected
                                                ? Colors.white
                                                : Colors.white60,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ),
                        ],
                      ),
                    ),

                  // Details & feature highlights
                  Padding(
                    padding: EdgeInsets.all(isMobile ? 16 : 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.description,
                          style: FyrFonts.display(
                            fontSize: isMobile ? 14 : 15.5,
                            color: Colors.white.withValues(alpha: 0.88),
                            height: 1.5,
                          ),
                        ),
                        if (app.highlights.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          ...app.highlights.map(
                            (point) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 5),
                                    child: Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: accent,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      point,
                                      style: FyrFonts.mono(
                                        fontSize: 12.2,
                                        color: Colors.white70,
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void showImageLightbox(
  BuildContext context, {
  required String title,
  required String subtitle,
  required List<String> assetPaths,
}) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.88),
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(dialogContext),
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: FyrColors.accent.withValues(alpha: 0.4),
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Image.asset(
                          assetPaths.first,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: FyrColors.surface.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: FyrColors.borderSubtle),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          title,
                          style: FyrFonts.mono(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '· $subtitle',
                          style: FyrFonts.mono(
                            fontSize: 12,
                            color: Colors.white60,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              style: IconButton.styleFrom(
                backgroundColor: FyrColors.surface.withValues(alpha: 0.9),
              ),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(dialogContext),
            ),
          ),
        ],
      ),
    ),
  );
}
