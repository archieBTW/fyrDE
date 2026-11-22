import 'package:flutter/material.dart';

enum DbDriverType {
  sqlite(
    label: 'SQLite 3',
    shortTag: 'SQLITE',
    defaultPort: 0,
    cliBinary: 'sqlite3',
    badgeColor: Color(0xFF38BDF8),
    icon: Icons.insert_drive_file_rounded,
    hint: 'Local .db / .sqlite file',
    description:
        'Embedded serverless SQL database stored in a single local file. Open existing or create new.',
  ),
  postgres(
    label: 'PostgreSQL',
    shortTag: 'PGSQL',
    defaultPort: 5432,
    cliBinary: 'psql',
    badgeColor: Color(0xFF60A5FA),
    icon: Icons.dns_rounded,
    hint: 'Default port 5432',
    description:
        'Advanced open-source relational database with full ACID compliance, JSONB, and extensions.',
  ),
  mysql(
    label: 'MySQL / MariaDB',
    shortTag: 'MYSQL',
    defaultPort: 3306,
    cliBinary: 'mysql',
    badgeColor: Color(0xFFF59E0B),
    icon: Icons.storage_rounded,
    hint: 'Default port 3306',
    description:
        'Widely deployed relational database engine for web backends and transactional workloads.',
  ),
  mariadb(
    label: 'MariaDB',
    shortTag: 'MARIADB',
    defaultPort: 3306,
    cliBinary: 'mariadb',
    badgeColor: Color(0xFFEC4899),
    icon: Icons.table_view_rounded,
    hint: 'Default port 3306',
    description:
        'Community-developed, MySQL-compatible relational database server.',
  ),
  duckdb(
    label: 'DuckDB',
    shortTag: 'DUCKDB',
    defaultPort: 0,
    cliBinary: 'duckdb',
    badgeColor: Color(0xFFFACC15),
    icon: Icons.analytics_rounded,
    hint: 'Local .duckdb file',
    description:
        'High-performance in-process analytical (OLAP) SQL engine for local files and Parquet.',
  ),
  redis(
    label: 'Redis',
    shortTag: 'REDIS',
    defaultPort: 6379,
    cliBinary: 'redis-cli',
    badgeColor: Color(0xFFF87171),
    icon: Icons.bolt_rounded,
    hint: 'Default port 6379',
    description:
        'In-memory key-value data store for caching, sessions, streams, and real-time analytics.',
  ),
  clickhouse(
    label: 'ClickHouse',
    shortTag: 'CH',
    defaultPort: 8123,
    cliBinary: 'clickhouse-client',
    badgeColor: Color(0xFFA78BFA),
    icon: Icons.speed_rounded,
    hint: 'Default port 8123',
    description:
        'Column-oriented OLAP database management system for real-time analytical queries.',
  );

  final String label;
  final String shortTag;
  final int defaultPort;
  final String cliBinary;
  final Color badgeColor;
  final IconData icon;
  final String hint;
  final String description;

  const DbDriverType({
    required this.label,
    required this.shortTag,
    required this.defaultPort,
    required this.cliBinary,
    required this.badgeColor,
    required this.icon,
    required this.hint,
    required this.description,
  });

  bool get isFileBased =>
      this == DbDriverType.sqlite || this == DbDriverType.duckdb;

  String get defaultUsername {
    switch (this) {
      case DbDriverType.postgres:
        return 'postgres';
      case DbDriverType.mysql:
      case DbDriverType.mariadb:
        return 'root';
      case DbDriverType.redis:
        return '';
      case DbDriverType.clickhouse:
        return 'default';
      case DbDriverType.sqlite:
      case DbDriverType.duckdb:
        return '';
    }
  }

  static DbDriverType fromName(String name) {
    for (final d in DbDriverType.values) {
      if (d.name == name) return d;
    }
    return DbDriverType.sqlite;
  }
}

enum DbWorkspaceMode {
  sqlEditor('SQL Editor', Icons.code_rounded),
  dataGrid('Data Grid', Icons.grid_on_rounded),
  structureDdl('Table Structure & DDL', Icons.account_tree_rounded),
  erDiagram('ER Diagram', Icons.hub_rounded);

  final String label;
  final IconData icon;
  const DbWorkspaceMode(this.label, this.icon);
}

enum DbBottomTab {
  resultGrid('Result Grid', Icons.table_chart_rounded),
  executionPlan('Execution Plan', Icons.schema_rounded),
  queryHistory('Query History', Icons.history_rounded),
  executionLog('Execution Log', Icons.terminal_rounded);

  final String label;
  final IconData icon;
  const DbBottomTab(this.label, this.icon);
}

class ConnectionTestResult {
  final bool success;
  final double latencyMs;
  final String message;
  final String? details;
  final bool cliAvailable;

  const ConnectionTestResult({
    required this.success,
    required this.latencyMs,
    required this.message,
    this.details,
    this.cliAvailable = false,
  });
}

class ParsedConnectionUri {
  final DbDriverType? driver;
  final String? host;
  final int? port;
  final String? database;
  final String? username;
  final String? password;
  final bool? sslEnabled;

  const ParsedConnectionUri({
    this.driver,
    this.host,
    this.port,
    this.database,
    this.username,
    this.password,
    this.sslEnabled,
  });
}

class DbConnectionProfile {
  final String id;
  String name;
  DbDriverType driver;
  String host;
  int port;
  String databaseOrPath;
  String username;
  /// Kept in memory for the current session only; never written to connections.json.
  String? password;
  bool sslEnabled;
  bool readOnly;
  String colorTagHex;
  bool isConnected;

  DbConnectionProfile({
    required this.id,
    required this.name,
    required this.driver,
    this.host = 'localhost',
    int? port,
    required this.databaseOrPath,
    this.username = '',
    this.password,
    this.sslEnabled = false,
    this.readOnly = false,
    this.colorTagHex = '#D040FF',
    this.isConnected = false,
  }) : port = port ?? driver.defaultPort;

  String get endpointSummary {
    if (driver.isFileBased) {
      return '${driver.label} • $databaseOrPath';
    }
    final dbSuffix = databaseOrPath.isNotEmpty ? '/$databaseOrPath' : '';
    return '${driver.label} • $host:$port$dbSuffix';
  }

  /// Serializes connection metadata to JSON (intentionally excludes raw passwords).
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'driver': driver.name,
      'host': host,
      'port': port,
      'databaseOrPath': databaseOrPath,
      'username': username,
      'sslEnabled': sslEnabled,
      'readOnly': readOnly,
      'colorTagHex': colorTagHex,
    };
  }

  factory DbConnectionProfile.fromJson(Map<String, dynamic> json) {
    final driver = DbDriverType.fromName(json['driver']?.toString() ?? 'sqlite');
    return DbConnectionProfile(
      id: json['id']?.toString() ??
          'conn_${DateTime.now().microsecondsSinceEpoch}',
      name: json['name']?.toString() ?? 'Untitled Connection',
      driver: driver,
      host: json['host']?.toString() ?? 'localhost',
      port: json['port'] is int
          ? json['port'] as int
          : int.tryParse(json['port']?.toString() ?? '') ?? driver.defaultPort,
      databaseOrPath: json['databaseOrPath']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      sslEnabled: json['sslEnabled'] == true,
      readOnly: json['readOnly'] == true,
      colorTagHex: json['colorTagHex']?.toString() ?? '#D040FF',
      isConnected: false,
    );
  }

  DbConnectionProfile copyWith({
    String? id,
    String? name,
    DbDriverType? driver,
    String? host,
    int? port,
    String? databaseOrPath,
    String? username,
    String? password,
    bool? sslEnabled,
    bool? readOnly,
    String? colorTagHex,
    bool? isConnected,
  }) {
    return DbConnectionProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      driver: driver ?? this.driver,
      host: host ?? this.host,
      port: port ?? this.port,
      databaseOrPath: databaseOrPath ?? this.databaseOrPath,
      username: username ?? this.username,
      password: password ?? this.password,
      sslEnabled: sslEnabled ?? this.sslEnabled,
      readOnly: readOnly ?? this.readOnly,
      colorTagHex: colorTagHex ?? this.colorTagHex,
      isConnected: isConnected ?? this.isConnected,
    );
  }
}

class DbColumnSchema {
  final String name;
  final String dataType;
  final bool isPrimaryKey;
  final bool isNullable;
  final bool isUnique;
  final String? defaultValue;
  final String? foreignKeyTarget; // e.g., 'users.id'

  const DbColumnSchema({
    required this.name,
    required this.dataType,
    this.isPrimaryKey = false,
    this.isNullable = true,
    this.isUnique = false,
    this.defaultValue,
    this.foreignKeyTarget,
  });

  bool get isForeignKey =>
      foreignKeyTarget != null && foreignKeyTarget!.trim().isNotEmpty;

  String? get foreignKeyTable {
    if (!isForeignKey) return null;
    final parts = foreignKeyTarget!.split('.');
    return parts.first.trim();
  }

  String? get foreignKeyColumn {
    if (!isForeignKey) return null;
    final parts = foreignKeyTarget!.split('.');
    return parts.length > 1 ? parts[1].trim() : 'id';
  }
}

class DbIndexSchema {
  final String name;
  final String tableName;
  final List<String> columns;
  final bool isUnique;

  const DbIndexSchema({
    required this.name,
    required this.tableName,
    required this.columns,
    this.isUnique = false,
  });
}

class DbTriggerSchema {
  final String name;
  final String tableName;
  final String timing; // 'BEFORE' or 'AFTER'
  final String event; // 'INSERT', 'UPDATE', 'DELETE'
  final String definitionSql;

  const DbTriggerSchema({
    required this.name,
    required this.tableName,
    required this.timing,
    required this.event,
    required this.definitionSql,
  });
}

class DbTableSchema {
  final String name;
  final String schemaName;
  final bool isView;
  int rowCount;
  int sizeBytes;
  final List<DbColumnSchema> columns;
  final List<DbIndexSchema> indexes;
  final List<DbTriggerSchema> triggers;
  String ddlSql;
  final List<Map<String, dynamic>> rows;
  Offset erPosition;

  DbTableSchema({
    required this.name,
    this.schemaName = 'public',
    this.isView = false,
    int? rowCount,
    this.sizeBytes = 16384,
    required this.columns,
    this.indexes = const [],
    this.triggers = const [],
    this.ddlSql = '',
    List<Map<String, dynamic>>? rows,
    this.erPosition = const Offset(40, 40),
  })  : rows = rows ?? [],
        rowCount = rowCount ?? (rows?.length ?? 0);

  String? get primaryKeyColumn {
    for (final col in columns) {
      if (col.isPrimaryKey) return col.name;
    }
    return columns.isNotEmpty ? columns.first.name : null;
  }

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

class QueryResult {
  final List<String> columns;
  final List<Map<String, dynamic>> rows;
  final int affectedRows;
  final double executionTimeMs;
  final List<String> explainPlan;
  final String? error;
  final String executedSql;
  final DateTime executedAt;

  QueryResult({
    required this.columns,
    required this.rows,
    this.affectedRows = 0,
    required this.executionTimeMs,
    this.explainPlan = const [],
    this.error,
    required this.executedSql,
    DateTime? executedAt,
  }) : executedAt = executedAt ?? DateTime.now();

  bool get isSuccess => error == null;
}

class SqlQueryTab {
  final String id;
  String title;
  String connectionId;
  String sqlText;
  QueryResult? lastResult;
  bool isRunning;

  SqlQueryTab({
    required this.id,
    required this.title,
    required this.connectionId,
    required this.sqlText,
    this.lastResult,
    this.isRunning = false,
  });
}

class QueryHistoryEntry {
  final String id;
  final String connectionName;
  final String sql;
  final double durationMs;
  final int rowCount;
  final bool isSuccess;
  final DateTime timestamp;

  QueryHistoryEntry({
    required this.id,
    required this.connectionName,
    required this.sql,
    required this.durationMs,
    required this.rowCount,
    required this.isSuccess,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
