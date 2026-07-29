import '../../db/inmemory.dart';

List<Map<String, Object?>> todos() => InMemoryDB().todos;
