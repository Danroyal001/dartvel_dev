// `dartvel upgrade --plan` says what upgrading a project to this CLI's Dartvel
// would change, and changes nothing.
//
// Upgrade and compatibility: upgrades preserve source, generated-code,
// protocol, database, module, plugin and deployment compatibility, and the
// plan comes before the upgrade. Generated Code Determinism: a generator
// upgrade that changes output shape is listed with the diff it will cause.
//
// The failures worth testing are the quiet ones: a plan that writes, a check
// that could not be made reported as unchanged, a project already newer than
// the CLI told to "upgrade" backwards, and a module pinned to an older Dartvel
// that would only fail once mounted.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/build/sdk_floor.dart';
import 'package:dartvel_cli/src/commands/upgrade_command.dart';
import 'package:dartvel_cli/src/generators/generate_check.dart';
import 'package:dartvel_cli/src/templates/project_templates.dart';
import 'package:dartvel_cli/src/upgrade/upgrade_plan.dart';
import 'package:dartvel_core/dartvel.dart'
    show DVProtocolContract, DVProtocolLock, DVProtocolModel;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _target = dartvelPackageVersion;

String _lock(Map<String, String> versions) {
  final StringBuffer out = StringBuffer('packages:\n');
  versions.forEach((String name, String version) {
    out
      ..writeln('  $name:')
      ..writeln('    dependency: "direct main"')
      ..writeln('    source: hosted')
      ..writeln('    version: "$version"');
  });
  return out.toString();
}

/// A Flutter application on the release before this CLI's.
const String _oldApp =
    '''
name: shop
environment:
  # Excludes every Dart the target runs on.
  sdk: ">=3.4.0 <3.10.0"
dependencies:
  flutter:
    sdk: flutter
  dartvel_core: ^0.4.0
  dartvel_flutter: ^0.4.0
  # dartvel_flutter needs ^14.2.0.
  go_router: ^13.0.0
dev_dependencies:
  dartvel_cli: ^$_target
  dartvel_generator: ^0.4.0
''';

String _currentApp({String core = '^$_target'}) =>
    '''
name: shop
environment:
  sdk: ">=3.13.0 <4.0.0"
dependencies:
  flutter:
    sdk: flutter
  dartvel_core: $core
  dartvel_flutter: ^$_target
''';

const DVToolchainVersions _modernToolchain = DVToolchainVersions(
  dart: '3.13.4',
  flutter: '3.47.5',
);

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('dv_upgrade_plan_'));
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
      if (e is File) p.relative(e.path, from: root.path): e.readAsStringSync(),
  };

  Future<DVGenerateCheckResult> noGeneratedChange(String _) async =>
      const DVGenerateCheckResult(stale: <String>[], unstable: <String>[]);

  Future<DVUpgradePlan> plan({
    DVToolchainVersions toolchain = _modernToolchain,
    DVGeneratedCheck? generated,
  }) => dvPlanUpgrade(
    root.path,
    probe: () async => toolchain,
    generatedCheck: generated ?? noGeneratedChange,
  );

  DVUpgradeItem item(DVUpgradePlan plan, String subject) =>
      plan.items.firstWhere(
        (DVUpgradeItem i) => i.subject == subject,
        orElse: () =>
            throw StateError('no item for $subject in:\n${plan.render()}'),
      );

  void oldProject() {
    write('pubspec.yaml', _oldApp);
    write(
      'pubspec.lock',
      _lock(<String, String>{
        'dartvel_core': '0.4.0',
        'dartvel_flutter': '0.4.0',
        'dartvel_cli': _target,
      }),
    );
    write('lib/pages/home.dart', 'void f() => DV.Storage.get("a");\n');
    write('lib/dartvel_client/dartvel_client.dart', '// generated\n');
  }

  group('an application on the previous release', () {
    test(
      'the plan writes nothing and is refused while anything blocks it',
      () async {
        oldProject();
        final Map<String, String> before = snapshot();
        final List<String> out = <String>[];
        final int code = await dvRunUpgrade(
          root.path,
          plan: true,
          out: out.add,
          probe: () async => _modernToolchain,
          generatedCheck: noGeneratedChange,
        );
        expect(code, 1);
        expect(snapshot(), before);
        expect(out.join('\n'), contains(_target));
      },
    );

    test(
      'an SDK constraint below the floor blocks, naming the floor',
      () async {
        oldProject();
        final DVUpgradeItem sdk = item(await plan(), 'environment.sdk');
        expect(sdk.outcome, DVUpgradeOutcome.blocked);
        expect(sdk.detail, contains('>=$dvDartFloor'));
      },
    );

    test(
      'a Dartvel constraint that excludes the target is a change to it',
      () async {
        oldProject();
        final DVUpgradeItem core = item(await plan(), 'dartvel_core');
        expect(core.outcome, DVUpgradeOutcome.changes);
        expect(core.detail, contains('^0.4.0'));
        expect(core.detail, contains('^$_target'));
      },
    );

    test('a package already on the target is unchanged', () async {
      oldProject();
      expect(
        item(await plan(), 'dartvel_cli').outcome,
        DVUpgradeOutcome.unchanged,
      );
    });

    test('dartvel_generator is named for removal', () async {
      oldProject();
      final DVUpgradeItem generator = item(await plan(), 'dartvel_generator');
      expect(generator.outcome, DVUpgradeOutcome.changes);
      expect(generator.detail, contains('retired'));
    });

    test('a shared dependency the target cannot accept blocks', () async {
      oldProject();
      final DVUpgradeItem router = item(await plan(), 'go_router');
      expect(router.outcome, DVUpgradeOutcome.blocked);
      expect(router.detail, contains('^13.0.0'));
    });

    test('deprecated names are counted and pointed at migrate-code', () async {
      oldProject();
      final DVUpgradeItem source = item(await plan(), 'deprecated names');
      expect(source.outcome, DVUpgradeOutcome.changes);
      expect(source.detail, contains('lib/pages/home.dart'));
      expect(source.detail, contains('dartvel migrate-code --apply'));
    });

    test(
      'regenerated output that differs is listed with its line changes',
      () async {
        oldProject();
        final DVUpgradePlan result = await plan(
          generated: (String _) async => const DVGenerateCheckResult(
            stale: <String>['lib/dartvel_client/routes.dart'],
            unstable: <String>[],
            lineChanges: <String, (int, int)>{
              'lib/dartvel_client/routes.dart': (3, 1),
            },
          ),
        );
        final DVUpgradeItem generated = item(result, 'generated output');
        expect(generated.outcome, DVUpgradeOutcome.changes);
        expect(
          generated.detail,
          contains('lib/dartvel_client/routes.dart +3 -1'),
        );
      },
    );

    test('the checks it cannot make are unchecked, never unchanged', () async {
      oldProject();
      final DVUpgradePlan result = await plan();
      for (final String subject in <String>[
        'protocol',
        'database',
        'plugins',
        'deployment',
      ]) {
        expect(
          item(result, subject).outcome,
          DVUpgradeOutcome.unchecked,
          reason: subject,
        );
      }
    });
  });

  group('the toolchain', () {
    test('an installed Flutter older than the floor blocks', () async {
      write('pubspec.yaml', _currentApp());
      final DVUpgradeItem flutter = item(
        await plan(
          toolchain: const DVToolchainVersions(
            dart: '3.13.0',
            flutter: '3.40.0',
          ),
        ),
        'installed Flutter',
      );
      expect(flutter.outcome, DVUpgradeOutcome.blocked);
      expect(flutter.detail, contains(dvFlutterFloor));
    });

    test('a toolchain that could not be read is unchecked', () async {
      write('pubspec.yaml', _currentApp());
      final DVUpgradePlan result = await plan(
        toolchain: const DVToolchainVersions(),
      );
      expect(
        item(result, 'installed Dart').outcome,
        DVUpgradeOutcome.unchecked,
      );
      expect(
        item(result, 'installed Flutter').outcome,
        DVUpgradeOutcome.unchecked,
      );
    });

    test('the Flutter floor is the one the scaffold tells people', () {
      expect(
        ProjectTemplates.readmeTemplate('x'),
        contains('Flutter SDK >= $dvFlutterFloor'),
      );
    });

    test('the installed versions are read from the tools', () {
      expect(
        dvParseToolchainVersions(
          flutterMachine:
              'Waiting for another flutter command...\n'
              '{"frameworkVersion": "3.44.5", "dartSdkVersion": "3.12.2"}',
        ),
        const DVToolchainVersions(dart: '3.12.2', flutter: '3.44.5'),
      );
      expect(
        dvParseToolchainVersions(
          dartVersion:
              'Dart SDK version: 3.12.2 (stable) (Tue Jun 9) on '
              '"linux_x64"',
        ),
        const DVToolchainVersions(dart: '3.12.2'),
      );
    });
  });

  group('a project newer than this CLI', () {
    test('is blocked and told to update the CLI, not to downgrade', () async {
      write('pubspec.yaml', _currentApp(core: '^9.0.0'));
      write('pubspec.lock', _lock(<String, String>{'dartvel_core': '9.0.1'}));
      final DVUpgradeItem core = item(await plan(), 'dartvel_core');
      expect(core.outcome, DVUpgradeOutcome.blocked);
      expect(core.detail, contains('dartvel update'));
    });
  });

  group('an application already on the target', () {
    test('an admitted but unresolved version is a pub upgrade', () async {
      write('pubspec.yaml', _currentApp());
      final DVUpgradeItem core = item(await plan(), 'dartvel_core');
      expect(core.outcome, DVUpgradeOutcome.changes);
      expect(core.detail, contains('pub upgrade dartvel_core'));
    });

    test('is planned with nothing to change and nothing blocked', () async {
      write('pubspec.yaml', _currentApp());
      write(
        'pubspec.lock',
        _lock(<String, String>{
          'dartvel_core': _target,
          'dartvel_flutter': _target,
        }),
      );
      write('lib/pages/home.dart', 'void f() => DV.FileStorage.get("a");\n');
      write('lib/dartvel_client/dartvel_client.dart', '// generated\n');
      final DVUpgradePlan result = await plan();
      expect(result.blocked, isFalse, reason: result.render());
      expect(
        result.items.where(
          (DVUpgradeItem i) => i.outcome == DVUpgradeOutcome.changes,
        ),
        isEmpty,
        reason: result.render(),
      );
    });

    test(
      'with no generated output there is nothing to compare, and it says so',
      () async {
        write('pubspec.yaml', _currentApp());
        final DVUpgradePlan result = await plan(
          generated: (String _) => throw StateError('must not generate'),
        );
        expect(
          item(result, 'generated output').outcome,
          DVUpgradeOutcome.unchecked,
        );
        expect(
          item(result, 'generated output').detail,
          contains('no lib/dartvel_client'),
        );
      },
    );
  });

  group('the protocol', () {
    test('a recorded lockfile that cannot be trusted blocks', () async {
      write('pubspec.yaml', _currentApp());
      final DVProtocolLock lock = const DVProtocolLock(<Never>[]).bump(
        const DVProtocolContract(
          models: <DVProtocolModel>[DVProtocolModel('User', [])],
        ),
        at: DateTime.utc(2026, 1, 1),
      );
      write(
        DVProtocolLock.fileName,
        lock.encode().replaceFirst(lock.current!.shape, '00000000'),
      );
      expect(item(await plan(), 'protocol').outcome, DVUpgradeOutcome.blocked);
    });
  });

  group('modules', () {
    void parentWithModule(String moduleCore) {
      write(
        'pubspec.yaml',
        '${_currentApp()}dartvel:\n'
            '  modules:\n'
            '    store:\n'
            '      source:\n'
            '        path: modules/store\n'
            '      mount: /store\n',
      );
      write(
        'modules/store/pubspec.yaml',
        'name: store\n'
            'dependencies:\n'
            '  dartvel_core: $moduleCore\n'
            'dartvel:\n'
            '  module:\n'
            '    id: store\n',
      );
    }

    test(
      'a module whose Dartvel constraint excludes the target blocks',
      () async {
        parentWithModule('^0.4.0');
        final DVUpgradeItem module = item(await plan(), 'module store');
        expect(module.outcome, DVUpgradeOutcome.blocked);
        expect(module.detail, contains('^0.4.0'));
      },
    );

    test('a module that admits the target is unchanged', () async {
      parentWithModule('^$_target');
      expect(
        item(await plan(), 'module store').outcome,
        DVUpgradeOutcome.unchanged,
      );
    });
  });

  group('the command', () {
    test('upgrade without --plan refuses and writes nothing', () async {
      oldProject();
      final Map<String, String> before = snapshot();
      final List<String> out = <String>[];
      final int code = await dvRunUpgrade(
        root.path,
        plan: false,
        out: out.add,
        probe: () async => _modernToolchain,
        generatedCheck: noGeneratedChange,
      );
      expect(code, 1);
      expect(snapshot(), before);
      expect(out.join('\n'), contains('--plan'));
    });

    test('is upgrade, with --plan', () {
      final CommandRunner<void> runner = CommandRunner<void>('dartvel', 't')
        ..addCommand(UpgradeCommand());
      expect(
        runner.commands['upgrade']!.argParser.options.keys,
        contains('plan'),
      );
    });
  });

  test('generate --check counts the lines a stale file would change', () async {
    write('pubspec.yaml', 'name: shop\n');
    write('lib/dartvel_client/routes.dart', 'a\nb\nc\n');
    final DVGenerateCheckResult result = await dvGenerateCheck(
      root.path,
      generator: (String at) async {
        File(
          p.join(at, 'lib', 'dartvel_client', 'routes.dart'),
        ).writeAsStringSync('a\nB\nc\nd\ne\n');
      },
    );
    expect(result.stale, <String>['lib/dartvel_client/routes.dart']);
    expect(result.lineChanges['lib/dartvel_client/routes.dart'], (3, 1));
  });
}
