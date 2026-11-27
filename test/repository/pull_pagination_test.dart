@TestOn('vm')

import 'dart:convert';

import 'package:sync_client/sync_client.dart';
import 'package:test/test.dart';

import '../helpers/fake_http_helper.dart';
import '../helpers/test_db.dart';

/// Il pull paginato: il client chiede le pagine finché il server dice
/// `hasMore`, importando ogni pagina subito (la memoria resta legata alla
/// pagina, non alla libreria).
void main() {
  late SQLiteWrapperSync db;
  late FakeHttpHelper fakeHttp;
  late SyncRepository repository;

  final pullRegex = RegExp(r'/pull/([^/]+)/([^/]+)$');

  setUp(() async {
    db = await openInMemoryDb();
    fakeHttp = FakeHttpHelper();
    repository = SyncRepository(
      sqliteWrapperSync: db,
      serverUrl: 'http://localhost:8076',
      realm: 'TEST_REALM',
      customHttpHelper: fakeHttp,
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
  });

  Map<String, dynamic> page(
    List<Map<String, dynamic>> rows, {
    required bool hasMore,
    int nextCursor = 0,
  }) =>
      {
        'outdatedRowsGuid': <String>[],
        'data': rows,
        'hasMore': hasMore,
        'nextCursor': nextCursor,
      };

  Map<String, dynamic> remoteRow(String guid, String title) => {
        'operation': 'I',
        'rowguid': guid,
        'tablename': 'todos',
        'clientdate': 1700000000000,
        'rowData': {'title': title, 'done': 0},
      };

  List<Map<String, dynamic>> pullBodies() => fakeHttp.calls
      .where((c) => c.url.contains('/pull/'))
      .map((c) => jsonDecode(c.body as String) as Map<String, dynamic>)
      .toList();

  test('importa tutte le pagine e avanza il cursore', () async {
    final guids = [db.newUUID(), db.newUUID(), db.newUUID()];
    fakeHttp.queueResponse(
      pullRegex,
      page([remoteRow(guids[0], 'prima')], hasMore: true, nextCursor: 42),
    );
    fakeHttp.queueResponse(
      pullRegex,
      page([remoteRow(guids[1], 'seconda')], hasMore: true, nextCursor: 84),
    );
    fakeHttp.queueResponse(
      pullRegex,
      page([remoteRow(guids[2], 'terza')], hasMore: false),
    );

    await repository.sync(dbName: 'test');

    final bodies = pullBodies();
    expect(bodies.length, 3);
    expect(bodies.map((b) => b['cursor']).toList(), [0, 42, 84]);
    expect(bodies.first['limit'], kPullPageRows);
    expect(bodies.first['maxBytes'], kPullPageMaxBytes);
    // Il pull manda solo metadati.
    expect((bodies.first['changes'] as List), isEmpty);

    final titles = await db.query(
      'SELECT title, rowguid FROM todos ORDER BY rowid',
      dbName: 'test',
    );
    expect(titles.map((r) => r['title']).toList(), ['prima', 'seconda', 'terza']);
  });

  test('un server vecchio (senza hasMore) fa una sola richiesta', () async {
    fakeHttp.setResponse(pullRegex, {
      'outdatedRowsGuid': <String>[],
      'data': <Map<String, dynamic>>[],
    });

    await repository.sync(dbName: 'test');

    expect(pullBodies().length, 1);
    expect(pullBodies().first['cursor'], 0);
  });

  test('outdatedRowsGuid rimuove le righe locali dalla coda anche a pagine', () async {
    final outdated = db.newUUID();
    final keep = db.newUUID();
    await db.insert({'rowguid': outdated, 'title': 'outdated', 'done': 0},
        'todos', dbName: 'test');
    await db.insert({'rowguid': keep, 'title': 'keep', 'done': 0}, 'todos',
        dbName: 'test');

    fakeHttp.queueResponse(pullRegex, {
      'outdatedRowsGuid': [outdated],
      'data': <Map<String, dynamic>>[],
      'hasMore': true,
      'nextCursor': 7,
    });
    fakeHttp.queueResponse(pullRegex, page([], hasMore: false));

    await repository.sync(dbName: 'test');

    final pushed = fakeHttp.calls
        .where((c) => c.url.contains('/push/'))
        .map((c) => jsonDecode(c.body as String) as Map<String, dynamic>)
        .expand((b) => (b['changes'] as List))
        .map((c) => (c as Map)['rowguid'])
        .toSet();
    expect(pushed, equals({keep}));
  });

  test('se il cursore non avanza il client si ferma (niente loop infinito)',
      () async {
    fakeHttp.setResponse(pullRegex, {
      'outdatedRowsGuid': <String>[],
      'data': <Map<String, dynamic>>[],
      'hasMore': true,
      'nextCursor': 0, // non avanza
    });

    await repository.sync(dbName: 'test');

    expect(pullBodies().length, 1);
  });
}
