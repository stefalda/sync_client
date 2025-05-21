import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inject_x/inject_x.dart';
import 'package:sqlite_wrapper_sync_sample/database_service.dart';
import 'package:sqlite_wrapper_sync_sample/models.dart';
import 'package:sync_client/sync_client.dart';

// HOW TO TEST
// EMPTY the data folder
// perform "docker compose up" to start the sync server

const serverUrl = "http://localhost:8076";

const mainDBName = "database1";
const secondaryDBName = "database2";
late DatabaseService databaseService;
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  databaseService = InjectX.add(DatabaseService());
  await databaseService.initDB(test: true, dbName: mainDBName);
  await databaseService.initDB(test: true, dbName: secondaryDBName);

  String? rowGuid1;

  String? rowGuid2;

  final syncRepository = SyncRepository(
      serverUrl: serverUrl,
      sqliteWrapperSync: databaseService.sqLiteWrapperSync,
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
    rowGuid1 = await databaseService.addNewTodo("CLIENT 1 - PRIMO",
        dbName: mainDBName);
    await databaseService.addNewTodo("CLIENT 1 - SECONDO", dbName: mainDBName);
    rowGuid2 = await databaseService.addNewTodo("CLIENT 2 - PRIMO",
        dbName: secondaryDBName);
    await databaseService.addNewTodo("CLIENT 2 - SECONDO",
        dbName: secondaryDBName);

    // Perform a sync
    await syncRepository.sync(dbName: mainDBName);
    await syncRepository.sync(dbName: secondaryDBName);

    int count = await databaseService.sqLiteWrapperSync.query(
        "SELECT COUNT(*) FROM ${Todo.table}",
        singleResult: true,
        dbName: secondaryDBName);
    expect(count, 4);
  });

  test("DELETE A record and sync", () async {
    // DELETE A todo from second
    Todo? todo =
        await databaseService.getTodo(rowGuid1!, dbName: secondaryDBName);
    await databaseService.deleteTodo(todo!, dbName: secondaryDBName);

    // SYNC 2
    await syncRepository.sync(dbName: secondaryDBName);

    // SYNC 1
    await syncRepository.sync(dbName: mainDBName);

    // Expect 3 todo on 1
    int count = await databaseService.sqLiteWrapperSync.query(
        "SELECT COUNT(*) FROM ${Todo.table}",
        singleResult: true,
        dbName: mainDBName);
    expect(count, 3);
  });

  test("Modify a record and sync", () async {
    Todo? todo = await databaseService.getTodoByTitle("CLIENT 2 - PRIMO",
        dbName: mainDBName);
    todo!.title = "${todo.title} MODIFICATO SUL CLIENT 1";
    await databaseService.saveTodo(todo, dbName: mainDBName);
    // SYNC 1
    await syncRepository.sync(dbName: mainDBName);
    // SYNC 2
    await syncRepository.sync(dbName: secondaryDBName);

    Todo? todo2 =
        await databaseService.getTodo(rowGuid2!, dbName: secondaryDBName);

    expect(todo2!.title, "CLIENT 2 - PRIMO MODIFICATO SUL CLIENT 1");
  });

  test("Modify the same record on both client, only last should win", () async {
    Todo? todo =
        await databaseService.getTodo(rowGuid2!, dbName: secondaryDBName);
    todo!.title = "CLIENT 2 - PRIMO RIMODIFICATO SUL CLIENT 2";
    await databaseService.saveTodo(todo, dbName: secondaryDBName);

    todo = await databaseService.getTodo(rowGuid2!, dbName: mainDBName);
    todo!.title = "CLIENT 2 - PRIMO RIMODIFICATO SUL CLIENT 1";
    await databaseService.saveTodo(todo, dbName: mainDBName);

    // SYNC 1
    await syncRepository.sync(dbName: mainDBName);
    // SYNC 2
    await syncRepository.sync(dbName: secondaryDBName);
    // SYNC 1
    await syncRepository.sync(dbName: mainDBName);

    Todo? todo2 =
        await databaseService.getTodo(rowGuid2!, dbName: secondaryDBName);

    expect(todo2!.title, "CLIENT 2 - PRIMO RIMODIFICATO SUL CLIENT 1");

    todo2 = await databaseService.getTodo(rowGuid2!, dbName: mainDBName);

    expect(todo2!.title, "CLIENT 2 - PRIMO RIMODIFICATO SUL CLIENT 1");
  });

  test("DELETE A record on a client, modify it on another and sync", () async {
    // DELETE A todo from second
    Todo? todo = await databaseService.getTodoByTitle("CLIENT 2 - SECONDO",
        dbName: secondaryDBName);
    await databaseService.deleteTodo(todo!, dbName: secondaryDBName);

    // SYNC 2
    await syncRepository.sync(dbName: secondaryDBName);

    Todo? todoRimosso = await databaseService
        .getTodoByTitle("CLIENT 2 - SECONDO", dbName: secondaryDBName);

    expect(todoRimosso, isNull);

    todo = await databaseService.getTodoByTitle("CLIENT 2 - SECONDO",
        dbName: mainDBName);
    todo!.title = "CLIENT 2 - SECONDO - MODIFICATO DOPO CANCELLAZIONE";
    await databaseService.saveTodo(todo, dbName: mainDBName);

    // SYNC 1
    await syncRepository.sync(dbName: mainDBName);
    // SYNC 2
    await syncRepository.sync(dbName: secondaryDBName);

    Todo? todoRipristinato = await databaseService.getTodoByTitle(
        "CLIENT 2 - SECONDO - MODIFICATO DOPO CANCELLAZIONE",
        dbName: secondaryDBName);
    expect(todoRipristinato, isNotNull);
  });
}
