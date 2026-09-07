// The dashboard the backend was already prepared to serve, and did not have.
//
// dvAdminMount decides whether there is an admin and where it is mounted,
// dvAdminFor decides whether a request may see it, and the web server serves
// files from the admin root. Nothing wrote a file into that root, so a
// project that enabled the admin got a 404 from a mount that existed.
//
// The artifact is a static page rather than a second Flutter application on
// purpose. It is served by the application's own backend, which may be
// running with no route to the internet, so it loads nothing from anywhere
// else; and it is one dashboard for the whole application rather than one
// per build target, so what it reads is the project graph, which has no
// target in it.
import 'dart:convert';

import 'package:dartvel_cli/src/build/admin_artifact.dart';
import 'package:test/test.dart';

Map<String, Object?> graph() => <String, Object?>{
      'graphVersion': 1,
      'models': <Object?>[
        <String, Object?>{
          'name': 'User',
          'file': 'lib/models/user.dart',
          'fields': <Object?>[
            <String, Object?>{'name': 'id', 'type': 'String'},
          ],
        },
      ],
      'routes': <Object?>[
        <String, Object?>{'path': '/', 'file': 'lib/pages/index.dart'},
      ],
      'functions': <Object?>[
        <String, Object?>{
          'path': '/orders',
          'method': 'post',
          'file': 'lib/backend/functions/orders.post.dart',
        },
      ],
      'jobs': <Object?>[],
    };

void main() {
  group('what the artifact is made of', () {
    test('a shell, its styles, its script and the graph', () {
      final Map<String, String> files = dvAdminArtifact(
        graph: graph(),
        appName: 'Shop',
        buildId: 'build-1',
      );

      expect(
        files.keys.toSet(),
        containsAll(<String>['index.html', 'admin.css', 'admin.js',
            'graph.json'],),
      );
    });

    test('the graph is written back exactly as it came in', () {
      // The page reads this at runtime. A builder that reshaped it would put
      // a second definition of the graph in the repository, and the two would
      // disagree the first time one of them changed.
      final Map<String, Object?> source = graph();
      final Map<String, String> files = dvAdminArtifact(
        graph: source,
        appName: 'Shop',
        buildId: 'build-1',
      );

      expect(jsonDecode(files['graph.json']!), source);
    });
  });

  group('what it must never do', () {
    test('nothing is loaded from another host', () {
      // The backend serving this may have no route to the internet, and a
      // dashboard that half-renders because a CDN is unreachable is worse
      // than one that was never offered.
      final Map<String, String> files = dvAdminArtifact(
        graph: graph(),
        appName: 'Shop',
        buildId: 'build-1',
      );

      for (final MapEntry<String, String> file in files.entries) {
        expect(file.value, isNot(contains('http://')), reason: file.key);
        expect(file.value, isNot(contains('https://')), reason: file.key);
        expect(file.value, isNot(contains('//cdn')), reason: file.key);
      }
    });

    test('every reference is relative, so the mount can move', () {
      // The path is a default and the project can change it to something
      // private. An asset referenced from the root would then 404, and the
      // dashboard would be broken by exactly the setting that exists to
      // protect it.
      final String html = dvAdminArtifact(
        graph: graph(),
        appName: 'Shop',
        buildId: 'build-1',
      )['index.html']!;

      expect(html, contains('admin.css'));
      expect(html, contains('admin.js'));
      expect(html, isNot(contains('"/admin.css"')));
      expect(html, isNot(contains("'/admin.js'")));
      expect(html, isNot(contains('/__studio')));
    });

    test('an application name is escaped, not interpolated', () {
      // The name comes from pubspec.yaml, which is not an attacker, but the
      // dashboard is the page where a mistake matters most and escaping the
      // one value that reaches the HTML costs a function call.
      final String html = dvAdminArtifact(
        graph: graph(),
        appName: '<script>alert(1)</script>',
        buildId: 'build-1',
      )['index.html']!;

      expect(html, isNot(contains('<script>alert(1)</script>')));
      expect(html, contains('&lt;script&gt;'));
    });

    test('the graph is fetched, not inlined into the script', () {
      // Inlining it would mean escaping JSON into a script tag, which is the
      // shape that goes wrong quietly. It is a separate file the page asks
      // for, and the server already answers .json with a JSON content type.
      final Map<String, String> files = dvAdminArtifact(
        graph: graph(),
        appName: 'Shop',
        buildId: 'build-1',
      );

      expect(files['admin.js'], contains("fetch('graph.json'"));
      expect(files['admin.js'], isNot(contains('"models":')));
    });
  });

  group('what it shows', () {
    test('the four kinds of node the graph carries', () {
      final String script = dvAdminArtifact(
        graph: graph(),
        appName: 'Shop',
        buildId: 'build-1',
      )['admin.js']!;

      for (final String kind in <String>[
        'models',
        'routes',
        'functions',
        'jobs',
      ]) {
        expect(script, contains(kind), reason: kind);
      }
    });

    test('the build it was generated from', () {
      // So somebody looking at a dashboard can tell whether it is the one
      // this deployment built.
      final String html = dvAdminArtifact(
        graph: graph(),
        appName: 'Shop',
        buildId: 'build-42',
      )['index.html']!;

      expect(html, contains('build-42'));
    });

    test('a value from the graph is escaped where it is rendered', () {
      // The graph is derived from source files, and a model or a route can
      // be named anything somebody typed. The script renders through
      // textContent rather than innerHTML for that reason, and this is the
      // assertion that keeps it that way.
      final String script = dvAdminArtifact(
        graph: graph(),
        appName: 'Shop',
        buildId: 'build-1',
      )['admin.js']!;

      expect(script, contains('textContent'));
      expect(script, isNot(contains('innerHTML')));
    });
  });
}
