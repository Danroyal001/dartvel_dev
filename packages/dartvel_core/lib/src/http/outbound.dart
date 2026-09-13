/// `DV.Http`: how the application calls the world.
///
/// Backend functions are how the world calls the application; this is the
/// other direction — the payment gateway, the shipping API, the partner's
/// endpoint — and the surface third-party integrations are built on.
///
/// It sends and returns the same WinterCG [Response] and [Headers] the inbound
/// side uses. A fetch type is the same type whichever way it travels, so there
/// is no second response class to learn and no conversion between an inbound
/// body and an outbound one.
library dartvel_core.http.outbound;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../observability/observability.dart';
import '../secrets/secrets.dart';
import 'transport.dart';
import 'wintercg.dart';

/// Puts one outbound request on the wire and yields its response as it
/// arrives. [dvStreamHttpRequest] by default; replaceable for a test that
/// wants to be the wire itself.
typedef DVHttpStreamSend = Future<DVHttpStreamedResponse> Function(
    DVHttpRequest request);

/// `DV-HTTP-001`: a request named a host nobody declared.
class DVHttpUndeclaredHostException implements Exception {
  const DVHttpUndeclaredHostException(this.host);

  final String host;
  String get code => 'DV-HTTP-001';

  @override
  String toString() => '$code: no host named "$host" is declared. Declare it '
      'under dartvel.http.hosts, or with DV.Http.declare, so its credentials, '
      'timeout, retries and breaker come from one place.';
}

/// `DV-HTTP-002`: the host's breaker is open, and the request never went out.
///
/// Names the host and when it will be tried again, so the caller's own
/// degradation path can run — and say something true — instead of queueing
/// behind a service that is already down.
class DVHttpCircuitOpenException implements Exception {
  const DVHttpCircuitOpenException(this.host, this.retryAt);

  final String host;
  final DateTime retryAt;
  String get code => 'DV-HTTP-002';

  @override
  String toString() => '$code: the circuit breaker for "$host" is open; the '
      'request failed fast. The next attempt is allowed at '
      '${retryAt.toUtc().toIso8601String()}.';
}

/// A host did not answer within its timeout.
class DVHttpTimeoutException implements Exception {
  const DVHttpTimeoutException(this.host, this.timeout);

  final String host;
  final Duration timeout;

  @override
  String toString() =>
      'DVHttpTimeoutException: "$host" did not answer within $timeout.';
}

/// `DV-HTTP-004`: a test reached the network with no fake configured.
///
/// Refused rather than allowed to pass slowly: a suite whose result depends on
/// somebody else's uptime is not a suite.
class DVHttpNetworkBlockedException implements Exception {
  const DVHttpNetworkBlockedException(this.host);

  final String host;
  String get code => 'DV-HTTP-004';

  @override
  String toString() => '$code: a request to "$host" reached for the network '
      'while outbound HTTP is faked, and no stub answers for that host. Add '
      'one to the fakeHttp map.';
}

/// How a host retries.
///
/// Whether a request may be retried at all is decided by its method and its
/// idempotency key, not here: this only says how many times and how far
/// apart.
class DVHttpRetryPolicy {
  const DVHttpRetryPolicy({
    this.attempts = 3,
    this.baseDelay = const Duration(milliseconds: 200),
    this.maxDelay = const Duration(seconds: 10),
    this.exponential = true,
    this.jitter = true,
  });

  /// Total attempts, including the first. One means never retry.
  final int attempts;
  final Duration baseDelay;
  final Duration maxDelay;
  final bool exponential;

  /// Randomises each wait, so a hundred clients that failed together do not
  /// all come back in the same millisecond.
  final bool jitter;

  /// How long to wait before retry number [retry], counted from one.
  Duration delayFor(int retry, Random random) {
    final int factor = exponential ? 1 << (retry - 1).clamp(0, 20) : 1;
    int micros = baseDelay.inMicroseconds * factor;
    if (micros > maxDelay.inMicroseconds) micros = maxDelay.inMicroseconds;
    if (jitter) micros = (micros / 2 + random.nextDouble() * micros / 2).round();
    return Duration(microseconds: micros);
  }
}

/// When a host's breaker opens, and how long it stays open.
class DVHttpBreakerPolicy {
  const DVHttpBreakerPolicy({
    this.failureRate = 0.5,
    this.window = const Duration(seconds: 30),
    this.cooldown = const Duration(seconds: 60),
    this.minimumRequests = 5,
  });

  /// The share of requests in [window] that must fail for it to open.
  final double failureRate;
  final Duration window;
  final Duration cooldown;

  /// Fewer requests than this in the window never open it: one failure out of
  /// one request is a rate of 100% and tells you nothing.
  final int minimumRequests;
}

/// A declared host: the unit credentials, timeout, retries, breaker and pool
/// hang off.
///
/// Per host because "the payment gateway is slow" and "the geocoder is slow"
/// call for different answers, and a global setting gives them the same one.
class DVHttpHostConfig {
  const DVHttpHostConfig({
    required this.baseUrl,
    this.bearerSecret,
    this.headers = const <String, String>{},
    this.timeout = const Duration(seconds: 30),
    this.retries = const DVHttpRetryPolicy(),
    this.breaker,
    this.maxConcurrent,
  });

  final String baseUrl;

  /// The name of a secret sent as `Authorization: Bearer <value>`.
  ///
  /// A name, resolved through Secrets at the moment of sending — never a value
  /// and never interpolated into a URL, which is how credentials end up in
  /// access logs.
  final String? bearerSecret;

  final Map<String, String> headers;
  final Duration timeout;
  final DVHttpRetryPolicy retries;
  final DVHttpBreakerPolicy? breaker;

  /// Requests allowed in flight at once; null for no limit.
  final int? maxConcurrent;

  /// Reads one entry of the `dartvel.http.hosts` block.
  factory DVHttpHostConfig.fromConfig(String name, Map<String, Object?> map) {
    final Object? baseUrl = map['baseUrl'];
    if (baseUrl is! String || baseUrl.isEmpty) {
      throw ArgumentError('dartvel.http.hosts.$name needs a baseUrl.');
    }

    String? bearer;
    final Object? auth = map['auth'];
    if (auth is Map) {
      for (final MapEntry<Object?, Object?> entry in auth.entries) {
        if (entry.key == 'bearer') {
          bearer = '${entry.value}';
        } else {
          // Refused rather than ignored: an auth scheme that silently does
          // nothing sends unauthenticated requests and says nothing about it.
          throw ArgumentError(
              'dartvel.http.hosts.$name.auth.${entry.key} is not a supported '
              'auth scheme; bearer is.');
        }
      }
    }

    DVHttpRetryPolicy retries = const DVHttpRetryPolicy();
    final Object? retry = map['retries'];
    if (retry is Map) {
      retries = DVHttpRetryPolicy(
        attempts: _int(retry['attempts'], 3),
        baseDelay: _duration(retry['delay'], const Duration(milliseconds: 200)),
        exponential: '${retry['backoff'] ?? 'exponential'}' == 'exponential',
        jitter: retry['jitter'] is bool ? retry['jitter']! as bool : true,
      );
    }

    DVHttpBreakerPolicy? breaker;
    final Object? circuit = map['circuitBreaker'];
    if (circuit is Map) {
      breaker = DVHttpBreakerPolicy(
        failureRate: circuit['failureRate'] is num
            ? (circuit['failureRate']! as num).toDouble()
            : 0.5,
        window: _duration(circuit['window'], const Duration(seconds: 30)),
        cooldown: _duration(circuit['cooldown'], const Duration(seconds: 60)),
        minimumRequests: _int(circuit['minimumRequests'], 5),
      );
    }

    final Object? pool = map['pool'];
    final Object? headers = map['headers'];
    return DVHttpHostConfig(
      baseUrl: baseUrl,
      bearerSecret: bearer,
      headers: headers is Map
          ? <String, String>{
              for (final MapEntry<Object?, Object?> e in headers.entries)
                '${e.key}': '${e.value}',
            }
          : const <String, String>{},
      timeout: _duration(map['timeout'], const Duration(seconds: 30)),
      retries: retries,
      breaker: breaker,
      maxConcurrent: pool is Map && pool['maxConcurrent'] != null
          ? _int(pool['maxConcurrent'], 0)
          : null,
    );
  }
}

int _int(Object? value, int fallback) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

/// `10s`, `500ms`, `2m`, `1h`, or a bare number of seconds.
Duration _duration(Object? value, Duration fallback) {
  if (value == null) return fallback;
  if (value is num) return Duration(milliseconds: (value * 1000).round());
  final RegExpMatch? match =
      RegExp(r'^\s*(\d+(?:\.\d+)?)\s*(ms|s|m|h)?\s*$').firstMatch('$value');
  if (match == null) {
    throw ArgumentError('"$value" is not a duration; use 500ms, 10s, 2m or 1h.');
  }
  final double amount = double.parse(match.group(1)!);
  final int millis = switch (match.group(2)) {
    'ms' => amount.round(),
    'm' => (amount * 60000).round(),
    'h' => (amount * 3600000).round(),
    _ => (amount * 1000).round(),
  };
  return Duration(milliseconds: millis);
}

/// A request a fake answered, for a test to assert on.
class DVHttpCall {
  const DVHttpCall({
    required this.host,
    required this.method,
    required this.url,
    required this.headers,
    required this.body,
  });

  final String host;
  final String method;
  final Uri url;
  final Map<String, String> headers;
  final List<int> body;
}

/// A response recorded from a real call, to be replayed by a stub.
///
/// Recorded rather than written by hand so a stub stays honest about the
/// shape the service actually returns.
class DVHttpFixture {
  const DVHttpFixture({
    required this.method,
    required this.url,
    required this.status,
    this.headers = const <String, String>{},
    this.body = const <int>[],
  });

  final String method;
  final Uri url;
  final int status;
  final Map<String, String> headers;
  final List<int> body;

  Map<String, Object?> toJson() {
    String? text;
    try {
      text = utf8.decode(body);
    } on FormatException {
      text = null;
    }
    return <String, Object?>{
      'method': method,
      'url': url.toString(),
      'status': status,
      'headers': headers,
      if (text != null) 'body': text else 'bodyBase64': base64Encode(body),
    };
  }

  factory DVHttpFixture.fromJson(Map<String, Object?> json) => DVHttpFixture(
        method: '${json['method']}',
        url: Uri.parse('${json['url']}'),
        status: json['status']! as int,
        headers: <String, String>{
          for (final MapEntry<String, Object?> e
              in ((json['headers'] as Map?)?.cast<String, Object?>() ??
                      const <String, Object?>{})
                  .entries)
            e.key: '${e.value}',
        },
        body: json['bodyBase64'] != null
            ? base64Decode('${json['bodyBase64']}')
            : utf8.encode('${json['body'] ?? ''}'),
      );
}

enum _StubKind { response, timeout, error, sequence }

/// What a faked host answers.
///
/// The failure paths are as short to write as the success one, because an
/// integration test that can only produce a 200 has tested the half that was
/// never going to be the problem.
class DVHttpStub {
  const DVHttpStub._(
    this._kind, {
    this.status = 200,
    this.headers = const <String, String>{},
    this.body = const <int>[],
    this.error,
    this.sequence = const <DVHttpStub>[],
  });

  final _StubKind _kind;
  final int status;
  final Map<String, String> headers;
  final List<int> body;
  final Object? error;
  final List<DVHttpStub> sequence;

  factory DVHttpStub.json(
    Object? data, {
    int status = 200,
    Map<String, String> headers = const <String, String>{},
  }) =>
      DVHttpStub._(
        _StubKind.response,
        status: status,
        headers: <String, String>{
          'content-type': 'application/json; charset=utf-8',
          ...headers,
        },
        body: utf8.encode(jsonEncode(data)),
      );

  factory DVHttpStub.text(
    String text, {
    int status = 200,
    Map<String, String> headers = const <String, String>{},
  }) =>
      DVHttpStub._(
        _StubKind.response,
        status: status,
        headers: <String, String>{
          'content-type': 'text/plain; charset=utf-8',
          ...headers,
        },
        body: utf8.encode(text),
      );

  /// A bare status: `DVHttpStub.status(503)` exercises the degradation path.
  factory DVHttpStub.status(int status) =>
      DVHttpStub._(_StubKind.response, status: status);

  /// Never answers, so the host's own timeout is what the caller meets.
  factory DVHttpStub.timeout() => const DVHttpStub._(_StubKind.timeout);

  /// Fails the way a broken connection does.
  factory DVHttpStub.error(Object error) =>
      DVHttpStub._(_StubKind.error, error: error);

  /// The nth call gets the nth stub, and the last one repeats — a service
  /// that fails twice and then recovers.
  factory DVHttpStub.sequence(List<DVHttpStub> stubs) =>
      DVHttpStub._(_StubKind.sequence, sequence: stubs);

  /// Replays a recorded response.
  factory DVHttpStub.fixture(DVHttpFixture fixture) => DVHttpStub._(
        _StubKind.response,
        status: fixture.status,
        headers: fixture.headers,
        body: fixture.body,
      );

  Future<DVHttpStreamedResponse> _answer(int call) {
    switch (_kind) {
      case _StubKind.response:
        return Future<DVHttpStreamedResponse>.value(DVHttpStreamedResponse(
          statusCode: status,
          headers: headers,
          body: Stream<List<int>>.value(body),
        ));
      case _StubKind.timeout:
        return Completer<DVHttpStreamedResponse>().future;
      case _StubKind.error:
        return Future<DVHttpStreamedResponse>.error(error!);
      case _StubKind.sequence:
        if (sequence.isEmpty) return DVHttpStub.status(200)._answer(call);
        final int index = (call - 1).clamp(0, sequence.length - 1);
        return sequence[index]._answer(call);
    }
  }
}

/// Faked outbound HTTP, and what it was asked.
class DVHttpFake {
  DVHttpFake(Map<String, DVHttpStub> stubs)
      : stubs = Map<String, DVHttpStub>.unmodifiable(stubs);

  final Map<String, DVHttpStub> stubs;

  /// Every request a stub answered, in order.
  final List<DVHttpCall> calls = <DVHttpCall>[];

  final Map<String, int> _counts = <String, int>{};
}

/// A declared host's requests.
class DVHttpHost {
  const DVHttpHost._(this.name, this.config);

  final String name;
  final DVHttpHostConfig config;

  Future<Response> get(String path,
          {Map<String, String> headers = const <String, String>{},
          int? attempts}) =>
      send('GET', path, headers: headers, attempts: attempts);

  Future<Response> head(String path,
          {Map<String, String> headers = const <String, String>{},
          int? attempts}) =>
      send('HEAD', path, headers: headers, attempts: attempts);

  Future<Response> delete(String path,
          {Map<String, String> headers = const <String, String>{},
          int? attempts}) =>
      send('DELETE', path, headers: headers, attempts: attempts);

  Future<Response> post(String path,
          {Object? json,
          Object? body,
          Map<String, String> headers = const <String, String>{},
          String? idempotencyKey,
          int? attempts}) =>
      send('POST', path,
          json: json,
          body: body,
          headers: headers,
          idempotencyKey: idempotencyKey,
          attempts: attempts);

  Future<Response> put(String path,
          {Object? json,
          Object? body,
          Map<String, String> headers = const <String, String>{},
          String? idempotencyKey,
          int? attempts}) =>
      send('PUT', path,
          json: json,
          body: body,
          headers: headers,
          idempotencyKey: idempotencyKey,
          attempts: attempts);

  Future<Response> patch(String path,
          {Object? json,
          Object? body,
          Map<String, String> headers = const <String, String>{},
          String? idempotencyKey,
          int? attempts}) =>
      send('PATCH', path,
          json: json,
          body: body,
          headers: headers,
          idempotencyKey: idempotencyKey,
          attempts: attempts);

  Future<Response> send(
    String method,
    String path, {
    Object? json,
    Object? body,
    Map<String, String> headers = const <String, String>{},
    String? idempotencyKey,
    int? attempts,
  }) {
    if (Uri.tryParse(path)?.hasScheme ?? false) {
      // A declared host carries credentials. Letting a full URL through would
      // send them to whatever host the URL names.
      throw ArgumentError('"$path" is a full URL; a declared host takes a path. '
          'Use DV.Http.get for an absolute URL.');
    }
    final String base = config.baseUrl.endsWith('/')
        ? config.baseUrl.substring(0, config.baseUrl.length - 1)
        : config.baseUrl;
    final Uri url = Uri.parse('$base${path.startsWith('/') ? path : '/$path'}');
    return DVHttp._execute(name, config, method, url,
        json: json,
        body: body,
        headers: headers,
        idempotencyKey: idempotencyKey,
        attempts: attempts);
  }
}

/// `DV.Http`.
class DVHttp {
  const DVHttp();

  static final Map<String, DVHttpHostConfig> _hosts =
      <String, DVHttpHostConfig>{};
  static final Map<String, _Breaker> _breakers = <String, _Breaker>{};
  static final Map<String, _Pool> _pools = <String, _Pool>{};
  static DVHttpFake? _fake;
  static List<DVHttpFixture>? _recording;

  /// The wire. Null means [dvStreamHttpRequest], which walks the installed
  /// transports — including the native HTTP/2 client when it is present.
  static DVHttpStreamSend? transport;

  /// How retries wait. Replaceable so a test is not slowed by its own backoff.
  static Future<void> Function(Duration duration) sleep =
      (Duration duration) => Future<void>.delayed(duration);

  /// The breaker's clock.
  static DateTime Function() clock = DateTime.now;

  /// The jitter source.
  static Random random = Random();

  /// Forgets every declared host, breaker, pool, fake and recording, and puts
  /// the wire, the clock and the sleep back.
  static void reset() {
    _hosts.clear();
    _breakers.clear();
    _pools.clear();
    _fake = null;
    _recording = null;
    transport = null;
    sleep = (Duration duration) => Future<void>.delayed(duration);
    clock = DateTime.now;
    random = Random();
  }

  /// Declares [name]. Declaring it again replaces it, and starts its breaker
  /// and pool afresh.
  void declare(String name, DVHttpHostConfig config) {
    _hosts[name] = config;
    _breakers.remove(name);
    _pools.remove(name);
  }

  /// Declares every host in a `dartvel.http` block.
  void declareFromConfig(Map<String, Object?> http) {
    final Object? hosts = http['hosts'];
    if (hosts is! Map) return;
    for (final MapEntry<Object?, Object?> entry in hosts.entries) {
      final Object? value = entry.value;
      if (value is! Map) {
        throw ArgumentError('dartvel.http.hosts.${entry.key} must be a map.');
      }
      declare(
        '${entry.key}',
        DVHttpHostConfig.fromConfig(
            '${entry.key}', value.cast<String, Object?>()),
      );
    }
  }

  /// The declared host [name]. Throws `DV-HTTP-001` when there is none.
  DVHttpHost host(String name) {
    final DVHttpHostConfig? config = _hosts[name];
    if (config == null) throw DVHttpUndeclaredHostException(name);
    return DVHttpHost._(name, config);
  }

  Future<Response> get(Object url,
          {Map<String, String> headers = const <String, String>{},
          int? attempts}) =>
      send('GET', url, headers: headers, attempts: attempts);

  Future<Response> head(Object url,
          {Map<String, String> headers = const <String, String>{},
          int? attempts}) =>
      send('HEAD', url, headers: headers, attempts: attempts);

  Future<Response> delete(Object url,
          {Map<String, String> headers = const <String, String>{},
          int? attempts}) =>
      send('DELETE', url, headers: headers, attempts: attempts);

  Future<Response> post(Object url,
          {Object? json,
          Object? body,
          Map<String, String> headers = const <String, String>{},
          String? idempotencyKey,
          int? attempts}) =>
      send('POST', url,
          json: json,
          body: body,
          headers: headers,
          idempotencyKey: idempotencyKey,
          attempts: attempts);

  Future<Response> put(Object url,
          {Object? json,
          Object? body,
          Map<String, String> headers = const <String, String>{},
          String? idempotencyKey,
          int? attempts}) =>
      send('PUT', url,
          json: json,
          body: body,
          headers: headers,
          idempotencyKey: idempotencyKey,
          attempts: attempts);

  Future<Response> patch(Object url,
          {Object? json,
          Object? body,
          Map<String, String> headers = const <String, String>{},
          String? idempotencyKey,
          int? attempts}) =>
      send('PATCH', url,
          json: json,
          body: body,
          headers: headers,
          idempotencyKey: idempotencyKey,
          attempts: attempts);

  /// Sends to an absolute URL, with the default policy: a 30-second timeout,
  /// idempotency-aware retries, no breaker and no pool. Declare the host to
  /// change any of that.
  Future<Response> send(
    String method,
    Object url, {
    Object? json,
    Object? body,
    Map<String, String> headers = const <String, String>{},
    String? idempotencyKey,
    int? attempts,
  }) {
    final Uri uri = url is Uri ? url : Uri.parse('$url');
    if (!uri.hasScheme || uri.host.isEmpty) {
      throw ArgumentError('"$url" is not an absolute URL.');
    }
    return _execute(
      uri.authority,
      DVHttpHostConfig(baseUrl: '${uri.scheme}://${uri.authority}'),
      method,
      uri,
      json: json,
      body: body,
      headers: headers,
      idempotencyKey: idempotencyKey,
      attempts: attempts,
    );
  }

  /// Answers every outbound request from [stubs], by declared host name or by
  /// the host part of an absolute URL, and refuses any request no stub
  /// answers (`DV-HTTP-004`).
  DVHttpFake fake(Map<String, DVHttpStub> stubs) {
    final DVHttpFake fake = DVHttpFake(stubs);
    _fake = fake;
    return fake;
  }

  /// Back to the real wire.
  void unfake() => _fake = null;

  /// Appends a [DVHttpFixture] to [into] for every real response, until
  /// [stopRecording].
  void record(List<DVHttpFixture> into) => _recording = into;

  void stopRecording() => _recording = null;

  static const Set<String> _idempotentMethods = <String>{
    'GET',
    'HEAD',
    'PUT',
    'DELETE',
    'OPTIONS',
    'TRACE',
  };

  /// Statuses worth another attempt: the server said "not now", not "no".
  static bool _retryable(int status) =>
      status == 429 || status == 500 || status == 502 || status == 503 ||
      status == 504;

  static Future<Response> _execute(
    String key,
    DVHttpHostConfig config,
    String rawMethod,
    Uri url, {
    Object? json,
    Object? body,
    required Map<String, String> headers,
    String? idempotencyKey,
    int? attempts,
  }) async {
    final String method = rawMethod.toUpperCase();
    final bool idempotent =
        _idempotentMethods.contains(method) || idempotencyKey != null;

    int maxAttempts = attempts ?? config.retries.attempts;
    if (maxAttempts < 1) maxAttempts = 1;
    if (!idempotent && maxAttempts > 1) {
      if (attempts != null) {
        // Asked for explicitly, so said out loud. Retrying a POST because its
        // response was slow is how a customer is billed twice; without a key
        // the server has no way to tell the second attempt from a second
        // order.
        DVObservability.log(
          'Refusing to retry $method $url: it is not idempotent and carries '
          'no idempotency key. Sent once.',
          level: DVLogLevel.warn,
          code: 'DV-HTTP-003',
          context: <String, Object?>{'host': key, 'method': method},
        );
      }
      maxAttempts = 1;
    }

    final Map<String, String> sent = <String, String>{
      for (final MapEntry<String, String> e in config.headers.entries)
        e.key.toLowerCase(): e.value,
      for (final MapEntry<String, String> e in headers.entries)
        e.key.toLowerCase(): e.value,
    };

    List<int> payload = const <int>[];
    if (json != null) {
      payload = utf8.encode(jsonEncode(json));
      sent.putIfAbsent('content-type', () => 'application/json; charset=utf-8');
    } else if (body is String) {
      payload = utf8.encode(body);
    } else if (body is List<int>) {
      payload = body;
    } else if (body != null) {
      throw ArgumentError('body must be a String or bytes; use json: for data.');
    }

    // The same key on every attempt, so the server can collapse them.
    if (idempotencyKey != null) sent['idempotency-key'] = idempotencyKey;

    final String? secretName = config.bearerSecret;
    if (secretName != null) {
      // Resolved here, before anything is sent: a missing credential throws
      // naming the secret, and never becomes an unauthenticated request.
      sent['authorization'] = 'Bearer ${const DVSecrets().get(secretName)}';
    }

    final DVSpan? parent = dvCurrentSpan;
    final DVSpan? span = parent == null
        ? null
        : DVObservability.tracer.startSpan('http $method $key', parent: parent);
    if (span != null) {
      sent.putIfAbsent('traceparent', () => span.context.toHeader());
      span
        ..setAttribute('http.method', method)
        ..setAttribute('http.host', key);
    }

    final DVHttpRequest request = DVHttpRequest(
      url: url,
      method: method,
      headers: sent,
      body: payload,
    );

    try {
      for (int attempt = 1;; attempt++) {
        final DVHttpBreakerPolicy? breakerPolicy = config.breaker;
        final _Breaker? breaker = breakerPolicy == null
            ? null
            : _breakers.putIfAbsent(key, () => _Breaker(breakerPolicy));
        final DateTime? blockedUntil = breaker?.blockedUntil(clock());
        if (blockedUntil != null) {
          DVObservability.log(
            'Circuit breaker for "$key" is open; $method $url failed fast.',
            level: DVLogLevel.warn,
            code: 'DV-HTTP-002',
            context: <String, Object?>{
              'host': key,
              'retryAt': blockedUntil.toUtc().toIso8601String(),
            },
          );
          throw DVHttpCircuitOpenException(key, blockedUntil);
        }

        _Received? received;
        Object? failure;
        StackTrace? failureStack;
        try {
          received = await _once(key, config, request);
        } on DVHttpNetworkBlockedException {
          // A missing fake is the test's mistake, not the host's health.
          breaker?.release();
          rethrow;
        } on Object catch (error, stack) {
          failure = error;
          failureStack = stack;
        }

        final bool failed = failure != null || _retryable(received!.status);
        breaker?.record(clock(), failed: failed);

        if (!failed || attempt >= maxAttempts) {
          if (failure != null) {
            span?.recordError(failure, failureStack);
            Error.throwWithStackTrace(failure, failureStack!);
          }
          span?.setAttribute('http.status_code', '${received!.status}');
          return Response(
            received!.status,
            headers: Headers(received.headers),
            body: Stream<List<int>>.value(Uint8List.fromList(received.bytes)),
          );
        }

        await sleep(config.retries.delayFor(attempt, random));
      }
    } finally {
      span?.end();
    }
  }

  /// One attempt: through the pool, bounded by the host's timeout, with the
  /// whole body read inside it.
  static Future<_Received> _once(
    String key,
    DVHttpHostConfig config,
    DVHttpRequest request,
  ) {
    Future<_Received> inner() async {
      final DVHttpStreamedResponse response = await _dispatch(key, request);
      final List<int> bytes = await _collect(response.body);
      final List<DVHttpFixture>? recording = _recording;
      if (recording != null && _fake == null) {
        recording.add(DVHttpFixture(
          method: request.method,
          url: request.url,
          status: response.statusCode,
          headers: response.headers,
          body: bytes,
        ));
      }
      return _Received(response.statusCode, response.headers, bytes);
    }

    final int? limit = config.maxConcurrent;
    // The pool holds its slot until the request itself finishes, not until
    // the caller stops waiting: a timed-out request is still in flight, and
    // releasing its slot would let more than the limit onto the wire.
    final Future<_Received> work = limit == null || limit < 1
        ? inner()
        : _pools.putIfAbsent(key, () => _Pool(limit)).run(inner);

    // Future.timeout keeps listening to [work] after it gives up on it, so the
    // abandoned request's own later failure is observed rather than escaping
    // as an uncaught error in the process that stopped waiting. The test for
    // exactly that pins this behaviour, since nothing here says it out loud.
    return work.timeout(
      config.timeout,
      onTimeout: () => throw DVHttpTimeoutException(key, config.timeout),
    );
  }

  static Future<DVHttpStreamedResponse> _dispatch(
      String key, DVHttpRequest request) {
    final DVHttpFake? fake = _fake;
    if (fake != null) {
      final DVHttpStub? stub = fake.stubs[key] ??
          fake.stubs[request.url.host] ??
          fake.stubs[request.url.authority];
      if (stub == null) {
        DVObservability.log(
          'A test reached the network: no stub answers "$key".',
          level: DVLogLevel.error,
          code: 'DV-HTTP-004',
          context: <String, Object?>{'host': key},
        );
        return Future<DVHttpStreamedResponse>.error(
            DVHttpNetworkBlockedException(key));
      }
      fake.calls.add(DVHttpCall(
        host: key,
        method: request.method,
        url: request.url,
        headers: request.headers,
        body: request.body,
      ));
      final int call = fake._counts[key] = (fake._counts[key] ?? 0) + 1;
      return stub._answer(call);
    }
    return (transport ?? dvStreamHttpRequest)(request);
  }

  static Future<List<int>> _collect(Stream<List<int>> body) async {
    final BytesBuilder bytes = BytesBuilder(copy: false);
    await for (final List<int> chunk in body) {
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }
}

class _Received {
  const _Received(this.status, this.headers, this.bytes);

  final int status;
  final Map<String, String> headers;
  final List<int> bytes;
}

/// One host's breaker: closed, open until a time, or half-open with a single
/// probe in flight.
class _Breaker {
  _Breaker(this.policy);

  final DVHttpBreakerPolicy policy;
  final Queue<(DateTime, bool)> _outcomes = Queue<(DateTime, bool)>();
  DateTime? _openUntil;
  bool _probing = false;

  /// When the breaker will next allow a request, or null to allow this one.
  ///
  /// After the cooldown exactly one request goes through, and the rest keep
  /// failing fast until it answers. Letting everyone through at once is what
  /// knocks a recovering service straight back over.
  DateTime? blockedUntil(DateTime now) {
    final DateTime? until = _openUntil;
    if (until == null) return null;
    if (now.isBefore(until) || _probing) return until;
    _probing = true;
    return null;
  }

  /// Gives back a probe slot that never reached the host.
  void release() => _probing = false;

  void record(DateTime now, {required bool failed}) {
    if (_openUntil != null) {
      _probing = false;
      if (failed) {
        _openUntil = now.add(policy.cooldown);
      } else {
        _openUntil = null;
        _outcomes.clear();
      }
      return;
    }

    _outcomes.add((now, failed));
    final DateTime horizon = now.subtract(policy.window);
    while (_outcomes.isNotEmpty && _outcomes.first.$1.isBefore(horizon)) {
      _outcomes.removeFirst();
    }
    final int total = _outcomes.length;
    final int failures =
        _outcomes.where(((DateTime, bool) o) => o.$2).length;
    if (total >= policy.minimumRequests &&
        failures / total >= policy.failureRate) {
      _openUntil = now.add(policy.cooldown);
    }
  }
}

/// At most [limit] requests in flight; the rest wait their turn in order.
class _Pool {
  _Pool(this.limit);

  final int limit;
  int _active = 0;
  final Queue<Completer<void>> _waiting = Queue<Completer<void>>();

  Future<T> run<T>(Future<T> Function() body) async {
    if (_active >= limit) {
      final Completer<void> turn = Completer<void>();
      _waiting.add(turn);
      // The slot is handed over by the request that finished, so it is not
      // counted again here.
      await turn.future;
    } else {
      _active++;
    }
    try {
      return await body();
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _active--;
      }
    }
  }
}
