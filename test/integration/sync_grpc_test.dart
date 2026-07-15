@TestOn('vm')
@Tags(['integration'])

import 'dart:convert';

import 'package:sync_client/src/http_helper.dart';
import 'package:sync_client/sync_client.dart';
import 'package:test/test.dart';

const serverUrl = 'http://localhost:8076';
const realm = 'integration_test';
const grpcHost = 'localhost';
const grpcPort = 50052;

final grpcTableInfos = {
  'todos': TableInfo(keyField: 'rowguid', binaryFields: [], encryptedFields: []),
};

Future<SQLiteWrapperSyncGRPC> openGrpcDb({
  required String dbName,
  required bool initSync,
}) async {
  final db = SQLiteWrapperSyncGRPC(
    tableInfos: grpcTableInfos,
    host: grpcHost,
    port: grpcPort,
  );
  await db.openDB('ignored', dbName: dbName, onCreate: () async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS "todos" (
        "rowguid" varchar(36) PRIMARY KEY NOT NULL,
        "title" varchar(255) NOT NULL,
        "done" int default 0
      )
    ''', dbName: dbName);
    if (initSync) {
      await db.initSyncTables(dbName: dbName);
    }
  });
  return db;
}

/// Register user on the sync server via direct HTTP and configure local sync DB.
Future<void> registerGrpcUser(
    SQLiteWrapperSyncGRPC db, String email, String dbName) async {
  final clientId = db.newUUID();
  // Register on server
  await httpHelper.call(
    '$serverUrl/register/$realm', {},
    body: jsonEncode({
      'name': 'GRPC User',
      'email': email,
      'password': 'test',
      'clientId': clientId,
      'clientDescription': '{"name":"GRPC"}',
      'newRegistration': true,
      'language': 'en',
    }),
    method: 'POST',
  );
  // Configure local sync tables
  await db.execute(
    "INSERT INTO sync_details (clientid, useremail, userpassword) VALUES ('$clientId', '$email', '${EncryptHelper.encryptPassword('test')}')",
    dbName: dbName,
  );
}

void main() {
  late String email;
  late SQLiteWrapperSyncGRPC db1;
  late SQLiteWrapperSyncGRPC db2;
  late SyncRepository repo1;
  late SyncRepository repo2;
  String? rowGuid1;
  String? rowGuid2;

  group('Integration: gRPC - CRUD + sync REST end-to-end', () {
    setUpAll(() async {
      email = 'grpc_all_${DateTime.now().millisecondsSinceEpoch}@test.com';
      db1 = await openGrpcDb(dbName: 'grpc_test', initSync: true);
      db2 = await openGrpcDb(dbName: 'grpc_test', initSync: true);
      repo1 = SyncRepository(
        sqliteWrapperSync: db1,
        serverUrl: serverUrl,
        realm: realm,
      );
      repo2 = SyncRepository(
        sqliteWrapperSync: db2,
        serverUrl: serverUrl,
        realm: realm,
      );

      // Directly populate sync_details for CRUD tests
      await db1.execute(
        "INSERT OR IGNORE INTO sync_details (clientid, useremail, userpassword) VALUES ('crud-client', '$email', 'test')",
        dbName: 'grpc_test',
      );
    });

    test('insert via gRPC creates todo and sync_data row', () async {
      final guid = db1.newUUID();
      await db1.insert(
        {'rowguid': guid, 'title': 'gRPC Item', 'done': 0},
        'todos',
        dbName: 'grpc_test',
      );
      final todo = await db1.query(
        "SELECT * FROM todos WHERE rowguid = '$guid'",
        singleResult: true,
        dbName: 'grpc_test',
      ) as Map<String, dynamic>?;
      expect(todo, isNotNull);
      expect(todo!['title'], equals('gRPC Item'));
      final shouldSync = await db1.shouldSync(dbName: 'grpc_test');
      expect(shouldSync, isTrue);
    });

    test('update via gRPC', () async {
      final todos = await db1.query(
        "SELECT rowguid FROM todos WHERE title = 'gRPC Item'",
        dbName: 'grpc_test',
      ) as List;
      expect(todos, isNotEmpty);
      rowGuid1 = todos.first as String;
      await db1.update(
        {'rowguid': rowGuid1, 'title': 'gRPC Updated', 'done': 0},
        'todos',
        keys: ['rowguid'],
        dbName: 'grpc_test',
      );
      final todo = await db1.query(
        "SELECT title FROM todos WHERE rowguid = '$rowGuid1'",
        singleResult: true,
        dbName: 'grpc_test',
      );
      expect(todo, equals('gRPC Updated'));
    });

    test('delete via gRPC', () async {
      final guid = db1.newUUID();
      await db1.insert(
        {'rowguid': guid, 'title': 'To Delete', 'done': 0},
        'todos',
        dbName: 'grpc_test',
      );
      await db1.delete(
        {'rowguid': guid},
        'todos',
        keys: ['rowguid'],
        dbName: 'grpc_test',
      );
      final deleted = await db1.query(
        "SELECT * FROM todos WHERE rowguid = '$guid'",
        singleResult: true,
        dbName: 'grpc_test',
      );
      expect(deleted, isNull);
    });

    test('register and sync across clients', () async {
      // Clear local sync config and data from previous tests
      await db1.execute('DELETE FROM sync_details', dbName: 'grpc_test');
      await db1.execute('DELETE FROM sync_data', dbName: 'grpc_test');
      await db1.execute('DELETE FROM sync_encryption', dbName: 'grpc_test');
      await db1.execute('DELETE FROM todos', dbName: 'grpc_test');

      // Register via direct HTTP and configure local DB
      await registerGrpcUser(db1, email, 'grpc_test');

      // Configure second client (same user)
      final clientId2 = db2.newUUID();
      await httpHelper.call(
        '$serverUrl/register/$realm', {},
        body: jsonEncode({
          'name': 'GRPC 2',
          'email': email,
          'password': 'test',
          'clientId': clientId2,
          'clientDescription': '{"name":"GRPC2"}',
          'newRegistration': false,
          'language': 'en',
        }),
        method: 'POST',
      );
      await db2.execute(
        "INSERT INTO sync_details (clientid, useremail, userpassword) VALUES ('$clientId2', '$email', '${EncryptHelper.encryptPassword('test')}')",
        dbName: 'grpc_test',
      );

      rowGuid1 = db1.newUUID();
      await db1.insert(
        {'rowguid': rowGuid1, 'title': 'GRPC CLIENT 1 - PRIMO', 'done': 0},
        'todos',
        dbName: 'grpc_test',
      );
      rowGuid2 = db1.newUUID();
      await db1.insert(
        {'rowguid': rowGuid2, 'title': 'GRPC CLIENT 1 - SECONDO', 'done': 0},
        'todos',
        dbName: 'grpc_test',
      );
      await repo1.sync(dbName: 'grpc_test');
      await repo2.sync(dbName: 'grpc_test');
      final count = await db2.query(
        'SELECT COUNT(*) FROM todos',
        singleResult: true,
        dbName: 'grpc_test',
      );
      expect(count, equals(2));
    });

    test('modify on client 2, sync, client 1 sees change', () async {
      await db2.update(
        {'rowguid': rowGuid2, 'title': 'GRPC MODIFICATO SUL CLIENT 2'},
        'todos',
        keys: ['rowguid'],
        dbName: 'grpc_test',
      );
      await repo2.sync(dbName: 'grpc_test');
      await repo1.sync(dbName: 'grpc_test');
      final title = await db1.query(
        "SELECT title FROM todos WHERE rowguid = '$rowGuid2'",
        singleResult: true,
        dbName: 'grpc_test',
      );
      expect(title, equals('GRPC MODIFICATO SUL CLIENT 2'));
    });

    test('delete on client 2, sync, client 1 sees deletion', () async {
      await db2.delete(
        {'rowguid': rowGuid1},
        'todos',
        keys: ['rowguid'],
        dbName: 'grpc_test',
      );
      await repo2.sync(dbName: 'grpc_test');
      await repo1.sync(dbName: 'grpc_test');
      final count = await db1.query(
        'SELECT COUNT(*) FROM todos',
        singleResult: true,
        dbName: 'grpc_test',
      );
      expect(count, equals(1));
    });
  });
}
