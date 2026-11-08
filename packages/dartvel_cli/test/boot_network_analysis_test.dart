// DV-RUN-007: "a @DVBoot function awaits the network before the first frame"
// (Application Entry). Nothing before ready waits on the network, because a
// launch that blocks on a server is a launch that hangs in a lift -- and the
// boot function that does it looks perfectly reasonable in review.
//
// `dartvel analyze boot` reads the same @DVBoot functions the generator
// lowers, so what it reports is what the app entry will run.
import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/analysis/boot_network.dart';
import 'package:dartvel_cli/src/commands/analyze_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<String> runAnalyze(List<String> args, Directory root) async {
  final StringBuffer out = StringBuffer();
  await runZoned(
    () async {
      final CommandRunner<void> runner =
          CommandRunner<void>('dartvel', 'Test runner')
            ..addCommand(AnalyzeCommand(root: root.path));
      await runner.run(<String>['analyze', ...args]);
    },
    zoneSpecification: ZoneSpecification(
      print: (Zone _, ZoneDelegate __, Zone ___, String line) =>
          out.writeln(line),
    ),
  );
  return out.toString();
}

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dv_run_007_');
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: boot_pkg\n');
    Directory(p.join(root.path, 'lib')).createSync();
  });
  tearDown(() => root.deleteSync(recursive: true));

  void boot(String source) =>
      File(p.join(root.path, 'lib', 'boot.dart')).writeAsStringSync('''
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';

$source
''');

  test('an awaited request in an app boot function is DV-RUN-007, with its '
      'line', () {
    boot('''
@DVBoot()
Future<void> _loadFlags(DVBoot boot) async {
  final Object? flags = await DV.Http.host('flags').get('/rules');
  DV.global<Object?>(flags);
}
''');
    final List<DVBootNetworkFinding> found = dvBootNetworkFindings(root.path);
    expect(found, hasLength(1));
    expect(found.single.code, 'DV-RUN-007');
    expect(found.single.file, 'lib/boot.dart');
    expect(found.single.line, 7);
    expect(found.single.function, '_loadFlags');
    expect(found.single.toString(), contains('DV-RUN-007 lib/boot.dart:7'));
  });

  test('the forms that do not wait on the network before the first frame '
      'pass', () {
    boot('''
@DVBoot(entries: {DVEntryKind.server})
Future<void> _serverOnly(DVBoot boot) async {
  await DV.Http.get('https://api.example/warm');
}

@DVBoot()
void _deferred(DVBoot boot) {
  // Started, not awaited: phase 7 work in all but name.
  unawaited(DVHttp().get('https://flags.example/rules'));
}

@DVBoot()
Future<void> _local(DVBoot boot) async {
  // await DV.Http.get('https://commented.example/out');
  await Future<void>.value();
  DV.log('await DV.Http.get is only words here');
}
''');
    expect(dvBootNetworkFindings(root.path), isEmpty);
  });

  test('dartvel analyze boot prints each finding, and says when there are '
      'none', () async {
    boot('''
@DVBoot()
Future<void> _token(DVBoot boot) async {
  await DVHttp().post('https://push.example/token', body: '{}');
}
''');
    final String out = await runAnalyze(<String>['boot'], root);
    expect(out, contains('DV-RUN-007 lib/boot.dart:'));
    expect(out, contains('_token'));
    expect(out, contains('1 boot function(s)'));

    boot('''
@DVBoot()
void _clock(DVBoot boot) {}
''');
    expect(await runAnalyze(<String>['boot'], root),
        contains('no @DVBoot function awaits the network'));
  });
}
