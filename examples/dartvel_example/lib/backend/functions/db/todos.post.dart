import '../../db/inmemory.dart';

Map<String, Object?> addTodo(String title) => InMemoryDB().addTodo(title);
