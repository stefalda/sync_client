@TestOn('vm')
@Tags(['integration'])

import 'package:sync_client/sync_client.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../helpers/test_db.dart';

const serverUrl = 'http://localhost:8076';
final _uuid = const Uuid();

/// Integration tests require the Docker stack running:
///   docker compose -f test/integration/docker/docker-compose.yml up -d
///
/// Each test uses a unique realm to avoid cross-test state pollution.

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

SyncRepository createRepo(
    SQLiteWrapperSync db, String realm, String dbName) {
  return SyncRepository(
    sqliteWrapperSync: db,
    serverUrl: serverUrl,
    realm: realm,
  );
}

String uniqueRealm() => 'INT_TEST_${_uuid.v4().substring(0, 8)}';

void main() {
  group('Integration: register + sync', () {
    late String realm;
    late String dbName1;
    late String dbName2;
    late SQLiteWrapperSync db1;
    late SQLiteWrapperSync db2;
    late SyncRepository repo1;
    late SyncRepository repo2;

    setUp(() async {
      realm = uniqueRealm();
      dbName1 = '${realm}_1';
      dbName2 = '${realm}_2';
      db1 = await openIntegrationDb(dbName: dbName1, initSync: true);
      db2 = await openIntegrationDb(dbName: dbName2, initSync: true);
      repo1 = createRepo(db1, realm, dbName1);
      repo2 = createRepo(db2, realm, dbName2);
    });

    test('register two clients + sync creates no duplicates', () async {
      // Register client 1 (new registration)
      await repo1.register(
        name: 'Client 1',
        email: 'test_${realm}@test.com',
        password: 'test',
        deviceInfo: '{"name":"CLIENT1"}',
        newRegistration: true,
        language: 'en',
        secretKey: '',
        dbName: dbName1,
      );

      // Register client 2 (same user, new client)
      await repo2.register(
        name: 'Client 2',
        email: 'test_${realm}@test.com',
        password: 'test',
        deviceInfo: '{"name":"CLIENT2"}',
        newRegistration: false,
        language: 'en',
        secretKey: '',
        dbName: dbName2,
      );

      // Sync both
      await repo1.sync(dbName: dbName1);
      await repo2.sync(dbName: dbName2);

      // Insert data on client 1
      final guid1 = db1.newUUID();
      await db1.insert(
        {'rowguid': guid1, 'title': 'CLIENT 1 - PRIMO', 'done': 0},
        'todos',
        dbName: dbName1,
      );
      await db1.insert(
        {'rowguid': db1.newUUID(), 'title': 'CLIENT 1 - SECONDO', 'done': 0},
        'todos',
        dbName: dbName1,
      );

      // Insert data on client 2
      final guid2 = db2.newUUID();
      await db2.insert(
        {'rowguid': guid2, 'title': 'CLIENT 2 - PRIMO', 'done': 0},
        'todos',
        dbName: dbName2,
      );
      await db2.insert(
        {'rowguid': db2.newUUID(), 'title': 'CLIENT 2 - SECONDO', 'done': 1},
        'todos',
        dbName: dbName2,
      );

      // Sync both directions
      await repo1.sync(dbName: dbName1);
      await repo2.sync(dbName: dbName2);

      // Both should now have 4 items
      final count1 = await db1.query(
        'SELECT COUNT(*) FROM todos',
        singleResult: true,
        dbName: dbName1,
      );
      final count2 = await db2.query(
        'SELECT COUNT(*) FROM todos',
        singleResult: true,
        dbName: dbName2,
      );
      expect(count1, equals(4));
      expect(count2, equals(4));
    });

    test('delete + sync is propagated', () async {
      // Register
      await repo1.register(
        name: 'Test',
        email: 'del_${realm}@test.com',
        password: 'test',
        deviceInfo: '{"name":"DEL1"}',
        newRegistration: true,
        language: 'en',
        secretKey: '',
        dbName: dbName1,
      );
      await repo2.register(
        name: 'Test',
        email: 'del_${realm}@test.com',
        password: 'test',
        deviceInfo: '{"name":"DEL2"}',
        newRegistration: false,
        language: 'en',
        secretKey: '',
        dbName: dbName2,
      );

      // Insert an item on client 1
      final guid = db1.newUUID();
      await db1.insert(
        {'rowguid': guid, 'title': 'To Delete', 'done': 0},
        'todos',
        dbName: dbName1,
      );

      // Sync to propagate to client 2
      await repo1.sync(dbName: dbName1);
      await repo2.sync(dbName: dbName2);

      // Verify it exists on client 2
      var count = await db2.query(
        'SELECT COUNT(*) FROM todos',
        singleResult: true,
        dbName: dbName2,
      );
      expect(count, equals(1));

      // Delete on client 2
      await db2.execute(
        "DELETE FROM todos WHERE rowguid = '$guid'",
        dbName: dbName2,
      );

      // Sync back
      await repo2.sync(dbName: dbName2);
      await repo1.sync(dbName: dbName1);

      // Both should now have 0 items
      count = await db1.query(
        'SELECT COUNT(*) FROM todos',
        singleResult: true,
        dbName: dbName1,
      );
      expect(count, equals(0));
    });

    test('concurrent modification: last write wins', () async {
      await repo1.register(
        name: 'Test',
        email: 'concurrent_${realm}@test.com',
        password: 'test',
        deviceInfo: '{"name":"C1"}',
        newRegistration: true,
        language: 'en',
        secretKey: '',
        dbName: dbName1,
      );
      await repo2.register(
        name: 'Test',
        email: 'concurrent_${realm}@test.com',
        password: 'test',
        deviceInfo: '{"name":"C2"}',
        newRegistration: false,
        language: 'en',
        secretKey: '',
        dbName: dbName2,
      );

      // Insert on client 1
      final guid = db1.newUUID();
      await db1.insert(
        {'rowguid': guid, 'title': 'Original', 'done': 0},
        'todos',
        dbName: dbName1,
      );

      await repo1.sync(dbName: dbName1);
      await repo2.sync(dbName: dbName2);

      // Both modify the same item
      await db1.execute(
        "UPDATE todos SET title = 'Modified on Client 1' WHERE rowguid = '$guid'",
        dbName: dbName1,
      );
      await db2.execute(
        "UPDATE todos SET title = 'Modified on Client 2' WHERE rowguid = '$guid'",
        dbName: dbName2,
      );

      // Client 1 syncs first (its change arrives first)
      await repo1.sync(dbName: dbName1);
      // Client 2 syncs second (its change wins)
      await repo2.sync(dbName: dbName2);
      // Client 1 syncs again to get the final state
      await repo1.sync(dbName: dbName1);

      // Both should have Client 2's title (last write wins)
      final title1 = await db1.query(
        "SELECT title FROM todos WHERE rowguid = '$guid'",
        singleResult: true,
        dbName: dbName1,
      );
      final title2 = await db2.query(
        "SELECT title FROM todos WHERE rowguid = '$guid'",
        singleResult: true,
        dbName: dbName2,
      );
      expect(title1, equals('Modified on Client 2'));
      expect(title2, equals('Modified on Client 2'));
    });

    test('delete on A, modify on B, sync restores with B changes', () async {
      await repo1.register(
        name: 'Test',
        email: 'delmod_${realm}@test.com',
        password: 'test',
        deviceInfo: '{"name":"DM1"}',
        newRegistration: true,
        language: 'en',
        secretKey: '',
        dbName: dbName1,
      );
      await repo2.register(
        name: 'Test',
        email: 'delmod_${realm}@test.com',
        password: 'test',
        deviceInfo: '{"name":"DM2"}',
        newRegistration: false,
        language: 'en',
        secretKey: '',
        dbName: dbName2,
      );

      // Insert on client 1
      final guid = db1.newUUID();
      await db1.insert(
        {'rowguid': guid, 'title': 'Shared Item', 'done': 0},
        'todos',
        dbName: dbName1,
      );

      await repo1.sync(dbName: dbName1);
      await repo2.sync(dbName: dbName2);

      // Delete on client 2
      await db2.execute(
        "DELETE FROM todos WHERE rowguid = '$guid'",
        dbName: dbName2,
      );

      // Sync the delete
      await repo2.sync(dbName: dbName2);

      // Modify on client 1 (before receiving the delete)
      await db1.execute(
        "UPDATE todos SET title = 'Modified after delete' WHERE rowguid = '$guid'",
        dbName: dbName1,
      );

      // Sync client 1 (its change/modify arrives)
      await repo1.sync(dbName: dbName1);
      // Sync client 2 (should receive the modify, restoring the row)
      await repo2.sync(dbName: dbName2);

      // The item should exist on client 2 with the modified title
      final restored = await db2.query(
        "SELECT title FROM todos WHERE rowguid = '$guid'",
        singleResult: true,
        dbName: dbName2,
      );
      expect(restored, equals('Modified after delete'));
    });
  });
}
