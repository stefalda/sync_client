import 'package:flutter/widgets.dart';
import 'package:sqlite_wrapper_sample/database_helper.dart';
import 'package:sqlite_wrapper_sample/models.dart';

class TodoItem extends StatelessWidget {
  final Todo todo;
  final String dbName;

  const TodoItem(this.todo, {required this.dbName, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => DatabaseHelper().toggleDone(todo, dbName: dbName),
      onLongPress: () => DatabaseHelper().deleteTodo(todo, dbName: dbName),
      child: Text(
        "${todo.title} ${(todo.rowguid)}",
        style: TextStyle(
            fontSize: 15,
            decoration: (todo.done == true
                ? TextDecoration.lineThrough
                : TextDecoration.none)),
      ),
    );
  }
}
