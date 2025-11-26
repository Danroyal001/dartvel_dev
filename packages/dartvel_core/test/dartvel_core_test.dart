import 'dart:convert';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('Res', () {
    test('json creates correct response', () async {
      final data = {'message': 'hello'};
      final res = Res.json(data);
      expect(res.status, 200);
      expect(res.headers.get('content-type'), contains('application/json'));
      
      final body = await res.body!.text();
      expect(jsonDecode(body), data);
    });

    test('text creates correct response', () async {
      final text = 'hello world';
      final res = Res.text(text);
      expect(res.status, 200);
      final body = await res.body!.text();
      expect(body, text);
    });

    test('notFound creates 404 response', () async {
      final res = Res.notFound();
      expect(res.status, 404);
      final body = await res.body!.text();
      expect(body, 'Not found');
    });

    test('notFound with message', () async {
      final res = Res.notFound('Custom error');
      expect(res.status, 404);
      final body = await res.body!.text();
      expect(body, 'Custom error');
    });
  });
}
