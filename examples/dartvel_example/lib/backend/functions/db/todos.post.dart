import '../../db/inmemory.dart';

Map<String, dynamic> addTodo(String title) => InMemoryDB().addTodo(title);
