// The whole generated client, compiled against the real API.
//
// Every other generator test reads the emitted text, and text that reads
// correctly still fails to compile. Four such defects shipped at once in
// models.g.dart, and separately every admin route generated a *private*
// DVRoutes member — the target existed and no application code could name it.
// Both classes of bug are invisible to string matching and obvious to the
// analyzer.
//
// So this generates a project the way `dartvel build` does — router, models,
// jobs, static paths, backend, and the admin pages — resolves it against the
// real dartvel_core and dartvel_flutter, and analyzes the lot.
//
// It costs a `flutter pub get`, which is why it lives in its own file: the
// rest of the generator tests stay instant.
@Timeout(Duration(minutes: 8))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartvel_cli/src/commands/admin_command.dart';
import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A model covering the field shapes that broke: nullable and non-nullable,
/// defaultable and not, a type with no sensible default, and a sensitive one.
const String _model = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Account {
  final String id;
  final String email;
  final String? displayName;
  @DVModel.sensitiveField()
  final String passwordHash;
  final int seats;
  final double balance;
  final bool active;
  final DateTime createdAt;
  final DateTime? cancelledAt;

  const _Account({
    required this.id,
    required this.email,
    this.displayName,
    required this.passwordHash,
    required this.seats,
    required this.balance,
    required this.active,
    required this.createdAt,
    this.cancelledAt,
  });
}
''';

const String _indexPage = '''
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Home')
@pragma('vm:entry-point')
Widget _indexPage(BuildContext context) => const DVText('Home');
''';

/// A nested, parameterised route — the shape whose typed target is generated
/// from the path.
const String _postPage = '''
import 'package:flutter/widgets.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Post')
@pragma('vm:entry-point')
Widget _postPage(BuildContext context) => const DVText('Post');
''';

const String _backendFunction = '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
@pragma('vm:entry-point')
Future<Map<String, Object?>> _ping() async => <String, Object?>{'ok': true};
''';

/// The monorepo root, resolved from this package rather than the working
/// directory — several suites here move it.
Future<String> repoRoot() async {
  final lib = await Isolate.resolvePackageUri(
      Uri.parse('package:dartvel_cli/dartvel_cli.dart'));
  if (lib == null) {
    throw StateError('dartvel_cli could not resolve its own package URI.');
  }
  return p.normalize(p.join(p.dirname(lib.toFilePath()), '..', '..', '..'));
}

void write(String path, String contents) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}

void main() {
  late Directory project;
  late ProcessResult analysis;

  setUpAll(() async {
    final root = await repoRoot();
    project = await Directory.systemTemp.createTemp('dartvel_analyze_');

    write(p.join(project.path, 'lib', 'models', 'account.dart'), _model);
    write(p.join(project.path, 'lib', 'pages', 'index.page.dart'), _indexPage);
    write(p.join(project.path, 'lib', 'pages', 'posts', '[slug].page.dart'),
        _postPage);
    write(p.join(project.path, 'lib', 'backend', 'ping.dart'), _backendFunction);
    write(p.join(project.path, 'pubspec.yaml'), '''
name: generated_client_probe
publish_to: none
environment:
  sdk: ^3.9.0
dependencies:
  flutter:
    sdk: flutter
  dartvel_core:
    path: ${p.join(root, 'packages', 'dartvel_core')}
  dartvel_flutter:
    path: ${p.join(root, 'packages', 'dartvel_flutter')}
dartvel:
  prodBackendHost: https://example.com
''');
    // The Dartvel packages declare hosted constraints on each other so they
    // can be published; pub refuses a path dependency in a published package.
    // A probe that depends on them by path therefore has to override the whole
    // set, or pub reports the two kinds as irreconcilable:
    // "dartvel_flutter from path depends on dartvel_core from hosted and
    // generated_client_probe depends on dartvel_core from path".
    write(p.join(project.path, 'pubspec_overrides.yaml'), '''
dependency_overrides:
  dartvel_core:
    path: ${p.join(root, 'packages', 'dartvel_core')}
  dartvel_flutter:
    path: ${p.join(root, 'packages', 'dartvel_flutter')}
  dartvel_shelf:
    path: ${p.join(root, 'packages', 'dartvel_shelf')}
''');

    // The orchestrator reads the project from the working directory, which is
    // also why this package pins test concurrency to one.
    final previous = Directory.current;
    Directory.current = project;
    try {
      // Admin pages first: they are ordinary pages, so the router has to see
      // them. Generating them afterwards leaves their routes out of DVRoutes
      // entirely, which is also how a bug in route naming went unnoticed.
      DartvelAdminGenerator.generate(root: project, force: true);
      await routes.generate();
    } finally {
      Directory.current = previous;
    }

    final resolved = await Process.run('flutter', <String>['pub', 'get'],
        workingDirectory: project.path);
    if (resolved.exitCode != 0) {
      throw StateError('flutter pub get failed:\n${resolved.stderr}');
    }
    analysis = await Process.run(
      'flutter',
      <String>['analyze', 'lib'],
      workingDirectory: project.path,
    );
  });

  tearDownAll(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  List<String> linesContaining(String marker) => const LineSplitter()
      .convert('${analysis.stdout}${analysis.stderr}')
      .where((String line) => line.contains(marker))
      // The annotated inputs are private by design and referenced only by the
      // generated code, so the analyzer's unused-element warnings about them
      // are the rule working, not a defect.
      .where((String line) => !line.contains('lib/models/account.dart'))
      .where((String line) => !line.contains('lib/backend/'))
      .where((String line) => !line.contains('.page.dart'))
      .toList(growable: false);

  test('the generated project has no analyzer errors', () {
    final errors = linesContaining('error •');

    expect(errors, isEmpty,
        reason: 'the generated project must compile:\n${errors.join('\n')}');
  });

  test('the generated project has no analyzer warnings', () {
    // Warnings are not style here. `String??` parsed as a warning cascade, and
    // the private DVRoutes members showed up as unused_field — which is how a
    // route nobody could navigate to would be caught.
    final warnings = linesContaining('warning •');

    expect(warnings, isEmpty,
        reason: 'the generated project must be warning-clean:\n'
            '${warnings.join('\n')}');
  });

  test('every generated file was actually produced', () {
    // A pass because nothing was generated would be worse than a failure.
    final client = Directory(p.join(project.path, 'lib', 'dartvel_client'));
    final produced = client
        .listSync()
        .whereType<File>()
        .map((File f) => p.basename(f.path))
        .toSet();

    expect(produced, containsAll(<String>[
      'models.g.dart',
      'router.g.dart',
      'widgets.g.dart',
      'functions.g.dart',
      'jobs.g.dart',
      'dartvel_client.dart',
    ]));
    expect(analysis.exitCode, anyOf(0, 1),
        reason: 'flutter analyze did not run: ${analysis.stderr}');
  });

  test('the admin pages were generated and analyzed too', () {
    final admin =
        Directory(p.join(project.path, 'lib', 'pages', '_dartvel_admin'));

    expect(admin.existsSync(), isTrue);
    expect(
      admin.listSync().whereType<File>().map((File f) => p.basename(f.path)),
      containsAll(<String>[
        'index.page.dart',
        'models.page.dart',
        'queues.page.dart',
        'cache.page.dart',
        'routes.page.dart',
        'studio.page.dart',
        'outbox.page.dart',
        'policies.page.dart',
        'telemetry.page.dart',
      ]),
    );
  });
}
