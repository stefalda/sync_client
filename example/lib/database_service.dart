import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite_wrapper/grpc/sqlite_service_client_wrapper.dart';
import 'package:sqlite_wrapper_sync_sample/main.dart';
import 'package:sqlite_wrapper_sync_sample/models.dart';
import 'package:sync_client/sync_client.dart';

/// Singleton class to operate with the database and the sync server
class DatabaseService {
  /// Notificatore per forzare il rebuild delle liste dopo un reset.
  final ValueNotifier<int> resetNotifier = ValueNotifier<int>(0);
  /// Return conditionally the sync client
  // ignore: strict_top_level_inference
  getSyncClient({required String dbName}) {
    if (dbName == grpcName) {
      //|| dbName == dbName1) {
      return sqLiteWrapperSyncGRPC;
    }
    return sqLiteWrapperSync;
  }

  /// Define the tables structure
  SQLiteWrapperSync sqLiteWrapperSync = SQLiteWrapperSync(
      tableInfos: {"todos": TableInfo(keyField: 'rowguid', binaryFields: [])});

  SQLiteWrapperSyncGRPC sqLiteWrapperSyncGRPC = SQLiteWrapperSyncGRPC(
      tableInfos: {"todos": TableInfo(keyField: 'rowguid', binaryFields: [])},
      host: 'localhost',
      port: 50052);

  /// Init the Database
  Future<void> initDB(
      {bool inMemory = false,
      bool test = false,
      required String dbName,
      useGRPC = false}) async {
    debugPrint("initDB $dbName");
    String dbPath = inMemoryDatabasePath;
    if (useGRPC) {
      // gRPC connection already configured via constructor
    } else if (!inMemory) {
      if (test) {
        dbPath = "$dbName.sqlite";
        final f = File(dbPath);
        if (f.existsSync()) {
          f.deleteSync();
        }
      } else {
        if (!kIsWeb) {
          final docDir = await getApplicationDocumentsDirectory();
          if (!await docDir.exists()) {
            await docDir.create(recursive: true);
          }
          dbPath = p.join(docDir.path, "$dbName.sqlite");
        } else {
          // WEB VERSION OR grpcDB
          dbPath = dbName;
        }
      }
    }
    final client = getSyncClient(dbName: dbName);
    if (useGRPC) {
      // openDB via gRPC potrebbe fallire (es. server irraggiungibile).
      // Il try/catch assicura che l'app continui comunque.
      try {
        await client.openDB(dbPath,
            dbName: dbName, useGRPC: useGRPC, onCreate: () async {
          await _createTables(dbName: dbName);
        });
      } catch (e) {
        debugPrint("Warning: gRPC initDB failed: $e");
      }
      // Garantisce che databases abbia l'entry per grpcDB anche se openDB
      // è fallito (es. server irraggiungibile al primo avvio).
      _ensureGrpcDbEntry();
    } else {
      final DatabaseInfo dbInfo = await client.openDB(dbPath,
          dbName: dbName, useGRPC: useGRPC, onCreate: () async {
        await _createTables(dbName: dbName);
      });
      debugPrint("Database path: ${dbInfo.path}");
    }
  }

  Future<void> _createTables({required String dbName}) async {
    const String sql = """CREATE TABLE IF NOT EXISTS "todos" (
          "rowguid" varchar(36) PRIMARY KEY NOT NULL,
          "title" varchar(255) NOT NULL,
          "done" int default 0
        );
        """;
    await getSyncClient(dbName: dbName).execute(sql, dbName: dbName);
    await getSyncClient(dbName: dbName).initSyncTables(dbName: dbName);
  }

  /// Assicura che databases abbia l'entry per grpcDB.
  /// Necessario perché openDB via gRPC potrebbe fallire (es. server giù).
  /// Da chiamare sempre dopo un tentativo di initDB gRPC.
  void _ensureGrpcDbEntry() {
    // ignore: unnecessary_null_comparison
    if (sqLiteWrapperSyncGRPC.databases.get(grpcName) == null) {
      sqLiteWrapperSyncGRPC.databases.add(
          name: grpcName,
          useGRPC: true,
          db: SqliteServiceClientWrapper(
              client: sqLiteWrapperSyncGRPC.client,
              dbName: grpcName));
    }
  }

  /// Return a list of all todos
  Stream getTodos({required String dbName}) {
    return getSyncClient(dbName: dbName).watch(
        "SELECT * FROM todos order by rowguid",
        tables: [Todo.table],
        fromMap: Todo.fromMap,
        dbName: dbName);
  }

  /// Create a stream to update the todo count
  Stream<Map<String, dynamic>> getTodoCount({required String dbName}) {
    return Stream.castFrom(getSyncClient(dbName: dbName).watch("""
        SELECT SUM(done) as done, sum(todo) as todo FROM (
        SELECT COUNT(*) as done,  0 as todo FROM todos where done = 1
        UNION
        SELECT 0 as done,  COUNT(*) as todo FROM todos where done = 0
        ) as todos 
      """, tables: [Todo.table], singleResult: true, dbName: dbName));
  }

  /// Add the new to-do Item
  Future<String> addNewTodo(String title, {required String dbName}) async {
    final rowguid = getSyncClient(dbName: dbName).newUUID();
    await getSyncClient(dbName: dbName).insert(
        Todo(rowguid: rowguid, title: title).toMap(), Todo.table,
        dbName: dbName);
    return rowguid;
  }

  /// Toggle a todo item - Done/To Do
  Future<void> toggleDone(Todo todo, {required String dbName}) async {
    todo.done = !todo.done;
    await getSyncClient(dbName: dbName)
        .update(todo.toMap(), "todos", keys: ["rowguid"], dbName: dbName);
  }

  /// Remove the todo item
  Future<void> deleteTodo(Todo todo, {required String dbName}) async {
    await getSyncClient(dbName: dbName)
        .delete(todo.toMap(), "todos", keys: ["rowguid"], dbName: dbName);
  }

  /// Save the new todo
  Future<void> saveTodo(Todo todo, {required String dbName}) async {
    await getSyncClient(dbName: dbName)
        .save(todo.toMap(), "todos", keys: ["rowguid"], dbName: dbName);
  }

  /// Get a specific todo by id
  Future<Todo?> getTodo(String rowguid, {required String dbName}) async {
    return await getSyncClient(dbName: dbName).query(
        "SELECT * FROM ${Todo.table} WHERE rowguid=?",
        params: [rowguid],
        fromMap: Todo.fromMap,
        singleResult: true,
        dbName: dbName);
  }

  /// Get a specific todo by title
  Future<Todo?> getTodoByTitle(String title, {required String dbName}) async {
    return await getSyncClient(dbName: dbName).query(
        "SELECT * FROM ${Todo.table} WHERE title=?",
        params: [title],
        fromMap: Todo.fromMap,
        singleResult: true,
        dbName: dbName);
  }

  /// Get the sync repository configuration (URL and REALM)
  dynamic _getSyncRepository({required String dbName}) {
    return SyncRepository(
        serverUrl: "http://localhost:3000",
        sqliteWrapperSync: getSyncClient(dbName: dbName),
        realm: "default");
  }

  /// Register all three databases (primary, secondary, gRPC).
  Future<void> register(String dbName1, String dbName2) async {
    final syncRepository = _getSyncRepository(dbName: dbName1);
    if (!await syncRepository.isConfigured(dbName: dbName1)) {
      try {
        await syncRepository.register(
            name: "Test 1",
            email: "test@test.com",
            newRegistration: true,
            password: "test",
            dbName: dbName1,
            secretKey: "",
            deviceInfo: "{\"name\":\"MACOS1\"}",
            language: "en");
      } on SyncException catch (ex) {
        if (ex.type == SyncExceptionType.registerExceptionAlreadyRegistered) {
          await syncRepository.register(
              name: "Test 1",
              email: "test@test.com",
              newRegistration: false,
              password: "test",
              dbName: dbName1,
              secretKey: "",
              deviceInfo: "{\"name\":\"MACOS1\"}",
              language: "en");
        }
      }
      // Register second client (secondaryDB)
      await configureSync(dbName: dbName2);
      if (!await syncRepository.isConfigured(dbName: dbName2)) {
        await syncRepository.register(
            name: "Test 1",
            email: "test@test.com",
            newRegistration: false,
            password: "test",
            dbName: dbName2,
            secretKey: "",
            deviceInfo: "{\"name\":\"MACOS2\"}",
            language: "en");
      }
      // Register gRPC client (grpcDB)
      final grpcRepository = _getSyncRepository(dbName: grpcName);
      if (!await grpcRepository.isConfigured(dbName: grpcName)) {
        await grpcRepository.register(
            name: "Test 1",
            email: "test@test.com",
            newRegistration: false,
            password: "test",
            dbName: grpcName,
            secretKey: "",
            deviceInfo: "{\"name\":\"GRPC1\"}",
            language: "en");
      }
    } else {
      debugPrint("Already configured...");
    }
  }

  /// Sync first the DB1 then DB2
  /// 2 pass might be required to a full sync
  /// (because if the changes are in db2, the first time they're invisible to db1)
  /*Future<void> syncAll(String dbName1, String dbName2) async {
    debugPrint("Sync...");
    final syncRepository = _getSyncRepository();
    await syncRepository.sync(dbName: dbName1);
    await syncRepository.sync(dbName: dbName2);
  }
  */

  Future<void> configureSync({required String dbName}) async {
    final syncRepository = _getSyncRepository(dbName: dbName);
    if (!await syncRepository.isConfigured(dbName: dbName)) {
      // Register second client
      await syncRepository.register(
          name: "Test 1",
          email: "test@test.com",
          newRegistration: false,
          password: "test",
          dbName: dbName,
          secretKey: "",
          deviceInfo: "{\"name\":\"MACOS2\"}",
          language: "en");
    }
  }

  Future<void> sync({required String dbName}) async {
    debugPrint("Sync...");
    final syncRepository = _getSyncRepository(dbName: dbName);
    await syncRepository.sync(dbName: dbName);
  }

  /// Resetta tutti i database cancellando dati e configurazione sync.
  /// Poi li reinizializza da capo (come all'avvio).
  Future<void> resetAll() async {
    debugPrint("Resetting all databases...");

    /// Resetta i database locali: chiudi, cancella file, riapri con onCreate
    final localDbs = [dbName1, dbName2];
    for (final name in localDbs) {
      await getSyncClient(dbName: name).closeDB(dbName: name);
      final docDir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(docDir.path, "$name.sqlite");
      final f = File(dbPath);
      if (await f.exists()) {
        await f.delete();
      }
    }

    /// Resetta il database gRPC: best-effort, ignora errori di rete
    try {
      await sqLiteWrapperSyncGRPC
          .execute("DROP TABLE IF EXISTS todos", dbName: grpcName);
    } catch (_) {}
    try {
      await sqLiteWrapperSyncGRPC.initSyncTables(dbName: grpcName);
    } catch (_) {}
    try {
      await sqLiteWrapperSyncGRPC.execute(
          """CREATE TABLE IF NOT EXISTS "todos" (
          "rowguid" varchar(36) PRIMARY KEY NOT NULL,
          "title" varchar(255) NOT NULL,
          "done" int default 0
        )""",
          dbName: grpcName);
    } catch (_) {}

    /// Reinizializza tutti e tre i database
    await initDB(dbName: dbName1, useGRPC: false);
    await initDB(dbName: dbName2);
    await initDB(dbName: grpcName, useGRPC: true);

    /// Dopo il reset i flag sono certamente a "non configurato"
    sqLiteWrapperSync.syncConfigured = SyncEnabled.disabled;
    sqLiteWrapperSyncGRPC.syncConfigured = SyncEnabled.disabled;

    // La garanzia dell'entry in databases per grpcDB è ora gestita da
    // initDB() stesso (per gRPC chiama sempre _ensureGrpcDbEntry()).

    /// Forza il rebuild delle liste nella UI
    resetNotifier.value++;

    debugPrint("All databases reset");
  }

  /// Simula una caduta e riconnessione della connessione gRPC.
  /// Utile per testare l'auto-recovery del watch stream.
  Future<void> reconnectGrpc() async {
    debugPrint("Reconnecting gRPC DB...");

    // 1. Crea un nuovo service manager (canale fresco). Il vecchio canale
    //    viene abbandonato simulando una caduta di connessione.
    sqLiteWrapperSyncGRPC.initServiceManager(host: 'localhost', port: 50052);

    // 2. Sostituisce il wrapper in databases con uno che usa il nuovo canale,
    //    così query()/execute() non trovano mai databases vuoto.
    sqLiteWrapperSyncGRPC.databases.add(
        name: grpcName,
        useGRPC: true,
        db: SqliteServiceClientWrapper(
            client: sqLiteWrapperSyncGRPC.client,
            dbName: grpcName));

    // 3. Tenta openDB lato server (best effort)
    try {
      await sqLiteWrapperSyncGRPC
          .openDB('grpcDB', dbName: grpcName, useGRPC: true);
    } catch (e) {
      debugPrint("gRPC openDB failed (server may be down): $e");
    }

    debugPrint("gRPC DB reconnected");
  }
}
