// One capture pipeline. `dartvel prerender` runs the build's own capture
// (`dartvel build web`) and writes nothing of its own.
//
// It used to be a second pipeline: its own server, an older semantics walker
// that lost headings in landmarks and captured guarded routes, written over
// the build's capture files; and its own sitemap.xml and robots.txt naming
// `http://localhost:8080` unless told otherwise -- so running it after a
// build made the production pages worse and pointed crawlers at localhost.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/prerender_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Stands in for `dartvel build`, recording what it was asked.
class _RecordingBuild extends Command<void> {
  _RecordingBuild() {
    argParser.addFlag('prerender', defaultsTo: true);
  }

  final List<List<String>> runs = <List<String>>[];

  @override
  final String name = 'build';

  @override
  final String description = 'recording build';

  @override
  Future<void> run() async => runs.add(<String>[...argResults!.rest]);
}

void main() {
  late Directory root;
  late Directory previous;
  setUp(() {
    previous = Directory.current;
    root = Directory.systemTemp.createTempSync('dartvel_prerender_');
    Directory(p.join(root.path, 'build', 'web')).createSync(recursive: true);
    Directory.current = root;
  });
  tearDown(() {
    Directory.current = previous;
    root.deleteSync(recursive: true);
  });

  test('dartvel prerender runs the build\'s capture and writes nothing itself', () async {
    final _RecordingBuild build = _RecordingBuild();
    final CommandRunner<void> runner = CommandRunner<void>('dartvel', 'test')
      ..addCommand(build)
      ..addCommand(PrerenderCommand());
    await runner.run(<String>['prerender']);
    expect(build.runs, <List<String>>[<String>['web']]);
    for (final String name in <String>['sitemap.xml', 'robots.txt']) {
      expect(File(p.join(root.path, 'build', 'web', name)).existsSync(), isFalse, reason: name);
    }
    expect(Directory(p.join(root.path, '.dart_tool', 'dartvel_semantics')).existsSync(), isFalse);
  });

  test('an old --base-url is accepted and not used', () async {
    final _RecordingBuild build = _RecordingBuild();
    final CommandRunner<void> runner = CommandRunner<void>('dartvel', 'test')
      ..addCommand(build)
      ..addCommand(PrerenderCommand());
    await runner.run(<String>['prerender', '--base-url', 'http://localhost:8080']);
    expect(build.runs, hasLength(1));
    expect(File(p.join(root.path, 'build', 'web', 'sitemap.xml')).existsSync(), isFalse);
  });

  test('the build no longer sends people to dartvel prerender', () {
    final String capture =
        File(p.join(previous.path, 'lib', 'src', 'build', 'semantics_capture.dart')).readAsStringSync();
    expect(capture, isNot(contains('run `dartvel prerender`')));
  });
}
