import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:sync_client/src/api/models/client_changes.dart';
import 'package:sync_client/src/api/models/password_change.dart';
import 'package:sync_client/src/api/models/sync_data.dart';
import 'package:sync_client/src/api/models/sync_details.dart'
    as api_sync_details;
import 'package:sync_client/src/api/models/sync_info.dart';
import 'package:sync_client/src/api/models/user_registration.dart';
import 'package:sync_client/src/authentication_helper.dart';
import 'package:sync_client/src/debug_utils.dart';
import 'package:sync_client/src/sqlite_wrapper_sync_mixin.dart';
import 'package:sync_client/sync_client.dart' hide Operation;

typedef SyncController = StreamController<SyncProgress>;
const kMaxDataToSendAtOnce = 100;

/// Dimensione massima **stimata** (byte di JSON, prima della compressione) per
/// singola richiesta di push.
///
/// Il limite per numero di righe non basta: i campi binari (cover, foto) sono
/// inviati in base64 dentro `rowData`, quindi 100 righe possono valere pochi KB
/// oppure decine di MB. Il body del server (express) ha un limite (10-50 MB a
/// seconda della configurazione) e un chunk troppo grande fallisce con
/// "request entity too large", lasciando la sync a metà.
///
/// 8 MB resta sotto il default di 10 MB del server e lascia margine per
/// l'envelope; una riga singola più grande del limite viene inviata da sola.
const kMaxBytesPerPush = 8 * 1024 * 1024;

/// Quante righe vengono lette dal DB per volta durante il push.
///
/// Il push è "streaming": in memoria restano solo i metadati delle modifiche in
/// coda e i `rowData` (blob inclusi) delle righe del blocco in corso. Con blob
/// da 2 MB e blocchi da 8 righe il picco è di poche decine di MB invece
/// dell'intera libreria.
const kRowsLoadedAtOnce = 8;

/// Righe massime per pagina di pull.
const kPullPageRows = 200;

/// Byte massimi (stimati) di `rowData` per pagina di pull: il server può
/// restituirne meno, così una pagina di cover non pesa centinaia di MB.
const kPullPageMaxBytes = 8 * 1024 * 1024;

/// Stima conservativa della dimensione JSON di una riga da inviare.
///
/// Non serializza (sarebbe costoso su librerie grandi): somma le chiavi e i
/// valori, contando 1 byte per carattere delle stringhe (dove il base64 dei
/// blob è il contributo dominante) e una costante per i tipi scalari.
int estimateSyncDataSize(SyncData data) {
  // operation + rowguid + tablename + clientdate + parentesi/virgole
  var size = 128;
  final rowData = data.rowData;
  if (rowData == null) return size;
  rowData.forEach((key, value) {
    size += key.length + 4; // "key": value
    if (value is String) {
      size += value.length;
    } else if (value is List<int>) {
      size += value.length;
    } else {
      size += 16;
    }
  });
  return size;
}

/// Spezza le modifiche da inviare in chunk che rispettano sia il numero massimo
/// di righe ([maxRows]) sia la dimensione massima stimata ([maxBytes]).
///
/// Una singola riga più grande di [maxBytes] viene messa in un chunk da sola:
/// non è ulteriormente spezzabile e il server deve accettarla.
List<List<SyncData>> splitForPush(
  List<SyncData> data, {
  int maxRows = kMaxDataToSendAtOnce,
  int maxBytes = kMaxBytesPerPush,
}) {
  final chunks = <List<SyncData>>[];
  var current = <SyncData>[];
  var currentBytes = 0;

  for (final item in data) {
    final itemBytes = estimateSyncDataSize(item);
    final full = current.length >= maxRows ||
        (current.isNotEmpty && currentBytes + itemBytes > maxBytes);
    if (full) {
      chunks.add(current);
      current = <SyncData>[];
      currentBytes = 0;
    }
    current.add(item);
    currentBytes += itemBytes;
  }
  if (current.isNotEmpty) chunks.add(current);
  return chunks;
}

class SyncRepository {
  final SQLiteWrapperSyncMixin sqliteWrapperSync;
  final String serverUrl;
  final String realm;
  late AuthenticationHelper authenticationHelper;
  bool debug = true;
  final SyncController syncController =
      StreamController<SyncProgress>.broadcast();
  Stream<SyncProgress> get syncProgress => syncController.stream;
  final HttpHelper httpHelper;

  /// Limite di righe per singola richiesta di push.
  final int maxRowsPerPush;

  /// Limite (stimato) di byte per singola richiesta di push.
  final int maxBytesPerPush;

  /// Righe massime per pagina di pull.
  final int maxRowsPerPull;

  /// Byte massimi di `rowData` per pagina di pull.
  final int maxBytesPerPull;

  /// Se true le righe già inviate vengono tolte da `sync_data` subito dopo il
  /// push riuscito: un'interruzione (app in background, rete) fa ripartire solo
  /// le modifiche residue invece dell'intera libreria.
  final bool deletePushedRowsProgressively;

  //Constructor
  SyncRepository(
      {required this.sqliteWrapperSync,
      required this.serverUrl,
      required this.realm,
      HttpHelper? customHttpHelper,
      this.maxRowsPerPush = kMaxDataToSendAtOnce,
      this.maxBytesPerPush = kMaxBytesPerPush,
      this.maxRowsPerPull = kPullPageRows,
      this.maxBytesPerPull = kPullPageMaxBytes,
      this.deletePushedRowsProgressively = true})
      : httpHelper = customHttpHelper ?? HttpHelper() {
    authenticationHelper = AuthenticationHelper(
        serverUrl: serverUrl,
        realm: realm,
        sqliteWrapperSync: sqliteWrapperSync,
        customHttpHelper: httpHelper);
  }

  /// Register the User and the Client
  /// (only the Client if newRegistration is false)
  /// and store the credentials in the DB
  Future<void> register(
      {required String? name,
      required String email,
      required String password,
      required String deviceInfo,
      required bool newRegistration,
      required String language,
      required String
          secretKey, // If "" the key will be generated automatically
      required String dbName}) async {
    const sql = "SELECT * FROM sync_details";
    final rows = await sqliteWrapperSync.query(sql, dbName: dbName);
    if (rows.isNotEmpty) {
      throw SyncException("A sync configuration is already present",
          type: SyncExceptionType.syncConfigurationAlreadyPresent);
    }

    final UserRegistration userRegistration = UserRegistration();
    userRegistration.name = name;
    userRegistration.email = email;
    userRegistration.password = password;
    userRegistration.clientId = sqliteWrapperSync.newUUID();
    userRegistration.clientDescription = deviceInfo;
    userRegistration.newRegistration = newRegistration;
    userRegistration.language = language;

    final json = jsonEncode(userRegistration.toMap());
    try {
      // Call the server
      dynamic result = await httpHelper.call("$serverUrl/register/$realm", {},
          body: json, method: "POST");

      // Save the name
      if (!newRegistration && (name ?? "").isEmpty) {
        name = result['user']['name'];
      }
    } on CustomHttpException catch (e) {
      // New Registration
      if (newRegistration &&
          e.message.contains("The email is already registered")) {
        throw SyncException(e.message,
            type: SyncExceptionType.registerExceptionAlreadyRegistered);
      }
      if (newRegistration) {
        throw SyncException(e.message, type: SyncExceptionType.generic);
      }
      // Login
      if (e.message.contains("email is not registered")) {
        throw SyncException(e.message,
            type: SyncExceptionType.loginExceptionUserNotFound);
      }
      if (e.message.contains("Wrong username or password")) {
        throw SyncException(e.message,
            type: SyncExceptionType.loginExceptionWrongCredentials);
      }

      throw SyncException(e.message, type: SyncExceptionType.generic);
    }
    if (newRegistration && secretKey.isEmpty) {
      secretKey = sqliteWrapperSync.generateSecretKey();
    }
    if (secretKey.isNotEmpty) {
      await sqliteWrapperSync.setSecretKey(secretKey, dbName: dbName);
      EncryptHelper.secretKey = secretKey;
    }

    await _configureSync(name, email, password, userRegistration.clientId!,
        dbName: dbName);
    await _logPreviouslyInsertedData(dbName: dbName);
    sqliteWrapperSync.syncConfigured = SyncEnabled.enabled;
    debugPrint("Ready for first sync");
  }

  /// Unregister the client, optionally deleting ALL the data
  /// related to this user if the deleteRemoteData is set to true
  Future<void> unregister(
      {required String email,
      required String password,
      required String clientId,
      required String dbName,
      deleteRemoteData = false}) async {
    final UserRegistration userRegistration = UserRegistration();
    userRegistration.email = email;
    userRegistration.password = password;
    userRegistration.clientId = clientId;
    // Don't delete everything unless requested
    userRegistration.deleteRemoteData = deleteRemoteData;
    final json = jsonEncode(userRegistration.toMap());
    // dynamic result =
    await authenticationHelper.authenticatedCall(
        "$serverUrl/unregister/$realm", {},
        body: json,
        method: "POST",
        dbName: dbName,
        syncController: syncController);
    await resetDB(dbName: dbName);
  }

  /// Reset the table data for account and sync data
  Future<void> resetDB({required String dbName}) async {
    // DELETE LOGGED DATA
    await sqliteWrapperSync.execute("DELETE FROM sync_data", dbName: dbName);
    // DELETE SYNC DETAIL
    await sqliteWrapperSync.execute("DELETE FROM sync_details", dbName: dbName);
    // DELETE THE SECRET KEY
    await sqliteWrapperSync
        .execute("DELETE FROM sync_encryption", dbName: dbName);
  }

  ///
  /// Sync the data by performing two API calls
  ///
  ///   PULL - to get all the information from the server deciding if some data on the client are outdated
  ///   PUSH - to send all the (valid) changes to the server
  ///
  Future<void> sync({required String dbName}) async {
    late String clientId;
    bool syncing = false;
    try {
      syncController.add(SyncProgress(
        status: SyncStatus.starting,
        message: 'Starting sync...',
      ));
      await Future.delayed(Duration.zero); // Update UI

      // Get the clientid
      var clientInfo = await _getSyncConfigDetails(dbName: dbName);
      if (clientInfo == null) {
        throw SyncException("You have to configure the Sync!",
            type: SyncExceptionType.syncConfigurationMissing);
      }
      clientId = clientInfo["clientid"];
      int lastSync = clientInfo["lastsync"] ?? 0;
      //FIXME - JUST FOR DEBUG
      //lastSync = 0;

      syncing = true;
      _debugPrint("Get the changes list from the DB $dbName");
      // Solo metadati: i rowData (blob inclusi) vengono letti dal DB a blocchi
      // durante il push, così la memoria non cresce con la libreria.
      List<SyncData> syncDataList = await _getPendingChanges(dbName: dbName);
      // for (var element in syncDataList) {
      //   _debugPrint(
      //       "Table: ${element.tablename} Operation: ${element.operation} Key: ${element.rowguid}");
      // }

      // Perform the pull
      _debugPrint("PULL first");
      final clientDataList =
          await _pull(clientId, lastSync, syncDataList, dbName: dbName);

      // Do multiple push with partial data to avoid sending too many data at once

      // Perform the push of the remaining data.
      // I rowData (blob inclusi, in base64) vengono letti dal DB solo per il
      // blocco in corso: la memoria resta limitata da `kRowsLoadedAtOnce` e
      // dai limiti per richiesta, non dalla dimensione della libreria.
      _debugPrint("Time to PUSH...");
      late SyncInfo syncInfo;
      final total = clientDataList.length;
      if (total == 0) {
        syncInfo = await _push(clientId, lastSync, const <SyncData>[],
            dbName: dbName, isPartial: false);
      } else {
        var sentRows = 0;
        var chunk = <SyncData>[];
        var chunkBytes = 0;

        Future<void> flushChunk({required bool isPartial}) async {
          syncInfo = await _push(clientId, lastSync, chunk,
              dbName: dbName, isPartial: isPartial);
          if (deletePushedRowsProgressively) {
            await _deletePushedRows(chunk, dbName: dbName);
          }
          sentRows += chunk.length;
          // Il chunk contiene copie con i rowData: sostituendolo si liberano.
          chunk = <SyncData>[];
          chunkBytes = 0;
          if (sentRows < total) {
            syncController.add(SyncProgress(
              status: SyncStatus.pushing,
              message: 'Sent $sentRows/$total',
              processedItems: sentRows,
              totalItems: total,
            ));
            await Future.delayed(Duration.zero); // Update UI
            print("Pushing $sentRows/$total");
          }
        }

        for (var from = 0; from < total; from += kRowsLoadedAtOnce) {
          final to =
              (from + kRowsLoadedAtOnce) > total ? total : from + kRowsLoadedAtOnce;
          final window = clientDataList.sublist(from, to);
          // Carica i dati (e i blob) solo per queste righe. La mappa restituita
          // è l'unica copia in vita: i metadati in `clientDataList` non
          // trattengono mai i blob, quindi la memoria non cresce con la coda.
          final rowDataByGuid = await _loadRowData(window, dbName: dbName);

          for (final item in window) {
            final itemWithData = _copyWithRowData(
              item,
              rowDataByGuid[item.rowguid] ?? <String, dynamic>{},
            );
            final itemBytes = estimateSyncDataSize(itemWithData);
            final chunkFull = chunk.length >= maxRowsPerPush ||
                (chunk.isNotEmpty && chunkBytes + itemBytes > maxBytesPerPush);
            if (chunkFull) {
              final isLast = sentRows + chunk.length == total;
              await flushChunk(isPartial: !isLast);
            }
            chunk.add(itemWithData);
            chunkBytes += itemBytes;
          }
        }
        if (chunk.isNotEmpty) {
          await flushChunk(isPartial: false);
        }
      }

      // Add a small delay before completing
      await Future.delayed(const Duration(seconds: 1));

      syncController.add(SyncProgress(
        status: SyncStatus.completed,
        message: 'Sync completed successfully',
      ));
      await Future.delayed(Duration.zero); // Update UI

      if (syncInfo.lastSync != null) {
        // Delete rows from sync_data
        _debugPrint("Delete rows from sync_data");
        await sqliteWrapperSync.execute("DELETE FROM sync_data",
            dbName: dbName);

        // Update the last update date
        _debugPrint("Update last update date");
        await sqliteWrapperSync.execute("UPDATE sync_details SET lastSync = ?",
            params: [syncInfo.lastSync!.millisecondsSinceEpoch],
            dbName: dbName);
      }
    } catch (ex, stacktrace) {
      syncController.add(SyncProgress(
        status: SyncStatus.error,
        message: 'Sync failed',
        error: ex.toString(),
      ));
      await Future.delayed(Duration.zero); // Update UI

      if (ex is SyncException) {
        rethrow;
      }
      //ERROR
      debugPrint("ERROR DURING SYNC: $ex");
      debugPrint(stacktrace);
      if (ex.toString().contains("already syncing")) {
        throw SyncException(ex.toString(),
            type: SyncExceptionType.alreadySyncing);
      }
      throw SyncException(ex.toString(), type: SyncExceptionType.generic);
    } finally {
      // If it's syncing tell the server that it's not syncing anymore
      // but that the sync failed
      if (syncing) {
        await _cancelSync(clientId, dbName: dbName);
      }
    }
  }

  /// Start a forgotten password request
  ///   the server sends a mail to the email address
  ///   with a PIN that must be used set the new password
  ///   using the changePassword method
  Future<void> forgottenPassword({required String email}) async {
    await httpHelper.call("$serverUrl/password/$realm/forgotten", {},
        body: jsonEncode({"email": email}), method: "POST");
  }

  /// Change the password passing the PIN retrieved from the email received
  Future<void> changePassword(
      {required String email,
      required String password,
      required String pin,
      required String dbName}) async {
    final PasswordChange passwordChange =
        PasswordChange(email: email, password: password, pin: pin);
    final json = jsonEncode(passwordChange.toMap());
    try {
      await httpHelper.call("$serverUrl/password/$realm/change", {},
          body: json, method: "POST");
      // Update the password in the db
      const sqlUpdate = "UPDATE sync_details SET userpassword = ?";
      await sqliteWrapperSync
          .execute(sqlUpdate, params: [EncryptHelper.encryptPassword(password)], dbName: dbName);
    } on UnauthorizedException catch (ex) {
      throw SyncException(ex.toString(),
          type: SyncExceptionType.wrongOrExpiredPin);
    } on CustomHttpException catch (ex) {
      // 403 means that the PIN is
      if (ex.statusCode == 403) {
        throw SyncException(ex.message,
            type: SyncExceptionType.wrongOrExpiredPin);
      }
    }
  }

  /// Verifica se è configurata la sincronizzazione
  Future<bool> isConfigured({required String dbName}) async {
    try {
      const sql = "SELECT COUNT(*) FROM sync_details";
      return (await sqliteWrapperSync.query(sql,
              singleResult: true, dbName: dbName)) >
          0;
    } catch (_) {
      // Se la query fallisce (es. server giù, databases non popolato)
      // assumiamo che non sia configurato.
      return false;
    }
  }

  /// Reset syncDetails usually when both tokens are invalid
  Future<void> deleteSyncDetails({required String dbName}) async {
    await sqliteWrapperSync.execute(
        "DELETE FROM sync_details;DELETE FROM sync_encryption;",
        dbName: dbName);
  }

  /// Get the current SyncDetails  or null if sync is not yet configured
  Future<SyncDetails?> getSyncDetails({required String dbName}) async {
    return await sqliteWrapperSync.query("SELECT * FROM sync_details",
        singleResult: true,
        params: [],
        fromMap: SyncDetails.fromDB,
        dbName: dbName);
  }

  /// Perform the pull call
  Future<List<SyncData>> _pull(
      String clientId, int lastSync, List<SyncData> syncDataList,
      {required String dbName}) async {
    // The rowData are not needed in the pull, remove them
    try {
      var cursor = 0;
      var pages = 0;
      var downloaded = 0;

      while (true) {
        final ClientChanges clientChanges = ClientChanges()
          ..clientId = clientId
          ..lastSync = lastSync
          ..limit = maxRowsPerPull
          ..maxBytes = maxBytesPerPull
          ..cursor = cursor
          ..changes = syncDataList;

        final json = jsonEncode(clientChanges.toMap(skipRowData: true));
        // This call unexptectly returns even if it's awaited
        dynamic result = await authenticationHelper.authenticatedCall(
            "$serverUrl/pull/$realm/$clientId", {},
            body: json,
            method: "POST",
            dbName: dbName,
            isPushOrPull: true,
            syncController: syncController);

        api_sync_details.SyncDetails syncDetails =
            api_sync_details.SyncDetails.fromJson(result);

        // Now remove from syncDataList the keys indicated by the server
        for (var rowguid in syncDetails.outdatedRowsGuid!) {
          syncDataList.removeWhere((element) => element.rowguid == rowguid);
        }

        // Insert into the DB the new rows sent by the server (subito, senza
        // tenere in memoria tutte le pagine).
        await _importServerData(syncDetails.data, dbName: dbName);

        pages++;
        downloaded += syncDetails.data.length;
        _debugPrint(
            "Pull page $pages: ${syncDetails.data.length} changes, "
            "total $downloaded, hasMore ${syncDetails.hasMore}");
        syncController.add(SyncProgress(
            status: SyncStatus.pulling,
            message: 'Downloaded $downloaded changes',
            totalItems: downloaded,
            processedItems: downloaded));
        await Future.delayed(Duration.zero); // Update UI

        if (!syncDetails.hasMore) break;
        // Difesa contro un server che non fa avanzare il cursore.
        if (syncDetails.nextCursor <= cursor) {
          _debugPrint(
              "Pull: nextCursor non avanza (${syncDetails.nextCursor} <= $cursor), mi fermo");
          break;
        }
        cursor = syncDetails.nextCursor;
      }

      // Return the remaining syncData
      return syncDataList;
    } on Exception catch (e) {
      debugPrint("Error during pull: ${e.toString()}");
      rethrow;
    }
  }

  /// Perform the push call
  Future<SyncInfo> _push(
      String clientId, int lastSync, List<SyncData> syncDataList,
      {required String dbName, required bool isPartial}) async {
    final ClientChanges clientChanges = ClientChanges()
      ..clientId = clientId
      ..lastSync = lastSync
      ..isPartial = isPartial ? 1 : 0
      ..changes = syncDataList;

    final json = jsonEncode(clientChanges.toMap(skipRowData: false));
    _debugPrint("PUSH ${syncDataList.length} rows");
    dynamic result = await authenticationHelper.authenticatedCall(
        "$serverUrl/push/$realm/$clientId", {},
        body: json,
        method: "POST",
        dbName: dbName,
        isPushOrPull: true,
        syncController: syncController);
    SyncInfo syncInfo = SyncInfo.fromJson(result);

    return syncInfo;
  }

  /// Sync should be stopped...
  Future<void> _cancelSync(String clientId, {required String dbName}) async {
    try {
      final json = jsonEncode({"clientId": clientId});
      // This call unexptectly returns even if it's awaited
      await authenticationHelper.authenticatedCall(
          "$serverUrl/cancelSync/$realm", {},
          body: json,
          method: "POST",
          dbName: dbName,
          syncController: syncController);
    } on Exception catch (e) {
      debugPrint("Error during cancelSync: ${e.toString()}");
    }
  }

  ///Import data from Server generating the DELETE, INSERT OR UPDATE calls
  Future<void> _importServerData(List<SyncData> syncDataList,
      {required String dbName}) async {
    // Prepara le info sulle tabelle da sincronizzare
    for (var i = 0; i < syncDataList.length; i++) {
      syncController.add(SyncProgress(
          status: SyncStatus.pulling,
          message: 'Importing remote data',
          totalItems: syncDataList.length,
          processedItems: i));
      await Future.delayed(Duration.zero); // Update UI
      final SyncData syncData = syncDataList.elementAt(i);
      final TableInfo tableInfo =
          sqliteWrapperSync.tableInfos[syncData.tablename]!;
      if (syncData.operation == "D") {
        final sql =
            "DELETE from ${syncData.tablename} WHERE ${tableInfo.keyField} = ?";
        await sqliteWrapperSync.execute(sql,
            params: [syncData.rowguid],
            dbName: dbName,
            tables: [syncData.tablename!]);
      } else {
        // PROVA SEMPRE PRIMA UN UPDATE, IN CASO DI FALLIMENTO PROCEDI CON UNA INSERT
        // RIMUOVI LA ROWGUID dai campi in modo da essere sicuro della posizione
        if (syncData.rowData == null) {
          _debugPrint("No data for guid ${syncData.rowguid}...");
          continue;
        }
        final rowData = Map<String, dynamic>.from(syncData.rowData!);
        rowData.removeWhere(
            (key, value) => key == "rowguid" || key == tableInfo.keyField);


        // If a field valus contains binary data is encoded in base64 and
        // must be decoded
        for (var element in tableInfo.binaryFields) {
          if (rowData[element] != null) {
            rowData[element] = const Base64Decoder().convert(rowData[element]);
          }
        }
        // If some columns should be encrypted go ahead...
        if (tableInfo.encryptedFields.isNotEmpty) {
          //debugPrint("PROCEDI A DECRYPT");
          // LOAD THE SECRET KEY
          if (EncryptHelper.secretKey == null) {
            await sqliteWrapperSync.getSecretKey(dbName: dbName);
          }
          // Should encrypt data
          for (var fieldName in tableInfo.encryptedFields) {
            rowData[fieldName] = EncryptHelper.decrypt(rowData[fieldName]);
          }
          //debugPrint(rowData);
        }

        // Se abbiamo delle colonne di cui cambiare il nome
        tableInfo.aliasesFields.forEach((key, value) {
          rowData[value] = rowData[key];
          rowData.remove(key);
        });

        // ADD to update other fields that must be set to null
        await _addNullFields(syncData.tablename!, tableInfo.keyField, rowData,
            dbName: dbName);

        // Valori
        final List values = rowData.values.toList(growable: true);

        // Add the key as last params
        values.add(syncData.rowguid);

        var sql = """UPDATE ${syncData.tablename} 
              SET
              ${rowData.keys.toList().join(" = ?,")} = ? 
              WHERE ${tableInfo.keyField} = ?""";
        final updated = await sqliteWrapperSync.execute(sql,
            params: values, dbName: dbName, tables: [syncData.tablename!]);
        if (updated == 0) {
          //INSERT
          var sql = """INSERT INTO ${syncData.tablename} 
              (
                ${rowData.keys.toList().join(", ")}
                , ${tableInfo.keyField}) 
              VALUES 
                (
                ${values.map((e) => "?").join(', ')}
                )""";
          _debugPrint(
              "Processing rowguid - ${syncData.rowguid} - table: ${syncData.tablename} operation:  ${syncData.operation}");

          await sqliteWrapperSync.execute(sql,
              params: values, dbName: dbName, tables: [syncData.tablename!]);
        }
      }
    }
  }

  /// Get the data to sync from the client DB
  /// Modifiche locali in attesa di push: **solo metadati**.
  ///
  /// Per il pull il server non ha bisogno dei dati della riga (`skipRowData`),
  /// quindi i blob non vengono toccati finché la riga non sta per partire.
  Future<List<SyncData>> _getPendingChanges({required String dbName}) async {
    final List<SyncData> changes = List.empty(growable: true);
    for (final tableName in sqliteWrapperSync.tableInfos.keys) {
      final sql = """SELECT sd.id as id, sd.operation,
                            sd.clientdate as clientdate, sd.rowguid as rowguid
         FROM sync_data sd
         WHERE sd.id IN (
            SELECT MAX(id) FROM sync_data WHERE tablename=? GROUP by tablename, rowguid
            )
         ORDER BY sd.id""";
      final rows = await sqliteWrapperSync.query(
        sql,
        params: [tableName],
        dbName: dbName,
      );
      for (final row in rows) {
        final map = row as Map;
        changes.add(SyncData(
          id: map["id"] as int,
          operation: map["operation"] as String,
          rowguid: map["rowguid"] as String,
          tablename: tableName,
          clientdate: DateTime.fromMillisecondsSinceEpoch(
            map["clientdate"] as int,
            isUtc: true,
          ),
        ));
      }
    }
    return changes;
  }

  /// Carica i dati correnti delle righe passate (una query per tabella) e li
  /// restituisce già pronti per il push: `rowguid` -> `rowData`.
  ///
  /// Le righe eliminate localmente non esistono più: la mappa non le contiene,
  /// e il push manderà `rowData` vuoto (come faceva la LEFT JOIN del vecchio
  /// caricamento massivo).
  Future<Map<String, Map<String, dynamic>>> _loadRowData(
    List<SyncData> items, {
    required String dbName,
  }) async {
    final byTable = <String, List<SyncData>>{};
    for (final item in items) {
      final tableName = item.tablename;
      if (tableName == null) continue;
      byTable.putIfAbsent(tableName, () => []).add(item);
    }

    final result = <String, Map<String, dynamic>>{};
    for (final entry in byTable.entries) {
      final tableInfo = sqliteWrapperSync.tableInfos[entry.key];
      if (tableInfo == null) continue;
      final keyField = tableInfo.keyField;
      final placeholders = List.filled(entry.value.length, '?').join(',');
      final rows = await sqliteWrapperSync.query(
        'SELECT * FROM ${entry.key} WHERE $keyField IN ($placeholders)',
        params: entry.value.map((e) => e.rowguid).toList(),
        dbName: dbName,
      );

      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final guid = '${map[keyField]}';
        await _prepareRowData(map, tableInfo, dbName: dbName);
        result[guid] = map;
      }
    }
    return result;
  }

  /// Toglie da `sync_data` le righe appena inviate con successo.
  ///
  /// Il push è transazionale lato server: quando risponde 200 le modifiche sono
  /// già persistite, quindi toglierle in locale non perde nulla e rende la sync
  /// ripartibile (un'interruzione fa ripartire solo il residuo).
  Future<void> _deletePushedRows(List<SyncData> chunk,
      {required String dbName}) async {
    final ids = chunk.map((e) => e.id).whereType<int>().toList();
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    await sqliteWrapperSync.execute(
      'DELETE FROM sync_data WHERE id IN ($placeholders)',
      params: ids,
      dbName: dbName,
    );
  }

  /// Copia della modifica con i dati della riga, per non agganciare i blob ai
  /// metadati che vivono per tutta la durata della sync.
  SyncData _copyWithRowData(SyncData item, Map<String, dynamic> rowData) {
    return SyncData(
      id: item.id,
      operation: item.operation,
      rowguid: item.rowguid,
      tablename: item.tablename,
      clientdate: item.clientdate,
      rowData: rowData,
    );
  }

  /// Converte i campi binari in base64, scarta i null e cifra i campi previsti.
  Future<void> _prepareRowData(
    Map<String, dynamic> rowData,
    TableInfo tableInfo, {
    required String dbName,
  }) async {
    for (final field in tableInfo.binaryFields) {
      if (rowData[field] == null) continue;
      final include = tableInfo.includeBinaryField;
      if (include != null && !include(field, rowData)) {
        rowData.remove(field);
        continue;
      }
      rowData[field] = base64Encode(rowData[field] as Uint8List);
    }
    // Remove null values to spare some space
    rowData.removeWhere((key, value) => value == null);

    if (tableInfo.encryptedFields.isNotEmpty) {
      if (EncryptHelper.secretKey == null) {
        await sqliteWrapperSync.getSecretKey(dbName: dbName);
      }
      for (final fieldName in tableInfo.encryptedFields) {
        rowData[fieldName] = EncryptHelper.encrypt(rowData[fieldName]);
      }
    }
  }

  /// Memorizza sul DB le credenziali scambiate con il server
  Future<void> _configureSync(
      String? name, String email, String password, String clientId,
      {required String dbName}) async {
    const sqlUpdate =
        "INSERT INTO sync_details (name, clientid, useremail, userpassword) values (?,?,?,?)";
    await sqliteWrapperSync.execute(sqlUpdate,
        params: [name, clientId, email, EncryptHelper.encryptPassword(password)],
        dbName: dbName);
  }

  /// Ottiene il client id (clientid e lastsync in una map) o restituisce null qualora non sia stato definito
  Future<Map<String, dynamic>?> _getSyncConfigDetails({required String dbName}) async {
    const sql = "SELECT clientid, lastsync FROM sync_details";
    final row =
        await sqliteWrapperSync.query(sql, singleResult: true, dbName: dbName);
    if (row == null) {
      return null;
    }
    return row;
  }

  /// Create the insert LOGs for all the rows already in the DB
  Future<void> _logPreviouslyInsertedData({required String dbName}) async {
    for (final entry in sqliteWrapperSync.tableInfos.entries) {
      final String tableName = entry.key;
      final TableInfo tableInfo = entry.value;
      final filter = tableInfo.rowFilter != null
          ? " WHERE ${tableInfo.rowFilter}"
          : "";
      final String sql = "SELECT ${tableInfo.keyField} FROM $tableName$filter";
      List<String> rowguids =
          List<String>.from(await sqliteWrapperSync.query(sql, dbName: dbName));
      for (String rowguid in rowguids) {
        await sqliteWrapperSync.logOperation(tableName, Operation.insert, rowguid,
            dbName: dbName, force: true);
      }
    }
  }

  void _debugPrint(String message) {
    if (debug) {
      print(message);
    }
  }

  /// Return the list of all columns of a table
  Future<List<String>> _getAllTablesColumns(String table,
      {required String dbName}) async {
    const sql = """SELECT name as columnName
                    FROM pragma_table_info(?)
                    order by columnName""";
    final List<String> results = List.from(
        await sqliteWrapperSync.query(sql, params: [table], dbName: dbName));
    return results;
  }

  /// Set to null missing fields present in the table but absent from the json
  /// object, because they are non sent to save space on the remote server and
  /// during connection
  Future<void> _addNullFields(
      String table, String keyField, Map<String, dynamic> rowData,
      {required String dbName}) async {
    // Get all columns
    List<String> columns = await _getAllTablesColumns(table, dbName: dbName);
    List<String> keys = rowData.keys.toList();
    // Remove columns already settable
    columns.removeWhere(
        (element) => keys.contains(element) || element == keyField);
    // Add to rowData with value null the remaining columns

    final Map<String, dynamic> nullFields = {};
    for (String key in columns) {
      nullFields[key] = null;
    }
    rowData.addAll(nullFields);
  }

  void dispose() {
    syncController.close();
  }
}
