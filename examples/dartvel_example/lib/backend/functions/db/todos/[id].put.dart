import '../../../db/inmemory.dart';

Map<String, Object?> update(String id, String title) =>
    InMemoryDB().updateTodo(id, title) ??
    <String, Object?>{'error': 'not_found'};
