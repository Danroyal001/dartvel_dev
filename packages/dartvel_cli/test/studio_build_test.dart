// The Studio a web-server build carries.
//
// The build wrote a static manifest into the admin root and nothing else, so
// the Studio the binary served could list model names and do nothing with
// them; the real one -- records, forms, the page builder -- was only in the
// Flutter admin pages, which the same build leaves out of the client. This
// compiles DVStudioApp into the admin root instead, served at the mount, and
// keeps the manifest beside it for the Routes, Functions and Jobs sections.
//
// No compiler here: the run is a stand-in that writes what `flutter build web`
// writes, and the assertions are on what lands in the admin root.
import 'dart:io';

import 'package:dartvel_cli/src/build/studio_build.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory project;
  late String adminRoot;
  late List<List<String>> runs;

  setUp(() {
    project = Directory.systemTemp.createTempSync('dv_studio_build_');
    addTearDown(() => project.deleteSync(recursive: true));
    adminRoot = p.join(project.path, 'build', 'web', '__admin');
    // What the manifest step already wrote.
    for (final String name in <String>[
      'index.html',
      'admin.css',
      'admin.js',
      'graph.json',
    ]) {
      File(p.join(adminRoot, name))
        ..createSync(recursive: true)
        ..writeAsStringSync('manifest $name');
    }
    runs = <List<String>>[];
  });

  Future<ProcessResult> compiles(String executable, List<String> arguments,
      {String? workingDirectory}) async {
    runs.add(<String>[executable, ...arguments]);
    final String out = arguments[arguments.indexOf('-o') + 1];
    File(p.join(out, 'main.dart.js'))
      ..createSync(recursive: true)
      ..writeAsStringSync('// studio');
    File(p.join(out, 'flutter_bootstrap.js')).writeAsStringSync('// boot');
    File(p.join(out, 'canvaskit', 'canvaskit.wasm'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(<int>[0, 97, 115, 109]);
    File(p.join(out, 'index.html'))
        .writeAsStringSync('<html><title>the app\'s own shell</title></html>');
    return ProcessResult(0, 0, '', '');
  }

  test('compiles DVStudioApp at the mount, with nothing from a CDN', () async {
    final DVStudioBuildResult result = await dvBuildStudio(
      root: project.path,
      mount: '/ops/panel',
      adminRoot: adminRoot,
      appName: 'Shop',
      run: compiles,
    );

    expect(result.ok, isTrue, reason: result.lines.join('\n'));
    final List<String> command = runs.single;
    expect(command.first, 'flutter');
    expect(command.sublist(1, 3), <String>['build', 'web']);
    final String entry = command[command.indexOf('-t') + 1];
    expect(File(entry).readAsStringSync(), contains('DVStudioApp('));
    expect(File(entry).readAsStringSync(),
        contains('dvStudioBrowserTransport()'));
    // The mount the build decided: a project that moved its admin must not
    // find Studio's files requested from /__studio.
    expect(command[command.indexOf('--base-href') + 1], '/ops/panel/');
    // The backend may have no route to the internet.
    expect(command, contains('--no-web-resources-cdn'));
    expect(command, contains('--release'));
  });

  test('the admin root is Studio, with the manifest kept beside it', () async {
    await dvBuildStudio(
      root: project.path,
      mount: '/__studio',
      adminRoot: adminRoot,
      appName: 'Shop',
      run: compiles,
    );

    expect(File(p.join(adminRoot, 'main.dart.js')).existsSync(), isTrue);
    expect(File(p.join(adminRoot, 'canvaskit', 'canvaskit.wasm')).existsSync(),
        isTrue);
    expect(File(p.join(adminRoot, 'graph.json')).readAsStringSync(),
        'manifest graph.json');
    // The static dashboard is replaced, not left for somebody to open.
    expect(File(p.join(adminRoot, 'admin.js')).existsSync(), isFalse);
    expect(File(p.join(adminRoot, 'admin.css')).existsSync(), isFalse);

    final String index =
        File(p.join(adminRoot, 'index.html')).readAsStringSync();
    expect(index, contains('<base href="/__studio/">'));
    expect(index, contains('flutter_bootstrap.js'));
    expect(index, contains('noindex'));
    expect(index, isNot(contains("the app's own shell")));
  });

  test('an application name is escaped where the shell shows it', () async {
    await dvBuildStudio(
      root: project.path,
      mount: '/__studio',
      adminRoot: adminRoot,
      appName: '<script>x</script>',
      run: compiles,
    );

    final String index =
        File(p.join(adminRoot, 'index.html')).readAsStringSync();
    expect(index, isNot(contains('<script>x</script>')));
  });

  test('a failed compile fails, and leaves the manifest as it was', () async {
    final DVStudioBuildResult result = await dvBuildStudio(
      root: project.path,
      mount: '/__studio',
      adminRoot: adminRoot,
      appName: 'Shop',
      run: (String executable, List<String> arguments,
              {String? workingDirectory}) async =>
          ProcessResult(0, 1, '', 'Error: something did not compile'),
    );

    expect(result.ok, isFalse);
    expect(result.lines.join('\n'), contains('something did not compile'));
    expect(File(p.join(adminRoot, 'admin.js')).readAsStringSync(),
        'manifest admin.js');
  });
}
