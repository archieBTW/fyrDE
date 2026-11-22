import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../engine/sql_engine.dart';
import '../models/db_models.dart';

class PendingCellEdit {
  final String tableName;
  final int rowIndex;
  final String columnName;
  final dynamic oldValue;
  final dynamic newValue;
  final bool isInsert;
  final bool isDelete;
  final Map<String, dynamic>? rowSnapshot;

  const PendingCellEdit({
    required this.tableName,
    required this.rowIndex,
    required this.columnName,
    required this.oldValue,
    required this.newValue,
    this.isInsert = false,
    this.isDelete = false,
    this.rowSnapshot,
  });
}

class DbController extends ChangeNotifier {
  final String configFilePath;
  final bool persistConnections;

  final List<DbConnectionProfile> connections = [];
  final Map<String, List<DbTableSchema>> _schemasByConnection = {};
  final List<SqlQueryTab> openTabs = [];
  final List<QueryHistoryEntry> queryHistory = [];
  final List<String> executionLogs = [];

  // Key: "$tableName:$rowIndex:$columnName"
  final Map<String, PendingCellEdit> pendingCellEdits = {};
  // Snapshot of table rows for full rollback support
  final Map<String, List<Map<String, dynamic>>> _tableSnapshots = {};

  String? activeConnectionId;
  int activeTabIndex = 0;
  String? selectedTableName;
  DbWorkspaceMode workspaceMode = DbWorkspaceMode.sqlEditor;
  DbBottomTab activeBottomTab = DbBottomTab.resultGrid;

  String navigatorSearchQuery = '';
  String dataGridFilterWhere = '';
  String? dataGridSortColumn;
  bool dataGridSortAsc = true;
  int? selectedDataRowIndex;
  bool autoCommit = true;
  bool isConnecting = false;
  String? statusMessage;

  DbController({
    String? configFilePath,
    bool loadSaved = true,
    this.persistConnections = true,
  }) : configFilePath = configFilePath ?? defaultConfigPath {
    if (loadSaved) {
      loadSavedConnectionsSync();
    }
    _log(
      connections.isEmpty
          ? 'fyrDB ready — no saved connections configured yet'
          : 'fyrDB ready — loaded ${connections.length} saved connection${connections.length == 1 ? '' : 's'}',
    );
  }

  static String get defaultConfigPath =>
      SqlEngine.resolvePath('~/.config/fyrdb/connections.json');

  DbConnectionProfile? get activeConnection {
    final id = activeConnectionId;
    if (id == null || connections.isEmpty) return null;
    for (final c in connections) {
      if (c.id == id) return c;
    }
    return null;
  }

  List<DbTableSchema> get activeSchemas {
    final id = activeConnectionId;
    if (id == null) return const [];
    return _schemasByConnection[id] ?? const [];
  }

  List<DbTableSchema> get activeTables =>
      activeSchemas.where((t) => !t.isView).toList();

  List<DbTableSchema> get activeViews =>
      activeSchemas.where((t) => t.isView).toList();

  List<DbIndexSchema> get activeIndexes {
    final list = <DbIndexSchema>[];
    for (final t in activeSchemas) {
      list.addAll(t.indexes);
    }
    return list;
  }

  List<DbTriggerSchema> get activeTriggers {
    final list = <DbTriggerSchema>[];
    for (final t in activeSchemas) {
      list.addAll(t.triggers);
    }
    return list;
  }

  DbTableSchema? get selectedTable {
    final schemas = activeSchemas;
    if (schemas.isEmpty) return null;
    if (selectedTableName != null) {
      for (final s in schemas) {
        if (s.name == selectedTableName) return s;
      }
    }
    return schemas.first;
  }

  SqlQueryTab? get activeTab {
    if (openTabs.isEmpty) return null;
    activeTabIndex = activeTabIndex.clamp(0, openTabs.length - 1);
    return openTabs[activeTabIndex];
  }

  int get pendingEditCount => pendingCellEdits.length;

  /// Loads saved connection profiles from `configFilePath` (no raw passwords stored).
  void loadSavedConnectionsSync() {
    try {
      final file = File(configFilePath);
      if (!file.existsSync()) return;
      final content = file.readAsStringSync().trim();
      if (content.isEmpty) return;
      final decoded = jsonDecode(content);
      if (decoded is List) {
        connections.clear();
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            connections.add(DbConnectionProfile.fromJson(item));
          }
        }
      }
    } catch (e) {
      _log('Warning: Failed to read saved connections from $configFilePath: $e');
    }
  }

  /// Persists saved connections to `~/.config/fyrdb/connections.json` (excluding raw passwords).
  Future<void> saveConnections() async {
    if (!persistConnections) return;
    try {
      final file = File(configFilePath);
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      const encoder = JsonEncoder.withIndent('  ');
      final payload = connections.map((c) => c.toJson()).toList();
      await file.writeAsString(encoder.convert(payload));
    } catch (e) {
      _log('Warning: Failed to persist connections to $configFilePath: $e');
    }
  }

  void setWorkspaceMode(DbWorkspaceMode mode) {
    workspaceMode = mode;
    notifyListeners();
  }

  void setBottomTab(DbBottomTab tab) {
    activeBottomTab = tab;
    notifyListeners();
  }

  void setNavigatorSearch(String query) {
    navigatorSearchQuery = query;
    notifyListeners();
  }

  void toggleAutoCommit() {
    autoCommit = !autoCommit;
    statusMessage = autoCommit
        ? 'Transaction mode: Auto-Commit enabled'
        : 'Transaction mode: Manual Transaction (BEGIN)';
    _log(statusMessage!);
    notifyListeners();
  }

  Future<void> selectConnection(String connectionId) async {
    DbConnectionProfile? target;
    for (final c in connections) {
      if (c.id == connectionId) {
        target = c;
        break;
      }
    }
    if (target == null) return;

    isConnecting = true;
    notifyListeners();

    target.isConnected = true;
    activeConnectionId = target.id;
    pendingCellEdits.clear();
    _tableSnapshots.clear();
    dataGridFilterWhere = '';
    dataGridSortColumn = null;
    selectedDataRowIndex = null;

    // Introspect real schema if not already populated (e.g. from test/in-memory setup)
    if (!_schemasByConnection.containsKey(target.id)) {
      final introspected = await SqlEngine.introspectConnection(target);
      _schemasByConnection[target.id] = introspected;
    }

    final tables = activeSchemas;
    if (tables.isNotEmpty) {
      if (selectedTableName == null ||
          !tables.any((t) => t.name == selectedTableName)) {
        selectedTableName = tables.first.name;
      }
    } else {
      selectedTableName = null;
    }

    _ensureTabForConnection(target);

    isConnecting = false;
    statusMessage = 'Connected to ${target.name} (${target.driver.label})';
    _log(
      'Connected to ${target.name} [${target.endpointSummary}] — ${tables.length} object${tables.length == 1 ? '' : 's'}',
    );
    notifyListeners();
  }

  Future<void> addConnection(
    DbConnectionProfile profile, {
    List<DbTableSchema>? schemas,
    bool createFileIfMissing = false,
  }) async {
    if (createFileIfMissing) {
      final resolved = SqlEngine.resolvePath(profile.databaseOrPath);
      if (resolved.isNotEmpty &&
          resolved != ':memory:' &&
          !File(resolved).existsSync()) {
        if (profile.driver == DbDriverType.sqlite) {
          await SqlEngine.createSqliteFile(resolved);
        } else if (profile.driver == DbDriverType.duckdb) {
          await SqlEngine.createDuckDbFile(resolved);
        }
      }
    }

    connections.add(profile);
    if (schemas != null) {
      _schemasByConnection[profile.id] = schemas;
    }
    await saveConnections();
    await selectConnection(profile.id);
  }

  void disconnectConnection(String connectionId) {
    for (final c in connections) {
      if (c.id == connectionId) {
        c.isConnected = false;
        _log('Disconnected from ${c.name}');
        statusMessage = 'Disconnected from ${c.name}';
        break;
      }
    }
    if (activeConnectionId == connectionId) {
      activeConnectionId = null;
      selectedTableName = null;
      pendingCellEdits.clear();
      _tableSnapshots.clear();
      selectedDataRowIndex = null;
    }
    notifyListeners();
  }

  void disconnectActive() {
    final id = activeConnectionId;
    if (id != null) {
      disconnectConnection(id);
    }
  }

  Future<void> removeConnection(String connectionId) async {
    String? removedName;
    connections.removeWhere((c) {
      if (c.id == connectionId) {
        removedName = c.name;
        return true;
      }
      return false;
    });
    _schemasByConnection.remove(connectionId);
    openTabs.removeWhere((t) => t.connectionId == connectionId);
    if (openTabs.isNotEmpty) {
      activeTabIndex = activeTabIndex.clamp(0, openTabs.length - 1);
    } else {
      activeTabIndex = 0;
    }

    if (activeConnectionId == connectionId) {
      activeConnectionId = null;
      selectedTableName = null;
      pendingCellEdits.clear();
      _tableSnapshots.clear();
      selectedDataRowIndex = null;
    }

    await saveConnections();
    if (removedName != null) {
      statusMessage = 'Removed connection "$removedName"';
      _log('Removed saved connection "$removedName"');
    }
    notifyListeners();
  }

  Future<void> refreshActiveSchema() async {
    final conn = activeConnection;
    if (conn == null) return;
    if (conn.driver == DbDriverType.sqlite &&
        conn.databaseOrPath.trim() == ':memory:') {
      return;
    }
    final refreshed = await SqlEngine.introspectConnection(conn);
    _schemasByConnection[conn.id] = refreshed;
    if (refreshed.isEmpty) {
      selectedTableName = null;
    } else if (selectedTableName == null ||
        !refreshed.any((t) => t.name == selectedTableName)) {
      selectedTableName = refreshed.first.name;
    }
    statusMessage =
        'Refreshed schema for ${conn.name} (${refreshed.length} objects)';
    _log(statusMessage!);
    notifyListeners();
  }

  void _ensureTabForConnection(DbConnectionProfile conn) {
    final existingIdx = openTabs.indexWhere((t) => t.connectionId == conn.id);
    if (existingIdx >= 0) {
      activeTabIndex = existingIdx;
      return;
    }
    final tables = _schemasByConnection[conn.id] ?? const [];
    final String starterSql;
    if (conn.driver == DbDriverType.redis) {
      starterSql = 'PING';
    } else if (tables.isNotEmpty) {
      starterSql = 'SELECT * FROM ${tables.first.name} LIMIT 50;';
    } else {
      starterSql =
          '-- Connected to ${conn.name} (${conn.driver.label})\n-- Write a SQL statement below and press Ctrl+Enter to execute.\nSELECT 1 AS ok;';
    }
    final num = openTabs.length + 1;
    openTabs.add(
      SqlQueryTab(
        id: 'tab_${DateTime.now().microsecondsSinceEpoch}_$num',
        title: '${num.toString().padLeft(2, '0')}_query.sql',
        connectionId: conn.id,
        sqlText: starterSql,
      ),
    );
    activeTabIndex = openTabs.length - 1;
  }

  void selectTable(String tableName, {DbWorkspaceMode? switchToMode}) {
    selectedTableName = tableName;
    selectedDataRowIndex = null;
    if (switchToMode != null) {
      workspaceMode = switchToMode;
    }
    notifyListeners();
  }

  void selectSqlTab(int index) {
    if (index >= 0 && index < openTabs.length) {
      activeTabIndex = index;
      notifyListeners();
    }
  }

  void newSqlTab({String? title, String? initialSql}) {
    final conn = activeConnection;
    if (conn == null) return;
    final num = openTabs.length + 1;
    final tbl = selectedTableName;
    final defaultSql = conn.driver == DbDriverType.redis
        ? 'INFO keyspace'
        : (tbl != null
            ? 'SELECT * FROM $tbl LIMIT 50;'
            : '-- New query on ${conn.name}\nSELECT 1 AS result;');
    final tab = SqlQueryTab(
      id: 'tab_${DateTime.now().microsecondsSinceEpoch}_$num',
      title: title ?? '${num.toString().padLeft(2, '0')}_query.sql',
      connectionId: conn.id,
      sqlText: initialSql ?? defaultSql,
    );
    openTabs.add(tab);
    activeTabIndex = openTabs.length - 1;
    workspaceMode = DbWorkspaceMode.sqlEditor;
    notifyListeners();
  }

  void closeSqlTab(int index) {
    if (openTabs.length <= 1) return;
    if (index < 0 || index >= openTabs.length) return;
    openTabs.removeAt(index);
    if (activeTabIndex >= openTabs.length) {
      activeTabIndex = openTabs.length - 1;
    }
    notifyListeners();
  }

  void updateActiveTabSql(String sql) {
    final tab = activeTab;
    if (tab != null) {
      tab.sqlText = sql;
    }
  }

  void insertSqlSnippet(String snippet) {
    final tab = activeTab;
    if (tab == null) {
      if (activeConnection != null) {
        newSqlTab(initialSql: snippet);
      }
      return;
    }
    final current = tab.sqlText.trim();
    tab.sqlText = current.isEmpty ? snippet : '$current\n\n$snippet';
    workspaceMode = DbWorkspaceMode.sqlEditor;
    notifyListeners();
  }

  void formatActiveSql() {
    final tab = activeTab;
    if (tab == null) return;
    tab.sqlText = SqlEngine.formatSql(tab.sqlText);
    statusMessage = 'Formatted SQL query in ${tab.title}';
    notifyListeners();
  }

  /// Synchronous in-memory SQL execution (used for `:memory:` databases and pure-Dart tests).
  QueryResult runSql(String sql, {String? connectionId}) {
    final conn = _findConnection(connectionId ?? activeConnectionId);
    if (conn == null) {
      return QueryResult(
        columns: const [],
        rows: const [],
        executionTimeMs: 0.1,
        error: 'No active database connection.',
        executedSql: sql,
      );
    }
    final schemas = _schemasByConnection.putIfAbsent(conn.id, () => []);
    final result = SqlEngine.executeInMemory(sql, schemas);
    _recordExecutionResult(conn, sql, result);
    if (selectedTableName == null && schemas.isNotEmpty) {
      selectedTableName = schemas.first.name;
    }
    notifyListeners();
    return result;
  }

  /// Executes SQL against the real database engine (SQLite file on disk, remote CLI, or `:memory:`).
  Future<QueryResult> executeSql(String sql, {String? connectionId}) async {
    final conn = _findConnection(connectionId ?? activeConnectionId);
    if (conn == null) {
      return QueryResult(
        columns: const [],
        rows: const [],
        executionTimeMs: 0.1,
        error: 'No active database connection.',
        executedSql: sql,
      );
    }

    if (conn.readOnly && _isMutatingSql(sql)) {
      final errRes = QueryResult(
        columns: const [],
        rows: const [],
        executionTimeMs: 0.1,
        error:
            'Connection "${conn.name}" is in Read-Only mode. Mutating statements are blocked.',
        executedSql: sql,
      );
      _recordExecutionResult(conn, sql, errRes);
      notifyListeners();
      return errRes;
    }

    QueryResult result;
    if (conn.driver == DbDriverType.sqlite) {
      final rawPath = conn.databaseOrPath.trim();
      final resolved = SqlEngine.resolvePath(rawPath);
      if (rawPath == ':memory:') {
        final schemas = _schemasByConnection.putIfAbsent(conn.id, () => []);
        result = SqlEngine.executeInMemory(sql, schemas);
        if (selectedTableName == null && schemas.isNotEmpty) {
          selectedTableName = schemas.first.name;
        }
      } else if (SqlEngine.hasSqliteCli && File(resolved).existsSync()) {
        result = await SqlEngine.executeOnSqliteFile(resolved, sql);
        if (result.isSuccess && _isMutatingSql(sql)) {
          final refreshed = await SqlEngine.introspectSqliteFile(resolved);
          _schemasByConnection[conn.id] = refreshed;
          if (refreshed.isEmpty) {
            selectedTableName = null;
          } else if (selectedTableName == null ||
              !refreshed.any((t) => t.name == selectedTableName)) {
            selectedTableName = refreshed.first.name;
          }
        }
      } else {
        result = await SqlEngine.executeOnSqliteFile(resolved, sql);
      }
    } else {
      result = await SqlEngine.executeOnProfile(conn, sql);
      if (result.isSuccess && _isMutatingSql(sql)) {
        final refreshed = await SqlEngine.introspectConnection(conn);
        if (refreshed.isNotEmpty) {
          _schemasByConnection[conn.id] = refreshed;
          if (selectedTableName == null ||
              !refreshed.any((t) => t.name == selectedTableName)) {
            selectedTableName = refreshed.first.name;
          }
        }
      }
    }

    _recordExecutionResult(conn, sql, result);
    notifyListeners();
    return result;
  }

  bool _isMutatingSql(String sql) {
    final trimmed = sql.trimLeft().toUpperCase();
    return trimmed.startsWith('INSERT') ||
        trimmed.startsWith('UPDATE') ||
        trimmed.startsWith('DELETE') ||
        trimmed.startsWith('CREATE') ||
        trimmed.startsWith('DROP') ||
        trimmed.startsWith('ALTER') ||
        trimmed.startsWith('REPLACE') ||
        trimmed.startsWith('TRUNCATE');
  }

  DbConnectionProfile? _findConnection(String? id) {
    if (id == null) return activeConnection;
    for (final c in connections) {
      if (c.id == id) return c;
    }
    return activeConnection;
  }

  void _recordExecutionResult(
    DbConnectionProfile conn,
    String sql,
    QueryResult result,
  ) {
    queryHistory.insert(
      0,
      QueryHistoryEntry(
        id: 'hist_${DateTime.now().microsecondsSinceEpoch}',
        connectionName: conn.name,
        sql: sql.trim(),
        durationMs: result.executionTimeMs,
        rowCount: result.rows.length,
        isSuccess: result.isSuccess,
      ),
    );

    if (result.isSuccess) {
      statusMessage =
          '${result.rows.length} rows returned in ${result.executionTimeMs.toStringAsFixed(1)} ms on ${conn.name}';
      _log(
        '[${conn.name}] OK (${result.executionTimeMs.toStringAsFixed(2)} ms, ${result.rows.length} rows): ${_oneLine(sql)}',
      );
    } else {
      statusMessage = 'SQL Error: ${result.error}';
      _log('[${conn.name}] ERROR: ${result.error} — ${_oneLine(sql)}');
    }
  }

  Future<void> runActiveQuery() async {
    final conn = activeConnection;
    final tab = activeTab;
    if (conn == null || tab == null) return;
    tab.isRunning = true;
    notifyListeners();

    final res = await executeSql(tab.sqlText, connectionId: conn.id);
    tab.lastResult = res;
    tab.isRunning = false;
    activeBottomTab = DbBottomTab.resultGrid;
    notifyListeners();
  }

  Future<void> explainActiveQuery() async {
    final conn = activeConnection;
    final tab = activeTab;
    if (conn == null || tab == null) return;
    final raw = tab.sqlText.trim();
    if (raw.isEmpty) return;

    final explainPrefix =
        conn.driver == DbDriverType.sqlite ? 'EXPLAIN QUERY PLAN ' : 'EXPLAIN ';
    final explainSql =
        raw.toUpperCase().startsWith('EXPLAIN') ? raw : '$explainPrefix$raw';
    final res = await executeSql(explainSql, connectionId: conn.id);
    final planSteps = res.explainPlan.isNotEmpty
        ? res.explainPlan
        : res.rows
            .map((r) => r.values.map((v) => v?.toString() ?? '').join(' | '))
            .where((s) => s.isNotEmpty)
            .toList();

    tab.lastResult = QueryResult(
      columns: tab.lastResult?.columns ?? res.columns,
      rows: tab.lastResult?.rows ?? res.rows,
      affectedRows: res.affectedRows,
      executionTimeMs: res.executionTimeMs,
      explainPlan: planSteps,
      error: res.error,
      executedSql: tab.sqlText,
    );
    activeBottomTab = DbBottomTab.executionPlan;
    statusMessage = res.isSuccess
        ? 'Explain Query Plan generated (${planSteps.length} steps)'
        : 'Explain error: ${res.error}';
    notifyListeners();
  }

  // --- Data Grid Filtering, Sorting & Transactional Inline Editing ---

  void setDataGridFilter(String whereExpr) {
    dataGridFilterWhere = whereExpr.trim();
    notifyListeners();
  }

  void toggleDataGridSort(String columnName) {
    if (dataGridSortColumn == columnName) {
      dataGridSortAsc = !dataGridSortAsc;
    } else {
      dataGridSortColumn = columnName;
      dataGridSortAsc = true;
    }
    notifyListeners();
  }

  void selectDataRow(int? index) {
    selectedDataRowIndex = index;
    notifyListeners();
  }

  List<Map<String, dynamic>> getFilteredDataGridRows() {
    final table = selectedTable;
    if (table == null) return const [];
    final orderClause = dataGridSortColumn != null
        ? ' ORDER BY $dataGridSortColumn ${dataGridSortAsc ? 'ASC' : 'DESC'}'
        : '';
    final whereClause = dataGridFilterWhere.isNotEmpty
        ? ' WHERE $dataGridFilterWhere'
        : '';
    final sql = 'SELECT * FROM ${table.name}$whereClause$orderClause';
    final res = SqlEngine.executeInMemory(sql, activeSchemas);
    if (res.isSuccess) return res.rows;
    return table.rows;
  }

  void _ensureTableSnapshot(DbTableSchema table) {
    final connId = activeConnectionId;
    if (connId == null) return;
    final key = '$connId:${table.name}';
    if (!_tableSnapshots.containsKey(key)) {
      _tableSnapshots[key] = table.rows
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
    }
  }

  void stageCellEdit(
    String tableName,
    int rowIndex,
    String columnName,
    dynamic newValue,
  ) {
    DbTableSchema? table;
    for (final t in activeSchemas) {
      if (t.name == tableName) {
        table = t;
        break;
      }
    }
    table ??= selectedTable;
    if (table == null || rowIndex < 0 || rowIndex >= table.rows.length) return;
    _ensureTableSnapshot(table);

    final oldVal = table.rows[rowIndex][columnName];
    if ('$oldVal' == '$newValue') return;

    final editKey = '$tableName:$rowIndex:$columnName';
    final existing = pendingCellEdits[editKey];
    final rowSnap = Map<String, dynamic>.from(table.rows[rowIndex]);
    pendingCellEdits[editKey] = PendingCellEdit(
      tableName: tableName,
      rowIndex: rowIndex,
      columnName: columnName,
      oldValue: existing != null ? existing.oldValue : oldVal,
      newValue: newValue,
      rowSnapshot: rowSnap,
    );
    table.rows[rowIndex][columnName] = newValue;
    statusMessage =
        'Staged edit on $tableName.$columnName (${pendingCellEdits.length} uncommitted change${pendingCellEdits.length == 1 ? '' : 's'})';
    notifyListeners();
  }

  bool isCellDirty(String tableName, int rowIndex, String columnName) {
    return pendingCellEdits.containsKey('$tableName:$rowIndex:$columnName');
  }

  void insertBlankRow() {
    final table = selectedTable;
    if (table == null || table.isView) return;
    _ensureTableSnapshot(table);

    final newRow = <String, dynamic>{};
    final pk = table.primaryKeyColumn;
    var nextId = 1;
    if (pk != null) {
      for (final r in table.rows) {
        final v = r[pk];
        if (v is int && v >= nextId) nextId = v + 1;
      }
    }

    for (final col in table.columns) {
      if (col.isPrimaryKey) {
        newRow[col.name] = nextId;
      } else if (col.defaultValue != null) {
        newRow[col.name] = col.defaultValue!.replaceAll("'", '');
      } else if (col.dataType.contains('INT')) {
        newRow[col.name] = 0;
      } else if (col.dataType.contains('BOOL')) {
        newRow[col.name] = 1;
      } else {
        newRow[col.name] = 'new_${col.name}';
      }
    }

    final rowIdx = table.rows.length;
    table.rows.add(newRow);
    table.rowCount = table.rows.length;
    selectedDataRowIndex = rowIdx;

    final colKey = pk ?? (table.columns.isNotEmpty ? table.columns.first.name : 'row');
    pendingCellEdits['${table.name}:$rowIdx:$colKey'] = PendingCellEdit(
      tableName: table.name,
      rowIndex: rowIdx,
      columnName: colKey,
      oldValue: null,
      newValue: nextId,
      isInsert: true,
      rowSnapshot: Map<String, dynamic>.from(newRow),
    );
    statusMessage = 'Inserted new row #$nextId into ${table.name}';
    notifyListeners();
  }

  void deleteSelectedRow() {
    final table = selectedTable;
    if (table == null || table.isView || selectedDataRowIndex == null) return;
    final idx = selectedDataRowIndex!;
    if (idx < 0 || idx >= table.rows.length) return;
    _ensureTableSnapshot(table);

    final removed = table.rows.removeAt(idx);
    table.rowCount = table.rows.length;
    selectedDataRowIndex = null;
    final pk = table.primaryKeyColumn ?? 'row';
    pendingCellEdits['${table.name}:deleted:$idx'] = PendingCellEdit(
      tableName: table.name,
      rowIndex: idx,
      columnName: pk,
      oldValue: removed[pk],
      newValue: 'DELETED',
      isDelete: true,
      rowSnapshot: Map<String, dynamic>.from(removed),
    );
    statusMessage = 'Removed row from ${table.name} (pending commit)';
    notifyListeners();
  }

  Future<void> commitPendingChanges() async {
    final conn = activeConnection;
    if (conn == null) return;
    final count = pendingCellEdits.length;

    // Persist staged edits to disk when connected to a real SQLite file
    if (conn.driver == DbDriverType.sqlite &&
        conn.databaseOrPath.trim() != ':memory:' &&
        SqlEngine.hasSqliteCli) {
      final resolved = SqlEngine.resolvePath(conn.databaseOrPath);
      if (File(resolved).existsSync()) {
        for (final edit in pendingCellEdits.values) {
          DbTableSchema? table;
          for (final t in activeSchemas) {
            if (t.name == edit.tableName) {
              table = t;
              break;
            }
          }
          if (table == null) continue;
          final pk = table.primaryKeyColumn;
          if (edit.isInsert && edit.rowSnapshot != null) {
            final row = edit.rowIndex < table.rows.length
                ? table.rows[edit.rowIndex]
                : edit.rowSnapshot!;
            final cols = row.keys.map((k) => '"$k"').join(', ');
            final vals = row.values.map(_sqlVal).join(', ');
            await SqlEngine.executeOnSqliteFile(
              resolved,
              'INSERT INTO "${table.name}" ($cols) VALUES ($vals);',
            );
          } else if (edit.isDelete && pk != null && edit.oldValue != null) {
            await SqlEngine.executeOnSqliteFile(
              resolved,
              'DELETE FROM "${table.name}" WHERE "$pk" = ${_sqlVal(edit.oldValue)};',
            );
          } else if (pk != null &&
              edit.rowSnapshot != null &&
              edit.rowSnapshot![pk] != null) {
            await SqlEngine.executeOnSqliteFile(
              resolved,
              'UPDATE "${table.name}" SET "${edit.columnName}" = ${_sqlVal(edit.newValue)} WHERE "$pk" = ${_sqlVal(edit.rowSnapshot![pk])};',
            );
          }
        }
      }
    }

    pendingCellEdits.clear();
    _tableSnapshots.clear();
    statusMessage =
        'COMMIT OK — $count change${count == 1 ? '' : 's'} persisted to ${conn.name}';
    _log('[${conn.name}] COMMIT TRANSACTION ($count changes)');
    notifyListeners();
  }

  String _sqlVal(dynamic v) {
    if (v == null) return 'NULL';
    if (v is num) return v.toString();
    if (v is bool) return v ? '1' : '0';
    return "'${v.toString().replaceAll("'", "''")}'";
  }

  void rollbackPendingChanges() {
    final conn = activeConnection;
    final count = pendingCellEdits.length;
    for (final entry in _tableSnapshots.entries) {
      final sepIdx = entry.key.indexOf(':');
      if (sepIdx > 0) {
        final connId = entry.key.substring(0, sepIdx);
        final tblName = entry.key.substring(sepIdx + 1);
        final schemas = _schemasByConnection[connId] ?? [];
        for (final t in schemas) {
          if (t.name == tblName) {
            t.rows
              ..clear()
              ..addAll(
                entry.value.map((r) => Map<String, dynamic>.from(r)),
              );
            t.rowCount = t.rows.length;
          }
        }
      }
    }
    pendingCellEdits.clear();
    _tableSnapshots.clear();
    statusMessage =
        'ROLLBACK OK — reverted $count uncommitted change${count == 1 ? '' : 's'}';
    if (conn != null) {
      _log('[${conn.name}] ROLLBACK TRANSACTION ($count changes reverted)');
    }
    notifyListeners();
  }

  void updateTableErPosition(String tableName, Offset newPos) {
    for (final t in activeSchemas) {
      if (t.name == tableName) {
        t.erPosition = Offset(
          newPos.dx.clamp(12.0, 1600.0),
          newPos.dy.clamp(12.0, 1200.0),
        );
        notifyListeners();
        return;
      }
    }
  }

  void autoLayoutErDiagram() {
    final tables = activeSchemas;
    for (var i = 0; i < tables.length; i++) {
      final col = i % 3;
      final row = i ~/ 3;
      tables[i].erPosition = Offset(36.0 + col * 320.0, 36.0 + row * 255.0);
    }
    statusMessage = 'Auto-arranged ${tables.length} ER Diagram nodes';
    notifyListeners();
  }

  Future<void> openFiles(List<String> paths) async {
    for (final rawPath in paths) {
      final path = SqlEngine.resolvePath(rawPath);
      final lower = path.toLowerCase();
      final file = File(path);
      if (!file.existsSync()) continue;

      if (lower.endsWith('.sql')) {
        final content = file.readAsStringSync();
        final fileName = path.split('/').last;
        if (activeConnection != null) {
          newSqlTab(title: fileName, initialSql: content);
          await runActiveQuery();
          statusMessage = 'Opened SQL script $fileName';
        } else {
          statusMessage =
              'Connect to a database first before opening SQL script $fileName';
        }
      } else if (lower.endsWith('.sqlite') ||
          lower.endsWith('.sqlite3') ||
          lower.endsWith('.db')) {
        final fileName = path.split('/').last;
        // Reuse existing connection if same path is already saved
        DbConnectionProfile? existing;
        for (final c in connections) {
          if (c.driver == DbDriverType.sqlite &&
              SqlEngine.resolvePath(c.databaseOrPath) == path) {
            existing = c;
            break;
          }
        }
        if (existing != null) {
          _schemasByConnection.remove(existing.id);
          await selectConnection(existing.id);
          statusMessage =
              'Opened SQLite database $fileName (${activeSchemas.length} objects)';
        } else {
          final connId = 'conn_${DateTime.now().microsecondsSinceEpoch}';
          final profile = DbConnectionProfile(
            id: connId,
            name: fileName,
            driver: DbDriverType.sqlite,
            databaseOrPath: path,
            isConnected: true,
          );
          final introspected = await SqlEngine.introspectSqliteFile(path);
          await addConnection(profile, schemas: introspected);
          statusMessage =
              'Mounted SQLite database $fileName (${introspected.length} objects)';
        }
      } else if (lower.endsWith('.duckdb') || lower.endsWith('.ddb')) {
        final fileName = path.split('/').last;
        final connId = 'conn_${DateTime.now().microsecondsSinceEpoch}';
        final profile = DbConnectionProfile(
          id: connId,
          name: fileName,
          driver: DbDriverType.duckdb,
          databaseOrPath: path,
          isConnected: true,
        );
        await addConnection(profile);
        statusMessage =
            'Mounted DuckDB database $fileName (${activeSchemas.length} objects)';
      }
    }
    notifyListeners();
  }

  String exportResultAs(String format) {
    final res = activeTab?.lastResult;
    if (res == null) return '';
    final tableName = selectedTableName ?? 'query_results';
    switch (format.toLowerCase()) {
      case 'csv':
        return SqlEngine.exportToCsv(res);
      case 'json':
        return SqlEngine.exportToJson(res);
      case 'sql':
        return SqlEngine.exportToSqlInserts(tableName, res);
      default:
        return SqlEngine.exportToCsv(res);
    }
  }

  void _log(String msg) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    executionLogs.insert(0, '[$ts] $msg');
  }

  String _oneLine(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
}
