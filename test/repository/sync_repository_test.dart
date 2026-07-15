import 'package:sync_client/sync_client.dart';
import 'package:test/test.dart';

import '../helpers/fake_http_helper.dart';
import '../helpers/test_db.dart';

void main() {
  late SQLiteWrapperSync db;
  late FakeHttpHelper fakeHttp;
  late SyncRepository repository;

  Future<void> setupRepository() async {
    db = await openInMemoryDb();
    fakeHttp = FakeHttpHelper();
    repository = SyncRepository(
      sqliteWrapperSync: db,
      serverUrl: 'http://localhost:8076',
      realm: 'TEST_REALM',
      customHttpHelper: fakeHttp,
    );
  }

  Future<void> registerUser({bool newRegistration = true}) async {
    // Every register needs a unique clientId otherwise the DB will complain
    // about duplicate PK on sync_details. Since register() generates a new
    // clientId via sqliteWrapperSync.newUUID(), each call is unique.
    await repository.register(
      name: 'Test User',
      email: 'test@test.com',
      password: 'test',
      deviceInfo: '{"name":"TEST"}',
      newRegistration: newRegistration,
      language: 'en',
      secretKey: '',
      dbName: 'test',
    );
  }

  group('SyncRepository - register', () {
    setUp(() => setupRepository());

    test('new registration succeeds and populates sync_details', () async {
      await registerUser(newRegistration: true);
      final configured = await repository.isConfigured(dbName: 'test');
      expect(configured, isTrue);
      final details = await repository.getSyncDetails(dbName: 'test');
      expect(details, isNotNull);
      expect(details!.useremail, equals('test@test.com'));
    });

    test('existing registration (login) succeeds', () async {
      // Open second database
      await db.openDB(':memory:', dbName: 'test2', onCreate: () async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS "todos" (
            "rowguid" varchar(36) PRIMARY KEY NOT NULL,
            "title" varchar(255) NOT NULL,
            "done" int default 0
          )
        ''', dbName: 'test2');
        await db.initSyncTables(dbName: 'test2');
      });
      // Register on first database
      await repository.register(
        name: 'Test User',
        email: 'test@test.com',
        password: 'test',
        deviceInfo: '{"name":"DEVICE1"}',
        newRegistration: true,
        language: 'en',
        secretKey: '',
        dbName: 'test',
      );
      // Register same user on second database (login, new client)
      await repository.register(
        name: 'Test User',
        email: 'test@test.com',
        password: 'test',
        deviceInfo: '{"name":"DEVICE2"}',
        newRegistration: false,
        language: 'en',
        secretKey: '',
        dbName: 'test2',
      );
      final configured = await repository.isConfigured(dbName: 'test2');
      expect(configured, isTrue);
    });

    test('throws if sync is already configured', () async {
      await registerUser(newRegistration: true);
      // Another new registration should throw
      expect(
        () => registerUser(newRegistration: true),
        throwsA(isA<SyncException>().having(
          (e) => e.type,
          'type',
          SyncExceptionType.syncConfigurationAlreadyPresent,
        )),
      );
    });

    test('register with secretKey sets encryption', () async {
      await repository.register(
        name: 'Test User',
        email: 'test@test.com',
        password: 'test',
        deviceInfo: '{"name":"TEST"}',
        newRegistration: true,
        language: 'en',
        secretKey: 'a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6',
        dbName: 'test',
      );
      // Secret key should be stored
      final key = await db.getSecretKey(dbName: 'test');
      expect(key, equals('a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6'));
    });
  });

  group('SyncRepository - isConfigured / getSyncDetails', () {
    setUp(() => setupRepository());

    test('isConfigured returns false before registration', () async {
      final configured = await repository.isConfigured(dbName: 'test');
      expect(configured, isFalse);
    });

    test('getSyncDetails returns null before registration', () async {
      final details = await repository.getSyncDetails(dbName: 'test');
      expect(details, isNull);
    });
  });

  group('SyncRepository - sync cycle', () {
    setUp(() async {
      await setupRepository();
      await registerUser(newRegistration: true);
      fakeHttp.clearCalls();
    });

    test('sync succeeds with no local changes', () async {
      await repository.sync(dbName: 'test');
      // Should have called: login, refreshToken, pull, refreshToken, push, cancelSync
      expect(fakeHttp.callCount, greaterThanOrEqualTo(5));
      // Verify pull and push were called
      final urls = fakeHttp.calledUrls;
      expect(urls.any((u) => u.contains('/pull/')), isTrue);
      expect(urls.any((u) => u.contains('/push/')), isTrue);
    });

    test('sync processes local insert changes', () async {
      // Insert a todo item
      final guid = db.newUUID();
      await db.insert(
        {'rowguid': guid, 'title': 'Test Item', 'done': 0},
        'todos',
        dbName: 'test',
        tryToLogOperation: true,
      );
      fakeHttp.clearCalls();

      // Configure pull response to return no remote data
      fakeHttp.setResponse(
        RegExp(r'/pull/([^/]+)/([^/]+)$'),
        {'outdatedRowsGuid': <String>[], 'data': <Map<String, dynamic>>[]},
      );

      await repository.sync(dbName: 'test');

      // sync_data should be cleared after successful sync
      final remaining = await db.query(
        'SELECT COUNT(*) FROM sync_data',
        singleResult: true,
        dbName: 'test',
      );
      expect(remaining, equals(0));
    });

    test('sync with remote data imports it locally', () async {
      // Configure pull to return remote data
      final remoteGuid = db.newUUID();
      fakeHttp.setResponse(
        RegExp(r'/pull/([^/]+)/([^/]+)$'),
        {
          'outdatedRowsGuid': <String>[],
          'data': [
            {
              'operation': 'I',
              'rowguid': remoteGuid,
              'tablename': 'todos',
              'clientdate': 1700000000000,
              'rowData': {'title': 'Remote Item', 'done': 0},
            },
          ],
        },
      );

      await repository.sync(dbName: 'test');

      // Verify the remote item was imported
      final items = await db.query(
        "SELECT * FROM todos WHERE rowguid = '$remoteGuid'",
        dbName: 'test',
      );
      expect(items.length, equals(1));
      expect(items[0]['title'], equals('Remote Item'));
    });

    test('sync removes outdated rows from push', () async {
      final guid = db.newUUID();
      await db.insert(
        {'rowguid': guid, 'title': 'Outdated', 'done': 0},
        'todos',
        dbName: 'test',
        tryToLogOperation: true,
      );
      fakeHttp.clearCalls();

      // Server marks this row as outdated (someone else already pushed it)
      fakeHttp.setResponse(
        RegExp(r'/pull/([^/]+)/([^/]+)$'),
        {
          'outdatedRowsGuid': [guid],
          'data': <Map<String, dynamic>>[],
        },
      );

      fakeHttp.setResponse(
        RegExp(r'/push/([^/]+)/([^/]+)$'),
        {
          'lastSync': DateTime.now().millisecondsSinceEpoch,
        },
      );

      await repository.sync(dbName: 'test');

      // The outdated row should not have been pushed, and sync_data should be empty
      final remaining = await db.query(
        'SELECT COUNT(*) FROM sync_data',
        singleResult: true,
        dbName: 'test',
      );
      expect(remaining, equals(0));
    });

    test('sync without config throws', () async {
      final unconfiguredDb = await openInMemoryDb(initSync: true);
      final repo = SyncRepository(
        sqliteWrapperSync: unconfiguredDb,
        serverUrl: 'http://localhost:8076',
        realm: 'TEST',
        customHttpHelper: FakeHttpHelper(),
      );
      expect(
        () => repo.sync(dbName: 'test'),
        throwsA(isA<SyncException>().having(
          (e) => e.type,
          'type',
          SyncExceptionType.syncConfigurationMissing,
        )),
      );
    });
  });

  group('SyncRepository - HTTP errors', () {
    setUp(() async {
      await setupRepository();
    });

    test('connection error throws SyncException', () async {
      // Insert sync_details directly so register is not needed
      await db.execute(
        "INSERT INTO sync_details (clientid, useremail, userpassword) VALUES ('c1', 'u@t.com', 'p')",
        dbName: 'test',
      );
      // Throw on any HTTP call
      fakeHttp.queueError(
        RegExp(r'.*'),
        SyncException('Connection refused', type: SyncExceptionType.connectionException),
      );

      expect(
        () => repository.sync(dbName: 'test'),
        throwsA(isA<SyncException>().having(
          (e) => e.type,
          'type',
          SyncExceptionType.connectionException,
        )),
      );
    });

    test('401 triggers token refresh and retry succeeds', () async {
      await db.execute(
        "INSERT INTO sync_details (clientid, useremail, userpassword) VALUES ('c2', 'u@t.com', 'p')",
        dbName: 'test',
      );
      // First pull call throws UnauthorizedException
      fakeHttp.queueError(
        RegExp(r'/pull/'),
        UnauthorizedException(),
      );
      // Subsequent calls work normally
      // (refreshToken, then retry pull)

      await repository.sync(dbName: 'test');
      // Sync should have succeeded after token refresh
      expect(fakeHttp.callCount, greaterThanOrEqualTo(6));
    });

    test('401 on both original and retry throws reloginNeeded', () async {
      await db.execute(
        "INSERT INTO sync_details (clientid, useremail, userpassword) VALUES ('c3', 'u@t.com', 'p')",
        dbName: 'test',
      );
      // Queue UnauthorizedException for both the original pull and the retry
      fakeHttp.queueError(
        RegExp(r'/pull/'),
        UnauthorizedException(),
      );
      fakeHttp.queueError(
        RegExp(r'/pull/'),
        UnauthorizedException(),
      );

      expect(
        () => repository.sync(dbName: 'test'),
        throwsA(isA<SyncException>().having(
          (e) => e.type,
          'type',
          SyncExceptionType.reloginNeeded,
        )),
      );
    });
  });

  group('SyncRepository - unregister', () {
    setUp(() async {
      await setupRepository();
      await registerUser(newRegistration: true);
    });

    test('unregister calls API and clears sync tables', () async {
      await repository.unregister(
        email: 'test@test.com',
        password: 'test',
        clientId: 'test-client',
        dbName: 'test',
      );
      final configured = await repository.isConfigured(dbName: 'test');
      expect(configured, isFalse);
      expect(fakeHttp.calledUrls.any((u) => u.contains('/unregister/')), isTrue);
    });

    test('unregister with deleteRemoteData passes flag', () async {
      await repository.unregister(
        email: 'test@test.com',
        password: 'test',
        clientId: 'test-client',
        dbName: 'test',
        deleteRemoteData: true,
      );
      final configured = await repository.isConfigured(dbName: 'test');
      expect(configured, isFalse);
    });
  });

  group('SyncRepository - password management', () {
    setUp(() => setupRepository());

    test('forgottenPassword calls API', () async {
      await repository.forgottenPassword(email: 'test@test.com');
      expect(
        fakeHttp.calledUrls.any((u) => u.contains('/password/')),
        isTrue,
      );
    });

    test('changePassword updates local password when API succeeds', () async {
      await db.execute(
        "INSERT INTO sync_details (clientid, useremail, userpassword) VALUES ('c4', 'u@t.com', 'old_pwd')",
        dbName: 'test',
      );
      await repository.changePassword(
        email: 'test@test.com',
        password: 'new_password',
        pin: '123456',
        dbName: 'test',
      );
      // Password should be updated in DB
      final details = await repository.getSyncDetails(dbName: 'test');
      expect(details, isNotNull);
      expect(details!.userpassword, equals('new_password'));
    });

    test('changePassword throws on expired PIN', () async {
      await db.execute(
        "INSERT INTO sync_details (clientid, useremail, userpassword) VALUES ('c5', 'u@t.com', 'pwd')",
        dbName: 'test',
      );
      fakeHttp.queueError(
        RegExp(r'/password/([^/]+)/change$'),
        CustomHttpException(
          statusCode: 403,
          message: 'PIN expired',
        ),
      );
      expect(
        () => repository.changePassword(
          email: 'test@test.com',
          password: 'new_pwd',
          pin: '000000',
          dbName: 'test',
        ),
        throwsA(isA<SyncException>().having(
          (e) => e.type,
          'type',
          SyncExceptionType.wrongOrExpiredPin,
        )),
      );
    });
  });

  group('SyncRepository - deleteSyncDetails', () {
    setUp(() async {
      await setupRepository();
      await registerUser(newRegistration: true);
    });

    test('removes sync configuration tables', () async {
      final configured = await repository.isConfigured(dbName: 'test');
      expect(configured, isTrue);

      await repository.deleteSyncDetails(dbName: 'test');

      final after = await repository.isConfigured(dbName: 'test');
      expect(after, isFalse);
    });
  });
}
