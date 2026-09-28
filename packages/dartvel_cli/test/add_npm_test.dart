// `dartvel add npm:<name>`: resolved from the registry, checked against the
// integrity it publishes, wrapped and pinned.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart';
import 'package:dartvel_cli/src/commands/add_command.dart';
import 'package:dartvel_cli/src/module_trust/module_lock.dart';
import 'package:dartvel_cli/src/modules/foreign/resolver.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

class _Registry extends DVSourceFetcher {
  _Registry(this.tarball, {this.integrity});
  final List<int> tarball;
  final String? integrity;
  final List<String> asked = <String>[];

  @override
  Future<String> getText(Uri url) async {
    asked.add('$url');
    Map<String, Object?> release(String v) => <String, Object?>{
          'version': v,
          'dist': <String, Object?>{
            'tarball': 'https://registry.npmjs.org/@acme/text-kit/-/text-kit-$v.tgz',
            'integrity':
                integrity ?? 'sha512-${base64Encode(sha512.convert(tarball).bytes)}',
          },
        };
    return jsonEncode(<String, Object?>{
      'dist-tags': <String, Object?>{'latest': '3.1.0'},
      'versions': <String, Object?>{
        for (final String v in <String>['2.9.0', '3.0.0', '3.1.0', '4.0.0-beta.1'])
          v: release(v),
      },
    });
  }

  @override
  Future<List<int>> getBytes(Uri url) async {
    asked.add('$url');
    return tarball;
  }
}

List<int> npmTarball() {
  final Directory src = Directory.systemTemp.createTempSync('dv_npm_src_');
  addTearDown(() => src.deleteSync(recursive: true));
  final Directory pkg = Directory(p.join(src.path, 'package'))..createSync();
  File(p.join(pkg.path, 'package.json')).writeAsStringSync(jsonEncode(<String, Object?>{
    'name': '@acme/text-kit',
    'version': '3.1.0',
    'module': 'index.mjs',
    'types': 'index.d.ts',
  }));
  File(p.join(pkg.path, 'index.mjs'))
      .writeAsStringSync('export function slug(t) { return t.toLowerCase(); }\n');
  File(p.join(pkg.path, 'index.d.ts'))
      .writeAsStringSync('export declare function slug(text: string): string;\n');
  final String out = '${src.path}.tgz';
  addTearDown(() => File(out).deleteSync());
  expect(Process.runSync('tar', <String>['-czf', out, '-C', src.path, 'package']).exitCode, 0);
  return File(out).readAsBytesSync();
}

String project() {
  final Directory root = Directory.systemTemp.createTempSync('dv_add_npm_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(
      'name: shop\nenvironment:\n  sdk: ^3.13.0\ndartvel:\n  app:\n    name: Shop\n');
  return root.path;
}

Future<int> run(String root, List<String> args, DVSourceFetcher fetcher) async {
  final CommandRunner<void> runner = CommandRunner<void>('dartvel', 'test')
    ..addCommand(AddCommand(root: root, fetcher: fetcher));
  try {
    await runner.run(<String>['add', ...args]);
  } on DVAddRefused {
    return 1;
  }
  return 0;
}

void main() {
  test('npm: resolves the range, verifies the tarball and wraps the package',
      () async {
    final String root = project();
    final List<int> tarball = npmTarball();
    final _Registry registry = _Registry(tarball);

    expect(await run(root, <String>['npm:@acme/text-kit@^3.0.0'], registry), 0);

    expect(registry.asked.first, 'https://registry.npmjs.org/@acme%2Ftext-kit');
    expect(registry.asked,
        contains('https://registry.npmjs.org/@acme/text-kit/-/text-kit-3.1.0.tgz'));
    final String module = p.join(root, 'modules', 'dv_text_kit_module');
    final YamlMap pubspec =
        loadYaml(File(p.join(module, 'pubspec.yaml')).readAsStringSync()) as YamlMap;
    expect(pubspec['dartvel']['module']['kind'], 'npm');
    expect(pubspec['dartvel']['module']['operations']['slug']['web'], 'real');
    expect(File(p.join(module, 'assets', 'npm', 'acme_text_kit.mjs')).existsSync(),
        isTrue);
    final DVModulePin pin = DVModuleLock.read(root).pins['dv_text_kit_module']!;
    expect(pin.source, 'npm:@acme/text-kit@3.1.0');
    expect(pin.sourceDigest, sha256.convert(tarball).toString());
    final YamlMap parent =
        loadYaml(File(p.join(root, 'pubspec.yaml')).readAsStringSync()) as YamlMap;
    expect(parent['dartvel']['modules']['textKit'], isNotNull);
  });

  test('a tarball that is not the one the registry names is refused', () async {
    final String root = project();
    final _Registry registry = _Registry(npmTarball(),
        integrity: 'sha512-${base64Encode(List<int>.filled(64, 7))}');
    expect(await run(root, <String>['npm:@acme/text-kit'], registry), 1);
    expect(Directory(p.join(root, 'modules')).existsSync(), isFalse);
    expect(File(p.join(root, dvModuleLockFile)).existsSync(), isFalse);
  });
}
