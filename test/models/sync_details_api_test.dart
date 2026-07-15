import 'package:sync_client/src/api/models/sync_details.dart';
import 'package:test/test.dart';

void main() {
  group('SyncDetails (api)', () {
    test('fromJson parses outdatedRowsGuid and data', () {
      final json = {
        'outdatedRowsGuid': ['guid-1', 'guid-2'],
        'data': [
          {
            'operation': 'U',
            'rowguid': 'guid-3',
            'tablename': 'todos',
            'clientdate': 1700000000000,
            'rowData': {'title': 'Updated'},
          },
        ],
      };
      final details = SyncDetails.fromJson(json);
      expect(details.outdatedRowsGuid, containsAll(['guid-1', 'guid-2']));
      expect(details.data.length, equals(1));
      expect(details.data[0].rowguid, equals('guid-3'));
      expect(details.data[0].rowData, equals({'title': 'Updated'}));
    });

    test('fromJson handles empty data list', () {
      final json = {
        'outdatedRowsGuid': <String>[],
        'data': <Map<String, dynamic>>[],
      };
      final details = SyncDetails.fromJson(json);
      expect(details.outdatedRowsGuid, isEmpty);
      expect(details.data, isEmpty);
    });

    test('fromJson handles missing data field', () {
      final json = {
        'outdatedRowsGuid': <String>[],
      };
      final details = SyncDetails.fromJson(json);
      expect(details.data, isEmpty);
    });
  });
}
