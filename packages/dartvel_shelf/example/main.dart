// A small JSON API: path parameters, query strings, request bodies, a route
// that accepts a larger body than the rest, and errors.
//
//   dart run example/main.dart
//
//   curl http://127.0.0.1:8080/todos
//   curl -X POST -H 'content-type: application/json' \
//        -d '{"title":"write docs"}' http://127.0.0.1:8080/todos
//   curl http://127.0.0.1:8080/todos/1
//   curl 'http://127.0.0.1:8080/search?tag=a&tag=b'
//   curl http://127.0.0.1:8080/health
import 'dart:io';

import 'package:dartvel_shelf/dartvel_shelf.dart';

final _todos = <int, Map<String, Object?>>{};
var _nextId = 1;

Future<void> main() async {
  final router = Router()
    ..get('/todos', (req) async => Response.json(_todos.values.toList()))
    ..get('/todos/:id', (req) async {
      final id = int.tryParse(req.params['id']!);
      final todo = id == null ? null : _todos[id];
      if (todo == null) {
        return Response.json({'error': 'no such todo'}, status: 404);
      }
      return Response.json(todo);
    })
    ..post('/todos', (req) async {
      if (req.headers.get('content-type')?.startsWith('application/json') !=
          true) {
        return Response.json({'error': 'send JSON'}, status: 415);
      }
      // jsonDecode() hands back the raw text when the body is not valid JSON
      // rather than throwing, so check the shape before trusting it.
      final body = await req.body.jsonDecode();
      if (body is! Map || body['title'] is! String) {
        return Response.json({
          'error': 'expected {"title": "..."}',
        }, status: 400);
      }
      final todo = {'id': _nextId++, 'title': body['title'], 'done': false};
      _todos[todo['id'] as int] = todo;
      return Response.json(
        todo,
        status: 201,
        headers: Headers()..set('location', '/todos/${todo['id']}'),
      );
    })
    ..delete('/todos/:id', (req) async {
      final removed = _todos.remove(int.tryParse(req.params['id']!));
      return removed == null
          ? Response.json({'error': 'no such todo'}, status: 404)
          : Response(204);
    })
    ..get('/search', (req) async {
      // queryParameters keeps the last value of a repeated key;
      // queryParametersAll keeps every one.
      final tags = req.url.queryParametersAll['tag'] ?? const <String>[];
      return Response.json({'tags': tags});
    })
    // Every other route reads at most maxBodyBytes (1 MiB by default); this
    // one reads up to 8 MiB.
    ..post('/uploads', (req) async {
      final bytes = await req.body.bytes();
      return Response.json({'received': bytes.length});
    }, maxBodyBytes: 8 * 1024 * 1024);

  final server = await serve(
    router.call,
    host: '127.0.0.1',
    port: 8080,
    // Tells the native side about /uploads' larger limit. Without this the
    // server's own limit applies to every route.
    routeBodyLimits: router.bodyLimits,
    requestTimeout: const Duration(seconds: 30),
  );
  stdout.writeln('Listening on http://${server.host}:${server.port}');

  await ProcessSignal.sigint.watch().first;
  await server.stop();
  exit(0);
}
