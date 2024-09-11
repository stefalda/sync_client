import 'package:flutter/material.dart';
import 'package:sqlite_wrapper_sync_sample/database_helper.dart';
import 'package:sqlite_wrapper_sync_sample/todo_list.dart';

const dbName1 = "primaryDB";
const dbName2 = "secondaryDB";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Init the DB
  await DatabaseHelper().initDB(dbName: dbName1);
  await DatabaseHelper().initDB(dbName: dbName2);
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
          const Expanded(
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TodoList(
                    dbName: dbName1,
                  ),
                  TodoList(dbName: dbName2),
                ]),
          ),

          /// Bottom buttons to perform registration and sync
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton(
                  onPressed: () => DatabaseHelper().register(dbName1, dbName2),
                  child: const Text("Register")),
              TextButton(
                  onPressed: () => DatabaseHelper().sync(dbName1, dbName2),
                  child: const Text("Sync"))
            ],
          )
        ],
      ),

      // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
