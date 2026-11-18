import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/db_models.dart';

class SqlEngine {
  static bool? _hasSqliteCliCache;

  /// Checks whether `/usr/bin/sqlite3` is available on the host system.
  static bool get hasSqliteCli {
    if (_hasSqliteCliCache != null) return _hasSqliteCliCache!;
    try {
      _hasSqliteCliCache = File('/usr/bin/sqlite3').existsSync();
    } catch (_) {
      _hasSqliteCliCache = false;
    }
    return _hasSqliteCliCache!;
  }

  /// Builds the non-interactive CLI invocation for any supported database driver.
  static List<String> buildCliCommand(
    DbConnectionProfile profile,
    String sql,
  ) {
    switch (profile.driver) {
      case DbDriverType.sqlite:
        return [
          '/usr/bin/sqlite3',
          '-json',
          profile.databaseOrPath,
          sql,
        ];
      case DbDriverType.postgres:
        return [
          'psql',
          '-h',
          profile.host,
          '-p',
          '${profile.port}',
          '-U',
          profile.username,
          '-d',
          profile.databaseOrPath,
          '--csv',
          '-c',
          sql,
        ];
      case DbDriverType.mysql:
      case DbDriverType.mariadb:
        return [
          profile.driver.cliBinary,
          '-h',
          profile.host,
          '-P',
          '${profile.port}',
          '-u',
          profile.username,
          '-D',
          profile.databaseOrPath,
          '--batch',
          '-e',
          sql,
        ];
      case DbDriverType.duckdb:
        return [
          'duckdb',
          '-json',
          profile.databaseOrPath,
          '-c',
          sql,
        ];
      case DbDriverType.redis:
        return [
          'redis-cli',
          '-h',
          profile.host,
          '-p',
          '${profile.port}',
          ...sql.trim().split(RegExp(r'\s+')),
        ];
      case DbDriverType.clickhouse:
        return [
          'clickhouse-client',
          '--host',
          profile.host,
          '--port',
          '${profile.port}',
          '--database',
          profile.databaseOrPath,
          '--format',
          'JSONEachRow',
          '--query',
          sql,
        ];
    }
  }

  /// Materializes a list of `DbTableSchema` tables and their rows into a real SQLite 3
  /// file on disk using `/usr/bin/sqlite3` when available.
  static Future<bool> seedSqliteFile(
    String filePath,
    List<DbTableSchema> schemas,
  ) async {
    if (!hasSqliteCli) return false;
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
      final res = await Process.run('/usr/bin/sqlite3', [
        filePath,
        buffer.toString(),
      ]);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Executes a real SQL statement against a SQLite file on disk via `/usr/bin/sqlite3`.
  static Future<QueryResult> executeOnSqliteFile(
    String filePath,
    String sql,
  ) async {
    final sw = Stopwatch()..start();
    final trimmed = _stripSqlComments(sql).trim();
    if (!hasSqliteCli || !File(filePath).existsSync()) {
      return QueryResult(
        columns: const [],
        rows: const [],
        executionTimeMs: 0.2,
        error: 'SQLite file or /usr/bin/sqlite3 not found: $filePath',
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
        final eqpRes = await Process.run('/usr/bin/sqlite3', [
          '-json',
          filePath,
          'EXPLAIN QUERY PLAN $trimmed',
        ]);
        if (eqpRes.exitCode == 0) {
          final out = (eqpRes.stdout as String).trim();
          if (out.isNotEmpty) {
            final decoded = jsonDecode(out) as List<dynamic>;
            for (final item in decoded) {
              if (item is Map && item['detail'] != null) {
                explainPlan.add(item['detail'].toString());
              }
            }
          }
        }
      }

      if (isSelect) {
        final res = await Process.run('/usr/bin/sqlite3', [
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
        final res = await Process.run('/usr/bin/sqlite3', [
          filePath,
          '$trimmed;\nSELECT changes();',
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
            lines.isNotEmpty ? (int.tryParse(lines.last.trim()) ?? 1) : 1;
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
    String filePath,
  ) async {
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
            'PRAGMA foreign_key_list($tableName);',
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
          'PRAGMA table_info($tableName);',
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
            'PRAGMA index_list($tableName);',
          );
          for (final iRow in idxRes.rows) {
            final idxName = iRow['name']?.toString() ?? '';
            if (idxName.isEmpty) continue;
            final isUnique = (iRow['unique'] is int
                ? (iRow['unique'] as int) > 0
                : iRow['unique']?.toString() == '1');
            final infoRes = await executeOnSqliteFile(
              filePath,
              'PRAGMA index_info($idxName);',
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

        // Rows
        final dataRes = await executeOnSqliteFile(
          filePath,
          'SELECT * FROM $tableName LIMIT 200;',
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
