import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// The example configuration the docs use: a primary, a mounted host and a
/// wildcard host.
Map<String, Object?> exampleYaml() => <String, Object?>{
  'example.com': <String, Object?>{'siteUrl': 'https://example.com'},
  'docs.example.com': <String, Object?>{
    'mount': '/docs',
    'siteUrl': 'https://docs.example.com',
    'name': 'Example Docs',
    'description': 'Reference for Example.',
  },
  '*.apps.example.com': <String, Object?>{
    'mount': '/apps/{label}',
    'siteUrl': 'https://{label}.apps.example.com',
  },
};

DVHosts example() {
  final parsed = DVHosts.parse(exampleYaml());
  expect(parsed.problems, isEmpty);
  return parsed.hosts;
}

void main() {
  group('DVHosts.parse', () {
    test('reads every entry with its mount, siteUrl, name and description', () {
      final DVHosts hosts = example();
      expect(hosts.entries, hasLength(3));
      expect(hosts.primary.pattern, 'example.com');
      expect(hosts.primary.mount, '/');
      final DVHostEntry docs = hosts.entries.firstWhere(
        (DVHostEntry e) => e.pattern == 'docs.example.com',
      );
      expect(docs.mount, '/docs');
      expect(docs.siteUrl, 'https://docs.example.com');
      expect(docs.name, 'Example Docs');
      expect(docs.description, 'Reference for Example.');
    });

    test('the primary siteUrl defaults to dartvel.seo.siteUrl', () {
      final parsed = DVHosts.parse(<String, Object?>{
        'example.com': null,
        'docs.example.com': <String, Object?>{
          'mount': '/docs',
          'siteUrl': 'https://docs.example.com',
        },
      }, defaultSiteUrl: 'https://example.com');
      expect(parsed.problems, isEmpty);
      expect(parsed.hosts.primary.siteUrl, 'https://example.com');
    });

    test('absent hosts is no hosts and no problem', () {
      final parsed = DVHosts.parse(null);
      expect(parsed.problems, isEmpty);
      expect(parsed.hosts.isEmpty, isTrue);
    });

    test('refuses two primaries', () {
      final problems = DVHosts.parse(<String, Object?>{
        'example.com': <String, Object?>{'siteUrl': 'https://example.com'},
        'example.org': <String, Object?>{
          'siteUrl': 'https://example.org',
          'mount': '/',
        },
      }).problems;
      expect(problems.join('\n'), contains('primary'));
    });

    test('refuses no primary', () {
      final problems = DVHosts.parse(<String, Object?>{
        'docs.example.com': <String, Object?>{
          'mount': '/docs',
          'siteUrl': 'https://docs.example.com',
        },
      }).problems;
      expect(problems.join('\n'), contains('primary'));
    });

    test('refuses a wildcard that is not a single leftmost label', () {
      for (final String bad in <String>[
        '*.*.example.com',
        'a.*.example.com',
        '*example.com',
        '*.com.*',
      ]) {
        final problems = DVHosts.parse(<String, Object?>{
          'example.com': <String, Object?>{'siteUrl': 'https://example.com'},
          bad: <String, Object?>{
            'mount': '/apps/{label}',
            'siteUrl': 'https://{label}.apps.example.com',
          },
        }).problems;
        expect(problems, isNotEmpty, reason: bad);
      }
    });

    test('refuses {label} in a non-wildcard entry', () {
      final problems = DVHosts.parse(<String, Object?>{
        'example.com': <String, Object?>{'siteUrl': 'https://example.com'},
        'docs.example.com': <String, Object?>{
          'mount': '/docs/{label}',
          'siteUrl': 'https://docs.example.com',
        },
      }).problems;
      expect(problems.join('\n'), contains('{label}'));
    });

    test('refuses {label} that is not a whole path segment', () {
      final problems = DVHosts.parse(<String, Object?>{
        'example.com': <String, Object?>{'siteUrl': 'https://example.com'},
        '*.apps.example.com': <String, Object?>{
          'mount': '/apps/x-{label}',
          'siteUrl': 'https://{label}.apps.example.com',
        },
      }).problems;
      expect(problems.join('\n'), contains('{label}'));
    });

    test('refuses a mount not starting with /', () {
      final problems = DVHosts.parse(<String, Object?>{
        'example.com': <String, Object?>{'siteUrl': 'https://example.com'},
        'docs.example.com': <String, Object?>{
          'mount': 'docs',
          'siteUrl': 'https://docs.example.com',
        },
      }).problems;
      expect(problems.join('\n'), contains('mount'));
    });

    test('refuses a siteUrl that is not an http(s) origin', () {
      for (final String bad in <String>[
        'ftp://docs.example.com',
        'docs.example.com',
        'https://docs.example.com/path',
        'https://docs.example.com?x=1',
      ]) {
        final problems = DVHosts.parse(<String, Object?>{
          'example.com': <String, Object?>{'siteUrl': 'https://example.com'},
          'docs.example.com': <String, Object?>{
            'mount': '/docs',
            'siteUrl': bad,
          },
        }).problems;
        expect(problems.join('\n'), contains('siteUrl'), reason: bad);
      }
    });

    test('refuses a non-wildcard entry with no siteUrl', () {
      final problems = DVHosts.parse(<String, Object?>{
        'example.com': <String, Object?>{'siteUrl': 'https://example.com'},
        'docs.example.com': <String, Object?>{'mount': '/docs'},
      }).problems;
      expect(problems.join('\n'), contains('siteUrl'));
    });

    test('refuses a non-ASCII host pattern', () {
      final problems = DVHosts.parse(<String, Object?>{
        'exämple.com': <String, Object?>{'siteUrl': 'https://example.com'},
      }).problems;
      expect(problems, isNotEmpty);
    });

    test('round-trips through the manifest JSON', () {
      final DVHosts hosts = example();
      final DVHosts back = DVHosts.fromJson(hosts.toJson());
      expect(back.toJson(), hosts.toJson());
      expect(back.primary.pattern, 'example.com');
    });
  });

  group('dvNormaliseHost', () {
    test('lowercases, strips the port and a trailing dot', () {
      expect(dvNormaliseHost('Docs.Example.COM:8443'), 'docs.example.com');
      expect(dvNormaliseHost('example.com.'), 'example.com');
      expect(dvNormaliseHost('example.com.:80'), 'example.com');
    });

    test('handles bracketed IPv6 with and without a port', () {
      expect(dvNormaliseHost('[::1]:8080'), '::1');
      expect(dvNormaliseHost('[::1]'), '::1');
    });

    test('rejects non-ASCII and empty hosts', () {
      expect(dvNormaliseHost('exämple.com'), isNull);
      expect(dvNormaliseHost(''), isNull);
      expect(dvNormaliseHost(null), isNull);
    });
  });

  group('dvEffectiveHost', () {
    test('Host when the peer is not a trusted proxy', () {
      expect(
        dvEffectiveHost(
          host: 'example.com',
          forwardedHost: 'docs.example.com',
          peerIsTrustedProxy: false,
        ),
        'example.com',
      );
    });

    test('X-Forwarded-Host when the peer is a trusted proxy', () {
      expect(
        dvEffectiveHost(
          host: 'internal:8080',
          forwardedHost: 'Docs.Example.com',
          peerIsTrustedProxy: true,
        ),
        'docs.example.com',
      );
    });

    test(
      'the entry the nearest trusted proxy wrote, when there are several',
      () {
        expect(
          dvEffectiveHost(
            host: 'internal:8080',
            forwardedHost: 'evil.example.net, docs.example.com',
            peerIsTrustedProxy: true,
          ),
          'docs.example.com',
        );
      },
    );
  });

  group('DVHosts.match', () {
    test('exact before wildcard', () {
      final hosts = DVHosts.parse(<String, Object?>{
        ...exampleYaml(),
        'special.apps.example.com': <String, Object?>{
          'mount': '/special',
          'siteUrl': 'https://special.apps.example.com',
        },
      }).hosts;
      expect(
        hosts.match('special.apps.example.com')!.entry.pattern,
        'special.apps.example.com',
      );
      expect(
        hosts.match('foo.apps.example.com')!.entry.pattern,
        '*.apps.example.com',
      );
    });

    test('a wildcard matches exactly one leftmost label', () {
      final DVHosts hosts = example();
      final DVHostMatch? m = hosts.match('foo.apps.example.com');
      expect(m, isNotNull);
      expect(m!.label, 'foo');
      expect(m.origin, 'https://foo.apps.example.com');
      expect(m.mount, '/apps/foo');
      expect(hosts.match('a.b.apps.example.com'), isNull);
      expect(hosts.match('apps.example.com'), isNull);
    });

    test('normalises the host it is given', () {
      expect(
        example().match('DOCS.example.com:443')!.entry.pattern,
        'docs.example.com',
      );
    });

    test('unknown hosts do not match', () {
      expect(example().match('203.0.113.9'), isNull);
      expect(example().match('example.net'), isNull);
    });
  });

  group('DVHostMatch paths', () {
    test('internalPath maps / to the mount and /x under it', () {
      final DVHostMatch docs = example().match('docs.example.com')!;
      expect(docs.internalPath('/'), '/docs');
      expect(docs.internalPath(''), '/docs');
      expect(docs.internalPath('/x'), '/docs/x');
      final DVHostMatch primary = example().match('example.com')!;
      expect(primary.internalPath('/'), '/');
      expect(primary.internalPath('/docs/x'), '/docs/x');
    });

    test('hostPath strips the mount and is null outside it', () {
      final DVHostMatch app = example().match('foo.apps.example.com')!;
      expect(app.hostPath('/apps/foo'), '/');
      expect(app.hostPath('/apps/foo/settings'), '/settings');
      expect(app.hostPath('/apps/foobar'), isNull);
      expect(app.hostPath('/apps/bar'), isNull);
      expect(app.hostPath('/'), isNull);
    });
  });

  group('DVHosts.publicUrl', () {
    test('the longest matching mount owns the path', () {
      final DVHosts hosts = example();
      expect(hosts.publicUrl('/docs/x'), 'https://docs.example.com/x');
      expect(hosts.publicUrl('/docs'), 'https://docs.example.com');
      expect(hosts.publicUrl('/apps/foo'), 'https://foo.apps.example.com');
      expect(
        hosts.publicUrl('/apps/foo/settings'),
        'https://foo.apps.example.com/settings',
      );
      expect(hosts.publicUrl('/pricing'), 'https://example.com/pricing');
      expect(hosts.publicUrl('/'), 'https://example.com');
    });

    test('a nested mount beats its parent', () {
      final hosts = DVHosts.parse(<String, Object?>{
        ...exampleYaml(),
        'api.example.com': <String, Object?>{
          'mount': '/docs/api',
          'siteUrl': 'https://api.example.com',
        },
      }).hosts;
      expect(hosts.publicUrl('/docs/api/v1'), 'https://api.example.com/v1');
      expect(hosts.publicUrl('/docs/guide'), 'https://docs.example.com/guide');
    });

    test('a segment that only starts like a mount is the primary\'s', () {
      expect(
        example().publicUrl('/docsearch'),
        'https://example.com/docsearch',
      );
    });

    test('a wildcard needs a valid lowercase DNS label', () {
      final DVHosts hosts = example();
      expect(hosts.publicUrl('/apps/Foo'), 'https://example.com/apps/Foo');
      expect(hosts.publicUrl('/apps/-bad'), 'https://example.com/apps/-bad');
      expect(hosts.publicUrl('/apps/a_b'), 'https://example.com/apps/a_b');
      expect(hosts.publicUrl('/apps'), 'https://example.com/apps');
    });

    test('carries the query', () {
      final DVHosts hosts = example();
      expect(
        hosts.publicUrl('/docs/x', query: 'a=1'),
        'https://docs.example.com/x?a=1',
      );
      expect(
        hosts.publicUrl('/apps/foo', query: 'a=1'),
        'https://foo.apps.example.com/?a=1',
      );
      expect(
        hosts.publicUrl('/docs/x', query: ''),
        'https://docs.example.com/x',
      );
    });
  });

  group('owners of route patterns', () {
    test('a parameter segment stands for any label', () {
      final DVHosts hosts = example();
      expect(hosts.ownerOfPattern('/apps/:id')!.pattern, '*.apps.example.com');
      expect(
        hosts.ownerOfPattern('/apps/:id/settings')!.pattern,
        '*.apps.example.com',
      );
      expect(hosts.ownerOfPattern('/docs/:page')!.pattern, 'docs.example.com');
      expect(hosts.ownerOfPattern('/apps')!.pattern, 'example.com');
    });

    test('whether a host has any route under its mount', () {
      final DVHosts hosts = example();
      const List<String> routes = <String>[
        '/',
        '/docs',
        '/docs/x',
        '/apps/foo',
        '/apps/foo/settings',
      ];
      expect(hosts.match('foo.apps.example.com')!.servesAnyOf(routes), isTrue);
      expect(hosts.match('bar.apps.example.com')!.servesAnyOf(routes), isFalse);
      expect(
        hosts.match('bar.apps.example.com')!.servesAnyOf(<String>['/apps/:id']),
        isTrue,
      );
      expect(hosts.match('docs.example.com')!.servesAnyOf(routes), isTrue);
      expect(hosts.match('example.com')!.servesAnyOf(const <String>[]), isTrue);
    });
  });

  group('dvHostedRequest', () {
    bool isRoute(String p) => const <String>{
      '/',
      '/docs',
      '/docs/x',
      '/apps/foo',
      '/pricing',
    }.contains(p);

    test('maps the path, and sends a route of another host there', () {
      final DVHostedRequest r = dvHostedRequest(
        example(),
        host: 'example.com',
        rawPath: '/docs/x',
        query: 'a=1',
        isRoute: isRoute,
      );
      expect(r.path, '/docs/x');
      expect(r.redirect, 'https://docs.example.com/x?a=1');
    });

    test('a route on its own host renders at its own path and origin', () {
      final DVHostedRequest r = dvHostedRequest(
        example(),
        host: 'docs.example.com',
        rawPath: '/x/',
        isRoute: isRoute,
      );
      expect(r.path, '/docs/x');
      expect(r.redirect, isNull);
      expect(r.pagePath, '/x');
      expect(r.siteUrl, 'https://docs.example.com');
      expect(r.siteName, 'Example Docs');
      expect(r.description, 'Reference for Example.');
    });

    test('a path no route serves is not redirected', () {
      final DVHostedRequest r = dvHostedRequest(
        example(),
        host: 'example.com',
        rawPath: '/docs/nope',
        isRoute: isRoute,
      );
      expect(r.redirect, isNull);
      expect(r.path, '/docs/nope');
    });

    test('an unknown host is the primary', () {
      final DVHostedRequest r = dvHostedRequest(
        example(),
        host: '203.0.113.9:80',
        rawPath: '/pricing',
        isRoute: isRoute,
      );
      expect(r.requested.entry.pattern, 'example.com');
      expect(r.redirect, isNull);
      expect(r.siteUrl, 'https://example.com');
    });
  });
}
