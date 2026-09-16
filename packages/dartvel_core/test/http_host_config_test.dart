// The dartvel.http.hosts block, read strictly.
//
// The generator reads this block and so does the running application, through
// the same reader. A key it skips is the silent failure: `retry:` for
// `retries:` builds, runs, and retries a payment gateway three times on the
// default policy while the pubspec says something else. So anything the
// reader does not understand is refused, naming the key.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Matcher _refusedNaming(String key) => throwsA(
      isA<ArgumentError>().having((e) => '${e.message}', 'message', contains(key)),
    );

void main() {
  const DVHttp http = DVHttp();

  setUp(DVHttp.reset);
  tearDown(DVHttp.reset);

  Map<String, Object?> hosts(Map<String, Object?> paystack) => <String, Object?>{
        'hosts': <String, Object?>{'paystack': paystack},
      };

  test('a misspelt key in a host is refused, naming it', () {
    expect(
      () => http.declareFromConfig(hosts(<String, Object?>{
        'baseUrl': 'https://api.paystack.co',
        'retry': <String, Object?>{'attempts': 5},
      })),
      _refusedNaming('dartvel.http.hosts.paystack.retry'),
    );
  });

  test('a misspelt key inside a nested block is refused, naming it', () {
    for (final (String block, Map<String, Object?> body) in <(String, Map<String, Object?>)>[
      ('retries.attempt', <String, Object?>{'attempt': 5}),
      ('circuitBreaker.cooldwn', <String, Object?>{'cooldwn': '60s'}),
      ('pool.max', <String, Object?>{'max': 8}),
    ]) {
      final String parent = block.split('.').first;
      expect(
        () => http.declareFromConfig(hosts(<String, Object?>{
          'baseUrl': 'https://api.paystack.co',
          parent: body,
        })),
        _refusedNaming('dartvel.http.hosts.paystack.$block'),
        reason: block,
      );
    }
  });

  test('a key beside hosts is refused', () {
    expect(
      () => http.declareFromConfig(<String, Object?>{
        'host': <String, Object?>{},
      }),
      _refusedNaming('dartvel.http.host'),
    );
  });

  test('a value that would have fallen back to a default is refused', () {
    // Each of these used to be read as the default: an attempts count that is
    // not a number retried three times, a backoff nobody implements was
    // constant, and a jitter written as a string was on.
    for (final (String key, Map<String, Object?> body) in <(String, Map<String, Object?>)>[
      ('retries.attempts', <String, Object?>{'retries': <String, Object?>{'attempts': 'many'}}),
      ('retries.attempts', <String, Object?>{'retries': <String, Object?>{'attempts': 0}}),
      ('retries.backoff', <String, Object?>{'retries': <String, Object?>{'backoff': 'linear'}}),
      ('retries.jitter', <String, Object?>{'retries': <String, Object?>{'jitter': 'yes'}}),
      ('circuitBreaker.failureRate', <String, Object?>{'circuitBreaker': <String, Object?>{'failureRate': 2}}),
      ('pool.maxConcurrent', <String, Object?>{'pool': <String, Object?>{'maxConcurrent': 'eight'}}),
      ('retries', <String, Object?>{'retries': 3}),
    ]) {
      expect(
        () => http.declareFromConfig(hosts(<String, Object?>{
          'baseUrl': 'https://api.paystack.co',
          ...body,
        })),
        _refusedNaming('dartvel.http.hosts.paystack.$key'),
        reason: '$body',
      );
    }
  });

  test('a baseUrl that is not an absolute http(s) URL is refused', () {
    for (final String baseUrl in <String>[
      'api.paystack.co',
      '/v1',
      'ftp://files.example.com',
      'https://api.paystack.co/v1?key=secret',
    ]) {
      expect(
        () => http.declareFromConfig(hosts(<String, Object?>{'baseUrl': baseUrl})),
        _refusedNaming('dartvel.http.hosts.paystack.baseUrl'),
        reason: baseUrl,
      );
    }
  });

  test('the block the specification writes is accepted whole', () {
    http.declareFromConfig(hosts(<String, Object?>{
      'baseUrl': 'https://api.paystack.co',
      'auth': <String, Object?>{'bearer': 'PAYSTACK_SECRET_KEY'},
      'timeout': '10s',
      'retries': <String, Object?>{
        'attempts': 3,
        'backoff': 'exponential',
        'jitter': true,
      },
      'circuitBreaker': <String, Object?>{
        'failureRate': 0.5,
        'window': '30s',
        'cooldown': '60s',
      },
      'pool': <String, Object?>{'maxConcurrent': 8},
    }));
    final DVHttpHostConfig config = http.host('paystack').config;
    expect(config.bearerSecret, 'PAYSTACK_SECRET_KEY');
    expect(config.retries.exponential, isTrue);
    expect(config.maxConcurrent, 8);
  });

  test('backoff: constant is the other backoff there is', () {
    http.declareFromConfig(hosts(<String, Object?>{
      'baseUrl': 'https://api.paystack.co',
      'retries': <String, Object?>{'backoff': 'constant'},
    }));
    expect(http.host('paystack').config.retries.exponential, isFalse);
  });
}
