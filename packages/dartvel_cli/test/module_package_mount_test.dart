// A module mounted as a dependency: `package: acme_payments`.
//
// The specification's grant is written against a package, and mount
// discovery understood only `source.path` -- so a module mounted the way the
// specification mounts one was reported as needing a source path, and the
// build refused it before anything could check its pin or its grant.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/graph/module_mounts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _page = '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

@DVPage(title: 'A page')
Widget _aPage(BuildContext context) => const DVText('hi');
''';

Directory parent({bool resolved = true}) {
  final Directory root = Directory.systemTemp.createTempSync(
    'dartvel_pkgmount_',
  );
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shopfront
dartvel:
  modules:
    store:
      package: acme_store
      mount: /store
''');
  final Directory module = Directory(p.join(root.path, 'vendor', 'acme_store'))
    ..createSync(recursive: true);
  File(p.join(module.path, 'pubspec.yaml')).writeAsStringSync('''
name: acme_store
dartvel:
  module:
    id: store
''');
  File(p.join(module.path, 'lib', 'pages', 'index.page.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync(_page);
  File(p.join(root.path, '.dart_tool', 'package_config.json'))
    ..createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode(<String, Object?>{
        'configVersion': 2,
        'packages': <Object?>[
          if (resolved)
            <String, Object?>{
              'name': 'acme_store',
              'rootUri': '../vendor/acme_store/',
              'packageUri': 'lib/',
            },
        ],
      }),
    );
  return root;
}

void main() {
  test('a package mount resolves through the package config and mounts', () {
    final Directory root = parent();
    final DVModuleMount mount = dvDiscoverModuleMounts(root.path).single;

    expect(mount.problems, isEmpty);
    expect(mount.mounted, isTrue);
    expect(mount.fromPackage, isTrue);
    expect(mount.packageName, 'acme_store');
    expect(
      p.normalize(p.join(root.path, mount.sourcePath)),
      p.join(root.path, 'vendor', 'acme_store'),
    );
    expect(mount.routes.map((DVModuleRoute r) => r.mounted), <String>[
      '/store',
    ]);
    expect(
      mount.routes.single.import,
      'package:acme_store/pages/index.page.dart',
    );
  });

  test('a source mount is not a package mount', () {
    final Directory root = parent();
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shopfront
dartvel:
  modules:
    store:
      source: { path: vendor/acme_store }
      mount: /store
''');
    expect(dvDiscoverModuleMounts(root.path).single.fromPackage, isFalse);
  });

  test('a package that does not resolve is not mounted, and says why', () {
    final DVModuleMount mount = dvDiscoverModuleMounts(
      parent(resolved: false).path,
    ).single;
    expect(mount.mounted, isFalse);
    expect(mount.problems.join('\n'), contains('pub get'));
  });
}
