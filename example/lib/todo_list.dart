import 'package:flutter/material.dart';
import 'package:inject_x/inject_x.dart';
import 'package:sqlite_wrapper_sync_sample/database_service.dart';
import 'package:sqlite_wrapper_sync_sample/instructions.dart';
import 'package:sqlite_wrapper_sync_sample/models.dart';
import 'package:sqlite_wrapper_sync_sample/todo_item.dart';

class TodoList extends StatelessWidget {
  TodoList({required this.dbName, super.key});
  final String dbName;
  final databaseService = inject<DatabaseService>();

  void _addNewTodo() {
    databaseService.addNewTodo("NEW TODO", dbName: dbName);
    return;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 400,
      child: Column(
        children: [
          Text(
            dbName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          // To-do - COUNT
          StreamBuilder(
            stream: databaseService.getTodoCount(dbName: dbName),
            initialData: const [],
            builder: (BuildContext context, AsyncSnapshot snapshot) {
              return Container(
                child: snapshot.hasData
                    ? Text("Count: ${snapshot.data.toString()}")
                    : Container(),
              );
            },
          ),
          // Todos
          StreamBuilder(
            stream: databaseService.getTodos(dbName: dbName),
            initialData: const [],
            builder: (BuildContext context, AsyncSnapshot snapshot) {
              if (!snapshot.hasData) {
                return const CircularProgressIndicator();
              }
              final List<Todo> todos = List<Todo>.from(snapshot.data);
              return Expanded(
                  //child: SingleChildScrollView(
                  child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: ListView.separated(
                  separatorBuilder: (BuildContext context, int index) =>
                      const Divider(),
                  itemCount: todos.length,
                  itemBuilder: (BuildContext context, int index) {
                    final Todo todo = todos[index];
                    return TodoItem(
                      todo,
                      dbName: dbName,
                    );
                  },
                  //  ),
                ),
              ));
            },
          ),
          TextButton(
              onPressed: () => _addNewTodo(),
              child: const Text("Add new Todo")),
          TextButton(
              onPressed: () => databaseService.configureSync(dbName: dbName),
              child: const Text("Configure")),
          TextButton(
              onPressed: () => databaseService.sync(dbName: dbName),
              child: const Text("Sync")),
          const Instructions()
        ],
      ),
    );
  }
}
