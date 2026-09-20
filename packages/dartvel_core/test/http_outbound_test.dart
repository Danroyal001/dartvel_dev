// DV.Http: how the application calls the world.
//
// The section this implements makes one claim above the rest: an integration
// whose failure path has never run is an integration nobody has tested. So
// these tests spend their effort on the silent failures — a charge retried
// until the customer is billed twice, a timeout that leaves the request
// running, a breaker that keeps sending traffic into a service that is down, a
// credential that ends up in a URL — rather than on the 200 that was never
// going to be the problem.
import 'package:dartvel_core/src/observability/observability.dart';
import 'dart:async';
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// A transport that answers from [answer] and records what it was asked.
class _Wire {
  _Wire(this.answer);

  final FutureOr<DVHttpStreamedResponse> Function(DVHttpRequest request, int n)
      answer;
  final List<DVHttpRequest> requests = <DVHttpRequest>[];

  Future<DVHttpStreamedResponse> send(DVHttpRequest request) async {
    requests.add(request);
    return answer(request, requests.length);
  }
}

DVHttpStreamedResponse _reply(int status,
        {Object? json, Map<String, String> headers = const {}}) =>
    DVHttpStreamedResponse(
      statusCode: status,
      headers: <String, String>{
        if (json != null) 'content-type': 'application/json',
        ...headers,
      },
      body: Stream<List<int>>.value(
          json == null ? const <int>[] : utf8.encode(jsonEncode(json))),
    );

void main() {
  const DVHttp http = DVHttp();
  final List<Duration> slept = <Duration>[];
  DateTime now = DateTime.utc(2026, 9, 13, 12);

  setUp(() {
    DVHttp.reset();
    DVSecrets.reset();
    DVObservability.resetLogging();
    // The absolute URLs below are under a declared host, as every absolute URL
    // has to be; see http_undeclared_url_test.dart for the ones that are not.
    http.declare(
        'example', const DVHttpHostConfig(baseUrl: 'https://api.example.com'));
    slept.clear();
    now = DateTime.utc(2026, 9, 13, 12);
    DVHttp.sleep = (Duration d) async => slept.add(d);
    DVHttp.clock = () => now;
  });

  tearDown(() {
    DVHttp.reset();
    DVSecrets.reset();
  });

  group('one client, the wire types it already has', () {
    test('a response is the WinterCG Response the inbound side uses', () async {
      final _Wire wire = _Wire((_, __) => _reply(200, json: {'rate': 1.5}));
      DVHttp.transport = wire.send;

      final Response response =
          await http.get('https://api.example.com/v1/rates');

      expect(response, isA<Response>());
      expect(response.status, 200);
      expect(response.headers.get('content-type'), 'application/json');
      expect(await response.body!.jsonDecode(), {'rate': 1.5});
      expect(wire.requests.single.method, 'GET');
      expect(wire.requests.single.url.toString(),
          'https://api.example.com/v1/rates');
    });

    test('json is encoded and labelled', () async {
      final _Wire wire = _Wire((_, __) => _reply(201));
      DVHttp.transport = wire.send;

      await http.post('https://api.example.com/v1/charges',
          json: <String, Object?>{'amount': 500});

      final DVHttpRequest sent = wire.requests.single;
      expect(sent.method, 'POST');
      expect(sent.headers['content-type'], 'application/json; charset=utf-8');
      expect(jsonDecode(utf8.decode(sent.body)), {'amount': 500});
    });
  });

  group('hosts are declared, not concatenated', () {
    test('a declared host joins its base URL and path', () async {
      final _Wire wire = _Wire((_, __) => _reply(200));
      DVHttp.transport = wire.send;
      http.declare('paystack',
          const DVHttpHostConfig(baseUrl: 'https://api.paystack.co/'));

      await http.host('paystack').get('/transaction/verify/ref-1');

      expect(wire.requests.single.url.toString(),
          'https://api.paystack.co/transaction/verify/ref-1');
    });

    test('an undeclared host is refused with DV-HTTP-001', () {
      expect(
        () => http.host('paystak'),
        throwsA(isA<DVHttpUndeclaredHostException>()
            .having((e) => e.code, 'code', 'DV-HTTP-001')
            .having((e) => e.host, 'host', 'paystak')),
      );
    });

    test('credentials resolve by name through Secrets, into a header only',
        () async {
      final _Wire wire = _Wire((_, __) => _reply(200));
      DVHttp.transport = wire.send;
      DVSecrets.configure(<String, String>{'PAYSTACK_SECRET_KEY': 'sk_live_abc123xyz'});
      http.declare(
        'paystack',
        const DVHttpHostConfig(
          baseUrl: 'https://api.paystack.co',
          bearerSecret: 'PAYSTACK_SECRET_KEY',
        ),
      );

      await http.host('paystack').get('/balance');

      final DVHttpRequest sent = wire.requests.single;
      expect(sent.headers['authorization'], 'Bearer sk_live_abc123xyz');
      expect(sent.url.toString(), isNot(contains('sk_live')));
    });

    test('a missing secret is named, and the request is never sent', () async {
      final _Wire wire = _Wire((_, __) => _reply(200));
      DVHttp.transport = wire.send;
      http.declare(
        'paystack',
        const DVHttpHostConfig(
          baseUrl: 'https://api.paystack.co',
          bearerSecret: 'PAYSTACK_SECRET_KEY',
        ),
      );

      await expectLater(
        http.host('paystack').get('/balance'),
        throwsA(isA<DVSecretNotFoundException>()
            .having((e) => e.key, 'key', 'PAYSTACK_SECRET_KEY')),
      );
      expect(wire.requests, isEmpty,
          reason: 'an unauthenticated request to a payment gateway is not a '
              'degraded version of the authenticated one');
    });

    test('the dartvel.http config block declares hosts', () async {
      final _Wire wire = _Wire((_, __) => _reply(503));
      DVHttp.transport = wire.send;
      http.declareFromConfig(<String, Object?>{
        'hosts': <String, Object?>{
          'paystack': <String, Object?>{
            'baseUrl': 'https://api.paystack.co',
            'auth': <String, Object?>{'bearer': 'PAYSTACK_SECRET_KEY'},
            'timeout': '10s',
            'retries': <String, Object?>{
              'attempts': 2,
              'backoff': 'exponential',
              'jitter': false,
            },
            'circuitBreaker': <String, Object?>{
              'failureRate': 0.5,
              'window': '30s',
              'cooldown': '60s',
            },
            'pool': <String, Object?>{'maxConcurrent': 8},
          },
        },
      });

      final DVHttpHostConfig config = http.host('paystack').config;
      expect(config.baseUrl, 'https://api.paystack.co');
      expect(config.bearerSecret, 'PAYSTACK_SECRET_KEY');
      expect(config.timeout, const Duration(seconds: 10));
      expect(config.retries.attempts, 2);
      expect(config.retries.jitter, isFalse);
      expect(config.breaker!.cooldown, const Duration(seconds: 60));
      expect(config.maxConcurrent, 8);
    });
  });

  group('retries are idempotency-aware', () {
    setUp(() {
      http.declare(
        'api',
        const DVHttpHostConfig(
          baseUrl: 'https://api.example.com',
          retries: DVHttpRetryPolicy(attempts: 3, jitter: false),
        ),
      );
    });

    test('a GET that meets a 503 is retried, with backoff, until it succeeds',
        () async {
      final _Wire wire =
          _Wire((_, int n) => n < 3 ? _reply(503) : _reply(200));
      DVHttp.transport = wire.send;

      final Response response = await http.host('api').get('/rates');

      expect(response.status, 200);
      expect(wire.requests, hasLength(3));
      expect(slept, hasLength(2));
      expect(slept[1], greaterThan(slept[0]),
          reason: 'exponential backoff waits longer each time');
    });

    test('a POST is not retried — a retried charge bills the customer twice',
        () async {
      final _Wire wire = _Wire((_, __) => _reply(503));
      DVHttp.transport = wire.send;

      final Response response =
          await http.host('api').post('/charges', json: {'amount': 500});

      expect(response.status, 503);
      expect(wire.requests, hasLength(1));
    });

    test('a POST with an idempotency key retries, sending the same key',
        () async {
      final _Wire wire =
          _Wire((_, int n) => n < 2 ? _reply(503) : _reply(201));
      DVHttp.transport = wire.send;

      final Response response = await http
          .host('api')
          .post('/charges', json: {'amount': 500}, idempotencyKey: 'order-42');

      expect(response.status, 201);
      expect(wire.requests, hasLength(2));
      expect(
        wire.requests.map((DVHttpRequest r) => r.headers['idempotency-key']),
        everyElement('order-42'),
      );
    });

    test('asking to retry a POST without a key sends once and says DV-HTTP-003',
        () async {
      final _Wire wire = _Wire((_, __) => _reply(503));
      DVHttp.transport = wire.send;

      await http.host('api').post('/charges', json: {'amount': 1}, attempts: 3);

      expect(wire.requests, hasLength(1));
      expect(
        DVObservability.recentLogs.map((DVLogRecord r) => r.code),
        contains('DV-HTTP-003'),
      );
    });

    test('a 4xx is the caller\'s mistake and is not retried', () async {
      final _Wire wire = _Wire((_, __) => _reply(404));
      DVHttp.transport = wire.send;

      final Response response = await http.host('api').get('/missing');

      expect(response.status, 404);
      expect(wire.requests, hasLength(1));
    });

    test('a transport failure on a GET is retried like a 503', () async {
      final _Wire wire = _Wire((_, int n) =>
          n == 1 ? throw StateError('connection reset') : _reply(200));
      DVHttp.transport = wire.send;

      expect((await http.host('api').get('/rates')).status, 200);
      expect(wire.requests, hasLength(2));
    });
  });

  group('timeouts', () {
    test('a slow host times out with a typed error naming it', () async {
      DVHttp.sleep = (Duration d) => Future<void>.delayed(Duration.zero);
      final Completer<DVHttpStreamedResponse> never =
          Completer<DVHttpStreamedResponse>();
      DVHttp.transport = (DVHttpRequest _) => never.future;
      http.declare(
        'slow',
        const DVHttpHostConfig(
          baseUrl: 'https://slow.example.com',
          timeout: Duration(milliseconds: 20),
          retries: DVHttpRetryPolicy(attempts: 1),
        ),
      );

      await expectLater(
        http.host('slow').get('/'),
        throwsA(isA<DVHttpTimeoutException>()
            .having((e) => e.host, 'host', 'slow')
            .having((e) => e.timeout, 'timeout',
                const Duration(milliseconds: 20))),
      );
    });

    test('a request that fails after its timeout does not escape as an '
        'uncaught error', () async {
      final List<Object> uncaught = <Object>[];
      await runZonedGuarded(() async {
        final Completer<DVHttpStreamedResponse> late =
            Completer<DVHttpStreamedResponse>();
        DVHttp.transport = (DVHttpRequest _) => late.future;
        http.declare(
          'slow',
          const DVHttpHostConfig(
            baseUrl: 'https://slow.example.com',
            timeout: Duration(milliseconds: 10),
            retries: DVHttpRetryPolicy(attempts: 1),
          ),
        );
        try {
          await http.host('slow').get('/');
        } on DVHttpTimeoutException {
          // expected
        }
        late.completeError(StateError('the socket closed long after'));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }, (Object error, StackTrace _) => uncaught.add(error));

      expect(uncaught, isEmpty,
          reason: 'the abandoned request\'s own failure is not the caller\'s '
              'to handle, and must not crash the process that gave up on it');
    });
  });

  group('the circuit breaker', () {
    setUp(() {
      http.declare(
        'shipping',
        const DVHttpHostConfig(
          baseUrl: 'https://shipping.example.com',
          retries: DVHttpRetryPolicy(attempts: 1),
          breaker: DVHttpBreakerPolicy(
            failureRate: 0.5,
            window: Duration(seconds: 30),
            cooldown: Duration(seconds: 60),
            minimumRequests: 4,
          ),
        ),
      );
    });

    test('opens on the failure rate, then fails fast naming host and retry '
        'time, and says DV-HTTP-002', () async {
      final _Wire wire = _Wire((_, __) => _reply(503));
      DVHttp.transport = wire.send;

      for (int i = 0; i < 4; i++) {
        await http.host('shipping').get('/quote');
      }
      expect(wire.requests, hasLength(4));

      await expectLater(
        http.host('shipping').get('/quote'),
        throwsA(isA<DVHttpCircuitOpenException>()
            .having((e) => e.code, 'code', 'DV-HTTP-002')
            .having((e) => e.host, 'host', 'shipping')
            .having((e) => e.retryAt, 'retryAt',
                now.add(const Duration(seconds: 60)))),
      );
      expect(wire.requests, hasLength(4),
          reason: 'failing fast means the request never goes out');
      expect(DVObservability.recentLogs.map((DVLogRecord r) => r.code),
          contains('DV-HTTP-002'));
    });

    test('lets one request through after the cooldown, and closes on success',
        () async {
      bool healthy = false;
      final _Wire wire = _Wire((_, __) => healthy ? _reply(200) : _reply(503));
      DVHttp.transport = wire.send;
      for (int i = 0; i < 4; i++) {
        await http.host('shipping').get('/quote');
      }

      now = now.add(const Duration(seconds: 61));
      healthy = true;

      expect((await http.host('shipping').get('/quote')).status, 200);
      expect((await http.host('shipping').get('/quote')).status, 200);
      expect(wire.requests, hasLength(6));
    });

    test('a failed probe after the cooldown reopens it', () async {
      final _Wire wire = _Wire((_, __) => _reply(503));
      DVHttp.transport = wire.send;
      for (int i = 0; i < 4; i++) {
        await http.host('shipping').get('/quote');
      }
      now = now.add(const Duration(seconds: 61));

      await http.host('shipping').get('/quote');

      await expectLater(http.host('shipping').get('/quote'),
          throwsA(isA<DVHttpCircuitOpenException>()));
      expect(wire.requests, hasLength(5));
    });
  });

  group('the pool', () {
    test('never has more requests in flight than maxConcurrent', () async {
      int inFlight = 0;
      int peak = 0;
      DVHttp.transport = (DVHttpRequest _) async {
        inFlight++;
        peak = inFlight > peak ? inFlight : peak;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        inFlight--;
        return _reply(200);
      };
      http.declare(
        'geo',
        const DVHttpHostConfig(
            baseUrl: 'https://geo.example.com', maxConcurrent: 2),
      );

      await Future.wait(<Future<Response>>[
        for (int i = 0; i < 6; i++) http.host('geo').get('/lookup/$i'),
      ]);

      expect(peak, 2);
    });
  });

  group('trace context', () {
    test('a call inside a span sends a traceparent naming a child of it',
        () async {
      final _Wire wire = _Wire((_, __) => _reply(200));
      DVHttp.transport = wire.send;
      final DVSpan parent = DVTracer().startSpan('checkout');

      await dvInSpan(parent, () => http.get('https://api.example.com/rates'));

      final DVTraceContext? sent =
          DVTraceContext.parse(wire.requests.single.headers['traceparent']);
      expect(sent, isNotNull);
      expect(sent!.traceId, parent.traceId,
          reason: 'the outbound request belongs to the same trace');
      expect(sent.parentSpanId, isNot(parent.spanId),
          reason: 'it is a span under the function, not the function itself');
    });
  });

  group('testing is the point', () {
    test('stubs answer by host name, and the failure paths are one line each',
        () async {
      http.declare('paystack',
          const DVHttpHostConfig(baseUrl: 'https://api.paystack.co'));
      http.declare(
        'shipping',
        const DVHttpHostConfig(
          baseUrl: 'https://shipping.example.com',
          retries: DVHttpRetryPolicy(attempts: 1),
        ),
      );
      http.declare(
        'geocoder',
        const DVHttpHostConfig(
          baseUrl: 'https://geo.example.com',
          timeout: Duration(milliseconds: 10),
          retries: DVHttpRetryPolicy(attempts: 1),
        ),
      );
      final DVHttpFake fake = const DVTestHarness().fakeHttp(
        <String, DVHttpStub>{
          'paystack': DVHttpStub.json(<String, Object?>{'status': true}),
          'shipping': DVHttpStub.status(503),
          'geocoder': DVHttpStub.timeout(),
        },
      );

      final Response paid = await http.host('paystack').get('/verify');
      expect(await paid.body!.jsonDecode(), {'status': true});
      expect((await http.host('shipping').get('/quote')).status, 503);
      await expectLater(http.host('geocoder').get('/'),
          throwsA(isA<DVHttpTimeoutException>()));

      expect(fake.calls.map((DVHttpCall c) => c.host),
          <String>['paystack', 'shipping', 'geocoder']);
    });

    test('a test that reaches the network with no fake fails with DV-HTTP-004',
        () async {
      http.declare('paystack',
          const DVHttpHostConfig(baseUrl: 'https://api.paystack.co'));
      http.declare('partner',
          const DVHttpHostConfig(baseUrl: 'https://partner.example.com'));
      bool wireTouched = false;
      DVHttp.transport = (DVHttpRequest _) async {
        wireTouched = true;
        return _reply(200);
      };
      const DVTestHarness().fakeHttp(
          <String, DVHttpStub>{'paystack': DVHttpStub.status(200)});

      await expectLater(
        http.host('partner').get('/'),
        throwsA(isA<DVHttpNetworkBlockedException>()
            .having((e) => e.code, 'code', 'DV-HTTP-004')
            .having((e) => e.host, 'host', 'partner')),
      );
      expect(wireTouched, isFalse);
    });

    test('a recorded fixture replays the shape the service really returned',
        () async {
      DVHttp.transport = (DVHttpRequest _) async =>
          _reply(200, json: {'id': 'tx_1', 'amount': 500});
      http.declare('paystack',
          const DVHttpHostConfig(baseUrl: 'https://api.paystack.co'));

      final List<DVHttpFixture> recorded = <DVHttpFixture>[];
      http.record(recorded);
      await http.host('paystack').get('/transaction/tx_1');
      http.stopRecording();

      expect(recorded, hasLength(1));
      final DVHttpFixture fixture =
          DVHttpFixture.fromJson(jsonDecode(jsonEncode(recorded.single.toJson()))
              as Map<String, Object?>);

      const DVTestHarness().fakeHttp(
          <String, DVHttpStub>{'paystack': DVHttpStub.fixture(fixture)});
      final Response replayed = await http.host('paystack').get('/transaction/tx_1');

      expect(replayed.status, 200);
      expect(await replayed.body!.jsonDecode(), {'id': 'tx_1', 'amount': 500});
    });
  });
}
