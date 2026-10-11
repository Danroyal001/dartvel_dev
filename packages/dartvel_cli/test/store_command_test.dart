// `dartvel store data-safety`, run against a project on disk.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/store_command.dart';
import 'package:dartvel_cli/src/store/data_safety.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory project;
  late List<String> printed;

  setUp(() {
    project = Directory.systemTemp.createTempSync('dv-store-');
    printed = <String>[];
    File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync('''
name: demo
dependencies:
  firebase_messaging: ^15.0.0
dartvel:
  purchases: {}
  crashes:
    sink: dartvel
''');
  });

  tearDown(() => project.deleteSync(recursive: true));

  Future<void> run(List<String> args) => (CommandRunner<void>('dartvel', 'x')
        ..addCommand(StoreCommand(root: project.path, out: printed.add)))
      .run(<String>['store', ...args]);

  test('prints the CSV by default', () async {
    await run(<String>['data-safety']);
    expect(printed.join('\n'), startsWith('Question ID (machine readable)'));
  });

  test('prints the report as json', () async {
    await run(<String>['data-safety', '--format', 'json']);
    expect(printed.join('\n'), contains('"purchaseHistory"'));
  });

  test('writes the CSV and the worksheet to a directory', () async {
    final String out = p.join(project.path, 'out');
    await run(<String>['data-safety', '--out', out, '--unverified-ids']);
    final String csv = File(p.join(out, 'data-safety.csv')).readAsStringSync();
    expect(csv, contains('PSL_CRASH_LOGS'));
    final String sheet =
        File(p.join(out, 'data-safety-worksheet.md')).readAsStringSync();
    expect(sheet, contains('sdk-firebase_messaging'));
  });

  test('reads the Console template it is given', () async {
    final File template = File(p.join(project.path, 'template.csv'))
      ..writeAsStringSync('Question ID (machine readable),Response (machine readable),Response value,Answer requirement,Human-friendly question label\n'
          'Q_FIN,R_PURCHASE,,MULTIPLE_CHOICE,Financial info > Purchase history\n');
    await run(<String>['data-safety', '--template', template.path]);
    expect(printed.join('\n'), contains('Q_FIN,R_PURCHASE,TRUE'));
  });

  test('a template that is not there is an error, not an empty answer', () async {
    await expectLater(
        run(<String>['data-safety', '--template', '/nonexistent/t.csv']),
        throwsA(isA<UsageException>()));
  });

  test('the writer used by the build puts both files beside the bundle',
      () async {
    final String out = p.join(project.path, 'bundle');
    final List<String> written = dvWriteDataSafetyFiles(
        root: project.path, directory: out);
    expect(written.map(p.basename),
        <String>['data-safety.csv', 'data-safety-worksheet.md']);
    for (final String file in written) {
      expect(File(file).existsSync(), isTrue);
    }
    expect(DVDataSafetyType.values, isNotEmpty);
  });
}
