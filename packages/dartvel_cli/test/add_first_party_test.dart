// `dartvel add <name>` for a module Dartvel maintains itself.
//
// The first-party modules live in this repository's modules/ folder and are
// published to pub.dev like any other package. Adding one by name is the
// same act as adding any module: a dependency and a mount. What the name
// saves is knowing the package, the id and that its carried operations need
// a policy.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/add_command.dart';
import 'package:dartvel_cli/src/commands/version_command.dart'
    show dartvelCliVersion;
import 'package:dartvel_cli/src/graph/module_mounts.dart';
import 'package:dartvel_cli/src/modules/first_party.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

String _project({String modules = ''}) {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_add_fp_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shop
environment:
  sdk: ^3.13.0
dependencies:
  dartvel_core: ^$dartvelCliVersion
dartvel:
  app:
    name: Shop$modules
''');
  return root.path;
}

Future<int> _run(String root, List<String> args) async {
  final CommandRunner<void> runner = CommandRunner<void>('dartvel', 'test')
    ..addCommand(AddCommand(root: root));
  try {
    await runner.run(<String>['add', ...args]);
  } on UsageException {
    return 64;
  } on DVAddRefused {
    return 1;
  }
  return 0;
}

String _pubspec(String root) =>
    File(p.join(root, 'pubspec.yaml')).readAsStringSync();

/// This repository's root, from wherever the tests are run.
String _repository() {
  Directory dir = Directory.current;
  while (!Directory(p.join(dir.path, 'modules')).existsSync() ||
      !Directory(p.join(dir.path, 'packages', 'dartvel_cli')).existsSync()) {
    final Directory up = dir.parent;
    if (up.path == dir.path) fail('modules/ was not found above the tests');
    dir = up;
  }
  return dir.path;
}

void main() {
  test('a first-party module is added by name: a dependency and a mount',
      () async {
    final String root = _project();

    expect(await _run(root, <String>['meta-pixel']), 0);

    final YamlMap doc = loadYaml(_pubspec(root)) as YamlMap;
    expect(doc['dependencies']['dartvel_meta_pixel'], '^$dartvelCliVersion');
    // What was there is still there.
    expect(doc['dependencies']['dartvel_core'], '^$dartvelCliVersion');
    final YamlMap mount = doc['dartvel']['modules']['metaPixel'] as YamlMap;
    expect(mount['package'], 'dartvel_meta_pixel');
    // Its events are carried to the backend, which runs them with the
    // server's authority, so the mount says who may call them.
    expect(mount['backendPolicy'], 'public');
    expect(mount.containsKey('source'), isFalse);
    // Nothing is generated: the module is the package pub fetches.
    expect(Directory(p.join(root, 'modules')).existsSync(), isFalse);
  });

  test('the names people call them by all resolve', () {
    expect(dvFirstPartyModule('meta-pixel')?.package, 'dartvel_meta_pixel');
    expect(dvFirstPartyModule('facebook-pixel')?.package, 'dartvel_meta_pixel');
    expect(dvFirstPartyModule('dartvel_meta_pixel')?.package,
        'dartvel_meta_pixel');
    expect(dvFirstPartyModule('google-analytics')?.package,
        'dartvel_google_analytics');
    expect(dvFirstPartyModule('ga4')?.package, 'dartvel_google_analytics');
    expect(dvFirstPartyModule('woocommerce')?.package, 'dartvel_woocommerce');
    expect(dvFirstPartyModule('WooCommerce')?.package, 'dartvel_woocommerce');
    expect(dvFirstPartyModule('stripe'), isNull);
  });

  test('--as names the module something else', () async {
    final String root = _project();
    expect(await _run(root, <String>['ga4', '--as', 'analytics']), 0);
    final YamlMap doc = loadYaml(_pubspec(root)) as YamlMap;
    expect(doc['dartvel']['modules']['analytics']['package'],
        'dartvel_google_analytics');
  });

  test('--dry-run writes nothing', () async {
    final String root = _project();
    final String before = _pubspec(root);
    expect(await _run(root, <String>['woocommerce', '--dry-run']), 0);
    expect(_pubspec(root), before);
  });

  test('a module already mounted under that id is refused, untouched',
      () async {
    final String root = _project(modules: '''

  modules:
    woocommerce:
      package: something_else''');
    final String before = _pubspec(root);
    expect(await _run(root, <String>['woocommerce']), 1);
    expect(_pubspec(root), before);
  });

  test('a directory of that name is the source, not the catalogue', () async {
    // `dartvel add woocommerce` beside a project folder called woocommerce
    // means the folder: what is on disk was put there by whoever is asking.
    final String root = _project();
    File(p.join(root, 'woocommerce', 'pubspec.yaml'))
      ..createSync(recursive: true)
      ..writeAsStringSync('name: my_store\ndartvel:\n  module:\n    id: shop\n');
    expect(await _run(root, <String>['woocommerce']), 0);
    final YamlMap doc = loadYaml(_pubspec(root)) as YamlMap;
    expect(doc['dartvel']['modules']['shop']['source']['path'], 'woocommerce');
  });

  test('a name that is neither is still refused as before', () async {
    final String root = _project();
    final String before = _pubspec(root);
    expect(await _run(root, <String>['no-such-module']), 1);
    expect(_pubspec(root), before);
  });

  test('once pub has fetched it, the mount is a mounted package', () async {
    final String root = _project();
    expect(await _run(root, <String>['meta-pixel']), 0);
    File(p.join(root, '.dart_tool', 'package_config.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(<String, Object?>{
        'configVersion': 2,
        'packages': <Object?>[
          <String, Object?>{
            'name': 'dartvel_meta_pixel',
            'rootUri': Uri.directory(
                    p.join(_repository(), 'modules', 'dartvel_meta_pixel'))
                .toString(),
            'packageUri': 'lib/',
          },
        ],
      }));
    final DVModuleMount mount = dvDiscoverModuleMounts(root).single;
    expect(mount.problems, isEmpty);
    expect(mount.mounted, isTrue);
    expect(mount.id, 'metaPixel');
    expect(mount.surface, 'MetaPixel');
    expect(mount.start, isNotNull);
    expect(mount.csp['script-src'], contains('https://connect.facebook.net'));
  });

  group('the catalogue and the modules folder agree', () {
    for (final DVFirstPartyModule module in dvFirstPartyModules) {
      test(module.package, () {
        final File pubspec = File(
            p.join(_repository(), 'modules', module.package, 'pubspec.yaml'));
        expect(pubspec.existsSync(), isTrue,
            reason: 'modules/${module.package} is in the catalogue and not '
                'in the repository');
        final YamlMap doc = loadYaml(pubspec.readAsStringSync()) as YamlMap;
        expect(doc['name'], module.package);
        expect(doc['dartvel']['module']['id'], module.id);
        // `dartvel add` writes ^<this CLI's version>, so a module that is
        // not released with the CLI is one nobody can add.
        expect('${doc['version']}', dartvelCliVersion);
        expect(
          File(p.join(pubspec.parent.path, 'README.md')).existsSync(),
          isTrue,
        );
      });
    }

    test('every package in modules/ is in the catalogue', () {
      final List<String> onDisk = Directory(p.join(_repository(), 'modules'))
          .listSync()
          .whereType<Directory>()
          .where((Directory d) =>
              File(p.join(d.path, 'pubspec.yaml')).existsSync())
          .map((Directory d) => p.basename(d.path))
          .toList()
        ..sort();
      expect(
        onDisk,
        dvFirstPartyModules.map((DVFirstPartyModule m) => m.package).toList()
          ..sort(),
      );
    });
  });
}
