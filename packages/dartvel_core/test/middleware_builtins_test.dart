// The spec lists csrf, idempotency, locale, feature flags and maintenance as
// built-in middleware. These tests drive them through MiddlewareChain with
// map-shaped requests, the same way middleware_test.dart drives the rest.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/src/middleware/middleware.dart';
import 'package:test/test.dart';

Map<String, Object?> request({
  String method = 'POST',
  String path = '/orders',
  Map<String, String> headers = const <String, String>{},
  String? url,
}) =>
    <String, Object?>{
      'method': method,
      'path': path,
      if (url != null) 'url': url,
      'headers': headers,
    };

void main() {
  group('csrf', () {
    final token = const DVCSRF().token();

    test('a state-changing request without a token is aborted', () async {
      final middleware = CommonMiddleware.csrf(issuedToken: (_) => token);

      final context = MiddlewareContext();
      await middleware(request(), context);

      expect(context.shouldContinue, isFalse);
      expect(context.data['csrfError'], contains('CSRF'));
    });

    test('the header must equal the issued token, not merely look like one',
        () async {
      // A forged token with a valid shape is exactly the attack; format
      // validation alone would wave it through.
      final middleware = CommonMiddleware.csrf(issuedToken: (_) => token);
      final forged = const DVCSRF().token();

      final context = MiddlewareContext();
      await middleware(
        request(headers: <String, String>{DVCSRF.headerName: forged}),
        context,
      );

      expect(context.shouldContinue, isFalse);
    });

    test('the issued token passes', () async {
      final middleware = CommonMiddleware.csrf(issuedToken: (_) => token);

      final context = MiddlewareContext();
      await middleware(
        request(headers: <String, String>{DVCSRF.headerName: token}),
        context,
      );

      expect(context.shouldContinue, isTrue);
    });

    test('safe methods pass without a token', () async {
      final middleware = CommonMiddleware.csrf(issuedToken: (_) => token);

      final context = MiddlewareContext();
      await middleware(request(method: 'GET'), context);

      expect(context.shouldContinue, isTrue);
    });
  });

  group('idempotency', () {
    test('a repeated key is flagged as a replay with the stored response',
        () async {
      final middleware = CommonMiddleware.idempotency();
      final headers = <String, String>{'Idempotency-Key': 'charge-1'};

      final first = MiddlewareContext();
      await middleware(request(headers: headers), first);
      expect(first.shouldContinue, isTrue);
      expect(first.data['idempotencyKey'], 'charge-1');
      (first.data['recordIdempotentResponse']! as void Function(Object?))(
        <String, Object?>{'orderId': 'o-1'},
      );

      final second = MiddlewareContext();
      await middleware(request(headers: headers), second);
      expect(second.shouldContinue, isFalse);
      expect(second.data['idempotentReplay'], isTrue);
      expect(
        second.data['idempotentResponse'],
        <String, Object?>{'orderId': 'o-1'},
      );
    });

    test('the same key on a different endpoint is a different operation',
        () async {
      final middleware = CommonMiddleware.idempotency();
      final headers = <String, String>{'Idempotency-Key': 'k'};

      await middleware(request(path: '/orders', headers: headers),
          MiddlewareContext());
      final other = MiddlewareContext();
      await middleware(request(path: '/refunds', headers: headers), other);

      expect(other.shouldContinue, isTrue);
    });

    test('require aborts a keyless request; GET never needs one', () async {
      final middleware = CommonMiddleware.idempotency(require: true);

      final post = MiddlewareContext();
      await middleware(request(), post);
      expect(post.shouldContinue, isFalse);
      expect(post.data['idempotencyError'], contains('Idempotency-Key'));

      final get = MiddlewareContext();
      await middleware(request(method: 'GET'), get);
      expect(get.shouldContinue, isTrue);
    });
  });

  group('locale', () {
    test('negotiates from Accept-Language in preference order', () async {
      final middleware = CommonMiddleware.locale(
        supported: <String>['en', 'fr', 'de'],
      );

      final context = MiddlewareContext();
      await middleware(
        request(
          method: 'GET',
          headers: <String, String>{
            'Accept-Language': 'da, fr;q=0.9, en;q=0.8',
          },
        ),
        context,
      );

      expect(context.data['locale'], 'fr');
    });

    test('a regional tag falls back to its bare language', () async {
      final middleware = CommonMiddleware.locale(supported: <String>['en']);

      final context = MiddlewareContext();
      await middleware(
        request(
          method: 'GET',
          headers: <String, String>{'Accept-Language': 'en-GB'},
        ),
        context,
      );

      expect(context.data['locale'], 'en');
    });

    test('the query parameter outranks the header', () async {
      final middleware = CommonMiddleware.locale(
        supported: <String>['en', 'de'],
      );

      final context = MiddlewareContext();
      await middleware(
        request(
          method: 'GET',
          url: 'https://example.com/page?locale=de',
          headers: <String, String>{'Accept-Language': 'en'},
        ),
        context,
      );

      expect(context.data['locale'], 'de');
    });

    test('nothing matching resolves to the fallback', () async {
      final middleware = CommonMiddleware.locale(
        supported: <String>['en', 'de'],
        fallback: 'de',
      );

      final context = MiddlewareContext();
      await middleware(
        request(
          method: 'GET',
          headers: <String, String>{'Accept-Language': 'zh'},
        ),
        context,
      );

      expect(context.data['locale'], 'de');
    });
  });

  group('featureFlags', () {
    test('resolves each flag against the request', () async {
      final middleware = CommonMiddleware.featureFlags(
        flags: <String, bool Function(Object?)>{
          'newCheckout': (Object? r) => true,
          'betaSearch': (Object? r) =>
              r is Map && (r['headers'] as Map?)?['x-beta'] == '1',
        },
      );

      final plain = MiddlewareContext();
      await middleware(request(method: 'GET'), plain);
      expect(plain.data['featureFlags'], <String>{'newCheckout'});

      final beta = MiddlewareContext();
      await middleware(
        request(method: 'GET', headers: <String, String>{'x-beta': '1'}),
        beta,
      );
      expect(
        beta.data['featureFlags'],
        <String>{'newCheckout', 'betaSearch'},
      );
    });
  });

  group('maintenance', () {
    test('aborts while down, except health checks and the bypass secret',
        () async {
      var down = true;
      final middleware = CommonMiddleware.maintenance(
        isDown: () => down,
        bypassSecret: 'let-me-in',
      );

      final blocked = MiddlewareContext();
      await middleware(request(method: 'GET', path: '/'), blocked);
      expect(blocked.shouldContinue, isFalse);
      expect(blocked.data['maintenanceError'], contains('maintenance'));

      final health = MiddlewareContext();
      await middleware(request(method: 'GET', path: '/health'), health);
      expect(health.shouldContinue, isTrue);

      final operator = MiddlewareContext();
      await middleware(
        request(
          method: 'GET',
          path: '/',
          headers: <String, String>{'x-dartvel-maintenance-bypass': 'let-me-in'},
        ),
        operator,
      );
      expect(operator.shouldContinue, isTrue);

      down = false;
      final up = MiddlewareContext();
      await middleware(request(method: 'GET', path: '/'), up);
      expect(up.shouldContinue, isTrue);
    });
  });
}
