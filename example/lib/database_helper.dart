import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite_wrapper_sample/models.dart';
import 'package:sync_client/sync_client.dart';

const mainDBName = "todoDatabase";
const secondaryDBName = "todoDatabase2";

class DatabaseHelper {
  static final DatabaseHelper _singleton = DatabaseHelper._internal();
  factory DatabaseHelper() {
    return _singleton;
  }

  DatabaseHelper._internal();

  SQLiteWrapperSync sqLiteWrapperSync = SQLiteWrapperSync(
      tableInfos: {"todos": TableInfo(keyField: 'rowguid', binaryFields: [])});

  initDB({inMemory = false, test = false, dbName = mainDBName}) async {
    String dbPath = inMemoryDatabasePath;
    if (!inMemory) {
      if (test) {
        dbPath = "$dbName.sqlite";
        final f = File(dbPath);
        if (f.existsSync()) {
          f.deleteSync();
        }
      } else {
        final docDir = await getApplicationDocumentsDirectory();
        if (!await docDir.exists()) {
          await docDir.create(recursive: true);
        }
        dbPath = p.join(docDir.path, "$dbName.sqlite");
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
  Stream getTodos({dbName = mainDBName}) {
    return sqLiteWrapperSync.watch("SELECT * FROM todos order by rowguid",
        tables: [Todo.table], fromMap: Todo.fromMap, dbName: dbName);
  }

  Stream<Map<String, dynamic>> getTodoCount({dbName = mainDBName}) {
    return Stream.castFrom(sqLiteWrapperSync.watch("""
        SELECT SUM(done) as done, sum(todo) as todo FROM (
        SELECT COUNT(*) as done,  0 as todo FROM todos where done = 1
        UNION
        SELECT 0 as done,  COUNT(*) as todo FROM todos where done = 0
        ) as todos 
      """, tables: [Todo.table], singleResult: true, dbName: dbName));
  }

  /// Add the new to-do Item
  Future<String> addNewTodo(String title, {dbName = mainDBName}) async {
    final rowguid = sqLiteWrapperSync.newUUID();
    await sqLiteWrapperSync.insert(
        Todo(rowguid: rowguid, title: title).toMap(), Todo.table,
        dbName: dbName);
    return rowguid;
  }

  Future<void> toggleDone(Todo todo, {dbName = mainDBName}) async {
    todo.done = !todo.done;
    await sqLiteWrapperSync.update(todo.toMap(), "todos",
        keys: ["rowguid"], dbName: dbName);
  }

  Future<void> deleteTodo(Todo todo, {dbName = mainDBName}) async {
    await sqLiteWrapperSync.delete(todo.toMap(), "todos",
        keys: ["rowguid"], dbName: dbName);
  }

  Future<void> saveTodo(Todo todo, {dbName = mainDBName}) async {
    await sqLiteWrapperSync.save(todo.toMap(), "todos",
        keys: ["rowguid"], dbName: dbName);
  }

  Future<Todo?> getTodo(String rowguid, {dbName = mainDBName}) async {
    return await sqLiteWrapperSync.query(
        "SELECT * FROM ${Todo.table} WHERE rowguid=?",
        params: [rowguid],
        fromMap: Todo.fromMap,
        singleResult: true,
        dbName: dbName);
  }

  Future<Todo?> getTodoByTitle(String title, {dbName = mainDBName}) async {
    return await sqLiteWrapperSync.query(
        "SELECT * FROM ${Todo.table} WHERE title=?",
        params: [title],
        fromMap: Todo.fromMap,
        singleResult: true,
        dbName: dbName);
  }

  /// Sync dbName1 and then dbName2
  Future<void> sync(String dbName1, String dbName2) async {
    final syncRepository = SyncRepository(
        serverUrl: "192.168.4.3:8760",
        sqliteWrapperSync: sqLiteWrapperSync,
        realm: "TODOS");
    if (!await syncRepository.isConfigured(dbName: dbName1)) {
      await syncRepository.register(
          email: "test@test.com",
          newRegistration: true,
          password: "test",
          dbName: dbName1,
          deviceInfo: "MACOS");
      await syncRepository.register(
          newRegistration: false,
          email: "test@test.com",
          password: "test",
          dbName: dbName2,
          deviceInfo: "MACOS");
    }
    await syncRepository.sync(dbName: dbName1);
    await syncRepository.sync(dbName: dbName2);
  }

/*
  /// Return the tableInfos of the current DB
  Map<String, TableInfo> _getTableInfos() {
    final Map<String, TableInfo> tableInfos = {
      "todos":
          TableInfo(keyField: 'rowguid', binaryFields: [], externalKeys: [])
    };
    return tableInfos;
    final Map<String, TableInfo> tableInfos = {
      "books": TableInfo(keyField: "bookid", binaryFields: [], externalKeys: [
        ExternalKey(
            fieldName: "publisherid",
            externalFieldTable: "publishers",
            externalFieldKey: "publisherid"),
        ExternalKey(
            fieldName: "authorid",
            externalFieldTable: "authors",
            externalFieldKey: "authorid"),
        ExternalKey(
            fieldName: "categoryid",
            externalFieldTable: "categories",
            externalFieldKey: "categoryid"),
        ExternalKey(
            fieldName: "categoryid2",
            externalFieldTable: "categories",
            externalFieldKey: "categoryid"),
        ExternalKey(
            fieldName: "categoryid3",
            externalFieldTable: "categories",
            externalFieldKey: "categoryid"),
        ExternalKey(
            fieldName: "formatid",
            externalFieldTable: "formats",
            externalFieldKey: "formatid"),
        ExternalKey(
            fieldName: "origin",
            externalFieldTable: "origins",
            externalFieldKey: "originid"),
        ExternalKey(
            fieldName: "locationid",
            externalFieldTable: "locations",
            externalFieldKey: "locationid")
      ]),
      "authors": TableInfo(
          keyField: "authorid", binaryFields: ["photo"], externalKeys: []),
      "publishers": TableInfo(
          keyField: "publisherid", binaryFields: [], externalKeys: []),
      "covers": TableInfo(keyField: "coverid", binaryFields: [
        "cover"
      ], externalKeys: [
        ExternalKey(
            fieldName: "bookid",
            externalFieldTable: "books",
            externalFieldKey: "bookid")
      ], booleanFields: [
        "customCover"
      ], aliasesFields: {
        "cover": "big"
      }),
      "categories":
          TableInfo(keyField: "categoryid", binaryFields: [], externalKeys: [])
    };
    return tableInfos;
    
  }*/
}
