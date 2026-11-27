@TestOn('vm')

import 'package:sync_client/sync_client.dart';
import 'package:test/test.dart';

import '../helpers/fake_http_helper.dart';
import '../helpers/test_db.dart';

/// Regressione: se la configurazione di sync sparisce **durante** una sync
/// (logout, reset o cancellazione concorrente), il cleanup interno deve
/// fallire con un errore pulito e non con `TypeError: type 'Null' is not a
/// subtype of type 'FutureOr<SyncDetails>'`.
class _LogoutThenFailHelper extends FakeHttpHelper {
  _LogoutThenFailHelper(this.db);

  final SQLiteWrapperSync db;

  @override
  Future<dynamic> call(String url, Map<String, String?>? params,
      {String? method,
      Object? body,
      Map<String, String> additionalHeaders = const {},
      isPushOrPull = false,
      SyncController? syncController}) async {
    if (url.contains('/pull/')) {
      // Simula un logout/cancellazione mentre la sync è in corso.
      await db.execute('DELETE FROM sync_details', dbName: 'test');
      await db.execute('DELETE FROM sync_data', dbName: 'test');
      throw Exception('rete persa');
    }
    return super.call(url, params,
        method: method,
        body: body,
        additionalHeaders: additionalHeaders,
        isPushOrPull: isPushOrPull,
        syncController: syncController);
  }
}

void main() {
  late SQLiteWrapperSync db;
  late SyncRepository repository;

  Future<void> register() async {
    await repository.register(
      name: 'Test User',
      email: 'test@test.com',
      password: 'test',
      deviceInfo: '{"name":"TEST"}',
      newRegistration: true,
      language: 'en',
      secretKey: '',
      dbName: 'test',
    );
  }

  test('config sparita durante la sync: errore pulito, non TypeError', () async {
    db = await openInMemoryDb();
    repository = SyncRepository(
      sqliteWrapperSync: db,
      serverUrl: 'http://localhost:8076',
      realm: 'TEST_REALM',
      customHttpHelper: _LogoutThenFailHelper(db),
    );
    await register();

    Object? caught;
    try {
      await repository.sync(dbName: 'test');
    } catch (e) {
      caught = e;
    }

    expect(caught, isNotNull, reason: 'la sync deve fallire');
    // TypeError è un Error: se il cleanup esplode, sostituisce l'errore vero.
    expect(caught, isA<Exception>(), reason: 'atteso un Exception, non un Error');
    expect(caught.toString(), contains('rete persa'));
  });

  test('senza configurazione le chiamate autenticate falliscono con SyncException',
      () async {
    db = await openInMemoryDb();
    repository = SyncRepository(
      sqliteWrapperSync: db,
      serverUrl: 'http://localhost:8076',
      realm: 'TEST_REALM',
      customHttpHelper: FakeHttpHelper(),
    );
    await register();
    await db.execute('DELETE FROM sync_details', dbName: 'test');

    await expectLater(
      repository.unregister(
        dbName: 'test',
        email: 'test@test.com',
        password: 'test',
        clientId: 'any',
      ),
      throwsA(
        isA<SyncException>().having(
          (e) => e.type,
          'type',
          SyncExceptionType.syncConfigurationMissing,
        ),
      ),
    );
  });
}
