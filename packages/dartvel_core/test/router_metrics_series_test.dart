// The router keeps each method and status's request counter and duration
// histogram from one request to the next instead of looking them up by name
// and labels every time. What must not change because of it: every request is
// counted under its own method and status, and a registry that was reset (as
// every test that reads metrics does) counts from zero again rather than into
// series it no longer holds.
import 'package:dartvel_core/http.dart';
import 'package:dartvel_core/src/observability/observability.dart'
    show DVObservability;
import 'package:test/test.dart';

Request _request(String method, String path) => Request(
      method: method,
      url: Uri.parse('http://localhost$path'),
      headers: Headers(),
      bodyStream: const Stream<List<int>>.empty(),
    );

double? _count(String method, int status) => DVObservability.metrics.valueOf(
    'http_requests_total', <String, String>{'method': method, 'status': '$status'});

void main() {
  late Router router;
  setUp(() {
    DVObservability.metrics.reset();
    router = Router()
      ..get('/ok', (Request req) async => Response.text('ok'))
      ..post('/ok', (Request req) async => Response(201))
      ..get('/boom', (Request req) async => Response(503));
  });

  test('each method and status is counted in its own series', () async {
    for (var i = 0; i < 3; i++) {
      await router.call(_request('GET', '/ok'));
    }
    await router.call(_request('POST', '/ok'));
    await router.call(_request('GET', '/boom'));
    await router.call(_request('GET', '/missing'));
    expect(_count('GET', 200), 3);
    expect(_count('POST', 201), 1);
    expect(_count('GET', 503), 1);
    expect(_count('GET', 404), 1);
  });

  test('after a reset the counts start again from zero', () async {
    await router.call(_request('GET', '/ok'));
    await router.call(_request('GET', '/ok'));
    expect(_count('GET', 200), 2);
    DVObservability.metrics.reset();
    expect(_count('GET', 200), isNull);
    await router.call(_request('GET', '/ok'));
    expect(_count('GET', 200), 1);
    expect(DVObservability.metrics.typeOf('http_request_duration_seconds'),
        'histogram');
  });

  test('a router inside a measured request does not count it twice',
      () async {
    final Router outer = Router()..get('/ok', (Request req) => router.call(req));
    await outer.call(_request('GET', '/ok'));
    await outer.call(_request('GET', '/ok'));
    expect(_count('GET', 200), 2);
  });
}
