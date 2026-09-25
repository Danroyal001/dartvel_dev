// The backend functions `dartvel plugin add auth` writes compile.
//
// They carry @DVBackendFunction(rawPath: ...), and for as long as the
// annotation had no rawPath parameter a project that added the plugin stopped
// compiling at the first of them. This writes the plugin into a project that
// resolves the real dartvel_core and analyzes what it wrote.
@Timeout(Duration(minutes: 6))
library;

import 'dart:io';
import 'dart:isolate';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/plugin_command.dart';
import 'package:dartvel_cli/src/generators/raw_path.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory project;

  setUp(() async {
    final Uri cli = (await Isolate.resolvePackageUri(
      Uri.parse('package:dartvel_cli/dartvel_cli.dart'),
    ))!;
    final String packages = p.dirname(p.dirname(p.dirname(cli.toFilePath())));
    project = Directory.systemTemp.createTempSync('dartvel_plugin_auth_');
    File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync('''
name: plugin_auth_probe
publish_to: none
environment:
  sdk: ^3.13.0
dependencies:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
dependency_overrides:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
''');
    await (CommandRunner<void>('dartvel', 'probe')
        ..addCommand(PluginCommand(root: project.path)))
        .run(<String>['plugin', 'add', 'auth']);
  });

  tearDown(() => project.deleteSync(recursive: true));

  test('each auth function declares a raw path the build accepts', () {
    for (final String name in <String>['login.dart', 'logout.dart', 'me.get.dart']) {
      final String rel = 'lib/backend/functions/auth/$name';
      final DVRawPath raw = dvRawPathFromSource(
          File(p.join(project.path, rel)).readAsStringSync(),
          rel: rel);
      expect(raw.rawPath, startsWith('/auth/'), reason: rel);
    }
  });

  test('the auth functions analyze with no errors', () async {
    final ProcessResult got = await Process.run(
        Platform.resolvedExecutable, <String>['pub', 'get'],
        workingDirectory: project.path);
    expect(got.exitCode, 0, reason: '${got.stderr}');
    final ProcessResult analyzed = await Process.run(
      Platform.resolvedExecutable,
      <String>['analyze', '--no-fatal-warnings', 'lib/backend'],
      workingDirectory: project.path,
    );
    expect(analyzed.exitCode, 0,
        reason: '${analyzed.stdout}\n${analyzed.stderr}');
  });
}
