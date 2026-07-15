@TestOn('vm')
@Tags(['integration'])

import 'package:sync_client/sync_client.dart';
import 'package:test/test.dart';

const authGrpcHost = 'localhost';
const authGrpcPort = 50054;

final authTableInfos = {
  'todos': TableInfo(keyField: 'rowguid', binaryFields: [], encryptedFields: []),
};

void main() {
  group('Integration: gRPC with authentication', () {
    test('register, login, and perform CRUD with auth token', () async {
      final email =
          'auth_${DateTime.now().millisecondsSinceEpoch}@test.com';
      const password = 'test_password';

      final db = SQLiteWrapperSyncGRPC(
        tableInfos: authTableInfos,
        host: authGrpcHost,
        port: authGrpcPort,
      );

      // Register via authClient — no token needed
      final token = await db.authClient.register(email, password);
      expect(token, isNotEmpty);

      // Set the token so subsequent calls are authenticated
      db.token = token;

      await db.openDB('ignored', dbName: 'auth_test', onCreate: () async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS "todos" (
            "rowguid" varchar(36) PRIMARY KEY NOT NULL,
            "title" varchar(255) NOT NULL,
            "done" int default 0
          )
        ''', dbName: 'auth_test');
        await db.initSyncTables(dbName: 'auth_test');
      });

      final guid = db.newUUID();
      await db.insert(
        {'rowguid': guid, 'title': 'Auth Test Item', 'done': 0},
        'todos',
        dbName: 'auth_test',
      );
      var item = await db.query(
        "SELECT title FROM todos WHERE rowguid = '$guid'",
        singleResult: true,
        dbName: 'auth_test',
      );
      expect(item, equals('Auth Test Item'));

      await db.update(
        {'rowguid': guid, 'title': 'Auth Updated', 'done': 1},
        'todos',
        keys: ['rowguid'],
        dbName: 'auth_test',
      );
      item = await db.query(
        "SELECT title, done FROM todos WHERE rowguid = '$guid'",
        singleResult: true,
        dbName: 'auth_test',
      ) as Map<String, dynamic>?;
      expect(item!['title'], equals('Auth Updated'));

      await db.delete(
        {'rowguid': guid},
        'todos',
        keys: ['rowguid'],
        dbName: 'auth_test',
      );
      item = await db.query(
        "SELECT title FROM todos WHERE rowguid = '$guid'",
        singleResult: true,
        dbName: 'auth_test',
      );
      expect(item, isNull);
    });

    test('login with existing credentials returns a valid token', () async {
      final email =
          'auth_login_${DateTime.now().millisecondsSinceEpoch}@test.com';
      const password = 'login_password';

      final db = SQLiteWrapperSyncGRPC(
        tableInfos: authTableInfos,
        host: authGrpcHost,
        port: authGrpcPort,
      );

      final registerToken = await db.authClient.register(email, password);
      expect(registerToken, isNotEmpty);

      final loginToken = await db.authClient.login(email, password);
      expect(loginToken, isNotEmpty);

      // Both tokens should work for DB operations
      db.token = loginToken;
      await db.openDB('ignored', dbName: 'auth_login_test', onCreate: () async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS "todos" (
            "rowguid" varchar(36) PRIMARY KEY NOT NULL,
            "title" varchar(255) NOT NULL,
            "done" int default 0
          )
        ''', dbName: 'auth_login_test');
        await db.initSyncTables(dbName: 'auth_login_test');
      });

      final guid = db.newUUID();
      await db.insert(
        {'rowguid': guid, 'title': 'Login Test', 'done': 0},
        'todos',
        dbName: 'auth_login_test',
      );
      final item = await db.query(
        "SELECT title FROM todos WHERE rowguid = '$guid'",
        singleResult: true,
        dbName: 'auth_login_test',
      );
      expect(item, equals('Login Test'));
    });
  });
}
