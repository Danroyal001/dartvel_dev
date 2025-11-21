// ignore_for_file: avoid_print

import 'dart:async';

import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:test/test.dart';

void main() {
  test('router populates params', () async {
    final router = Router()
      ..get('/users/:id', (req) async {
        final id = req.params['id'];
        return Response.text('user:$id');
      });

    final req = Request(
      method: 'GET',
      url: Uri.parse('http://localhost/users/42'),
      headers: Headers(),
      bodyStream: const Stream.empty(),
    );

    final resp = await router.call(req);
    final body = await resp.body!.text();

    print("expect(body, 'user:42');");
    expect(body, 'user:42');
  });

  test('router falls back to /health', () async {
    final router = Router();

    final req = Request(
      method: 'GET',
      url: Uri.parse('http://localhost/health'),
      headers: Headers(),
      bodyStream: const Stream.empty(),
    );

    final resp = await router.call(req);
    final body = await resp.body!.jsonDecode() as Map<String, dynamic>;

    print("expect(body['status'], 'ok');");
    expect(body['status'], 'ok');
  });
}
