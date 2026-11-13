// One session across an application's own hosts.
//
// The session cookie was `__Host-dv_session`, which a browser locks to the
// exact host that set it. An application whose dartvel.hosts serves
// example.test, tools.example.test and *.tools.example.test signed somebody
// in on example.test and showed them signed out on x.tools.example.test --
// the same application, the same binary, the same account.
//
// The silent failures this covers:
//  * a Domain attribute naming a public suffix (co.uk, github.io), which a
//    browser drops without a word, or which would hand the session to
//    strangers if one did not;
//  * a domain chosen as "the last two labels";
//  * a redirecting host, or a host on another registrable domain, given the
//    session cookie;
//  * a request from a host the application does not serve -- a sibling
//    somebody else runs under the same domain -- accepted as the
//    application's own;
//  * a person signed in under the old `__Host-` cookie signed out by the
//    upgrade, or kept signed in on one host after signing out on another.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String _token = 'dvs_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const String _other = 'dvs_BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';

DVHosts _hosts(Map<String, Object?> yaml) {
  final DVHostsParse parsed =
      DVHosts.parse(yaml, defaultSiteUrl: 'https://example.test');
  if (parsed.problems.isNotEmpty) fail('${parsed.problems}');
  return parsed.hosts;
}

final Map<String, Object?> _siblings = <String, Object?>{
  'example.test': <String, Object?>{},
  'tools.example.test': <String, Object?>{
    'mount': '/tools',
    'siteUrl': 'https://tools.example.test',
  },
  '*.tools.example.test': <String, Object?>{
    'mount': '/tools/{label}',
    'siteUrl': 'https://{label}.tools.example.test',
  },
  'old.example.test': <String, Object?>{'redirect': 'https://example.test/'},
  'example.org': <String, Object?>{'redirect': 'https://example.test/'},
};

DVSessionScope _resolved(Map<String, Object?> hosts,
    [Map<String, Object?>? auth]) {
  final DVSessionScopeResolution resolution =
      DVSessionScope.resolve(hosts: _hosts(hosts), auth: auth);
  if (resolution.problems.isNotEmpty) fail('${resolution.problems}');
  return resolution.scope;
}

List<String> _problems(Map<String, Object?> hosts, Map<String, Object?>? auth) =>
    DVSessionScope.resolve(hosts: _hosts(hosts), auth: auth).problems;

void main() {
  group('which scope an application gets', () {
    test('hosts sharing a registrable domain share the session', () {
      final DVSessionScope scope = _resolved(_siblings);
      expect(scope.domain, 'example.test');
      expect(scope.covers('example.test'), isTrue);
      expect(scope.covers('tools.example.test'), isTrue);
      expect(scope.covers('x.tools.example.test'), isTrue);
    });

    test('a redirecting host, or one nothing declares, is not covered', () {
      final DVSessionScope scope = _resolved(_siblings);
      expect(scope.covers('old.example.test'), isFalse);
      expect(scope.covers('example.org'), isFalse);
      expect(scope.covers('evil.example.test'), isFalse);
      expect(scope.covers('a.b.tools.example.test'), isFalse);
      expect(scope.covers(null), isFalse);
    });

    test('one host keeps the host-only cookie', () {
      final DVSessionScope scope = _resolved(<String, Object?>{
        'example.test': <String, Object?>{},
        'example.org': <String, Object?>{'redirect': 'https://example.test/'},
      });
      expect(scope.domain, isNull);
      expect(DVSessionScope.resolve(hosts: DVHosts.none).scope.domain, isNull);
    });

    test('hosts on different registrable domains do not span them', () {
      // Two GitHub Pages sites are two registrable domains: github.io is a
      // public suffix, not a parent anybody may set a cookie for.
      final DVSessionScope pages = _resolved(<String, Object?>{
        'alice.github.io': <String, Object?>{
          'siteUrl': 'https://alice.github.io',
        },
        'bob.github.io': <String, Object?>{
          'mount': '/bob',
          'siteUrl': 'https://bob.github.io',
        },
      });
      expect(pages.domain, isNull);
    });

    test('mixed domains share the primary host\'s, and the rest stay '
        'host-only', () {
      final DVSessionScope scope = _resolved(<String, Object?>{
        'example.test': <String, Object?>{},
        'docs.example.test': <String, Object?>{
          'mount': '/docs',
          'siteUrl': 'https://docs.example.test',
        },
        'example.net': <String, Object?>{
          'mount': '/net',
          'siteUrl': 'https://example.net',
        },
      });
      expect(scope.domain, 'example.test');
      expect(scope.covers('docs.example.test'), isTrue);
      expect(scope.covers('example.net'), isFalse);
    });

    test('a wildcard under a public suffix shares nothing', () {
      final DVSessionScope scope = _resolved(<String, Object?>{
        'example.test': <String, Object?>{},
        '*.github.io': <String, Object?>{
          'mount': '/pages/{label}',
          'siteUrl': 'https://{label}.github.io',
        },
      });
      expect(scope.domain, isNull);
    });

    test('sessionScope: host keeps every host on its own cookie', () {
      final DVSessionScope scope =
          _resolved(_siblings, <String, Object?>{'sessionScope': 'host'});
      expect(scope.domain, isNull);
      expect(scope.covers('x.tools.example.test'), isFalse);
    });

    test('sessionDomain names the domain explicitly', () {
      final DVSessionScope scope = _resolved(<String, Object?>{
        'app.shop.example.test': <String, Object?>{
          'siteUrl': 'https://app.shop.example.test',
        },
        'admin.shop.example.test': <String, Object?>{
          'mount': '/admin',
          'siteUrl': 'https://admin.shop.example.test',
        },
      }, <String, Object?>{'sessionDomain': 'shop.example.test'});
      expect(scope.domain, 'shop.example.test');
      expect(scope.covers('admin.shop.example.test'), isTrue);
    });
  });

  group('what the build refuses, and says why', () {
    test('a public suffix', () {
      final List<String> problems = _problems(<String, Object?>{
        'shop.co.uk': <String, Object?>{'siteUrl': 'https://shop.co.uk'},
        'admin.shop.co.uk': <String, Object?>{
          'mount': '/admin',
          'siteUrl': 'https://admin.shop.co.uk',
        },
      }, <String, Object?>{'sessionDomain': 'co.uk'});
      expect(problems.join(), contains('dartvel.auth.sessionDomain'));
      expect(problems.join(), contains('public suffix'));
    });

    test('a domain that is not a parent of every host', () {
      final List<String> problems = _problems(
          _siblings, <String, Object?>{'sessionDomain': 'tools.example.test'});
      expect(problems.join(), contains('example.test'));
      expect(problems.join(), contains('not under'));
    });

    test('a scope that is not one, and a contradiction', () {
      expect(
        _problems(_siblings, <String, Object?>{'sessionScope': 'everywhere'})
            .join(),
        contains('dartvel.auth.sessionScope'),
      );
      expect(
        _problems(_siblings, <String, Object?>{
          'sessionScope': 'host',
          'sessionDomain': 'example.test',
        }).join(),
        contains('sessionScope: host'),
      );
    });

    test('a domain with no hosts to span', () {
      expect(
        DVSessionScope.resolve(
          hosts: DVHosts.none,
          auth: <String, Object?>{'sessionDomain': 'example.test'},
        ).problems.join(),
        contains('dartvel.hosts'),
      );
    });

    test('at start, too: a scope built by hand is checked', () {
      expect(
        () => const DVSessionScope.site(
          domain: 'co.uk',
          hosts: <String>['shop.co.uk'],
        ).validate(),
        throwsA(isA<DVSessionConfigError>()),
      );
      expect(
        () => const DVSessionScope.site(
          domain: 'example.test',
          hosts: <String>['example.org'],
        ).validate(),
        throwsA(isA<DVSessionConfigError>()),
      );
      const DVSessionScope.site(
        domain: 'example.test',
        hosts: <String>['example.test', '*.tools.example.test'],
      ).validate();
    });
  });

  group('the cookie', () {
    final DVSessionCookie spanning = DVSessionCookie(scope: _resolved(_siblings));
    const DVSessionCookie single = DVSessionCookie();

    test('on a covered host is __Secure- with the domain', () {
      expect(
        spanning.header(_token, development: false, host: 'x.tools.example.test'),
        '__Secure-dv_session=$_token; Domain=example.test; Path=/; HttpOnly; '
        'Secure; SameSite=Lax',
      );
    });

    test('on a host the scope does not cover stays __Host-', () {
      for (final String host in <String>['example.org', 'old.example.test']) {
        expect(
          spanning.header(_token, development: false, host: host),
          '__Host-dv_session=$_token; Path=/; HttpOnly; Secure; SameSite=Lax',
          reason: host,
        );
      }
    });

    test('of a single-host application is exactly what it was', () {
      expect(
        single.header(_token, development: false, host: 'example.test'),
        '__Host-dv_session=$_token; Path=/; HttpOnly; Secure; SameSite=Lax',
      );
      expect(single.header(_token, development: false),
          '__Host-dv_session=$_token; Path=/; HttpOnly; Secure; SameSite=Lax');
    });

    test('in development, or over plain local http, carries no domain', () {
      expect(
        spanning.header(_token, development: true, host: 'example.test'),
        'dv_session=$_token; Path=/; HttpOnly; SameSite=Lax',
      );
    });

    test('is read under the new name first, the old one second, and no '
        'bare name', () {
      expect(
        spanning.carried('__Host-dv_session=$_other; __Secure-dv_session=$_token',
            development: false, host: 'example.test'),
        (token: _token, legacy: false),
      );
      expect(
        spanning.carried('__Host-dv_session=$_other',
            development: false, host: 'example.test'),
        (token: _other, legacy: true),
      );
      expect(
        spanning.carried('dv_session=$_token',
            development: false, host: 'example.test'),
        isNull,
      );
      // A host the scope does not cover never reads the domain cookie.
      expect(
        spanning.carried('__Secure-dv_session=$_token',
            development: false, host: 'example.org'),
        isNull,
      );
    });

    test('carried under the old name moves to the new one, same token', () {
      expect(
        spanning.migration(
          '__Host-dv_session=$_token',
          development: false,
          host: 'tools.example.test',
        ),
        <String>[
          '__Secure-dv_session=$_token; Domain=example.test; Path=/; '
              'HttpOnly; Secure; SameSite=Lax',
          '__Host-dv_session=; Path=/; HttpOnly; Secure; SameSite=Lax; '
              'Max-Age=0',
        ],
      );
      // Alongside the new one, the old cookie is only cleared.
      expect(
        spanning.migration(
          '__Secure-dv_session=$_token; __Host-dv_session=$_other',
          development: false,
          host: 'example.test',
        ),
        <String>[
          '__Host-dv_session=; Path=/; HttpOnly; Secure; SameSite=Lax; '
              'Max-Age=0',
        ],
      );
      expect(
        spanning.migration('__Secure-dv_session=$_token',
            development: false, host: 'example.test'),
        isEmpty,
      );
      expect(
        single.migration('__Host-dv_session=$_token',
            development: false, host: 'example.test'),
        isEmpty,
      );
    });

    test('clearing it clears both names', () {
      expect(
        spanning.clearHeaders(development: false, host: 'x.tools.example.test'),
        <String>[
          '__Secure-dv_session=; Domain=example.test; Path=/; HttpOnly; '
              'Secure; SameSite=Lax; Max-Age=0',
          '__Host-dv_session=; Path=/; HttpOnly; Secure; SameSite=Lax; '
              'Max-Age=0',
        ],
      );
      expect(
        single.clearHeaders(development: false, host: 'example.test'),
        <String>[
          '__Host-dv_session=; Path=/; HttpOnly; Secure; SameSite=Lax; '
              'Max-Age=0',
        ],
      );
    });
  });

  group('whose requests are the application\'s own', () {
    final DVSessionScope scope = _resolved(_siblings);

    test('the application\'s own hosts, any of them', () {
      for (final String origin in <String>[
        'https://example.test',
        'https://tools.example.test',
        'https://x.tools.example.test',
        'https://x.tools.example.test:8443',
      ]) {
        expect(scope.allowsOrigin(origin, host: 'example.test'), isTrue,
            reason: origin);
      }
    });

    test('and nothing else', () {
      for (final String origin in <String>[
        'https://evil.example.test',
        'https://old.example.test',
        'https://example.test.evil.com',
        'https://xexample.test',
        'https://a.b.tools.example.test',
        'http://example.test',
        'null',
        'not a url',
      ]) {
        expect(scope.allowsOrigin(origin, host: 'example.test'), isFalse,
            reason: origin);
      }
    });

    test('a request with no Origin is judged by its CSRF token alone', () {
      expect(scope.allowsOrigin(null, host: 'example.test'), isTrue);
    });

    test('the origin the request was made to is always its own', () {
      expect(scope.allowsOrigin('https://10.0.0.5', host: '10.0.0.5'), isTrue);
      expect(scope.allowsOrigin('http://localhost:8080', host: 'localhost:8080'),
          isTrue);
    });

    test('a deployment served over plain http is still its own origin', () {
      // No TLS anywhere: the page and the request are both http. Refusing
      // it would break every form on a staging box with hosts declared.
      expect(
        scope.allowsOrigin('http://10.0.0.5:8080',
            host: '10.0.0.5:8080', secure: false),
        isTrue,
      );
      expect(
        scope.allowsOrigin('http://example.test',
            host: 'example.test', secure: false),
        isTrue,
      );
      // An http page posting to the https site is not the same origin, and
      // an http sibling is never the application's own.
      expect(
        scope.allowsOrigin('http://example.test',
            host: 'example.test', secure: true),
        isFalse,
      );
      expect(
        scope.allowsOrigin('http://tools.example.test',
            host: 'example.test', secure: false),
        isFalse,
      );
    });

    test('origins dartvel.server.cors names are allowed as well', () {
      expect(
        scope.allowsOrigin('https://partner.example.com',
            host: 'example.test',
            alsoAllowed: <String>['https://partner.example.com']),
        isTrue,
      );
    });

    test('an application with no hosts is not checked here', () {
      expect(
        const DVSessionScope.host()
            .allowsOrigin('https://anything.example', host: 'example.test'),
        isTrue,
      );
    });
  });

  group('the session stage', () {
    late DVSessions sessions;
    late DVSessionAuthentication stage;
    late String token;

    setUp(() async {
      sessions = DVSessions(store: DVMemorySessionStore());
      token = (await sessions.create('ada', tenant: 'default')).token;
      stage = DVSessionAuthentication(
        sessions: sessions,
        cookie: DVSessionCookie(scope: _resolved(_siblings)),
      );
    });

    test('authenticates the old cookie and moves it to the new one', () async {
      final DVSessionAuthenticationResult result = await stage.authenticate(
        cookie: '__Host-dv_session=$token',
        tenant: 'default',
        host: 'x.tools.example.test',
      );
      expect(result.principal?.userId, 'ada');
      expect(result.setCookies.first,
          startsWith('__Secure-dv_session=$token; Domain=example.test'));
      expect(result.setCookies.last, startsWith('__Host-dv_session=;'));
    });

    test('authenticates the domain cookie on a sibling host', () async {
      final DVSessionAuthenticationResult result = await stage.authenticate(
        cookie: '__Secure-dv_session=$token',
        tenant: 'default',
        host: 'tools.example.test',
      );
      expect(result.principal?.userId, 'ada');
      expect(result.setCookies, isEmpty);
    });

    test('refusing a revoked session clears both cookies', () async {
      final DVSession session =
          (await sessions.check(token, tenant: 'default')).session!;
      await sessions.revoke(session.id);
      final DVSessionAuthenticationResult result = await stage.authenticate(
        cookie: '__Secure-dv_session=$token',
        tenant: 'default',
        host: 'example.test',
      );
      expect(result.status, 401);
      expect(result.setCookies, hasLength(2));
      expect(result.setCookies.first, contains('Domain=example.test'));
      expect(result.setCookies.first, contains('Max-Age=0'));
      expect(result.setCookies.last, startsWith('__Host-dv_session=;'));
    });
  });
}
