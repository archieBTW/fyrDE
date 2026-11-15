import 'package:flutter/material.dart';
import 'adblock_engine.dart';
import 'browser_models.dart';
import 'fyr_theme.dart';

/// Modal dialog for Browser Settings, History, and Bookmarks.
class SettingsDialog extends StatefulWidget {
  final BrowserSettings settings;
  final List<Map<String, String>> history;
  final List<Map<String, String>> bookmarks;
  final ValueChanged<BrowserSettings> onSettingsChanged;
  final ValueChanged<String> onNavigate;
  final ValueChanged<String> onRemoveBookmark;
  final VoidCallback onClearHistory;
  final int initialTab;

  const SettingsDialog({
    super.key,
    required this.settings,
    required this.history,
    required this.bookmarks,
    required this.onSettingsChanged,
    required this.onNavigate,
    required this.onRemoveBookmark,
    required this.onClearHistory,
    this.initialTab = 0,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late int _tabIndex;
  late SearchEngine _engine;
  late bool _adBlockEnabled;
  late List<String> _whitelist;
  late TextEditingController _homeController;
  final TextEditingController _whitelistController = TextEditingController();
  final TextEditingController _filterController = TextEditingController();
  String _filterQuery = '';

  @override
  void initState() {
    super.initState();
    _tabIndex = widget.initialTab;
    _engine = widget.settings.searchEngine;
    _adBlockEnabled = widget.settings.adBlockEnabled;
    _whitelist = List<String>.from(widget.settings.adBlockWhitelist);
    _homeController = TextEditingController(text: widget.settings.homePage);
  }

  @override
  void dispose() {
    _homeController.dispose();
    _whitelistController.dispose();
    _filterController.dispose();
    super.dispose();
  }

  void _emitSettings() {
    final trimmedHome = _homeController.text.trim();
    widget.onSettingsChanged(
      BrowserSettings(
        searchEngine: _engine,
        homePage: trimmedHome.isEmpty ? kDefaultHomePage : trimmedHome,
        adBlockEnabled: _adBlockEnabled,
        adBlockWhitelist: List<String>.from(_whitelist),
      ),
    );
  }

  void _addWhitelistEntry() {
    final host = AdBlockEngine.extractHost(_whitelistController.text);
    if (host.isEmpty) return;
    if (!_whitelist.contains(host)) {
      setState(() {
        _whitelist.add(host);
        _whitelistController.clear();
      });
      _emitSettings();
    } else {
      _whitelistController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: FyrTheme.bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: FyrTheme.dividerColor.withValues(alpha: 0.35)),
      ),
      child: SizedBox(
        width: 620,
        height: 520,
        child: Column(
          children: [
            _buildTopTabs(),
            Divider(height: 1, color: FyrTheme.dividerColor.withValues(alpha: 0.25)),
            Expanded(
              child: IndexedStack(
                index: _tabIndex,
                children: [
                  _buildGeneralSettingsTab(),
                  _buildHistoryTab(),
                  _buildBookmarksTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _tabChip(0, 'Settings', Icons.tune),
          const SizedBox(width: 8),
          _tabChip(1, 'History', Icons.history),
          const SizedBox(width: 8),
          _tabChip(2, 'Bookmarks', Icons.bookmarks_outlined),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close, color: FyrTheme.textColor, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _tabChip(int index, String label, IconData icon) {
    final selected = _tabIndex == index;
    return InkWell(
      onTap: () => setState(() {
        _tabIndex = index;
        _filterQuery = '';
        _filterController.clear();
      }),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? FyrTheme.accentColor.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: selected
                  ? FyrTheme.accentColor
                  : FyrTheme.textColor.withValues(alpha: 0.65),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? FyrTheme.textColor
                    : FyrTheme.textColor.withValues(alpha: 0.65),
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneralSettingsTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Search Engine',
          style: TextStyle(
            color: FyrTheme.textColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<SearchEngine>(
          initialValue: _engine,
          dropdownColor: FyrTheme.bgColor,
          style: TextStyle(color: FyrTheme.textColor, fontSize: 13),
          decoration: _inputDecoration(),
          items: SearchEngine.values
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Text(e.label),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() => _engine = value);
            _emitSettings();
          },
        ),
        const SizedBox(height: 20),
        Text(
          'Home Page',
          style: TextStyle(
            color: FyrTheme.textColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _homeController,
                style: TextStyle(color: FyrTheme.textColor, fontSize: 13),
                decoration: _inputDecoration(hint: kDefaultHomePage),
                onSubmitted: (_) => _emitSettings(),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                _homeController.text = kDefaultHomePage;
                _emitSettings();
              },
              child: const Text('Use Default'),
            ),
            TextButton(
              onPressed: _emitSettings,
              child: const Text('Save'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            'AdBlock Shield',
            style: TextStyle(
              color: FyrTheme.textColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            'Blocks known third-party ad & tracker requests in Chromium without breaking page scripts.',
            style: TextStyle(
              color: FyrTheme.textColor.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
          value: _adBlockEnabled,
          onChanged: (value) {
            setState(() => _adBlockEnabled = value);
            _emitSettings();
          },
        ),
        const SizedBox(height: 12),
        Text(
          'Allowlisted Sites (AdBlock paused on these domains)',
          style: TextStyle(
            color: FyrTheme.textColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _whitelistController,
                style: TextStyle(color: FyrTheme.textColor, fontSize: 13),
                decoration: _inputDecoration(hint: 'example.com'),
                onSubmitted: (_) => _addWhitelistEntry(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _addWhitelistEntry,
              child: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_whitelist.isEmpty)
          Text(
            'No sites allowlisted.',
            style: TextStyle(
              color: FyrTheme.textColor.withValues(alpha: 0.45),
              fontSize: 12,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _whitelist
                .map(
                  (host) => Chip(
                    label: Text(
                      host,
                      style: TextStyle(color: FyrTheme.textColor, fontSize: 12),
                    ),
                    onDeleted: () {
                      setState(() => _whitelist.remove(host));
                      _emitSettings();
                    },
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  Widget _buildHistoryTab() {
    final filtered = widget.history.where((item) {
      if (_filterQuery.isEmpty) return true;
      final q = _filterQuery.toLowerCase();
      return (item['title'] ?? '').toLowerCase().contains(q) ||
          (item['url'] ?? '').toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _filterController,
                  style: TextStyle(color: FyrTheme.textColor, fontSize: 13),
                  decoration: _inputDecoration(hint: 'Search history...'),
                  onChanged: (v) => setState(() => _filterQuery = v.trim()),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: widget.history.isEmpty
                    ? null
                    : () {
                        widget.onClearHistory();
                        setState(() {});
                      },
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Clear'),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'No history entries found.',
                    style: TextStyle(
                      color: FyrTheme.textColor.withValues(alpha: 0.5),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    final url = item['url'] ?? '';
                    final title = (item['title'] ?? '').trim();
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.public,
                        size: 16,
                        color: FyrTheme.textColor.withValues(alpha: 0.55),
                      ),
                      title: Text(
                        title.isNotEmpty ? title : url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: FyrTheme.textColor, fontSize: 13),
                      ),
                      subtitle: Text(
                        url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: FyrTheme.textColor.withValues(alpha: 0.5),
                          fontSize: 11,
                        ),
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.onNavigate(url);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildBookmarksTab() {
    final filtered = widget.bookmarks.where((item) {
      if (_filterQuery.isEmpty) return true;
      final q = _filterQuery.toLowerCase();
      return (item['title'] ?? '').toLowerCase().contains(q) ||
          (item['url'] ?? '').toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _filterController,
            style: TextStyle(color: FyrTheme.textColor, fontSize: 13),
            decoration: _inputDecoration(hint: 'Filter bookmarks...'),
            onChanged: (v) => setState(() => _filterQuery = v.trim()),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'No bookmarks saved yet.',
                    style: TextStyle(
                      color: FyrTheme.textColor.withValues(alpha: 0.5),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    final url = item['url'] ?? '';
                    final title = (item['title'] ?? '').trim();
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.bookmark,
                        size: 16,
                        color: FyrTheme.accentColor,
                      ),
                      title: Text(
                        title.isNotEmpty ? title : url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: FyrTheme.textColor, fontSize: 13),
                      ),
                      subtitle: Text(
                        url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: FyrTheme.textColor.withValues(alpha: 0.5),
                          fontSize: 11,
                        ),
                      ),
                      trailing: IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: FyrTheme.textColor.withValues(alpha: 0.55),
                        ),
                        onPressed: () {
                          widget.onRemoveBookmark(url);
                          setState(() {});
                        },
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.onNavigate(url);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: FyrTheme.textColor.withValues(alpha: 0.4),
        fontSize: 13,
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: FyrTheme.dividerColor.withValues(alpha: 0.35),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: FyrTheme.dividerColor.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}
