// `dartvel upgrade --project` moves a project's Dartvel packages to the
// release of the CLI it is run with.
//
// Dartvel's version followed its own 0.x line until 0.13.51 and follows
// Flutter's from 3.47.0. A caret never crosses that: `^0.13.51` stops below
// 0.14.0, so `pub upgrade` on an existing project stays on 0.13.51 for ever
// and says nothing. Moving across is a change to pubspec.yaml, and this is
// the command that makes it.
//
// The failures worth testing are the quiet ones: a constraint spelled the long
// way left behind, an override or a path rewritten into a hosted version, a
// project newer than the CLI moved backwards, a mounted module left on the old
// line so the parent cannot resolve, and a pubspec left changed when the
// resolver refused it.
import 'dart:io';

import 'package:dartvel_cli/src/commands/upgrade_command.dart';
import 'package:dartvel_cli/src/modules/first_party.dart';
import 'package:dartvel_cli/src/templates/project_templates.dart';
import 'package:dartvel_cli/src/upgrade/project_upgrade.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

const String _target = dartvelPackageVersion;

/// An application on the last release of the 0.x line, as `dartvel create`
/// wrote it then.
const String _app01351 = '''
name: shop
description: A shop.
environment:
  sdk: ">=3.13.0 <4.0.0"
  flutter: ">=3.47.0"

dependencies:
  flutter:
    sdk: flutter
  dartvel_core: ^0.13.51
  dartvel_shelf: ^0.13.51 # the server
  dartvel_flutter:
    hosted: https://pub.dev
    version: ^0.13.51
  dartvel_scene: "^0.13.51"
  go_router: ^14.2.0

dev_dependencies:
  dartvel_cli: ^0.13.51
  test: ^1.25.0

dartvel:
  name: Shop
''';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('dv_project_upgrade_'));
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  void write(String rel, String content) {
    File(p.join(root.path, rel))
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  String read(String rel) => File(p.join(root.path, rel)).readAsStringSync();

  test('this CLI is past the 0.x line, which is what the move is to', () {
    expect(Version.parse(_target).major, greaterThanOrEqualTo(3));
    expect(VersionConstraint.parse('^0.13.51').allows(Version.parse(_target)),
        isFalse);
  });

  group('the pubspec rewrite', () {
    test('every Dartvel constraint moves to this release, in both spellings',
        () {
      final DVProjectUpgrade result = dvUpgradeProjectPubspec(_app01351);
      expect(result.blocked, isEmpty);
      expect(
        result.moved.map((DVConstraintMove m) => m.package),
        <String>[
          'dartvel_core',
          'dartvel_shelf',
          'dartvel_flutter',
          'dartvel_scene',
          'dartvel_cli',
        ],
      );
      expect(result.moved.first.from, '^0.13.51');
      expect(result.moved.first.to, '^$_target');
      expect(
        result.pubspec,
        _app01351
            .replaceAll('"^0.13.51"', '^$_target')
            .replaceAll('^0.13.51', '^$_target'),
      );
    });

    // A first-party module (dartvel_google_analytics, dartvel_meta_pixel, ...)
    // is published with every release. Left on the old one, it is no longer
    // "released with the framework", so the next build refuses it as an
    // unpinned module (sigmadev.digital, 26 Nov 2026: 3.47.13 modules under a
    // 3.47.15 framework stopped the web-server build).
    // (A range that already admits this release is left as written and the
    // lock is resolved forward instead: the next test covers that path, since
    // the packages resolved forward are dvReleasedPackages.)
    test('first-party modules move with the framework', () {
      const String app = '''
name: site
dependencies:
  dartvel_core: ^0.13.51
  dartvel_google_analytics: ^0.13.51
  dartvel_meta_pixel: ^0.13.51
dev_dependencies:
  dartvel_cli: ^0.13.51
''';
      final DVProjectUpgrade result = dvUpgradeProjectPubspec(app);
      expect(result.blocked, isEmpty);
      expect(
        result.moved.map((DVConstraintMove m) => m.package),
        <String>[
          'dartvel_core',
          'dartvel_google_analytics',
          'dartvel_meta_pixel',
          'dartvel_cli',
        ],
      );
      expect(result.pubspec, app.replaceAll('^0.13.51', '^$_target'));
    });

    test('every first-party module is one of the released packages', () {
      for (final DVFirstPartyModule module in dvFirstPartyModules) {
        expect(dvReleasedPackages, contains(module.package),
            reason: '${module.package} is published with every release');
      }
    });

    test('nothing else in the file is touched', () {
      final DVProjectUpgrade result = dvUpgradeProjectPubspec(_app01351);
      expect(result.pubspec, contains('go_router: ^14.2.0'));
      expect(result.pubspec, contains('test: ^1.25.0'));
      expect(result.pubspec, contains('# the server'));
      expect(result.pubspec, contains('sdk: ">=3.13.0 <4.0.0"'));
      expect(
        result.pubspec.split('\n').length,
        _app01351.split('\n').length,
      );
    });

    test('a project already on this release is left exactly as it is', () {
      final String current = _app01351.replaceAll('0.13.51', _target);
      final DVProjectUpgrade result = dvUpgradeProjectPubspec(current);
      expect(result.moved, isEmpty);
      expect(result.pubspec, current);
    });

    test('a range that already admits this release is not narrowed', () {
      const String ranged = '''
name: shop
dependencies:
  dartvel_core: ">=0.13.0 <4.0.0"
''';
      final DVProjectUpgrade result = dvUpgradeProjectPubspec(ranged);
      expect(result.moved, isEmpty);
      expect(result.pubspec, ranged);
    });

    test('a path, a git source and an override are reported, not rewritten',
        () {
      const String local = '''
name: shop
dependencies:
  dartvel_core:
    path: ../dartvel_core
  dartvel_flutter:
    git:
      url: https://github.com/Danroyal001/dartvel_dev.git
      path: packages/dartvel_flutter
  dartvel_shelf: ^0.13.51

dependency_overrides:
  dartvel_shelf: 0.13.40
''';
      final DVProjectUpgrade result = dvUpgradeProjectPubspec(local);
      expect(result.pubspec, contains('dartvel_shelf: ^$_target'));
      expect(result.pubspec, contains('dartvel_shelf: 0.13.40'));
      expect(result.pubspec, contains('path: ../dartvel_core'));
      expect(result.pubspec, contains('path: packages/dartvel_flutter'));
      expect(
        result.left.map((DVConstraintLeft l) => l.package),
        containsAll(<String>['dartvel_core', 'dartvel_flutter']),
      );
      expect(
        result.left.any(
          (DVConstraintLeft l) =>
              l.package == 'dartvel_shelf' && l.reason.contains('override'),
        ),
        isTrue,
      );
    });

    test('a project newer than this CLI is refused, never moved backwards',
        () {
      const String newer = '''
name: shop
dependencies:
  dartvel_core: ^99.0.0
  dartvel_flutter: ^0.13.51
''';
      final DVProjectUpgrade result = dvUpgradeProjectPubspec(newer);
      expect(result.blocked.single, contains('dartvel_core'));
      expect(result.blocked.single, contains('dartvel update'));
      expect(result.pubspec, newer);
      expect(result.moved, isEmpty);
    });
  });

  group('the command', () {
    test('moves pubspec.yaml across and resolves it', () async {
      write('pubspec.yaml', _app01351);
      final List<String> out = <String>[];
      final List<String> resolved = <String>[];
      final int code = await dvRunUpgrade(
        root.path,
        plan: false,
        project: true,
        out: out.add,
        selfUpgrade: () async => fail('--project must not replace the CLI'),
        resolve: (String directory, {required bool flutter}) async {
          resolved.add('${flutter ? 'flutter' : 'dart'} $directory');
          return null;
        },
      );
      expect(code, 0);
      expect(read('pubspec.yaml'), isNot(contains('0.13.51')));
      expect(read('pubspec.yaml'), contains('dartvel_core: ^$_target'));
      expect(read('pubspec.yaml'), contains('dartvel_cli: ^$_target'));
      expect(resolved, <String>['flutter ${root.path}']);
      expect(out.join('\n'), contains('dartvel_core ^0.13.51 → ^$_target'));
    });

    test('a mounted module in the project moves with it', () async {
      write(
        'pubspec.yaml',
        '$_app01351'
        '  modules:\n'
        '    billing:\n'
        '      source:\n'
        '        path: modules/billing\n'
        '      mount: /billing\n',
      );
      write('modules/billing/pubspec.yaml', '''
name: billing
dependencies:
  dartvel_core: ^0.13.51
dartvel:
  module:
    id: billing
''');
      final List<String> out = <String>[];
      final int code = await dvRunUpgrade(
        root.path,
        plan: false,
        project: true,
        out: out.add,
        resolve: (String directory, {required bool flutter}) async => null,
      );
      expect(code, 0);
      expect(
        read('modules/billing/pubspec.yaml'),
        contains('dartvel_core: ^$_target'),
      );
      expect(out.join('\n'), contains('modules/billing/pubspec.yaml'));
    });

    test(
        'a module dartvel add generated is not edited, because its lock pins '
        'every byte; it is pointed at dartvel add --refresh', () async {
      write(
        'pubspec.yaml',
        '$_app01351'
        '  modules:\n'
        '    slugify:\n'
        '      source:\n'
        '        path: modules/slugify\n'
        '      mount: /slugify\n',
      );
      const String generated = '''
# GENERATED by dartvel add from path:vendor/slugify.
name: dv_slugify_module
dependencies:
  dartvel_core: ^0.9.0
dartvel:
  module:
    id: slugify
    kind: dartPackage
''';
      write('modules/slugify/pubspec.yaml', generated);
      write('dartvel.module.lock', '''
dv_slugify_module:
  version: 0.0.1
  source: path:vendor/slugify
  sourceDigest: ${'a' * 64}
  wrapperHash: ${'b' * 64}
  generator: dartvel_cli 0.13.51
  capabilities: []
''');
      final List<String> out = <String>[];
      final int code = await dvRunUpgrade(
        root.path,
        plan: false,
        project: true,
        out: out.add,
        resolve: (String directory, {required bool flutter}) async => null,
      );
      expect(code, 0);
      expect(read('modules/slugify/pubspec.yaml'), generated);
      expect(read('pubspec.yaml'), contains('dartvel_core: ^$_target'));
      expect(out.join('\n'), contains('dartvel add --refresh slugify'));
    });

    test('a refused resolution puts every file back and says why', () async {
      write('pubspec.yaml', _app01351);
      final List<String> out = <String>[];
      final int code = await dvRunUpgrade(
        root.path,
        plan: false,
        project: true,
        out: out.add,
        resolve: (String directory, {required bool flutter}) async =>
            'version solving failed',
      );
      expect(code, 1);
      expect(read('pubspec.yaml'), _app01351);
      expect(out.join('\n'), contains('version solving failed'));
    });

    test('a project newer than this CLI is left alone', () async {
      final String newer = _app01351.replaceFirst(
        'dartvel_core: ^0.13.51',
        'dartvel_core: ^99.0.0',
      );
      write('pubspec.yaml', newer);
      final List<String> out = <String>[];
      var resolved = false;
      final int code = await dvRunUpgrade(
        root.path,
        plan: false,
        project: true,
        out: out.add,
        resolve: (String directory, {required bool flutter}) async {
          resolved = true;
          return null;
        },
      );
      expect(code, 1);
      expect(resolved, isFalse);
      expect(read('pubspec.yaml'), newer);
    });

    test('outside a project it says so', () async {
      final List<String> out = <String>[];
      final int code = await dvRunUpgrade(
        root.path,
        plan: false,
        project: true,
        out: out.add,
      );
      expect(code, 1);
      expect(out.join('\n'), contains('pubspec.yaml'));
    });

    test(
        'a constraint that already admits this release but a lock behind it '
        'is resolved forward, not reported as current', () async {
      const String admitting = '''
name: shop
dependencies:
  flutter:
    sdk: flutter
  dartvel_core: ">=3.0.0 <4.0.0"
  dartvel_flutter: ">=3.0.0 <4.0.0"
''';
      write('pubspec.yaml', admitting);
      write('pubspec.lock', '''
packages:
  dartvel_core:
    dependency: "direct main"
    source: hosted
    version: "3.0.0"
  dartvel_flutter:
    dependency: "direct main"
    source: hosted
    version: "3.0.0"
''');
      final List<String> out = <String>[];
      final List<String> resolved = <String>[];
      final int code = await dvRunUpgrade(
        root.path,
        plan: false,
        project: true,
        out: out.add,
        resolve: (String directory, {required bool flutter}) async {
          resolved.add(directory);
          return null;
        },
      );
      expect(code, 0);
      expect(resolved, <String>[root.path]);
      expect(read('pubspec.yaml'), admitting);
      expect(out.join('\n'), contains('dartvel_core 3.0.0'));
      expect(out.join('\n'), isNot(contains('Nothing was changed')));
    });

    test('already on this release: nothing written, nothing resolved',
        () async {
      final String current = _app01351.replaceAll('0.13.51', _target);
      write('pubspec.yaml', current);
      final List<String> out = <String>[];
      var resolved = false;
      final int code = await dvRunUpgrade(
        root.path,
        plan: false,
        project: true,
        out: out.add,
        resolve: (String directory, {required bool flutter}) async {
          resolved = true;
          return null;
        },
      );
      expect(code, 0);
      expect(resolved, isFalse);
      expect(read('pubspec.yaml'), current);
    });
  });
}
