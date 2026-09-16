// `dartvel migrate-code` rewrites names Dartvel has deprecated to the names
// that replace them.
//
// Upgrade and compatibility names the rewrites: DVStyleModifier -> DVModifier,
// .styleModifier() -> .modifier() and DV.Storage -> DV.FileStorage. Each rule
// here is also a name the packages mark @Deprecated with the replacement named.
//
// The failures worth testing are the silent ones. A rewrite inside a string or
// a comment changes what a program prints or documents and still compiles. A
// rewrite of a user's own `styleModifier` declaration, or of `DV.StorageQuota`,
// breaks code that was never deprecated. A dry run that writes, or an apply
// that lands half its files, leaves a project in a state nobody chose.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/migrate_code_command.dart';
import 'package:dartvel_cli/src/upgrade/code_migrations.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String migrate(String source) => dvMigrateDartSource(source).source;

void main() {
  group('the rewrite of one source', () {
    test('renames the deprecated type wherever it is a type', () {
      expect(
        migrate(
          'final DVStyleModifier m = DVStyleModifier();\n'
          'List<DVStyleModifier> all = <DVStyleModifier>[];\n',
        ),
        'final DVModifier m = DVModifier();\n'
        'List<DVModifier> all = <DVModifier>[];\n',
      );
    });

    test(
      'rewrites .styleModifier( on calls, cascades and null-aware calls',
      () {
        expect(
          migrate(
            'box.styleModifier(m); box..styleModifier(m); '
            'box?.styleModifier(m); box ?..styleModifier(m);',
          ),
          'box.modifier(m); box..modifier(m); '
          'box?.modifier(m); box ?..modifier(m);',
        );
      },
    );

    test(
      'leaves a declaration, named argument or field called styleModifier',
      () {
        const String source =
            'class A {\n'
            '  A styleModifier(DVModifier m) => this;\n'
            '}\n'
            'void f({Object? styleModifier}) {}\n'
            'void g() => f(styleModifier: 1);\n'
            'void h(Options o) => o.styleModifier = null;\n';
        expect(migrate(source), source);
      },
    );

    test('rewrites DV.Storage and nothing that merely starts with it', () {
      expect(
        migrate(
          'await DV.Storage.put(k, v);\n'
          'DV.StorageQuota; DV.BlobStorage; DV.FileStorage; MyDV.Storage;\n',
        ),
        'await DV.FileStorage.put(k, v);\n'
        'DV.StorageQuota; DV.BlobStorage; DV.FileStorage; MyDV.Storage;\n',
      );
    });

    test('never rewrites inside comments or string text', () {
      const String source =
          '// DV.Storage in a line comment\n'
          '/// [DVStyleModifier] in a doc comment\n'
          '/* outer /* nested DV.Storage */ still DVStyleModifier */\n'
          "const a = 'DV.Storage';\n"
          'const b = "box.styleModifier(m)";\n'
          "const c = r'\${DV.Storage}';\n"
          "const d = '''it's DebugAuthProvider''';\n"
          'const e = """\n'
          '  "DV.Storage" across lines\n'
          '""";\n'
          "const f = 'escaped \\' DV.Storage';\n";
      expect(migrate(source), source);
    });

    test('does rewrite code inside a string interpolation', () {
      expect(
        migrate(
          "'\${DV.Storage.name} and \$DebugAuthProvider "
          "\${{'k': \"\${DV.Storage}\"}}'",
        ),
        "'\${DV.FileStorage.name} and \$LocalAuthProvider "
        "\${{'k': \"\${DV.FileStorage}\"}}'",
      );
    });

    test('rewrites the deprecated model annotations to their DVModel form', () {
      expect(
        migrate(
          '@DVSearchable()\n'
          'final String title;\n'
          '@DVSensitiveModelField(encrypted: true)\n'
          'final String token;\n',
        ),
        '@DVModel.searchableField()\n'
        'final String title;\n'
        '@DVModel.sensitiveField(encrypted: true)\n'
        'final String token;\n',
      );
    });

    test('leaves the annotation names where they are not annotations', () {
      const String source =
          "import 'package:dartvel_core/dartvel.dart' show DVSearchable;\n";
      expect(migrate(source), source);
    });

    test('renames the Debug providers to the Local ones', () {
      expect(
        migrate(
          'DebugAuthProvider(); DebugAnalyticsProvider(); '
          'DebugPushNotificationProvider();',
        ),
        'LocalAuthProvider(); LocalAnalyticsProvider(); '
        'LocalPushNotificationProvider();',
      );
    });

    test('reports the rule, line and column of every rewrite', () {
      final DVSourceMigration result = dvMigrateDartSource(
        'void main() {\n'
        '  DV.Storage.get(k);\n'
        '  box.styleModifier(m);\n'
        '}\n',
      );
      expect(
        <String>[
          for (final DVCodeRewrite r in result.rewrites)
            '${r.rule.id}@${r.line}:${r.column}',
        ],
        <String>['dv-storage@2:6', 'style-modifier-method@3:7'],
      );
    });

    test('a second run over migrated source finds nothing', () {
      final String once = migrate(
        'DV.Storage; DVStyleModifier; '
        'x.styleModifier(m); @DVSearchable() int a;',
      );
      expect(dvMigrateDartSource(once).rewrites, isEmpty);
    });
  });

  group('every rule is backed by the packages', () {
    // A rule whose replacement does not exist rewrites working code into code
    // that does not compile, and one whose name is not deprecated churns code
    // nobody asked to change. Checked against the sources that ship.
    final String packages = p.normalize(p.join(Directory.current.path, '..'));
    String source(String rel) => File(p.join(packages, rel)).readAsStringSync();
    final String sources = <String>[
      'dartvel_flutter/lib/dartvel_flutter.dart',
      'dartvel_core/lib/src/annotations/annotations.dart',
      'dartvel_core/lib/src/auth/auth.dart',
      'dartvel_core/lib/src/analytics/analytics.dart',
      'dartvel_core/lib/src/notifications/push.dart',
    ].map(source).join('\n');

    for (final DVCodeMigrationRule rule in dvCodeMigrationRules) {
      test(
        '${rule.id}: ${rule.from} is deprecated or an alias of ${rule.to}',
        () {
          expect(
            RegExp(rule.evidence).hasMatch(sources),
            isTrue,
            reason: 'no declaration matching ${rule.evidence} in the packages',
          );
        },
      );
    }
  });

  group('a project', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('dv_migrate_code_'));
    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    void write(String rel, String content) {
      File(p.join(root.path, rel))
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    Map<String, String> snapshot() => <String, String>{
      for (final FileSystemEntity e in root.listSync(
        recursive: true,
        followLinks: false,
      ))
        if (e is File)
          p.relative(e.path, from: root.path): e.readAsStringSync(),
    };

    void fixture() {
      write('pubspec.yaml', 'name: shop\n');
      write('lib/pages/home.dart', 'void f() => DV.Storage.get("a");\n');
      write('test/home_test.dart', 'final m = DVStyleModifier();\n');
      write('lib/clean.dart', 'void g() => DV.FileStorage.get("a");\n');
      // Regenerated by the CLI, and not the project's own source.
      write('lib/dartvel_client/dartvel_client.dart', 'DV.Storage;\n');
      write('.dart_tool/x.dart', 'DV.Storage;\n');
      write('build/y.dart', 'DV.Storage;\n');
    }

    test('the plan names the project files and skips generated output', () {
      fixture();
      final DVCodeMigrationPlan plan = dvPlanCodeMigration(root.path);
      expect(plan.files.keys.toList()..sort(), <String>[
        'lib/pages/home.dart',
        'test/home_test.dart',
      ]);
      expect(plan.rewriteCount, 2);
    });

    test('a dry run prints every rewrite and writes nothing', () async {
      fixture();
      final Map<String, String> before = snapshot();
      final List<String> out = <String>[];
      final int code = await dvRunMigrateCode(
        root.path,
        apply: false,
        out: out.add,
      );
      expect(code, 0);
      expect(snapshot(), before);
      final String printed = out.join('\n');
      expect(printed, contains('lib/pages/home.dart:1'));
      expect(printed, contains('- void f() => DV.Storage.get("a");'));
      expect(printed, contains('+ void f() => DV.FileStorage.get("a");'));
      expect(printed, contains('--apply'));
    });

    test('--apply writes the rewrites and only them', () async {
      fixture();
      final Map<String, String> before = snapshot();
      final int code = await dvRunMigrateCode(
        root.path,
        apply: true,
        out: (_) {},
      );
      expect(code, 0);
      final Map<String, String> after = snapshot();
      expect(
        after['lib/pages/home.dart'],
        'void f() => DV.FileStorage.get("a");\n',
      );
      expect(after['test/home_test.dart'], 'final m = DVModifier();\n');
      for (final String rel in before.keys) {
        if (rel == 'lib/pages/home.dart' || rel == 'test/home_test.dart') {
          continue;
        }
        expect(after[rel], before[rel], reason: '$rel must not change');
      }
      expect(dvPlanCodeMigration(root.path).files, isEmpty);
    });

    test(
      'apply refuses when a file changed after the plan, writing nothing',
      () {
        fixture();
        final DVCodeMigrationPlan plan = dvPlanCodeMigration(root.path);
        write(
          'test/home_test.dart',
          'final m = DVStyleModifier(); // edited\n',
        );
        final Map<String, String> before = snapshot();
        final DVCodeMigrationApplyResult result = dvApplyCodeMigration(plan);
        expect(result.applied, isFalse);
        expect(result.message, contains('test/home_test.dart'));
        expect(snapshot(), before);
      },
    );

    test('nothing to migrate says so', () async {
      write('pubspec.yaml', 'name: shop\n');
      write('lib/clean.dart', 'void g() => DV.FileStorage.get("a");\n');
      final List<String> out = <String>[];
      expect(await dvRunMigrateCode(root.path, apply: true, out: out.add), 0);
      expect(out.join('\n'), contains('Nothing to migrate'));
    });

    test('outside a project it refuses', () async {
      final List<String> out = <String>[];
      expect(await dvRunMigrateCode(root.path, apply: false, out: out.add), 1);
      expect(out.join('\n'), contains('pubspec.yaml'));
    });
  });

  test('the command is migrate-code, dry run unless --apply', () {
    final CommandRunner<void> runner = CommandRunner<void>('dartvel', 't')
      ..addCommand(MigrateCodeCommand());
    final Command<void> command = runner.commands['migrate-code']!;
    expect(command.argParser.options['apply']!.defaultsTo, isFalse);
  });
}
