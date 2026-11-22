import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/db_models.dart';

class SqlEngine {
  static String? _sqliteCliPathCache;
  static bool _sqliteCliChecked = false;

  /// Expands leading `~/` to the current user's HOME directory.
  static String resolvePath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed == '~') {
      return Platform.environment['HOME'] ?? trimmed;
    }
    if (trimmed.startsWith('~/')) {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return '$home${trimmed.substring(1)}';
      }
    }
    return trimmed;
  }

  /// Searches standard Linux binary paths and PATH for a CLI executable.
  static String? findCliBinary(String binaryName) {
    final candidates = <String>[
      '/usr/bin/$binaryName',
      '/usr/local/bin/$binaryName',
      '/bin/$binaryName',
    ];
    final pathEnv = Platform.environment['PATH'];
    if (pathEnv != null && pathEnv.isNotEmpty) {
      for (final dir in pathEnv.split(':')) {
        if (dir.isNotEmpty) {
          candidates.add('$dir/$binaryName');
        }
      }
    }
    for (final candidate in candidates) {
      try {
        if (File(candidate).existsSync()) {
          return candidate;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Path to the `sqlite3` CLI executable on the host system, if installed.
  static String? get sqliteCliPath {
    if (!_sqliteCliChecked) {
      _sqliteCliChecked = true;
      _sqliteCliPathCache = findCliBinary('sqlite3');
    }
    return _sqliteCliPathCache;
  }

  /// Checks whether `sqlite3` CLI is available on the host system.
  static bool get hasSqliteCli => sqliteCliPath != null;

  /// Parses a standard database connection URI such as:
  /// `postgres://user:pass@host:5432/dbname?sslmode=require`
  /// `mysql://user:pass@host:3306/dbname`
  /// `redis://:pass@host:6379/0`
  static ParsedConnectionUri? parseConnectionUri(String rawUri) {
    final trimmed = rawUri.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.scheme.isEmpty) return null;

    final scheme = uri.scheme.toLowerCase();
    DbDriverType? driver;
    bool? ssl;

    switch (scheme) {
      case 'postgres':
      case 'postgresql':
        driver = DbDriverType.postgres;
        break;
      case 'mysql':
        driver = DbDriverType.mysql;
        break;
      case 'mariadb':
        driver = DbDriverType.mariadb;
        break;
      case 'redis':
        driver = DbDriverType.redis;
        break;
      case 'rediss':
        driver = DbDriverType.redis;
        ssl = true;
        break;
      case 'clickhouse':
      case 'clickhouses':
        driver = DbDriverType.clickhouse;
        if (scheme == 'clickhouses') ssl = true;
        break;
      case 'sqlite':
      case 'sqlite3':
        driver = DbDriverType.sqlite;
        break;
      case 'duckdb':
        driver = DbDriverType.duckdb;
        break;
      default:
        return null;
    }

    if (driver.isFileBased) {
      final filePath = uri.path;
      return ParsedConnectionUri(
        driver: driver,
        database: filePath.isNotEmpty ? filePath : null,
      );
    }

    String? username;
    String? password;
    if (uri.userInfo.isNotEmpty) {
      final colonIdx = uri.userInfo.indexOf(':');
      if (colonIdx >= 0) {
        username = Uri.decodeComponent(uri.userInfo.substring(0, colonIdx));
        password = Uri.decodeComponent(uri.userInfo.substring(colonIdx + 1));
      } else {
        username = Uri.decodeComponent(uri.userInfo);
      }
    }

    final dbPath = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    final sslMode = (uri.queryParameters['sslmode'] ??
            uri.queryParameters['ssl'] ??
            uri.queryParameters['tls'] ??
            '')
        .toLowerCase();
    if (sslMode == 'require' ||
        sslMode == 'verify-ca' ||
        sslMode == 'verify-full' ||
        sslMode == 'true' ||
        sslMode == '1') {
      ssl = true;
    } else if (sslMode == 'disable' || sslMode == 'false' || sslMode == '0') {
      ssl = false;
    }

    return ParsedConnectionUri(
      driver: driver,
      host: uri.host.isNotEmpty ? uri.host : null,
      port: uri.hasPort ? uri.port : driver.defaultPort,
      database: dbPath.isNotEmpty ? dbPath : null,
      username: (username != null && username.isNotEmpty) ? username : null,
      password: (password != null && password.isNotEmpty) ? password : null,
      sslEnabled: ssl,
    );
  }

  /// Creates a new valid empty SQLite 3 database file on disk.
  static Future<bool> createSqliteFile(String rawPath) async {
    final filePath = resolvePath(rawPath);
    if (filePath.isEmpty || filePath == ':memory:') return false;
    try {
      final file = File(filePath);
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      final cli = sqliteCliPath;
      if (cli != null) {
        final res = await Process.run(cli, [
          filePath,
          'PRAGMA journal_mode = WAL; VACUUM;',
        ]);
        return res.exitCode == 0 && file.existsSync();
      }
      // Fallback: create empty file so it exists on disk even without sqlite3 CLI
      if (!file.existsSync()) {
        file.createSync(recursive: true);
      }
      return file.existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Creates a new DuckDB file on disk when `duckdb` CLI is available.
  static Future<bool> createDuckDbFile(String rawPath) async {
    final filePath = resolvePath(rawPath);
    if (filePath.isEmpty || filePath == ':memory:') return false;
    try {
      final file = File(filePath);
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      final cli = findCliBinary('duckdb');
      if (cli != null) {
        final res = await Process.run(cli, [filePath, '-c', 'SELECT 1;']);
        return res.exitCode == 0 && file.existsSync();
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Runs a real connectivity & diagnostic check for the given connection profile.
  static Future<ConnectionTestResult> testConnection(
    DbConnectionProfile profile, {
    bool createIfMissing = false,
  }) async {
    final sw = Stopwatch()..start();

    if (profile.driver == DbDriverType.sqlite) {
      final raw = profile.databaseOrPath.trim();
      if (raw.isEmpty) {
        sw.stop();
        return ConnectionTestResult(
          success: false,
          latencyMs: sw.elapsedMicroseconds / 1000.0,
          message: 'Database file path is required.',
          cliAvailable: hasSqliteCli,
        );
      }
      if (raw == ':memory:') {
        sw.stop();
        return ConnectionTestResult(
          success: true,
          latencyMs: sw.elapsedMicroseconds / 1000.0,
          message: 'In-memory SQLite workspace ready.',
          details: 'Data will live in memory for the current session.',
          cliAvailable: hasSqliteCli,
        );
      }

      final resolved = resolvePath(raw);
      if (Directory(resolved).existsSync()) {
        sw.stop();
        return ConnectionTestResult(
          success: false,
          latencyMs: sw.elapsedMicroseconds / 1000.0,
          message: 'Path points to a directory, not a database file.',
          details: resolved,
          cliAvailable: hasSqliteCli,
        );
      }

      final file = File(resolved);
      if (!file.existsSync()) {
        sw.stop();
        if (createIfMissing) {
          final parentExists = file.parent.existsSync();
          return ConnectionTestResult(
            success: true,
            latencyMs: sw.elapsedMicroseconds / 1000.0,
            message: 'Ready to create new SQLite database.',
            details: parentExists
                ? 'Will initialize $resolved${hasSqliteCli ? ' via sqlite3 CLI' : ''}.'
                : 'Parent folder ${file.parent.path} will be created automatically.',
            cliAvailable: hasSqliteCli,
          );
        }
        return ConnectionTestResult(
          success: false,
          latencyMs: sw.elapsedMicroseconds / 1000.0,
          message: 'SQLite file not found.',
          details:
              'File "$resolved" does not exist. Choose an existing file or use "Create New File".',
          cliAvailable: hasSqliteCli,
        );
      }

      // Existing file — verify header & optionally query version via sqlite3 CLI
      try {
        final len = file.lengthSync();
        if (len >= 16) {
          final raf = file.openSync(mode: FileMode.read);
          try {
            final header = raf.readSync(16);
            final headerStr = ascii.decode(header, allowInvalid: true);
            if (!headerStr.startsWith('SQLite format 3')) {
              sw.stop();
              return ConnectionTestResult(
                success: false,
                latencyMs: sw.elapsedMicroseconds / 1000.0,
                message: 'File is not a valid SQLite 3 database.',
                details: 'Header signature mismatch in $resolved.',
                cliAvailable: hasSqliteCli,
              );
            }
          } finally {
            raf.closeSync();
          }
        }

        if (hasSqliteCli) {
          final verRes = await executeOnSqliteFile(
            resolved,
            "SELECT sqlite_version() AS version, (SELECT COUNT(*) FROM sqlite_master WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%') AS objects;",
          );
          sw.stop();
          if (!verRes.isSuccess) {
            return ConnectionTestResult(
              success: false,
              latencyMs: sw.elapsedMicroseconds / 1000.0,
              message: 'SQLite integrity check failed.',
              details: verRes.error,
              cliAvailable: true,
            );
          }
          final version = verRes.rows.isNotEmpty
              ? verRes.rows.first['version']?.toString() ?? '3'
              : '3';
          final objects = verRes.rows.isNotEmpty
              ? verRes.rows.first['objects']?.toString() ?? '0'
              : '0';
          return ConnectionTestResult(
            success: true,
            latencyMs: sw.elapsedMicroseconds / 1000.0,
            message: 'SQLite $version ready — $objects schema objects found.',
            details: '$resolved (${_formatFileSize(len)})',
            cliAvailable: true,
          );
        }

        sw.stop();
        return ConnectionTestResult(
          success: true,
          latencyMs: sw.elapsedMicroseconds / 1000.0,
          message: 'SQLite file verified (${_formatFileSize(len)}).',
          details:
              'Note: sqlite3 CLI was not found on PATH; install sqlite3 for full disk query execution.',
          cliAvailable: false,
        );
      } catch (e) {
        sw.stop();
        return ConnectionTestResult(
          success: false,
          latencyMs: sw.elapsedMicroseconds / 1000.0,
          message: 'Cannot read SQLite file.',
          details: e.toString(),
          cliAvailable: hasSqliteCli,
        );
      }
    }

    if (profile.driver == DbDriverType.duckdb) {
      final raw = profile.databaseOrPath.trim();
      final cli = findCliBinary('duckdb');
      if (raw.isEmpty) {
        sw.stop();
        return ConnectionTestResult(
          success: false,
          latencyMs: sw.elapsedMicroseconds / 1000.0,
          message: 'DuckDB file path is required.',
          cliAvailable: cli != null,
        );
      }
      final resolved = resolvePath(raw);
      final file = File(resolved);
      if (!file.existsSync() && !createIfMissing) {
        sw.stop();
        return ConnectionTestResult(
          success: false,
          latencyMs: sw.elapsedMicroseconds / 1000.0,
          message: 'DuckDB file not found: $resolved',
          details: 'Browse for an existing .duckdb file or use "Create New File".',
          cliAvailable: cli != null,
        );
      }
      if (cli == null) {
        sw.stop();
        return ConnectionTestResult(
          success: false,
          latencyMs: sw.elapsedMicroseconds / 1000.0,
          message: 'DuckDB CLI ("duckdb") not installed on this system.',
          details:
              'Install the duckdb CLI binary on PATH to query DuckDB files.',
          cliAvailable: false,
        );
      }
      if (file.existsSync()) {
        final res = await Process.run(cli, [resolved, '-c', 'SELECT version();'])
            .timeout(const Duration(seconds: 5));
        sw.stop();
        if (res.exitCode != 0) {
          return ConnectionTestResult(
            success: false,
            latencyMs: sw.elapsedMicroseconds / 1000.0,
            message: 'DuckDB failed to open database.',
            details: (res.stderr as String).trim(),
            cliAvailable: true,
          );
        }
        return ConnectionTestResult(
          success: true,
          latencyMs: sw.elapsedMicroseconds / 1000.0,
          message: 'DuckDB connection verified.',
          details: resolved,
          cliAvailable: true,
        );
      }
      sw.stop();
      return ConnectionTestResult(
        success: true,
        latencyMs: sw.elapsedMicroseconds / 1000.0,
        message: 'Ready to create new DuckDB file.',
        details: '$resolved (duckdb CLI detected)',
        cliAvailable: true,
      );
    }

    // Remote TCP database engines (PostgreSQL, MySQL/MariaDB, Redis, ClickHouse)
    final host = profile.host.trim();
    final port = profile.port;
    if (host.isEmpty) {
      sw.stop();
      return const ConnectionTestResult(
        success: false,
        latencyMs: 0,
        message: 'Host is required.',
      );
    }
    if (port <= 0 || port > 65535) {
      sw.stop();
      return const ConnectionTestResult(
        success: false,
        latencyMs: 0,
        message: 'Port must be between 1 and 65535.',
      );
    }

    final cliBin = _resolveDriverCli(profile.driver);
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 4),
      );
      socket.destroy();
      sw.stop();
      final tcpMs = sw.elapsedMicroseconds / 1000.0;

      if (cliBin == null) {
        return ConnectionTestResult(
          success: true,
          latencyMs: tcpMs,
          message:
              'TCP reachable at $host:$port (${tcpMs.toStringAsFixed(1)} ms).',
          details:
              'Note: "${profile.driver.cliBinary}" CLI is not installed on PATH. Install it to execute queries from fyrDB.',
          cliAvailable: false,
        );
      }

      // Attempt live protocol/auth ping via CLI when available
      final pingSql = profile.driver == DbDriverType.redis ? 'PING' : 'SELECT 1;';
      final pingRes = await executeOnProfile(profile, pingSql);
      if (pingRes.isSuccess) {
        return ConnectionTestResult(
          success: true,
          latencyMs: pingRes.executionTimeMs,
          message:
              'Connected to ${profile.driver.label} at $host:$port (${tcpMs.toStringAsFixed(1)} ms TCP).',
          details: 'Verified via ${profile.driver.cliBinary} CLI.',
          cliAvailable: true,
        );
      } else {
        return ConnectionTestResult(
          success: false,
          latencyMs: tcpMs,
          message:
              'TCP port $port is open (${tcpMs.toStringAsFixed(1)} ms), but server rejected query.',
          details: pingRes.error,
          cliAvailable: true,
        );
      }
    } on SocketException catch (e) {
      sw.stop();
      return ConnectionTestResult(
        success: false,
        latencyMs: sw.elapsedMicroseconds / 1000.0,
        message: 'Could not reach $host:$port.',
        details:
            '${e.message}${e.osError != null ? ' (${e.osError!.message})' : ''}. Check host, port, firewall, and ensure ${profile.driver.label} is running.',
        cliAvailable: cliBin != null,
      );
    } catch (e) {
      sw.stop();
      return ConnectionTestResult(
        success: false,
        latencyMs: sw.elapsedMicroseconds / 1000.0,
        message: 'Connection test failed for $host:$port.',
        details: e.toString(),
        cliAvailable: cliBin != null,
      );
    }
  }

  static String? _resolveDriverCli(DbDriverType driver) {
    final primary = findCliBinary(driver.cliBinary);
    if (primary != null) return primary;
    if (driver == DbDriverType.mysql) {
      return findCliBinary('mariadb');
    }
    if (driver == DbDriverType.mariadb) {
      return findCliBinary('mysql');
    }
    return null;
  }

  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  /// Builds the non-interactive CLI invocation for any supported database driver.
  static List<String> buildCliCommand(
    DbConnectionProfile profile,
    String sql,
  ) {
    switch (profile.driver) {
      case DbDriverType.sqlite:
        return [
          sqliteCliPath ?? 'sqlite3',
          '-json',
          resolvePath(profile.databaseOrPath),
          sql,
        ];
      case DbDriverType.postgres:
        return [
          _resolveDriverCli(DbDriverType.postgres) ?? 'psql',
          '-h',
          profile.host,
          '-p',
          '${profile.port}',
          if (profile.username.isNotEmpty) ...['-U', profile.username],
          if (profile.databaseOrPath.isNotEmpty) ...[
            '-d',
            profile.databaseOrPath,
          ],
          '-v',
          'ON_ERROR_STOP=1',
          '--csv',
          '-c',
          sql,
        ];
      case DbDriverType.mysql:
      case DbDriverType.mariadb:
        return [
          _resolveDriverCli(profile.driver) ?? profile.driver.cliBinary,
          '-h',
          profile.host,
          '-P',
          '${profile.port}',
          if (profile.username.isNotEmpty) ...['-u', profile.username],
          if (profile.databaseOrPath.isNotEmpty) ...[
            '-D',
            profile.databaseOrPath,
          ],
          '--batch',
          '-e',
          sql,
        ];
      case DbDriverType.duckdb:
        return [
          _resolveDriverCli(DbDriverType.duckdb) ?? 'duckdb',
          '-json',
          resolvePath(profile.databaseOrPath),
          '-c',
          sql,
        ];
      case DbDriverType.redis:
        return [
          _resolveDriverCli(DbDriverType.redis) ?? 'redis-cli',
          '-h',
          profile.host,
          '-p',
          '${profile.port}',
          if (profile.databaseOrPath.isNotEmpty &&
              int.tryParse(profile.databaseOrPath) != null) ...[
            '-n',
            profile.databaseOrPath,
          ],
          if (profile.sslEnabled) '--tls',
          ...sql.trim().split(RegExp(r'\s+')),
        ];
      case DbDriverType.clickhouse:
        return [
          _resolveDriverCli(DbDriverType.clickhouse) ?? 'clickhouse-client',
          '--host',
          profile.host,
          '--port',
          '${profile.port}',
          if (profile.username.isNotEmpty) ...['--user', profile.username],
          if (profile.databaseOrPath.isNotEmpty) ...[
            '--database',
            profile.databaseOrPath,
          ],
          '--format',
          'JSONEachRow',
          '--query',
          sql,
        ];
    }
  }

  /// Executes a real statement against a live connection profile via its driver CLI.
  /// Never returns fake/mock rows when the driver or server is unavailable.
  static Future<QueryResult> executeOnProfile(
    DbConnectionProfile profile,
    String sql,
  ) async {
    final trimmed = _stripSqlComments(sql).trim();
    if (trimmed.isEmpty) {
      return QueryResult(
        columns: const [],
        rows: const [],
        executionTimeMs: 0.1,
        error: 'Empty SQL query.',
        executedSql: sql,
      );
    }

    if (profile.driver == DbDriverType.sqlite) {
      return executeOnSqliteFile(resolvePath(profile.databaseOrPath), sql);
    }

    final cli = _resolveDriverCli(profile.driver);
    if (cli == null) {
      return QueryResult(
        columns: const [],
        rows: const [],
        executionTimeMs: 0.1,
        error:
            'CLI driver "${profile.driver.cliBinary}" is not installed on this system. Install it to execute queries against ${profile.driver.label}.',
        executedSql: sql,
      );
    }

    final sw = Stopwatch()..start();
    final cmd = buildCliCommand(profile, trimmed);
    final env = Map<String, String>.from(Platform.environment);
    if (profile.driver == DbDriverType.postgres) {
      if (profile.password != null && profile.password!.isNotEmpty) {
        env['PGPASSWORD'] = profile.password!;
      }
      env['PGCONNECT_TIMEOUT'] = '5';
      if (profile.sslEnabled) {
        env['PGSSLMODE'] = 'require';
      }
    } else if (profile.driver == DbDriverType.mysql ||
        profile.driver == DbDriverType.mariadb) {
      if (profile.password != null && profile.password!.isNotEmpty) {
        env['MYSQL_PWD'] = profile.password!;
      }
    } else if (profile.driver == DbDriverType.redis) {
      if (profile.password != null && profile.password!.isNotEmpty) {
        env['REDISCLI_AUTH'] = profile.password!;
      }
    }

    try {
      final res = await Process.run(
        cmd.first,
        cmd.sublist(1),
        environment: env,
      ).timeout(const Duration(seconds: 15));
      sw.stop();
      final elapsedMs = sw.elapsedMicroseconds / 1000.0;

      if (res.exitCode != 0) {
        final stderrText = (res.stderr as String).trim();
        final stdoutText = (res.stdout as String).trim();
        return QueryResult(
          columns: const [],
          rows: const [],
          executionTimeMs: elapsedMs,
          error: stderrText.isNotEmpty
              ? stderrText
              : (stdoutText.isNotEmpty
                  ? stdoutText
                  : '${profile.driver.cliBinary} exited with code ${res.exitCode}'),
          executedSql: sql,
        );
      }

      final out = (res.stdout as String).trim();
      if (out.isEmpty) {
        return QueryResult(
          columns: const ['status'],
          rows: const [
            {'status': 'OK'},
          ],
          affectedRows: 0,
          executionTimeMs: elapsedMs,
          explainPlan: ['EXECUTED VIA ${profile.driver.cliBinary.toUpperCase()}'],
          executedSql: sql,
        );
      }

      switch (profile.driver) {
        case DbDriverType.postgres:
          return _parseCsvResult(out, elapsedMs, sql);
        case DbDriverType.mysql:
        case DbDriverType.mariadb:
          return _parseTsvResult(out, elapsedMs, sql);
        case DbDriverType.duckdb:
          return _parseJsonArrayResult(out, elapsedMs, sql);
        case DbDriverType.clickhouse:
          return _parseJsonLinesResult(out, elapsedMs, sql);
        case DbDriverType.redis:
          final lines = out.split('\n');
          return QueryResult(
            columns: const ['response'],
            rows: lines.map((l) => {'response': l}).toList(),
            affectedRows: lines.length,
            executionTimeMs: elapsedMs,
            explainPlan: const ['REDIS-CLI COMMAND'],
            executedSql: sql,
          );
        case DbDriverType.sqlite:
          return _parseJsonArrayResult(out, elapsedMs, sql);
      }
    } catch (e) {
      sw.stop();
      return QueryResult(
        columns: const [],
        rows: const [],
        executionTimeMs: sw.elapsedMicroseconds / 1000.0,
        error: e.toString(),
        executedSql: sql,
      );
    }
  }

  static QueryResult _parseJsonArrayResult(
    String stdoutStr,
    double elapsedMs,
    String sql,
  ) {
    try {
      final decoded = jsonDecode(stdoutStr);
      if (decoded is List) {
        final columns = <String>[];
        final rows = <Map<String, dynamic>>[];
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            if (columns.isEmpty) columns.addAll(item.keys);
            rows.add(Map<String, dynamic>.from(item));
          }
        }
        return QueryResult(
          columns: columns,
          rows: rows,
          affectedRows: rows.length,
          executionTimeMs: elapsedMs,
          executedSql: sql,
        );
      }
    } catch (_) {}
    return QueryResult(
      columns: const ['output'],
      rows: [
        {'output': stdoutStr},
      ],
      affectedRows: 1,
      executionTimeMs: elapsedMs,
      executedSql: sql,
    );
  }

  static QueryResult _parseJsonLinesResult(
    String stdoutStr,
    double elapsedMs,
    String sql,
  ) {
    final columns = <String>[];
    final rows = <Map<String, dynamic>>[];
    for (final line in stdoutStr.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      try {
        final obj = jsonDecode(t);
        if (obj is Map<String, dynamic>) {
          if (columns.isEmpty) columns.addAll(obj.keys);
          rows.add(Map<String, dynamic>.from(obj));
        }
      } catch (_) {}
    }
    return QueryResult(
      columns: columns,
      rows: rows,
      affectedRows: rows.length,
      executionTimeMs: elapsedMs,
      executedSql: sql,
    );
  }

  static QueryResult _parseTsvResult(
    String stdoutStr,
    double elapsedMs,
    String sql,
  ) {
    final lines = stdoutStr.split('\n').where((l) => l.isNotEmpty).toList();
    if (lines.isEmpty) {
      return QueryResult(
        columns: const [],
        rows: const [],
        executionTimeMs: elapsedMs,
        executedSql: sql,
      );
    }
    final columns = lines.first.split('\t');
    final rows = <Map<String, dynamic>>[];
    for (var i = 1; i < lines.length; i++) {
      final cells = lines[i].split('\t');
      final row = <String, dynamic>{};
      for (var c = 0; c < columns.length; c++) {
        final rawVal = c < cells.length ? cells[c] : null;
        row[columns[c]] = rawVal == 'NULL' ? null : rawVal;
      }
      rows.add(row);
    }
    return QueryResult(
      columns: columns,
      rows: rows,
      affectedRows: rows.length,
      executionTimeMs: elapsedMs,
      executedSql: sql,
    );
  }

  static QueryResult _parseCsvResult(
    String stdoutStr,
    double elapsedMs,
    String sql,
  ) {
    final lines = stdoutStr.split('\n').where((l) => l.isNotEmpty).toList();
    if (lines.isEmpty) {
      return QueryResult(
        columns: const [],
        rows: const [],
        executionTimeMs: elapsedMs,
        executedSql: sql,
      );
    }
    final columns = _parseCsvLine(lines.first);
    final rows = <Map<String, dynamic>>[];
    for (var i = 1; i < lines.length; i++) {
      final cells = _parseCsvLine(lines[i]);
      final row = <String, dynamic>{};
      for (var c = 0; c < columns.length; c++) {
        row[columns[c]] = c < cells.length ? cells[c] : null;
      }
      rows.add(row);
    }
    return QueryResult(
      columns: columns,
      rows: rows,
      affectedRows: rows.length,
      executionTimeMs: elapsedMs,
      executedSql: sql,
    );
  }

  static List<String> _parseCsvLine(String line) {
    final result = <String>[];
    final current = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (inQuotes) {
        if (ch == '"' && i + 1 < line.length && line[i + 1] == '"') {
          current.write('"');
          i++;
        } else if (ch == '"') {
          inQuotes = false;
        } else {
          current.write(ch);
        }
      } else {
        if (ch == '"') {
          inQuotes = true;
        } else if (ch == ',') {
          result.add(current.toString());
          current.clear();
        } else {
          current.write(ch);
        }
      }
    }
    result.add(current.toString());
    return result;
  }

  /// Introspects real tables & columns for a connected database profile.
  static Future<List<DbTableSchema>> introspectConnection(
    DbConnectionProfile profile,
  ) async {
    switch (profile.driver) {
      case DbDriverType.sqlite:
        if (profile.databaseOrPath.trim() == ':memory:') return [];
        return introspectSqliteFile(resolvePath(profile.databaseOrPath));
      case DbDriverType.postgres:
        return _introspectPostgres(profile);
      case DbDriverType.mysql:
      case DbDriverType.mariadb:
        return _introspectMysql(profile);
      case DbDriverType.duckdb:
        return _introspectDuckDb(profile);
      case DbDriverType.redis:
      case DbDriverType.clickhouse:
        return [];
    }
  }

  static Future<List<DbTableSchema>> _introspectPostgres(
    DbConnectionProfile profile,
  ) async {
    final res = await executeOnProfile(
      profile,
      "SELECT table_schema, table_name, table_type FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog', 'information_schema') ORDER BY table_schema, table_name;",
    );
    if (!res.isSuccess || res.rows.isEmpty) return [];

    final tables = <DbTableSchema>[];
    var idx = 0;
    for (final row in res.rows) {
      final schemaName = row['table_schema']?.toString() ?? 'public';
      final tableName = row['table_name']?.toString() ?? '';
      if (tableName.isEmpty) continue;
      final isView =
          (row['table_type']?.toString() ?? '').toUpperCase().contains('VIEW');

      final colRes = await executeOnProfile(
        profile,
        "SELECT column_name, data_type, is_nullable, column_default FROM information_schema.columns WHERE table_schema = '$schemaName' AND table_name = '$tableName' ORDER BY ordinal_position;",
      );
      final columns = colRes.rows.map((c) {
        return DbColumnSchema(
          name: c['column_name']?.toString() ?? '',
          dataType: (c['data_type']?.toString() ?? 'TEXT').toUpperCase(),
          isNullable: (c['is_nullable']?.toString() ?? 'YES') == 'YES',
          defaultValue: c['column_default']?.toString(),
        );
      }).toList();

      final dataRes = await executeOnProfile(
        profile,
        'SELECT * FROM "$schemaName"."$tableName" LIMIT 200;',
      );

      final colIndex = idx % 3;
      final rowIndex = idx ~/ 3;
      idx++;
      final tbl = DbTableSchema(
        name: tableName,
        schemaName: schemaName,
        isView: isView,
        rowCount: dataRes.rows.length,
        sizeBytes: math.max(4096, dataRes.rows.length * 256),
        columns: columns,
        rows: dataRes.isSuccess ? dataRes.rows : [],
        erPosition: Offset(40.0 + colIndex * 310.0, 40.0 + rowIndex * 250.0),
      );
      tbl.ddlSql = generateTableDdl(tbl);
      tables.add(tbl);
    }
    return tables;
  }

  static Future<List<DbTableSchema>> _introspectMysql(
    DbConnectionProfile profile,
  ) async {
    final db = profile.databaseOrPath.trim();
    if (db.isEmpty) return [];
    final res = await executeOnProfile(
      profile,
      "SELECT table_name, table_type FROM information_schema.tables WHERE table_schema = '$db' ORDER BY table_name;",
    );
    if (!res.isSuccess || res.rows.isEmpty) return [];

    final tables = <DbTableSchema>[];
    var idx = 0;
    for (final row in res.rows) {
      final tableName =
          (row['table_name'] ?? row['TABLE_NAME'])?.toString() ?? '';
      if (tableName.isEmpty) continue;
      final typeStr =
          (row['table_type'] ?? row['TABLE_TYPE'])?.toString() ?? '';
      final isView = typeStr.toUpperCase().contains('VIEW');

      final colRes = await executeOnProfile(
        profile,
        "SELECT column_name, data_type, is_nullable, column_key, column_default FROM information_schema.columns WHERE table_schema = '$db' AND table_name = '$tableName' ORDER BY ordinal_position;",
      );
      final columns = colRes.rows.map((c) {
        final key = (c['column_key'] ?? c['COLUMN_KEY'])?.toString() ?? '';
        return DbColumnSchema(
          name: (c['column_name'] ?? c['COLUMN_NAME'])?.toString() ?? '',
          dataType:
              ((c['data_type'] ?? c['DATA_TYPE'])?.toString() ?? 'TEXT')
                  .toUpperCase(),
          isPrimaryKey: key == 'PRI',
          isUnique: key == 'UNI',
          isNullable:
              ((c['is_nullable'] ?? c['IS_NULLABLE'])?.toString() ?? 'YES') ==
                  'YES',
          defaultValue: (c['column_default'] ?? c['COLUMN_DEFAULT'])?.toString(),
        );
      }).toList();

      final dataRes = await executeOnProfile(
        profile,
        'SELECT * FROM `$tableName` LIMIT 200;',
      );

      final colIndex = idx % 3;
      final rowIndex = idx ~/ 3;
      idx++;
      final tbl = DbTableSchema(
        name: tableName,
        schemaName: db,
        isView: isView,
        rowCount: dataRes.rows.length,
        sizeBytes: math.max(4096, dataRes.rows.length * 256),
        columns: columns,
        rows: dataRes.isSuccess ? dataRes.rows : [],
        erPosition: Offset(40.0 + colIndex * 310.0, 40.0 + rowIndex * 250.0),
      );
      tbl.ddlSql = generateTableDdl(tbl);
      tables.add(tbl);
    }
    return tables;
  }

  static Future<List<DbTableSchema>> _introspectDuckDb(
    DbConnectionProfile profile,
  ) async {
    final res = await executeOnProfile(profile, 'SHOW TABLES;');
    if (!res.isSuccess || res.rows.isEmpty) return [];

    final tables = <DbTableSchema>[];
    var idx = 0;
    for (final row in res.rows) {
      final tableName = row.values.isNotEmpty ? row.values.first.toString() : '';
      if (tableName.isEmpty) continue;
      final descRes = await executeOnProfile(profile, 'DESCRIBE "$tableName";');
      final columns = descRes.rows.map((c) {
        return DbColumnSchema(
          name: c['column_name']?.toString() ?? '',
          dataType: (c['column_type']?.toString() ?? 'VARCHAR').toUpperCase(),
          isNullable: (c['null']?.toString() ?? 'YES') == 'YES',
          isPrimaryKey: (c['key']?.toString() ?? '') == 'PRI',
          defaultValue: c['default']?.toString(),
        );
      }).toList();
      final dataRes = await executeOnProfile(
        profile,
        'SELECT * FROM "$tableName" LIMIT 200;',
      );
      final colIndex = idx % 3;
      final rowIndex = idx ~/ 3;
      idx++;
      final tbl = DbTableSchema(
        name: tableName,
        schemaName: 'main',
        rowCount: dataRes.rows.length,
        sizeBytes: math.max(4096, dataRes.rows.length * 256),
        columns: columns,
        rows: dataRes.isSuccess ? dataRes.rows : [],
        erPosition: Offset(40.0 + colIndex * 310.0, 40.0 + rowIndex * 250.0),
      );
      tbl.ddlSql = generateTableDdl(tbl);
      tables.add(tbl);
    }
    return tables;
  }

  /// Materializes a list of `DbTableSchema` tables and their rows into a real SQLite 3
  /// file on disk using `sqlite3` CLI when available.
  static Future<bool> seedSqliteFile(
    String rawPath,
    List<DbTableSchema> schemas,
  ) async {
    final cli = sqliteCliPath;
    if (cli == null) return false;
    final filePath = resolvePath(rawPath);
    try {
      final file = File(filePath);
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      if (file.existsSync()) {
        file.deleteSync();
      }
      final buffer = StringBuffer();
      buffer.writeln('PRAGMA foreign_keys = ON;');
      buffer.writeln('BEGIN TRANSACTION;');
      for (final table in schemas) {
        if (table.isView) continue;
        final ddl = table.ddlSql.trim().isNotEmpty
            ? table.ddlSql.trim()
            : generateTableDdl(table);
        buffer.writeln(ddl.endsWith(';') ? ddl : '$ddl;');
        for (final idx in table.indexes) {
          final unique = idx.isUnique ? 'UNIQUE ' : '';
          buffer.writeln(
            'CREATE ${unique}INDEX IF NOT EXISTS ${idx.name} ON ${table.name} (${idx.columns.join(', ')});',
          );
        }
        for (final row in table.rows) {
          if (row.isEmpty) continue;
          final cols = row.keys.toList();
          final vals = cols.map((k) => _sqlLiteral(row[k])).join(', ');
          buffer.writeln(
            'INSERT INTO ${table.name} (${cols.join(', ')}) VALUES ($vals);',
          );
        }
      }
      for (final table in schemas) {
        if (!table.isView) continue;
        if (table.ddlSql.trim().isNotEmpty) {
          final ddl = table.ddlSql.trim();
          buffer.writeln(ddl.endsWith(';') ? ddl : '$ddl;');
        }
      }
      buffer.writeln('COMMIT;');
      final res = await Process.run(cli, [
        filePath,
        buffer.toString(),
      ]);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Executes a real SQL statement against a SQLite file on disk via `sqlite3` CLI.
  static Future<QueryResult> executeOnSqliteFile(
    String rawPath,
    String sql,
  ) async {
    final sw = Stopwatch()..start();
    final filePath = resolvePath(rawPath);
    final cli = sqliteCliPath;
    final trimmed = _stripSqlComments(sql).trim();
    if (cli == null || !File(filePath).existsSync()) {
      return QueryResult(
        columns: const [],
        rows: const [],
        executionTimeMs: 0.2,
        error: cli == null
            ? 'sqlite3 CLI binary not found on system PATH.'
            : 'SQLite file not found: $filePath',
        executedSql: sql,
      );
    }

    try {
      // Explain plan via real SQLite
      final explainPlan = <String>[];
      final upper = trimmed.toUpperCase();
      final isSelect = upper.startsWith('SELECT') ||
          upper.startsWith('PRAGMA') ||
          upper.startsWith('WITH') ||
          upper.startsWith('EXPLAIN');

      if (upper.startsWith('SELECT')) {
        final eqpRes = await Process.run(cli, [
          '-json',
          filePath,
          'EXPLAIN QUERY PLAN $trimmed',
        ]);
        if (eqpRes.exitCode == 0) {
          final out = (eqpRes.stdout as String).trim();
          if (out.isNotEmpty) {
            try {
              final decoded = jsonDecode(out) as List<dynamic>;
              for (final item in decoded) {
                if (item is Map && item['detail'] != null) {
                  explainPlan.add(item['detail'].toString());
                }
              }
            } catch (_) {
              for (final line in out.split('\n')) {
                final clean = line.trim();
                if (clean.isNotEmpty && clean != 'QUERY PLAN') {
                  explainPlan.add(clean);
                }
              }
            }
          }
        }
      }

      if (isSelect) {
        final res = await Process.run(cli, [
          '-json',
          filePath,
          trimmed,
        ]);
        sw.stop();
        if (res.exitCode != 0) {
          return QueryResult(
            columns: const [],
            rows: const [],
            executionTimeMs: sw.elapsedMicroseconds / 1000.0,
            error: (res.stderr as String).trim(),
            executedSql: sql,
          );
        }
        final stdoutStr = (res.stdout as String).trim();
        if (stdoutStr.isEmpty) {
          return QueryResult(
            columns: const [],
            rows: const [],
            executionTimeMs: sw.elapsedMicroseconds / 1000.0,
            explainPlan: explainPlan,
            executedSql: sql,
          );
        }
        final decoded = jsonDecode(stdoutStr) as List<dynamic>;
        final rows = <Map<String, dynamic>>[];
        final columns = <String>[];
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            if (columns.isEmpty) {
              columns.addAll(item.keys);
            }
            rows.add(Map<String, dynamic>.from(item));
          }
        }
        return QueryResult(
          columns: columns,
          rows: rows,
          affectedRows: rows.length,
          executionTimeMs: sw.elapsedMicroseconds / 1000.0,
          explainPlan: explainPlan.isEmpty
              ? const ['SCAN TABLE USING SQLITE3 NATIVE ENGINE']
              : explainPlan,
          executedSql: sql,
        );
      } else {
        final stmtWithSemi = trimmed.endsWith(';') ? trimmed : '$trimmed;';
        final res = await Process.run(cli, [
          filePath,
          '$stmtWithSemi\nSELECT changes();',
        ]);
        sw.stop();
        if (res.exitCode != 0) {
          return QueryResult(
            columns: const [],
            rows: const [],
            executionTimeMs: sw.elapsedMicroseconds / 1000.0,
            error: (res.stderr as String).trim(),
            executedSql: sql,
          );
        }
        final lines = (res.stdout as String).trim().split('\n');
        final changes =
            lines.isNotEmpty ? (int.tryParse(lines.last.trim()) ?? 0) : 0;
        return QueryResult(
          columns: const ['status', 'affected_rows'],
          rows: [
            {'status': 'OK', 'affected_rows': changes},
          ],
          affectedRows: changes,
          executionTimeMs: sw.elapsedMicroseconds / 1000.0,
          explainPlan: const ['EXECUTE STATEMENT ON SQLITE3 FILE'],
          executedSql: sql,
        );
      }
    } catch (e) {
      sw.stop();
      return QueryResult(
        columns: const [],
        rows: const [],
        executionTimeMs: sw.elapsedMicroseconds / 1000.0,
        error: e.toString(),
        executedSql: sql,
      );
    }
  }

  /// Introspects a real SQLite 3 database file on disk using `sqlite_master` and `PRAGMA` statements.
  static Future<List<DbTableSchema>> introspectSqliteFile(
    String rawPath,
  ) async {
    final filePath = resolvePath(rawPath);
    if (!hasSqliteCli || !File(filePath).existsSync()) return [];
    final tables = <DbTableSchema>[];
    try {
      final masterRes = await executeOnSqliteFile(
        filePath,
        "SELECT name, type, sql FROM sqlite_master WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%' ORDER BY type DESC, name ASC;",
      );
      if (!masterRes.isSuccess) return [];

      var idx = 0;
      for (final mRow in masterRes.rows) {
        final tableName = mRow['name']?.toString() ?? '';
        if (tableName.isEmpty) continue;
        final isView = mRow['type']?.toString() == 'view';
        final ddl = mRow['sql']?.toString() ?? '';

        // Foreign keys
        final fkMap = <String, String>{};
        if (!isView) {
          final fkRes = await executeOnSqliteFile(
            filePath,
            'PRAGMA foreign_key_list("$tableName");',
          );
          for (final fk in fkRes.rows) {
            final fromCol = fk['from']?.toString();
            final targetTable = fk['table']?.toString();
            final targetCol = fk['to']?.toString() ?? 'id';
            if (fromCol != null && targetTable != null) {
              fkMap[fromCol] = '$targetTable.$targetCol';
            }
          }
        }

        // Columns
        final colRes = await executeOnSqliteFile(
          filePath,
          'PRAGMA table_info("$tableName");',
        );
        final columns = <DbColumnSchema>[];
        for (final cRow in colRes.rows) {
          final colName = cRow['name']?.toString() ?? '';
          final colType = cRow['type']?.toString().toUpperCase() ?? 'TEXT';
          final isPk = (cRow['pk'] is int
              ? (cRow['pk'] as int) > 0
              : cRow['pk']?.toString() == '1');
          final notNull = (cRow['notnull'] is int
              ? (cRow['notnull'] as int) > 0
              : cRow['notnull']?.toString() == '1');
          columns.add(
            DbColumnSchema(
              name: colName,
              dataType: colType.isEmpty ? 'TEXT' : colType,
              isPrimaryKey: isPk,
              isNullable: !notNull && !isPk,
              defaultValue: cRow['dflt_value']?.toString(),
              foreignKeyTarget: fkMap[colName],
            ),
          );
        }

        // Indexes
        final indexes = <DbIndexSchema>[];
        if (!isView) {
          final idxRes = await executeOnSqliteFile(
            filePath,
            'PRAGMA index_list("$tableName");',
          );
          for (final iRow in idxRes.rows) {
            final idxName = iRow['name']?.toString() ?? '';
            if (idxName.isEmpty) continue;
            final isUnique = (iRow['unique'] is int
                ? (iRow['unique'] as int) > 0
                : iRow['unique']?.toString() == '1');
            final infoRes = await executeOnSqliteFile(
              filePath,
              'PRAGMA index_info("$idxName");',
            );
            final idxCols = infoRes.rows
                .map((r) => r['name']?.toString() ?? '')
                .where((s) => s.isNotEmpty)
                .toList();
            indexes.add(
              DbIndexSchema(
                name: idxName,
                tableName: tableName,
                columns: idxCols,
                isUnique: isUnique,
              ),
            );
          }
        }

        // Triggers
        final triggers = <DbTriggerSchema>[];
        if (!isView) {
          final trgRes = await executeOnSqliteFile(
            filePath,
            "SELECT name, sql FROM sqlite_master WHERE type = 'trigger' AND tbl_name = '${tableName.replaceAll("'", "''")}';",
          );
          for (final tRow in trgRes.rows) {
            final trgName = tRow['name']?.toString() ?? '';
            final trgSql = tRow['sql']?.toString() ?? '';
            if (trgName.isEmpty) continue;
            final upperSql = trgSql.toUpperCase();
            final timing = upperSql.contains('BEFORE') ? 'BEFORE' : 'AFTER';
            final event = upperSql.contains('DELETE')
                ? 'DELETE'
                : (upperSql.contains('UPDATE') ? 'UPDATE' : 'INSERT');
            triggers.add(
              DbTriggerSchema(
                name: trgName,
                tableName: tableName,
                timing: timing,
                event: event,
                definitionSql: trgSql,
              ),
            );
          }
        }

        // Rows
        final dataRes = await executeOnSqliteFile(
          filePath,
          'SELECT * FROM "$tableName" LIMIT 200;',
        );

        final colIndex = idx % 3;
        final rowIndex = idx ~/ 3;
        idx++;

        tables.add(
          DbTableSchema(
            name: tableName,
            schemaName: 'main',
            isView: isView,
            rowCount: dataRes.rows.length,
            sizeBytes: math.max(4096, dataRes.rows.length * 256),
            columns: columns,
            indexes: indexes,
            triggers: triggers,
            ddlSql: ddl,
            rows: dataRes.rows,
            erPosition: Offset(40.0 + colIndex * 310.0, 40.0 + rowIndex * 250.0),
          ),
        );
      }
    } catch (_) {}
    return tables;
  }

  /// Pure-Dart Relational SQL Engine that synchronously parses and executes SQL
  /// queries (`SELECT`, `JOIN`, `WHERE`, `GROUP BY`, `ORDER BY`, `LIMIT`, `OFFSET`,
  /// aggregates, `INSERT`, `UPDATE`, `DELETE`, `CREATE TABLE`, `DROP TABLE`, `EXPLAIN`)
  /// against the connection's live schema & rows.
  static QueryResult executeInMemory(
    String rawSql,
    List<DbTableSchema> tables,
  ) {
    final sw = Stopwatch()..start();
    final cleaned = _stripSqlComments(rawSql).trim();
    if (cleaned.isEmpty) {
      return QueryResult(
        columns: const [],
        rows: const [],
        executionTimeMs: 0.1,
        error: 'Empty SQL query.',
        executedSql: rawSql,
      );
    }

    // Split multiple statements by semicolon, execute sequentially, return last result
    final statements = _splitStatements(cleaned);
    QueryResult? lastResult;
    for (final stmt in statements) {
      lastResult = _executeSingleStatement(stmt, tables, rawSql, sw);
      if (lastResult.error != null) {
        return lastResult;
      }
    }
    return lastResult!;
  }

  static QueryResult _executeSingleStatement(
    String stmt,
    List<DbTableSchema> tables,
    String originalSql,
    Stopwatch sw,
  ) {
    final trimmed = stmt.trim();
    final upper = trimmed.toUpperCase();

    try {
      if (upper.startsWith('EXPLAIN QUERY PLAN ') ||
          upper.startsWith('EXPLAIN ')) {
        final innerSql = upper.startsWith('EXPLAIN QUERY PLAN ')
            ? trimmed.substring('EXPLAIN QUERY PLAN '.length).trim()
            : trimmed.substring('EXPLAIN '.length).trim();
        final plan = generateExplainPlan(innerSql, tables);
        sw.stop();
        return QueryResult(
          columns: const ['id', 'parent', 'notused', 'detail'],
          rows: List.generate(
            plan.length,
            (i) => {
              'id': i + 2,
              'parent': 0,
              'notused': 0,
              'detail': plan[i],
            },
          ),
          affectedRows: plan.length,
          executionTimeMs: math.max(0.4, sw.elapsedMicroseconds / 1000.0),
          explainPlan: plan,
          executedSql: originalSql,
        );
      }

      if (upper.startsWith('SELECT')) {
        return _executeSelect(trimmed, tables, originalSql, sw);
      }
      if (upper.startsWith('INSERT INTO')) {
        return _executeInsert(trimmed, tables, originalSql, sw);
      }
      if (upper.startsWith('UPDATE ')) {
        return _executeUpdate(trimmed, tables, originalSql, sw);
      }
      if (upper.startsWith('DELETE FROM')) {
        return _executeDelete(trimmed, tables, originalSql, sw);
      }
      if (upper.startsWith('CREATE TABLE')) {
        return _executeCreateTable(trimmed, tables, originalSql, sw);
      }
      if (upper.startsWith('DROP TABLE')) {
        return _executeDropTable(trimmed, tables, originalSql, sw);
      }

      sw.stop();
      return QueryResult(
        columns: const [],
        rows: const [],
        executionTimeMs: math.max(0.2, sw.elapsedMicroseconds / 1000.0),
        error: 'Unsupported SQL statement: ${trimmed.split(' ').take(3).join(' ')}',
        executedSql: originalSql,
      );
    } catch (e) {
      sw.stop();
      return QueryResult(
        columns: const [],
        rows: const [],
        executionTimeMs: math.max(0.2, sw.elapsedMicroseconds / 1000.0),
        error: e.toString(),
        executedSql: originalSql,
      );
    }
  }

  /// Generates realistic `EXPLAIN QUERY PLAN` steps for a query.
  static List<String> generateExplainPlan(
    String sql,
    List<DbTableSchema> tables,
  ) {
    final normalized = sql.replaceAll(RegExp(r'\s+'), ' ').trim();
    final upper = normalized.toUpperCase();
    final plan = <String>[];

    final fromMatch = RegExp(
      r'\bFROM\s+([a-zA-Z0-9_]+)(?:\s+(?:AS\s+)?([a-zA-Z0-9_]+))?',
      caseSensitive: false,
    ).firstMatch(normalized);

    if (fromMatch != null) {
      final baseTableName = fromMatch.group(1)!;
      final table = _findTable(tables, baseTableName);
      final hasWhere = upper.contains(' WHERE ');
      final pkCol = table?.primaryKeyColumn ?? 'id';

      if (hasWhere &&
          RegExp('\\b$pkCol\\s*=', caseSensitive: false).hasMatch(normalized)) {
        plan.add(
          'SEARCH $baseTableName USING INTEGER PRIMARY KEY (rowid=?) [cost=1.20 rows=1]',
        );
      } else if (table != null && table.indexes.isNotEmpty && hasWhere) {
        DbIndexSchema? matchedIdx;
        for (final idx in table.indexes) {
          if (idx.columns.any(
            (c) => RegExp('\\b$c\\b', caseSensitive: false).hasMatch(normalized),
          )) {
            matchedIdx = idx;
            break;
          }
        }
        if (matchedIdx != null) {
          plan.add(
            'SEARCH $baseTableName USING INDEX ${matchedIdx.name} (${matchedIdx.columns.join('=? AND ')}=?) [cost=2.45 rows=${math.max(1, table.rowCount ~/ 2)}]',
          );
        } else {
          plan.add(
            'SCAN $baseTableName [cost=${(table.rowCount * 1.15).toStringAsFixed(2)} rows=${table.rowCount}]',
          );
        }
      } else {
        final rows = table?.rowCount ?? 10;
        plan.add(
          'SCAN $baseTableName [cost=${(rows * 1.1).toStringAsFixed(2)} rows=$rows]',
        );
      }
    }

    final joinMatches = RegExp(
      r'\b(LEFT\s+(?:OUTER\s+)?|INNER\s+)?JOIN\s+([a-zA-Z0-9_]+)',
      caseSensitive: false,
    ).allMatches(normalized);

    for (final jm in joinMatches) {
      final joinType = (jm.group(1) ?? '').trim().toUpperCase();
      final joinTable = jm.group(2)!;
      final t = _findTable(tables, joinTable);
      final prefix = joinType.startsWith('LEFT') ? 'LEFT-JOIN' : 'INNER-JOIN';
      if (t != null && t.indexes.isNotEmpty) {
        plan.add(
          '$prefix: SEARCH $joinTable USING COVERING INDEX ${t.indexes.first.name} [cost=1.85 rows=${t.rowCount}]',
        );
      } else {
        plan.add(
          '$prefix: SEARCH $joinTable USING INTEGER PRIMARY KEY (rowid=?) [cost=1.40 rows=1]',
        );
      }
    }

    if (upper.contains(' GROUP BY ')) {
      plan.add('USE TEMP B-TREE FOR GROUP BY [cost=1.60]');
    }
    if (upper.contains(' ORDER BY ')) {
      plan.add('USE TEMP B-TREE FOR ORDER BY [cost=1.35]');
    }

    if (plan.isEmpty) {
      plan.add('SCAN CONSTANT ROW [cost=0.10 rows=1]');
    }
    return plan;
  }

  static QueryResult _executeSelect(
    String sql,
    List<DbTableSchema> tables,
    String originalSql,
    Stopwatch sw,
  ) {
    final normalized = sql.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Extract clauses in order: SELECT ... FROM ... [JOIN ...] [WHERE ...] [GROUP BY ...] [ORDER BY ...] [LIMIT ...] [OFFSET ...]
    final selectMatch = RegExp(
      r'^SELECT\s+(?:DISTINCT\s+)?(.+?)\s+FROM\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(normalized);

    if (selectMatch == null) {
      // Handle SELECT without FROM (e.g. SELECT 1, sqlite_version())
      final exprs = _splitTopLevelComma(
        normalized.substring('SELECT'.length).trim(),
      );
      final row = <String, dynamic>{};
      final cols = <String>[];
      for (final e in exprs) {
        final aliasParts = RegExp(r'^(.+?)\s+AS\s+([a-zA-Z0-9_]+)$',
                caseSensitive: false)
            .firstMatch(e.trim());
        final colName = aliasParts != null ? aliasParts.group(2)! : e.trim();
        final valExpr = aliasParts != null ? aliasParts.group(1)! : e.trim();
        cols.add(colName);
        row[colName] = _parseLiteral(valExpr);
      }
      sw.stop();
      return QueryResult(
        columns: cols,
        rows: [row],
        affectedRows: 1,
        executionTimeMs: math.max(0.3, sw.elapsedMicroseconds / 1000.0),
        explainPlan: const ['SCAN CONSTANT ROW'],
        executedSql: originalSql,
      );
    }

    final selectDistinct = RegExp(r'^SELECT\s+DISTINCT\b', caseSensitive: false)
        .hasMatch(normalized);
    final selectListStr = selectMatch.group(1)!.trim();
    var remainder = selectMatch.group(2)!.trim();

    int? offsetVal;
    int? limitVal;
    String? orderByStr;
    String? groupByStr;
    String? whereStr;

    // Extract OFFSET
    final offsetMatch = RegExp(r'\s+OFFSET\s+(\d+)\s*$', caseSensitive: false)
        .firstMatch(remainder);
    if (offsetMatch != null) {
      offsetVal = int.tryParse(offsetMatch.group(1)!);
      remainder = remainder.substring(0, offsetMatch.start).trim();
    }

    // Extract LIMIT
    final limitMatch = RegExp(
      r'\s+LIMIT\s+(\d+)(?:\s*,\s*(\d+))?\s*$',
      caseSensitive: false,
    ).firstMatch(remainder);
    if (limitMatch != null) {
      if (limitMatch.group(2) != null) {
        offsetVal = int.tryParse(limitMatch.group(1)!);
        limitVal = int.tryParse(limitMatch.group(2)!);
      } else {
        limitVal = int.tryParse(limitMatch.group(1)!);
      }
      remainder = remainder.substring(0, limitMatch.start).trim();
    }

    // Extract ORDER BY
    final orderMatch = RegExp(
      r'\s+ORDER\s+BY\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(remainder);
    if (orderMatch != null) {
      orderByStr = orderMatch.group(1)!.trim();
      remainder = remainder.substring(0, orderMatch.start).trim();
    }

    // Extract GROUP BY
    final groupMatch = RegExp(
      r'\s+GROUP\s+BY\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(remainder);
    if (groupMatch != null) {
      groupByStr = groupMatch.group(1)!.trim();
      remainder = remainder.substring(0, groupMatch.start).trim();
    }

    // Extract WHERE
    final whereMatch = RegExp(
      r'\s+WHERE\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(remainder);
    if (whereMatch != null) {
      whereStr = whereMatch.group(1)!.trim();
      remainder = remainder.substring(0, whereMatch.start).trim();
    }

    // Now `remainder` is `baseTable [AS alias] [JOIN ...]`
    final joinRegex = RegExp(
      r'\s+(?:(LEFT(?:\s+OUTER)?|INNER)\s+)?JOIN\s+',
      caseSensitive: false,
    );
    final firstJoin = joinRegex.firstMatch(remainder);
    final baseTableClause = firstJoin != null
        ? remainder.substring(0, firstJoin.start).trim()
        : remainder.trim();

    final baseParts = baseTableClause.split(RegExp(r'\s+'));
    final baseTableName = _stripQuotes(baseParts.first);
    final baseAlias = baseParts.length >= 2
        ? _stripQuotes(
            baseParts.last.toUpperCase() == 'AS'
                ? baseTableName
                : baseParts.last,
          )
        : baseTableName;

    final baseTable = _findTable(tables, baseTableName);
    if (baseTable == null) {
      sw.stop();
      return QueryResult(
        columns: const [],
        rows: const [],
        executionTimeMs: math.max(0.2, sw.elapsedMicroseconds / 1000.0),
        error: 'Table or view not found: "$baseTableName"',
        executedSql: originalSql,
      );
    }

    // Build initial combined rows with both unqualified and qualified column keys
    var workingRows = baseTable.rows.map((r) {
      final map = <String, dynamic>{};
      for (final entry in r.entries) {
        map[entry.key] = entry.value;
        map['$baseTableName.${entry.key}'] = entry.value;
        map['$baseAlias.${entry.key}'] = entry.value;
      }
      return map;
    }).toList();

    // Process JOIN clauses if any
    if (firstJoin != null) {
      final joinsPart = remainder.substring(firstJoin.start);
      final joinPattern = RegExp(
        r'(?:(LEFT(?:\s+OUTER)?|INNER)\s+)?JOIN\s+([a-zA-Z0-9_]+)(?:\s+(?:AS\s+)?([a-zA-Z0-9_]+))?\s+ON\s+([^\s]+)\s*=\s*([^\s]+)',
        caseSensitive: false,
      );
      for (final jm in joinPattern.allMatches(joinsPart)) {
        final joinKind = (jm.group(1) ?? 'INNER').toUpperCase();
        final isLeftJoin = joinKind.startsWith('LEFT');
        final joinTableName = jm.group(2)!;
        final rawAlias = jm.group(3);
        final joinAlias = (rawAlias != null && rawAlias.toUpperCase() != 'ON')
            ? rawAlias
            : joinTableName;
        final leftKey = jm.group(4)!.trim();
        final rightKey = jm.group(5)!.trim();

        final joinTable = _findTable(tables, joinTableName);
        if (joinTable == null) {
          sw.stop();
          return QueryResult(
            columns: const [],
            rows: const [],
            executionTimeMs: math.max(0.2, sw.elapsedMicroseconds / 1000.0),
            error: 'Joined table not found: "$joinTableName"',
            executedSql: originalSql,
          );
        }

        final nextRows = <Map<String, dynamic>>[];
        for (final leftRow in workingRows) {
          var matchedAny = false;
          for (final rightRow in joinTable.rows) {
            final candidate = Map<String, dynamic>.from(leftRow);
            for (final entry in rightRow.entries) {
              candidate.putIfAbsent(entry.key, () => entry.value);
              candidate['$joinTableName.${entry.key}'] = entry.value;
              candidate['$joinAlias.${entry.key}'] = entry.value;
            }
            final lv = _resolveColumnValue(candidate, leftKey);
            final rv = _resolveColumnValue(candidate, rightKey);
            if (_valuesEqual(lv, rv)) {
              matchedAny = true;
              nextRows.add(candidate);
            }
          }
          if (!matchedAny && isLeftJoin) {
            final nullPadded = Map<String, dynamic>.from(leftRow);
            for (final col in joinTable.columns) {
              nullPadded.putIfAbsent(col.name, () => null);
              nullPadded['$joinTableName.${col.name}'] = null;
              nullPadded['$joinAlias.${col.name}'] = null;
            }
            nextRows.add(nullPadded);
          }
        }
        workingRows = nextRows;
      }
    }

    // Apply WHERE filter
    if (whereStr != null && whereStr.isNotEmpty) {
      workingRows = workingRows
          .where((row) => _evaluateWhere(row, whereStr!))
          .toList();
    }

    // Parse SELECT projections
    final selectItems = _splitTopLevelComma(selectListStr);
    final hasAggregate = selectItems.any((item) => _isAggregateExpr(item));

    List<Map<String, dynamic>> projectedRows = [];
    List<String> outputColumns = [];

    if (groupByStr != null || hasAggregate) {
      final groupCols = groupByStr != null
          ? groupByStr.split(',').map((s) => s.trim()).toList()
          : <String>[];

      final groups = <String, List<Map<String, dynamic>>>{};
      if (groupCols.isEmpty) {
        groups['__all__'] = workingRows;
      } else {
        for (final r in workingRows) {
          final key = groupCols
              .map((gc) => '${_resolveColumnValue(r, gc)}')
              .join('||');
          groups.putIfAbsent(key, () => []).add(r);
        }
      }

      for (final grpRows in groups.values) {
        final outRow = <String, dynamic>{};
        for (final item in selectItems) {
          final parsed = _parseProjectionItem(item);
          if (!outputColumns.contains(parsed.outputName)) {
            outputColumns.add(parsed.outputName);
          }
          outRow[parsed.outputName] = _evaluateGroupExpression(
            grpRows,
            parsed.expr,
          );
        }
        projectedRows.add(outRow);
      }
    } else {
      // Standard row projection
      if (selectListStr.trim() == '*') {
        outputColumns = baseTable.columns.map((c) => c.name).toList();
        for (final r in workingRows) {
          final outRow = <String, dynamic>{};
          for (final col in outputColumns) {
            outRow[col] = _resolveColumnValue(r, col);
          }
          projectedRows.add(outRow);
        }
      } else {
        final parsedItems = selectItems.map(_parseProjectionItem).toList();
        outputColumns = parsedItems.map((p) => p.outputName).toList();
        for (final r in workingRows) {
          final outRow = <String, dynamic>{};
          for (final p in parsedItems) {
            outRow[p.outputName] = _evaluateRowExpression(r, p.expr);
          }
          projectedRows.add(outRow);
        }
      }
    }

    if (selectDistinct) {
      final seen = <String>{};
      final deduped = <Map<String, dynamic>>[];
      for (final r in projectedRows) {
        final sig = outputColumns.map((c) => '${r[c]}').join('|#|');
        if (seen.add(sig)) {
          deduped.add(r);
        }
      }
      projectedRows = deduped;
    }

    // Apply ORDER BY
    if (orderByStr != null && orderByStr.isNotEmpty) {
      final orderSpecs = orderByStr.split(',').map((s) => s.trim()).toList();
      projectedRows.sort((a, b) {
        for (final spec in orderSpecs) {
          final parts = spec.split(RegExp(r'\s+'));
          final colExpr = parts.first.trim();
          final desc = parts.length > 1 && parts[1].toUpperCase() == 'DESC';
          final av = _resolveOrderValue(a, colExpr);
          final bv = _resolveOrderValue(b, colExpr);
          final cmp = _compareValues(av, bv);
          if (cmp != 0) {
            return desc ? -cmp : cmp;
          }
        }
        return 0;
      });
    }

    // Apply OFFSET and LIMIT
    if (offsetVal != null && offsetVal > 0) {
      projectedRows = offsetVal >= projectedRows.length
          ? []
          : projectedRows.sublist(offsetVal);
    }
    if (limitVal != null && limitVal >= 0 && projectedRows.length > limitVal) {
      projectedRows = projectedRows.sublist(0, limitVal);
    }

    final explain = generateExplainPlan(normalized, tables);
    sw.stop();
    return QueryResult(
      columns: outputColumns,
      rows: projectedRows,
      affectedRows: projectedRows.length,
      executionTimeMs: math.max(0.4, sw.elapsedMicroseconds / 1000.0),
      explainPlan: explain,
      executedSql: originalSql,
    );
  }

  static QueryResult _executeInsert(
    String sql,
    List<DbTableSchema> tables,
    String originalSql,
    Stopwatch sw,
  ) {
    final match = RegExp(
      r'^INSERT\s+INTO\s+([a-zA-Z0-9_]+)\s*(?:\(([^)]+)\))?\s*VALUES\s*(.+)$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(sql.trim());

    if (match == null) {
      sw.stop();
      return QueryResult(
        columns: const [],
        rows: const [],
        executionTimeMs: 0.2,
        error: 'Syntax error in INSERT INTO statement.',
        executedSql: originalSql,
      );
    }

    final tableName = match.group(1)!;
    final colsGroup = match.group(2);
    final valuesPart = match.group(3)!.trim();

    final table = _findTable(tables, tableName);
    if (table == null) {
      sw.stop();
      return QueryResult(
        columns: const [],
        rows: const [],
        executionTimeMs: 0.2,
        error: 'Table not found: "$tableName"',
        executedSql: originalSql,
      );
    }

    final targetColumns = colsGroup != null
        ? colsGroup.split(',').map((s) => _stripQuotes(s.trim())).toList()
        : table.columns.map((c) => c.name).toList();

    final tupleMatches = RegExp(r'\(([^)]+)\)').allMatches(valuesPart);
    var inserted = 0;

    for (final tm in tupleMatches) {
      final rawVals = _splitTopLevelComma(tm.group(1)!);
      final newRow = <String, dynamic>{};
      for (final col in table.columns) {
        newRow[col.name] = col.defaultValue != null
            ? _parseLiteral(col.defaultValue!)
            : null;
      }
      for (var i = 0;
          i < math.min(targetColumns.length, rawVals.length);
          i++) {
        newRow[targetColumns[i]] = _parseLiteral(rawVals[i].trim());
      }
      // Auto-assign integer primary key if null
      final pk = table.primaryKeyColumn;
      if (pk != null && newRow[pk] == null) {
        var maxId = 0;
        for (final r in table.rows) {
          final v = r[pk];
          if (v is int && v > maxId) maxId = v;
        }
        newRow[pk] = maxId + 1;
      }
      table.rows.add(newRow);
      inserted++;
    }
    table.rowCount = table.rows.length;
    sw.stop();
    return QueryResult(
      columns: const ['status', 'inserted_rows', 'table'],
      rows: [
        {
          'status': 'INSERT OK',
          'inserted_rows': inserted,
          'table': table.name,
        },
      ],
      affectedRows: inserted,
      executionTimeMs: math.max(0.3, sw.elapsedMicroseconds / 1000.0),
      explainPlan: ['INSERT INTO ${table.name} ($inserted rows)'],
      executedSql: originalSql,
    );
  }

  static QueryResult _executeUpdate(
    String sql,
    List<DbTableSchema> tables,
    String originalSql,
    Stopwatch sw,
  ) {
    final match = RegExp(
      r'^UPDATE\s+([a-zA-Z0-9_]+)\s+SET\s+(.+?)(?:\s+WHERE\s+(.+))?$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(sql.trim());

    if (match == null) {
      sw.stop();
      return QueryResult(
        columns: const [],
        rows: const [],
        executionTimeMs: 0.2,
        error: 'Syntax error in UPDATE statement.',
        executedSql: originalSql,
      );
    }

    final tableName = match.group(1)!;
    final setPart = match.group(2)!.trim();
    final wherePart = match.group(3)?.trim();

    final table = _findTable(tables, tableName);
    if (table == null) {
      sw.stop();
      return QueryResult(
        columns: const [],
        rows: const [],
        executionTimeMs: 0.2,
        error: 'Table not found: "$tableName"',
        executedSql: originalSql,
      );
    }

    final assignments = _splitTopLevelComma(setPart);
    var updated = 0;
    for (final row in table.rows) {
      if (wherePart == null || _evaluateWhere(row, wherePart)) {
        for (final assign in assignments) {
          final eqIdx = assign.indexOf('=');
          if (eqIdx > 0) {
            final col = _stripQuotes(assign.substring(0, eqIdx).trim());
            final valExpr = assign.substring(eqIdx + 1).trim();
            row[col] = _evaluateRowExpression(row, valExpr);
          }
        }
        updated++;
      }
    }

    sw.stop();
    return QueryResult(
      columns: const ['status', 'updated_rows', 'table'],
      rows: [
        {
          'status': 'UPDATE OK',
          'updated_rows': updated,
          'table': table.name,
        },
      ],
      affectedRows: updated,
      executionTimeMs: math.max(0.3, sw.elapsedMicroseconds / 1000.0),
      explainPlan: ['UPDATE ${table.name} ($updated rows matched)'],
      executedSql: originalSql,
    );
  }

  static QueryResult _executeDelete(
    String sql,
    List<DbTableSchema> tables,
    String originalSql,
    Stopwatch sw,
  ) {
    final match = RegExp(
      r'^DELETE\s+FROM\s+([a-zA-Z0-9_]+)(?:\s+WHERE\s+(.+))?$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(sql.trim());

    if (match == null) {
      sw.stop();
      return QueryResult(
        columns: const [],
        rows: const [],
        executionTimeMs: 0.2,
        error: 'Syntax error in DELETE statement.',
        executedSql: originalSql,
      );
    }

    final tableName = match.group(1)!;
    final wherePart = match.group(2)?.trim();
    final table = _findTable(tables, tableName);
    if (table == null) {
      sw.stop();
      return QueryResult(
        columns: const [],
        rows: const [],
        executionTimeMs: 0.2,
        error: 'Table not found: "$tableName"',
        executedSql: originalSql,
      );
    }

    final before = table.rows.length;
    if (wherePart == null || wherePart.isEmpty) {
      table.rows.clear();
    } else {
      table.rows.removeWhere((row) => _evaluateWhere(row, wherePart));
    }
    final deleted = before - table.rows.length;
    table.rowCount = table.rows.length;

    sw.stop();
    return QueryResult(
      columns: const ['status', 'deleted_rows', 'table'],
      rows: [
        {
          'status': 'DELETE OK',
          'deleted_rows': deleted,
          'table': table.name,
        },
      ],
      affectedRows: deleted,
      executionTimeMs: math.max(0.3, sw.elapsedMicroseconds / 1000.0),
      explainPlan: ['DELETE FROM ${table.name} ($deleted rows removed)'],
      executedSql: originalSql,
    );
  }

  static QueryResult _executeCreateTable(
    String sql,
    List<DbTableSchema> tables,
    String originalSql,
    Stopwatch sw,
  ) {
    final match = RegExp(
      r'^CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?([a-zA-Z0-9_]+)\s*\((.+)\)$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(sql.trim());

    if (match == null) {
      sw.stop();
      return QueryResult(
        columns: const [],
        rows: const [],
        executionTimeMs: 0.2,
        error: 'Syntax error in CREATE TABLE statement.',
        executedSql: originalSql,
      );
    }

    final tableName = _stripQuotes(match.group(1)!);
    final body = match.group(2)!.trim();
    final defs = _splitTopLevelComma(body);
    final columns = <DbColumnSchema>[];

    for (final rawDef in defs) {
      final def = rawDef.trim();
      final upperDef = def.toUpperCase();
      if (upperDef.startsWith('PRIMARY KEY') ||
          upperDef.startsWith('FOREIGN KEY') ||
          upperDef.startsWith('CONSTRAINT')) {
        continue;
      }
      final parts = def.split(RegExp(r'\s+'));
      if (parts.isEmpty) continue;
      final colName = _stripQuotes(parts.first);
      final dataType = parts.length > 1 ? parts[1].toUpperCase() : 'TEXT';
      final isPk = upperDef.contains('PRIMARY KEY');
      final isNotNull = upperDef.contains('NOT NULL') || isPk;
      final isUnique = upperDef.contains('UNIQUE') || isPk;

      String? fkTarget;
      final refMatch = RegExp(
        r'REFERENCES\s+([a-zA-Z0-9_]+)\s*\(([a-zA-Z0-9_]+)\)',
        caseSensitive: false,
      ).firstMatch(def);
      if (refMatch != null) {
        fkTarget = '${refMatch.group(1)}.${refMatch.group(2)}';
      }

      String? defaultVal;
      final defMatch = RegExp(
        r'DEFAULT\s+([^\s,]+)',
        caseSensitive: false,
      ).firstMatch(def);
      if (defMatch != null) {
        defaultVal = defMatch.group(1);
      }

      columns.add(
        DbColumnSchema(
          name: colName,
          dataType: dataType,
          isPrimaryKey: isPk,
          isNullable: !isNotNull,
          isUnique: isUnique,
          defaultValue: defaultVal,
          foreignKeyTarget: fkTarget,
        ),
      );
    }

    tables.removeWhere((t) => t.name.toLowerCase() == tableName.toLowerCase());
    final newTable = DbTableSchema(
      name: tableName,
      schemaName: 'public',
      columns: columns,
      ddlSql: sql.trim().endsWith(';') ? sql.trim() : '${sql.trim()};',
      rows: [],
      erPosition: Offset(
        40.0 + (tables.length % 3) * 320.0,
        40.0 + (tables.length ~/ 3) * 250.0,
      ),
    );
    tables.add(newTable);

    sw.stop();
    return QueryResult(
      columns: const ['status', 'table', 'columns'],
      rows: [
        {
          'status': 'CREATE TABLE OK',
          'table': tableName,
          'columns': columns.length,
        },
      ],
      affectedRows: 0,
      executionTimeMs: math.max(0.3, sw.elapsedMicroseconds / 1000.0),
      explainPlan: ['CREATE TABLE $tableName (${columns.length} columns)'],
      executedSql: originalSql,
    );
  }

  static QueryResult _executeDropTable(
    String sql,
    List<DbTableSchema> tables,
    String originalSql,
    Stopwatch sw,
  ) {
    final match = RegExp(
      r'^DROP\s+TABLE\s+(?:IF\s+EXISTS\s+)?([a-zA-Z0-9_]+)$',
      caseSensitive: false,
    ).firstMatch(sql.trim());

    if (match == null) {
      sw.stop();
      return QueryResult(
        columns: const [],
        rows: const [],
        executionTimeMs: 0.2,
        error: 'Syntax error in DROP TABLE statement.',
        executedSql: originalSql,
      );
    }
    final tableName = _stripQuotes(match.group(1)!);
    tables.removeWhere((t) => t.name.toLowerCase() == tableName.toLowerCase());
    sw.stop();
    return QueryResult(
      columns: const ['status', 'dropped_table'],
      rows: [
        {'status': 'DROP TABLE OK', 'dropped_table': tableName},
      ],
      affectedRows: 0,
      executionTimeMs: math.max(0.2, sw.elapsedMicroseconds / 1000.0),
      explainPlan: ['DROP TABLE $tableName'],
      executedSql: originalSql,
    );
  }

  // --- Expression & Filter Evaluation Helpers ---

  static bool _evaluateWhere(Map<String, dynamic> row, String whereClause) {
    // Split by top-level OR first
    final orParts = _splitByLogicalOp(whereClause, 'OR');
    if (orParts.length > 1) {
      return orParts.any((part) => _evaluateWhere(row, part));
    }

    // Split by top-level AND
    final andParts = _splitByLogicalOp(whereClause, 'AND');
    if (andParts.length > 1) {
      return andParts.every((part) => _evaluateWhere(row, part));
    }

    var cond = whereClause.trim();
    if (cond.startsWith('(') && cond.endsWith(')')) {
      cond = cond.substring(1, cond.length - 1).trim();
    }

    // IS NOT NULL / IS NULL
    final isNotNullMatch = RegExp(
      r'^(.+?)\s+IS\s+NOT\s+NULL$',
      caseSensitive: false,
    ).firstMatch(cond);
    if (isNotNullMatch != null) {
      final val = _resolveColumnValue(row, isNotNullMatch.group(1)!.trim());
      return val != null;
    }

    final isNullMatch = RegExp(
      r'^(.+?)\s+IS\s+NULL$',
      caseSensitive: false,
    ).firstMatch(cond);
    if (isNullMatch != null) {
      final val = _resolveColumnValue(row, isNullMatch.group(1)!.trim());
      return val == null;
    }

    // IN (...)
    final inMatch = RegExp(
      r'^(.+?)\s+IN\s*\((.+)\)$',
      caseSensitive: false,
    ).firstMatch(cond);
    if (inMatch != null) {
      final leftVal = _resolveColumnValue(row, inMatch.group(1)!.trim());
      final items = _splitTopLevelComma(inMatch.group(2)!)
          .map((e) => _parseLiteral(e.trim()))
          .toList();
      return items.any((item) => _valuesEqual(leftVal, item));
    }

    // LIKE
    final likeMatch = RegExp(
      r'^(.+?)\s+LIKE\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(cond);
    if (likeMatch != null) {
      final leftVal =
          _resolveColumnValue(row, likeMatch.group(1)!.trim())?.toString() ??
              '';
      final patternRaw =
          _parseLiteral(likeMatch.group(2)!.trim())?.toString() ?? '';
      final regexPattern = '^' +
          RegExp.escape(patternRaw)
              .replaceAll('%', '.*')
              .replaceAll('_', '.') +
          r'$';
      return RegExp(regexPattern, caseSensitive: false).hasMatch(leftVal);
    }

    // Comparison operators: !=, <>, <=, >=, =, <, >
    for (final op in ['!=', '<>', '<=', '>=', '=', '<', '>']) {
      final idx = cond.indexOf(op);
      if (idx > 0) {
        final leftStr = cond.substring(0, idx).trim();
        final rightStr = cond.substring(idx + op.length).trim();
        final leftVal = _evaluateRowExpression(row, leftStr);
        final rightVal = _evaluateRowExpression(row, rightStr);
        switch (op) {
          case '=':
            return _valuesEqual(leftVal, rightVal);
          case '!=':
          case '<>':
            return !_valuesEqual(leftVal, rightVal);
          case '<':
            return _compareValues(leftVal, rightVal) < 0;
          case '>':
            return _compareValues(leftVal, rightVal) > 0;
          case '<=':
            return _compareValues(leftVal, rightVal) <= 0;
          case '>=':
            return _compareValues(leftVal, rightVal) >= 0;
        }
      }
    }

    return true;
  }

  static _ProjectionItem _parseProjectionItem(String rawItem) {
    final trimmed = rawItem.trim();
    final asMatch = RegExp(
      r'^(.+?)\s+AS\s+([a-zA-Z0-9_"]+)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (asMatch != null) {
      return _ProjectionItem(
        expr: asMatch.group(1)!.trim(),
        outputName: _stripQuotes(asMatch.group(2)!.trim()),
      );
    }
    // Unaliased qualified column like u.username -> outputName 'username'
    if (RegExp(r'^[a-zA-Z0-9_]+\.[a-zA-Z0-9_]+$').hasMatch(trimmed)) {
      return _ProjectionItem(
        expr: trimmed,
        outputName: trimmed.split('.').last,
      );
    }
    return _ProjectionItem(expr: trimmed, outputName: _stripQuotes(trimmed));
  }

  static bool _isAggregateExpr(String item) {
    return RegExp(
      r'\b(COUNT|SUM|AVG|MIN|MAX)\s*\(',
      caseSensitive: false,
    ).hasMatch(item);
  }

  static dynamic _evaluateGroupExpression(
    List<Map<String, dynamic>> groupRows,
    String expr,
  ) {
    final trimmed = expr.trim();
    final aggMatch = RegExp(
      r'^(COUNT|SUM|AVG|MIN|MAX)\s*\(\s*(?:DISTINCT\s+)?(.+?)\s*\)$',
      caseSensitive: false,
    ).firstMatch(trimmed);

    if (aggMatch != null) {
      final fn = aggMatch.group(1)!.toUpperCase();
      final arg = aggMatch.group(2)!.trim();
      final isDistinct = RegExp(r'\(\s*DISTINCT\s+', caseSensitive: false)
          .hasMatch(trimmed);

      if (fn == 'COUNT') {
        if (arg == '*') return groupRows.length;
        final vals = groupRows
            .map((r) => _resolveColumnValue(r, arg))
            .where((v) => v != null);
        return isDistinct ? vals.toSet().length : vals.length;
      }

      final numVals = <double>[];
      final rawVals = <dynamic>[];
      for (final r in groupRows) {
        final v = _resolveColumnValue(r, arg);
        if (v != null) {
          rawVals.add(v);
          if (v is num) {
            numVals.add(v.toDouble());
          } else {
            final parsed = double.tryParse(v.toString());
            if (parsed != null) numVals.add(parsed);
          }
        }
      }

      if (fn == 'SUM') {
        if (numVals.isEmpty) return 0;
        final sum = numVals.fold<double>(0.0, (a, b) => a + b);
        return sum == sum.roundToDouble() ? sum.toInt() : sum;
      }
      if (fn == 'AVG') {
        if (numVals.isEmpty) return 0.0;
        final avg = numVals.fold<double>(0.0, (a, b) => a + b) / numVals.length;
        return double.parse(avg.toStringAsFixed(2));
      }
      if (fn == 'MIN') {
        if (rawVals.isEmpty) return null;
        rawVals.sort(_compareValues);
        return rawVals.first;
      }
      if (fn == 'MAX') {
        if (rawVals.isEmpty) return null;
        rawVals.sort(_compareValues);
        return rawVals.last;
      }
    }

    if (groupRows.isEmpty) return null;
    return _evaluateRowExpression(groupRows.first, trimmed);
  }

  static dynamic _evaluateRowExpression(
    Map<String, dynamic> row,
    String expr,
  ) {
    final trimmed = expr.trim();
    if ((trimmed.startsWith("'") && trimmed.endsWith("'")) ||
        (trimmed.startsWith('"') && trimmed.endsWith('"'))) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    if (trimmed.toUpperCase() == 'NULL') return null;
    if (trimmed.toUpperCase() == 'TRUE') return 1;
    if (trimmed.toUpperCase() == 'FALSE') return 0;
    final intVal = int.tryParse(trimmed);
    if (intVal != null) return intVal;
    final doubleVal = double.tryParse(trimmed);
    if (doubleVal != null) return doubleVal;

    // Simple arithmetic (+, -, *, /) on column + literal
    for (final op in [' + ', ' - ', ' * ', ' / ']) {
      final idx = trimmed.indexOf(op);
      if (idx > 0) {
        final lv = _evaluateRowExpression(row, trimmed.substring(0, idx));
        final rv =
            _evaluateRowExpression(row, trimmed.substring(idx + op.length));
        if (lv is num && rv is num) {
          switch (op.trim()) {
            case '+':
              return lv + rv;
            case '-':
              return lv - rv;
            case '*':
              return lv * rv;
            case '/':
              return rv == 0 ? null : lv / rv;
          }
        }
      }
    }

    return _resolveColumnValue(row, trimmed);
  }

  static dynamic _resolveColumnValue(Map<String, dynamic> row, String colExpr) {
    final clean = _stripQuotes(colExpr.trim());
    if (row.containsKey(clean)) return row[clean];
    for (final entry in row.entries) {
      if (entry.key.toLowerCase() == clean.toLowerCase()) {
        return entry.value;
      }
    }
    if (clean.contains('.')) {
      final shortName = clean.split('.').last;
      if (row.containsKey(shortName)) return row[shortName];
      for (final entry in row.entries) {
        if (entry.key.toLowerCase() == shortName.toLowerCase()) {
          return entry.value;
        }
      }
    }
    return _parseLiteral(colExpr);
  }

  static dynamic _resolveOrderValue(Map<String, dynamic> row, String colExpr) {
    final clean = _stripQuotes(colExpr.trim());
    if (row.containsKey(clean)) return row[clean];
    if (clean.contains('.')) {
      final shortName = clean.split('.').last;
      if (row.containsKey(shortName)) return row[shortName];
    }
    for (final entry in row.entries) {
      if (entry.key.toLowerCase() == clean.toLowerCase()) {
        return entry.value;
      }
    }
    return null;
  }

  static bool _valuesEqual(dynamic a, dynamic b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a is num && b is num) return a.toDouble() == b.toDouble();
    final aNum = num.tryParse(a.toString());
    final bNum = num.tryParse(b.toString());
    if (aNum != null && bNum != null) {
      return aNum.toDouble() == bNum.toDouble();
    }
    return a.toString().toLowerCase() == b.toString().toLowerCase();
  }

  static int _compareValues(dynamic a, dynamic b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    if (a is num && b is num) return a.compareTo(b);
    final aNum = num.tryParse(a.toString());
    final bNum = num.tryParse(b.toString());
    if (aNum != null && bNum != null) return aNum.compareTo(bNum);
    return a.toString().compareTo(b.toString());
  }

  static dynamic _parseLiteral(String raw) {
    final t = raw.trim();
    if (t.isEmpty || t.toUpperCase() == 'NULL') return null;
    if ((t.startsWith("'") && t.endsWith("'")) ||
        (t.startsWith('"') && t.endsWith('"'))) {
      return t.substring(1, t.length - 1);
    }
    if (t.toUpperCase() == 'TRUE') return 1;
    if (t.toUpperCase() == 'FALSE') return 0;
    final i = int.tryParse(t);
    if (i != null) return i;
    final d = double.tryParse(t);
    if (d != null) return d;
    return t;
  }

  static String _sqlLiteral(dynamic value) {
    if (value == null) return 'NULL';
    if (value is num) return value.toString();
    if (value is bool) return value ? '1' : '0';
    final escaped = value.toString().replaceAll("'", "''");
    return "'$escaped'";
  }

  static DbTableSchema? _findTable(List<DbTableSchema> tables, String name) {
    final clean = _stripQuotes(name.trim()).toLowerCase();
    for (final t in tables) {
      if (t.name.toLowerCase() == clean) return t;
    }
    return null;
  }

  static String _stripQuotes(String s) {
    final t = s.trim();
    if (t.length >= 2 &&
        ((t.startsWith('"') && t.endsWith('"')) ||
            (t.startsWith('`') && t.endsWith('`')) ||
            (t.startsWith("'") && t.endsWith("'")))) {
      return t.substring(1, t.length - 1);
    }
    return t;
  }

  static String _stripSqlComments(String sql) {
    final lines = sql.split('\n');
    final buf = StringBuffer();
    for (final line in lines) {
      final commentIdx = line.indexOf('--');
      if (commentIdx >= 0) {
        buf.writeln(line.substring(0, commentIdx));
      } else {
        buf.writeln(line);
      }
    }
    return buf.toString();
  }

  static List<String> _splitStatements(String sql) {
    final res = <String>[];
    final current = StringBuffer();
    var inSingle = false;
    var inDouble = false;

    for (var i = 0; i < sql.length; i++) {
      final ch = sql[i];
      if (ch == "'" && !inDouble) inSingle = !inSingle;
      if (ch == '"' && !inSingle) inDouble = !inDouble;
      if (ch == ';' && !inSingle && !inDouble) {
        final s = current.toString().trim();
        if (s.isNotEmpty) res.add(s);
        current.clear();
      } else {
        current.write(ch);
      }
    }
    final tail = current.toString().trim();
    if (tail.isNotEmpty) res.add(tail);
    return res;
  }

  static List<String> _splitTopLevelComma(String input) {
    final res = <String>[];
    final current = StringBuffer();
    var depth = 0;
    var inSingle = false;
    var inDouble = false;

    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (ch == "'" && !inDouble) inSingle = !inSingle;
      if (ch == '"' && !inSingle) inDouble = !inDouble;
      if (!inSingle && !inDouble) {
        if (ch == '(') depth++;
        if (ch == ')' && depth > 0) depth--;
        if (ch == ',' && depth == 0) {
          res.add(current.toString().trim());
          current.clear();
          continue;
        }
      }
      current.write(ch);
    }
    final tail = current.toString().trim();
    if (tail.isNotEmpty) res.add(tail);
    return res;
  }

  static List<String> _splitByLogicalOp(String input, String op) {
    final pattern = RegExp('\\s+$op\\s+', caseSensitive: false);
    final matches = pattern.allMatches(input).toList();
    if (matches.isEmpty) return [input];

    final parts = <String>[];
    var lastStart = 0;
    for (final m in matches) {
      final prefix = input.substring(0, m.start);
      final openParens = '('.allMatches(prefix).length;
      final closeParens = ')'.allMatches(prefix).length;
      final singleQuotes = "'".allMatches(prefix).length;
      if (openParens == closeParens && singleQuotes.isEven) {
        parts.add(input.substring(lastStart, m.start).trim());
        lastStart = m.end;
      }
    }
    if (parts.isEmpty) return [input];
    parts.add(input.substring(lastStart).trim());
    return parts;
  }

  // --- Export & DDL Formatting Helpers ---

  /// Exports a `QueryResult` to RFC-4180 CSV text.
  static String exportToCsv(QueryResult result) {
    final buf = StringBuffer();
    buf.writeln(result.columns.map(_escapeCsvField).join(','));
    for (final row in result.rows) {
      final cells = result.columns.map((c) {
        final v = row[c];
        return v == null ? '' : _escapeCsvField(v.toString());
      });
      buf.writeln(cells.join(','));
    }
    return buf.toString();
  }

  static String _escapeCsvField(String field) {
    if (field.contains(',') || field.contains('"') || field.contains('\n')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }

  /// Exports a `QueryResult` to pretty-printed JSON array.
  static String exportToJson(QueryResult result) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(result.rows);
  }

  /// Exports a `QueryResult` as executable `INSERT INTO ... VALUES (...)` statements.
  static String exportToSqlInserts(String tableName, QueryResult result) {
    final buf = StringBuffer();
    final cols = result.columns.join(', ');
    for (final row in result.rows) {
      final vals = result.columns.map((c) => _sqlLiteral(row[c])).join(', ');
      buf.writeln('INSERT INTO $tableName ($cols) VALUES ($vals);');
    }
    return buf.toString();
  }

  /// Generates clean, formatted `CREATE TABLE` DDL along with index and trigger definitions.
  static String generateTableDdl(DbTableSchema table) {
    if (table.isView && table.ddlSql.trim().isNotEmpty) {
      return table.ddlSql;
    }
    final buf = StringBuffer();
    buf.writeln('CREATE TABLE ${table.name} (');
    for (var i = 0; i < table.columns.length; i++) {
      final c = table.columns[i];
      final parts = <String>['  ${c.name}', c.dataType];
      if (c.isPrimaryKey) parts.add('PRIMARY KEY');
      if (!c.isNullable && !c.isPrimaryKey) parts.add('NOT NULL');
      if (c.isUnique && !c.isPrimaryKey) parts.add('UNIQUE');
      if (c.defaultValue != null && c.defaultValue!.isNotEmpty) {
        parts.add('DEFAULT ${c.defaultValue}');
      }
      if (c.isForeignKey) {
        final fkParts = c.foreignKeyTarget!.split('.');
        parts.add('REFERENCES ${fkParts.first}(${fkParts.last})');
      }
      final comma = i < table.columns.length - 1 ? ',' : '';
      buf.writeln('${parts.join(' ')}$comma');
    }
    buf.writeln(');');

    if (table.indexes.isNotEmpty) {
      buf.writeln();
      for (final idx in table.indexes) {
        final u = idx.isUnique ? 'UNIQUE ' : '';
        buf.writeln(
          'CREATE ${u}INDEX ${idx.name} ON ${table.name} (${idx.columns.join(', ')});',
        );
      }
    }

    if (table.triggers.isNotEmpty) {
      buf.writeln();
      for (final trg in table.triggers) {
        buf.writeln(trg.definitionSql);
      }
    }
    return buf.toString().trim();
  }

  /// Pretty-formats SQL keywords and clause line breaks.
  static String formatSql(String sql) {
    var out = sql.trim();
    const keywords = [
      'SELECT',
      'FROM',
      'INNER JOIN',
      'LEFT JOIN',
      'JOIN',
      'WHERE',
      'GROUP BY',
      'ORDER BY',
      'LIMIT',
      'OFFSET',
      'INSERT INTO',
      'VALUES',
      'UPDATE',
      'SET',
      'DELETE FROM',
      'CREATE TABLE',
      'DROP TABLE',
      'EXPLAIN QUERY PLAN',
      'AND',
      'OR',
      'ON',
      'AS',
      'ASC',
      'DESC',
      'COUNT',
      'SUM',
      'AVG',
      'MIN',
      'MAX',
    ];
    for (final kw in keywords) {
      out = out.replaceAllMapped(
        RegExp('\\b$kw\\b', caseSensitive: false),
        (_) => kw,
      );
    }
    for (final clause in [
      'FROM',
      'INNER JOIN',
      'LEFT JOIN',
      'JOIN',
      'WHERE',
      'GROUP BY',
      'ORDER BY',
      'LIMIT',
    ]) {
      out = out.replaceAllMapped(
        RegExp('\\s+($clause)\\b'),
        (m) => '\n${m.group(1)}',
      );
    }
    return out.trim();
  }
}

class _ProjectionItem {
  final String expr;
  final String outputName;
  const _ProjectionItem({required this.expr, required this.outputName});
}
