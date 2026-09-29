// Where the documentation lives, whether it is enabled, and who may reach it.
import 'package:dartvel_cli/src/build/docs_mount.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Object? _dartvel(String yaml) {
  final Object? document = loadYaml('dartvel:\n$yaml');
  return document is Map ? document['dartvel'] : null;
}

void main() {
  group('the path', () {
    test('a project that says nothing gets /docs', () {
      expect(dvDocsMount(null).path, '/docs');
    });

    test('a project that names a path gets that path', () {
      expect(
        dvDocsMount(_dartvel('  docs:\n    path: /manual')).path,
        '/manual',
      );
    });

    test('a trailing slash is normalized away', () {
      expect(
        dvDocsMount(_dartvel('  docs:\n    path: /docs/')).path,
        '/docs',
      );
    });

    test('a path with no leading slash is refused', () {
      expect(dvDocsMountProblem('docs'), isNotNull);
      expect(dvDocsMountProblem('docs'), contains('/'));
    });

    test('mounting at / is refused', () {
      expect(dvDocsMountProblem('/'), isNotNull);
      expect(dvDocsMountProblem('/')!.toLowerCase(), contains('application'));
    });

    test('a parameterised path is refused', () {
      expect(dvDocsMountProblem('/docs/:id'), isNotNull);
      expect(dvDocsMountProblem('/docs/*'), isNotNull);
    });

    test('a valid path passes problem check', () {
      expect(dvDocsMountProblem('/docs'), isNull);
      expect(dvDocsMountProblem('/documentation'), isNull);
      expect(dvDocsMountProblem('/internal/docs'), isNull);
    });
  });

  group('the toggle (enabled)', () {
    test('OFF by default for every app when omitted', () {
      expect(dvDocsMount(null).enabled, isFalse);
      expect(dvDocsMount(_dartvel('')).enabled, isFalse);
    });

    test('OFF by default even when path is declared', () {
      expect(
        dvDocsMount(_dartvel('  docs:\n    path: /docs')).enabled,
        isFalse,
      );
    });

    test('OFF when explicitly set to false', () {
      expect(
        dvDocsMount(_dartvel('  docs:\n    enabled: false')).enabled,
        isFalse,
      );
    });

    test('enabled only when explicitly set to true', () {
      expect(
        dvDocsMount(_dartvel('  docs:\n    enabled: true')).enabled,
        isTrue,
      );
      expect(
        dvDocsMount(_dartvel('  docs:\n    enabled: true\n    path: /api-docs'))
            .enabled,
        isTrue,
      );
    });
  });

  group('the access', () {
    test('defaults to studio access when enabled', () {
      final DVDocsMount mount =
          dvDocsMount(_dartvel('  docs:\n    enabled: true'));
      expect(mount.access, DVDocsAccess.studio);
      expect(mount.requiresAuth, isTrue);
    });

    test('defaults to studio access when omitted', () {
      final DVDocsMount mount = dvDocsMount(null);
      expect(mount.access, DVDocsAccess.studio);
      expect(mount.requiresAuth, isTrue);
    });

    test('allows explicit studio access', () {
      final DVDocsMount mount = dvDocsMount(
        _dartvel('  docs:\n    enabled: true\n    access: studio'),
      );
      expect(mount.access, DVDocsAccess.studio);
      expect(mount.requiresAuth, isTrue);
    });

    test('allows public access', () {
      final DVDocsMount mount = dvDocsMount(
        _dartvel('  docs:\n    enabled: true\n    access: public'),
      );
      expect(mount.access, DVDocsAccess.public);
      expect(mount.requiresAuth, isFalse);
    });
  });

  group('conflict with application routes', () {
    test('refuses a page claiming the exact mount path', () {
      final String? problem = dvDocsMountConflict(
        '/docs',
        <String, String>{'/docs': 'lib/pages/docs.page.dart'},
      );
      expect(problem, isNotNull);
      expect(problem, contains('lib/pages/docs.page.dart'));
      expect(problem, contains('claims "/docs"'));
      expect(problem, contains('the docs mount "/docs"'));
      expect(problem, contains('dartvel.docs.path'));
    });

    test('refuses a page underneath the mount path', () {
      final String? problem = dvDocsMountConflict(
        '/docs',
        <String, String>{
          '/docs/getting-started': 'lib/pages/docs/getting-started.page.dart',
        },
      );
      expect(problem, isNotNull);
      expect(problem, contains('lib/pages/docs/getting-started.page.dart'));
      expect(problem, contains('claims "/docs/getting-started"'));
      expect(problem, contains('the docs mount "/docs"'));
    });

    test('allows a route that merely starts with the same letters', () {
      expect(
        dvDocsMountConflict(
          '/docs',
          <String, String>{'/docss': 'lib/pages/docss.page.dart'},
        ),
        isNull,
      );
    });

    test('allows routes outside the mount', () {
      expect(
        dvDocsMountConflict(
          '/docs',
          <String, String>{
            '/': 'lib/pages/index.page.dart',
            '/pricing': 'lib/pages/pricing.page.dart',
          },
        ),
        isNull,
      );
    });
  });
}
