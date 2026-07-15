import 'package:sync_client/sync_client.dart';

final testTableInfos = {
  'todos': TableInfo(keyField: 'rowguid', binaryFields: [], encryptedFields: []),
};

Future<SQLiteWrapperSync> openInMemoryDb({
  String dbName = 'test',
  bool initSync = true,
}) async {
  final db = SQLiteWrapperSync(tableInfos: testTableInfos);
  await db.openDB(inMemoryDatabasePath, dbName: dbName, onCreate: () async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS "todos" (
        "rowguid" varchar(36) PRIMARY KEY NOT NULL,
        "title" varchar(255) NOT NULL,
        "done" int default 0
      )
    ''', dbName: dbName);
    if (initSync) {
      await db.initSyncTables(dbName: dbName);
    }
  });
  return db;
}
