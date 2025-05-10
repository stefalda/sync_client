import 'package:sqlite_wrapper/sqlite_wrapper.dart';
import 'package:sync_client/src/db/models/sync_details.dart';
import 'package:sync_client/src/debug_utils.dart';
import 'package:sync_client/src/encrypt_helper.dart';
import 'package:sync_client/src/table_info.dart';
import 'package:uuid/uuid.dart';

import './db/models/sync_data.dart';

enum SyncEnabled { unknown, enabled, disabled }

enum Operation { insert, delete, update }

/// TABLES IGNORED IN SYNC OPERATIONS
const systemTables = ["sync_encryption", "sync_details", "sync_data"];

/// Use the mixin like this
/// class MyDatabase extends SQLiteWrapperBase with SQLiteWrapperSyncMixin {
//  MyDatabase({required Map<String, TableInfo> tableInfos}) {
//    this.tableInfos = tableInfos;
//  }
//}
mixin SQLiteWrapperSyncMixin on SQLiteWrapperBase {
  /// UUID generator
  final Uuid _uuid = const Uuid();

  /// TableInfos should be passed in the contructor
  late Map<String, TableInfo> tableInfos;

  /// Genereate a new Key that must be saved somewhere by calling the setSecretKey (for instance)
  String generateSecretKey() {
    return EncryptHelper.generateSecretKey();
  }

  /// Store the secretKey in the DB in the sync_encryption table
  setSecretKey(String value, {required String dbName}) async {
    await super.insert({'secretkey': value}, "sync_encryption", dbName: dbName);
  }

  /// Read the secretKey in the DB, returns null if it's not set...
  /// If it's set enable encryption by saving it in EncryptHelper
  Future<String?> getSecretKey({required String dbName}) async {
    String? key = await super.query("SELECT secretkey FROM sync_encryption",
        singleResult: true, dbName: dbName);
    EncryptHelper.secretKey = key;
    return key;
  }

  /// Holds the current state of the sync configuration
  SyncEnabled syncConfigured = SyncEnabled.unknown;

  /// Used to verify if a synchronization is in progress
  // if true, for example, it doesn't write the log rows...
  bool isSyncing = false;

  /*
   * Store the modification for synchronization (only if synchronization is configured)
   */
  logOperation(String tableName, Operation operation, String rowguid,
      {required String dbName, force = false}) async {
    // Check if the table is configured for logging in the tableInfos
    if (!tableInfos.keys.contains(tableName)) return;

    // Check if the client is configured for logging
    final shouldLog = await isSyncConfigured(dbName: dbName);
    if ((!force && !shouldLog) || isSyncing) {
      debugPrint("Skipping LOG $tableName - $operation - rowguid $rowguid");
      return;
    }
    debugPrint("LOG OPERATION $tableName - $operation - rowguid $rowguid");
    // Follow the documented logic depending on the operation
    switch (operation) {
      case Operation.delete:
        // Check if there is an existing log row
        SyncData? existingLogRow =
            await _existingLogRow(tableName, rowguid, null, dbName: dbName);
        if (existingLogRow != null) {
          // Delete the row whether it was an I or a U
          await _deleteSyncDataRow(existingLogRow, dbName);
          /*await SQLiteWrapper().execute("DELETE FROM sync_data WHERE id = ?",
              params: [existingLogRow.id], dbName: dbName);
            */

          // If it was an 'I' we don't insert anything more
          if (existingLogRow.operation == "I") return;
        }
        // Insert the D for delete
        await _insertLogRow(tableName, "D", rowguid, dbName: dbName);
        break;
      case Operation.insert:
        await _insertLogRow(tableName, "I", rowguid, dbName: dbName);
        break;
      case Operation.update:
        // Verify if there is an   existing log row
        SyncData? existingLogRow =
            await _existingLogRow(tableName, rowguid, null, dbName: dbName);
        if (existingLogRow != null) {
          // If the previous row was an I we do nothing and don't update the date
          // otherwise we could create precedence problems, it's a new insert anyway...
          if (existingLogRow.operation == "I") return;
          // Delete the row in case it was a U and insert it again
          await _deleteSyncDataRow(existingLogRow, dbName);
        }
        await _insertLogRow(tableName, "U", rowguid, dbName: dbName);
        break;
    }
  }

  /// Insert a new record in the passed table based on the map object
  /// and return the new id
  @override
  Future<int> insert(Map<String, dynamic> map, String table,
      {String? dbName = defaultDBName, tryToLogOperation = true}) async {
    final res = await super.insert(map, table, dbName: dbName);
    //Log
    if (tryToLogOperation && !_isSystemTable(table)) {
      await logOperation(table, Operation.insert, map[_getKeyField(table)],
          dbName: dbName!);
    }
    return res;
  }

  /// Perform an INSERT or an UPDATE depending on the record state (UPSERT)
  @override
  Future<int> save(Map<String, dynamic> map, String table,
      {List<String>? keys,
      String? dbName = defaultDBName,
      tryToLogOperation = true}) async {
    final res = await super.save(map, table, keys: keys, dbName: dbName);
    if (tryToLogOperation && !_isSystemTable(table)) {
      await logOperation(table, Operation.update, map[_getKeyField(table)],
          dbName: dbName!);
    }
    return res;
  }

  /// Update a row in the passed table
  @override
  Future<int> update(Map<String, dynamic> map, String table,
      {required List<String> keys,
      String? dbName = defaultDBName,
      tryToLogOperation = true}) async {
    final res = await super.update(map, table, keys: keys, dbName: dbName);
    if (tryToLogOperation && !_isSystemTable(table)) {
      await logOperation(table, Operation.update, map[_getKeyField(table)],
          dbName: dbName!);
    }
    return res;
  }

  /// DELETE the item building the SQL query using the table and the id passed
  @override
  Future<int> delete(Map<String, dynamic> map, String table,
      {required List<String> keys,
      String? dbName = defaultDBName,
      tryToLogOperation = true}) async {
    final res = await super.delete(map, table, keys: keys, dbName: dbName);
    if (tryToLogOperation && !_isSystemTable(table)) {
      await logOperation(table, Operation.delete, map[_getKeyField(table)],
          dbName: dbName!);
    }
    return res;
  }

  /// Check if the sync is configured
  /// reading the sync_details table
  Future<bool> isSyncConfigured({required String dbName}) async {
    if (syncConfigured == SyncEnabled.unknown) {
      const sql = "SELECT count(*) as C FROM ${SyncDetails.tableName}";
      final int count = await query(sql, singleResult: true, dbName: dbName);

      syncConfigured = (count > 0) ? SyncEnabled.enabled : SyncEnabled.disabled;
    }
    return syncConfigured == SyncEnabled.enabled;
  }

  /// Get the current SyncDetails  or null if sync is not yet configured
  Future<SyncDetails?> getSyncDetails({required String dbName}) async {
    return await super.query("SELECT * FROM ${SyncDetails.tableName}",
        singleResult: true,
        params: [],
        fromMap: SyncDetails.fromDB,
        dbName: dbName);
  }

  /// Get the current state of sync, returning true if there are local
  /// unsyncronized rows that should be sent to the server
  Future<bool> shouldSync({required String dbName}) async {
    return await super.query("SELECT COUNT(*) FROM ${SyncData.tableName}",
            singleResult: true,
            params: [],
            fromMap: SyncDetails.fromDB,
            dbName: dbName) >
        0;
  }

  /// Delete a sync data row
  Future<void> _deleteSyncDataRow(
      SyncData existingLogRow, String dbName) async {
    await super.delete(existingLogRow.toMap(), SyncData.tableName,
        keys: ["id"], dbName: dbName);
  }

  /// Insert a new log row
  _insertLogRow(String tableName, String operation, String rowguid,
      {required String dbName}) async {
    final SyncData syncData = SyncData(
        tablename: tableName,
        rowguid: rowguid,
        operation: operation,
        clientdate: DateTime.now().toUtc());
    await super.insert(syncData.toMap(), SyncData.tableName, dbName: dbName);
  }

  /// Return the name of the guid column in the table
  /// according to the table infos
  String _getKeyField(String tableName) {
    return tableInfos[tableName]?.keyField ?? "rowguid";
  }

  /// Return the existing log row if it exists
  Future<SyncData?> _existingLogRow(
      String tableName, String rowguid, String? operationFilter,
      {required String dbName}) async {
    String sql =
        "SELECT id, tablename, rowguid, operation, clientdate FROM ${SyncData.tableName} WHERE tablename = ? AND rowguid = ?";
    if (operationFilter != null) {
      sql += " AND operation = '$operationFilter!'";
    }
    return await super.query(sql,
        params: [tableName, rowguid],
        singleResult: true,
        fromMap: SyncData.fromDB,
        dbName: dbName);
  }

  /// Generate a new UUID
  String newUUID() {
    return _uuid.v4();
  }

  /// Create the sync tables
  Future<void> initSyncTables({required String dbName}) async {
    final sql = """
              CREATE TABLE IF NOT EXISTS sync_data (id integer PRIMARY KEY AUTOINCREMENT NOT NULL,   tablename varchar(255) NOT NULL,  rowguid varchar(36) NOT NULL,  operation char(1) NOT NULL,  clientdate timestamp(128) NOT NULL);
              CREATE TABLE IF NOT EXISTS sync_details (clientid varchar(36) PRIMARY KEY NOT NULL, name varchar(255), useremail varchar(255) NOT NULL, userpassword varchar(255) NOT NULL, lastsync timestamp(128), accesstoken varchar(36), refreshtoken varchar(36), accesstokenexpiration timestamp(128));
              CREATE TABLE IF NOT EXISTS sync_encryption (secretkey String PRIMARY KEY NOT NULL);              
          """;
    await execute(sql, dbName: dbName);
  }

  /// Cycle to all the synced tables and populate them with datas...
  Future<void> insertInitialSyncData({required String dbName}) async {
    final now = DateTime.now().toUtc();
    for (String tablename in tableInfos.keys) {
      final TableInfo? tableInfo = tableInfos[tablename];
      await _insertInitialSyncData(tablename, tableInfo!.keyField, now,
          dbName: dbName);
    }
  }

  /// Perform the insert for the specific table
  Future<void> _insertInitialSyncData(
      String tablename, String keyfield, DateTime now,
      {required String dbName}) async {
    await execute(
        """INSERT INTO sync_data (tablename, rowguid, operation, clientdate)
                    SELECT '$tablename', $keyfield, 'I', ? FROM $tablename LEFT JOIN sync_data on sync_data.rowguid=$keyfield WHERE sync_data.rowguid is null""",
        params: [now.millisecondsSinceEpoch], dbName: dbName);
  }

  /// Check if the table passed is a system one
  /// so it shouldn't be considered for sync
  _isSystemTable(String table) {
    return systemTables.contains(table);
  }
}
