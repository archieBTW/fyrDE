import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:fyrdb/engine/sql_engine.dart';
import 'package:fyrdb/main.dart';
import 'package:fyrdb/models/db_models.dart';
import 'package:fyrdb/state/db_controller.dart';
import 'package:fyrdb/widgets/connection_wizard.dart';

List<DbTableSchema> _buildTestFixtureSchemas() {
  final users = DbTableSchema(
    name: 'users',
    schemaName: 'main',
    columns: const [
      DbColumnSchema(
        name: 'id',
        dataType: 'INTEGER',
        isPrimaryKey: true,
        isNullable: false,
      ),
      DbColumnSchema(
        name: 'username',
        dataType: 'TEXT',
        isNullable: false,
      ),
      DbColumnSchema(
        name: 'role',
        dataType: 'TEXT',
        isNullable: false,
      ),
      DbColumnSchema(
        name: 'plan_tier',
        dataType: 'TEXT',
        isNullable: false,
      ),
      DbColumnSchema(
        name: 'active',
        dataType: 'INTEGER',
        isNullable: false,
      ),
    ],
    rows: [
      {
        'id': 1,
        'username': 'alice',
        'role': 'architect',
        'plan_tier': 'enterprise',
        'active': 1,
      },
      {
        'id': 2,
        'username': 'bob',
        'role': 'engineer',
        'plan_tier': 'pro',
        'active': 1,
      },
      {
        'id': 3,
        'username': 'carol',
        'role': 'lead',
        'plan_tier': 'enterprise',
        'active': 1,
      },
    ],
  );
  users.ddlSql = SqlEngine.generateTableDdl(users);

  final services = DbTableSchema(
    name: 'services',
    schemaName: 'main',
    columns: const [
      DbColumnSchema(
        name: 'id',
        dataType: 'INTEGER',
        isPrimaryKey: true,
        isNullable: false,
      ),
      DbColumnSchema(
        name: 'owner_id',
        dataType: 'INTEGER',
        isNullable: false,
        foreignKeyTarget: 'users.id',
      ),
      DbColumnSchema(
        name: 'service_name',
        dataType: 'TEXT',
        isNullable: false,
      ),
      DbColumnSchema(
        name: 'status',
        dataType: 'TEXT',
        isNullable: false,
      ),
      DbColumnSchema(
        name: 'replicas',
        dataType: 'INTEGER',
        isNullable: false,
      ),
      DbColumnSchema(
        name: 'latency_ms',
        dataType: 'REAL',
        isNullable: false,
      ),
    ],
    rows: [
      {
        'id': 10,
        'owner_id': 1,
        'service_name': 'api-gateway',
        'status': 'HEALTHY',
        'replicas': 4,
        'latency_ms': 12.5,
      },
      {
        'id': 11,
        'owner_id': 3,
        'service_name': 'inference-router',
        'status': 'HEALTHY',
        'replicas': 8,
        'latency_ms': 24.0,
      },
      {
        'id': 12,
        'owner_id': 2,
        'service_name': 'batch-worker',
        'status': 'SCALING',
        'replicas': 2,
        'latency_ms': 45.0,
      },
    ],
  );
  services.ddlSql = SqlEngine.generateTableDdl(services);

  return [users, services];
}

void main() {
  group('fyrDB Clean Startup, Persistence & URI Parsing', () {
    test('starts cleanly with zero demo connections and null activeConnection', () {
      final ctrl = DbController(loadSaved: false, persistConnections: false);

      expect(ctrl.connections, isEmpty);
      expect(ctrl.activeConnection, isNull);
      expect(ctrl.activeConnectionId, isNull);
      expect(ctrl.activeSchemas, isEmpty);
      expect(ctrl.selectedTable, isNull);
      expect(ctrl.activeTab, isNull);
    });

    test('persists saved connections to connections.json without raw passwords', () async {
      final tmpDir = await Directory.systemTemp.createTemp('fyrdb_cfg_test_');
      try {
        final cfgPath = '${tmpDir.path}/connections.json';
        final ctrl = DbController(
          configFilePath: cfgPath,
          loadSaved: true,
          persistConnections: true,
        );
        expect(ctrl.connections, isEmpty);

        await ctrl.addConnection(
          DbConnectionProfile(
            id: 'conn_pg_test',
            name: 'local_pg',
            driver: DbDriverType.postgres,
            host: '127.0.0.1',
            port: 5432,
            databaseOrPath: 'app_db',
            username: 'postgres',
            password: 'super_secret_password',
            sslEnabled: true,
          ),
          schemas: [],
        );

        final rawJson = File(cfgPath).readAsStringSync();
        expect(rawJson, contains('local_pg'));
        expect(rawJson, contains('app_db'));
        expect(rawJson, isNot(contains('super_secret_password')));

        // Reload in a fresh controller instance
        final reloaded = DbController(
          configFilePath: cfgPath,
          loadSaved: true,
          persistConnections: true,
        );
        expect(reloaded.connections.length, equals(1));
        expect(reloaded.connections.first.name, equals('local_pg'));
        expect(reloaded.connections.first.password, isNull);
        expect(reloaded.activeConnection, isNull);

        // Remove connection and verify persistence updates
        await reloaded.removeConnection('conn_pg_test');
        expect(reloaded.connections, isEmpty);
        final afterDelete = DbController(
          configFilePath: cfgPath,
          loadSaved: true,
          persistConnections: true,
        );
        expect(afterDelete.connections, isEmpty);
      } finally {
        await tmpDir.delete(recursive: true);
      }
    });

    test('parses PostgreSQL, MySQL, and Redis connection URIs accurately', () {
      final pg = SqlEngine.parseConnectionUri(
        'postgres://admin:p%40ss@db.example.com:5433/prod_db?sslmode=require',
      );
      expect(pg, isNotNull);
      expect(pg!.driver, equals(DbDriverType.postgres));
      expect(pg.username, equals('admin'));
      expect(pg.password, equals('p@ss'));
      expect(pg.host, equals('db.example.com'));
      expect(pg.port, equals(5433));
      expect(pg.database, equals('prod_db'));
      expect(pg.sslEnabled, isTrue);

      final redis = SqlEngine.parseConnectionUri(
        'rediss://:secret@cache.internal:6380/2',
      );
      expect(redis, isNotNull);
      expect(redis!.driver, equals(DbDriverType.redis));
      expect(redis.password, equals('secret'));
      expect(redis.host, equals('cache.internal'));
      expect(redis.port, equals(6380));
      expect(redis.database, equals('2'));
      expect(redis.sslEnabled, isTrue);
    });
  });

  group('fyrDB Relational SQL Engine & Controller Suite', () {
    test('executes SELECT with WHERE, ORDER BY, LIMIT, JOIN, and Aggregates', () {
      final schemas = _buildTestFixtureSchemas();

      final r1 = SqlEngine.executeInMemory(
        "SELECT id, username, plan_tier FROM users WHERE plan_tier = 'enterprise' ORDER BY id DESC LIMIT 2;",
        schemas,
      );
      expect(r1.isSuccess, isTrue);
      expect(r1.columns, equals(['id', 'username', 'plan_tier']));
      expect(r1.rows.length, equals(2));
      expect(r1.rows.first['username'], equals('carol'));

      final r2 = SqlEngine.executeInMemory(
        'SELECT u.username, s.service_name, s.replicas '
        'FROM services s '
        'JOIN users u ON s.owner_id = u.id '
        'WHERE s.replicas >= 4 '
        'ORDER BY s.replicas DESC;',
        schemas,
      );
      expect(r2.isSuccess, isTrue);
      expect(r2.rows.length, equals(2));
      expect(r2.rows.first['service_name'], equals('inference-router'));
      expect(r2.rows.first['username'], equals('carol'));

      final r3 = SqlEngine.executeInMemory(
        'SELECT status, COUNT(*) AS total_services, SUM(replicas) AS sum_replicas '
        'FROM services '
        'GROUP BY status '
        'ORDER BY sum_replicas DESC;',
        schemas,
      );
      expect(r3.isSuccess, isTrue);
      final healthyRow = r3.rows.firstWhere((r) => r['status'] == 'HEALTHY');
      expect(healthyRow['total_services'], equals(2));
      expect(healthyRow['sum_replicas'], equals(12));

      final eqp = SqlEngine.executeInMemory(
        'EXPLAIN QUERY PLAN SELECT * FROM services s JOIN users u ON s.owner_id = u.id WHERE s.id = 10;',
        schemas,
      );
      expect(eqp.isSuccess, isTrue);
      expect(eqp.explainPlan.length, greaterThanOrEqualTo(2));
    });

    test('executes CREATE TABLE, INSERT, UPDATE, and DELETE mutations', () {
      final schemas = <DbTableSchema>[];

      final cRes = SqlEngine.executeInMemory(
        'CREATE TABLE feature_toggles (id INTEGER PRIMARY KEY, flag_key VARCHAR(64) NOT NULL, enabled BOOLEAN DEFAULT 1);',
        schemas,
      );
      expect(cRes.isSuccess, isTrue);
      expect(schemas.any((t) => t.name == 'feature_toggles'), isTrue);

      final iRes = SqlEngine.executeInMemory(
        "INSERT INTO feature_toggles (id, flag_key, enabled) VALUES (1, 'vulkan_hdr', 1), (2, 'fractional_scale', 0);",
        schemas,
      );
      expect(iRes.isSuccess, isTrue);
      expect(iRes.affectedRows, equals(2));

      final uRes = SqlEngine.executeInMemory(
        "UPDATE feature_toggles SET enabled = 1 WHERE flag_key = 'fractional_scale';",
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

    test('exports CSV, JSON, SQL INSERTs, and DDL', () async {
      final ctrl = DbController(loadSaved: false, persistConnections: false);
      await ctrl.addConnection(
        DbConnectionProfile(
          id: 'conn_mem',
          name: 'in_memory_db',
          driver: DbDriverType.sqlite,
          databaseOrPath: ':memory:',
        ),
        schemas: _buildTestFixtureSchemas(),
      );

      final res = ctrl.runSql('SELECT id, username, role FROM users LIMIT 2;');
      expect(res.isSuccess, isTrue);

      final csv = SqlEngine.exportToCsv(res);
      expect(csv, contains('id,username,role'));
      expect(csv, contains('1,alice,architect'));

      final json = SqlEngine.exportToJson(res);
      expect(json, contains('"username": "alice"'));

      final sqlInserts = SqlEngine.exportToSqlInserts('users', res);
      expect(
        sqlInserts,
        contains(
          "INSERT INTO users (id, username, role) VALUES (1, 'alice', 'architect');",
        ),
      );

      final ddl = SqlEngine.generateTableDdl(ctrl.activeTables.first);
      expect(ddl, contains('CREATE TABLE users'));
      expect(ddl, contains('PRIMARY KEY'));
    });

    test('creates, seeds, queries, and introspects a real SQLite 3 file on disk', () async {
      final tmpDir = await Directory.systemTemp.createTemp('fyrdb_sqlite_test_');
      try {
        final dbPath = '${tmpDir.path}/real_local.sqlite';
        if (SqlEngine.hasSqliteCli) {
          final created = await SqlEngine.createSqliteFile(dbPath);
          expect(created, isTrue);
          expect(File(dbPath).existsSync(), isTrue);

          final seeded = await SqlEngine.seedSqliteFile(
            dbPath,
            _buildTestFixtureSchemas(),
          );
          expect(seeded, isTrue);

          final testRes = await SqlEngine.testConnection(
            DbConnectionProfile(
              id: 'conn_disk',
              name: 'real_local.sqlite',
              driver: DbDriverType.sqlite,
              databaseOrPath: dbPath,
            ),
          );
          expect(testRes.success, isTrue);

          final queryRes = await SqlEngine.executeOnSqliteFile(
            dbPath,
            'SELECT username, plan_tier FROM users WHERE active = 1 ORDER BY id ASC;',
          );
          expect(queryRes.isSuccess, isTrue);
          expect(queryRes.rows.length, equals(3));
          expect(queryRes.rows.first['username'], equals('alice'));

          final introspected = await SqlEngine.introspectSqliteFile(dbPath);
          expect(introspected.length, equals(2));
        }
      } finally {
        await tmpDir.delete(recursive: true);
      }
    });

    test('manages connections, disconnect, and inline cell edit commit/rollback', () async {
      final ctrl = DbController(loadSaved: false, persistConnections: false);
      await ctrl.addConnection(
        DbConnectionProfile(
          id: 'conn_a',
          name: 'mem_a',
          driver: DbDriverType.sqlite,
          databaseOrPath: ':memory:',
        ),
        schemas: _buildTestFixtureSchemas(),
      );
      expect(ctrl.connections.length, equals(1));
      expect(ctrl.activeConnection?.name, equals('mem_a'));

      // Stage inline cell edit and rollback
      ctrl.selectTable('services');
      final origStatus = ctrl.selectedTable!.rows.first['status'];
      ctrl.stageCellEdit('services', 0, 'status', 'MAINTENANCE');
      expect(ctrl.pendingEditCount, equals(1));
      expect(ctrl.selectedTable!.rows.first['status'], equals('MAINTENANCE'));

      ctrl.rollbackPendingChanges();
      expect(ctrl.pendingEditCount, equals(0));
      expect(ctrl.selectedTable!.rows.first['status'], equals(origStatus));

      // Stage inline cell edit and commit
      ctrl.stageCellEdit('services', 0, 'replicas', 12);
      expect(ctrl.pendingEditCount, equals(1));
      await ctrl.commitPendingChanges();
      expect(ctrl.pendingEditCount, equals(0));
      expect(ctrl.selectedTable!.rows.first['replicas'], equals(12));

      // Disconnect returns activeConnection to null
      ctrl.disconnectActive();
      expect(ctrl.activeConnection, isNull);
      expect(ctrl.connections.length, equals(1));
    });
  });

  group('fyrDB Connection Setup Wizard & Workspace Widget Tests', () {
    testWidgets(
      'clean startup with zero demo connections shows Connection Setup Wizard and navigates all 3 steps',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 880);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final ctrl = DbController(loadSaved: false, persistConnections: false);
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: ctrl,
            child: const FyrDbApp(),
          ),
        );
        await tester.pump();

        // Clean empty state shows wizard and zero demo connections
        expect(find.text('fyrDB'), findsOneWidget);
        expect(find.text('DATABASE NAVIGATOR'), findsOneWidget);
        expect(find.text('No Saved Connections'), findsOneWidget);
        expect(find.byType(ConnectionWizard), findsOneWidget);
        expect(find.text('Connection Setup Wizard'), findsOneWidget);
        expect(find.text('1. Engine'), findsOneWidget);
        expect(find.text('2. Configure'), findsOneWidget);
        expect(find.text('3. Test & Connect'), findsOneWidget);

        // Step 1: Select SQLite and go to Step 2
        await tester.tap(find.byKey(const ValueKey('engine_card_sqlite')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('wizard_next_btn')));
        await tester.pump();

        expect(find.text('Configure SQLite 3'), findsOneWidget);
        expect(find.text('Browse Existing File'), findsOneWidget);
        expect(find.text('Create New File'), findsOneWidget);

        // Step 2: Fill in connection details (:memory:) and advance to Step 3
        await tester.enterText(
          find.byKey(const ValueKey('wizard_name_field')),
          'my_local_sqlite',
        );
        await tester.enterText(
          find.byKey(const ValueKey('wizard_path_field')),
          ':memory:',
        );
        await tester.tap(find.byKey(const ValueKey('wizard_next_btn')));
        await tester.pump();

        // Step 3: Verify summary, run Test Connection, and Connect
        expect(find.text('Review, Test & Connect'), findsOneWidget);
        expect(find.text('my_local_sqlite'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('wizard_test_conn_btn')));
        await tester.pumpAndSettle();
        expect(find.text('In-memory SQLite workspace ready.'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('wizard_connect_btn')));
        await tester.pumpAndSettle();

        // Workspace is now active with the new connection!
        expect(ctrl.activeConnection?.name, equals('my_local_sqlite'));
        expect(find.byType(ConnectionWizard), findsNothing);
        expect(find.text('Result Grid'), findsOneWidget);
        expect(find.text('Execution Plan'), findsOneWidget);

        // Switch workspace views cleanly even with 0 tables
        // (DragToMoveArea registers a DoubleTapGestureRecognizer on TopBar,
        // so pump past kDoubleTapTimeout = 300ms for single-tap resolution.)
        await tester.ensureVisible(find.text('Data Grid'));
        await tester.tap(find.text('Data Grid'));
        await tester.pump(const Duration(milliseconds: 350));
        expect(ctrl.workspaceMode, equals(DbWorkspaceMode.dataGrid));

        await tester.ensureVisible(find.text('Table Structure & DDL'));
        await tester.tap(find.text('Table Structure & DDL'));
        await tester.pump(const Duration(milliseconds: 350));
        expect(ctrl.workspaceMode, equals(DbWorkspaceMode.structureDdl));

        await tester.ensureVisible(find.text('ER Diagram'));
        await tester.tap(find.text('ER Diagram'));
        await tester.pump(const Duration(milliseconds: 350));
        expect(ctrl.workspaceMode, equals(DbWorkspaceMode.erDiagram));
        expect(find.text('Auto-Layout'), findsOneWidget);
      },
    );
  });
}
