import 'dart:convert';

import 'package:dartvel_core/src/middleware/middleware.dart';
import 'package:dartvel_shelf/dartvel_shelf.dart' as dv;
import 'package:test/test.dart';

void main() {
  group('CommonMiddleware.rateLimit', () {
    test('tracks forwarded clients independently', () async {
      final middleware = CommonMiddleware.rateLimit(
        maxRequests: 1,
        window: const Duration(minutes: 1),
      );

      final first = MiddlewareContext();
      await middleware(_request(ip: '203.0.113.10'), first);
      expect(first.shouldContinue, isTrue);

      final second = MiddlewareContext();
      await middleware(_request(ip: '203.0.113.10'), second);
      expect(second.shouldContinue, isFalse);
      expect(second.data['rateLimitError'], 'Too many requests');

      final third = MiddlewareContext();
      await middleware(_request(ip: '203.0.113.11'), third);
      expect(third.shouldContinue, isTrue);
    });

    test('uses typed map client identifiers', () async {
      final middleware = CommonMiddleware.rateLimit(
        maxRequests: 1,
        window: const Duration(minutes: 1),
      );

      final first = MiddlewareContext();
      await middleware(<String, Object?>{'clientId': 'client-a'}, first);
      expect(first.shouldContinue, isTrue);

      final second = MiddlewareContext();
      await middleware(<String, Object?>{'clientId': 'client-b'}, second);
      expect(second.shouldContinue, isTrue);

      final third = MiddlewareContext();
      await middleware(<String, Object?>{'clientId': 'client-a'}, third);
      expect(third.shouldContinue, isFalse);
    });
  });

  group('CommonMiddleware.bodyParser', () {
    test('parses JSON request bodies', () async {
      final middleware = CommonMiddleware.bodyParser();
      final context = MiddlewareContext();

      await middleware(
        _request(
          contentType: 'application/json',
          body: jsonEncode(<String, Object?>{'name': 'Ada', 'age': 36}),
        ),
        context,
      );

      expect(
        context.data['parsedBody'],
        <String, Object?>{'name': 'Ada', 'age': 36},
      );
    });

    test('parses urlencoded request bodies', () async {
      final middleware = CommonMiddleware.bodyParser();
      final context = MiddlewareContext();

      await middleware(
        _request(
          contentType: 'application/x-www-form-urlencoded',
          body: 'name=Ada&role=admin',
        ),
        context,
      );

      expect(
        context.data['parsedBody'],
        <String, String>{'name': 'Ada', 'role': 'admin'},
      );
    });
  });
}

dv.Request _request({
  String ip = '203.0.113.10',
  String contentType = 'text/plain',
  String body = '',
}) {
  return dv.Request(
    method: 'POST',
    url: Uri.parse('https://example.test/forms'),
    headers: dv.Headers(<String, String>{
      'x-forwarded-for': ip,
      'content-type': contentType,
    }),
    bodyStream: Stream<List<int>>.value(utf8.encode(body)),
  );
}
