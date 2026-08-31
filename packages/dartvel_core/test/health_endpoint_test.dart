// The endpoints themselves, not just the registries behind them.
//
// GET /health returned a hardcoded {'status':'ok'} and there was no /metrics
// at all, though the framework's own site said there was.
import 'dart:async';
import 'dart:convert';

import 'package:dartvel_core/src/http/router.dart';
import 'package:dartvel_core/src/http/wintercg.dart';
import 'package:dartvel_core/src/observability/health.dart';
import 'package:dartvel_core/src/observability/observability.dart';
import 'package:test/test.dart';

Future<Response> get(Router router, String path) => router(Request(
      method: 'GET',
      url: Uri.parse('http://localhost$path'),
      headers: Headers(),
      bodyStream: const Stream<List<int>>.empty(),
    ));

Future<String> read(Response response) async {
  final List<int> bytes = <int>[];
  await for (final List<int> chunk in response.body!.stream) {
    bytes.addAll(chunk);
  }
  return utf8.decode(bytes);
}

void main() {
  setUp(() {
    DVObservability.health.clear();
    DVObservability.metrics.reset();
  });

  test('health answers with real status, not a literal', () async {
    final Router router = Router();
    final Response response = await get(router, '/health');
    final Map<String, Object?> body =
        jsonDecode(await read(response)) as Map<String, Object?>;

    expect(response.status, 200);
    expect(body['status'], 'up');
    // The two things that distinguish a report from a constant.
    expect(body.containsKey('uptime'), isTrue);
  });

  test('a failing check makes it 503', () async {
    DVObservability.health
        .register('database', () async => DVHealthResult.down('no route'));

    final Router router = Router();
    final Response response = await get(router, '/health');
    final Map<String, Object?> body =
        jsonDecode(await read(response)) as Map<String, Object?>;

    // The whole point: a load balancer has to be able to take this instance
    // out of rotation, and it does that on the status code.
    expect(response.status, 503);
    expect(body['status'], 'down');
    expect(
      ((body['checks']! as Map<String, Object?>)['database']!
          as Map<String, Object?>)['detail'],
      'no route',
    );
  });

  test('a degraded check still serves', () async {
    DVObservability.health
        .register('cache', () async => DVHealthResult.degraded('slow'));

    final Response response = await get(Router(), '/health');
    expect(response.status, 200);
  });

  test('metrics are served in the exposition format', () async {
    DVObservability.metrics.counter('requests_total').increment(3);

    final Response response = await get(Router(), '/metrics');
    final String body = await read(response);

    expect(response.status, 200);
    // The content type is not decoration: a scraper sent application/json
    // refuses the payload.
    expect(response.headers.get('content-type'),
        contains('text/plain; version=0.0.4'));
    expect(body, contains('dartvel_requests_total 3'));
  });

  test('metrics include process uptime', () async {
    final String body = await read(await get(Router(), '/metrics'));
    expect(body, contains('dartvel_uptime_seconds'));
  });

  test('an application route still wins over the built-ins', () async {
    // The built-ins are a fallback. An application that wants its own /health
    // -- a deeper check, a different shape -- must be able to have one.
    final Router router = Router()
      ..get('/health', (Request req) async => Response.text('mine'));

    expect(await read(await get(router, '/health')), 'mine');
  });
}
