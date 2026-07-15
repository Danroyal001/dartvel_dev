// Simple in-memory store for example purposes only.
class InMemoryDB {
  static final InMemoryDB _i = InMemoryDB._();
  InMemoryDB._();
  factory InMemoryDB() => _i;

  int _todoId = 0;
  final List<Map<String, dynamic>> todos = <Map<String, dynamic>>[];

  Map<String, dynamic> addTodo(String title) {
    final item = <String, dynamic>{
      'id': (++_todoId).toString(),
      'title': title
    };
    todos.add(item);
    return item;
  }

  Map<String, dynamic>? updateTodo(String id, String title) {
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
