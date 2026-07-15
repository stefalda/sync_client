import 'package:sync_client/sync_client.dart';
import 'package:test/test.dart';

void main() {
  group('SyncProgress', () {
    test('progress returns null when processedItems and totalItems are null', () {
      final progress = SyncProgress(
        status: SyncStatus.starting,
        message: 'Starting...',
      );
      expect(progress.progress, isNull);
    });

    test('progress returns null when processedItems is null', () {
      final progress = SyncProgress(
        status: SyncStatus.pulling,
        message: 'Pulling...',
        totalItems: 10,
      );
      expect(progress.progress, isNull);
    });

    test('progress returns null when totalItems is null', () {
      final progress = SyncProgress(
        status: SyncStatus.pushing,
        message: 'Pushing...',
        processedItems: 5,
      );
      expect(progress.progress, isNull);
    });

    test('progress returns null when totalItems is 0', () {
      final progress = SyncProgress(
        status: SyncStatus.pushing,
        message: 'Pushing...',
        processedItems: 0,
        totalItems: 0,
      );
      expect(progress.progress, isNull);
    });

    test('progress returns correct ratio', () {
      final progress = SyncProgress(
        status: SyncStatus.pushing,
        message: 'Pushing...',
        processedItems: 3,
        totalItems: 10,
      );
      expect(progress.progress, equals(0.3));
    });

    test('all SyncStatus values are constructible', () {
      for (final status in SyncStatus.values) {
        final progress = SyncProgress(status: status, message: 'msg');
        expect(progress.status, equals(status));
      }
    });

    test('error is null when not set', () {
      final progress = SyncProgress(status: SyncStatus.completed, message: 'Done');
      expect(progress.error, isNull);
    });
  });
}
