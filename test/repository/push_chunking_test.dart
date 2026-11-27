@TestOn('vm')

import 'package:test/test.dart';
import 'package:sync_client/sync_client.dart';
import 'package:sync_client/src/api/models/sync_data.dart';

SyncData change(int payloadBytes, {String guid = 'guid', String table = 'books'}) {
  return SyncData(
    operation: 'U',
    rowguid: guid,
    tablename: table,
    clientdate: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    rowData: {
      'bookid': guid,
      'title': 't',
      // i campi binari arrivano qui già in base64
      'big': 'a' * payloadBytes,
    },
  );
}

void main() {
  group('estimateSyncDataSize', () {
    test('cresce con il payload e conta le stringhe base64', () {
      final small = estimateSyncDataSize(change(10));
      final big = estimateSyncDataSize(change(1024 * 1024));
      expect(big - small, greaterThan(1000 * 1000));
      expect(big, greaterThan(1024 * 1024));
    });

    test('senza rowData resta una stima minima positiva', () {
      final data = SyncData(operation: 'D', rowguid: 'g', tablename: 'books');
      expect(estimateSyncDataSize(data), greaterThan(0));
      expect(estimateSyncDataSize(data), lessThan(512));
    });
  });

  group('splitForPush', () {
    test('lista vuota: nessun chunk', () {
      expect(splitForPush(<SyncData>[]), isEmpty);
    });

    test('poche righe piccole: un solo chunk', () {
      final chunks = splitForPush(List.generate(5, (i) => change(100, guid: '$i')));
      expect(chunks, hasLength(1));
      expect(chunks.first, hasLength(5));
    });

    test('100 righe piccole: un solo chunk (regressione sul limite righe)', () {
      final chunks =
          splitForPush(List.generate(100, (i) => change(100, guid: '$i')));
      expect(chunks, hasLength(1));
      expect(chunks.first, hasLength(100));
    });

    test('250 righe piccole: 100 + 100 + 50', () {
      final chunks =
          splitForPush(List.generate(250, (i) => change(100, guid: '$i')));
      expect(chunks.map((c) => c.length).toList(), [100, 100, 50]);
    });

    test('tante righe piccole: rispetta il limite di byte', () {
      // 8 MB di limite, righe da ~1 MB -> 8 per chunk (non 100)
      final chunks = splitForPush(
        List.generate(20, (i) => change(1024 * 1024, guid: '$i')),
      );
      expect(chunks.length, greaterThan(1));
      for (final chunk in chunks) {
        final bytes = chunk.fold<int>(0, (sum, e) => sum + estimateSyncDataSize(e));
        expect(bytes, lessThanOrEqualTo(kMaxBytesPerPush + 1024 * 1024));
        expect(chunk.length, lessThanOrEqualTo(kMaxDataToSendAtOnce));
      }
      final total = chunks.fold<int>(0, (sum, c) => sum + c.length);
      expect(total, 20, reason: 'nessuna riga persa');
    });

    test('una riga più grande del limite viaggia da sola', () {
      final chunks = splitForPush(
        [change(100), change(20 * 1024 * 1024), change(100)],
      );
      expect(chunks, hasLength(3));
      expect(chunks[1], hasLength(1));
    });

    test('limiti personalizzati', () {
      final chunks = splitForPush(
        List.generate(10, (i) => change(100, guid: '$i')),
        maxRows: 4,
      );
      expect(chunks.map((c) => c.length).toList(), [4, 4, 2]);
    });

    test('nessuna riga duplicata o persa', () {
      final data = List.generate(137, (i) => change(200 * 1024, guid: '$i'));
      final chunks = splitForPush(data);
      final guids = chunks.expand((c) => c).map((e) => e.rowguid).toList();
      expect(guids, hasLength(137));
      expect(guids.toSet(), hasLength(137));
      expect(guids.toList(), data.map((e) => e.rowguid).toList(),
          reason: 'l\'ordine deve essere preservato');
    });
  });
}
