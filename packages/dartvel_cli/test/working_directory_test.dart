// No suite in this package moves the process working directory.
//
// `Directory.current` is one value for the whole process, and `dart test`
// runs every suite in an isolate of that one process. A suite that changes it
// moves the ground under whichever suite is running beside it, so the failure
// lands somewhere else -- release_coupling, middleware_keys, banned_names,
// shell_command -- and on a different test each run. Pinning concurrency to
// one narrowed that and did not end it: the engine releases a suite's slot
// before the suite has closed.
//
// So the property is checked where it holds or does not: every suite that
// mentions the working directory is run with a setter that refuses. A command
// test gives its command a root instead; a test that wants to know something
// ignores the working directory overrides the getter in a zone, which moves
// nothing outside it.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Printed by the child each time a suite tries to move the directory.
const String _marker = 'DVCWD-WRITE';

/// Printed by the child as each suite's group starts.
const String _ran = 'DVCWD-RAN';

/// This file, which names the property and so mentions it.
const String _self = 'working_directory_test.dart';

void main() {
  test('no suite moves the process working directory', () async {
    // dart test starts every suite in the package root, and nothing here
    // changes that -- which is the point.
    final String package = p.normalize(Directory.current.absolute.path);
    final List<File> suites = Directory(p.join(package, 'test'))
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) =>
            f.path.endsWith('_test.dart') &&
            p.basename(f.path) != _self &&
            f.readAsStringSync().contains('Directory.current'))
        .toList()
      ..sort((File a, File b) => a.path.compareTo(b.path));
    expect(suites, isNotEmpty,
        reason: 'the selection found nothing, so the check would run nothing');

    final Directory scratch =
        Directory.systemTemp.createTempSync('dartvel_cwd_guard_');
    addTearDown(() => scratch.deleteSync(recursive: true));

    final StringBuffer program = StringBuffer()
      ..writeln("import 'dart:io';")
      ..writeln("import 'package:test/test.dart';");
    for (var i = 0; i < suites.length; i++) {
      program.writeln("import '${Uri.file(suites[i].path)}' as s$i;");
    }
    program
      ..writeln('void main() {')
      ..writeln('  IOOverrides.runZoned(() {');
    for (var i = 0; i < suites.length; i++) {
      final String name = p.basename(suites[i].path);
      program
        ..writeln("    group('$name', () {")
        ..writeln("      setUpAll(() => print('$_ran $name'));")
        ..writeln('      s$i.main();')
        ..writeln('    });');
    }
    program
      ..writeln('  }, setCurrentDirectory: (String path) {')
      // On stdout, beside the markers that say which suite is running, so a
      // write is laid at the door of the suite that made it. A suite that
      // catches broadly would otherwise swallow the only evidence.
      ..writeln("    print('$_marker ' + path);")
      // Thrown rather than allowed, so the command under test never runs in
      // this package's own directory and writes into it.
      ..writeln("    throw StateError('moved the process working directory "
          "to ' + path);")
      ..writeln('  });')
      ..writeln('}');
    final File entry = File(p.join(scratch.path, 'guard.dart'))
      ..writeAsStringSync(program.toString());

    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>[
        '--packages=${p.join(package, '.dart_tool', 'package_config.json')}',
        entry.path,
      ],
      workingDirectory: package,
    );
    final List<String> lines = '${result.stdout}'.split('\n');

    // A program that did not compile moves nothing, and would pass. Nor is a
    // summary line enough: a suite that runs `dart test` itself prints one.
    // Every suite has to have started its own group.
    final Set<String> ran = <String>{
      for (final String line in lines)
        if (line.startsWith('$_ran ')) line.substring(_ran.length + 1).trim(),
    };
    for (final File suite in suites) {
      expect(ran, contains(p.basename(suite.path)),
          reason: '${p.basename(suite.path)} never ran, so it was not '
              'checked:\n${result.stdout}\n${result.stderr}');
    }

    final Map<String, List<String>> moved = <String, List<String>>{};
    String running = '(before any suite)';
    for (final String line in lines) {
      if (line.startsWith('$_ran ')) {
        running = line.substring(_ran.length + 1).trim();
      } else if (line.startsWith('$_marker ')) {
        (moved[running] ??= <String>[]).add(line.substring(_marker.length + 1));
      }
    }
    expect(moved, isEmpty,
        reason: 'these suites moved the working directory every other suite '
            'shares; give the command a root instead');
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('the library never moves it either', () {
    // A command that changed directory would do to the user's shell script
    // what a suite does to its neighbours -- and the check above only sees it
    // if some suite happens to reach that line.
    final String package = p.normalize(Directory.current.absolute.path);
    final RegExp write = RegExp(r'Directory\.current\s*=(?!=)');
    final List<String> found = <String>[
      for (final String dir in <String>['lib', 'bin'])
        if (Directory(p.join(package, dir)).existsSync())
          for (final File f in Directory(p.join(package, dir))
              .listSync(recursive: true)
              .whereType<File>()
              .where((File f) => f.path.endsWith('.dart')))
            if (write.hasMatch(f.readAsStringSync()))
              p.relative(f.path, from: package),
    ];
    expect(found, isEmpty);
  });
}
