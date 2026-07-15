import '../../../db/inmemory.dart';

String remove(String id) => InMemoryDB().removeTodo(id) ? 'ok' : 'not_found';
