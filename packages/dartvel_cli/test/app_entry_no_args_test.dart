// `DV.run()` takes nothing (owner, 14 Oct 2026): `void main() => DV.run();` is
// the whole of a pure app's main.dart.
//
// The process's arguments still matter -- a file opened with the app, a
// dartvel:// link, a command dispatched to a command entry -- and Dart hands
// them only to a `main(List<String>)`. So the generator writes the entry the
// build compiles, lib/dartvel_client/main.g.dart, which keeps the arguments
// and calls the app's own main, and DV.run reads them from there.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/build/app_entry.dart';
import 'package:dartvel_cli/src/commands/build_command.dart';
import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:dartvel_cli/src/templates/project_templates.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<Directory> _generated(String mainSource) async {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_entry_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
  File(p.join(root.path, 'lib', 'main.dart')).writeAsStringSync(mainSource);
  File(p.join(root.path, 'lib', 'pages', 'index.dart')).writeAsStringSync('''
import 'package:flutter/widgets.dart';
import '../dartvel_client/dartvel_client.dart';
@DVPage()
Widget _indexPage(BuildContext context) => const DVText('Home');
''');
  await ClientGenerator.generate(
    root: root.path, pagesDir: 'lib/pages', pkgName: 'entry_app', buildId: 'test',
    backendHost: '127.0.0.1', backendPort: 3000, devBackendHost: 'http://localhost:3000',
    prodBackendHost: 'https://api.example.test', apiBasePath: '/api', envFiles: const <String>[],
    seoSiteName: 'A', seoTitle: 'A', seoDesc: 'A', seoImage: '', seoTwitter: '',
    defaultTransition: 'fade', durationMs: 200, curve: 'easeInOut', normalizeTrailing: true,
    notFoundRedirect: '', plugins: const <String>[], ota: false, dv: YamlMap.wrap(<String, Object?>{}),
  );
  return root;
}

String _read(Directory root, String rel) => File(p.join(root.path, rel)).readAsStringSync();

void main() {
  test('the scaffold teaches DV.run() with nothing passed', () {
    expect(ProjectTemplates.mainTemplate, contains('void main() => DV.run();'));
    expect(ProjectTemplates.mainTemplate, isNot(contains('DV.run(args)')));
  });

  test('the generated entry keeps the arguments and calls a no-argument main', () async {
    final Directory root = await _generated(
        "import 'dartvel_client/dartvel_client.dart';\n\nvoid main() => DV.run();\n");
    final String entry = _read(root, 'lib/dartvel_client/main.g.dart');
    expect(entry, contains("import 'package:entry_app/main.dart' as app;"));
    expect(entry, contains('void main(List<String> args) {'));
    expect(entry, contains('dvSetLaunchArguments(args);'));
    expect(entry, contains('app.main();'));
  });

  test('an app still written as main(List<String> args) keeps working', () async {
    final Directory root = await _generated(
        "import 'dartvel_client/dartvel_client.dart';\n\nvoid main(List<String> args) => DV.run(args);\n");
    expect(_read(root, 'lib/dartvel_client/main.g.dart'), contains('app.main(args);'));
  });

  test('DV.run() falls back to the arguments the entry kept', () async {
    final Directory root = await _generated(
        "import 'dartvel_client/dartvel_client.dart';\n\nvoid main() => DV.run();\n");
    final String application = _read(root, 'lib/dartvel_client/application.g.dart');
    expect(application, contains('static Future<void> run([List<String>? args]) => dvRunApplication(args ?? dvLaunchArguments,'));
  });

  test('the entry the build compiles is the generated one, when there is one', () async {
    final Directory root = await _generated(
        "import 'dartvel_client/dartvel_client.dart';\n\nvoid main() => DV.run();\n");
    expect(dvAppEntryTarget(root.path), 'lib/dartvel_client/main.g.dart');
    final Directory bare = Directory.systemTemp.createTempSync('dartvel_entry_bare_');
    addTearDown(() => bare.deleteSync(recursive: true));
    expect(dvAppEntryTarget(bare.path), isNull);
  });

  test('dartvel build hands Flutter the generated entry', () async {
    final Directory root = await _generated(
        "import 'dartvel_client/dartvel_client.dart';\n\nvoid main() => DV.run();\n");
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: entry_app\n');
    // A web scaffold already there, so the faked build reaches Flutter's build.
    Directory(p.join(root.path, 'web')).createSync();
    File(p.join(root.path, 'web', 'index.html')).writeAsStringSync('<html><head></head><body></body></html>');
    final List<String> calls = <String>[];
    final BuildCommand command = BuildCommand(
      root: root.path,
      preflight: (String platform, {bool? autoInstall}) async => true,
      processRun: (String executable, List<String> arguments,
          {String? workingDirectory, bool runInShell = false}) async {
        calls.add(<String>[executable, ...arguments].join(' '));
        return ProcessResult(0, 0, '', '');
      },
      hasBuildRunner: (String root) => false,
    );
    final int before = exitCode;
    try {
      await (CommandRunner<void>('dartvel', 'test')..addCommand(command))
          .run(<String>['build', 'web', '--no-prerender']);
    } catch (_) {
      // Whatever a faked build trips over after the Flutter call is not
      // what this asks.
    } finally {
      exitCode = before;
    }
    final String flutterBuild = calls.firstWhere(
        (String c) => c.startsWith('flutter build web'),
        orElse: () => 'no flutter build web in $calls');
    expect(flutterBuild, contains('--target lib/dartvel_client/main.g.dart'));
  });

  test('nothing that teaches Dartvel passes arguments to DV.run', () {
    // The repository root, from packages/dartvel_cli.
    final Directory repo = Directory(p.normalize(p.join(Directory.current.path, '..', '..')));
    final List<File> teaching = <File>[
      File(p.join(repo.path, 'README.md')),
      File(p.join(repo.path, 'NEW_SPEC.md')),
      File(p.join(repo.path, 'docs', 'getting-started.md')),
      for (final String dir in <String>['examples', p.join('sites', 'dartvel_site', 'lib')])
        for (final FileSystemEntity e in Directory(p.join(repo.path, dir)).listSync(recursive: true))
          if (e is File && e.path.endsWith('.dart') && !e.path.contains('dartvel_client')) e,
    ];
    final List<String> offenders = <String>[
      for (final File f in teaching)
        if (f.existsSync() && f.readAsStringSync().contains('DV.run(args)'))
          p.relative(f.path, from: repo.path),
    ];
    expect(offenders, isEmpty);
  });
}
