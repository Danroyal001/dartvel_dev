// `dartvel privacy check | export | erase | retention --plan`.
//
// Each subcommand guards a failure that looks like success. An erasure that
// runs because nobody was asked; one run in a pipeline because a prompt was
// answered by nothing; one against tables it cannot write at the version it
// read, which deletes half a subject and reports the rest; an export written
// somewhere nobody chose; a retention plan that changes what it was only
// meant to describe. So each test looks at the database afterwards, not only
// at what was printed.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/privacy_command.dart';
import 'package:dartvel_core/dartvel.dart';
// The record layer, which a test of the privacy walk names.
import 'package:dartvel_core/framework.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _user = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel(subject: DVSubject.self, retain: DVRetention.indefinite)
class _User {
  final String id;
  final String email;
  @DVModel.sensitiveField()
  final String nationalId;
  const _User({required this.id, required this.email, required this.nationalId});
}
''';

const String _order = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel(subject: #userId, retain: DVRetention.days(30, then: DVRetention.anonymize))
class _Order {
  final String id;
  final String userId;
  final String createdAt;
  @DVModel.sensitiveField()
  final String cardLast4;
  @DVModel.retain(years: 7, because: 'tax law')
  final String invoiceNumber;
  const _Order({
    required this.id,
    required this.userId,
    required this.createdAt,
    required this.cardLast4,
    required this.invoiceNumber,
  });
}
''';

const String _visit = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel(subject: #userId, retain: DVRetention.days(30, from: 'at'))
class _Visit {
  final String id;
  final String userId;
  final String at;
  const _Visit({required this.id, required this.userId, required this.at});
}
''';

final String _key = List<String>.filled(32, 'a7').join();
final DateTime _now = DateTime.utc(2026, 9, 1);

class _Run {
  _Run(this.lines, this.exitCode);
  final List<String> lines;
  final int? exitCode;
  String get text => lines.join('\n');
}

void main() {
  late Directory project;
  late String dbPath;

  Future<SqliteDVDatabaseAdapter> database() async =>
      SqliteDVDatabaseAdapter.file(dbPath);

  DVRecordTable table(DVDatabaseAdapter db, String name, List<String> columns,
          {Set<String> sensitive = const <String>{}}) =>
      DVRecordTable(
          table: name,
          key: 'id',
          columns: columns,
          sensitive: sensitive,
          database: db);

  Future<void> seed({bool versioned = true}) async {
    final SqliteDVDatabaseAdapter db = await database();
    if (versioned) {
      final DVRecordTable users =
          table(db, 'users', <String>['id', 'email', 'nationalId']);
      final DVRecordTable orders = table(db, 'orders',
          <String>['id', 'userId', 'createdAt', 'cardLast4', 'invoiceNumber']);
      await users.ensureSchema();
      await orders.ensureSchema();
      final DVRecordTable visits =
          table(db, 'visits', <String>['id', 'userId', 'at']);
      await visits.ensureSchema();
      await visits.write(<String, Object?>{
        'id': 'v1', 'userId': '7', 'at': '2026-01-01T00:00:00Z',
      });
      await users.write(<String, Object?>{
        'id': '1042', 'email': 'ada@example.com', 'nationalId': 'X-1',
      });
      await users.write(<String, Object?>{
        'id': '7', 'email': 'bob@example.com', 'nationalId': 'X-2',
      });
      await orders.write(<String, Object?>{
        'id': 'o1', 'userId': '1042', 'createdAt': '2026-01-01T00:00:00Z',
        'cardLast4': '4242', 'invoiceNumber': 'INV-1',
      });
    } else {
      // The table the generated model creates today: its fields and nothing
      // else, so no version column to write at.
      await db.execute(
          'CREATE TABLE users (id TEXT, email TEXT, nationalId TEXT)');
      await db.execute(
          'CREATE TABLE orders (id TEXT, userId TEXT, createdAt TEXT, '
          'cardLast4 TEXT, invoiceNumber TEXT)');
      await db.execute(
          "INSERT INTO users VALUES ('1042', 'ada@example.com', 'X-1')");
      await db.execute('CREATE TABLE visits (id TEXT, userId TEXT, at TEXT)');
    }
    db.close();
  }

  Future<List<Map<String, Object?>>> rows(String name) async {
    final SqliteDVDatabaseAdapter db = await database();
    try {
      return await db.query('SELECT * FROM $name');
    } finally {
      db.close();
    }
  }

  Future<_Run> run(
    List<String> args, {
    Map<String, String>? environment,
    bool interactive = false,
    List<String> answers = const <String>[],
  }) async {
    final List<String> lines = <String>[];
    int? code;
    final List<String> pending = List<String>.of(answers);
    final CommandRunner<void> runner = CommandRunner<void>('dartvel', 'test')
      ..addCommand(PrivacyCommand(
        root: project.path,
        environment: environment ??
            <String, String>{'DARTVEL_PRIVACY_KEY': _key},
        interactive: interactive,
        readLine: () => pending.isEmpty ? null : pending.removeAt(0),
        out: lines.add,
        setExitCode: (int c) => code = c,
        now: () => _now,
      ));
    await runner.run(<String>['privacy', ...args]);
    return _Run(lines, code);
  }

  setUp(() {
    project = Directory.systemTemp.createTempSync('dv_privacy_cmd_');
    dbPath = p.join(project.path, 'app.db');
    File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync('''
name: privacy_cmd_probe
publish_to: none
environment:
  sdk: ^3.9.0
dartvel:
  database:
    provider: sqlite
    path: app.db
''');
    for (final MapEntry<String, String> m in <String, String>{
      'user': _user,
      'order': _order,
      'visit': _visit,
    }.entries) {
      File(p.join(project.path, 'lib', 'models', '${m.key}.dart'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(m.value);
    }
  });

  tearDown(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  group('check', () {
    test('lists every model with its subject path and retention', () async {
      final _Run r = await run(<String>['check']);
      expect(r.text, contains('User'));
      expect(r.text, contains('self'));
      expect(r.text, contains('Order'));
      expect(r.text, contains('userId'));
      expect(r.text, contains('30 days from createdAt, then anonymized'));
      expect(r.text, contains('tax law'));
      expect(r.exitCode, anyOf(isNull, 0));
    });

    test('a sensitive field no path reaches fails the check', () async {
      File(p.join(project.path, 'lib', 'models', 'card.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Card {
  final String id;
  @DVModel.sensitiveField()
  final String number;
  const _Card({required this.id, required this.number});
}
''');
      final _Run r = await run(<String>['check']);
      expect(r.text, contains('DV-PRIVACY-001'));
      expect(r.text, contains('Card'));
      expect(r.exitCode, 1);
    });
  });

  group('erase', () {
    test('without confirmation, and nobody to ask, erases nothing', () async {
      await seed();
      final _Run r = await run(
          <String>['erase', '--subject', 'user:1042', '--reason', 'DSAR 1']);
      expect(r.exitCode, 1);
      expect(r.text, contains('--yes'));
      expect(await rows('users'), hasLength(2));
      expect(await rows('orders'), hasLength(1));
    });

    test('at a terminal, anything but a typed yes erases nothing', () async {
      await seed();
      for (final String answer in <String>['y', 'YES please', '']) {
        final _Run r = await run(
          <String>['erase', '--subject', 'user:1042', '--reason', 'DSAR 1'],
          interactive: true,
          answers: <String>[answer],
        );
        expect(r.exitCode, 1, reason: 'answer "$answer"');
        expect(await rows('users'), hasLength(2), reason: 'answer "$answer"');
      }
    });

    test('in CI a terminal is not asked; only the flag erases', () async {
      await seed();
      final _Run r = await run(
        <String>['erase', '--subject', 'user:1042', '--reason', 'DSAR 1'],
        environment: <String, String>{'DARTVEL_PRIVACY_KEY': _key, 'CI': 'true'},
        interactive: true,
        answers: <String>['yes'],
      );
      expect(r.exitCode, 1);
      expect(await rows('users'), hasLength(2));
    });

    test('a typed yes erases, and says what was kept and why', () async {
      await seed();
      final _Run r = await run(
        <String>['erase', '--subject', 'user:1042', '--reason', 'DSAR 1'],
        interactive: true,
        answers: <String>['yes'],
      );
      expect(r.exitCode, anyOf(isNull, 0), reason: r.text);
      expect((await rows('users')).map((Map<String, Object?> u) => u['id']),
          <Object?>['7']);
      final Map<String, Object?> order = (await rows('orders')).single;
      expect(order['cardLast4'], DVPrivacy.tombstone);
      expect(r.text, contains('tax law'));
      expect(r.text, isNot(contains('1042')),
          reason: 'the receipt names the subject by pseudonym only');
    });

    test('--yes erases where nobody can be asked', () async {
      await seed();
      final _Run r = await run(<String>[
        'erase', '--subject', 'user:1042', '--reason', 'DSAR 1', '--yes',
      ]);
      expect(r.exitCode, anyOf(isNull, 0), reason: r.text);
      expect(await rows('users'), hasLength(1));
    });

    test('without the signing key nothing is erased', () async {
      await seed();
      final _Run r = await run(
        <String>['erase', '--subject', 'user:1042', '--reason', 'DSAR', '--yes'],
        environment: const <String, String>{},
      );
      expect(r.exitCode, 1);
      expect(r.text, contains('DARTVEL_PRIVACY_KEY'));
      expect(await rows('users'), hasLength(2));
    });

    test('tables with no version column are refused before anything is '
        'deleted', () async {
      await seed(versioned: false);
      final _Run r = await run(<String>[
        'erase', '--subject', 'user:1042', '--reason', 'DSAR', '--yes',
      ]);
      expect(r.exitCode, 1);
      expect(r.text, contains('users'));
      expect(r.text, contains('_dv_version'));
      expect(await rows('users'), hasLength(1));
    });

    test('a subject that is not a DVSubject.self model is refused', () async {
      await seed();
      final _Run r = await run(<String>[
        'erase', '--subject', 'order:o1', '--reason', 'DSAR', '--yes',
      ]);
      expect(r.exitCode, 1);
      expect(r.text, contains('DVSubject.self'));
      expect(await rows('orders'), hasLength(1));
    });
  });

  group('export', () {
    test('writes the archive to the path given, and only there', () async {
      await seed();
      final String out = p.join(project.path, 'exports', 'ada.json');
      final _Run r = await run(
          <String>['export', '--subject', 'user:1042', '--out', out]);
      expect(r.exitCode, anyOf(isNull, 0), reason: r.text);
      final Map<String, Object?> archive =
          jsonDecode(File(out).readAsStringSync()) as Map<String, Object?>;
      final Map<String, Object?> records =
          archive['records']! as Map<String, Object?>;
      expect((records['User']! as List<Object?>), hasLength(1));
      expect((records['Order']! as List<Object?>), hasLength(1));
      expect(await rows('users'), hasLength(2), reason: 'an export changes nothing');
    });

    test('with no path named, nothing is written', () async {
      await seed();
      await expectLater(
        run(<String>['export', '--subject', 'user:1042']),
        throwsA(isA<UsageException>()),
      );
    });

    test('an existing file is not replaced without --force', () async {
      await seed();
      final File out = File(p.join(project.path, 'ada.json'))
        ..writeAsStringSync('earlier');
      final _Run r = await run(
          <String>['export', '--subject', 'user:1042', '--out', out.path]);
      expect(r.exitCode, 1);
      expect(out.readAsStringSync(), 'earlier');
    });
  });

  group('retention', () {
    test('--plan says what the next sweep would do, and changes nothing',
        () async {
      await seed();
      final List<int> before = File(dbPath).readAsBytesSync();
      final List<Map<String, Object?>> ordersBefore = await rows('orders');
      final List<Map<String, Object?>> visitsBefore = await rows('visits');
      final _Run r = await run(<String>['retention', '--plan']);
      expect(r.exitCode, anyOf(isNull, 0), reason: r.text);
      // A plain 30-day retention deletes; a 30-day anonymization on a row a
      // law keeps for seven years is held, and the plan must say so rather
      // than promise a change the sweep will not make (DV-PRIVACY-008).
      expect(r.text, contains('Visit: would delete 1'));
      expect(r.text, contains('Order: 1 expired and held'));
      expect(r.text, contains('DV-PRIVACY-008'));
      expect(await rows('orders'), ordersBefore);
      expect(await rows('visits'), visitsBefore);
      expect(File(dbPath).readAsBytesSync(), before,
          reason: 'a plan that writes -- even a schema -- is not a plan');
      final SqliteDVDatabaseAdapter db = await database();
      final List<Map<String, Object?>> tables = await db
          .query("SELECT name FROM sqlite_master WHERE type = 'table'");
      db.close();
      expect(tables.map((Map<String, Object?> t) => t['name']).toSet(),
          <String>{'users', 'orders', 'visits'});
    });

    test('without --plan it refuses rather than sweeping', () async {
      await seed();
      await expectLater(
          run(<String>['retention']), throwsA(isA<UsageException>()));
      expect((await rows('orders')).single['cardLast4'], '4242');
    });
  });
}
