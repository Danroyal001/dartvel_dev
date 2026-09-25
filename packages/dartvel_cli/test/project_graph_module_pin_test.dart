// A module in the graph says what was pinned for it.
//
// The graph is what Studio, Cloud, CI and the AI surfaces read, and what they
// each need to know about a generated module is which bytes it came from. A
// graph that named a module and not its pin would send every one of those
// tools to the lockfile separately, and the one that forgot would be reading
// a module with no provenance at all.
//
// A foreign module carries both digests, because a changed source and a
// changed wrapper are different events with opposite fixes. A module from
// pub.dev carries the archive digest it has always been pinned by.
import 'dart:io';

import 'package:dartvel_cli/src/graph/project_graph.dart';
import 'package:dartvel_cli/src/module_trust/module_lock.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String _project(String lock) {
  final Directory root =
      Directory.systemTemp.createTempSync('dartvel_graph_pin_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'modules', 'scanner')).createSync(recursive: true);
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: pin_app
environment:
  sdk: ^3.13.0
dartvel:
  modules:
    scanner:
      path: modules/scanner
      mount: /scanner
''');
  File(p.join(root.path, 'modules', 'scanner', 'pubspec.yaml'))
      .writeAsStringSync('''
name: scanner
environment:
  sdk: ^3.13.0
dartvel:
  module:
    id: scanner
''');
  File(p.join(root.path, dvModuleLockFile)).writeAsStringSync(lock);
  return root.path;
}

Future<DartvelProjectGraph> _graph(String lock) =>
    DartvelProjectGraph.build(root: _project(lock), pkgName: 'pin_app');

void main() {
  test('a foreign module carries both digests and where they came from',
      () async {
    final DartvelProjectGraph graph = await _graph('''
scanner:
  source: "maven:com.vendor:scanner"
  version: "4.2.0"
  sourceDigest: "${'3' * 64}"
  wrapperHash: "${'9' * 64}"
  generator: "1.7.2"
  resolvedFrom: "https://repo1.maven.org/"
  targets: [android]
  capabilities: [nativeBindings]
''');

    final DVGraphModule module =
        graph.modules.firstWhere((DVGraphModule m) => m.id == 'scanner');
    // A nested pin rather than fields spread across the node: `source` on a
    // module already means where its project is, and provenance is one thing
    // a reader looks for in one place.
    expect(module.pin!.source, 'maven:com.vendor:scanner');
    expect(module.pin!.sourceDigest, startsWith('333'));
    expect(module.pin!.wrapperHash, startsWith('999'));
    expect(module.pin!.generator, '1.7.2');
    expect(module.pin!.targets, <String>['android']);
  });

  test('it survives a round trip through graph.json', () async {
    // Every reader of the graph gets it from the JSON, so a field that is
    // computed and not serialised is a field only this process has.
    final DartvelProjectGraph graph = await _graph('''
scanner:
  source: "cargo:image"
  version: "0.25.0"
  sourceDigest: "${'a' * 64}"
  wrapperHash: "${'b' * 64}"
  capabilities: []
''');
    final DVGraphModule back = DVGraphModule.fromJson(
      graph.modules
          .firstWhere((DVGraphModule m) => m.id == 'scanner')
          .toJson(),
    );

    expect(back.pin!.source, 'cargo:image');
    expect(back.pin!.wrapperHash, startsWith('bbb'));
  });

  test('a module from pub.dev carries its archive digest and no wrapper',
      () async {
    final DartvelProjectGraph graph = await _graph('''
scanner:
  version: "4.2.0"
  sha256: "${'c' * 64}"
  publisher: "vendor.com"
  key: null
  capabilities: []
''');

    final DVGraphModule module =
        graph.modules.firstWhere((DVGraphModule m) => m.id == 'scanner');
    expect(module.pin!.sha256, startsWith('ccc'));
    expect(module.pin!.publisher, 'vendor.com');
    expect(module.pin!.wrapperHash, isNull);
    expect(module.pin!.source, isNull);
  });

  test('a module nobody pinned says nothing rather than guessing', () async {
    // Unpinned is a real state -- a path module in a monorepo is never
    // pinned -- and inventing a digest for it would make the graph claim
    // provenance it does not have.
    final DartvelProjectGraph graph = await _graph('');

    final DVGraphModule module =
        graph.modules.firstWhere((DVGraphModule m) => m.id == 'scanner');
    expect(module.pin, isNull);
  });
}
