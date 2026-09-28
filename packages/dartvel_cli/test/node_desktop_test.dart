// npm packages and WebAssembly on the desktop, through a bundled Node.
//
// The placement matrix gives a desktop client the same carrier the backend
// has: Node, run per call. The difference is where Node comes from -- the
// copy dartvel build puts beside the application, so the person running it
// needs nothing installed. Phones need nodejs-mobile, which is not built,
// so the module's native targets are the desktops and a call from a phone
// is refused at build time rather than failing on the device.
import 'dart:io';

import 'package:dartvel_cli/src/build/node_runtime_bundle.dart';
import 'package:dartvel_cli/src/modules/described_api.dart';
import 'package:dartvel_cli/src/modules/foreign/module_writer.dart';
import 'package:dartvel_cli/src/modules/foreign/npm_module.dart';
import 'package:dartvel_cli/src/modules/foreign/npm_surface.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'npm_module_test.dart' show install, npmPackage, scratch;

Future<DVGeneratedModule> generate(Directory root) async {
  final DVNpmSurface surface = dvScanNpmPackage(npmPackage(root).path);
  return dvWriteForeignModule(dvNpmModuleSpec(
    id: 'textKit',
    source: 'npm:@acme/text-kit@3.1.0',
    surface: surface,
    bundles: await dvBundleNpm(surface),
  ));
}

void main() {
  test('a Node package is real on the desktop, and only there', () async {
    final DVGeneratedModule module = await generate(scratch());
    final YamlMap declared =
        (loadYaml(module.files['pubspec.yaml']!) as YamlMap)['dartvel']['module']
            as YamlMap;
    expect(declared['operations']['words']['native'], 'real');
    expect(declared['targets'], <String>['linux', 'macos', 'windows']);
  });

  test('the device carrier runs the package in the Node it is given',
      () async {
    final String? node = _which('node');
    if (node == null) {
      markTestSkipped('no node');
      return;
    }
    final Directory root = scratch();
    final DVGeneratedModule module = await generate(root);
    final String config = install(root, module);
    final File probe = File(p.join(root.path, 'probe.dart'))
      ..writeAsStringSync('''
import 'package:${module.packageName}/src/carrier_native.dart' as native;

Future<void> main() async {
  print(await native.words('a b c'));
}
''');
    // A directory with no node in it on PATH: the one named is the one used.
    final ProcessResult run = await Process.run(
        Platform.resolvedExecutable, <String>['--packages=$config', probe.path],
        environment: <String, String>{'DARTVEL_NODE': node, 'PATH': '/nonexistent'},
        includeParentEnvironment: false);
    expect('${run.stdout}${run.stderr}', contains('[a, b, c]'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  group('dartvel build puts Node in the bundle', () {
    Directory project({required bool native}) {
      final Directory root = scratch();
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shop
dartvel:
  modules:
    textKit:
      source:
        path: modules/dv_text_kit_module
      mount: /text-kit
''');
      File(p.join(root.path, 'modules', 'dv_text_kit_module', 'pubspec.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('''
name: dv_text_kit_module
dartvel:
  module:
    id: textKit
    kind: npm
    operations:
      words:
        native: ${native ? 'real' : 'unavailable'}
        web: real
        backend: real
''');
      return root;
    }

    test('when a module runs in Node on the device', () {
      final Directory root = project(native: true);
      final File fakeNode = File(p.join(root.path, 'node-bin'))
        ..writeAsStringSync('#!/bin/sh\necho node');
      final Directory bundle = Directory(p.join(root.path, 'bundle'))
        ..createSync();
      final DVNodeBundle result =
          dvBundleNodeRuntime(root.path, bundle.path, node: fakeNode.path);
      expect(result.modules, <String>['textKit']);
      expect(File(p.join(bundle.path, 'lib', 'node')).readAsStringSync(),
          contains('echo node'));
    });

    test('and not otherwise', () {
      final Directory root = project(native: false);
      final Directory bundle = Directory(p.join(root.path, 'bundle'))
        ..createSync();
      final DVNodeBundle result = dvBundleNodeRuntime(root.path, bundle.path,
          node: '/bin/true');
      expect(result.modules, isEmpty);
      expect(File(p.join(bundle.path, 'lib', 'node')).existsSync(), isFalse);
    });

    test('says what is missing when the host has no Node to copy', () {
      final Directory root = project(native: true);
      final Directory bundle = Directory(p.join(root.path, 'bundle'))
        ..createSync();
      final DVNodeBundle result =
          dvBundleNodeRuntime(root.path, bundle.path, node: null);
      expect(result.problem, contains('textKit'));
      expect(result.problem, contains('node'));
    });
  });
}

String? _which(String name) {
  final ProcessResult r = Process.runSync('which', <String>[name]);
  return r.exitCode == 0 ? '${r.stdout}'.trim() : null;
}
