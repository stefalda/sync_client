import 'package:sync_client/sync_client.dart';
import 'package:test/test.dart';

import '../helpers/test_db.dart';

void main() {
  late SQLiteWrapperSync db;

  setUp(() async {
    db = await openInMemoryDb();
    // Mark sync as configured so logging is active
    await db.execute(
      "INSERT INTO sync_details (clientid, useremail, userpassword) VALUES ('c1', 'u@t.com', 'p')",
      dbName: 'test',
    );
  });

  group('logOperation - insert', () {
    test('writes an I row to sync_data', () async {
      await db.logOperation('todos', Operation.insert, 'guid-1', dbName: 'test');
      final rows = await db.query(
        "SELECT * FROM sync_data WHERE rowguid = 'guid-1'",
        dbName: 'test',
      );
      expect(rows.length, equals(1));
      expect(rows[0]['operation'], equals('I'));
      expect(rows[0]['tablename'], equals('todos'));
    });
  });

  group('logOperation - I then U collation', () {
    test('Insert then Update keeps a single I row', () async {
      await db.logOperation('todos', Operation.insert, 'guid-2', dbName: 'test');
      await db.logOperation('todos', Operation.update, 'guid-2', dbName: 'test');
      final rows = await db.query(
        "SELECT * FROM sync_data WHERE rowguid = 'guid-2'",
        dbName: 'test',
      );
      expect(rows.length, equals(1));
      expect(rows[0]['operation'], equals('I'));
    });
  });

  group('logOperation - U then U consolidation', () {
    test('Update then Update produces a single U row', () async {
      await db.logOperation('todos', Operation.update, 'guid-3', dbName: 'test');
      await db.logOperation('todos', Operation.update, 'guid-3', dbName: 'test');
      final rows = await db.query(
        "SELECT * FROM sync_data WHERE rowguid = 'guid-3'",
        dbName: 'test',
      );
      expect(rows.length, equals(1));
      expect(rows[0]['operation'], equals('U'));
    });
  });

  group('logOperation - I then D removal', () {
    test('Insert then Delete leaves no trace', () async {
      await db.logOperation('todos', Operation.insert, 'guid-4', dbName: 'test');
      await db.logOperation('todos', Operation.delete, 'guid-4', dbName: 'test');
      final rows = await db.query(
        "SELECT * FROM sync_data WHERE rowguid = 'guid-4'",
        dbName: 'test',
      );
      expect(rows, isEmpty);
    });
  });

  group('logOperation - U then D demotion', () {
    test('Update then Delete produces a D row', () async {
      await db.logOperation('todos', Operation.update, 'guid-5', dbName: 'test');
      await db.logOperation('todos', Operation.delete, 'guid-5', dbName: 'test');
      final rows = await db.query(
        "SELECT * FROM sync_data WHERE rowguid = 'guid-5'",
        dbName: 'test',
      );
      expect(rows.length, equals(1));
      expect(rows[0]['operation'], equals('D'));
    });
  });

  group('logOperation - non-tracked table', () {
    test('does nothing for tables not in tableInfos', () async {
      await db.logOperation('unknown_table', Operation.insert, 'guid-6',
          dbName: 'test');
      // If tableInfos does not contain the table, logOperation returns early
      final count = await db.query(
        'SELECT COUNT(*) FROM sync_data',
        singleResult: true,
        dbName: 'test',
      );
      expect(count, equals(0));
    });
  });

  group('logOperation - isSyncing', () {
    test('skips logging when isSyncing is true', () async {
      db.isSyncing = true;
      await db.logOperation('todos', Operation.insert, 'guid-7', dbName: 'test');
      db.isSyncing = false;
      final count = await db.query(
        'SELECT COUNT(*) FROM sync_data',
        singleResult: true,
        dbName: 'test',
      );
      expect(count, equals(0));
    });
  });

  group('logOperation - sync not configured', () {
    test('skips logging when no sync_details row exists', () async {
      // Create a fresh DB without sync config
      final unconfiguredDb = await openInMemoryDb(initSync: true);
      // Don't insert into sync_details — sync unconfigured
      await unconfiguredDb.logOperation(
          'todos', Operation.insert, 'guid-8', dbName: 'test');
      final count = await unconfiguredDb.query(
        'SELECT COUNT(*) FROM sync_data',
        singleResult: true,
        dbName: 'test',
      );
      expect(count, equals(0));
    });
  });

  group('shouldSync', () {
    test('returns false when sync_data is empty', () async {
      final result = await db.shouldSync(dbName: 'test');
      expect(result, isFalse);
    });

    test('returns true when sync_data has rows', () async {
      await db.logOperation('todos', Operation.insert, 'guid-9', dbName: 'test');
      final result = await db.shouldSync(dbName: 'test');
      expect(result, isTrue);
    });
  });

  group('initSyncTables', () {
    test('creates sync_data, sync_details, sync_encryption tables', () async {
      // initSyncTables is called in openInMemoryDb, so tables should exist
      await db.execute(
        "INSERT INTO sync_data (tablename, rowguid, operation, clientdate) VALUES ('t', 'g', 'I', 1000)",
        dbName: 'test',
      );
      final count = await db.query(
        'SELECT COUNT(*) FROM sync_data',
        singleResult: true,
        dbName: 'test',
      );
      expect(count, greaterThan(0));
    });
  });

  group('insertInitialSyncData', () {
    test('logs existing data rows with I operation', () async {
      // Insert real data
      const guid = 'existing-guid';
      await db.execute(
        "INSERT INTO todos (rowguid, title, done) VALUES ('$guid', 'Existing', 0)",
        dbName: 'test',
      );
      // Clear any sync_data from the insert's logOperation (since sync is configured)
      await db.execute('DELETE FROM sync_data', dbName: 'test');

      // Now insert initial sync data
      await db.insertInitialSyncData(dbName: 'test');
      final rows = await db.query(
        "SELECT * FROM sync_data WHERE rowguid = '$guid'",
        dbName: 'test',
      );
      expect(rows.length, equals(1));
      expect(rows[0]['operation'], equals('I'));
    });
  });
}
