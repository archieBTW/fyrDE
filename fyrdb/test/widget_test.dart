import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:fyrdb/engine/sql_engine.dart';
import 'package:fyrdb/main.dart';
import 'package:fyrdb/models/db_models.dart';
import 'package:fyrdb/state/db_controller.dart';

void main() {
  group('fyrDB Relational SQL Engine & Export Suite', () {
    test('executes SELECT with WHERE, ORDER BY, LIMIT, JOIN, and Aggregates', () {
      final ctrl = DbController();
      final schemas = ctrl.activeSchemas;

      // 1. SELECT + WHERE + ORDER BY + LIMIT
      final r1 = SqlEngine.executeInMemory(
        "SELECT id, username, plan_tier FROM users WHERE plan_tier = 'enterprise' ORDER BY id DESC LIMIT 3;",
        schemas,
      );
      expect(r1.isSuccess, isTrue);
      expect(r1.columns, equals(['id', 'username', 'plan_tier']));
      expect(r1.rows.length, equals(3));
      expect(r1.rows.first['username'], equals('astrid'));

      // 2. Multi-table JOIN
      final r2 = SqlEngine.executeInMemory(
        'SELECT u.username, w.name AS workspace, d.service_name, d.replicas '
        'FROM deployments d '
        'JOIN workspaces w ON d.workspace_id = w.id '
        'JOIN users u ON w.owner_id = u.id '
        'WHERE d.replicas >= 6 '
        'ORDER BY d.replicas DESC;',
        schemas,
      );
      expect(r2.isSuccess, isTrue);
      expect(r2.rows.length, equals(2));
      expect(r2.rows.first['service_name'], equals('vllm-inference-router'));
      expect(r2.rows.first['workspace'], equals('tensor-cluster-a100'));
      expect(r2.rows.first['username'], equals('astrid'));

      // 3. GROUP BY + Aggregates (COUNT, SUM, AVG)
      final r3 = SqlEngine.executeInMemory(
        'SELECT status, COUNT(*) AS total_services, SUM(replicas) AS sum_replicas, AVG(latency_ms) AS avg_lat '
        'FROM deployments '
        'GROUP BY status '
        'ORDER BY sum_replicas DESC;',
        schemas,
      );
      expect(r3.isSuccess, isTrue);
      expect(r3.rows.isNotEmpty, isTrue);
      final healthyRow = r3.rows.firstWhere((r) => r['status'] == 'HEALTHY');
      expect(healthyRow['total_services'], equals(7));
      expect(healthyRow['sum_replicas'], equals(26));

      // 4. EXPLAIN QUERY PLAN
      final eqp = SqlEngine.executeInMemory(
        'EXPLAIN QUERY PLAN SELECT * FROM deployments d JOIN workspaces w ON d.workspace_id = w.id WHERE d.workspace_id = 101 ORDER BY d.id ASC;',
        schemas,
      );
      expect(eqp.isSuccess, isTrue);
      expect(eqp.explainPlan.length, greaterThanOrEqualTo(2));
    });

    test('executes CREATE TABLE, INSERT, UPDATE, and DELETE mutations', () {
      final ctrl = DbController();
      final schemas = ctrl.activeSchemas;

      final cRes = SqlEngine.executeInMemory(
        'CREATE TABLE feature_toggles (id INTEGER PRIMARY KEY, flag_key VARCHAR(64) NOT NULL, enabled BOOLEAN DEFAULT 1);',
        schemas,
      );
      expect(cRes.isSuccess, isTrue);
      expect(schemas.any((t) => t.name == 'feature_toggles'), isTrue);

      final iRes = SqlEngine.executeInMemory(
        "INSERT INTO feature_toggles (id, flag_key, enabled) VALUES (1, 'vulkan_hdr', 1), (2, 'wayland_fractional_scale', 0);",
        schemas,
      );
      expect(iRes.isSuccess, isTrue);
      expect(iRes.affectedRows, equals(2));

      final uRes = SqlEngine.executeInMemory(
        "UPDATE feature_toggles SET enabled = 1 WHERE flag_key = 'wayland_fractional_scale';",
        schemas,
      );
      expect(uRes.isSuccess, isTrue);
      expect(uRes.affectedRows, equals(1));

      final sRes = SqlEngine.executeInMemory(
        'SELECT * FROM feature_toggles WHERE enabled = 1;',
        schemas,
      );
      expect(sRes.rows.length, equals(2));

      final dRes = SqlEngine.executeInMemory(
        'DELETE FROM feature_toggles WHERE id = 1;',
        schemas,
      );
      expect(dRes.isSuccess, isTrue);
      expect(dRes.affectedRows, equals(1));
    });

    test('exports CSV, JSON, SQL INSERTs, and DDL', () {
      final ctrl = DbController();
      final res = ctrl.runSql('SELECT id, username, role FROM users LIMIT 2;');
      expect(res.isSuccess, isTrue);

      final csv = SqlEngine.exportToCsv(res);
      expect(csv, contains('id,username,role'));
      expect(csv, contains('1,archer,principal_architect'));

      final json = SqlEngine.exportToJson(res);
      expect(json, contains('"username": "archer"'));

      final sqlInserts = SqlEngine.exportToSqlInserts('users', res);
      expect(
        sqlInserts,
        contains(
          "INSERT INTO users (id, username, role) VALUES (1, 'archer', 'principal_architect');",
        ),
      );

      final ddl = SqlEngine.generateTableDdl(ctrl.activeTables.first);
      expect(ddl, contains('CREATE TABLE users'));
      expect(ddl, contains('PRIMARY KEY'));
    });

    test('seeds, queries, and introspects real SQLite 3 file on disk', () async {
      final tmpDir = await Directory.systemTemp.createTemp('fyrdb_sqlite_test_');
      try {
        final dbPath = '${tmpDir.path}/test_cloud.sqlite';
        final ctrl = DbController();
        if (SqlEngine.hasSqliteCli) {
          final seeded = await SqlEngine.seedSqliteFile(
            dbPath,
            ctrl.activeSchemas,
          );
          expect(seeded, isTrue);
          expect(File(dbPath).existsSync(), isTrue);

          final queryRes = await SqlEngine.executeOnSqliteFile(
            dbPath,
            'SELECT username, plan_tier FROM users WHERE active = 1 ORDER BY id ASC LIMIT 3;',
          );
          expect(queryRes.isSuccess, isTrue);
          expect(queryRes.rows.length, equals(3));
          expect(queryRes.rows.first['username'], equals('archer'));

          final introspected = await SqlEngine.introspectSqliteFile(dbPath);
          expect(introspected.length, greaterThanOrEqualTo(5));
        }
      } finally {
        await tmpDir.delete(recursive: true);
      }
    });

    test('manages connections, tabs, and inline cell edit commit/rollback', () {
      final ctrl = DbController();
      expect(ctrl.connections.length, equals(3));
      expect(ctrl.activeConnection.name, equals('fyr_cloud_prod'));

      // Switch connection
      ctrl.selectConnection('conn_analytics_duckdb');
      expect(ctrl.activeConnection.name, equals('analytics_warehouse'));
      ctrl.selectConnection('conn_fyr_cloud');

      // Stage inline cell edit and rollback
      ctrl.selectTable('deployments');
      final origStatus = ctrl.selectedTable!.rows.first['status'];
      ctrl.stageCellEdit('deployments', 0, 'status', 'MAINTENANCE');
      expect(ctrl.pendingEditCount, equals(1));
      expect(ctrl.selectedTable!.rows.first['status'], equals('MAINTENANCE'));

      ctrl.rollbackPendingChanges();
      expect(ctrl.pendingEditCount, equals(0));
      expect(ctrl.selectedTable!.rows.first['status'], equals(origStatus));

      // Stage inline cell edit and commit
      ctrl.stageCellEdit('deployments', 0, 'replicas', 12);
      expect(ctrl.pendingEditCount, equals(1));
      ctrl.commitPendingChanges();
      expect(ctrl.pendingEditCount, equals(0));
      expect(ctrl.selectedTable!.rows.first['replicas'], equals(12));
    });
  });

  group('fyrDB UI Widget Smoke Test', () {
    testWidgets(
      'renders fyrDB TopBar, Database Navigator, SQL Editor, Result Grid, and ER Diagram',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 880);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final ctrl = DbController();
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: ctrl,
            child: const FyrDbApp(),
          ),
        );
        await tester.pump();

        expect(find.text('fyrDB'), findsOneWidget);
        expect(find.text('DATABASE NAVIGATOR'), findsOneWidget);
        expect(find.text('01_active_clusters.sql'), findsOneWidget);
        expect(find.text('Result Grid'), findsOneWidget);
        expect(find.text('Execution Plan'), findsOneWidget);

        // Switch to Data Grid view
        await tester.tap(find.text('Data Grid'));
        await tester.pump();
        expect(ctrl.workspaceMode, equals(DbWorkspaceMode.dataGrid));

        // Switch to Table Structure & DDL view
        await tester.tap(find.text('Table Structure & DDL'));
        await tester.pump();
        expect(ctrl.workspaceMode, equals(DbWorkspaceMode.structureDdl));
        expect(find.text('Generated DDL Script'), findsOneWidget);

        // Switch to ER Diagram view
        await tester.tap(find.text('ER Diagram'));
        await tester.pump();
        expect(ctrl.workspaceMode, equals(DbWorkspaceMode.erDiagram));
        expect(find.text('Auto-Layout'), findsOneWidget);
      },
    );
  });
}
