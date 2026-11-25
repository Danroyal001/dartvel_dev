// `dartvel upgrade --project` moves an application onto material_ui and
// cupertino_ui along with its Dartvel constraints.
//
// Dartvel 3.50 builds on those packages because Flutter 3.50 deprecates
// package:flutter/material.dart and package:flutter/cupertino.dart. They are
// copies of the libraries, not re-exports, so an application left on the old
// imports builds its pages against a second Material library: under Dartvel's
// material_ui app those widgets find no Theme and no Material ancestor of
// their own classes and fall back to defaults. That compiles. The upgrade has
// to move the imports with the release, and say so when it could not.
//
// The quiet failures: the dependency added with `any` (what dart fix writes),
// the fix run before the new packages resolve, a module's imports left behind,
// a failed fix reported as success, and a project that never imported either
// library given a fix run anyway.
import 'dart:io';

import 'package:dartvel_cli/src/commands/upgrade_command.dart';
import 'package:dartvel_cli/src/templates/project_templates.dart';
import 'package:dartvel_cli/src/upgrade/design_imports.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _target = dartvelPackageVersion;

String _app({String extra = ''}) => '''
name: shop
environment:
  sdk: ">=3.14.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  dartvel_core: ^$_target
  dartvel_flutter: ^$_target
$extra  go_router: ^14.2.0

dev_dependencies:
  dartvel_cli: ^$_target
''';

const String _materialPage = '''
import 'package:flutter/material.dart';

Widget page() => const Text('Shop');
''';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('dv_design_'));
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  void write(String path, String text) {
    final File file = File(p.join(root.path, path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(text);
  }

  String read(String path) => File(p.join(root.path, path)).readAsStringSync();

  group('finding the imports', () {
    test('imports and exports of either library, in lib and test', () {
      write('lib/pages/index.dart', _materialPage);
      write('test/a_test.dart',
          "import 'package:flutter/cupertino.dart' show CupertinoButton;\n");
      write('lib/barrel.dart', 'export "package:flutter/material.dart";\n');
      write('lib/clean.dart', "import 'package:material_ui/material_ui.dart';\n");
      expect(dvFindDesignImports(root.path), <String, Set<String>>{
        'lib/barrel.dart': <String>{'package:flutter/material.dart'},
        'lib/pages/index.dart': <String>{'package:flutter/material.dart'},
        'test/a_test.dart': <String>{'package:flutter/cupertino.dart'},
      });
    });

    test('build output, tool caches and nested packages are not read', () {
      write('build/x.dart', _materialPage);
      write('.dart_tool/y.dart', _materialPage);
      write('modules/billing/pubspec.yaml', 'name: billing\n');
      write('modules/billing/lib/z.dart', _materialPage);
      expect(dvFindDesignImports(root.path), isEmpty);
    });
  });

  group('the dependencies', () {
    test('a Dartvel Flutter app gets material_ui at the tested floor', () {
      final List<DVDesignLibrary> needed =
          dvDesignDependenciesNeeded(_app(), <String>{});
      expect(needed.map((DVDesignLibrary l) => l.package), <String>[
        'material_ui',
      ]);
      final String written = dvAddDesignDependencies(_app(), needed);
      expect(written, contains('  material_ui: ^$dvMaterialUiVersion\n'));
      expect(written, isNot(contains('any')));
      // Under dependencies, right after the flutter SDK entry.
      expect(
        written,
        contains('    sdk: flutter\n  material_ui: ^$dvMaterialUiVersion\n'),
      );
      // Nothing else moved.
      expect(written.replaceFirst('  material_ui: ^$dvMaterialUiVersion\n', ''),
          _app());
    });

    test('cupertino_ui only when the app imports flutter/cupertino', () {
      final List<DVDesignLibrary> needed = dvDesignDependenciesNeeded(
          _app(), <String>{'package:flutter/cupertino.dart'});
      expect(needed.map((DVDesignLibrary l) => l.package),
          <String>['material_ui', 'cupertino_ui']);
      expect(dvAddDesignDependencies(_app(), needed),
          contains('  cupertino_ui: ^$dvCupertinoUiVersion\n'));
    });

    test('a package already declared is left as the app wrote it', () {
      final String declared = _app(extra: '  material_ui: ^1.12.0\n');
      expect(dvDesignDependenciesNeeded(declared, <String>{}), isEmpty);
    });

    test('a project that is not a Flutter project gets nothing', () {
      const String server = '''
name: api
dependencies:
  dartvel_core: ^3.50.0
''';
      expect(
        dvDesignDependenciesNeeded(
            server, <String>{'package:flutter/material.dart'}),
        isEmpty,
      );
    });
  });

  group('the command', () {
    test(
        'adds the packages, resolves them, then runs Flutter\'s fix, in that '
        'order', () async {
      write('pubspec.yaml', _app());
      write('lib/pages/index.dart', _materialPage);
      final List<String> steps = <String>[];
      final List<String> out = <String>[];
      final int code = await dvRunUpgrade(
        root.path,
        plan: false,
        project: true,
        out: out.add,
        resolve: (String directory, {required bool flutter}) async {
          // The fix rewrites to a library that must already resolve.
          expect(read('pubspec.yaml'),
              contains('material_ui: ^$dvMaterialUiVersion'));
          steps.add('resolve $directory');
          return null;
        },
        designFix: (String directory) async {
          steps.add('fix $directory');
          write(
            'lib/pages/index.dart',
            _materialPage.replaceAll(
              'package:flutter/material.dart',
              'package:material_ui/material_ui.dart',
            ),
          );
          return null;
        },
      );
      expect(code, 0, reason: out.join('\n'));
      expect(steps, <String>['resolve ${root.path}', 'fix ${root.path}']);
      expect(out.join('\n'), contains('material_ui ^$dvMaterialUiVersion'));
      expect(out.join('\n'), contains(dvDesignFixCode));
    });

    test('a module of the project has its imports moved too', () async {
      write(
        'pubspec.yaml',
        '${_app()}\n'
        'dartvel:\n'
        '  modules:\n'
        '    billing:\n'
        '      source:\n'
        '        path: modules/billing\n'
        '      mount: /billing\n',
      );
      write('modules/billing/pubspec.yaml', '''
name: billing
dependencies:
  flutter:
    sdk: flutter
  dartvel_flutter: ^$_target
dartvel:
  module:
    id: billing
''');
      write('modules/billing/lib/pages/index.dart', _materialPage);
      final List<String> fixed = <String>[];
      final int code = await dvRunUpgrade(
        root.path,
        plan: false,
        project: true,
        out: (_) {},
        resolve: (String directory, {required bool flutter}) async => null,
        designFix: (String directory) async {
          fixed.add(p.relative(directory, from: root.path));
          final File page =
              File(p.join(directory, 'lib', 'pages', 'index.dart'));
          if (page.existsSync()) {
            page.writeAsStringSync(page.readAsStringSync().replaceAll(
                'package:flutter/material.dart',
                'package:material_ui/material_ui.dart'));
          }
          return null;
        },
      );
      expect(code, 0);
      expect(fixed, <String>['modules/billing']);
      expect(read('modules/billing/pubspec.yaml'),
          contains('material_ui: ^$dvMaterialUiVersion'));
    });

    test('a fix that fails is reported with the command, not as done',
        () async {
      write('pubspec.yaml', _app());
      write('lib/pages/index.dart', _materialPage);
      final List<String> out = <String>[];
      final int code = await dvRunUpgrade(
        root.path,
        plan: false,
        project: true,
        out: out.add,
        resolve: (String directory, {required bool flutter}) async => null,
        designFix: (String directory) async => 'dart fix: analysis failed',
      );
      expect(code, 1);
      expect(out.join('\n'), contains('analysis failed'));
      expect(out.join('\n'), contains(dvDesignFixCommand.join(' ')));
      expect(out.join('\n'), isNot(contains('Resolved. Run')));
    });

    test('an import the fix left behind is named, and the run fails',
        () async {
      write('pubspec.yaml', _app());
      write('lib/pages/index.dart', _materialPage);
      final List<String> out = <String>[];
      final int code = await dvRunUpgrade(
        root.path,
        plan: false,
        project: true,
        out: out.add,
        resolve: (String directory, {required bool flutter}) async => null,
        designFix: (String directory) async => null,
      );
      expect(code, 1);
      expect(out.join('\n'), contains('lib/pages/index.dart'));
    });

    test('an app with no old imports and the packages declared: no fix',
        () async {
      write('pubspec.yaml',
          _app(extra: '  material_ui: ^$dvMaterialUiVersion\n'));
      write('lib/pages/index.dart',
          "import 'package:material_ui/material_ui.dart';\n");
      final int code = await dvRunUpgrade(
        root.path,
        plan: false,
        project: true,
        out: (_) {},
        resolve: (String directory, {required bool flutter}) async =>
            fail('nothing to resolve'),
        designFix: (String directory) async => fail('nothing to fix'),
      );
      expect(code, 0);
    });
  });
}
