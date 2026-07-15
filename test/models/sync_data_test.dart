import 'package:sync_client/src/api/models/sync_data.dart';
import 'package:test/test.dart';

void main() {
  group('SyncData (api)', () {
    group('fromDB', () {
      test('parses all fields correctly', () {
        final row = {
          'rowguid': 'guid-123',
          'operation': 'I',
          'tablename': 'todos',
          'clientdate': 1700000000000,
          'id': 42,
        };
        final data = SyncData.fromDB(row);
        expect(data.rowguid, equals('guid-123'));
        expect(data.operation, equals('I'));
        expect(data.tablename, equals('todos'));
        expect(data.clientdate,
            equals(DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true)));
        expect(data.id, equals(42));
      });
    });

    group('toMap', () {
      test('includes rowData when skipRowData is false', () {
        final data = SyncData(
          operation: 'U',
          rowguid: 'guid-456',
          tablename: 'notes',
          clientdate: DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
          rowData: {'title': 'Hello', 'done': true},
        );
        final map = data.toMap(skipRowData: false);
        expect(map['operation'], equals('U'));
        expect(map['rowguid'], equals('guid-456'));
        expect(map['tablename'], equals('notes'));
        expect(map['clientdate'], equals(1700000000000));
        expect(map['rowData'], equals({'title': 'Hello', 'done': true}));
      });

      test('omits rowData when skipRowData is true', () {
        final data = SyncData(
          operation: 'D',
          rowguid: 'guid-789',
          tablename: 'tags',
          clientdate: DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
          rowData: {'name': 'urgent'},
        );
        final map = data.toMap(skipRowData: true);
        expect(map['operation'], equals('D'));
        expect(map['rowguid'], equals('guid-789'));
        expect(map['tablename'], equals('tags'));
        expect(map.containsKey('rowData'), isFalse);
      });

      test('omits rowData when it is null, even with skipRowData false', () {
        final data = SyncData(
          operation: 'I',
          rowguid: 'guid-000',
          tablename: 'items',
        );
        final map = data.toMap(skipRowData: false);
        expect(map.containsKey('rowData'), isFalse);
      });
    });

    group('fromMap', () {
      test('parses JSON map correctly', () {
        final json = {
          'operation': 'I',
          'rowguid': 'guid-abc',
          'tablename': 'todos',
          'clientdate': 1700000000000,
          'rowData': {'title': 'Test'},
        };
        final data = SyncData.fromMap(json);
        expect(data.operation, equals('I'));
        expect(data.rowguid, equals('guid-abc'));
        expect(data.tablename, equals('todos'));
        expect(data.clientdate,
            equals(DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true)));
        expect(data.rowData, equals({'title': 'Test'}));
      });

      test('handles null clientdate', () {
        final json = {
          'operation': 'D',
          'rowguid': 'guid-def',
          'tablename': 'todos',
        };
        final data = SyncData.fromMap(json);
        expect(data.clientdate, isNull);
      });
    });
  });
}
