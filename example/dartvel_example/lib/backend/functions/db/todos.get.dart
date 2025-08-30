import '../../db/inmemory.dart';

List<Map<String, dynamic>> todos() => InMemoryDB().todos;

