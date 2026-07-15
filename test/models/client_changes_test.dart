import 'package:sync_client/src/api/models/client_changes.dart';
import 'package:sync_client/src/api/models/sync_data.dart';
import 'package:test/test.dart';

void main() {
  group('ClientChanges', () {
    final sampleData = SyncData(
      operation: 'I',
      rowguid: 'guid-1',
      tablename: 'todos',
      rowData: {'title': 'Test'},
    );

    test('toMap includes rowData when skipRowData is false', () {
      final changes = ClientChanges()
        ..clientId = 'client-1'
        ..lastSync = 1000
        ..changes = [sampleData];
      final map = changes.toMap(skipRowData: false);
      expect(map['clientId'], equals('client-1'));
      expect(map['lastSync'], equals(1000));
      expect(map['isPartial'], equals(0));
      final changeList = map['changes'] as List;
      expect(changeList.length, equals(1));
      expect((changeList[0] as Map)['rowData'], equals({'title': 'Test'}));
    });

    test('toMap omits rowData when skipRowData is true', () {
      final changes = ClientChanges()
        ..clientId = 'client-2'
        ..lastSync = 2000
        ..changes = [sampleData];
      final map = changes.toMap(skipRowData: true);
      final changeList = map['changes'] as List;
      expect(changeList.length, equals(1));
      expect((changeList[0] as Map).containsKey('rowData'), isFalse);
    });

    test('isPartial is 0 by default', () {
      final changes = ClientChanges()
        ..clientId = 'c1'
        ..lastSync = 0
        ..changes = [];
      final map = changes.toMap(skipRowData: true);
      expect(map['isPartial'], equals(0));
    });

    test('fromMap parses correctly', () {
      final json = {
        'clientId': 'c1',
        'lastSync': 3000,
        'isPartial': 1,
        'changes': [
          {
            'operation': 'U',
            'rowguid': 'guid-2',
            'tablename': 'todos',
            'clientdate': 1700000000000,
          }
        ],
      };
      final changes = ClientChanges.fromMap(json);
      expect(changes.clientId, equals('c1'));
      expect(changes.lastSync, equals(3000));
      expect(changes.isPartial, equals(1));
      expect(changes.changes.length, equals(1));
      expect(changes.changes[0].operation, equals('U'));
      expect(changes.changes[0].rowguid, equals('guid-2'));
    });
  });
}
