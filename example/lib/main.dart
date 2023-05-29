import 'package:flutter/material.dart';
import 'package:sqlite_wrapper_sample/database_helper.dart';
import 'package:sqlite_wrapper_sample/todo_list.dart';

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
  const MyApp({Key? key}) : super(key: key);

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

  const HomePage({Key? key, required this.title}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(title),
      ),
      body: const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TodoList(
              dbName: dbName1,
            ),
            TodoList(dbName: dbName2),
          ]),
      floatingActionButton: IconButton(
        icon: const Icon(Icons.sync_alt_outlined),
        onPressed: () => DatabaseHelper().sync(dbName1, dbName2),
      ),

      // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
