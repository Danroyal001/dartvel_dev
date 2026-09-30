import 'dart:convert';

import 'package:dartvel_core/dartvel.dart' as dv;
import 'package:dartvel_core/src/middleware/middleware.dart';
import 'package:test/test.dart';

void main() {
  group('CommonMiddleware.rateLimit', () {
    test('a caller that has gone quiet is forgotten', () async {
      // Every source that ever sent a request kept a list in memory for the
      // life of the process. An attacker who rotates addresses grows that map
      // without bound, which is a denial of service by the limiter itself.
      DateTime now = DateTime.utc(2026, 9, 30, 12);
      final middleware = CommonMiddleware.rateLimit(
        maxRequests: 5,
        window: const Duration(minutes: 1),
        clock: () => now,
      );
      for (int i = 0; i < 500; i++) {
        await middleware(_request(ip: '198.51.100.${i % 250}'), MiddlewareContext());
        await middleware(_request(ip: '203.0.113.${i % 250}'), MiddlewareContext());
      }
      expect(dvRateLimitTrackedCallers(middleware), 500);

      now = now.add(const Duration(minutes: 3));
      await middleware(_request(ip: '192.0.2.1'), MiddlewareContext());
      expect(dvRateLimitTrackedCallers(middleware), 1);
    });

    test('a refusal says when to try again', () async {
      DateTime now = DateTime.utc(2026, 9, 30, 12);
      final middleware = CommonMiddleware.rateLimit(
        maxRequests: 1,
        window: const Duration(minutes: 1),
        clock: () => now,
      );
      await middleware(_request(ip: '203.0.113.20'), MiddlewareContext());
      now = now.add(const Duration(seconds: 20));
      final refused = MiddlewareContext();
      await middleware(_request(ip: '203.0.113.20'), refused);

      expect(refused.shouldContinue, isFalse);
      // The first request leaves the window 40 seconds from now.
      expect(refused.data['retryAfter'], 40);
    });

    test('tracks clients by their connection, independently', () async {
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

    test('counts an IPv6 client by its /64, not the address it chose',
        () async {
      final middleware = CommonMiddleware.rateLimit(
        maxRequests: 1,
        window: const Duration(minutes: 1),
      );

      final first = MiddlewareContext();
      await middleware(_request(ip: '[2001:db8:7:7::1]:4000'), first);
      expect(first.shouldContinue, isTrue);

      final rotated = MiddlewareContext();
      await middleware(_request(ip: '[2001:db8:7:7::2]:4001'), rotated);
      expect(rotated.shouldContinue, isFalse,
          reason: 'a new address in the same /64 is the same client');

      final elsewhere = MiddlewareContext();
      await middleware(_request(ip: '[2001:db8:7:8::1]:4002'), elsewhere);
      expect(elsewhere.shouldContinue, isTrue);
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
    headers: dv.Headers(<String, String>{'content-type': contentType}),
    peerAddress: dv.DVPeerAddress.parse(ip),
    bodyStream: Stream<List<int>>.value(utf8.encode(body)),
  );
}
