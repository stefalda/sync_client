import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite_wrapper_sync_sample/database_helper.dart';
import 'package:sqlite_wrapper_sync_sample/models.dart';
import 'package:sync_client/sync_client.dart';

const serverUrl = "http://localhost:3000";

const mainDBName = "database1";
const secondaryDBName = "database2";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper().initDB(test: true, dbName: mainDBName);
  await DatabaseHelper().initDB(test: true, dbName: secondaryDBName);

  String? rowGuid1;

  String? rowGuid2;

  final syncRepository = SyncRepository(
      serverUrl: serverUrl,
      sqliteWrapperSync: DatabaseHelper().sqLiteWrapperSync,
      realm: "TODO_TEST");

  test("Register a new user", () async {
    await syncRepository.register(
        name: "Test 1",
        email: "test@test.com",
        password: "test",
        deviceInfo: "{\"name\":\"TEST OS 1\"}",
        dbName: mainDBName,
        secretKey: "",
        newRegistration: true,
        language: "en");
    await syncRepository.register(
        name: "Test 2",
        email: "test@test.com",
        password: "test",
        deviceInfo: "{\"name\":\"TEST OS 2\"}",
        dbName: secondaryDBName,
        secretKey: "",
        newRegistration: false,
        language: "en");
  });

  test("Perform a sync", () async {
    await syncRepository.sync(dbName: mainDBName);
    await syncRepository.sync(dbName: secondaryDBName);
    // Insert some data
    rowGuid1 = await DatabaseHelper()
        .addNewTodo("CLIENT 1 - PRIMO", dbName: mainDBName);
    await DatabaseHelper().addNewTodo("CLIENT 1 - SECONDO", dbName: mainDBName);
    rowGuid2 = await DatabaseHelper()
        .addNewTodo("CLIENT 2 - PRIMO", dbName: secondaryDBName);
    await DatabaseHelper()
        .addNewTodo("CLIENT 2 - SECONDO", dbName: secondaryDBName);

    // Perform a sync
    await syncRepository.sync(dbName: mainDBName);
    await syncRepository.sync(dbName: secondaryDBName);

    int count = await DatabaseHelper().sqLiteWrapperSync.query(
        "SELECT COUNT(*) FROM ${Todo.table}",
        singleResult: true,
        dbName: secondaryDBName);
    expect(count, 4);
  });

  test("DELETE A record and sync", () async {
    // DELETE A todo from second
    Todo? todo =
        await DatabaseHelper().getTodo(rowGuid1!, dbName: secondaryDBName);
    await DatabaseHelper().deleteTodo(todo!, dbName: secondaryDBName);

    // SYNC 2
    await syncRepository.sync(dbName: secondaryDBName);

    // SYNC 1
    await syncRepository.sync(dbName: mainDBName);

    // Expect 3 todo on 1
    int count = await DatabaseHelper().sqLiteWrapperSync.query(
        "SELECT COUNT(*) FROM ${Todo.table}",
        singleResult: true,
        dbName: mainDBName);
    expect(count, 3);
  });

  test("Modify a record and sync", () async {
    Todo? todo = await DatabaseHelper()
        .getTodoByTitle("CLIENT 2 - PRIMO", dbName: mainDBName);
    todo!.title = "${todo.title} MODIFICATO SUL CLIENT 1";
    await DatabaseHelper().saveTodo(todo, dbName: mainDBName);
    // SYNC 1
    await syncRepository.sync(dbName: mainDBName);
    // SYNC 2
    await syncRepository.sync(dbName: secondaryDBName);

    Todo? todo2 =
        await DatabaseHelper().getTodo(rowGuid2!, dbName: secondaryDBName);

    expect(todo2!.title, "CLIENT 2 - PRIMO MODIFICATO SUL CLIENT 1");
  });

  test("Modify the same record on both client, only last should win", () async {
    Todo? todo =
        await DatabaseHelper().getTodo(rowGuid2!, dbName: secondaryDBName);
    todo!.title = "CLIENT 2 - PRIMO RIMODIFICATO SUL CLIENT 2";
    await DatabaseHelper().saveTodo(todo, dbName: secondaryDBName);

    todo = await DatabaseHelper().getTodo(rowGuid2!, dbName: mainDBName);
    todo!.title = "CLIENT 2 - PRIMO RIMODIFICATO SUL CLIENT 1";
    await DatabaseHelper().saveTodo(todo, dbName: mainDBName);

    // SYNC 1
    await syncRepository.sync(dbName: mainDBName);
    // SYNC 2
    await syncRepository.sync(dbName: secondaryDBName);
    // SYNC 1
    await syncRepository.sync(dbName: mainDBName);

    Todo? todo2 =
        await DatabaseHelper().getTodo(rowGuid2!, dbName: secondaryDBName);

    expect(todo2!.title, "CLIENT 2 - PRIMO RIMODIFICATO SUL CLIENT 1");

    todo2 = await DatabaseHelper().getTodo(rowGuid2!, dbName: mainDBName);

    expect(todo2!.title, "CLIENT 2 - PRIMO RIMODIFICATO SUL CLIENT 1");
  });

  test("DELETE A record on a client, modify it on another and sync", () async {
    // DELETE A todo from second
    Todo? todo = await DatabaseHelper()
        .getTodoByTitle("CLIENT 2 - SECONDO", dbName: secondaryDBName);
    await DatabaseHelper().deleteTodo(todo!, dbName: secondaryDBName);

    // SYNC 2
    await syncRepository.sync(dbName: secondaryDBName);

    Todo? todoRimosso = await DatabaseHelper()
        .getTodoByTitle("CLIENT 2 - SECONDO", dbName: secondaryDBName);

    expect(todoRimosso, isNull);

    todo = await DatabaseHelper()
        .getTodoByTitle("CLIENT 2 - SECONDO", dbName: mainDBName);
    todo!.title = "CLIENT 2 - SECONDO - MODIFICATO DOPO CANCELLAZIONE";
    await DatabaseHelper().saveTodo(todo, dbName: mainDBName);

    // SYNC 1
    await syncRepository.sync(dbName: mainDBName);
    // SYNC 2
    await syncRepository.sync(dbName: secondaryDBName);

    Todo? todoRipristinato = await DatabaseHelper().getTodoByTitle(
        "CLIENT 2 - SECONDO - MODIFICATO DOPO CANCELLAZIONE",
        dbName: secondaryDBName);
    expect(todoRipristinato, isNotNull);
  });
}
