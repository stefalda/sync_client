import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite_wrapper/sqlite_wrapper.dart';
import 'package:sync_client/src/api/models/client_changes.dart';
import 'package:sync_client/src/api/models/password_chage.dart';
import 'package:sync_client/src/api/models/sync_data.dart';
import 'package:sync_client/src/api/models/sync_details.dart'
    as api_sync_details;
import 'package:sync_client/src/api/models/sync_info.dart';
import 'package:sync_client/src/api/models/user_registration.dart';
import 'package:sync_client/src/authentication_helper.dart';
import 'package:sync_client/src/debug_utils.dart';
import 'package:sync_client/sync_client.dart';

class SyncRepository {
  final SQLiteWrapperSync sqliteWrapperSync;
  final String serverUrl;
  final String realm;
  late AuthenticationHelper authenticationHelper;
  bool debug = true;
  //Constructor
  SyncRepository(
      {required this.sqliteWrapperSync,
      required this.serverUrl,
      required this.realm}) {
    authenticationHelper = AuthenticationHelper(
        dbName: defaultDBName, serverUrl: serverUrl, realm: realm);
  }

  /// Register the User and the Client
  /// (only the Client if newRegistration is false)
  /// and store the credentials in the DB
  Future<void> register(
      {required String name,
      required String email,
      required String password,
      required String deviceInfo,
      required bool newRegistration,
      required String language,
      required String
          secretKey, // If "" the key will be generated automatically
      dbName = defaultDBName}) async {
    const sql = "SELECT * FROM sync_details";
    final rows = await SQLiteWrapper().query(sql, dbName: dbName);
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
      dynamic result = await HttpHelper.call("$serverUrl/register/$realm", {},
          body: json, method: "POST");

      // Save the name
      if (!newRegistration && name.isEmpty) {
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
      // GENERATE THE SECRET KEY
      // If there're no encrypted fields in the
      // tableInfo it will be never used
      secretKey = sqliteWrapperSync.generateSecretKey();
    }
    await sqliteWrapperSync.setSecretKey(secretKey);

    await _configureSync(name, email, password, userRegistration.clientId!,
        dbName: dbName);
    await _logPreviouslyInsertedData(dbName: dbName);
    //syncConfigured = SyncEnabled.enabled;
    debugPrint("Ready for first sync");
  }

  /// Unregister the client, optionally deleting ALL the data
  /// related to this user if the deleteRemoteData is set to true
  Future<void> unregister(
      {required String email,
      required String password,
      required String clientId,
      dbName = defaultDBName,
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
        body: json, method: "POST");
    await resetDB();
  }

  /// Reset the table data for account and sync data
  Future<void> resetDB({dbName = defaultDBName}) async {
    // DELETE LOGGED DATA
    await SQLiteWrapper().execute("DELETE FROM sync_data", dbName: dbName);
    // DELETE SYNC DETAIL
    await SQLiteWrapper().execute("DELETE FROM sync_details", dbName: dbName);
    // DELETE THE SECRET KEY
    await SQLiteWrapper()
        .execute("DELETE FROM sync_encryption", dbName: dbName);
  }

  ///
  /// Sync the data by performing two API calls
  ///
  ///   PULL - to get all the information from the server deciding if some data on the client are outdated
  ///   PUSH - to send all the (valid) changes to the server
  ///
  Future<void> sync({dbName = defaultDBName}) async {
    try {
      // Ottieni il clientid
      var clientInfo = await _getSyncConfigDetails(dbName: dbName);
      if (clientInfo == null) {
        throw SyncException("You have to configure the Sync!",
            type: SyncExceptionType.syncConfigurationMissing);
      }
      String clientId = clientInfo["clientid"];
      int lastSync = clientInfo["lastsync"] ?? 0;

      // Controlla quali copertine sono già presenti sul server o quali sono "custom"
      // final synController = SyncCovers();
      // await synController.checkCustomCovers();

      _debugPrint("Get the changes list from the DB $dbName");
      // Ottieni l'elenco delle modifiche da inviare
      List<SyncData> syncDataList = await _getDataToSync(dbName: dbName);
      for (var element in syncDataList) {
        _debugPrint(
            "Table: ${element.tablename} Operation: ${element.operation} Key: ${element.rowguid}");
      }

      // Effettua il pull
      _debugPrint("Effettua la chiamata PULL");
      final clientDataList =
          await _pull(clientId, lastSync, syncDataList, dbName: dbName);

      // Effettua il push dei dati superstiti
      _debugPrint("Effettua la chiamata PUSH");
      final SyncInfo syncInfo = await _push(clientId, lastSync, clientDataList);

      /// Aggiorna le copertine
      //  await _downloadCovers();

      if (syncInfo.lastSync != null) {
        // Cancella le righe in syncdata
        _debugPrint("Cancella le righe da sync_data");
        await SQLiteWrapper().execute("DELETE FROM sync_data", dbName: dbName);

        // Aggiorna la data di ultimo aggiornamento
        _debugPrint("Aggiorna la data di ultimo aggiornamento");
        await SQLiteWrapper().execute("UPDATE sync_details SET lastSync = ?",
            params: [syncInfo.lastSync!.millisecondsSinceEpoch],
            dbName: dbName);
      }
    } catch (ex, stacktrace) {
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
    }
  }

  /// Start a forgotten password request
  ///   the server sends a mail to the email address
  ///   with a PIN that must be used set the new password
  ///   using the changePassword method
  Future<void> forgottenPassword({required String email}) async {
    await HttpHelper.call("$serverUrl/password/$realm/forgotten", {},
        body: jsonEncode({"email": email}), method: "POST");
  }

  /// Change the password passing the PIN retrieved from the email received
  Future<void> changePassword(
      {required String email,
      required String password,
      required String pin,
      dbName = defaultDBName}) async {
    final PasswordChange passwordChange =
        PasswordChange(email: email, password: password, pin: pin);
    final json = jsonEncode(passwordChange.toMap());
    try {
      await HttpHelper.call("$serverUrl/password/$realm/change", {},
          body: json, method: "POST");
      // Update the password in the db
      const sqlUpdate = "UPDATE sync_details SET userpassword = ?";
      await SQLiteWrapper()
          .execute(sqlUpdate, params: [password], dbName: dbName);
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
  Future<bool> isConfigured({dbName = defaultDBName}) async {
    const sql = "SELECT COUNT(*) FROM sync_details";
    return (await sqliteWrapperSync.query(sql,
            singleResult: true, dbName: dbName)) >
        0;
  }

  /// Reset syncDetails usually when both tokens are invalid
  Future<void> deleteSyncDetails({dbName = defaultDBName}) async {
    await SQLiteWrapper().execute(
        "DELETE FROM sync_details;DELETE FROM sync_encryption;",
        dbName: dbName);
  }

  /// Get the current SyncDetails  or null if sync is not yet configured
  Future<SyncDetails?> getSyncDetails({dbName = defaultDBName}) async {
    return await SQLiteWrapper().query("SELECT * FROM sync_details",
        singleResult: true,
        params: [],
        fromMap: SyncDetails.fromDB,
        dbName: dbName);
  }

  /// Effettua la chiamata al pull
  Future<List<SyncData>> _pull(
      String clientId, int lastSync, List<SyncData> syncDataList,
      {dbName = defaultDBName}) async {
    // i rowData non servono nella pull, rimuvili
    final ClientChanges clientChanges = ClientChanges()
      ..clientId = clientId
      ..lastSync = lastSync
      ..changes = syncDataList;

    final json = jsonEncode(clientChanges.toMap(skipRowData: true));
    dynamic result = await authenticationHelper.authenticatedCall(
        "$serverUrl/pull/$realm", {},
        body: json, method: "POST");

    api_sync_details.SyncDetails syncDetails =
        api_sync_details.SyncDetails.fromJson(result);
    // Adesso rimuove da syncDataList le chiavi indicate dal server
    for (var rowguid in syncDetails.outdatedRowsGuid!) {
      syncDataList.removeWhere((element) => element.rowguid == rowguid);
    }
    _debugPrint(
        "Risultati pull: da eliminare dall'invio ${syncDetails.outdatedRowsGuid!.length} - da aggiornare dal server ${syncDetails.data.length}");

    // Inserisce dentro il DB le nuove righe inviate dal DB
    await _importServerData(syncDetails.data, dbName: dbName);
    // Restituisce l'elenco dei syncData superstiti
    return syncDataList;
  }

  /// Effettua la chiamata al push
  Future<SyncInfo> _push(
      String clientId, int lastSync, List<SyncData> syncDataList) async {
    final ClientChanges clientChanges = ClientChanges()
      ..clientId = clientId
      ..lastSync = lastSync
      ..changes = syncDataList;

    final json = jsonEncode(clientChanges.toMap(skipRowData: false));
    _debugPrint("PUSH ${syncDataList.length} rows");
    dynamic result = await authenticationHelper.authenticatedCall(
        "$serverUrl/push/$realm", {},
        body: json, method: "POST");
    SyncInfo syncInfo = SyncInfo.fromJson(result);

    return syncInfo;
  }

  /**
   * Cicla sui SyncData e aggionge i dati delle righe
      Future<List<SyncData>> _completeData(List<SyncData> syncDataList) async {
      syncDataList.forEach((syncData) async {
      if (syncData.operation != "D") {
      final sql =
      "SELECT * from ${syncData.tablename}_sync WHERE ${syncData.tablename!.substring(0, syncData.tablename!.length - 2)}id=${syncData.rowguid}";
      syncData.rowData =
      (await this._dbService.getResult(sql)) as Map<String, dynamic>;
      }
      });
      return syncDataList;
      }
   */

  ///Import data from Server generating the DELETE, INSERT OR UPDATE calls
  Future<void> _importServerData(List<SyncData> syncDataList,
      {dbName = defaultDBName}) async {
    // Prepara le info sulle tabelle da sincronizzare
    for (var i = 0; i < syncDataList.length; i++) {
      final SyncData syncData = syncDataList.elementAt(i);
      final TableInfo tableInfo =
          sqliteWrapperSync.tableInfos[syncData.tablename]!;
      if (syncData.operation == "D") {
        final sql =
            "DELETE from ${syncData.tablename} WHERE ${tableInfo.keyField} = ?";
        await SQLiteWrapper().execute(sql,
            params: [syncData.rowguid],
            dbName: dbName,
            tables: [syncData.tablename!]);
      } else {
        // PROVA SEMPRE PRIMA UN UPDATE, IN CASO DI FALLIMENTO PROCEDI CON UNA INSERT
        // RIMUOVI LA ROWGUID dai campi in modo da essere sicuro della posizione
        if (syncData.rowData == null) {
          _debugPrint("MANCANO I DATI!");
          break;
        }
        final rowData = Map<String, dynamic>.from(syncData.rowData!);
        rowData.removeWhere(
            (key, value) => key == "rowguid" || key == tableInfo.keyField);
        /*
        // Se uno dei campi è un uuid occorre trascodificarlo nell'id relativo al DB corrente
        for (var n = 0; n < tableInfo.externalKeys.length; n++) {
          final externalKey = tableInfo.externalKeys[n];
          if (rowData[externalKey.fieldName] != null) {
            final res = await SQLiteWrapper().query(
                "SELECT ${externalKey.externalFieldKey} as value FROM "
                "${externalKey.externalFieldTable} WHERE "
                "${externalKey.externalKey}='${rowData[externalKey.fieldName]}'",
                singleResult: true,
                dbName: dbName);
            rowData[externalKey.fieldName] = res!["value"];
          }
        }*/

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
            await sqliteWrapperSync.getSecretKey();
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
        // Se abbiamo dei valori booleani convertili in numeri
        /*for (var key in tableInfo.booleanFields) {
          print("Converti il boolean field...");
          if (rowData[key] != null) {
            rowData[key] = rowData[key] == true ? 1 : 0;
          }
        }*/
        // ADD to update other fields that must be set to null
        await _addNullFields(syncData.tablename!, tableInfo.keyField, rowData);

        // Valori
        final List values = rowData.values.toList(growable: true);

        // Add the key as last params
        values.add(syncData.rowguid);

        var sql = """UPDATE ${syncData.tablename} 
              SET
              ${rowData.keys.toList().join(" = ?,")} = ? 
              WHERE ${tableInfo.keyField} = ?""";
        final updated = await SQLiteWrapper().execute(sql,
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
          await await SQLiteWrapper().execute(sql,
              params: values, dbName: dbName, tables: [syncData.tablename!]);
        }
      }
    }
  }

  Future<List<SyncData>> _getDataToSync({dbName = defaultDBName}) async {
    final List<SyncData> syncDataList = List.empty(growable: true);
    for (String tableName in sqliteWrapperSync.tableInfos.keys) {
      final TableInfo tableInfo = sqliteWrapperSync.tableInfos[tableName]!;
      syncDataList.addAll(await _getSyncData(tableName, tableInfo.keyField,
          dbName: dbName,
          binaryFields: tableInfo.binaryFields,
          encryptedFields: tableInfo.encryptedFields));
    }
    return syncDataList;
  }

  /// Compila le informazioni da inviare al server generandole nel caso del primo inserimento
  Future<List<SyncData>> _getSyncData(String tableName, String keyField,
      {required List<String> binaryFields,
      required List<String> encryptedFields,
      dbName = defaultDBName}) async {
    final sql =
        """SELECT sd.operation, sd.clientdate as clientdate, sd.rowguid as _guid, rowData.*
         from sync_data sd LEFT JOIN $tableName as rowData on rowData.$keyField=sd.rowguid
         WHERE
         sd.id IN (
            SELECT MAX(id) FROM sync_data WHERE tablename='$tableName' GROUP by tablename, rowguid
            )
         """;
    List<SyncData> data = List.empty(growable: true);
    final rows = await SQLiteWrapper().query(sql, dbName: dbName);
    for (Map<String, dynamic> row in rows) {
      SyncData syncData = SyncData();
      syncData.rowguid = row["_guid"] as String;
      syncData.tablename = tableName;
      // Dati da sync_data
      syncData.operation = row["operation"] as String;
      syncData.clientdate =
          DateTime.fromMillisecondsSinceEpoch(row["clientdate"] as int);
      // Il risultato della query è immutabile quindi ne creo un clone per
      // manipolarlo
      final rowData = Map<String, dynamic>.from(row);
      //Remove from the result the rowguid id
      rowData.removeWhere((key, value) => key == '_guid');
      // Lascia solo i dati della riga
      // Converti in base 64 i binaryFields
      for (String field in binaryFields) {
        if (rowData[field] != null) {
          rowData[field] = base64Encode(rowData[field] as Uint8List);
        }
      }
      // Remove null values to spare some space
      rowData.removeWhere((key, value) => value == null);
      // If some columns should be encrypted go ahead...
      if (encryptedFields.isNotEmpty) {
        //debugPrint("PROCEDI A ENCRYPT");

        /// Load the secretKey is it's still not set...
        if (EncryptHelper.secretKey == null) {
          await sqliteWrapperSync.getSecretKey();
        }
        // Should encrypt data
        for (var fieldName in encryptedFields) {
          rowData[fieldName] = EncryptHelper.encrypt(rowData[fieldName]);
        }
        //debugPrint(rowData);
      }

      rowData.removeWhere(
          (key, value) => key == "operation" || key == "clientdate");
      syncData.rowData = rowData;
      data.add(syncData);
    }
    return data;
  }

  /// Memorizza sul DB le credenziali scambiate con il server
  Future<void> _configureSync(
      String name, String email, String password, String clientId,
      {dbName = defaultDBName}) async {
    const sqlUpdate =
        "INSERT INTO sync_details (name, clientid, useremail, userpassword) values (?,?,?,?)";
    await SQLiteWrapper().execute(sqlUpdate,
        params: [name, clientId, email, password], dbName: dbName);
  }

  /// Ottiene il client id (clientid e lastsync in una map) o restituisce null qualora non sia stato definito
  _getSyncConfigDetails({dbName = defaultDBName}) async {
    const sql = "SELECT clientid, lastsync FROM sync_details";
    final row =
        await SQLiteWrapper().query(sql, singleResult: true, dbName: dbName);
    if (row == null) {
      return null;
    }
    return row;
  }

  /// Create the insert LOGs for all the rows already in the DB
  Future<void> _logPreviouslyInsertedData({dbName = defaultDBName}) async {
    //Map<String, TableInfo> tableInfos = _getTableInfos();
    for (var i = 0; i < sqliteWrapperSync.tableInfos.keys.length; i++) {
      final String tableName = sqliteWrapperSync.tableInfos.keys.elementAt(i);
      final TableInfo tableInfo = sqliteWrapperSync.tableInfos[tableName]!;
      final String sql = "SELECT ${tableInfo.keyField} FROM $tableName";
      //FIXME - the only composite
      // This is an associative table without an own key
      // if (tableInfo.keyField == "" && tableInfo.externalKeys.length > 0) {
      //  sql =
      //      "SELECT ${tableInfo.externalKeys.map((e) => e.fieldName).join(", ")} FROM $tableName";
      //}
      List<String> rowguids =
          List<String>.from(await SQLiteWrapper().query(sql, dbName: dbName));
      for (String rowguid in rowguids) {
        sqliteWrapperSync.logOperation(tableName, Operation.insert, rowguid,
            dbName: dbName, force: true);
      }
    }
  }

  _debugPrint(String message) {
    if (debug) {
      print(message);
    }
  }

  /// Return the list of all columns of a table
  Future<List<String>> _getAllTablesColumns(String table,
      {dbName = defaultDBName}) async {
    const sql = """SELECT p.name as columnName
                    FROM sqlite_master m
                    left outer join pragma_table_info((m.name)) p
                        on m.name <> p.name
                    WHERE m.name=?
                    order by columnName""";
    final List<String> results = List.from(
        await SQLiteWrapper().query(sql, params: [table], dbName: dbName));
    return results;
  }

  /// Set to null missing fields present in the table but absent from the json
  /// object, because they are non sent to save space on the remote server and
  /// during connection
  Future<void> _addNullFields(
      String table, String keyField, Map<String, dynamic> rowData) async {
    // Get all columns
    List<String> columns = await _getAllTablesColumns(table);
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
}
