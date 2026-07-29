// Simple in-memory store for example purposes only.
class InMemoryDB {
  static final InMemoryDB _i = InMemoryDB._();
  InMemoryDB._();
  factory InMemoryDB() => _i;

  int _todoId = 0;
  final List<Map<String, Object?>> todos = <Map<String, Object?>>[];

  Map<String, Object?> addTodo(String title) {
    final item = <String, Object?>{
      'id': (++_todoId).toString(),
      'title': title
    };
    todos.add(item);
    return item;
  }

  Map<String, Object?>? updateTodo(String id, String title) {
    for (final t in todos) {
      if (t['id'] == id) {
        t['title'] = title;
        return t;
      }
    }
    return null;
  }

  bool removeTodo(String id) {
    final before = todos.length;
    todos.removeWhere((t) => t['id'] == id);
    return todos.length < before;
  }
}
