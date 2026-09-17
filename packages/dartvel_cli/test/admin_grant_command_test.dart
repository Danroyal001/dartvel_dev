// `dartvel admin grant`: who may open Studio on a deployed application.
//
// Nobody may until somebody is granted, and the grant is what the running
// backend reads. So each case here writes with the command and reads back
// with the store the backend uses, against the database file the command
// was pointed at -- not the command's own output.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/admin_command.dart';
import 'package:dartvel_core/dartvel.dart'
    show DVStudioGrants, SqliteDVDatabaseAdapter;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory project;
  late List<String> lines;
  late String database;

  setUp(() {
    project = Directory.systemTemp.createTempSync('dartvel_admin_grant_');
    addTearDown(() => project.deleteSync(recursive: true));
    File(p.join(project.path, 'pubspec.yaml'))
        .writeAsStringSync('name: shop\n');
    // Where a web-server binary keeps its SQLite file.
    database = p.join(project.path, 'deploy', 'dartvel_data', 'data.db');
    Directory(p.dirname(database)).createSync(recursive: true);
    SqliteDVDatabaseAdapter.file(database);
    lines = <String>[];
  });

  Future<int> run(List<String> arguments,
      {Map<String, String> environment = const <String, String>{}}) async {
    int code = 0;
    final CommandRunner<void> runner = CommandRunner<void>('dartvel', '')
      ..addCommand(AdminCommand(
        root: project.path,
        environment: environment,
        out: lines.add,
        setExitCode: (int value) => code = value,
      ));
    await runner.run(<String>['admin', ...arguments]);
    return code;
  }

  Future<bool> granted(String user, {String tenant = 'default'}) =>
      DVStudioGrants(SqliteDVDatabaseAdapter.file(database))
          .isGranted(user, tenant: tenant);

  test('grants Studio to an account, in the database it is pointed at',
      () async {
    expect(await granted('u-operator'), isFalse);

    expect(await run(<String>['grant', 'u-operator', '--database', database]),
        0, reason: lines.join('\n'));

    expect(await granted('u-operator'), isTrue);
    // Nobody else came with it.
    expect(await granted('u-customer'), isFalse);
  });

  test('grants on the tenant it is told, and only that one', () async {
    expect(
        await run(<String>[
          'grant',
          'u-operator',
          '--tenant',
          'acme',
          '--database',
          database,
        ]),
        0,
        reason: lines.join('\n'));

    expect(await granted('u-operator', tenant: 'acme'), isTrue);
    expect(await granted('u-operator'), isFalse);
  });

  test('revokes, and lists what is granted', () async {
    await run(<String>['grant', 'u-operator', '--database', database]);
    await run(<String>['grant', 'u-owner', '--database', database]);
    lines.clear();

    expect(await run(<String>['list', '--database', database]), 0);
    expect(lines.join('\n'), allOf(contains('u-operator'), contains('u-owner')));

    expect(await run(<String>['revoke', 'u-operator', '--database', database]),
        0);
    expect(await granted('u-operator'), isFalse);
    expect(await granted('u-owner'), isTrue);

    // Revoking somebody who holds no grant says so and fails, rather than
    // reporting a revocation that did nothing.
    expect(await run(<String>['revoke', 'u-nobody', '--database', database]),
        isNot(0));
  });

  test('refuses a database that does not exist rather than creating one',
      () async {
    // A grant written into a new empty file is a grant the running server
    // never reads, reported as done.
    final String missing = p.join(project.path, 'nowhere', 'data.db');
    expect(await run(<String>['grant', 'u-operator', '--database', missing]),
        isNot(0));
    expect(File(missing).existsSync(), isFalse);
    expect(lines.join('\n'), contains(missing));
  });

  test('refuses a grant with no account', () async {
    expect(await run(<String>['grant', '--database', database]), isNot(0));
  });
}
