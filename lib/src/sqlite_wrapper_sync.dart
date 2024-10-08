import 'package:sqlite_wrapper/sqlite_wrapper.dart';
import 'package:sync_client/src/db/models/sync_details.dart';
import 'package:sync_client/src/debug_utils.dart';
import 'package:sync_client/src/encrypt_helper.dart';
import 'package:sync_client/src/table_info.dart';
import 'package:uuid/uuid.dart';

import './db/models/sync_data.dart';

enum SyncEnabled { unknown, enabled, disabled }

enum Operation { insert, delete, update }

class SQLiteWrapperSync extends SQLiteWrapperCore {
  /// UUID generator
  final Uuid _uuid = const Uuid();
  final Map<String, TableInfo> tableInfos;

  /// Encryption

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

  SyncEnabled syncConfigured = SyncEnabled.unknown;
  // Serve per verificare se è in corso una sincronizzazione
  // in caso positivo, ad esempio, non scrive le righe di log...
  bool isSyncing = false;

  SQLiteWrapperSync({required this.tableInfos}) : super();

  /*
   * Memorizza la modifica per la sincronizzazione (solo se la sincronizzazione è configurata)
   */
  logOperation(String tableName, Operation operation, String rowguid,
      {required String dbName, force = false}) async {
    // Check if the table is configured for logging in the tableInfos
    if (!tableInfos.keys.contains(tableName)) return;
    debugPrint("LOG OPERATION $tableName - $operation - rowguid $rowguid");
    // Check if the client is configured for logging
    final shouldLog = await isSyncConfigured(dbName: dbName);
    if (!force && !shouldLog || isSyncing) {
      debugPrint("Skipping LOG $shouldLog");
      return;
    }
    // Segue la logica documentata a seconda dell'operazione
    switch (operation) {
      case Operation.delete:
        // Verifichiamo se abbiamo una riga preesistente
        SyncData? existingLogRow =
            await _existingLogRow(tableName, rowguid, null, dbName: dbName);
        if (existingLogRow != null) {
          // Cancelliamo la riga sia che fosse una I o una U
          await _deleteSyncDataRow(existingLogRow, dbName);
          /*await SQLiteWrapper().execute("DELETE FROM sync_data WHERE id = ?",
              params: [existingLogRow.id], dbName: dbName);
            */

          // Se era una 'I' non inseriamo più nulla
          if (existingLogRow.operation == "I") return;
        }
        // Inseriamo la D
        await _insertLogRow(tableName, "D", rowguid, dbName: dbName);
        break;
      case Operation.insert:
        await _insertLogRow(tableName, "I", rowguid, dbName: dbName);
        break;
      case Operation.update:
        // Verifichiamo se abbiamo una riga preesistente
        SyncData? existingLogRow =
            await _existingLogRow(tableName, rowguid, null, dbName: dbName);
        if (existingLogRow != null) {
          // Se la riga precedente era una I non facciamo nulla e non aggiorniamo la data
          // altrimenti potrebbero crearsi problemi di precedenza, tanto è un nuovo inserimento...
          if (existingLogRow.operation == "I") return;
          // Cancelliamo la riga nel caso fosse una U e la reinseriamo
          await _deleteSyncDataRow(existingLogRow, dbName);
          /*await SQLiteWrapper().execute(
              "DELETE FROM ${sync_data_db.SyncData.tableName} WHERE id = ?",
              params: [existingLogRow.id],
              dbName: dbName);
              */
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
    if (tryToLogOperation) {
      await logOperation(table, Operation.insert, map[_getKeyField(table)],
          dbName: dbName!);
    }
    return res;
  }

  // Perform an INSERT or an UPDATE depending on the record state (UPSERT)
  @override
  Future<int> save(Map<String, dynamic> map, String table,
      {List<String>? keys,
      String? dbName = defaultDBName,
      tryToLogOperation = true}) async {
    final res = await super.save(map, table, keys: keys, dbName: dbName);
    if (tryToLogOperation) {
      await logOperation(table, Operation.update, map[_getKeyField(table)],
          dbName: dbName!);
    }
    return res;
  }

  @override
  Future<int> update(Map<String, dynamic> map, String table,
      {required List<String> keys,
      String? dbName = defaultDBName,
      tryToLogOperation = true}) async {
    final res = await super.update(map, table, keys: keys, dbName: dbName);
    if (tryToLogOperation) {
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
    if (tryToLogOperation) {
      await logOperation(table, Operation.delete, map[_getKeyField(table)],
          dbName: dbName!);
    }
    return res;
  }

  ///////////////////////////////////

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

  /// Get the current SyncDetails  or null if sync is not yet configured
  Future<bool> shouldSync({required String dbName}) async {
    return await super.query("SELECT COUNT(*) FROM ${SyncData.tableName}",
            singleResult: true,
            params: [],
            fromMap: SyncDetails.fromDB,
            dbName: dbName) >
        0;
  }

  Future<void> _deleteSyncDataRow(
      SyncData existingLogRow, String dbName) async {
    await super.delete(existingLogRow.toMap(), SyncData.tableName,
        keys: ["id"], dbName: dbName);
  }

  _insertLogRow(String tableName, String operation, String rowguid,
      {required String dbName}) async {
    final SyncData syncData = SyncData(
        tablename: tableName,
        rowguid: rowguid,
        operation: operation,
        clientdate: DateTime.now().toUtc());
    await super.insert(syncData.toMap(), SyncData.tableName, dbName: dbName);
    /*
    const String sql =
        "INSERT INTO sync_data (tablename, rowguid, operation, clientdate) VALUES (?, ?, ?, ?)";
    await SQLiteWrapper().execute(sql,
        params: [
          tableName,
          rowguid,
          operation,
          DateTime.now().toUtc().millisecondsSinceEpoch
        ],
        dbName: dbName);
      */
  }

  /// Return the name of the guid column in the table
  /// according to the table infos
  String _getKeyField(String tableName) {
    return tableInfos[tableName]?.keyField ?? "rowguid";
  }

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

/*
  Future<void> _insertInitialSyncData(
      String tablename, String keyfield, DateTime now,
      {String dbName = mainDBName}) async {
    await SQLiteWrapper().execute(
        """INSERT INTO sync_data (tablename, rowguid, operation, clientdate)
                    SELECT '$tablename', $keyfield, 'I', ? FROM ${tablename}_sync LEFT JOIN sync_data on sync_data.rowguid=$keyfield WHERE sync_data.rowguid is null""",
        params: [now.millisecondsSinceEpoch], dbName: dbName);
  }
  */

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
}
