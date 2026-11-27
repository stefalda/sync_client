@TestOn('vm')

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:sync_client/sync_client.dart';
import 'package:test/test.dart';

import '../helpers/fake_http_helper.dart';

/// Tabella con un campo binario, come `covers.big` nell'app.
final Map<String, TableInfo> binaryTableInfos = {
  'docs': TableInfo(keyField: 'docid', binaryFields: ['payload']),
};

Future<SQLiteWrapperSync> openBinaryDb() async {
  final db = SQLiteWrapperSync(tableInfos: binaryTableInfos);
  await db.openDB(':memory:', dbName: 'test', onCreate: () async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS "docs" (
        "docid" varchar(36) PRIMARY KEY NOT NULL,
        "title" varchar(255),
        "payload" blob,
        "custom" int
      )
    ''', dbName: 'test');
    await db.initSyncTables(dbName: 'test');
  });
  return db;
}

Uint8List bytesOf(int size, int seed) {
  final random = Random(seed);
  final data = Uint8List(size);
  for (var i = 0; i < size; i++) {
    data[i] = random.nextInt(256);
  }
  return data;
}

void main() {
  late SQLiteWrapperSync db;
  late FakeHttpHelper fakeHttp;
  late SyncRepository repository;

  // Limiti piccoli per rendere osservabile lo streaming nei test.
  const maxBytes = 2 * 1024 * 1024;

  setUp(() async {
    db = await openBinaryDb();
    fakeHttp = FakeHttpHelper();
    repository = SyncRepository(
      sqliteWrapperSync: db,
      serverUrl: 'http://localhost:8076',
      realm: 'TEST_REALM',
      customHttpHelper: fakeHttp,
      maxBytesPerPush: maxBytes,
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
    fakeHttp.setResponse(
      RegExp(r'/pull/([^/]+)/([^/]+)$'),
      {'outdatedRowsGuid': <String>[], 'data': <Map<String, dynamic>>[]},
    );
    fakeHttp.clearCalls();
  });

  List<Map<String, dynamic>> pushBodies() => fakeHttp.calls
      .where((c) => c.url.contains('/push/'))
      .map((c) => jsonDecode(c.body as String) as Map<String, dynamic>)
      .toList();

  test('i blob viaggiano letti a blocchi, tutti e una sola volta', () async {
    // 6 righe da ~1 MB: con limite 2 MB il chunking ne mette una per push.
    final payloads = <String, Uint8List>{};
    for (var i = 0; i < 6; i++) {
      final docid = db.newUUID();
      final payload = bytesOf(900 * 1024, i + 1);
      payloads[docid] = payload;
      await db.insert({
        'docid': docid,
        'title': 'doc $i',
        'payload': payload,
        'custom': 1,
      }, 'docs', dbName: 'test');
    }

    await repository.sync(dbName: 'test');

    final pushes = pushBodies();
    expect(pushes.length, greaterThan(1), reason: 'deve spezzare in più push');

    final pushed = <String, dynamic>{};
    for (final push in pushes) {
      final changes = (push['changes'] as List).cast<Map<String, dynamic>>();
      // Nessun push deve superare il limite configurato (JSON prima di gzip).
      expect(jsonEncode(changes).length, lessThanOrEqualTo(maxBytes * 1.2));
      for (final change in changes) {
        pushed[change['rowguid'] as String] = change['rowData'];
      }
    }

    expect(pushed.keys.toSet(), payloads.keys.toSet());
    for (final entry in payloads.entries) {
      final rowData = pushed[entry.key] as Map<String, dynamic>;
      expect(rowData['title'], isNotNull);
      expect(
        rowData['payload'],
        equals(base64Encode(entry.value)),
        reason: 'il blob deve arrivare integro per ${entry.key}',
      );
    }

    // isPartial: 1 su tutti tranne l'ultimo.
    final partials = pushes.map((p) => p['isPartial']).toList();
    expect(partials.sublist(0, partials.length - 1), everyElement(1));
    expect(partials.last, 0);
  });

  test('i rowData vengono letti al momento del push', () async {
    final docid = db.newUUID();
    await db.insert({
      'docid': docid,
      'title': 'prima',
      'payload': bytesOf(1024, 1),
      'custom': 1,
    }, 'docs', dbName: 'test');

    // Modifica "silenziosa" (senza logOperation): il push deve mandare lo
    // stato attuale della riga, che è quello che si legge dal DB a blocchi.
    await db.execute(
      "UPDATE docs SET title = 'dopo' WHERE docid = ?",
      params: [docid],
      dbName: 'test',
    );

    await repository.sync(dbName: 'test');

    final changes = pushBodies().expand((p) => (p['changes'] as List)).toList();
    expect(changes, hasLength(1));
    expect((changes.first as Map)['rowData']['title'], 'dopo');
  });

  test('una riga cancellata viaggia senza rowData', () async {
    final docid = db.newUUID();
    final row = {
      'docid': docid,
      'title': 'da cancellare',
      'payload': bytesOf(1024, 2),
      'custom': 1,
    };
    await db.insert(row, 'docs', dbName: 'test');
    // Prima sync: la riga è creata sul server ('I').
    await repository.sync(dbName: 'test');

    // Poi viene cancellata: ora sì che si logga una 'D'.
    fakeHttp.clearCalls();
    await db.delete(row, 'docs', keys: ['docid'], dbName: 'test');
    await repository.sync(dbName: 'test');

    final changes = pushBodies().expand((p) => (p['changes'] as List)).toList();
    expect(changes, hasLength(1));
    final change = changes.first as Map<String, dynamic>;
    expect(change['operation'], 'D');
    expect(change['rowguid'], docid);
    expect((change['rowData'] as Map?)?.isEmpty ?? true, isTrue);
  });

  test('il pull non porta i rowData (solo metadati)', () async {
    final docid = db.newUUID();
    await db.insert({
      'docid': docid,
      'title': 'x',
      'payload': bytesOf(1024, 3),
      'custom': 1,
    }, 'docs', dbName: 'test');

    await repository.sync(dbName: 'test');

    final pullCall = fakeHttp.calls.firstWhere((c) => c.url.contains('/pull/'));
    final pullBody = jsonDecode(pullCall.body as String) as Map<String, dynamic>;
    final changes = (pullBody['changes'] as List).cast<Map<String, dynamic>>();
    expect(changes, hasLength(1));
    expect(changes.first.containsKey('rowData'), isFalse,
        reason: 'il pull deve mandare solo i metadati');
    expect(changes.first['rowguid'], docid);
  });

  test('le righe dichiarate outdated dal server non vengono pushate', () async {
    final keep = db.newUUID();
    final outdated = db.newUUID();
    for (final id in [keep, outdated]) {
      await db.insert({
        'docid': id,
        'title': id,
        'payload': bytesOf(1024, 4),
        'custom': 1,
      }, 'docs', dbName: 'test');
    }
    fakeHttp.setResponse(
      RegExp(r'/pull/([^/]+)/([^/]+)$'),
      {
        'outdatedRowsGuid': [outdated],
        'data': <Map<String, dynamic>>[],
      },
    );

    await repository.sync(dbName: 'test');

    final pushedGuids = pushBodies()
        .expand((p) => (p['changes'] as List))
        .map((c) => (c as Map)['rowguid'])
        .toSet();
    expect(pushedGuids, equals({keep}));
  });
}
