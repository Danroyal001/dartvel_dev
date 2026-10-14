import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/framework.dart' show dvRenderedPageKey;
import 'package:test/test.dart';

void main() {
  group('dvNormalizeHost', () {
    test('normalises ASCII case, ports, whitespace and trailing dots', () {
      expect(dvNormalizeHost('  EXAMPLE.COM:8080.  '), 'example.com');
      expect(dvNormalizeHost('tools.sigmadev.digital:443'), 'tools.sigmadev.digital');
      expect(dvNormalizeHost('Sigmadev.Digital.'), 'sigmadev.digital');
    });

    test('rejects invalid hostnames', () {
      expect(dvNormalizeHost(''), isNull);
      expect(dvNormalizeHost(null), isNull);
      expect(dvNormalizeHost('-bad.com'), isNull);
      expect(dvNormalizeHost('bad-.com'), isNull);
      expect(dvNormalizeHost('bad..com'), isNull);
      expect(dvNormalizeHost('bad/com'), isNull);
      expect(dvNormalizeHost('bad:port:extra'), isNull);
    });
  });

  group('dvExtractHost', () {
    test('extracts Host header when no proxy is configured', () {
      final host = dvExtractHost(
        {'host': 'sigmadev.digital:80'},
        remoteAddress: '192.168.1.1',
      );
      expect(host, 'sigmadev.digital');
    });

    test('ignores untrusted X-Forwarded-Host from untrusted remote address', () {
      final host = dvExtractHost(
        {
          'host': 'sigmadev.digital',
          'x-forwarded-host': 'attacker.com',
        },
        trustedProxies: {'10.0.0.1'},
        remoteAddress: '192.168.1.50',
      );
      expect(host, 'sigmadev.digital');
    });

    test('trusts X-Forwarded-Host from explicitly configured trusted proxy', () {
      final host = dvExtractHost(
        {
          'host': 'backend.internal',
          'x-forwarded-host': 'tools.sigmadev.digital, proxy1.internal',
        },
        trustedProxies: {'10.0.0.1'},
        remoteAddress: '10.0.0.1:45678',
      );
      expect(host, 'tools.sigmadev.digital');
    });

    test('trusts loopback when trustLoopback is enabled', () {
      final host = dvExtractHost(
        {
          'host': '127.0.0.1:8740',
          'x-forwarded-host': 'sigmadev.digital',
        },
        trustLoopback: true,
        remoteAddress: '127.0.0.1:54321',
      );
      expect(host, 'sigmadev.digital');
    });
  });

  group('dvMatchHost', () {
    const config = DVHostRoutingConfig(
      entries: [
        DVHostEntry(
          pattern: 'sigmadev.digital',
          siteUrl: 'https://sigmadev.digital',
        ),
        const DVHostEntry(
          pattern: 'tools.sigmadev.digital',
          siteUrl: 'https://tools.sigmadev.digital',
          mount: '/tools',
        ),
        const DVHostEntry(
          pattern: '*.tools.sigmadev.digital',
          siteUrl: 'https://{slug}.tools.sigmadev.digital',
          mount: '/tools/{slug}',
        ),
      ],
    );

    test('matches exact host', () {
      final match1 = dvMatchHost('sigmadev.digital', config);
      expect(match1, isNotNull);
      expect(match1!.entry.pattern, 'sigmadev.digital');
      expect(match1.siteUrl, 'https://sigmadev.digital');
      expect(dvResolveHostPath(match1, '/'), '/');
      expect(dvResolveHostPath(match1, '/about'), '/about');

      final match2 = dvMatchHost('tools.sigmadev.digital', config);
      expect(match2, isNotNull);
      expect(match2!.entry.pattern, 'tools.sigmadev.digital');
      expect(match2.siteUrl, 'https://tools.sigmadev.digital');
      expect(dvResolveHostPath(match2, '/'), '/tools');
      expect(dvResolveHostPath(match2, '/categories'), '/tools/categories');
    });

    test('matches single-label wildcard with capture', () {
      final match = dvMatchHost('base64-encode.tools.sigmadev.digital', config);
      expect(match, isNotNull);
      expect(match!.captures['slug'], 'base64-encode');
      expect(match.siteUrl, 'https://base64-encode.tools.sigmadev.digital');
      expect(dvResolveHostPath(match, '/'), '/tools/base64-encode');
    });

    test('rejects multi-label wildcard subdomains', () {
      final match = dvMatchHost('sub.slug.tools.sigmadev.digital', config);
      expect(match, isNull);
    });

    test('rejects unrecognised domains', () {
      expect(dvMatchHost('other.com', config), isNull);
      expect(dvMatchHost('evil-tools.sigmadev.digital.attacker.com', config), isNull);
    });
  });

  group('dvHostLegacyRedirect', () {
    const mainHost = DVHostMatch(
      entry: DVHostEntry(pattern: 'sigmadev.digital'),
      matchedHost: 'sigmadev.digital',
    );
    final registeredSlugs = {'base64-encode', 'json-formatter', 'uuid-generator'};

    test('redirects /tools to tools.sigmadev.digital/', () {
      expect(
        dvHostLegacyRedirect(mainHost, '/tools', registeredToolSlugs: registeredSlugs),
        'https://tools.sigmadev.digital/',
      );
      expect(
        dvHostLegacyRedirect(mainHost, '/tools/', registeredToolSlugs: registeredSlugs),
        'https://tools.sigmadev.digital/',
      );
      expect(
        dvHostLegacyRedirect(mainHost, '/tools?q=search', registeredToolSlugs: registeredSlugs),
        'https://tools.sigmadev.digital/?q=search',
      );
    });

    test('redirects registered tool path to subdomain preserving query', () {
      expect(
        dvHostLegacyRedirect(
          mainHost,
          '/tools/base64-encode',
          registeredToolSlugs: registeredSlugs,
        ),
        'https://base64-encode.tools.sigmadev.digital/',
      );
      expect(
        dvHostLegacyRedirect(
          mainHost,
          '/tools/base64-encode/',
          registeredToolSlugs: registeredSlugs,
        ),
        'https://base64-encode.tools.sigmadev.digital/',
      );
      expect(
        dvHostLegacyRedirect(
          mainHost,
          '/tools/base64-encode?input=hello',
          registeredToolSlugs: registeredSlugs,
        ),
        'https://base64-encode.tools.sigmadev.digital/?input=hello',
      );
    });

    test('does not redirect unregistered tool path', () {
      expect(
        dvHostLegacyRedirect(
          mainHost,
          '/tools/non-existent-tool',
          registeredToolSlugs: registeredSlugs,
        ),
        isNull,
      );
    });
  });

  group('cache partitioning by host', () {
    test('partitions cache keys by validated host', () {
      final uri = Uri.parse('https://sigmadev.digital/');
      final headers = <String, String>{'accept-language': 'en'};
      final key1 = dvRenderedPageKey('site1', uri, headers, host: 'sigmadev.digital');
      final key2 = dvRenderedPageKey('site1', uri, headers, host: 'tools.sigmadev.digital');
      final key3 = dvRenderedPageKey('site1', uri, headers);

      expect(key1, isNot(equals(key2)));
      expect(key1, isNot(equals(key3)));
      expect(key1, contains('host:sigmadev.digital'));
      expect(key2, contains('host:tools.sigmadev.digital'));
    });
  });

  group('DVHostRoutingConfig.parse', () {
    test('parses dartvel.hosts section correctly', () {
      final problems = <String>[];
      final config = DVHostRoutingConfig.parse({
        'trustedProxies': ['127.0.0.1'],
        'entries': {
          'sigmadev.digital': {
            'siteUrl': 'https://sigmadev.digital',
          },
          'tools.sigmadev.digital': {
            'siteUrl': 'https://tools.sigmadev.digital',
            'mount': '/tools',
          },
          '*.tools.sigmadev.digital': {
            'siteUrl': 'https://{slug}.tools.sigmadev.digital',
            'mount': '/tools/{slug}',
          },
          'invalid host name': {},
        },
      }, problems: problems);

      expect(problems, hasLength(1));
      expect(config.trustedProxies, contains('127.0.0.1'));
      expect(config.entries, hasLength(3));
      expect(config.entries[0].pattern, 'sigmadev.digital');
      expect(config.entries[1].pattern, 'tools.sigmadev.digital');
      expect(config.entries[2].isWildcard, isTrue);
    });
  });
}
