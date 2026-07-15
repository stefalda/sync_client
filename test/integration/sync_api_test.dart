@TestOn('vm')
@Tags(['integration'])

import 'package:sync_client/sync_client.dart';
import 'package:test/test.dart';

import '../helpers/test_db.dart';

const serverUrl = 'http://localhost:8076';
const realm = 'integration_test';

/// Integration tests require the Docker stack running:
///   docker compose -f test/integration/docker/docker-compose.yml up -d
///
/// Tests share the same realm and run sequentially via setUpAll.

SQLiteWrapperSync createIntegrationDb(String dbName) {
  return SQLiteWrapperSync(tableInfos: testTableInfos);
}

Future<SQLiteWrapperSync> openIntegrationDb({
  required String dbName,
  required bool initSync,
}) async {
  final db = createIntegrationDb(dbName);
  await db.openDB(':memory:', dbName: dbName, onCreate: () async {
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

SyncRepository createRepo(SQLiteWrapperSync db, String dbName) {
  return SyncRepository(
    sqliteWrapperSync: db,
    serverUrl: serverUrl,
    realm: realm,
  );
}

void main() {
  late String email;
  late SQLiteWrapperSync db1;
  late SQLiteWrapperSync db2;
  late SyncRepository repo1;
  late SyncRepository repo2;
  String? rowGuid1;
  String? rowGuid2;

  group('Integration: register, sync, modify, sync, verify', () {
    setUpAll(() async {
      email = 'inttest_${DateTime.now().millisecondsSinceEpoch}@test.com';
      db1 = await openIntegrationDb(dbName: 'int_db1', initSync: true);
      db2 = await openIntegrationDb(dbName: 'int_db2', initSync: true);
      repo1 = createRepo(db1, 'int_db1');
      repo2 = createRepo(db2, 'int_db2');
    });

    test('Register clients', () async {
      await repo1.register(
        name: 'Client 1',
        email: email,
        password: 'test',
        deviceInfo: '{"name":"CLIENT1"}',
        newRegistration: true,
        language: 'en',
        secretKey: '',
        dbName: 'int_db1',
      );
      await repo2.register(
        name: 'Client 2',
        email: email,
        password: 'test',
        deviceInfo: '{"name":"CLIENT2"}',
        newRegistration: false,
        language: 'en',
        secretKey: '',
        dbName: 'int_db2',
      );
    });

    test('Insert data and sync across clients', () async {
      rowGuid1 = db1.newUUID();
      await db1.insert(
        {'rowguid': rowGuid1, 'title': 'CLIENT 1 - PRIMO', 'done': 0},
        'todos',
        dbName: 'int_db1',
      );
      await db1.insert(
        {'rowguid': db1.newUUID(), 'title': 'CLIENT 1 - SECONDO', 'done': 0},
        'todos',
        dbName: 'int_db1',
      );
      rowGuid2 = db2.newUUID();
      await db2.insert(
        {'rowguid': rowGuid2, 'title': 'CLIENT 2 - PRIMO', 'done': 0},
        'todos',
        dbName: 'int_db2',
      );
      await db2.insert(
        {'rowguid': db2.newUUID(), 'title': 'CLIENT 2 - SECONDO', 'done': 1},
        'todos',
        dbName: 'int_db2',
      );
      await repo1.sync(dbName: 'int_db1');
      await repo2.sync(dbName: 'int_db2');
      final count = await db2.query(
        'SELECT COUNT(*) FROM todos',
        singleResult: true,
        dbName: 'int_db2',
      );
      expect(count, equals(4));
    });

    test('Delete a record and sync', () async {
      final todoMap = await db2.query(
        "SELECT * FROM todos WHERE rowguid = '$rowGuid1'",
        singleResult: true,
        dbName: 'int_db2',
      ) as Map<String, dynamic>?;
      expect(todoMap, isNotNull);
      await db2.delete(todoMap!, 'todos', keys: ['rowguid'], dbName: 'int_db2');
      await repo2.sync(dbName: 'int_db2');
      await repo1.sync(dbName: 'int_db1');
      final count = await db1.query(
        'SELECT COUNT(*) FROM todos',
        singleResult: true,
        dbName: 'int_db1',
      );
      expect(count, equals(3));
    });

    test('Modify a record and sync', () async {
      await db1.update(
        {'rowguid': rowGuid2, 'title': 'CLIENT 2 - PRIMO MODIFICATO SUL CLIENT 1'},
        'todos',
        keys: ['rowguid'],
        dbName: 'int_db1',
      );
      await repo1.sync(dbName: 'int_db1');
      await repo2.sync(dbName: 'int_db2');
      final title = await db2.query(
        "SELECT title FROM todos WHERE rowguid = '$rowGuid2'",
        singleResult: true,
        dbName: 'int_db2',
      );
      expect(title, equals('CLIENT 2 - PRIMO MODIFICATO SUL CLIENT 1'));
    });

    test('Concurrent modification: last write wins', () async {
      await db2.update(
        {'rowguid': rowGuid2, 'title': 'RIMODIFICATO SUL CLIENT 2'},
        'todos',
        keys: ['rowguid'],
        dbName: 'int_db2',
      );
      await db1.update(
        {'rowguid': rowGuid2, 'title': 'RIMODIFICATO SUL CLIENT 1'},
        'todos',
        keys: ['rowguid'],
        dbName: 'int_db1',
      );
      await repo1.sync(dbName: 'int_db1');
      await repo2.sync(dbName: 'int_db2');
      await repo1.sync(dbName: 'int_db1');
      final title1 = await db1.query(
        "SELECT title FROM todos WHERE rowguid = '$rowGuid2'",
        singleResult: true,
        dbName: 'int_db1',
      );
      final title2 = await db2.query(
        "SELECT title FROM todos WHERE rowguid = '$rowGuid2'",
        singleResult: true,
        dbName: 'int_db2',
      );
      expect(title1, equals('RIMODIFICATO SUL CLIENT 1'));
      expect(title2, equals('RIMODIFICATO SUL CLIENT 1'));
    });

    test('Delete on A, modify on B, sync restores with B changes', () async {
      final todoToDelete = await db2.query(
        "SELECT rowguid, title FROM todos WHERE title = 'CLIENT 2 - SECONDO'",
        singleResult: true,
        dbName: 'int_db2',
      ) as Map<String, dynamic>?;
      expect(todoToDelete, isNotNull);
      await db2.delete(todoToDelete!, 'todos', keys: ['rowguid'], dbName: 'int_db2');
      await repo2.sync(dbName: 'int_db2');
      final deleted = await db2.query(
        "SELECT * FROM todos WHERE rowguid = '${todoToDelete['rowguid']}'",
        singleResult: true,
        dbName: 'int_db2',
      );
      expect(deleted, isNull);
      await db1.update(
        {'rowguid': todoToDelete['rowguid'], 'title': 'CLIENT 2 - SECONDO - MODIFICATO DOPO CANCELLAZIONE'},
        'todos',
        keys: ['rowguid'],
        dbName: 'int_db1',
      );
      await repo1.sync(dbName: 'int_db1');
      await repo2.sync(dbName: 'int_db2');
      final restored = await db2.query(
        "SELECT title FROM todos WHERE rowguid = '${todoToDelete['rowguid']}'",
        singleResult: true,
        dbName: 'int_db2',
      );
      expect(restored, equals('CLIENT 2 - SECONDO - MODIFICATO DOPO CANCELLAZIONE'));
    });
  });
}
