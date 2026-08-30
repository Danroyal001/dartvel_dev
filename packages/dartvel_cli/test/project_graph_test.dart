// The project graph: one answer to "what is this application made of".
//
// The inspectors in the spec are eight questions about the same artifact. Built
// the other way round -- a --json flag bolted onto commands that already exist
// -- each generator would answer from its own rediscovery of the source, and
// the answers would disagree at the edges.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/graph/project_graph.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<DartvelProjectGraph> graphFor(Map<String, String> files) async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_graph_');
  addTearDown(() => root.deleteSync(recursive: true));
  for (final MapEntry<String, String> entry in files.entries) {
    final File file = File(p.join(root.path, entry.key));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }
  return DartvelProjectGraph.build(root: root.path, pkgName: 'graph_app');
}

void main() {
  test('the graph version is a contract, not a build stamp', () async {
    final DartvelProjectGraph graph = await graphFor(<String, String>{});
    expect(graph.graphVersion, 1);
    expect(graph.toJson()['graphVersion'], 1);
  });

  group('models', () {
    test('a model is named by its generated type, not its private input',
        () async {
      final DartvelProjectGraph graph = await graphFor(<String, String>{
        'lib/models/user.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _User {
  final String email;
  final int age;

  const _User({required this.email, required this.age});
}
''',
      });

      expect(graph.models.map((DVGraphModel m) => m.name), <String>['User']);
      expect(
        graph.models.single.fields.map((DVGraphField f) => '${f.type} ${f.name}'),
        <String>['String email', 'int age'],
      );
    });

    test('a field carries the source it was derived from', () async {
      final DartvelProjectGraph graph = await graphFor(<String, String>{
        'lib/models/user.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _User {
  final String email;

  const _User({required this.email});
}
''',
      });

      // The annotation line, not the `class` line. The spec says a node keeps
      // "the source mapping it was derived from", and what Dartvel read to
      // make this node is `@DVModel()`; it is also the first line of the
      // declaration, so opening it shows the class too.
      expect(graph.models.single.source, 'lib/models/user.dart:3');
    });

    test('a sensitive field is named but never valued', () async {
      // The rule the spec states for --json and MCP alike: an agent needs the
      // schema, and must not be handed the data.
      final DartvelProjectGraph graph = await graphFor(<String, String>{
        'lib/models/user.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _User {
  final String email;

  @DVModel.sensitiveField()
  final String taxId;

  const _User({required this.email, required this.taxId});
}
''',
      });

      final List<DVGraphField> fields = graph.models.single.fields;
      final DVGraphField taxId =
          fields.firstWhere((DVGraphField f) => f.name == 'taxId');
      expect(taxId.sensitive, isTrue);
      expect(fields.firstWhere((DVGraphField f) => f.name == 'email').sensitive,
          isFalse);

      // Serialized, the flag is present and there is no value anywhere.
      final Map<String, Object?> json =
          (graph.toJson()['models']! as List<Object?>).first!
              as Map<String, Object?>;
      final List<Object?> jsonFields = json['fields']! as List<Object?>;
      final Map<String, Object?> jsonTaxId = jsonFields
          .cast<Map<String, Object?>>()
          .firstWhere((Map<String, Object?> f) => f['name'] == 'taxId');
      expect(jsonTaxId['sensitive'], isTrue);
      expect(jsonTaxId.containsKey('value'), isFalse);
    });
  });

  group('routes', () {
    test('a page becomes a route with its source', () async {
      final DartvelProjectGraph graph = await graphFor(<String, String>{
        'lib/pages/index.page.dart': '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

@DVPage(title: 'Home')
Widget _homePage(BuildContext context) => const DVText('hi');
''',
        'lib/pages/about.page.dart': '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

@DVPage(title: 'About')
Widget _aboutPage(BuildContext context) => const DVText('about');
''',
      });

      expect(graph.routes.map((DVGraphRoute r) => r.path), <String>['/', '/about']);
      expect(graph.routes.first.source, startsWith('lib/pages/index.page.dart:'));
    });
  });

  group('backend functions', () {
    test('an unannotated file is still a served endpoint', () async {
      // Backend functions are file-based: a file under backend/functions is a
      // route whether or not it carries @DVBackendFunction. Counting only the
      // annotated ones told a reader the example served 2 endpoints when it
      // served 19, which is the kind of wrong answer that still looks right.
      final DartvelProjectGraph graph = await graphFor(<String, String>{
        'lib/backend/functions/hello.get.dart': '''
Future<String> handler() async => 'hi';
''',
        'lib/backend/functions/db/todos.post.dart': '''
Future<String> handler() async => 'made';
''',
      });

      expect(
        graph.functions.map((DVGraphFunction f) => '${f.method} ${f.path}'),
        <String>['POST /db/todos', 'GET /hello'],
      );
    });

    test('a file with no method suffix defaults to POST, as the router does',
        () async {
      // The generator defaults an unrecognised or absent suffix to POST. A
      // graph that said GET would describe a route nothing serves.
      final DartvelProjectGraph graph = await graphFor(<String, String>{
        'lib/backend/functions/notify_owner.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<Object?> _notifyOwner(Object? email) async => email;
''',
      });

      expect(graph.functions.single.method, 'POST');
      expect(graph.functions.single.path, '/notify_owner');
    });

    test('a function is named and located', () async {
      final DartvelProjectGraph graph = await graphFor(<String, String>{
        'lib/backend/functions/createorder.post.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<String> _createOrder(String sku) async => sku;
''',
      });

      expect(graph.functions.map((DVGraphFunction f) => f.name),
          <String>['createOrder']);
      expect(graph.functions.single.method, 'POST');
      expect(graph.functions.single.path, '/createorder');
    });
  });

  group('jobs', () {
    test('a job carries its queue', () async {
      final DartvelProjectGraph graph = await graphFor(<String, String>{
        'lib/jobs/jobs.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVJob(queue: 'mail')
class _SendWelcome {
  final String userId;

  const _SendWelcome({required this.userId});
}
''',
      });

      expect(graph.jobs.map((DVGraphJob j) => j.name), <String>['SendWelcome']);
      expect(graph.jobs.single.queue, 'mail');
    });
  });

  test('the graph is ordered, so two builds of one project diff cleanly',
      () async {
    final Map<String, String> files = <String, String>{
      'lib/models/zebra.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Zebra {
  final String id;
  const _Zebra({required this.id});
}
''',
      'lib/models/apple.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Apple {
  final String id;
  const _Apple({required this.id});
}
''',
    };

    final DartvelProjectGraph first = await graphFor(files);
    final DartvelProjectGraph second = await graphFor(files);

    expect(first.models.map((DVGraphModel m) => m.name), <String>['Apple', 'Zebra']);
    expect(jsonEncode(first.toJson()), jsonEncode(second.toJson()));
  });
}
