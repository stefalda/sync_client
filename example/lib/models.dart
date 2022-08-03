import 'dart:convert';

class Todo {
  static String table = "todos";

  String rowguid;
  String title;
  bool done = false;

  Todo({required this.rowguid, required this.title});

  Map<String, dynamic> toMap() {
    return {
      'rowguid': rowguid,
      'title': title,
      'done': done,
    };
  }

  factory Todo.fromMap(Map<String, dynamic> map) {
    return Todo(rowguid: map['rowguid'], title: map['title'] ?? '')
      ..done = (map['done'] ?? 0) == 1 ? true : false;
  }

  String toJson() => json.encode(toMap());

  factory Todo.fromJson(String source) => Todo.fromMap(json.decode(source));
}
