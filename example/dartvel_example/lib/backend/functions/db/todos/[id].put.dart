import '../../../db/inmemory.dart';

Map<String, dynamic> update(String id, String title) =>
    InMemoryDB().updateTodo(id, title) ?? {'error': 'not_found'};

