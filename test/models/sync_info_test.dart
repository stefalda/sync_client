import 'package:sync_client/src/api/models/sync_info.dart';
import 'package:test/test.dart';

void main() {
  group('SyncInfo', () {
    test('fromJson parses lastSync correctly', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final json = {'lastSync': now};
      final info = SyncInfo.fromJson(json);
      expect(info.lastSync,
          equals(DateTime.fromMillisecondsSinceEpoch(now, isUtc: true)));
    });

    test('fromJson handles null lastSync', () {
      final json = <String, dynamic>{};
      final info = SyncInfo.fromJson(json);
      expect(info.lastSync, isNull);
    });
  });
}
