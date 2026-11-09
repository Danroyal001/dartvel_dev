// @DVBackendFunction(rateLimit: '100/hour'): a function's own budget.
//
// The silent failures:
//  * two functions sharing one budget, so a burst on a cheap read locks
//    people out of checkout;
//  * two people behind one address sharing one budget once they have signed
//    in, so an office is limited as one caller;
//  * a refusal that does not say when to come back.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart' as dv;
import 'package:test/test.dart';

void main() {
  setUp(dv.dvResetMiddlewareRuntime);

  Future<dv.Response?> hit(
    String function, {
    String ip = '203.0.113.10',
    int max = 2,
    Duration window = const Duration(minutes: 1),
  }) =>
      dv.dvFunctionRateLimited(
        _request(ip),
        function: function,
        maxRequests: max,
        window: window,
      );

  test('allows the declared number, then answers 429 with Retry-After',
      () async {
    expect(await hit('POST /order'), isNull);
    expect(await hit('POST /order'), isNull);
    final dv.Response? refused = await hit('POST /order');
    expect(refused, isNotNull);
    expect(refused!.status, 429);
    expect(int.parse(refused.headers.get('retry-after')!), greaterThan(0));
    expect(await refused.body!.text(), 'Too many requests');
  });

  test('each function has its own budget', () async {
    await hit('POST /order');
    await hit('POST /order');
    expect(await hit('POST /order'), isNotNull);
    expect(await hit('GET /catalog'), isNull);
  });

  test('each caller has its own budget', () async {
    await hit('POST /order');
    await hit('POST /order');
    expect(await hit('POST /order', ip: '198.51.100.7'), isNull);
  });

  test('a signed-in caller is counted as themselves, not as their address',
      () async {
    dv.DVApiPrincipal principal(String subject) => dv.DVApiPrincipal(
          kind: dv.DVApiPrincipalKind.apiKey,
          subject: subject,
          tenant: 'acme',
          scopes: const <String>{},
          actions: const <String>{},
        );
    for (int i = 0; i < 2; i++) {
      expect(
          await dv.DVApiPrincipal.actingAs(
              principal('key-a'), () => hit('POST /order')),
          isNull);
    }
    expect(
        await dv.DVApiPrincipal.actingAs(
            principal('key-a'), () => hit('POST /order')),
        isNotNull);
    // Same address, another caller.
    expect(
        await dv.DVApiPrincipal.actingAs(
            principal('key-b'), () => hit('POST /order')),
        isNull);
  });

  test('a shared store keeps each function in its own counter', () async {
    dv.DVMiddlewareSettings.rateLimitStore = dv.DVMemoryCacheAdapter();
    await hit('POST /order');
    await hit('POST /order');
    expect(await hit('POST /order'), isNotNull);
    expect(await hit('GET /catalog'), isNull);
  });

  group('dvParseRateLimit', () {
    test('reads <count>/<unit>', () {
      expect(dv.dvParseRateLimit('100/hour'),
          (maxRequests: 100, window: const Duration(hours: 1)));
      expect(dv.dvParseRateLimit('5/second'),
          (maxRequests: 5, window: const Duration(seconds: 1)));
      expect(dv.dvParseRateLimit('30/minute'),
          (maxRequests: 30, window: const Duration(minutes: 1)));
      expect(dv.dvParseRateLimit('1000/day'),
          (maxRequests: 1000, window: const Duration(days: 1)));
    });

    test('refuses anything else', () {
      for (final String value in <String>[
        '',
        '100',
        '100 per hour',
        '0/hour',
        '-1/hour',
        '100/fortnight',
        '1.5/hour',
      ]) {
        expect(dv.dvParseRateLimit(value), isNull, reason: value);
      }
    });
  });
}

dv.Request _request(String ip) => dv.Request(
      method: 'POST',
      url: Uri.parse('https://example.test/api/order'),
      headers: dv.Headers(<String, String>{}),
      peerAddress: dv.DVPeerAddress.parse(ip),
      bodyStream: Stream<List<int>>.value(utf8.encode('')),
    );
