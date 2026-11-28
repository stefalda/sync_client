@TestOn('vm')

import 'package:sync_client/sync_client.dart';
import 'package:test/test.dart';

import '../helpers/fake_http_helper.dart';
import '../helpers/test_db.dart';

/// Handshake di versione: se un altro device dell'utente usa uno schema più
/// recente, la sync si ferma con un errore dedicato (invece di applicare righe
/// con colonne sconosciute, che verrebbero azzerate).
void main() {
  late SQLiteWrapperSync db;
  late FakeHttpHelper fakeHttp;
  late SyncRepository repository;

  final pullRegex = RegExp(r'/pull/([^/]+)/([^/]+)$');

  Future<void> setup({int schemaVersion = 15}) async {
    db = await openInMemoryDb();
    fakeHttp = FakeHttpHelper();
    repository = SyncRepository(
      sqliteWrapperSync: db,
      serverUrl: 'http://localhost:8076',
      realm: 'TEST_REALM',
      customHttpHelper: fakeHttp,
      schemaVersion: schemaVersion,
    );
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
    fakeHttp.clearCalls();
  }

  test('dichiara la propria versione di schema nel pull', () async {
    await setup(schemaVersion: 15);
    fakeHttp.setResponse(pullRegex, {
      'outdatedRowsGuid': <String>[],
      'data': <Map<String, dynamic>>[],
      'maxSchemaVersion': 15,
    });

    await repository.sync(dbName: 'test');

    final pull = fakeHttp.calls.firstWhere((c) => c.url.contains('/pull/'));
    expect((pull.body as String).contains('"schemaVersion":15'), isTrue);
  });

  test('si ferma se un altro device ha uno schema più nuovo', () async {
    await setup(schemaVersion: 13);
    fakeHttp.setResponse(pullRegex, {
      'outdatedRowsGuid': <String>[],
      'data': <Map<String, dynamic>>[],
      'maxSchemaVersion': 15,
    });

    await expectLater(
      repository.sync(dbName: 'test'),
      throwsA(
        isA<SyncException>().having(
          (e) => e.type,
          'type',
          SyncExceptionType.schemaVersionMismatch,
        ),
      ),
    );
  });

  test('un server vecchio (senza maxSchemaVersion) non blocca nulla', () async {
    await setup(schemaVersion: 13);
    fakeHttp.setResponse(pullRegex, {
      'outdatedRowsGuid': <String>[],
      'data': <Map<String, dynamic>>[],
    });

    await repository.sync(dbName: 'test');
    // nessuna eccezione: comportamento identico a prima dell'handshake
  });
}
