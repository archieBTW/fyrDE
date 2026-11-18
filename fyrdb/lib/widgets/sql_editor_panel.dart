import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/db_models.dart';
import '../state/db_controller.dart';

class SqlSyntaxHighlightingController extends TextEditingController {
  SqlSyntaxHighlightingController({super.text});

  static final RegExp _tokenRegex = RegExp(
    r"(--[^\n]*)|('[^']*')|\b(SELECT|FROM|WHERE|JOIN|INNER|LEFT|OUTER|ON|AS|AND|OR|IN|LIKE|IS|NULL|NOT|GROUP|BY|ORDER|ASC|DESC|LIMIT|OFFSET|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|DROP|TABLE|VIEW|INDEX|TRIGGER|EXPLAIN|QUERY|PLAN|COUNT|SUM|AVG|MIN|MAX|DISTINCT|PRIMARY|KEY|REFERENCES|DEFAULT|UNIQUE)\b|\b(\d+(?:\.\d+)?)\b",
    caseSensitive: false,
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final baseStyle = style ??
        GoogleFonts.jetBrainsMono(
          fontSize: 12.5,
          height: 1.5,
          color: FyrTheme.textColor,
        );
    final children = <TextSpan>[];
    final src = text;
    var lastEnd = 0;

    for (final match in _tokenRegex.allMatches(src)) {
      if (match.start > lastEnd) {
        children.add(
          TextSpan(
            text: src.substring(lastEnd, match.start),
            style: baseStyle,
          ),
        );
      }
      final token = match.group(0)!;
      Color tokenColor = FyrTheme.textColor;
      FontWeight weight = FontWeight.w400;

      if (match.group(1) != null) {
        // Comment
        tokenColor = FyrTheme.textColorMuted.withValues(alpha: 0.55);
      } else if (match.group(2) != null) {
        // String literal
        tokenColor = const Color(0xFF4ADE80);
      } else if (match.group(3) != null) {
        // SQL Keyword
        tokenColor = const Color(0xFFD040FF);
        weight = FontWeight.w700;
      } else if (match.group(4) != null) {
        // Number literal
        tokenColor = const Color(0xFF38BDF8);
      }

      children.add(
        TextSpan(
          text: token,
          style: baseStyle.copyWith(color: tokenColor, fontWeight: weight),
        ),
      );
      lastEnd = match.end;
    }

    if (lastEnd < src.length) {
      children.add(TextSpan(text: src.substring(lastEnd), style: baseStyle));
    }

    return TextSpan(style: baseStyle, children: children);
  }
}

class SqlEditorPanel extends StatefulWidget {
  const SqlEditorPanel({super.key});

  @override
  State<SqlEditorPanel> createState() => _SqlEditorPanelState();
}

class _SqlEditorPanelState extends State<SqlEditorPanel> {
  late final SqlSyntaxHighlightingController _sqlCtrl;
  String _lastSyncedTabId = '';

  @override
  void initState() {
    super.initState();
    _sqlCtrl = SqlSyntaxHighlightingController();
  }

  @override
  void dispose() {
    _sqlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DbController>();
    final activeTab = ctrl.activeTab;
    final accent = FyrTheme.accentColor;

    if (_lastSyncedTabId != activeTab.id ||
        _sqlCtrl.text != activeTab.sqlText) {
      _lastSyncedTabId = activeTab.id;
      _sqlCtrl.value = TextEditingValue(
        text: activeTab.sqlText,
        selection: TextSelection.collapsed(offset: activeTab.sqlText.length),
      );
    }

    final lineCount = '\n'.allMatches(activeTab.sqlText).length + 1;

    return Column(
      children: [
        // SQL Tabs & Snippet Toolbar
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: FyrTheme.surfaceColor,
            border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
          ),
          child: Row(
            children: [
              // Open SQL Tabs
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: ctrl.openTabs.length + 1,
                  itemBuilder: (context, idx) {
                    if (idx == ctrl.openTabs.length) {
                      return Center(
                        child: IconButton(
                          icon: Icon(
                            Icons.add_rounded,
                            size: 16,
                            color: FyrTheme.textColorMuted,
                          ),
                          tooltip: 'New SQL Query Tab (Ctrl+N)',
                          onPressed: ctrl.newSqlTab,
                        ),
                      );
                    }
                    final tab = ctrl.openTabs[idx];
                    final isCurrent = idx == ctrl.activeTabIndex;
                    return InkWell(
                      onTap: () => ctrl.selectSqlTab(idx),
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 4,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? accent.withValues(alpha: 0.18)
                              : FyrTheme.cardColor,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isCurrent
                                ? accent.withValues(alpha: 0.5)
                                : FyrTheme.dividerColor,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.description_outlined,
                              size: 12.5,
                              color: isCurrent
                                  ? accent
                                  : FyrTheme.textColorMuted,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              tab.title,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                fontWeight: isCurrent
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: FyrTheme.textColor,
                              ),
                            ),
                            if (ctrl.openTabs.length > 1) ...[
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () => ctrl.closeSqlTab(idx),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 12,
                                  color: FyrTheme.textColorMuted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Quick SQL Snippets
              _snippetChip(
                label: 'SELECT *',
                onTap: () => ctrl.insertSqlSnippet(
                  'SELECT * FROM ${ctrl.selectedTableName} LIMIT 50;',
                ),
              ),
              const SizedBox(width: 4),
              _snippetChip(
                label: 'JOIN',
                onTap: () => ctrl.insertSqlSnippet(
                  'SELECT u.username, w.name, w.region\nFROM workspaces w\nJOIN users u ON w.owner_id = u.id;',
                ),
              ),
              const SizedBox(width: 4),
              _snippetChip(
                label: 'GROUP BY',
                onTap: () => ctrl.insertSqlSnippet(
                  'SELECT status, COUNT(*) AS count, AVG(latency_ms) AS avg_ms\nFROM deployments\nGROUP BY status;',
                ),
              ),
              const SizedBox(width: 4),
              _snippetChip(
                label: 'Format SQL',
                icon: Icons.auto_fix_high_rounded,
                onTap: ctrl.formatActiveSql,
              ),
            ],
          ),
        ),
        // Top Half: SQL Code Editor with Line Numbers
        Expanded(
          flex: 5,
          child: Container(
            color: FyrTheme.contentColor,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Line number gutter
                Container(
                  width: 44,
                  padding: const EdgeInsets.only(top: 12, right: 8),
                  decoration: BoxDecoration(
                    color: FyrTheme.bgColor,
                    border: Border(
                      right: BorderSide(color: FyrTheme.dividerColor),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(
                      lineCount.clamp(1, 18),
                      (i) => Text(
                        '${i + 1}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12.5,
                          height: 1.5,
                          color:
                              FyrTheme.textColorMuted.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  ),
                ),
                // Syntax-highlighted editor
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: TextField(
                      controller: _sqlCtrl,
                      maxLines: null,
                      expands: true,
                      onChanged: ctrl.updateActiveTabSql,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12.5,
                        height: 1.5,
                        color: FyrTheme.textColor,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Bottom Pane Header (Result Grid / Execution Plan / Query History / Execution Log)
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: FyrTheme.surfaceColor,
            border: Border.symmetric(
              horizontal: BorderSide(color: FyrTheme.dividerColor),
            ),
          ),
          child: Row(
            children: [
              for (final bTab in DbBottomTab.values) ...[
                InkWell(
                  borderRadius: BorderRadius.circular(5),
                  onTap: () => ctrl.setBottomTab(bTab),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: ctrl.activeBottomTab == bTab
                          ? accent.withValues(alpha: 0.18)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          bTab.icon,
                          size: 13,
                          color: ctrl.activeBottomTab == bTab
                              ? accent
                              : FyrTheme.textColorMuted,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          bTab.label,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: ctrl.activeBottomTab == bTab
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: ctrl.activeBottomTab == bTab
                                ? FyrTheme.textColor
                                : FyrTheme.textColorMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              const Spacer(),
              if (activeTab.lastResult != null)
                _buildResultSummaryBadge(activeTab.lastResult!, accent),
            ],
          ),
        ),
        // Bottom Pane Content
        Expanded(
          flex: 6,
          child: _buildBottomContent(ctrl, activeTab.lastResult, accent),
        ),
      ],
    );
  }

  Widget _snippetChip({
    required String label,
    IconData? icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(5),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
        decoration: BoxDecoration(
          color: FyrTheme.cardColor,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: FyrTheme.dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 11.5, color: FyrTheme.accentColor),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: FyrTheme.textColorMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultSummaryBadge(QueryResult res, Color accent) {
    if (!res.isSuccess) {
      return Text(
        'ERROR: ${res.error}',
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFFF87171),
          fontWeight: FontWeight.w600,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.check_circle_rounded,
          size: 13,
          color: Color(0xFF4ADE80),
        ),
        const SizedBox(width: 5),
        Text(
          '${res.rows.length} rows • ${res.executionTimeMs.toStringAsFixed(1)} ms',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            color: FyrTheme.textColorMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomContent(
    DbController ctrl,
    QueryResult? result,
    Color accent,
  ) {
    switch (ctrl.activeBottomTab) {
      case DbBottomTab.resultGrid:
        return _buildResultGrid(result, accent);
      case DbBottomTab.executionPlan:
        return _buildExecutionPlan(result, accent);
      case DbBottomTab.queryHistory:
        return _buildQueryHistory(ctrl, accent);
      case DbBottomTab.executionLog:
        return _buildExecutionLog(ctrl);
    }
  }

  Widget _buildResultGrid(QueryResult? result, Color accent) {
    if (result == null) {
      return Center(
        child: Text(
          'Press Run SQL (Ctrl+Enter) to execute query.',
          style: TextStyle(fontSize: 12, color: FyrTheme.textColorMuted),
        ),
      );
    }
    if (!result.isSuccess) {
      return Container(
        padding: const EdgeInsets.all(16),
        color: FyrTheme.bgColor,
        alignment: Alignment.topLeft,
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFF87171),
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                result.error ?? 'Unknown SQL execution error',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: const Color(0xFFF87171),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (result.columns.isEmpty) {
      return Center(
        child: Text(
          'Query executed successfully (${result.affectedRows} rows affected).',
          style: TextStyle(fontSize: 12, color: FyrTheme.textColorMuted),
        ),
      );
    }

    return Container(
      color: FyrTheme.bgColor,
      child: Column(
        children: [
          // Column Headers
          Container(
            height: 30,
            decoration: BoxDecoration(
              color: FyrTheme.surfaceColor,
              border: Border(
                bottom: BorderSide(color: FyrTheme.dividerColor),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  alignment: Alignment.center,
                  child: Text(
                    '#',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: FyrTheme.textColorMuted,
                    ),
                  ),
                ),
                for (final col in result.columns)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(color: FyrTheme.dividerColor),
                        ),
                      ),
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          Icon(
                            _iconForColumnName(col),
                            size: 11,
                            color: accent,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              col,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: FyrTheme.textColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Rows
          Expanded(
            child: ListView.builder(
              itemCount: result.rows.length,
              itemBuilder: (context, rIdx) {
                final row = result.rows[rIdx];
                final isEven = rIdx.isEven;
                return Container(
                  height: 28,
                  decoration: BoxDecoration(
                    color: isEven
                        ? FyrTheme.bgColor
                        : FyrTheme.surfaceColor.withValues(alpha: 0.45),
                    border: Border(
                      bottom: BorderSide(
                        color: FyrTheme.dividerColor.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        alignment: Alignment.center,
                        child: Text(
                          '${rIdx + 1}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            color: FyrTheme.textColorMuted,
                          ),
                        ),
                      ),
                      for (final col in result.columns)
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                  color: FyrTheme.dividerColor.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ),
                            ),
                            alignment: Alignment.centerLeft,
                            child: _buildFormattedCell(row[col]),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForColumnName(String col) {
    final lower = col.toLowerCase();
    if (lower == 'id' || lower.endsWith('_id')) return Icons.key_rounded;
    if (lower.contains('ms') ||
        lower.contains('count') ||
        lower.contains('replicas') ||
        lower.contains('ram')) {
      return Icons.tag_rounded;
    }
    if (lower.contains('at') || lower.contains('day')) {
      return Icons.schedule_rounded;
    }
    return Icons.text_fields_rounded;
  }

  Widget _buildFormattedCell(dynamic val) {
    if (val == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'NULL',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 9.5,
            fontStyle: FontStyle.italic,
            color: FyrTheme.textColorMuted,
          ),
        ),
      );
    }

    final str = val.toString();
    if (str == 'HEALTHY' || str == 'INFO') {
      return _statusBadge(str, const Color(0xFF22C55E));
    }
    if (str == 'SYNCING' || str == 'SCALING' || str == 'WARN') {
      return _statusBadge(str, const Color(0xFFF59E0B));
    }
    if (str == 'DEGRADED' || str == 'CRITICAL') {
      return _statusBadge(str, const Color(0xFFF87171));
    }

    return Text(
      str,
      style: GoogleFonts.jetBrainsMono(
        fontSize: 11,
        color: val is num ? const Color(0xFF38BDF8) : FyrTheme.textColor,
      ),
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _statusBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildExecutionPlan(QueryResult? result, Color accent) {
    final steps = result?.explainPlan ?? const [];
    if (steps.isEmpty) {
      return Center(
        child: Text(
          'No execution plan generated yet.',
          style: TextStyle(fontSize: 12, color: FyrTheme.textColorMuted),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: steps.length,
      itemBuilder: (context, index) {
        final step = steps[index];
        final isIndexScan = step.toUpperCase().contains('INDEX') ||
            step.toUpperCase().contains('PRIMARY KEY');
        return Container(
          margin: EdgeInsets.only(left: index * 18.0, bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: FyrTheme.surfaceColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isIndexScan
                  ? const Color(0xFF22C55E).withValues(alpha: 0.45)
                  : accent.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (isIndexScan ? const Color(0xFF22C55E) : accent)
                      .withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'STEP ${index + 1}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isIndexScan ? const Color(0xFF4ADE80) : accent,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  step,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11.5,
                    color: FyrTheme.textColor,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: FyrTheme.cardColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isIndexScan ? 'INDEX SEEK' : 'B-TREE OP',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: isIndexScan
                        ? const Color(0xFF4ADE80)
                        : const Color(0xFFFBBF24),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQueryHistory(DbController ctrl, Color accent) {
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: ctrl.queryHistory.length,
      itemBuilder: (context, i) {
        final item = ctrl.queryHistory[i];
        return InkWell(
          onTap: () {
            ctrl.updateActiveTabSql(item.sql);
            ctrl.runActiveQuery();
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: FyrTheme.surfaceColor,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: FyrTheme.dividerColor),
            ),
            child: Row(
              children: [
                Icon(
                  item.isSuccess
                      ? Icons.check_circle_rounded
                      : Icons.error_rounded,
                  size: 14,
                  color: item.isSuccess
                      ? const Color(0xFF4ADE80)
                      : const Color(0xFFF87171),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.connectionName,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      color: accent,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.sql.replaceAll('\n', ' '),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: FyrTheme.textColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${item.rowCount} rows • ${item.durationMs.toStringAsFixed(1)} ms',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    color: FyrTheme.textColorMuted,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildExecutionLog(DbController ctrl) {
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: ctrl.executionLogs.length,
      itemBuilder: (context, idx) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            ctrl.executionLogs[idx],
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              color: FyrTheme.textColorMuted,
            ),
          ),
        );
      },
    );
  }
}
