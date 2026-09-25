// `dartvel init` initializes Dartvel inside a project that already exists.
//
// Adoption says it adds the dependency and the `dartvel:` key and nothing
// else: no scaffold, no moved files, no pubspec rewritten beyond those two
// additions. It used to be an alias of `create`, which replaced the whole
// pubspec with the scaffold template -- the one command a team adopting
// Dartvel would reach for was the one that destroyed their dependency list.
//
// The failures worth testing are the quiet ones: an edit that drops a comment
// or a dependency and still parses, a report that says "compatible" because a
// check could not be made, a write that half-happens, and a plan that is
// applied without being shown.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/adoption/adoption_plan.dart';
import 'package:dartvel_cli/src/commands/adopt_command.dart';
import 'package:dartvel_cli/src/commands/init_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// A Flutter application of the kind a team already has, comments and all.
const String _flutterApp = '''
# The acme application. Owned by the mobile team.
name: acme_app
description: An application that existed before Dartvel did.
publish_to: none
version: 2.4.0+18

environment:
  sdk: ">=3.4.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  # Pinned until the 9.x migration lands.
  bloc: ^8.1.0
  dio: ^5.5.0
  go_router: ^14.6.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.4.0
  freezed: ^2.5.0

flutter:
  uses-material-design: true
  assets:
    - assets/images/
''';

/// A Dart server with no widgets in it.
const String _dartServer = '''
name: acme_api
environment:
  sdk: ^3.13.0
dependencies:
  shelf: ^1.4.0
''';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('dv_adopt_'));
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  File pubspec() => File(p.join(root.path, 'pubspec.yaml'));

  /// Every file under [root] and its bytes, so "nothing else changed" is a
  /// comparison rather than a belief.
  Map<String, String> snapshot() => <String, String>{
        for (final FileSystemEntity e
            in root.listSync(recursive: true, followLinks: false))
          if (e is File)
            p.relative(e.path, from: root.path): e.readAsStringSync(),
      };

  group('the plan', () {
    test('adds the dependency and the dartvel key, and loses nothing', () {
      pubspec().writeAsStringSync(_flutterApp);

      final DVAdoptionPlan plan = dvPlanAdoption(root.path);

      expect(plan.refusal, isNull);
      expect(plan.edited, isNotNull);
      final String edited = plan.edited!;

      // Only insertions: every original line, comments included, is still
      // there and in the same order. A reformatting edit that re-emitted the
      // YAML would parse identically and drop both comments.
      final List<String> before = _flutterApp.split('\n');
      final List<String> after = edited.split('\n');
      int at = 0;
      for (final String line in after) {
        if (at < before.length && line == before[at]) at += 1;
      }
      expect(at, before.length,
          reason: 'line ${at + 1} of the original ("${before.length > at ? before[at] : ''}") '
              'is missing or moved in the edited pubspec');

      final YamlMap parsed = loadYaml(edited) as YamlMap;
      final YamlMap original = loadYaml(_flutterApp) as YamlMap;
      for (final Object? key in original.keys) {
        if (key == 'dependencies') continue;
        expect(parsed[key].toString(), original[key].toString(),
            reason: 'top-level $key changed');
      }
      final YamlMap deps = parsed['dependencies'] as YamlMap;
      for (final Object? key in (original['dependencies'] as YamlMap).keys) {
        expect(deps[key].toString(),
            (original['dependencies'] as YamlMap)[key].toString());
      }
      expect(deps.containsKey('dartvel_core'), isTrue);
      expect(deps.containsKey('dartvel_flutter'), isTrue,
          reason: 'a Flutter application gets the Flutter runtime');
      expect(parsed['dartvel'], isA<YamlMap>());
    });

    test('planning writes nothing', () {
      pubspec().writeAsStringSync(_flutterApp);
      Directory(p.join(root.path, 'lib')).createSync();
      File(p.join(root.path, 'lib', 'main.dart')).writeAsStringSync('void main() {}\n');
      final Map<String, String> before = snapshot();

      final DVAdoptionPlan plan = dvPlanAdoption(root.path);
      plan.render();

      expect(snapshot(), before);
    });

    test('a Dart server gets no Flutter runtime', () {
      pubspec().writeAsStringSync(_dartServer);

      final DVAdoptionPlan plan = dvPlanAdoption(root.path);
      final YamlMap deps =
          (loadYaml(plan.edited!) as YamlMap)['dependencies'] as YamlMap;

      expect(deps.containsKey('dartvel_core'), isTrue);
      expect(deps.containsKey('dartvel_flutter'), isFalse,
          reason: 'usage decides what is linked; a server declared no pages');
      expect(plan.isFlutter, isFalse);
    });

    test('never adds build_runner or a generator package', () {
      pubspec().writeAsStringSync(_dartServer);

      final String edited = dvPlanAdoption(root.path).edited!;

      expect(edited, isNot(contains('build_runner')));
      expect(edited, isNot(contains('dartvel_generator')));
    });

    test('a project with no dependencies block gets one', () {
      pubspec().writeAsStringSync('name: bare\nenvironment:\n  sdk: ^3.13.0\n');

      final DVAdoptionPlan plan = dvPlanAdoption(root.path);
      final YamlMap parsed = loadYaml(plan.edited!) as YamlMap;

      expect((parsed['dependencies'] as YamlMap).containsKey('dartvel_core'),
          isTrue);
    });

    test('an entry already declared is not declared twice', () {
      pubspec().writeAsStringSync('$_dartServer  dartvel_core: ^0.5.0\n');

      final DVAdoptionPlan plan = dvPlanAdoption(root.path);

      expect(plan.addedDependencies, isEmpty);
      expect(
          RegExp('dartvel_core:').allMatches(plan.edited!).length, 1);
    });

    test('keeps CRLF line endings', () {
      pubspec().writeAsStringSync(_dartServer.replaceAll('\n', '\r\n'));

      final String edited = dvPlanAdoption(root.path).edited!;

      expect(edited.replaceAll('\r\n', ''), isNot(contains('\n')),
          reason: 'a lone LF in a CRLF file is a diff on every line to git');
    });

    test('uses path dependencies when the CLI runs from the monorepo', () {
      pubspec().writeAsStringSync(_flutterApp);

      final DVAdoptionPlan plan =
          dvPlanAdoption(root.path, localPackagesDir: '/src/dartvel/packages');
      final YamlMap deps =
          (loadYaml(plan.edited!) as YamlMap)['dependencies'] as YamlMap;

      expect((deps['dartvel_flutter'] as YamlMap)['path'],
          '/src/dartvel/packages/dartvel_flutter');
    });
  });

  group('refusals', () {
    test('no pubspec: that is create\'s job, and nothing is written', () {
      final DVAdoptionPlan plan = dvPlanAdoption(root.path);

      expect(plan.refusal, isNotNull);
      expect(plan.refusal, contains('dartvel create'));
      expect(plan.edited, isNull);
      expect(dvApplyAdoption(plan).written, isFalse);
      expect(root.listSync(), isEmpty);
    });

    test('already initialized: nothing to add', () {
      pubspec().writeAsStringSync('$_dartServer\ndartvel:\n  pagesDir: lib/pages\n');

      final DVAdoptionPlan plan = dvPlanAdoption(root.path);

      expect(plan.alreadyInitialized, isTrue);
      expect(plan.edited, isNull);
      expect(dvApplyAdoption(plan).written, isFalse);
    });

    test('a flow-style dependencies map is refused rather than rewritten', () {
      const String flow =
          'name: flow\nenvironment:\n  sdk: ^3.13.0\ndependencies: {http: ^1.0.0}\n';
      pubspec().writeAsStringSync(flow);

      final DVAdoptionPlan plan = dvPlanAdoption(root.path);

      expect(plan.refusal, isNotNull);
      expect(plan.edited, isNull);
      expect(dvApplyAdoption(plan).written, isFalse);
      expect(pubspec().readAsStringSync(), flow);
    });

    test('a pubspec that does not parse is refused', () {
      pubspec().writeAsStringSync('name: [unclosed\n');

      expect(dvPlanAdoption(root.path).refusal, isNotNull);
    });
  });

  group('the compatibility report', () {
    test('an SDK constraint that excludes Dartvel\'s floor blocks', () {
      pubspec().writeAsStringSync(
          _dartServer.replaceFirst('^3.13.0', '">=2.19.0 <3.10.0"'));

      final DVAdoptionPlan plan = dvPlanAdoption(root.path);

      expect(plan.blocked, isTrue);
      expect(plan.render(), contains('3.13.0'));
      final DVAdoptionApplyResult result = dvApplyAdoption(plan);
      expect(result.written, isFalse);
      expect(pubspec().readAsStringSync(), isNot(contains('dartvel')));
    });

    test('a lower floor that still admits Dartvel\'s is fine', () {
      pubspec().writeAsStringSync(_flutterApp);

      final DVAdoptionPlan plan = dvPlanAdoption(root.path);

      expect(plan.blocked, isFalse);
      expect(
          plan.checks
              .where((DVAdoptionCheck c) => c.subject == 'environment.sdk')
              .single
              .outcome,
          DVAdoptionOutcome.ok);
    });

    test('a missing SDK constraint is unchecked, never compatible', () {
      pubspec().writeAsStringSync('name: nosdk\ndependencies:\n  http: ^1.2.0\n');

      final DVAdoptionPlan plan = dvPlanAdoption(root.path);

      expect(plan.blocked, isFalse);
      expect(plan.fullyChecked, isFalse);
      expect(plan.verdict, isNot('compatible'));
      expect(plan.render(), contains('unchecked'));
    });

    test('a mix pin Dartvel cannot share blocks, and names the drop-in', () {
      pubspec().writeAsStringSync(
          _flutterApp.replaceFirst('  dio: ^5.5.0\n', '  dio: ^5.5.0\n  mix: ^1.5.0\n'));

      final DVAdoptionPlan plan = dvPlanAdoption(root.path);

      expect(plan.blocked, isTrue);
      final DVAdoptionCheck mix = plan.checks
          .singleWhere((DVAdoptionCheck c) => c.subject == 'mix');
      expect(mix.outcome, DVAdoptionOutcome.blocked);
      expect(mix.detail, contains('dartvel_mix'));
    });

    test('a git dependency on a shared package is unchecked', () {
      pubspec().writeAsStringSync(_flutterApp.replaceFirst(
          '  go_router: ^14.6.0\n',
          '  go_router:\n    git: https://example.com/go_router.git\n'));

      final DVAdoptionPlan plan = dvPlanAdoption(root.path);

      expect(
          plan.checks
              .singleWhere((DVAdoptionCheck c) => c.subject == 'go_router')
              .outcome,
          DVAdoptionOutcome.unchecked);
      expect(plan.fullyChecked, isFalse);
    });

    test('an old Dartvel already declared blocks rather than being kept', () {
      pubspec().writeAsStringSync('$_dartServer  dartvel_core: ^0.3.0\n');

      expect(dvPlanAdoption(root.path).blocked, isTrue);
    });

    test('states the multi-tenancy scope once (DV-ADOPT-001)', () {
      pubspec().writeAsStringSync(_flutterApp);

      final String out = dvPlanAdoption(root.path).render();

      expect(RegExp('DV-ADOPT-001').allMatches(out).length, 1);
    });

    test('the shared constraints are the packages\' own', () {
      // A hand-kept table that drifted from the package pubspecs would pass
      // a project Dartvel cannot resolve with, or block one it can.
      for (final String package in <String>['dartvel_core', 'dartvel_flutter']) {
        final YamlMap declared = loadYaml(
                File('../$package/pubspec.yaml').readAsStringSync())
            as YamlMap;
        final Map<String, String> expected = <String, String>{
          for (final MapEntry<Object?, Object?> e
              in (declared['dependencies'] as YamlMap).entries)
            if (e.value is String)
              e.key! as String: e.value! as String
            else if (e.value is YamlMap && (e.value as YamlMap)['version'] is String)
              e.key! as String: (e.value as YamlMap)['version'] as String,
        };
        expect(dvDartvelDependencyConstraints[package], expected,
            reason: '$package/pubspec.yaml and the adoption table disagree');
      }
    });
  });

  group('layout mapping', () {
    test('an existing backend/functions directory is not claimed', () {
      // Every .dart file under <backendDir>/functions is served as an
      // endpoint. Pointing Dartvel at a directory full of the team's own code
      // would publish it.
      pubspec().writeAsStringSync(_flutterApp);
      final File theirs =
          File(p.join(root.path, 'lib', 'backend', 'functions', 'billing.dart'))
            ..createSync(recursive: true)
            ..writeAsStringSync('int charge() => 1;\n');

      final DVAdoptionPlan plan = dvPlanAdoption(root.path);
      final YamlMap dv = (loadYaml(plan.edited!) as YamlMap)['dartvel'] as YamlMap;

      expect(dv['backendDir'], isNot('lib/backend'));
      expect(plan.render(), contains('lib/backend/functions/billing.dart'));
      expect(theirs.existsSync(), isTrue, reason: 'nothing is moved');
    });

    test('an existing legacy *.page.dart is not claimed either', () {
      pubspec().writeAsStringSync(_flutterApp);
      File(p.join(root.path, 'lib', 'pages', 'home.page.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('class Home {}\n');

      final YamlMap dv = (loadYaml(dvPlanAdoption(root.path).edited!)
          as YamlMap)['dartvel'] as YamlMap;

      expect(dv['pagesDir'], isNot('lib/pages'));
    });

    test('the default is written out when nothing is in the way', () {
      pubspec().writeAsStringSync(_flutterApp);

      final YamlMap dv = (loadYaml(dvPlanAdoption(root.path).edited!)
          as YamlMap)['dartvel'] as YamlMap;

      expect(dv['pagesDir'], 'lib/pages');
      expect(dv['backendDir'], 'lib/backend');
    });
  });

  group('applying', () {
    test('writes exactly the plan and touches no other file', () {
      pubspec().writeAsStringSync(_flutterApp);
      File(p.join(root.path, 'lib', 'main.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('void main() {}\n');
      final Map<String, String> before = snapshot();

      final DVAdoptionPlan plan = dvPlanAdoption(root.path);
      final DVAdoptionApplyResult result = dvApplyAdoption(plan);

      expect(result.written, isTrue, reason: result.message);
      final Map<String, String> after = snapshot();
      expect(after.keys.toSet(), before.keys.toSet(),
          reason: 'no scaffold, no temp file left behind');
      expect(after['pubspec.yaml'], plan.edited);
      expect(after['lib/main.dart'], before['lib/main.dart']);
    });

    test('a pubspec changed since the plan was shown is not overwritten', () {
      pubspec().writeAsStringSync(_flutterApp);
      final DVAdoptionPlan plan = dvPlanAdoption(root.path);

      final String concurrent = '$_flutterApp\n# edited in another window\n';
      pubspec().writeAsStringSync(concurrent);
      final DVAdoptionApplyResult result = dvApplyAdoption(plan);

      expect(result.written, isFalse);
      expect(pubspec().readAsStringSync(), concurrent);
    });

    test('a failed write leaves the original whole and no temp file', () {
      if (Platform.isWindows) return;
      pubspec().writeAsStringSync(_flutterApp);
      final DVAdoptionPlan plan = dvPlanAdoption(root.path);
      // A directory nobody may create a file in: the temporary copy cannot
      // be written, so the rename that would replace the pubspec never runs.
      Process.runSync('chmod', <String>['555', root.path]);
      try {
        final DVAdoptionApplyResult result = dvApplyAdoption(plan);
        expect(result.written, isFalse);
      } finally {
        Process.runSync('chmod', <String>['755', root.path]);
      }
      expect(pubspec().readAsStringSync(), _flutterApp);
      expect(root.listSync().map((FileSystemEntity e) => p.basename(e.path)),
          <String>['pubspec.yaml']);
    });
  });

  group('the command', () {
    Future<(int, String)> runInit(List<String> args,
        {bool interactive = false, bool answer = false}) async {
      final StringBuffer out = StringBuffer();
      final int code = await dvRunInit(
        root.path,
        dryRun: args.contains('--dry-run'),
        assumeYes: args.contains('--yes'),
        interactive: interactive,
        confirm: () async => answer,
        out: out.writeln,
      );
      return (code, out.toString());
    }

    test('--dry-run prints the plan and writes nothing', () async {
      pubspec().writeAsStringSync(_flutterApp);

      final (int code, String out) = await runInit(<String>['--dry-run']);

      expect(code, 0);
      expect(out, contains('dartvel_flutter'));
      expect(out, contains('dry run'));
      expect(pubspec().readAsStringSync(), _flutterApp);
    });

    test('not a terminal and no --yes: shown, not applied', () async {
      pubspec().writeAsStringSync(_flutterApp);

      final (int code, String out) = await runInit(const <String>[]);

      expect(code, isNot(0));
      expect(out, contains('--yes'));
      expect(pubspec().readAsStringSync(), _flutterApp);
    });

    test('a declined prompt writes nothing', () async {
      pubspec().writeAsStringSync(_flutterApp);

      final (int code, _) =
          await runInit(const <String>[], interactive: true, answer: false);

      expect(code, isNot(0));
      expect(pubspec().readAsStringSync(), _flutterApp);
    });

    test('--yes applies, after printing the plan', () async {
      pubspec().writeAsStringSync(_flutterApp);

      final (int code, String out) = await runInit(<String>['--yes']);

      expect(code, 0);
      expect(out, contains('+'), reason: 'the plan is printed before it is applied');
      expect(pubspec().readAsStringSync(), contains('dartvel:'));
    });

    test('a blocked plan is not applied even with --yes', () async {
      pubspec().writeAsStringSync(
          _dartServer.replaceFirst('^3.13.0', '">=2.19.0 <3.0.0"'));

      final (int code, _) = await runInit(<String>['--yes']);

      expect(code, isNot(0));
      expect(pubspec().readAsStringSync(), isNot(contains('dartvel')));
    });

    test('init is its own command, and create is no longer reached by it',
        () {
      final CommandRunner<void> runner = CommandRunner<void>('dartvel', 't')
        ..addCommand(InitCommand())
        ..addCommand(AdoptCommand());

      expect(runner.commands['init'], isA<AdoptCommand>());
      expect(runner.commands['create'], isA<InitCommand>());
      expect(runner.commands['new'], isA<InitCommand>());
    });

    test('create\'s refusal points at init now that init exists', () {
      pubspec().writeAsStringSync(_flutterApp);

      expect(dvForeignProjectRefusal(root.path), contains('dartvel init'));
    });
  });
}
