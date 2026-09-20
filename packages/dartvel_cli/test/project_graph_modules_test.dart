// What a project is made of includes the modules it mounted.
//
// The graph the build writes beside Studio carried models, routes, functions
// and jobs, and said nothing about modules -- so Studio, whose Site map and
// Tasks sections read that file, could list a module's pages without being
// able to say the module existed, where it came from, or whether it mounted
// at all. A parent that declared a module the build could not find shipped
// without it and without a word about it anywhere an operator looks.
import 'dart:io';

import 'package:dartvel_cli/src/graph/project_graph.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<DartvelProjectGraph> graphFor(Map<String, String> files) async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_graph_modules_');
  addTearDown(() => root.deleteSync(recursive: true));
  for (final MapEntry<String, String> entry in files.entries) {
    final File file = File(p.join(root.path, entry.key));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }
  return DartvelProjectGraph.build(root: root.path, pkgName: 'graph_app');
}

const String _parent = '''
name: graph_app
dartvel:
  modules:
    notes:
      source:
        path: modules/notes
      mount: /notes
      deployment: embedded
''';

const String _module = '''
name: notes_module
dartvel:
  module:
    id: notes
''';

void main() {
  test('the graph names every mounted module and where it came from',
      () async {
    final DartvelProjectGraph graph = await graphFor(<String, String>{
      'pubspec.yaml': _parent,
      'modules/notes/pubspec.yaml': _module,
      'modules/notes/lib/pages/index.dart': '''
import 'package:flutter/widgets.dart';

@DVPage()
@pragma('vm:entry-point')
Widget _home(BuildContext context) => const Text('notes');
''',
    });

    expect(graph.modules.map((DVGraphModule m) => m.id), <String>['notes']);
    final DVGraphModule notes = graph.modules.single;
    expect(notes.mount, '/notes');
    expect(notes.source, 'modules/notes');
    expect(notes.package, 'notes_module');
    expect(notes.mounted, isTrue);
    expect(notes.data, 'shared');
    expect(notes.pages, 1, reason: 'the module contributes one page');
  });

  test('a module the build could not mount is in the graph, saying so',
      () async {
    // The declaration said to mount this and the build could not. Leaving it
    // out of the graph is how an application ships without a section and
    // nobody finds out until a customer does.
    final DartvelProjectGraph graph = await graphFor(<String, String>{
      'pubspec.yaml': _parent,
    });

    final DVGraphModule notes = graph.modules.single;
    expect(notes.mounted, isFalse);
    expect(notes.problems, isNotEmpty);
  });

  test('a project with no modules has none, and does not invent a key',
      () async {
    final DartvelProjectGraph graph = await graphFor(<String, String>{
      'pubspec.yaml': 'name: graph_app\n',
    });

    expect(graph.modules, isEmpty);
    expect(graph.toJson()['modules'], isEmpty);
  });

  test('the graph version moves when its shape does', () async {
    // A consumer that understood version 1 must be able to tell that this
    // file has a key it has never seen.
    final DartvelProjectGraph graph = await graphFor(<String, String>{});
    expect(graph.graphVersion, 2);
  });
}
