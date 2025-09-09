import 'package:shelf/shelf.dart';
import 'dart:async';
import '../.dart_tool/dartvel_backend_routes.g.dart' as gen;

Future<void> main() async {
  final handler = gen.buildBackendRouter();
  Future<void> probe(String method, String path) async {
    final req = Request(method, Uri.parse('http://localhost:3000$path'));
    try {
      final res = await handler(req);
      final body = await res.readAsString();
      print('TEST $method $path -> ${res.statusCode} $body');
    } catch (e, st) {
      print('ERROR $method $path: $e');
      print(st);
    }
  }

  await probe('POST', '/api/sum?a=2&b=3');
  await probe('POST', '/api/echo?msg=Hello');
  await probe('PUT', '/api/user/u1?name=Alice');
  await probe('DELETE', '/api/user/u1');
  await probe('POST', '/api/blog/last_viewed_date_2025-08-29');
}

