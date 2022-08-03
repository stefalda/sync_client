import 'package:flutter/material.dart';
import 'package:sqlite_wrapper_sample/Database_Helper.dart';
import 'package:sqlite_wrapper_sample/instructions.dart';
import 'package:sqlite_wrapper_sample/models.dart';
import 'package:sqlite_wrapper_sample/todo_item.dart';

class TodoList extends StatelessWidget {
  const TodoList({required this.dbName, Key? key}) : super(key: key);
  final String dbName;

  void _addNewTodo() {
    DatabaseHelper().addNewTodo("NEW TODO", dbName: dbName);
    return;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 400,
      child: Column(
        children: [
          // To-do - COUNT
          StreamBuilder(
            stream: DatabaseHelper().getTodoCount(dbName: dbName),
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
            stream: DatabaseHelper().getTodos(dbName: dbName),
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
          const Instructions()
        ],
      ),
    );
  }
}
