import 'package:flutter/material.dart';
import 'browser_models.dart';
import 'fyr_theme.dart';

class _StarterShortcut {
  final String title;
  final String url;
  final IconData icon;

  const _StarterShortcut(this.title, this.url, this.icon);
}

const List<_StarterShortcut> _defaultShortcuts = [
  _StarterShortcut('DuckDuckGo', 'https://duckduckgo.com', Icons.search),
  _StarterShortcut('Wikipedia', 'https://www.wikipedia.org', Icons.menu_book),
  _StarterShortcut('GitHub', 'https://github.com', Icons.code),
  _StarterShortcut('ArchWiki', 'https://wiki.archlinux.org', Icons.terminal),
];

/// Instant local start page (`fyr://home`) so startup never blocks on network.
class FyrHomePage extends StatefulWidget {
  final SearchEngine searchEngine;
  final bool adBlockEnabled;
  final List<Map<String, String>> bookmarks;
  final List<Map<String, String>> history;
  final ValueChanged<String> onNavigate;
  final VoidCallback onOpenSettings;

  const FyrHomePage({
    super.key,
    required this.searchEngine,
    required this.adBlockEnabled,
    required this.bookmarks,
    required this.history,
    required this.onNavigate,
    required this.onOpenSettings,
  });

  @override
  State<FyrHomePage> createState() => _FyrHomePageState();
}

class _FyrHomePageState extends State<FyrHomePage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recentItems = _uniqueRecentHistory(widget.history, limit: 6);
    return Container(
      color: FyrTheme.bgColor,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 28),
                _buildSearchBar(),
                const SizedBox(height: 32),
                _buildShortcutsSection(),
                if (recentItems.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _buildRecentSection(recentItems),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: FyrTheme.accentColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: FyrTheme.accentColor.withValues(alpha: 0.4),
                ),
              ),
              child: Icon(
                Icons.public,
                color: FyrTheme.accentColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FyrBrowser',
                  style: TextStyle(
                    color: FyrTheme.textColor,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'Searching with ${widget.searchEngine.label}',
                  style: TextStyle(
                    color: FyrTheme.textColor.withValues(alpha: 0.55),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: (widget.adBlockEnabled ? Colors.green : Colors.grey)
                    .withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.adBlockEnabled
                        ? Icons.shield
                        : Icons.shield_outlined,
                    size: 14,
                    color: widget.adBlockEnabled
                        ? Colors.greenAccent
                        : FyrTheme.textColor.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.adBlockEnabled ? 'Shield On' : 'Shield Off',
                    style: TextStyle(
                      color: FyrTheme.textColor.withValues(alpha: 0.85),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: widget.onOpenSettings,
              tooltip: 'Settings & History',
              icon: Icon(
                Icons.tune,
                color: FyrTheme.textColor.withValues(alpha: 0.75),
                size: 20,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: FyrTheme.textColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: FyrTheme.dividerColor.withValues(alpha: 0.35),
        ),
      ),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: FyrTheme.textColor, fontSize: 15),
        decoration: InputDecoration(
          hintText:
              'Search with ${widget.searchEngine.label} or enter a web address...',
          hintStyle: TextStyle(
            color: FyrTheme.textColor.withValues(alpha: 0.45),
            fontSize: 14,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: FyrTheme.accentColor,
            size: 20,
          ),
          suffixIcon: IconButton(
            icon: Icon(
              Icons.arrow_forward,
              color: FyrTheme.textColor.withValues(alpha: 0.65),
              size: 18,
            ),
            onPressed: () {
              final q = _searchController.text.trim();
              if (q.isNotEmpty) widget.onNavigate(q);
            },
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        onSubmitted: (value) {
          if (value.trim().isNotEmpty) {
            widget.onNavigate(value);
          }
        },
      ),
    );
  }

  Widget _buildShortcutsSection() {
    final hasBookmarks = widget.bookmarks.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hasBookmarks ? 'Bookmarks' : 'Quick Links',
          style: TextStyle(
            color: FyrTheme.textColor.withValues(alpha: 0.65),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: hasBookmarks
              ? widget.bookmarks.take(8).map((b) {
                  final title = (b['title'] ?? '').trim();
                  final url = b['url'] ?? '';
                  return _buildTile(
                    title.isNotEmpty ? title : url,
                    url,
                    Icons.bookmark_outline,
                  );
                }).toList()
              : _defaultShortcuts
                  .map((s) => _buildTile(s.title, s.url, s.icon))
                  .toList(),
        ),
      ],
    );
  }

  Widget _buildTile(String title, String url, IconData icon) {
    return InkWell(
      onTap: () => widget.onNavigate(url),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 160,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: FyrTheme.textColor.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: FyrTheme.dividerColor.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: FyrTheme.accentColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: FyrTheme.textColor.withValues(alpha: 0.9),
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentSection(List<Map<String, String>> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Visits',
          style: TextStyle(
            color: FyrTheme.textColor.withValues(alpha: 0.65),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: FyrTheme.textColor.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: FyrTheme.dividerColor.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            children: items.map((entry) {
              final url = entry['url'] ?? '';
              final title = (entry['title'] ?? '').trim();
              return InkWell(
                onTap: () => widget.onNavigate(url),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.history,
                        size: 15,
                        color: FyrTheme.textColor.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title.isNotEmpty ? title : url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: FyrTheme.textColor.withValues(alpha: 0.88),
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: FyrTheme.textColor.withValues(alpha: 0.4),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  List<Map<String, String>> _uniqueRecentHistory(
    List<Map<String, String>> raw, {
    required int limit,
  }) {
    final seen = <String>{};
    final out = <Map<String, String>>[];
    for (final item in raw) {
      final url = item['url'] ?? '';
      if (url.isEmpty || isInternalUrl(url) || seen.contains(url)) continue;
      seen.add(url);
      out.add(item);
      if (out.length >= limit) break;
    }
    return out;
  }
}

/// Native Flutter error screen shown when CEF emits `onLoadError`.
class FyrErrorPage extends StatelessWidget {
  final LoadErrorInfo error;
  final VoidCallback onRetry;
  final VoidCallback onGoHome;

  const FyrErrorPage({
    super.key,
    required this.error,
    required this.onRetry,
    required this.onGoHome,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FyrTheme.bgColor,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.cloud_off,
                  size: 44,
                  color: FyrTheme.accentColor,
                ),
                const SizedBox(height: 16),
                Text(
                  error.friendlyTitle,
                  style: TextStyle(
                    color: FyrTheme.textColor,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Failed to load ${error.failedUrl}',
                  style: TextStyle(
                    color: FyrTheme.textColor.withValues(alpha: 0.72),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${error.errorText} (error ${error.errorCode})',
                  style: TextStyle(
                    color: FyrTheme.textColor.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Try Again'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: onGoHome,
                      icon: const Icon(Icons.home_outlined, size: 16),
                      label: const Text('Go Home'),
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
