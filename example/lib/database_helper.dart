import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite_wrapper_sample/models.dart';
import 'package:sync_client/sync_client.dart';

/// Singleton class to operate with the database and the sync server
class DatabaseHelper {
  static final DatabaseHelper _singleton = DatabaseHelper._internal();
  factory DatabaseHelper() {
    return _singleton;
  }

  DatabaseHelper._internal();

  /// Define the tables structure
  SQLiteWrapperSync sqLiteWrapperSync = SQLiteWrapperSync(
      tableInfos: {"todos": TableInfo(keyField: 'rowguid', binaryFields: [])});

  /// Init the Database
  initDB({inMemory = false, test = false, required String dbName}) async {
    debugPrint("initDB $dbName");
    String dbPath = inMemoryDatabasePath;
    if (!inMemory) {
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
          // WEB VERSION
          dbPath = dbName;
        }
      }
    }
    final DatabaseInfo dbInfo = await sqLiteWrapperSync
        .openDB(dbPath, dbName: dbName, onCreate: () async {
      const String sql = """CREATE TABLE IF NOT EXISTS "todos" (
            "rowguid" varchar(36) PRIMARY KEY NOT NULL,
            "title" varchar(255) NOT NULL,
            "done" int default 0
          );
          """;
      await sqLiteWrapperSync.execute(sql, dbName: dbName);

      /// Initialize the Sync Tables
      await sqLiteWrapperSync.initSyncTables(dbName: dbName);
    });
    // Print where the database is stored
    debugPrint("Database path: ${dbInfo.path}");
  }

  /// Return a list of all todos
  Stream getTodos({required String dbName}) {
    return sqLiteWrapperSync.watch("SELECT * FROM todos order by rowguid",
        tables: [Todo.table], fromMap: Todo.fromMap, dbName: dbName);
  }

  /// Create a stream to update the todo count
  Stream<Map<String, dynamic>> getTodoCount({required String dbName}) {
    return Stream.castFrom(sqLiteWrapperSync.watch("""
        SELECT SUM(done) as done, sum(todo) as todo FROM (
        SELECT COUNT(*) as done,  0 as todo FROM todos where done = 1
        UNION
        SELECT 0 as done,  COUNT(*) as todo FROM todos where done = 0
        ) as todos 
      """, tables: [Todo.table], singleResult: true, dbName: dbName));
  }

  /// Add the new to-do Item
  Future<String> addNewTodo(String title, {required String dbName}) async {
    final rowguid = sqLiteWrapperSync.newUUID();
    await sqLiteWrapperSync.insert(
        Todo(rowguid: rowguid, title: title).toMap(), Todo.table,
        dbName: dbName);
    return rowguid;
  }

  /// Toggle a todo item - Done/To Do
  Future<void> toggleDone(Todo todo, {required String dbName}) async {
    todo.done = !todo.done;
    await sqLiteWrapperSync.update(todo.toMap(), "todos",
        keys: ["rowguid"], dbName: dbName);
  }

  /// Remove the todo item
  Future<void> deleteTodo(Todo todo, {required String dbName}) async {
    await sqLiteWrapperSync.delete(todo.toMap(), "todos",
        keys: ["rowguid"], dbName: dbName);
  }

  /// Save the new todo
  Future<void> saveTodo(Todo todo, {required String dbName}) async {
    await sqLiteWrapperSync.save(todo.toMap(), "todos",
        keys: ["rowguid"], dbName: dbName);
  }

  /// Get a specific todo by id
  Future<Todo?> getTodo(String rowguid, {required String dbName}) async {
    return await sqLiteWrapperSync.query(
        "SELECT * FROM ${Todo.table} WHERE rowguid=?",
        params: [rowguid],
        fromMap: Todo.fromMap,
        singleResult: true,
        dbName: dbName);
  }

  /// Get a specific todo by title
  Future<Todo?> getTodoByTitle(String title, {required String dbName}) async {
    return await sqLiteWrapperSync.query(
        "SELECT * FROM ${Todo.table} WHERE title=?",
        params: [title],
        fromMap: Todo.fromMap,
        singleResult: true,
        dbName: dbName);
  }

  /// Get the sync repository configuration (URL and REALM)
  dynamic _getSyncRepository() {
    return SyncRepository(
        serverUrl: "http://localhost:8076",
        sqliteWrapperSync: sqLiteWrapperSync,
        realm: "default");
  }

  /// Register dbName1 and then dbName2
  Future<void> register(String dbName1, String dbName2) async {
    final syncRepository = _getSyncRepository();
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
      if (!await syncRepository.isConfigured(dbName: dbName2)) {
        // Register second client
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
    } else {
      debugPrint("Already configured...");
    }
  }

  /// Sync first the DB1 then DB2
  /// 2 pass might be required to a full sync
  /// (because if the changes are in db2, the first time they're invisible to db1)
  Future<void> sync(String dbName1, String dbName2) async {
    debugPrint("Sync...");
    final syncRepository = _getSyncRepository();
    await syncRepository.sync(dbName: dbName1);
    await syncRepository.sync(dbName: dbName2);
  }
}
