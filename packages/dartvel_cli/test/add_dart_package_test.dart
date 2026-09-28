// `dartvel add pub:<name>`, `git:<url>` and `path:<dir>`: a Dart package,
// wrapped as a module and pinned.
//
// The registry is faked; the archive is a real tarball of a real package,
// so what is checked is what the command does with what it fetched: the
// version it chose, the digest it verified, the package it generated, the
// three lines it adds to the parent's pubspec and the pin it writes. The
// failures that matter are the quiet ones: an archive whose digest does not
// match what the registry says was served, a prerelease taken for a caret,
// a refusal that leaves half a module behind.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart';
import 'package:dartvel_cli/src/commands/add_command.dart';
import 'package:dartvel_cli/src/module_trust/module_lock.dart';
import 'package:dartvel_cli/src/modules/foreign/module_writer.dart';
import 'package:dartvel_cli/src/modules/foreign/resolver.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const String _code = '''
/// Turns [text] into a slug.
String slug(String text) => text.toLowerCase().replaceAll(' ', '-');
''';

class _FakeRegistry extends DVSourceFetcher {
  _FakeRegistry(this.archive, {String? claimedDigest})
      : claimed = claimedDigest ?? sha256.convert(archive).toString();

  final List<int> archive;
  final String claimed;
  final List<String> asked = <String>[];

  @override
  Future<String> getText(Uri url) async {
    asked.add('$url');
    return jsonEncode(<String, Object?>{
      'name': 'textkit',
      'versions': <Object?>[
        for (final String v in <String>['1.0.0', '1.2.0', '2.0.0-dev.1'])
          <String, Object?>{
            'version': v,
            'archive_url': 'https://pub.dev/packages/textkit/versions/$v.tar.gz',
            'archive_sha256': claimed,
          },
      ],
    });
  }

  @override
  Future<List<int>> getBytes(Uri url) async {
    asked.add('$url');
    return archive;
  }
}

String project() {
  final Directory root = Directory.systemTemp.createTempSync('dv_add_dart_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shop
environment:
  sdk: ^3.13.0
dependencies:
  flutter:
    sdk: flutter
dartvel:
  app:
    name: Shop
''');
  return root.path;
}

List<int> tarball(String code) {
  final Directory src = Directory.systemTemp.createTempSync('dv_textkit_');
  addTearDown(() => src.deleteSync(recursive: true));
  File(p.join(src.path, 'pubspec.yaml'))
      .writeAsStringSync('name: textkit\nversion: 1.2.0\n');
  File(p.join(src.path, 'lib', 'textkit.dart'))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(code);
  final String out = '${src.path}.tar.gz';
  addTearDown(() => File(out).deleteSync());
  final ProcessResult r = Process.runSync(
      'tar', <String>['-czf', out, '-C', src.path, '.']);
  expect(r.exitCode, 0, reason: '${r.stderr}');
  return File(out).readAsBytesSync();
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
  test('pub: takes the newest version the constraint allows, verified, and '
      'wraps it', () async {
    final String root = project();
    final List<int> archive = tarball(_code);
    final _FakeRegistry registry = _FakeRegistry(archive);

    expect(await run(root, <String>['pub:textkit@^1.0.0'], registry), 0);

    // 1.2.0, not 2.0.0-dev.1: a caret is not a request for a prerelease.
    expect(registry.asked,
        contains('https://pub.dev/packages/textkit/versions/1.2.0.tar.gz'));
    final String module = p.join(root, 'modules', 'dv_textkit_module');
    final YamlMap pubspec = loadYaml(
        File(p.join(module, 'pubspec.yaml')).readAsStringSync()) as YamlMap;
    expect(pubspec['dependencies']['textkit'], '1.2.0');
    expect(pubspec['dartvel']['module']['kind'], 'dartPackage');
    expect(pubspec['dartvel']['module']['operations']['slug']['web'], 'real');

    final YamlMap parent = loadYaml(
        File(p.join(root, 'pubspec.yaml')).readAsStringSync()) as YamlMap;
    expect(parent['dependencies']['dv_textkit_module']['path'],
        'modules/dv_textkit_module');
    expect(parent['dartvel']['modules']['textkit']['source']['path'],
        'modules/dv_textkit_module');

    final DVModulePin pin = DVModuleLock.read(root).pins['dv_textkit_module']!;
    expect(pin.source, 'pub:textkit@1.2.0');
    expect(pin.version, '1.2.0');
    expect(pin.sourceDigest, sha256.convert(archive).toString());
    // The pin is of the generated files as they are on disk.
    final Map<String, String> files = <String, String>{
      for (final FileSystemEntity f
          in Directory(module).listSync(recursive: true))
        if (f is File)
          p.relative(f.path, from: module).replaceAll('\\', '/'):
              f.readAsStringSync(),
    };
    expect(pin.wrapperHash, dvWrapperHash(files));
    expect(pin.generator, startsWith('dartvel_cli '));
  });

  test('an archive that is not the one the registry names is refused, and '
      'nothing is written', () async {
    final String root = project();
    final String before =
        File(p.join(root, 'pubspec.yaml')).readAsStringSync();
    final _FakeRegistry registry =
        _FakeRegistry(tarball(_code), claimedDigest: 'ab' * 32);

    expect(await run(root, <String>['pub:textkit'], registry), 1);
    expect(File(p.join(root, 'pubspec.yaml')).readAsStringSync(), before);
    expect(Directory(p.join(root, 'modules')).existsSync(), isFalse);
    expect(File(p.join(root, dvModuleLockFile)).existsSync(), isFalse);
  });

  test('path: wraps a local package; a bare path still points at dart pub add',
      () async {
    final String root = project();
    final Directory local = Directory(p.join(root, 'vendor', 'textkit'))
      ..createSync(recursive: true);
    File(p.join(local.path, 'pubspec.yaml'))
        .writeAsStringSync('name: textkit\nversion: 0.3.0\n');
    File(p.join(local.path, 'lib', 'textkit.dart'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(_code);

    expect(await run(root, <String>['vendor/textkit'], _FakeRegistry(<int>[])),
        1);
    expect(await run(root, <String>['path:vendor/textkit', '--as', 'slugs'],
            _FakeRegistry(<int>[])),
        0);
    final YamlMap pubspec = loadYaml(File(p.join(
            root, 'modules', 'dv_slugs_module', 'pubspec.yaml'))
        .readAsStringSync()) as YamlMap;
    expect(pubspec['dependencies']['textkit']['path'], '../../vendor/textkit');
    expect(DVModuleLock.read(root).pins['dv_slugs_module']!.source,
        'path:vendor/textkit');
  });

  test('--dry-run says what each environment gets and writes nothing',
      () async {
    final String root = project();
    final String before =
        File(p.join(root, 'pubspec.yaml')).readAsStringSync();
    final DVSourceFetcher registry =
        _FakeRegistry(tarball("import 'dart:io';\n$_code"));
    final DVAddPlan plan =
        await AddCommand.planForeign(root, 'pub:textkit', fetcher: registry);
    final String out = plan.lines.join('\n');
    expect(await run(root, <String>['pub:textkit', '--dry-run'], registry), 0);
    expect(out, contains('slug'));
    expect(out, contains('native real'));
    expect(out, contains('web unavailable'));
    expect(File(p.join(root, 'pubspec.yaml')).readAsStringSync(), before);
    expect(Directory(p.join(root, 'modules')).existsSync(), isFalse);
  });

  test('a package with nothing to call is DV-MODULE-010', () async {
    final String root = project();
    expect(
        await run(root, <String>['pub:textkit'],
            _FakeRegistry(tarball('class Only {}\n'))),
        1);
    expect(Directory(p.join(root, 'modules')).existsSync(), isFalse);
  });
}
