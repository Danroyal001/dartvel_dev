// The generated client, compiled against the real API.
//
// Every other model test reads the emitted text, and text that reads
// correctly still fails to compile — four such defects shipped at once, and a
// project generated from a model with a nullable or DateTime field could not
// be built at all. Nothing short of running the analyzer over the output
// catches that class of bug, so this generates a project and analyzes it.
//
// It costs a `flutter pub get`, which is why it lives in its own file: the
// rest of the model tests stay instant.
@Timeout(Duration(minutes: 6))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A model covering the field shapes a real application uses, including the
/// ones that broke: nullable and non-nullable, defaultable and not, a type
/// with no sensible default, and a sensitive field.
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

/// The monorepo root, resolved from this package rather than the working
/// directory — other suites in this package move it.
Future<String> repoRoot() async {
  final lib = await Isolate.resolvePackageUri(
      Uri.parse('package:dartvel_cli/dartvel_cli.dart'));
  if (lib == null) {
    throw StateError('dartvel_cli could not resolve its own package URI.');
  }
  // .../packages/dartvel_cli/lib/dartvel_cli.dart -> .../
  return p.normalize(p.join(p.dirname(lib.toFilePath()), '..', '..', '..'));
}

Future<ProcessResult> run(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
}) =>
    Process.run(executable, arguments, workingDirectory: workingDirectory);

void main() {
  late Directory project;
  late ProcessResult analysis;

  setUpAll(() async {
    final root = await repoRoot();
    project = await Directory.systemTemp.createTemp('dartvel_analyze_');
    Directory(p.join(project.path, 'lib', 'models'))
        .createSync(recursive: true);
    Directory(p.join(project.path, 'lib', 'dartvel_client'))
        .createSync(recursive: true);
    File(p.join(project.path, 'lib', 'models', 'account.dart'))
        .writeAsStringSync(_model);
    File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync('''
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
''');

    await ModelGenerator.generate(
      root: project.path,
      pkgName: 'generated_client_probe',
      buildId: 'analyze-test',
    );

    final resolved =
        await run('flutter', <String>['pub', 'get'], workingDirectory: project.path);
    if (resolved.exitCode != 0) {
      throw StateError('flutter pub get failed:\n${resolved.stderr}');
    }
    // Only the generated directory: the annotated input is deliberately a
    // private unreferenced class, which the analyzer warns about by design.
    analysis = await run(
      'flutter',
      <String>['analyze', p.join('lib', 'dartvel_client')],
      workingDirectory: project.path,
    );
  });

  tearDownAll(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  test('the generated client has no analyzer errors', () {
    final output = '${analysis.stdout}${analysis.stderr}';
    final errors = const LineSplitter()
        .convert(output)
        .where((String line) => line.contains('error •'))
        .toList(growable: false);

    expect(
      errors,
      isEmpty,
      reason: 'the generated client must compile:\n${errors.join('\n')}',
    );
  });

  test('the generated client has no analyzer warnings', () {
    // Warnings here are not style: `String??` parsed as a warning cascade,
    // and dead null-aware operators were how the broken getters showed up.
    final output = '${analysis.stdout}${analysis.stderr}';
    final warnings = const LineSplitter()
        .convert(output)
        .where((String line) => line.contains('warning •'))
        .toList(growable: false);

    expect(
      warnings,
      isEmpty,
      reason: 'the generated client must be warning-clean:\n'
          '${warnings.join('\n')}',
    );
  });

  test('the analyzer actually ran over the generated file', () {
    // A pass because nothing was analyzed would be worse than a failure.
    expect(
      File(p.join(project.path, 'lib', 'dartvel_client', 'models.g.dart'))
          .existsSync(),
      isTrue,
    );
    expect(analysis.exitCode, anyOf(0, 1),
        reason: 'flutter analyze did not run: ${analysis.stderr}');
  });
}
