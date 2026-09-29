// The one file the build writes into the admin root.
//
// The build wrote four: a static dashboard, its stylesheet, its script, and
// the project graph. Three of them were then deleted by the very next step of
// the same build, which compiles `DVStudioApp` into the admin root and
// replaces the page with the Studio somebody actually uses -- records, forms,
// the page builder, the site map. So the page, the styles and the script were
// written and thrown away in the same function, and the graph was the only
// thing that survived: Studio's site map, tasks and modules sections read it,
// and so does the server, which takes its queue names from it.
//
// What is left here is data. A build that also authored a page for the admin
// mount had two UIs for one thing, one of which could never be opened.
import 'dart:convert';

import 'package:dartvel_cli/src/build/admin_artifact.dart';
import 'package:dartvel_cli/src/graph/project_graph.dart';
import 'package:test/test.dart';

/// A real project graph, serialized the way the build serializes it.
///
/// The first version of this test wrote its own fixture by hand, with a
/// `file` key on every node. The graph calls it `source`, and the dashboard
/// read `file` too -- so the fixture agreed with the mistake and every
/// "Declared in" cell would have rendered empty in front of somebody. A
/// fixture invented next to the code it checks proves the two agree, which
/// is not the question.
Map<String, Object?> graph() => const DartvelProjectGraph(
      models: <DVGraphModel>[
        DVGraphModel(
          name: 'User',
          source: 'lib/models/user.dart',
          fields: <DVGraphField>[
            DVGraphField(name: 'id', type: 'String', sensitive: false),
          ],
        ),
      ],
      routes: <DVGraphRoute>[
        DVGraphRoute(
          path: '/',
          page: 'HomePage',
          source: 'lib/pages/index.dart',
        ),
      ],
      functions: <DVGraphFunction>[
        DVGraphFunction(
          name: 'orders',
          method: 'post',
          path: '/orders',
          source: 'lib/backend/functions/orders.post.dart',
          annotated: true,
        ),
      ],
      jobs: <DVGraphJob>[
        DVGraphJob(
          name: 'nightly',
          queue: 'default',
          source: 'lib/jobs/nightly.dart',
        ),
      ],
      modules: <DVGraphModule>[
        DVGraphModule(
          id: 'shop',
          package: 'shop_module',
          mount: '/shop',
          source: 'packages/shop',
          deployment: 'embedded',
          mounted: true,
          pages: 3,
          data: 'shared',
        ),
      ],
    ).toJson();

void main() {
  group('what the artifact is made of', () {
    test('the project graph, and nothing else', () {
      // A page, a stylesheet and a script used to be here as well, deleted a
      // moment later by the step that compiles Studio over them. The build
      // authoring a UI it never serves is the thing that went wrong; writing
      // it again is how it comes back.
      final Map<String, String> files = dvAdminArtifact(graph: graph());

      expect(files.keys, <String>['graph.json']);
    });

    test('the graph is written back exactly as it came in', () {
      // Studio's site map, task and module sections read this at runtime, and
      // so does the server for its queue names. A builder that reshaped it
      // would put a second definition of the graph in the repository, and the
      // two would disagree the first time one of them changed.
      final Map<String, Object?> source = graph();
      final Map<String, String> files = dvAdminArtifact(graph: source);

      expect(jsonDecode(files['graph.json']!), source);
    });
  });

  group('what it must never do', () {
    test('contain a page of any kind', () {
      final Map<String, String> files = dvAdminArtifact(graph: graph());

      for (final MapEntry<String, String> file in files.entries) {
        for (final String markup in <String>[
          '<!doctype',
          '<html',
          '<body',
          '<script',
          '<style',
          'onclick=',
        ]) {
          expect(file.value, isNot(contains(markup)),
              reason: '${file.key} contains $markup');
        }
      }
    });

    test('load anything from another host', () {
      // The backend serving the admin root may have no route to the internet,
      // and a Studio that half-renders because a CDN is unreachable is worse
      // than one that was never offered.
      final Map<String, String> files = dvAdminArtifact(graph: graph());

      for (final MapEntry<String, String> file in files.entries) {
        expect(file.value, isNot(contains('http://')), reason: file.key);
        expect(file.value, isNot(contains('https://')), reason: file.key);
        expect(file.value, isNot(contains('//cdn')), reason: file.key);
      }
    });
  });

  group('the keys its readers ask for', () {
    // The page declared its own columns and this is what caught the one that
    // mattered: it read `file` for every node's source and the graph calls it
    // `source`, so every "Declared in" cell rendered empty in front of
    // somebody -- a dashboard that looked like it worked and showed nothing.
    //
    // The columns now live in dartvel_flutter, where the sections that read
    // them are, and are checked there against a graph served over a fake
    // backend. What can be held on this side is the producer: that a real
    // graph has each key its readers ask for, with a value in it. Held
    // against a real DartvelProjectGraph rather than a fixture written here,
    // because a fixture written next to the code agreed with the mistake.
    //
    // Present, not exactly equal to. A real graph row carries keys no one
    // shows as a column -- a route's `kind` and `module`, a function's
    // `annotated`, a module's whole declaration -- and the first version of
    // this test demanded the two sets match, which failed on a correct graph
    // and would have been answered by deleting `kind` from the graph rather
    // than by fixing the test. A key a reader asks for and the graph does not
    // have is the bug worth catching; a key the graph has and a reader
    // ignores is the reader's business.
    const Map<String, List<String>> read = <String, List<String>>{
      'models': <String>['name', 'source', 'fields'],
      'routes': <String>['path', 'page', 'source'],
      'functions': <String>['name', 'method', 'path', 'source'],
      // The queue is the one the server itself asks for, in
      // dvAdminGraphQueues: a worker with no queue named in the graph is a
      // job that never runs and nothing saying so.
      'jobs': <String>['name', 'queue', 'source'],
      'modules': <String>['id', 'mount', 'deployment', 'source'],
    };

    test('are the keys a real graph produces', () {
      final Map<String, Object?> real = graph();
      expect(real.keys, containsAll(read.keys));

      for (final MapEntry<String, List<String>> section in read.entries) {
        final List<Object?> rows = real[section.key]! as List<Object?>;
        final Map<String, Object?> row =
            (rows.first as Map).cast<String, Object?>();
        expect(row.keys.toSet(), containsAll(section.value),
            reason: '${section.key} has ${row.keys.join(', ')}');
      }
    });

    test('and every one of them has something to show', () {
      // The half of the `file`/`source` bug that a person could see: the key
      // was absent, so the cell was empty, and a column of empty cells looks
      // like a page that loaded. A null in any of these is that again.
      final Map<String, Object?> real = graph();

      for (final MapEntry<String, List<String>> section in read.entries) {
        final List<Object?> rows = real[section.key]! as List<Object?>;
        final Map<String, Object?> row =
            (rows.first as Map).cast<String, Object?>();
        for (final String key in section.value) {
          expect(row[key], isNotNull, reason: '$section.key.$key is null');
          expect(row[key], isNotEmpty, reason: '$section.key.$key is empty');
        }
      }
    });

    test('and a kind the graph grows is not one Studio is silent about', () {
      // The other direction of the same check: a kind added to the graph and
      // never added to a section is simply not shown, with nothing to say so.
      final Map<String, Object?> real = graph()..remove('graphVersion');

      expect(real.keys.toSet(), read.keys.toSet());
    });
  });
}
