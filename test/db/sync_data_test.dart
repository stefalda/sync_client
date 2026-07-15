import 'package:sync_client/src/db/models/sync_data.dart' as db;
import 'package:test/test.dart';

void main() {
  group('SyncData (db)', () {
    test('fromDB parses all fields', () {
      final row = {
        'rowguid': 'guid-1',
        'operation': 'I',
        'tablename': 'todos',
        'clientdate': 1700000000000,
        'id': 42,
      };
      final data = db.SyncData.fromDB(row);
      expect(data.rowguid, equals('guid-1'));
      expect(data.operation, equals('I'));
      expect(data.tablename, equals('todos'));
      expect(data.clientdate,
          equals(DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true)));
      expect(data.id, equals(42));
    });

    test('toMap returns correct map', () {
      final data = db.SyncData(
        id: 1,
        operation: 'U',
        rowguid: 'guid-2',
        tablename: 'notes',
        clientdate: DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
      );
      final map = data.toMap();
      expect(map['id'], equals(1));
      expect(map['operation'], equals('U'));
      expect(map['rowguid'], equals('guid-2'));
      expect(map['tablename'], equals('notes'));
      expect(map['clientdate'], equals(1700000000000));
    });

    test('fromMap parses JSON map', () {
      final json = {
        'operation': 'D',
        'rowguid': 'guid-3',
        'tablename': 'tags',
        'clientdate': 1700000000000,
        'id': 3,
      };
      final data = db.SyncData.fromMap(json);
      expect(data.operation, equals('D'));
      expect(data.rowguid, equals('guid-3'));
      expect(data.tablename, equals('tags'));
      // fromMap does not populate 'id'
      expect(data.id, isNull);
    });
  });
}
