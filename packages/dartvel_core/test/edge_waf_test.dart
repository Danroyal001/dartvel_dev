import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Map<String, Object?> request({
  String method = 'POST',
  String path = '/admin/users',
  String? country,
}) =>
    <String, Object?>{
      'method': method,
      'path': path,
      'headers': <String, String>{
        if (country != null) 'x-test-country': country,
      },
    };

const adminFromOutside = DVWafRule(
  name: 'block-admin-from-outside',
  paths: <String>['/admin/**'],
  methods: <String>['POST', 'PUT', 'DELETE'],
  from: DVWafSource.notIn(<String>['GB', 'IE']),
  action: DVWafAction.refuse,
);

Future<MiddlewareContext> run(DVWaf waf, Object? req) async {
  final context = MiddlewareContext();
  await waf.middleware()(req, context);
  return context;
}

void main() {
  final fromHeader = DVWaf.countryHeader('x-test-country');

  group('matching', () {
    test('the rule in the spec refuses a write to /admin from outside',
        () async {
      final waf = DVWaf(const <DVWafRule>[adminFromOutside],
          countryOf: fromHeader);
      final context = await run(waf, request(country: 'US'));
      expect(context.shouldContinue, isFalse);
      expect(context.data['wafError'], isNotNull);
      expect(context.data['wafRule'], 'block-admin-from-outside');
      expect(context.data['diagnostic'], 'DV-EDGE-003');
    });

    test('allows the same write from an allowed country, in any case',
        () async {
      final waf = DVWaf(const <DVWafRule>[adminFromOutside],
          countryOf: fromHeader);
      expect((await run(waf, request(country: 'gb'))).shouldContinue, isTrue);
    });

    test('allows a method the rule does not name', () async {
      final waf = DVWaf(const <DVWafRule>[adminFromOutside],
          countryOf: fromHeader);
      expect(
        (await run(waf, request(method: 'get', country: 'US')))
            .shouldContinue,
        isTrue,
      );
      expect(
        (await run(waf, request(method: 'delete', country: 'US')))
            .shouldContinue,
        isFalse,
        reason: 'methods match whatever case the request uses',
      );
    });

    test('an unknown country is outside every allow-list and inside no '
        'block-list', () async {
      final waf = DVWaf(const <DVWafRule>[
        adminFromOutside,
        DVWafRule(
          name: 'block-us-reports',
          paths: <String>['/reports/**'],
          from: DVWafSource.within(<String>['US']),
        ),
      ], countryOf: fromHeader);
      expect((await run(waf, request())).shouldContinue, isFalse);
      expect(
        (await run(waf, request(path: '/reports/1'))).shouldContinue,
        isTrue,
      );
    });

    test('with no country resolver, the country is unknown', () async {
      final waf = DVWaf(const <DVWafRule>[adminFromOutside]);
      expect((await run(waf, request(country: 'GB'))).shouldContinue, isFalse,
          reason: 'a header nobody configured must not be trusted');
    });

    test('a country resolver that throws is an unknown country, not a crash',
        () async {
      final waf = DVWaf(const <DVWafRule>[adminFromOutside],
          countryOf: (_) => throw StateError('geo lookup down'));
      expect((await run(waf, request())).shouldContinue, isFalse);
    });

    test('a path is normalised before matching, so no spelling walks past',
        () async {
      final waf = DVWaf(const <DVWafRule>[adminFromOutside],
          countryOf: fromHeader);
      for (final path in <String>[
        '/admin',
        '/admin/',
        '//admin/users',
        '/admin/./users',
        '/public/../admin/users',
        '/%61dmin/users',
        '/admin%2Fusers',
        '/admin/users?debug=1',
      ]) {
        expect(
          (await run(waf, request(path: path, country: 'US'))).shouldContinue,
          isFalse,
          reason: '$path reaches /admin',
        );
      }
      final uri = <String, Object?>{
        'method': 'POST',
        'url': 'https://example.com//admin/users',
        'headers': <String, String>{'x-test-country': 'US'},
      };
      expect((await run(waf, uri)).shouldContinue, isFalse);
    });

    test('/admin/** does not match /administrator', () async {
      final waf = DVWaf(const <DVWafRule>[adminFromOutside],
          countryOf: fromHeader);
      expect(
        (await run(waf, request(path: '/administrator', country: 'US')))
            .shouldContinue,
        isTrue,
      );
    });

    test('* matches one segment and ** any number', () {
      final waf = DVWaf(const <DVWafRule>[
        DVWafRule(name: 'one', paths: <String>['/api/*/secret']),
      ]);
      expect(waf.decide(method: 'GET', path: '/api/v1/secret').refused,
          isTrue);
      expect(waf.decide(method: 'GET', path: '/api/v1/x/secret').refused,
          isFalse);
      expect(waf.decide(method: 'GET', path: '/api/secret').refused, isFalse);
    });

    test('the first matching rule decides, so an allow rule is an exception',
        () async {
      final waf = DVWaf(const <DVWafRule>[
        DVWafRule(
          name: 'admin-health',
          paths: <String>['/admin/health'],
          action: DVWafAction.allow,
        ),
        adminFromOutside,
      ], countryOf: fromHeader);
      expect(
        (await run(waf, request(path: '/admin/health', country: 'US')))
            .shouldContinue,
        isTrue,
      );
      expect(
        (await run(waf, request(path: '/admin/users', country: 'US')))
            .shouldContinue,
        isFalse,
      );
    });

    test('two rules may not share a name', () {
      expect(
        () => DVWaf(const <DVWafRule>[adminFromOutside, adminFromOutside]),
        throwsArgumentError,
      );
    });
  });

  group('adapters', () {
    test('the same rules are pushed to a platform adapter unchanged',
        () async {
      final adapter = DVRecordingWafAdapter();
      final waf = DVWaf(const <DVWafRule>[adminFromOutside], adapter: adapter);
      await waf.deploy();
      expect(adapter.installed, const <DVWafRule>[adminFromOutside]);
    });

    test('a failed install is an error, and the middleware still enforces',
        () async {
      final adapter = DVRecordingWafAdapter(failWith: StateError('CDN 503'));
      final waf = DVWaf(const <DVWafRule>[adminFromOutside],
          adapter: adapter, countryOf: fromHeader);
      await expectLater(waf.deploy(), throwsStateError);
      expect((await run(waf, request(country: 'US'))).shouldContinue, isFalse);
    });
  });

  group('DV-EDGE-006', () {
    test('a rule that matches every request is reported', () {
      final waf = DVWaf(const <DVWafRule>[
        DVWafRule(name: 'everything'),
        adminFromOutside,
      ]);
      final findings = waf.lint();
      expect(findings.map((f) => f.rule), <String>['everything']);
      expect(findings.single.code, 'DV-EDGE-006');
    });

    test('a rule that has matched nothing for ninety days is reported',
        () async {
      var now = DateTime.utc(2026, 1, 1);
      final waf = DVWaf(const <DVWafRule>[
        adminFromOutside,
        DVWafRule(name: 'never-hit', paths: <String>['/wp-login.php']),
      ], countryOf: fromHeader, clock: () => now);

      await run(waf, request(country: 'US'));
      now = now.add(const Duration(days: 89));
      expect(waf.lint(), isEmpty);

      now = now.add(const Duration(days: 2));
      expect(
        waf.lint().map((f) => f.rule),
        unorderedEquals(<String>['block-admin-from-outside', 'never-hit']),
      );

      await run(waf, request(country: 'US'));
      expect(waf.lint().map((f) => f.rule), <String>['never-hit']);
    });
  });
}
