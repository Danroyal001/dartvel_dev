// Nineteen middleware keys that changed nothing.
//
// @DVUseMiddleware([DVMiddlewares.rateLimit]) had exactly one reader in the
// repository: a validator that threw if the name was not on a whitelist. It
// checked the spelling and dropped the list. Nothing was stored, nothing was
// emitted into the generated router, and no request was ever handled
// differently for having declared any of them.
//
// The implementations were not missing. CommonMiddleware.rateLimit,
// .securityHeaders, .locale, .maintenance, .tenant, .idempotency, .csrf and
// .featureFlags are all written and all unit-tested -- through a chain built
// by hand inside their own tests. Nothing else ever built one.
//
// So this is the layer that turns a declared key into a decision, and the
// tests here are about the decision rather than the spelling.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Map<String, Object?> request({
  String method = 'GET',
  String path = '/orders',
  Map<String, String> headers = const <String, String>{},
}) =>
    <String, Object?>{
      'method': method,
      'path': path,
      'headers': headers,
      'url': 'https://shop.example.test$path',
    };

void main() {
  setUp(dvResetMiddlewareRuntime);
  tearDown(dvResetMiddlewareRuntime);

  group('which keys do something', () {
    test('a key with an implementation builds one', () {
      expect(dvMiddlewareFor('securityHeaders'), isNotNull);
      expect(dvMiddlewareFor('rateLimit'), isNotNull);
      expect(dvMiddlewareFor('tenant'), isNotNull);
    });

    test('a key with no implementation builds nothing', () {
      // cacheTags and rateLimitCheckout are declared on DVMiddlewares
      // and implemented nowhere. Returning a do-nothing middleware for them
      // would be the same silence in a new place.
      expect(dvMiddlewareFor('cacheTags'), isNull);
      expect(dvMiddlewareFor('rateLimitCheckout'), isNull);
    });

    test('every unbuilt key is named, and no key is in both sets', () {
      expect(
        dvMiddlewareKeysBuilt.intersection(dvMiddlewareKeysUnbuilt),
        isEmpty,
      );
      for (final String key in dvMiddlewareKeysBuilt) {
        expect(dvMiddlewareFor(key), isNotNull, reason: key);
      }
      for (final String key in dvMiddlewareKeysUnbuilt) {
        expect(dvMiddlewareFor(key), isNull, reason: key);
      }
    });
  });

  group('the keys the prelude enforces', () {
    test('a body limit is not run by the chain', () async {
      // It cannot be: the chain runs around the handler and the body is in
      // memory by then. The generated prelude checks before it reads, so the
      // chain skips these rather than refusing the build over them.
      expect(
        dvMiddlewareKeysAtRequest,
        containsAll(<String>['bodyLimit', 'uploadLimit']),
      );

      final DVMiddlewareResult result = await dvRunMiddlewares(
        const <String>['bodyLimit', 'uploadLimit', 'tracing'],
        request(),
      );

      expect(result.allowed, isTrue);
      expect(result.headers, isEmpty);
    });

    test('and none of the five sets overlap', () {
      // A key in two of them would be enforced twice or refused while
      // working, and which depends on the order the generator reads them.
      final List<Set<String>> sets = <Set<String>>[
        dvMiddlewareKeysBuilt,
        dvMiddlewareKeysAtRequest,
        dvMiddlewareKeysWrapping,
        dvMiddlewareKeysAlwaysOn,
        dvMiddlewareKeysUnbuilt,
      ];
      for (int a = 0; a < sets.length; a++) {
        for (int b = a + 1; b < sets.length; b++) {
          expect(sets[a].intersection(sets[b]), isEmpty,
              reason: 'sets $a and $b share a key');
        }
      }
    });
  });

  group('running a route\'s chain', () {
    test('an empty chain allows the request', () async {
      final DVMiddlewareResult result =
          await dvRunMiddlewares(const <String>[], request());
      expect(result.allowed, isTrue);
      expect(result.headers, isEmpty);
    });

    test('securityHeaders come back as response headers', () async {
      // The middleware puts them in context.data, which nothing downstream
      // read. Headers that never reach a response are a comment.
      final DVMiddlewareResult result =
          await dvRunMiddlewares(const <String>['securityHeaders'], request());

      expect(result.allowed, isTrue);
      expect(result.headers['X-Frame-Options'], 'DENY');
      expect(result.headers['X-Content-Type-Options'], 'nosniff');
    });

    test('a configured policy comes back as a header', () async {
      DVMiddlewareSettings.contentSecurityPolicy = "default-src 'self'";

      final DVMiddlewareResult result =
          await dvRunMiddlewares(const <String>['csp'], request());

      expect(result.allowed, isTrue);
      expect(result.headers['Content-Security-Policy'], "default-src 'self'");
    });

    test('no configured policy sends no header rather than an empty one', () {
      // An empty Content-Security-Policy is not "no policy": browsers read it
      // as one that allows nothing, which breaks the page. The build refuses
      // this combination, and this is the runtime refusing to invent a
      // header if it ever reaches here anyway.
      expect(DVMiddlewareSettings.contentSecurityPolicy, isNull);

      expectLater(
        dvRunMiddlewares(const <String>['cacheTags'], request()),
        completion(
          isA<DVMiddlewareResult>().having(
            (DVMiddlewareResult r) => r.headers,
            'headers',
            isEmpty,
          ),
        ),
      );
    });

    test('a rate limit refuses with 429 once the window is full', () async {
      DVMiddlewareSettings.rateLimitMaxRequests = 2;

      final Map<String, Object?> caller = request(
        headers: <String, String>{'x-real-ip': '198.51.100.7'},
      );
      expect(
        (await dvRunMiddlewares(const <String>['rateLimit'], caller)).allowed,
        isTrue,
      );
      expect(
        (await dvRunMiddlewares(const <String>['rateLimit'], caller)).allowed,
        isTrue,
      );

      final DVMiddlewareResult third =
          await dvRunMiddlewares(const <String>['rateLimit'], caller);
      expect(third.allowed, isFalse);
      expect(third.status, 429);
    });

    test('the counter survives between requests', () async {
      // Building a fresh CommonMiddleware.rateLimit per request would put the
      // counter in a closure that is thrown away, so the limit would never be
      // reached and the test above would be the only thing that ever saw one.
      DVMiddlewareSettings.rateLimitMaxRequests = 1;
      final Map<String, Object?> caller = request(
        headers: <String, String>{'x-real-ip': '203.0.113.9'},
      );

      await dvRunMiddlewares(const <String>['rateLimit'], caller);
      expect(
        (await dvRunMiddlewares(const <String>['rateLimit'], caller)).allowed,
        isFalse,
      );
    });

    test('a different caller is not rate limited by the first', () async {
      DVMiddlewareSettings.rateLimitMaxRequests = 1;
      await dvRunMiddlewares(
        const <String>['rateLimit'],
        request(headers: <String, String>{'x-real-ip': '198.51.100.1'}),
      );

      final DVMiddlewareResult other = await dvRunMiddlewares(
        const <String>['rateLimit'],
        request(headers: <String, String>{'x-real-ip': '198.51.100.2'}),
      );
      expect(other.allowed, isTrue);
    });

    test('maintenance refuses with 503 and lets health through', () async {
      DVMiddlewareSettings.maintenanceIsDown = () => true;

      final DVMiddlewareResult refused =
          await dvRunMiddlewares(const <String>['maintenance'], request());
      expect(refused.allowed, isFalse);
      expect(refused.status, 503);

      final DVMiddlewareResult health = await dvRunMiddlewares(
        const <String>['maintenance'],
        request(path: '/health'),
      );
      expect(health.allowed, isTrue);
    });

    test('a refusal stops the chain before the rest of it runs', () async {
      // securityHeaders after a maintenance refusal would otherwise decorate
      // a response that is not being sent, and worse, the next middleware in
      // a real chain might be the one that charges a card.
      DVMiddlewareSettings.maintenanceIsDown = () => true;

      final DVMiddlewareResult result = await dvRunMiddlewares(
        const <String>['maintenance', 'securityHeaders'],
        request(),
      );

      expect(result.allowed, isFalse);
      expect(result.headers, isEmpty);
    });

    test('the refusal message never repeats the request', () async {
      // These reach a client. A message quoting the path or a header is a
      // reflection, and the middleware layer is the wrong place to learn
      // that lesson twice.
      DVMiddlewareSettings.maintenanceIsDown = () => true;
      final DVMiddlewareResult result = await dvRunMiddlewares(
        const <String>['maintenance'],
        request(path: '/secret-admin-tool'),
      );

      expect(result.message, isNot(contains('secret-admin-tool')));
      expect(result.message, isNotEmpty);
    });

    test('locale resolution reaches the handler as data', () async {
      DVMiddlewareSettings.locales = <String>['en', 'fr'];
      final DVMiddlewareResult result = await dvRunMiddlewares(
        const <String>['locale'],
        request(headers: <String, String>{'accept-language': 'fr-CH, fr;q=0.9'}),
      );

      expect(result.allowed, isTrue);
      expect(result.data['locale'], 'fr');
    });

    test('a declared key nobody implemented refuses the build, not the '
        'request', () async {
      // Running a chain containing cacheTags must not quietly serve the
      // request as though tags had been recorded. The generator rejects it,
      // and this is the runtime saying the same thing rather than shrugging.
      await expectLater(
        dvRunMiddlewares(const <String>['cacheTags'], request()),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
