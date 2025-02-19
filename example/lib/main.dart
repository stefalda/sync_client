import 'package:flutter/material.dart';
import 'package:inject_x/inject_x.dart';
import 'package:sqlite_wrapper_sync_sample/database_service.dart';
import 'package:sqlite_wrapper_sync_sample/todo_list.dart';

const dbName1 = "primaryDB";
const dbName2 = "secondaryDB";
const grpcName = "grpcDB";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Init the DB
  final DatabaseService databaseService = InjectX.add(DatabaseService());
  await databaseService.initDB(dbName: dbName1, useGRPC: false);
  await databaseService.initDB(dbName: dbName2);
  await databaseService.initDB(dbName: grpcName, useGRPC: true);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SQLiteWrapper Sample',
      theme: ThemeData(
        primarySwatch: Colors.red,
      ),
      home: const HomePage(title: 'Todos'),
    );
  }
}

class HomePage extends StatelessWidget {
  final String title;

  const HomePage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final databaseService = inject<DatabaseService>();
    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(title),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TodoList(
                    dbName: dbName1,
                  ),
                  TodoList(dbName: dbName2),
                  TodoList(dbName: grpcName),
                ]),
          ),

          /// Bottom buttons to perform registration and sync
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton(
                  onPressed: () => databaseService.register(dbName1, dbName2),
                  child: const Text("Register")),
            ],
          )
        ],
      ),

      // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
