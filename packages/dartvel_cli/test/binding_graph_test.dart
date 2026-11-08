// The binding graph: how each call a mounted module declares reaches the
// place it runs, as kind, environment, target and carrier.
//
// Kind, source language and target are separate dimensions, and the carrier
// is a fourth: a C library is DVFfiBinding on a device and DVWasmBinding in
// a browser, and Swift is DVFfiBinding too. A module made of Dart, or of a
// described API carried over DV.Http, crosses no foreign boundary and so has
// no binding at all -- reporting one would invent a boundary that is not
// there. A cell that cannot be filled is either declared (compat, noop,
// unavailable) or a diagnostic: DV-BIND-005 when the kind cannot exist on
// the target, DV-BIND-007 when it could and no carrier is built.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/inspect_command.dart';
import 'package:dartvel_cli/src/graph/binding_graph.dart';
import 'package:dartvel_cli/src/graph/project_graph.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A project mounting one generated module per entry: id to the module
/// block written under `dartvel.module`.
String project(Map<String, String> modules) {
  final Directory root = Directory.systemTemp.createTempSync('dv_bindings_');
  addTearDown(() => root.deleteSync(recursive: true));
  final StringBuffer parent = StringBuffer('name: shop\ndartvel:\n  modules:\n');
  for (final MapEntry<String, String> m in modules.entries) {
    parent
      ..writeln('    ${m.key}:')
      ..writeln('      source: { path: modules/dv_${m.key}_module }')
      ..writeln('      mount: /${m.key}');
    File(p.join(root.path, 'modules', 'dv_${m.key}_module', 'pubspec.yaml'))
      ..createSync(recursive: true)
      ..writeAsStringSync('name: dv_${m.key}_module\n'
          'dartvel:\n  module:\n    id: ${m.key}\n${m.value}');
  }
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('$parent');
  return root.path;
}

const String ffiModule = '''
    kind: ffi
    surface: ZlibModule
    operations:
      crc32:
        native: real
        web: real
        backend: real
      deflate:
        native: real
        web: unavailable
        backend: real
''';

const String jvmModule = '''
    kind: jvm
    surface: ScannerModule
    targets: [android]
    operations:
      scan:
        native: real
        web: unavailable
        backend: compat
''';

const String npmModule = '''
    kind: npm
    surface: SlugModule
    targets: [linux, macos, windows]
    operations:
      slugify:
        native: real
        web: real
        backend: real
''';

const String dartModule = '''
    kind: dartPackage
    surface: TextkitModule
    operations:
      slug:
        native: real
        web: real
        backend: real
''';

DVBindingNode node(DVBindingGraph graph, String module, String environment,
        [String? target]) =>
    graph.nodes.singleWhere((DVBindingNode n) =>
        n.module == module &&
        n.environment == environment &&
        n.target == target);

void main() {
  test('a C library is FFI on every device and the backend, and WASM in the '
      'browser', () {
    final DVBindingGraph graph =
        DVBindingGraph.read(project(<String, String>{'zlib': ffiModule}));

    for (final String target in dvBindingNativeTargets) {
      final DVBindingNode device = node(graph, 'zlib', 'native', target);
      expect(device.kind, 'DVFfiBinding');
      expect(device.carrier, isNotEmpty);
      expect(device.operations, <String>['crc32', 'deflate']);
      expect(device.problem, isNull);
    }
    final DVBindingNode web = node(graph, 'zlib', 'web');
    expect(web.kind, 'DVWasmBinding');
    expect(web.operations, <String>['crc32']);
    expect(web.declared, <String, String>{'deflate': 'unavailable'});
    expect(node(graph, 'zlib', 'backend').kind, 'DVFfiBinding');
    expect(graph.problems, isEmpty);
  });

  test('a JVM library is JNI on Android, reaches no other device, and its '
      'declared degradations are reported rather than hidden', () {
    final DVBindingGraph graph =
        DVBindingGraph.read(project(<String, String>{'scanner': jvmModule}));

    final DVBindingNode android = node(graph, 'scanner', 'native', 'android');
    expect(android.kind, 'DVJniBinding');
    expect(android.operations, <String>['scan']);
    // The module declares android alone, so no other device has a node.
    expect(
        graph.nodes.where((DVBindingNode n) =>
            n.module == 'scanner' && n.environment == 'native'),
        hasLength(1));
    final DVBindingNode web = node(graph, 'scanner', 'web');
    expect(web.kind, isNull);
    expect(web.carrier, isNull);
    expect(web.declared, <String, String>{'scan': 'unavailable'});
    expect(node(graph, 'scanner', 'backend').declared,
        <String, String>{'scan': 'compat'});
    expect(graph.problems, isEmpty);
  });

  test('an npm package is Node on the desktops and a web binding in the '
      'browser', () {
    final DVBindingGraph graph =
        DVBindingGraph.read(project(<String, String>{'slug': npmModule}));
    expect(node(graph, 'slug', 'native', 'linux').kind, 'DVNodeJsBinding');
    expect(node(graph, 'slug', 'web').kind, 'DVWebBinding');
    expect(node(graph, 'slug', 'backend').kind, 'DVNodeJsBinding');
  });

  test('a Dart module crosses no boundary and has no binding', () {
    final DVBindingGraph graph =
        DVBindingGraph.read(project(<String, String>{'textkit': dartModule}));
    expect(graph.nodes, isEmpty);
  });

  test('a JVM module declaring iOS is DV-BIND-005: JNI does not exist there',
      () {
    final DVBindingGraph graph = DVBindingGraph.read(project(<String, String>{
      'scanner': jvmModule.replaceFirst('[android]', '[android, ios]'),
    }));
    final DVBindingNode ios = node(graph, 'scanner', 'native', 'ios');
    expect(ios.kind, 'DVJniBinding');
    expect(ios.carrier, isNull);
    expect(ios.problem, allOf(startsWith('DV-BIND-005'), contains('scanner'),
        contains('ios')));
  });

  test('an npm module declaring Android is DV-BIND-007: no carrier brings '
      'Node to a phone', () {
    final DVBindingGraph graph = DVBindingGraph.read(project(<String, String>{
      'slug': npmModule.replaceFirst('[linux, macos, windows]', '[android]'),
    }));
    final DVBindingNode android = node(graph, 'slug', 'native', 'android');
    expect(android.problem, allOf(startsWith('DV-BIND-007'),
        contains('DVNodeJsBinding'), contains('android')));
    expect(graph.problems.single, android.problem);
  });

  test('a JVM operation declared real in the browser is DV-BIND-005', () {
    final DVBindingGraph graph = DVBindingGraph.read(project(<String, String>{
      'scanner': jvmModule.replaceFirst('web: unavailable', 'web: real'),
    }));
    expect(node(graph, 'scanner', 'web').problem, startsWith('DV-BIND-005'));
  });

  test('the project graph records the bindings, and inspect bindings --json '
      'prints them', () async {
    final String root = project(<String, String>{'zlib': ffiModule});
    final DartvelProjectGraph graph =
        await DartvelProjectGraph.build(root: root, pkgName: 'shop');
    final List<Object?> recorded = graph.toJson()['bindings']! as List<Object?>;
    expect(recorded, isNotEmpty);

    final List<String> out = <String>[];
    await runZoned(() async {
      final CommandRunner<void> runner = CommandRunner<void>('dartvel', 'test')
        ..addCommand(InspectCommand(root: root));
      await runner.run(<String>['inspect', 'bindings', '--json']);
    }, zoneSpecification: ZoneSpecification(
        print: (Zone self, ZoneDelegate parent, Zone zone, String line) =>
            out.add(line)));
    final List<Object?> printed = jsonDecode(out.join()) as List<Object?>;
    expect(printed, recorded);
    final Map<String, Object?> web = printed
        .cast<Map<String, Object?>>()
        .singleWhere((Map<String, Object?> n) => n['environment'] == 'web');
    expect(web['kind'], 'DVWasmBinding');
    expect(web['module'], 'zlib');
    expect(web['moduleKind'], 'ffi');
  });
}
