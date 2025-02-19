import 'package:flutter/widgets.dart';
import 'package:inject_x/inject_x.dart';
import 'package:sqlite_wrapper_sync_sample/database_service.dart';
import 'package:sqlite_wrapper_sync_sample/models.dart';

class TodoItem extends StatelessWidget {
  final Todo todo;
  final String dbName;

  const TodoItem(this.todo, {required this.dbName, super.key});

  @override
  Widget build(BuildContext context) {
    final databaseService = inject<DatabaseService>();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => databaseService.toggleDone(todo, dbName: dbName),
      onLongPress: () => databaseService.deleteTodo(todo, dbName: dbName),
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
