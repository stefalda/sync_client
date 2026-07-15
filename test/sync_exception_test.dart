import 'package:sync_client/sync_client.dart';
import 'package:test/test.dart';

void main() {
  group('SyncException', () {
    test('stores type and message', () {
      final ex = SyncException('Something went wrong',
          type: SyncExceptionType.connectionException);
      expect(ex.message, equals('Something went wrong'));
      expect(ex.type, equals(SyncExceptionType.connectionException));
    });

    test('toString returns type - message format', () {
      final ex = SyncException('Config missing',
          type: SyncExceptionType.syncConfigurationMissing);
      expect(ex.toString(),
          contains('syncConfigurationMissing'));
      expect(ex.toString(), contains('Config missing'));
    });

    test('all SyncExceptionType values are constructible', () {
      for (final type in SyncExceptionType.values) {
        final ex = SyncException('test', type: type);
        expect(ex.type, equals(type));
        expect(ex.message, equals('test'));
      }
    });
  });
}
