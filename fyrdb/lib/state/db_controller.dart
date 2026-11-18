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

  const PendingCellEdit({
    required this.tableName,
    required this.rowIndex,
    required this.columnName,
    required this.oldValue,
    required this.newValue,
  });
}

class DbController extends ChangeNotifier {
  final List<DbConnectionProfile> connections = [];
  final Map<String, List<DbTableSchema>> _schemasByConnection = {};
  final List<SqlQueryTab> openTabs = [];
  final List<QueryHistoryEntry> queryHistory = [];
  final List<String> executionLogs = [];

  // Key: "$tableName:$rowIndex:$columnName"
  final Map<String, PendingCellEdit> pendingCellEdits = {};
  // Snapshot of table rows for full rollback support
  final Map<String, List<Map<String, dynamic>>> _tableSnapshots = {};

  String activeConnectionId = 'conn_fyr_cloud';
  int activeTabIndex = 0;
  String selectedTableName = 'deployments';
  DbWorkspaceMode workspaceMode = DbWorkspaceMode.sqlEditor;
  DbBottomTab activeBottomTab = DbBottomTab.resultGrid;

  String navigatorSearchQuery = '';
  String dataGridFilterWhere = '';
  String? dataGridSortColumn;
  bool dataGridSortAsc = true;
  int? selectedDataRowIndex;
  bool autoCommit = true;
  String? statusMessage;

  DbController() {
    _seedInitialConnectionsAndSchemas();
    _seedInitialTabs();
  }

  DbConnectionProfile get activeConnection {
    return connections.firstWhere(
      (c) => c.id == activeConnectionId,
      orElse: () => connections.first,
    );
  }

  List<DbTableSchema> get activeSchemas =>
      _schemasByConnection[activeConnectionId] ?? [];

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
    for (final s in schemas) {
      if (s.name == selectedTableName) return s;
    }
    return schemas.first;
  }

  SqlQueryTab get activeTab {
    if (openTabs.isEmpty) {
      openTabs.add(
        SqlQueryTab(
          id: 'tab_default',
          title: 'query_01.sql',
          connectionId: activeConnectionId,
          sqlText: 'SELECT * FROM users;',
        ),
      );
    }
    activeTabIndex = activeTabIndex.clamp(0, openTabs.length - 1);
    return openTabs[activeTabIndex];
  }

  int get pendingEditCount => pendingCellEdits.length;

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

  void selectConnection(String connectionId) {
    final target = connections.firstWhere(
      (c) => c.id == connectionId,
      orElse: () => connections.first,
    );
    target.isConnected = true;
    activeConnectionId = target.id;
    final tables = activeSchemas;
    if (tables.isNotEmpty &&
        !tables.any((t) => t.name == selectedTableName)) {
      selectedTableName = tables.first.name;
    }
    statusMessage = 'Connected to ${target.name} (${target.driver.label})';
    _log('Switched active connection to ${target.name} [${target.endpointSummary}]');
    notifyListeners();
  }

  void addConnection(DbConnectionProfile profile, {List<DbTableSchema>? schemas}) {
    connections.add(profile);
    _schemasByConnection[profile.id] = schemas ?? _buildDefaultStarterSchema();
    selectConnection(profile.id);
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
    final num = openTabs.length + 1;
    final tab = SqlQueryTab(
      id: 'tab_${DateTime.now().microsecondsSinceEpoch}_$num',
      title: title ?? '0${num}_query.sql',
      connectionId: activeConnectionId,
      sqlText: initialSql ??
          'SELECT id, username, role, plan_tier\nFROM users\nWHERE active = 1\nORDER BY id ASC;',
    );
    openTabs.add(tab);
    activeTabIndex = openTabs.length - 1;
    workspaceMode = DbWorkspaceMode.sqlEditor;
    notifyListeners();
  }

  void closeSqlTab(int index) {
    if (openTabs.length <= 1) return;
    openTabs.removeAt(index);
    if (activeTabIndex >= openTabs.length) {
      activeTabIndex = openTabs.length - 1;
    }
    notifyListeners();
  }

  void updateActiveTabSql(String sql) {
    activeTab.sqlText = sql;
  }

  void insertSqlSnippet(String snippet) {
    final current = activeTab.sqlText.trim();
    activeTab.sqlText = current.isEmpty ? snippet : '$current\n\n$snippet';
    workspaceMode = DbWorkspaceMode.sqlEditor;
    notifyListeners();
  }

  void formatActiveSql() {
    activeTab.sqlText = SqlEngine.formatSql(activeTab.sqlText);
    statusMessage = 'Formatted SQL query in ${activeTab.title}';
    notifyListeners();
  }

  QueryResult runSql(String sql, {String? connectionId}) {
    final connId = connectionId ?? activeConnectionId;
    final conn = connections.firstWhere(
      (c) => c.id == connId,
      orElse: () => activeConnection,
    );
    final schemas = _schemasByConnection[conn.id] ?? [];
    final result = SqlEngine.executeInMemory(sql, schemas);

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
    notifyListeners();
    return result;
  }

  void runActiveQuery() {
    final tab = activeTab;
    tab.isRunning = true;
    final res = runSql(tab.sqlText, connectionId: tab.connectionId);
    tab.lastResult = res;
    tab.isRunning = false;
    activeBottomTab = DbBottomTab.resultGrid;
    notifyListeners();
  }

  void explainActiveQuery() {
    final tab = activeTab;
    final raw = tab.sqlText.trim();
    final explainSql = raw.toUpperCase().startsWith('EXPLAIN')
        ? raw
        : 'EXPLAIN QUERY PLAN $raw';
    final res = runSql(explainSql, connectionId: tab.connectionId);
    tab.lastResult = QueryResult(
      columns: tab.lastResult?.columns ?? res.columns,
      rows: tab.lastResult?.rows ?? res.rows,
      affectedRows: res.affectedRows,
      executionTimeMs: res.executionTimeMs,
      explainPlan: res.explainPlan,
      executedSql: tab.sqlText,
    );
    activeBottomTab = DbBottomTab.executionPlan;
    statusMessage =
        'Explain Query Plan generated (${res.explainPlan.length} steps)';
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
    final key = '$activeConnectionId:${table.name}';
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
    final table = activeSchemas.firstWhere(
      (t) => t.name == tableName,
      orElse: () => selectedTable!,
    );
    if (rowIndex < 0 || rowIndex >= table.rows.length) return;
    _ensureTableSnapshot(table);

    final oldVal = table.rows[rowIndex][columnName];
    if ('$oldVal' == '$newValue') return;

    final editKey = '$tableName:$rowIndex:$columnName';
    final existing = pendingCellEdits[editKey];
    pendingCellEdits[editKey] = PendingCellEdit(
      tableName: tableName,
      rowIndex: rowIndex,
      columnName: columnName,
      oldValue: existing != null ? existing.oldValue : oldVal,
      newValue: newValue,
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

    if (pk != null) {
      pendingCellEdits['${table.name}:$rowIdx:$pk'] = PendingCellEdit(
        tableName: table.name,
        rowIndex: rowIdx,
        columnName: pk,
        oldValue: null,
        newValue: nextId,
      );
    }
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
    );
    statusMessage = 'Removed row from ${table.name} (pending commit)';
    notifyListeners();
  }

  void commitPendingChanges() {
    final count = pendingCellEdits.length;
    pendingCellEdits.clear();
    _tableSnapshots.clear();
    statusMessage =
        'COMMIT OK — $count change${count == 1 ? '' : 's'} persisted to ${activeConnection.name}';
    _log('[${activeConnection.name}] COMMIT TRANSACTION ($count changes)');
    notifyListeners();
  }

  void rollbackPendingChanges() {
    final count = pendingCellEdits.length;
    for (final entry in _tableSnapshots.entries) {
      final parts = entry.key.split(':');
      if (parts.length == 2) {
        final connId = parts[0];
        final tblName = parts[1];
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
    _log('[${activeConnection.name}] ROLLBACK TRANSACTION ($count changes reverted)');
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
    for (final path in paths) {
      final lower = path.toLowerCase();
      final file = File(path);
      if (!file.existsSync()) continue;

      if (lower.endsWith('.sql')) {
        final content = file.readAsStringSync();
        final fileName = path.split('/').last;
        newSqlTab(title: fileName, initialSql: content);
        runActiveQuery();
        statusMessage = 'Opened SQL script $fileName';
      } else if (lower.endsWith('.sqlite') ||
          lower.endsWith('.sqlite3') ||
          lower.endsWith('.db')) {
        final fileName = path.split('/').last;
        final connId = 'conn_${DateTime.now().millisecondsSinceEpoch}';
        final profile = DbConnectionProfile(
          id: connId,
          name: fileName,
          driver: DbDriverType.sqlite,
          databaseOrPath: path,
          isConnected: true,
        );
        var introspected = await SqlEngine.introspectSqliteFile(path);
        if (introspected.isEmpty) {
          introspected = _buildDefaultStarterSchema();
        }
        addConnection(profile, schemas: introspected);
        statusMessage =
            'Mounted SQLite database $fileName (${introspected.length} objects)';
      }
    }
    notifyListeners();
  }

  String exportResultAs(String format) {
    final res = activeTab.lastResult;
    if (res == null) return '';
    switch (format.toLowerCase()) {
      case 'csv':
        return SqlEngine.exportToCsv(res);
      case 'json':
        return SqlEngine.exportToJson(res);
      case 'sql':
        return SqlEngine.exportToSqlInserts(selectedTableName, res);
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

  void _seedInitialConnectionsAndSchemas() {
    final prodConn = DbConnectionProfile(
      id: 'conn_fyr_cloud',
      name: 'fyr_cloud_prod',
      driver: DbDriverType.sqlite,
      databaseOrPath: '~/.local/share/fyrdb/fyr_cloud.sqlite',
      username: 'fyr_admin',
      sslEnabled: true,
      colorTagHex: '#D040FF',
      isConnected: true,
    );

    final duckConn = DbConnectionProfile(
      id: 'conn_analytics_duckdb',
      name: 'analytics_warehouse',
      driver: DbDriverType.duckdb,
      databaseOrPath: '~/.local/share/fyrdb/telemetry_olap.duckdb',
      username: 'olap_reader',
      colorTagHex: '#FACC15',
      isConnected: true,
    );

    final pgConn = DbConnectionProfile(
      id: 'conn_staging_pg',
      name: 'staging_pg_cluster',
      driver: DbDriverType.postgres,
      host: '10.24.0.12',
      port: 5432,
      databaseOrPath: 'fyr_staging',
      username: 'postgres',
      sslEnabled: true,
      colorTagHex: '#60A5FA',
      isConnected: false,
    );

    connections.addAll([prodConn, duckConn, pgConn]);

    _schemasByConnection[prodConn.id] = _buildFyrCloudProdSchema();
    _schemasByConnection[duckConn.id] = _buildAnalyticsWarehouseSchema();
    _schemasByConnection[pgConn.id] = _buildStagingPostgresSchema();

    _log('Initialized fyrDB Engine v1.0 — 3 connections configured');
    _log('Connected to fyr_cloud_prod (SQLite 3 • 5 tables, 2 views, 6 indexes, 2 triggers)');
  }

  void _seedInitialTabs() {
    const tab1Sql = '''SELECT
  u.username,
  w.name AS workspace,
  w.region,
  d.service_name,
  d.image_tag,
  d.status,
  d.replicas,
  d.latency_ms
FROM deployments d
JOIN workspaces w ON d.workspace_id = w.id
JOIN users u ON w.owner_id = u.id
WHERE d.replicas >= 2
ORDER BY d.latency_ms ASC;''';

    const tab2Sql = '''SELECT
  u.username,
  u.role,
  a.action,
  a.ip_addr,
  a.severity,
  a.created_at
FROM audit_logs a
JOIN users u ON a.user_id = u.id
ORDER BY a.id DESC
LIMIT 8;''';

    const tab3Sql = '''SELECT
  status,
  COUNT(*) AS service_count,
  SUM(replicas) AS total_replicas,
  AVG(latency_ms) AS avg_latency_ms
FROM deployments
GROUP BY status
ORDER BY total_replicas DESC;''';

    final t1 = SqlQueryTab(
      id: 'tab_01',
      title: '01_active_clusters.sql',
      connectionId: 'conn_fyr_cloud',
      sqlText: tab1Sql,
    );
    final t2 = SqlQueryTab(
      id: 'tab_02',
      title: '02_user_audit_join.sql',
      connectionId: 'conn_fyr_cloud',
      sqlText: tab2Sql,
    );
    final t3 = SqlQueryTab(
      id: 'tab_03',
      title: '03_schema_metrics.sql',
      connectionId: 'conn_fyr_cloud',
      sqlText: tab3Sql,
    );

    openTabs.addAll([t1, t2, t3]);
    // Execute tab 1 immediately so the result grid & explain plan are populated on startup
    t1.lastResult = runSql(t1.sqlText, connectionId: t1.connectionId);
    t2.lastResult = SqlEngine.executeInMemory(
      t2.sqlText,
      _schemasByConnection['conn_fyr_cloud']!,
    );
    t3.lastResult = SqlEngine.executeInMemory(
      t3.sqlText,
      _schemasByConnection['conn_fyr_cloud']!,
    );
    activeTabIndex = 0;
  }

  List<DbTableSchema> _buildFyrCloudProdSchema() {
    final usersTable = DbTableSchema(
      name: 'users',
      schemaName: 'main',
      sizeBytes: 32768,
      erPosition: const Offset(36, 36),
      columns: const [
        DbColumnSchema(
          name: 'id',
          dataType: 'INTEGER',
          isPrimaryKey: true,
          isNullable: false,
          isUnique: true,
        ),
        DbColumnSchema(
          name: 'username',
          dataType: 'VARCHAR(64)',
          isNullable: false,
          isUnique: true,
        ),
        DbColumnSchema(
          name: 'email',
          dataType: 'VARCHAR(255)',
          isNullable: false,
          isUnique: true,
        ),
        DbColumnSchema(
          name: 'role',
          dataType: 'TEXT',
          isNullable: false,
          defaultValue: "'developer'",
        ),
        DbColumnSchema(
          name: 'plan_tier',
          dataType: 'TEXT',
          isNullable: false,
          defaultValue: "'pro'",
        ),
        DbColumnSchema(
          name: 'active',
          dataType: 'BOOLEAN',
          isNullable: false,
          defaultValue: '1',
        ),
        DbColumnSchema(
          name: 'created_at',
          dataType: 'TIMESTAMPTZ',
          isNullable: false,
        ),
      ],
      indexes: const [
        DbIndexSchema(
          name: 'idx_users_username',
          tableName: 'users',
          columns: ['username'],
          isUnique: true,
        ),
        DbIndexSchema(
          name: 'idx_users_role_tier',
          tableName: 'users',
          columns: ['role', 'plan_tier'],
        ),
      ],
      triggers: const [
        DbTriggerSchema(
          name: 'trg_users_audit_insert',
          tableName: 'users',
          timing: 'AFTER',
          event: 'INSERT',
          definitionSql:
              "CREATE TRIGGER trg_users_audit_insert AFTER INSERT ON users BEGIN INSERT INTO audit_logs (user_id, action, ip_addr, severity, created_at) VALUES (NEW.id, 'user.created', '127.0.0.1', 'INFO', CURRENT_TIMESTAMP); END;",
        ),
      ],
      rows: [
        {
          'id': 1,
          'username': 'archer',
          'email': 'archer@fyrde.io',
          'role': 'principal_architect',
          'plan_tier': 'enterprise',
          'active': 1,
          'created_at': '2026-01-10 08:15:00',
        },
        {
          'id': 2,
          'username': 'linnea',
          'email': 'linnea@fyrde.io',
          'role': 'sre_lead',
          'plan_tier': 'enterprise',
          'active': 1,
          'created_at': '2026-01-14 10:30:00',
        },
        {
          'id': 3,
          'username': 'soren',
          'email': 'soren@fyrde.io',
          'role': 'compositor_eng',
          'plan_tier': 'pro',
          'active': 1,
          'created_at': '2026-02-02 14:12:00',
        },
        {
          'id': 4,
          'username': 'freja',
          'email': 'freja@fyrde.io',
          'role': 'security_eng',
          'plan_tier': 'enterprise',
          'active': 1,
          'created_at': '2026-02-19 09:45:00',
        },
        {
          'id': 5,
          'username': 'kasper',
          'email': 'kasper@fyrde.io',
          'role': 'kernel_dev',
          'plan_tier': 'pro',
          'active': 1,
          'created_at': '2026-03-04 16:20:00',
        },
        {
          'id': 6,
          'username': 'astrid',
          'email': 'astrid@fyrde.io',
          'role': 'ml_infra',
          'plan_tier': 'enterprise',
          'active': 1,
          'created_at': '2026-03-21 11:05:00',
        },
        {
          'id': 7,
          'username': 'torben',
          'email': 'torben@fyrde.io',
          'role': 'qa_automation',
          'plan_tier': 'team',
          'active': 0,
          'created_at': '2026-04-08 13:50:00',
        },
        {
          'id': 8,
          'username': 'ingrid',
          'email': 'ingrid@fyrde.io',
          'role': 'data_platform',
          'plan_tier': 'pro',
          'active': 1,
          'created_at': '2026-04-18 17:40:00',
        },
      ],
    );

    final workspacesTable = DbTableSchema(
      name: 'workspaces',
      schemaName: 'main',
      sizeBytes: 24576,
      erPosition: const Offset(370, 36),
      columns: const [
        DbColumnSchema(
          name: 'id',
          dataType: 'INTEGER',
          isPrimaryKey: true,
          isNullable: false,
          isUnique: true,
        ),
        DbColumnSchema(
          name: 'owner_id',
          dataType: 'INTEGER',
          isNullable: false,
          foreignKeyTarget: 'users.id',
        ),
        DbColumnSchema(
          name: 'name',
          dataType: 'VARCHAR(128)',
          isNullable: false,
          isUnique: true,
        ),
        DbColumnSchema(
          name: 'region',
          dataType: 'TEXT',
          isNullable: false,
          defaultValue: "'eu-north-1'",
        ),
        DbColumnSchema(
          name: 'compositor',
          dataType: 'TEXT',
          isNullable: false,
          defaultValue: "'swayfx-1.4'",
        ),
        DbColumnSchema(
          name: 'ram_gb',
          dataType: 'INTEGER',
          isNullable: false,
          defaultValue: '32',
        ),
      ],
      indexes: const [
        DbIndexSchema(
          name: 'idx_workspaces_owner_id',
          tableName: 'workspaces',
          columns: ['owner_id'],
        ),
      ],
      rows: [
        {
          'id': 101,
          'owner_id': 1,
          'name': 'fyr-core-wayland',
          'region': 'eu-north-1',
          'compositor': 'swayfx-1.4',
          'ram_gb': 64,
        },
        {
          'id': 102,
          'owner_id': 2,
          'name': 'edge-mesh-control',
          'region': 'us-east-1',
          'compositor': 'swayfx-1.4',
          'ram_gb': 128,
        },
        {
          'id': 103,
          'owner_id': 3,
          'name': 'vulkan-shader-lab',
          'region': 'eu-central-1',
          'compositor': 'wlroots-0.18',
          'ram_gb': 64,
        },
        {
          'id': 104,
          'owner_id': 4,
          'name': 'zero-trust-vault',
          'region': 'eu-north-1',
          'compositor': 'swayfx-1.4',
          'ram_gb': 32,
        },
        {
          'id': 105,
          'owner_id': 6,
          'name': 'tensor-cluster-a100',
          'region': 'us-west-2',
          'compositor': 'headless-drm',
          'ram_gb': 256,
        },
        {
          'id': 106,
          'owner_id': 8,
          'name': 'duckdb-lakehouse',
          'region': 'ap-northeast-1',
          'compositor': 'swayfx-1.4',
          'ram_gb': 96,
        },
      ],
    );

    final deploymentsTable = DbTableSchema(
      name: 'deployments',
      schemaName: 'main',
      sizeBytes: 49152,
      erPosition: const Offset(704, 36),
      columns: const [
        DbColumnSchema(
          name: 'id',
          dataType: 'INTEGER',
          isPrimaryKey: true,
          isNullable: false,
          isUnique: true,
        ),
        DbColumnSchema(
          name: 'workspace_id',
          dataType: 'INTEGER',
          isNullable: false,
          foreignKeyTarget: 'workspaces.id',
        ),
        DbColumnSchema(
          name: 'service_name',
          dataType: 'VARCHAR(128)',
          isNullable: false,
        ),
        DbColumnSchema(
          name: 'image_tag',
          dataType: 'VARCHAR(64)',
          isNullable: false,
        ),
        DbColumnSchema(
          name: 'status',
          dataType: 'TEXT',
          isNullable: false,
          defaultValue: "'HEALTHY'",
        ),
        DbColumnSchema(
          name: 'replicas',
          dataType: 'INTEGER',
          isNullable: false,
          defaultValue: '2',
        ),
        DbColumnSchema(
          name: 'latency_ms',
          dataType: 'REAL',
          isNullable: false,
          defaultValue: '1.5',
        ),
      ],
      indexes: const [
        DbIndexSchema(
          name: 'idx_deployments_workspace_id',
          tableName: 'deployments',
          columns: ['workspace_id', 'status'],
        ),
      ],
      triggers: const [
        DbTriggerSchema(
          name: 'trg_deployments_replica_guard',
          tableName: 'deployments',
          timing: 'BEFORE',
          event: 'UPDATE',
          definitionSql:
              'CREATE TRIGGER trg_deployments_replica_guard BEFORE UPDATE ON deployments WHEN NEW.replicas < 0 BEGIN SELECT RAISE(ABORT, "Replicas cannot be negative"); END;',
        ),
      ],
      rows: [
        {
          'id': 501,
          'workspace_id': 101,
          'service_name': 'fyr-compositor-daemon',
          'image_tag': 'v2.4.0-vulkan',
          'status': 'HEALTHY',
          'replicas': 4,
          'latency_ms': 1.2,
        },
        {
          'id': 502,
          'workspace_id': 102,
          'service_name': 'envoy-mesh-ingress',
          'image_tag': 'v1.31.2-tls',
          'status': 'HEALTHY',
          'replicas': 6,
          'latency_ms': 1.8,
        },
        {
          'id': 503,
          'workspace_id': 105,
          'service_name': 'vllm-inference-router',
          'image_tag': 'v0.9.4-cuda12',
          'status': 'HEALTHY',
          'replicas': 8,
          'latency_ms': 2.4,
        },
        {
          'id': 504,
          'workspace_id': 104,
          'service_name': 'wireguard-kms-signer',
          'image_tag': 'v1.8.1-fips',
          'status': 'HEALTHY',
          'replicas': 3,
          'latency_ms': 2.9,
        },
        {
          'id': 505,
          'workspace_id': 106,
          'service_name': 'parquet-compactor',
          'image_tag': 'v3.2.0-avx512',
          'status': 'SYNCING',
          'replicas': 4,
          'latency_ms': 4.1,
        },
        {
          'id': 506,
          'workspace_id': 103,
          'service_name': 'spirv-shader-cache',
          'image_tag': 'v1.6.0-mesa',
          'status': 'HEALTHY',
          'replicas': 2,
          'latency_ms': 5.6,
        },
        {
          'id': 507,
          'workspace_id': 101,
          'service_name': 'pipewire-audio-bridge',
          'image_tag': 'v1.2.5-rt',
          'status': 'HEALTHY',
          'replicas': 2,
          'latency_ms': 6.3,
        },
        {
          'id': 508,
          'workspace_id': 102,
          'service_name': 'prometheus-tsdb-shard',
          'image_tag': 'v2.54.1',
          'status': 'DEGRADED',
          'replicas': 3,
          'latency_ms': 14.8,
        },
        {
          'id': 509,
          'workspace_id': 104,
          'service_name': 'oidc-session-broker',
          'image_tag': 'v4.0.2',
          'status': 'HEALTHY',
          'replicas': 1,
          'latency_ms': 3.5,
        },
        {
          'id': 510,
          'workspace_id': 106,
          'service_name': 'clickhouse-sink-worker',
          'image_tag': 'v24.8-lts',
          'status': 'SCALING',
          'replicas': 5,
          'latency_ms': 8.2,
        },
      ],
    );

    final apiKeysTable = DbTableSchema(
      name: 'api_keys',
      schemaName: 'main',
      sizeBytes: 16384,
      erPosition: const Offset(36, 310),
      columns: const [
        DbColumnSchema(
          name: 'id',
          dataType: 'INTEGER',
          isPrimaryKey: true,
          isNullable: false,
          isUnique: true,
        ),
        DbColumnSchema(
          name: 'user_id',
          dataType: 'INTEGER',
          isNullable: false,
          foreignKeyTarget: 'users.id',
        ),
        DbColumnSchema(
          name: 'key_prefix',
          dataType: 'VARCHAR(32)',
          isNullable: false,
          isUnique: true,
        ),
        DbColumnSchema(
          name: 'scopes',
          dataType: 'TEXT',
          isNullable: false,
        ),
        DbColumnSchema(
          name: 'last_used_at',
          dataType: 'TIMESTAMPTZ',
          isNullable: true,
        ),
      ],
      indexes: const [
        DbIndexSchema(
          name: 'idx_api_keys_prefix',
          tableName: 'api_keys',
          columns: ['key_prefix'],
          isUnique: true,
        ),
      ],
      rows: [
        {
          'id': 1,
          'user_id': 1,
          'key_prefix': 'fyr_live_98a7c1',
          'scopes': 'cluster:admin,db:write',
          'last_used_at': '2026-11-17 21:58:10',
        },
        {
          'id': 2,
          'user_id': 2,
          'key_prefix': 'fyr_live_44b2e9',
          'scopes': 'mesh:read,mesh:deploy',
          'last_used_at': '2026-11-17 21:40:02',
        },
        {
          'id': 3,
          'user_id': 3,
          'key_prefix': 'fyr_live_71d0f4',
          'scopes': 'shader:publish',
          'last_used_at': '2026-11-17 19:15:44',
        },
        {
          'id': 4,
          'user_id': 4,
          'key_prefix': 'fyr_sec_19f8a3',
          'scopes': 'kms:rotate,audit:read',
          'last_used_at': '2026-11-17 21:55:19',
        },
        {
          'id': 5,
          'user_id': 6,
          'key_prefix': 'fyr_gpu_63c5b8',
          'scopes': 'inference:invoke',
          'last_used_at': '2026-11-17 20:30:00',
        },
        {
          'id': 6,
          'user_id': 8,
          'key_prefix': 'fyr_olap_82e1d7',
          'scopes': 'warehouse:query',
          'last_used_at': null,
        },
      ],
    );

    final auditLogsTable = DbTableSchema(
      name: 'audit_logs',
      schemaName: 'main',
      sizeBytes: 65536,
      erPosition: const Offset(370, 310),
      columns: const [
        DbColumnSchema(
          name: 'id',
          dataType: 'BIGINT',
          isPrimaryKey: true,
          isNullable: false,
          isUnique: true,
        ),
        DbColumnSchema(
          name: 'user_id',
          dataType: 'INTEGER',
          isNullable: false,
          foreignKeyTarget: 'users.id',
        ),
        DbColumnSchema(
          name: 'action',
          dataType: 'VARCHAR(128)',
          isNullable: false,
        ),
        DbColumnSchema(
          name: 'ip_addr',
          dataType: 'VARCHAR(45)',
          isNullable: false,
        ),
        DbColumnSchema(
          name: 'severity',
          dataType: 'TEXT',
          isNullable: false,
          defaultValue: "'INFO'",
        ),
        DbColumnSchema(
          name: 'created_at',
          dataType: 'TIMESTAMPTZ',
          isNullable: false,
        ),
      ],
      indexes: const [
        DbIndexSchema(
          name: 'idx_audit_logs_user_created',
          tableName: 'audit_logs',
          columns: ['user_id', 'created_at'],
        ),
      ],
      rows: [
        {
          'id': 9001,
          'user_id': 1,
          'action': 'schema.migration.applied',
          'ip_addr': '10.24.0.4',
          'severity': 'INFO',
          'created_at': '2026-11-17 20:01:12',
        },
        {
          'id': 9002,
          'user_id': 2,
          'action': 'deployment.scaled.up',
          'ip_addr': '10.24.0.19',
          'severity': 'INFO',
          'created_at': '2026-11-17 20:14:35',
        },
        {
          'id': 9003,
          'user_id': 4,
          'action': 'kms.master_key.rotated',
          'ip_addr': '10.24.0.8',
          'severity': 'WARN',
          'created_at': '2026-11-17 20:32:09',
        },
        {
          'id': 9004,
          'user_id': 3,
          'action': 'vulkan.pipeline.compiled',
          'ip_addr': '10.24.1.15',
          'severity': 'INFO',
          'created_at': '2026-11-17 20:45:51',
        },
        {
          'id': 9005,
          'user_id': 6,
          'action': 'gpu.oom_guard.triggered',
          'ip_addr': '10.24.4.88',
          'severity': 'CRITICAL',
          'created_at': '2026-11-17 21:02:18',
        },
        {
          'id': 9006,
          'user_id': 8,
          'action': 'parquet.snapshot.exported',
          'ip_addr': '10.24.2.41',
          'severity': 'INFO',
          'created_at': '2026-11-17 21:11:04',
        },
        {
          'id': 9007,
          'user_id': 1,
          'action': 'sqlite.wal_checkpoint.run',
          'ip_addr': '10.24.0.4',
          'severity': 'INFO',
          'created_at': '2026-11-17 21:19:42',
        },
        {
          'id': 9008,
          'user_id': 5,
          'action': 'ebpf.probe.attached',
          'ip_addr': '10.24.0.77',
          'severity': 'WARN',
          'created_at': '2026-11-17 21:28:15',
        },
        {
          'id': 9009,
          'user_id': 2,
          'action': 'envoy.route_table.synced',
          'ip_addr': '10.24.0.19',
          'severity': 'INFO',
          'created_at': '2026-11-17 21:35:00',
        },
        {
          'id': 9010,
          'user_id': 4,
          'action': 'rbac.policy.verified',
          'ip_addr': '10.24.0.8',
          'severity': 'INFO',
          'created_at': '2026-11-17 21:44:27',
        },
        {
          'id': 9011,
          'user_id': 6,
          'action': 'tensor.weights.sharded',
          'ip_addr': '10.24.4.88',
          'severity': 'INFO',
          'created_at': '2026-11-17 21:51:09',
        },
        {
          'id': 9012,
          'user_id': 1,
          'action': 'db.index.analyzed',
          'ip_addr': '10.24.0.4',
          'severity': 'INFO',
          'created_at': '2026-11-17 21:59:01',
        },
      ],
    );

    final viewActiveDeployments = DbTableSchema(
      name: 'v_active_deployments',
      schemaName: 'main',
      isView: true,
      sizeBytes: 4096,
      erPosition: const Offset(704, 310),
      ddlSql: '''CREATE VIEW v_active_deployments AS
SELECT d.id, d.service_name, d.image_tag, d.status, d.replicas, d.latency_ms
FROM deployments d
WHERE d.status = 'HEALTHY';''',
      columns: const [
        DbColumnSchema(name: 'id', dataType: 'INTEGER', isPrimaryKey: true),
        DbColumnSchema(name: 'service_name', dataType: 'VARCHAR(128)'),
        DbColumnSchema(name: 'image_tag', dataType: 'VARCHAR(64)'),
        DbColumnSchema(name: 'status', dataType: 'TEXT'),
        DbColumnSchema(name: 'replicas', dataType: 'INTEGER'),
        DbColumnSchema(name: 'latency_ms', dataType: 'REAL'),
      ],
      rows: deploymentsTable.rows
          .where((r) => r['status'] == 'HEALTHY')
          .map((r) => Map<String, dynamic>.from(r))
          .toList(),
    );

    final viewUserWorkspaceUsage = DbTableSchema(
      name: 'v_user_workspace_usage',
      schemaName: 'main',
      isView: true,
      sizeBytes: 4096,
      erPosition: const Offset(704, 490),
      ddlSql: '''CREATE VIEW v_user_workspace_usage AS
SELECT u.username, w.name AS workspace, w.region, w.ram_gb
FROM workspaces w
JOIN users u ON w.owner_id = u.id;''',
      columns: const [
        DbColumnSchema(name: 'username', dataType: 'VARCHAR(64)'),
        DbColumnSchema(name: 'workspace', dataType: 'VARCHAR(128)'),
        DbColumnSchema(name: 'region', dataType: 'TEXT'),
        DbColumnSchema(name: 'ram_gb', dataType: 'INTEGER'),
      ],
      rows: [
        {
          'username': 'archer',
          'workspace': 'fyr-core-wayland',
          'region': 'eu-north-1',
          'ram_gb': 64,
        },
        {
          'username': 'linnea',
          'workspace': 'edge-mesh-control',
          'region': 'us-east-1',
          'ram_gb': 128,
        },
        {
          'username': 'soren',
          'workspace': 'vulkan-shader-lab',
          'region': 'eu-central-1',
          'ram_gb': 64,
        },
        {
          'username': 'freja',
          'workspace': 'zero-trust-vault',
          'region': 'eu-north-1',
          'ram_gb': 32,
        },
        {
          'username': 'astrid',
          'workspace': 'tensor-cluster-a100',
          'region': 'us-west-2',
          'ram_gb': 256,
        },
        {
          'username': 'ingrid',
          'workspace': 'duckdb-lakehouse',
          'region': 'ap-northeast-1',
          'ram_gb': 96,
        },
      ],
    );

    final all = [
      usersTable,
      workspacesTable,
      deploymentsTable,
      apiKeysTable,
      auditLogsTable,
      viewActiveDeployments,
      viewUserWorkspaceUsage,
    ];
    for (final t in all) {
      if (t.ddlSql.isEmpty) {
        t.ddlSql = SqlEngine.generateTableDdl(t);
      }
    }
    return all;
  }

  List<DbTableSchema> _buildAnalyticsWarehouseSchema() {
    final eventsDaily = DbTableSchema(
      name: 'events_daily',
      schemaName: 'analytics',
      sizeBytes: 131072,
      erPosition: const Offset(40, 40),
      columns: const [
        DbColumnSchema(
          name: 'day',
          dataType: 'TEXT',
          isPrimaryKey: true,
          isNullable: false,
        ),
        DbColumnSchema(
          name: 'region',
          dataType: 'TEXT',
          isNullable: false,
        ),
        DbColumnSchema(
          name: 'total_requests',
          dataType: 'BIGINT',
          isNullable: false,
        ),
        DbColumnSchema(
          name: 'p99_ms',
          dataType: 'REAL',
          isNullable: false,
        ),
      ],
      rows: [
        {
          'day': '2026-11-15',
          'region': 'eu-north-1',
          'total_requests': 14820900,
          'p99_ms': 4.2,
        },
        {
          'day': '2026-11-16',
          'region': 'eu-north-1',
          'total_requests': 16194200,
          'p99_ms': 3.9,
        },
        {
          'day': '2026-11-17',
          'region': 'us-east-1',
          'total_requests': 22410000,
          'p99_ms': 5.1,
        },
      ],
    );
    eventsDaily.ddlSql = SqlEngine.generateTableDdl(eventsDaily);
    return [eventsDaily];
  }

  List<DbTableSchema> _buildStagingPostgresSchema() {
    final tenants = DbTableSchema(
      name: 'tenants',
      schemaName: 'public',
      sizeBytes: 24576,
      erPosition: const Offset(40, 40),
      columns: const [
        DbColumnSchema(
          name: 'id',
          dataType: 'INTEGER',
          isPrimaryKey: true,
          isNullable: false,
        ),
        DbColumnSchema(
          name: 'slug',
          dataType: 'VARCHAR(64)',
          isNullable: false,
          isUnique: true,
        ),
        DbColumnSchema(
          name: 'mrr_usd',
          dataType: 'INTEGER',
          isNullable: false,
        ),
      ],
      rows: [
        {'id': 1, 'slug': 'nordic-robotics', 'mrr_usd': 12500},
        {'id': 2, 'slug': 'krono-aerospace', 'mrr_usd': 28000},
        {'id': 3, 'slug': 'valkyrie-bio', 'mrr_usd': 9400},
      ],
    );
    tenants.ddlSql = SqlEngine.generateTableDdl(tenants);
    return [tenants];
  }

  List<DbTableSchema> _buildDefaultStarterSchema() {
    final items = DbTableSchema(
      name: 'records',
      schemaName: 'main',
      columns: const [
        DbColumnSchema(
          name: 'id',
          dataType: 'INTEGER',
          isPrimaryKey: true,
          isNullable: false,
        ),
        DbColumnSchema(
          name: 'name',
          dataType: 'TEXT',
          isNullable: false,
        ),
        DbColumnSchema(
          name: 'value',
          dataType: 'REAL',
          isNullable: true,
        ),
      ],
      rows: [
        {'id': 1, 'name': 'alpha', 'value': 42.5},
        {'id': 2, 'name': 'beta', 'value': 99.0},
      ],
    );
    items.ddlSql = SqlEngine.generateTableDdl(items);
    return [items];
  }
}
