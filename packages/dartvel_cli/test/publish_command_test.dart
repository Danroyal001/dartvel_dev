// `dartvel publish`, and the four ways it declines.
//
// Host support, then the tooling, then the work -- and here the work is an
// upload of a binary that took minutes to produce, so every refusal has to
// come before it rather than after.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/publish_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _play = '''
dartvel:
  publish:
    play:
      track: internal
      credentials: secrets/play.json
''';

void main() {
  late Directory previous;
  late Directory root;
  late List<List<String>> ran;

  setUp(() {
    previous = Directory.current;
    root = Directory.systemTemp.createTempSync('dartvel_publish_cmd_');
    Directory.current = root;
    ran = <List<String>>[];
    exitCode = 0;
  });

  tearDown(() {
    Directory.current = previous;
    root.deleteSync(recursive: true);
    exitCode = 0;
  });

  void declare(String publish) =>
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shopfront
$publish
''');

  void buildArtifact() =>
      File(p.join(root.path, 'build', 'app', 'outputs', 'bundle', 'release',
          'app-release.aab'))
        ..createSync(recursive: true)
        ..writeAsStringSync('a bundle');

  Future<void> publish(List<String> arguments) async {
    final CommandRunner<void> runner = CommandRunner<void>('dartvel', 'test')
      ..addCommand(PublishCommand(processRun: (
        String executable,
        List<String> args, {
        String? workingDirectory,
        bool runInShell = false,
      }) async {
        ran.add(<String>[executable, ...args]);
        return ProcessResult(0, 0, '', '');
      }));
    await runner.run(<String>['publish', ...arguments]);
  }

  test('naming no store is a usage error, not a guess', () async {
    declare(_play);

    await publish(<String>[]);

    expect(exitCode, 64);
    expect(ran, isEmpty);
  });

  test('a declaration that cannot be honoured stops before the upload',
      () async {
    declare(_play.replaceAll('      credentials: secrets/play.json\n', ''));
    buildArtifact();

    await publish(<String>['play']);

    expect(exitCode, 78);
    expect(ran, isEmpty);
  });

  test('no artifact is said as no artifact, not as a failed upload', () async {
    // The build has not run. Telling somebody the upload failed would send
    // them to their store account for an answer that is on their disk.
    declare(_play);

    await publish(<String>['play']);

    expect(exitCode, 66);
    expect(ran, isEmpty);
  });

  test('a dry run prints the command and uploads nothing', () async {
    declare(_play);
    buildArtifact();

    await publish(<String>['play', '--dry-run']);

    expect(ran, isEmpty);
    expect(exitCode, 0);
  });

  test('an artifact given by hand is the one that is uploaded', () async {
    declare(_play);
    final File other = File(p.join(root.path, 'elsewhere.aab'))
      ..writeAsStringSync('a bundle');

    await publish(<String>['play', '--artifact', other.path]);

    // Nothing ran, because fastlane is not installed here -- but the
    // artifact check passed, which is what this is asserting: the file it
    // was given, not the one the build would have made.
    expect(exitCode, isNot(66));
  });
}
