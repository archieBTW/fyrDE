import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/db_models.dart';
import '../state/db_controller.dart';
import 'connection_wizard.dart';

class DbNavigator extends StatefulWidget {
  const DbNavigator({super.key});

  @override
  State<DbNavigator> createState() => _DbNavigatorState();
}

class _DbNavigatorState extends State<DbNavigator> {
  bool _tablesExpanded = true;
  bool _viewsExpanded = true;
  bool _indexesExpanded = true;
  bool _triggersExpanded = false;
  final Set<String> _expandedTableColumns = {};

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DbController>();
    final accent = FyrTheme.accentColor;
    final activeConn = ctrl.activeConnection;
    final query = ctrl.navigatorSearchQuery.toLowerCase();

    final tables = ctrl.activeTables
        .where((t) => query.isEmpty || t.name.toLowerCase().contains(query))
        .toList();
    final views = ctrl.activeViews
        .where((v) => query.isEmpty || v.name.toLowerCase().contains(query))
        .toList();
    final indexes = ctrl.activeIndexes
        .where((i) => query.isEmpty || i.name.toLowerCase().contains(query))
        .toList();
    final triggers = ctrl.activeTriggers
        .where((t) => query.isEmpty || t.name.toLowerCase().contains(query))
        .toList();

    return Container(
      width: 270,
      decoration: BoxDecoration(
        color: FyrTheme.sidebarColor,
        border: Border(right: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Row(
              children: [
                Icon(Icons.account_tree_rounded, size: 14, color: accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'DATABASE NAVIGATOR',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: FyrTheme.textColorMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${ctrl.connections.length}',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: FyrTheme.textColorMuted,
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(5),
                  onTap: () => ConnectionWizard.showModal(context),
                  child: Tooltip(
                    message: 'New Connection Wizard',
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Icon(
                        Icons.add_rounded,
                        size: 15,
                        color: accent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Filter input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: SizedBox(
              height: 28,
              child: TextField(
                onChanged: ctrl.setNavigatorSearch,
                style: TextStyle(fontSize: 11.5, color: FyrTheme.textColor),
                decoration: InputDecoration(
                  hintText: 'Filter tables, views, columns...',
                  hintStyle: TextStyle(
                    fontSize: 11,
                    color: FyrTheme.textColorMuted.withValues(alpha: 0.6),
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 14,
                    color: FyrTheme.textColorMuted,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  filled: true,
                  fillColor: FyrTheme.surfaceColor,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: FyrTheme.dividerColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: accent),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ctrl.connections.isEmpty
                ? _buildEmptyNavigatorState(context, accent)
                : ListView(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    children: [
                      for (final conn in ctrl.connections) ...[
                        _buildConnectionHeader(ctrl, conn, accent),
                        if (conn.id == ctrl.activeConnectionId) ...[
                          const SizedBox(height: 4),
                          if (ctrl.activeSchemas.isEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(18, 6, 12, 10),
                              child: Text(
                                conn.driver == DbDriverType.redis
                                    ? 'Key-value store active — run Redis commands in the editor.'
                                    : 'No tables found yet. Create a table in the SQL Editor or refresh schema.',
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.35,
                                  color: FyrTheme.textColorMuted,
                                ),
                              ),
                            )
                          else ...[
                            // Tables section
                            _buildSectionFolder(
                              label: 'Tables (${tables.length})',
                              icon: Icons.table_chart_rounded,
                              iconColor: const Color(0xFFA78BFA),
                              expanded: _tablesExpanded,
                              onTap: () => setState(
                                () => _tablesExpanded = !_tablesExpanded,
                              ),
                            ),
                            if (_tablesExpanded)
                              for (final tbl in tables)
                                _buildTableItem(ctrl, tbl, accent),
                            // Views section
                            _buildSectionFolder(
                              label: 'Views (${views.length})',
                              icon: Icons.visibility_rounded,
                              iconColor: const Color(0xFF38BDF8),
                              expanded: _viewsExpanded,
                              onTap: () => setState(
                                () => _viewsExpanded = !_viewsExpanded,
                              ),
                            ),
                            if (_viewsExpanded)
                              for (final vw in views)
                                _buildTableItem(ctrl, vw, accent),
                            // Indexes section
                            _buildSectionFolder(
                              label: 'Indexes (${indexes.length})',
                              icon: Icons.flash_on_rounded,
                              iconColor: const Color(0xFFFBBF24),
                              expanded: _indexesExpanded,
                              onTap: () => setState(
                                () => _indexesExpanded = !_indexesExpanded,
                              ),
                            ),
                            if (_indexesExpanded)
                              for (final idx in indexes)
                                _buildSubItem(
                                  icon: Icons.vpn_key_outlined,
                                  color: const Color(0xFFFBBF24),
                                  title: idx.name,
                                  badge: idx.tableName,
                                  onTap: () => ctrl.selectTable(
                                    idx.tableName,
                                    switchToMode: DbWorkspaceMode.structureDdl,
                                  ),
                                ),
                            // Triggers section
                            _buildSectionFolder(
                              label: 'Triggers (${triggers.length})',
                              icon: Icons.bolt_rounded,
                              iconColor: const Color(0xFFF472B6),
                              expanded: _triggersExpanded,
                              onTap: () => setState(
                                () => _triggersExpanded = !_triggersExpanded,
                              ),
                            ),
                            if (_triggersExpanded)
                              for (final trg in triggers)
                                _buildSubItem(
                                  icon: Icons.settings_backup_restore_rounded,
                                  color: const Color(0xFFF472B6),
                                  title: trg.name,
                                  badge: '${trg.timing} ${trg.event}',
                                  onTap: () => ctrl.selectTable(
                                    trg.tableName,
                                    switchToMode: DbWorkspaceMode.structureDdl,
                                  ),
                                ),
                          ],
                          const SizedBox(height: 6),
                        ],
                      ],
                    ],
                  ),
          ),
          // Footer summary bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: FyrTheme.surfaceColor,
              border: Border(top: BorderSide(color: FyrTheme.dividerColor)),
            ),
            child: Row(
              children: [
                Icon(
                  activeConn != null
                      ? Icons.verified_user_rounded
                      : Icons.link_off_rounded,
                  size: 13,
                  color: activeConn != null
                      ? const Color(0xFF4ADE80)
                      : FyrTheme.textColorMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    activeConn != null
                        ? activeConn.endpointSummary
                        : 'No active connection',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: FyrTheme.textColorMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyNavigatorState(BuildContext context, Color accent) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.storage_rounded,
              size: 28,
              color: FyrTheme.textColorMuted.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 10),
            Text(
              'No Saved Connections',
              style: GoogleFonts.outfit(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: FyrTheme.textColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Use the Connection Setup Wizard to open a local SQLite/DuckDB file or connect to a remote database server.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.35,
                color: FyrTheme.textColorMuted,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: accent.withValues(alpha: 0.5)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
              onPressed: () => ConnectionWizard.showModal(context),
              icon: Icon(Icons.add_link_rounded, size: 14, color: accent),
              label: Text(
                'Add Connection',
                style: TextStyle(fontSize: 11.5, color: FyrTheme.textColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionHeader(
    DbController ctrl,
    DbConnectionProfile conn,
    Color accent,
  ) {
    final isActive = conn.id == ctrl.activeConnectionId;
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: () => ctrl.selectConnection(conn.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
        decoration: BoxDecoration(
          color: isActive
              ? accent.withValues(alpha: 0.14)
              : FyrTheme.cardColor,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: isActive
                ? accent.withValues(alpha: 0.45)
                : FyrTheme.dividerColor,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isActive
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.keyboard_arrow_right_rounded,
              size: 15,
              color: FyrTheme.textColorMuted,
            ),
            const SizedBox(width: 4),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: conn.isConnected
                    ? const Color(0xFF22C55E)
                    : Colors.grey,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                conn.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: FyrTheme.textColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: conn.driver.badgeColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                conn.driver.shortTag,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: conn.driver.badgeColor,
                ),
              ),
            ),
            const SizedBox(width: 2),
            PopupMenuButton<String>(
              tooltip: 'Connection Actions',
              padding: EdgeInsets.zero,
              iconSize: 15,
              icon: Icon(
                Icons.more_vert_rounded,
                size: 14,
                color: FyrTheme.textColorMuted,
              ),
              onSelected: (action) {
                switch (action) {
                  case 'connect':
                    ctrl.selectConnection(conn.id);
                    break;
                  case 'disconnect':
                    ctrl.disconnectConnection(conn.id);
                    break;
                  case 'refresh':
                    ctrl.refreshActiveSchema();
                    break;
                  case 'delete':
                    ctrl.removeConnection(conn.id);
                    break;
                }
              },
              itemBuilder: (_) => [
                if (!isActive)
                  const PopupMenuItem(
                    value: 'connect',
                    child: Row(
                      children: [
                        Icon(Icons.power_rounded, size: 15),
                        SizedBox(width: 8),
                        Text('Connect', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                if (isActive) ...[
                  const PopupMenuItem(
                    value: 'refresh',
                    child: Row(
                      children: [
                        Icon(Icons.refresh_rounded, size: 15),
                        SizedBox(width: 8),
                        Text('Refresh Schema', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'disconnect',
                    child: Row(
                      children: [
                        Icon(Icons.link_off_rounded, size: 15),
                        SizedBox(width: 8),
                        Text('Disconnect', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ],
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline_rounded,
                        size: 15,
                        color: Color(0xFFF87171),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Delete Connection',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFFF87171),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionFolder({
    required String label,
    required IconData icon,
    required Color iconColor,
    required bool expanded,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(5),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 5, 6, 5),
        child: Row(
          children: [
            Icon(
              expanded
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.keyboard_arrow_right_rounded,
              size: 14,
              color: FyrTheme.textColorMuted,
            ),
            const SizedBox(width: 4),
            Icon(icon, size: 13.5, color: iconColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: FyrTheme.textColorMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableItem(
    DbController ctrl,
    DbTableSchema table,
    Color accent,
  ) {
    final isSelected = ctrl.selectedTableName == table.name;
    final colsExpanded = _expandedTableColumns.contains(table.name);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => ctrl.selectTable(table.name),
          onDoubleTap: () => ctrl.selectTable(
            table.name,
            switchToMode: DbWorkspaceMode.dataGrid,
          ),
          child: Container(
            margin: const EdgeInsets.only(left: 20, bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4.5),
            decoration: BoxDecoration(
              color: isSelected
                  ? accent.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() {
                      if (colsExpanded) {
                        _expandedTableColumns.remove(table.name);
                      } else {
                        _expandedTableColumns.add(table.name);
                      }
                    });
                  },
                  child: Icon(
                    colsExpanded
                        ? Icons.expand_more_rounded
                        : Icons.chevron_right_rounded,
                    size: 13,
                    color: FyrTheme.textColorMuted,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  table.isView
                      ? Icons.visibility_outlined
                      : Icons.grid_on_rounded,
                  size: 13,
                  color: isSelected ? accent : const Color(0xFFA78BFA),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    table.name,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11.5,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: FyrTheme.textColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: FyrTheme.cardColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${table.rows.length}r',
                    style: TextStyle(
                      fontSize: 9.5,
                      color: FyrTheme.textColorMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (colsExpanded)
          for (final col in table.columns)
            Padding(
              padding: const EdgeInsets.only(left: 42, top: 1.5, bottom: 1.5),
              child: Row(
                children: [
                  Icon(
                    col.isPrimaryKey
                        ? Icons.key_rounded
                        : (col.isForeignKey
                            ? Icons.link_rounded
                            : Icons.circle),
                    size: col.isPrimaryKey || col.isForeignKey ? 11 : 5,
                    color: col.isPrimaryKey
                        ? const Color(0xFFFBBF24)
                        : (col.isForeignKey
                            ? const Color(0xFF38BDF8)
                            : FyrTheme.textColorMuted.withValues(alpha: 0.45)),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      col.name,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10.5,
                        color: FyrTheme.textColorMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    col.dataType,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      color: FyrTheme.textColorMuted.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
      ],
    );
  }

  Widget _buildSubItem({
    required IconData icon,
    required Color color,
    required String title,
    required String badge,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(5),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 3.5, 8, 3.5),
        child: Row(
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10.5,
                  color: FyrTheme.textColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              badge,
              style: TextStyle(fontSize: 9.5, color: FyrTheme.textColorMuted),
            ),
          ],
        ),
      ),
    );
  }
}
