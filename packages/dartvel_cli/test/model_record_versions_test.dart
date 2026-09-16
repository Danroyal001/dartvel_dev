// A generated model's rows, erased.
//
// Erasure, retention sweeps, change capture, record history and a generated
// form's save all write a row only at the version they read. Generated
// models used to persist with a delete and an insert and no version at all,
// so their tables had no _dv_version column and `dartvel privacy erase`
// refused every real application; only tables made by hand through
// DVRecordTable could be erased.
//
// So this does what an application does, end to end. It generates a project
// whose models declare subject paths, with a table left over from before the
// version column existed and rows already in it. It migrates that table with
// `dartvel db migrate`'s own code, then creates, updates and deletes records
// through the generated API under `flutter test` against the same SQLite
// file. Last, it erases a subject through `dartvel privacy erase` and reads
// the database afterwards.
//
// The silent failures it is here for: rows migrated with a NULL version that
// no conditional write matches; a generated update that does not move the
// version, so a stale save succeeds; history not recording a generated write,
// or surviving its erasure; and an update landing between an erasure's read
// and its write being erased from the stale read.
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/db_command.dart';
import 'package:dartvel_cli/src/commands/privacy_command.dart';
import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:dartvel_core/dartvel.dart'
    show DVRecordTable, SqliteDVDatabaseAdapter;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _page = '''
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Home')
@pragma('vm:entry-point')
Widget _indexPage(BuildContext context) => const DVText('Home');
''';

const String _user = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel(subject: DVSubject.self, retain: DVRetention.indefinite)
@pragma('vm:entry-point')
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

@DVModel(subject: #userId, retain: DVRetention.indefinite, history: DVHistory(keep: Duration(days: 365)))
@pragma('vm:entry-point')
class _Order {
  final String id;
  final String userId;
  final String note;
  const _Order({required this.id, required this.userId, required this.note});
}
''';

/// Runs inside the generated project, against the SQLite file the outer test
/// migrated and later erases.
const String _writes = r'''
import 'dart:async';

import 'package:model_versions_probe/dartvel_client/dartvel_client.dart';
import 'package:model_versions_probe/dartvel_client/privacy.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final String dbPath = const String.fromEnvironment('DB');

/// Holds the first statement [hold] matches until the test lets it go.
class Pausing implements DVDatabaseAdapter {
  Pausing(this.inner);
  final DVDatabaseAdapter inner;
  bool Function(String sql, List<Object?> params)? hold;
  final Completer<void> reached = Completer<void>();
  final Completer<void> proceed = Completer<void>();

  @override
  Future<List<Map<String, Object?>>> query(String sql, [List<Object?>? params]) =>
      inner.query(sql, params);

  @override
  Future<int> execute(String sql, [List<Object?>? params]) async {
    final matcher = hold;
    if (matcher != null && matcher(sql, params ?? const <Object?>[])) {
      hold = null;
      reached.complete();
      await proceed.future;
    }
    return inner.execute(sql, params);
  }
}

Future<int> version(SqliteDVDatabaseAdapter db, String table, String id) async =>
    ((await db.query('SELECT _dv_version FROM $table WHERE id = ?', <Object?>[id]))
            .single['_dv_version']! as num)
        .toInt();

void main() {
  late SqliteDVDatabaseAdapter db;

  setUp(() {
    db = SqliteDVDatabaseAdapter.file(dbPath);
    DV.Database.configure(db);
  });

  tearDown(() async {
    await DVModelSync.reset();
    db.close();
  });

  test('a row from before the version column is updated at version one', () async {
    final User? old = await User.find('legacy');
    expect(old, isNotNull);
    expect(await version(db, 'users', 'legacy'), 1);
    await old!.copyWith(email: 'legacy@example.org').save();
    expect(await version(db, 'users', 'legacy'), 2);
    expect((await User.find('legacy'))!.email, 'legacy@example.org');
  });

  test('every generated write moves the version, and a stale save is refused', () async {
    await const User(id: '1042', email: 'ada@example.com', nationalId: 'X-1').save();
    await const User(id: '7', email: 'bob@example.com', nationalId: 'X-2').save();
    await const Order(id: 'o1', userId: '1042', note: 'first').save();
    expect(await version(db, 'orders', 'o1'), 1);

    final Order read = (await Order.find('o1'))!;
    final Order alsoRead = (await Order.find('o1'))!;
    final Order second = read.copyWith(note: 'second');
    await second.save();
    expect(await version(db, 'orders', 'o1'), 2);
    // `read` itself still holds version one: saving another copy of it is
    // the same lost update as saving alsoRead.
    await expectLater(
      read.copyWith(note: 'also stale').save(),
      throwsA(isA<DVConflictError>()),
    );

    await expectLater(
      alsoRead.copyWith(note: 'lost update').save(),
      throwsA(isA<DVConflictError>()),
    );
    expect((await Order.find('o1'))!.note, 'second');
    await expectLater(Order.destroy(alsoRead), throwsA(isA<DVConflictError>()));
    expect(await Order.find('o1'), isNotNull);

    // The model that did the write holds the version it wrote, so it, and a
    // copy of it, can save again.
    await second.copyWith(note: 'third').save();
    expect(await version(db, 'orders', 'o1'), 3);

    await const Order(id: 'o2', userId: '1042', note: 'second order').save();
    await const Order(id: 'o3', userId: '7', note: "bob's").save();
  });

  test('a model built by hand is refused over a stored row, and the row is kept', () async {
    await const Order(id: 'desk', userId: '7', note: 'as stored').save();
    final int before = await version(db, 'orders', 'desk');

    // Two writers. One reads the order; the other builds one by hand with
    // the same id, having read nothing.
    final Order reader = (await Order.find('desk'))!;
    const Order handBuilt = Order(id: 'desk', userId: '7', note: 'blind write');

    DVConflictError? refused;
    try {
      await handBuilt.save();
    } on DVConflictError catch (error) {
      refused = error;
    }
    expect(refused, isNotNull, reason: 'a write that read nothing replaced the row');
    expect(refused!.code, 'DV-HISTORY-001');
    expect(refused.base, isNull);
    expect(refused.expectedVersion, isNull);
    expect(refused.theirs['note'], 'as stored');
    expect((await Order.find('desk'))!.note, 'as stored');
    expect(await version(db, 'orders', 'desk'), before);

    // The writer who read is not affected by the refused one.
    await reader.copyWith(note: 'edited after reading').save();
    expect((await Order.find('desk'))!.note, 'edited after reading');

    // Replacing without reading is a decision, and says so at the call.
    await const Order(id: 'desk', userId: '7', note: 'replaced on purpose')
        .save(onConflict: DVConflict.lastWriteWins);
    expect((await Order.find('desk'))!.note, 'replaced on purpose');
  });

  test('a model the writer created saves again at the version it wrote', () async {
    final Order created = Order(id: 'fresh', userId: '7', note: 'new');
    await created.save();
    await created.copyWith(note: 'then edited').save();
    expect((await Order.find('fresh'))!.note, 'then edited');
  });

  testWidgets('an edit made in the generated form saves at the version it read', (WidgetTester tester) async {
    final Order loaded = (await tester.runAsync<Order?>(() async {
      await const Order(id: 'formed', userId: '7', note: 'before').save();
      return Order.find('formed');
    }))!;
    registerDartvelModels();
    Order? edited;
    await tester.pumpWidget(MaterialApp(
      home: Material(child: Order.Form(loaded, (Order o) => edited = o)),
    ));
    await tester.pumpAndSettle();
    // Fields follow the serialized map: id, userId, note.
    await tester.enterText(find.byType(EditableText).at(2), 'typed in a form');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(edited, isNotNull);

    await tester.runAsync(() => edited!.save());
    final Order? stored = await tester.runAsync<Order?>(() => Order.find('formed'));
    expect(stored!.note, 'typed in a form');

    // The same form over a record that moved underneath it is refused.
    Object? error;
    await tester.runAsync(() async {
      try {
        await loaded.copyWith(note: 'stale').save();
      } catch (e) {
        error = e;
      }
    });
    expect(error, isA<DVConflictError>());
  });

  test('history records the generated writes', () async {
    final Order order = (await Order.find('o1'))!;
    final List<DVHistoryEntry> log = await order.history();
    expect(log.map((DVHistoryEntry e) => e.version), <int>[1, 2, 3]);
    expect(log.last.changes['note']!.to, 'third');
  });

  test('an order moved to someone else between the walk and its write is not erased', () async {
    await const User(id: '55', email: 'cy@example.com', nationalId: 'X-3').save();
    await const Order(id: 'moving', userId: '55', note: 'cy').save();

    final Pausing paused = Pausing(db);
    paused.hold = (String sql, List<Object?> params) =>
        RegExp(r'^(DELETE FROM|UPDATE) orders ').hasMatch(sql) && params.contains('moving');
    final DVPrivacy privacy = DVPrivacy(
      models: dartvelPrivacyModels(paused),
      database: paused,
      signingKey: List<int>.filled(32, 7),
    );
    await privacy.ensureSchema();

    final Future<DVErasureResult> erasing = privacy.erase(subject: '55', reason: 'test');
    await paused.reached.future;
    // The walk has read the order as cy's. Before its write lands, the order
    // is handed to bob through the generated API.
    final Order mine = (await Order.find('moving'))!;
    await mine.copyWith(userId: '7', note: "bob's now").save();
    paused.proceed.complete();
    await erasing;

    final Order? after = await Order.find('moving');
    expect(after, isNotNull, reason: "bob's order was erased from a stale read");
    expect(after!.note, "bob's now");
    expect(after.userId, '7');
    expect(await User.find('55'), isNull, reason: 'the erasure did run');
  });
}
''';

final String _key = List<String>.filled(32, 'a7').join();

void main() {
  late Directory project;
  late String dbPath;
  late ProcessResult writes;
  late List<String> eraseOutput;
  int? eraseExit;

  setUpAll(() async {
    final Uri core =
        (await Isolate.resolvePackageUri(Uri.parse('package:dartvel_core/')))!;
    final String root = p.normalize(p.join(p.fromUri(core), '..', '..', '..'));
    project = Directory.systemTemp.createTempSync('dv_model_versions_');
    dbPath = p.join(project.path, 'app.db');

    void write(String path, String content) => File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);

    write(p.join(project.path, 'lib', 'pages', 'index.page.dart'), _page);
    write(p.join(project.path, 'lib', 'models', 'user.dart'), _user);
    write(p.join(project.path, 'lib', 'models', 'order.dart'), _order);
    write(p.join(project.path, 'test', 'writes_test.dart'), _writes);
    write(p.join(project.path, 'pubspec.yaml'), '''
name: model_versions_probe
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  flutter:
    sdk: flutter
  dartvel_core:
    path: ${p.join(root, 'packages', 'dartvel_core')}
  dartvel_flutter:
    path: ${p.join(root, 'packages', 'dartvel_flutter')}
dev_dependencies:
  flutter_test:
    sdk: flutter
dartvel:
  prodBackendHost: https://example.com
  database:
    provider: sqlite
    path: app.db
''');
    write(p.join(project.path, 'pubspec_overrides.yaml'), '''
dependency_overrides:
  dartvel_core:
    path: ${p.join(root, 'packages', 'dartvel_core')}
  dartvel_flutter:
    path: ${p.join(root, 'packages', 'dartvel_flutter')}
  dartvel_shelf:
    path: ${p.join(root, 'packages', 'dartvel_shelf')}
''');

    // The users table as the generator made it before generated models
    // carried a version, with a row already in it.
    final SqliteDVDatabaseAdapter old = SqliteDVDatabaseAdapter.file(dbPath);
    await old.execute(
        'CREATE TABLE users (id TEXT, email TEXT, nationalId TEXT)');
    await old.execute(
        "INSERT INTO users VALUES ('legacy', 'old@example.com', 'X-0')");
    old.close();

    await routes.generate(root_: project.path);
    await dvApplyMigrations(project.path);

    final ProcessResult resolved = await Process.run(
        'flutter', <String>['pub', 'get'],
        workingDirectory: project.path);
    if (resolved.exitCode != 0) {
      throw StateError('flutter pub get failed:\n${resolved.stderr}');
    }
    writes = await Process.run(
      'flutter',
      <String>[
        'test',
        '--reporter',
        'json',
        '--dart-define=DB=$dbPath',
        'test/writes_test.dart',
      ],
      workingDirectory: project.path,
    );

    eraseOutput = <String>[];
    await (CommandRunner<void>('dartvel', 'test')
          ..addCommand(PrivacyCommand(
            root: project.path,
            environment: <String, String>{'DARTVEL_PRIVACY_KEY': _key},
            interactive: false,
            readLine: () => null,
            out: eraseOutput.add,
            setExitCode: (int c) => eraseExit = c,
          )))
        .run(<String>[
      'privacy',
      'erase',
      '--subject',
      'user:1042',
      '--reason',
      'DSAR 17',
      '--yes',
    ]);
  });

  tearDownAll(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  Future<List<Map<String, Object?>>> rows(String sql) async {
    final SqliteDVDatabaseAdapter db = SqliteDVDatabaseAdapter.file(dbPath);
    try {
      return await db.query(sql);
    } finally {
      db.close();
    }
  }

  test('the generated API ran against the migrated tables as declared', () {
    final String output = '${writes.stdout}\n${writes.stderr}';
    final Map<int, String> names = <int, String>{};
    final Map<String, String> results = <String, String>{};
    bool? success;
    for (final String line in const LineSplitter().convert('${writes.stdout}')) {
      if (!line.startsWith('{')) continue;
      final Object? decoded = jsonDecode(line);
      if (decoded is! Map) continue;
      switch (decoded['type']) {
        case 'testStart':
          final Map<Object?, Object?> t =
              decoded['test']! as Map<Object?, Object?>;
          names[t['id']! as int] = '${t['name']}';
        case 'testDone':
          if (decoded['hidden'] == true) continue;
          final String? name = names[decoded['testID']];
          if (name != null) {
            results[name] =
                decoded['skipped'] == true ? 'skipped' : '${decoded['result']}';
          }
        case 'done':
          success = decoded['success'] == true;
      }
    }
    expect(results, <String, String>{
      'a row from before the version column is updated at version one':
          'success',
      'every generated write moves the version, and a stale save is refused':
          'success',
      'a model built by hand is refused over a stored row, and the row is kept':
          'success',
      'a model the writer created saves again at the version it wrote':
          'success',
      'an edit made in the generated form saves at the version it read':
          'success',
      'history records the generated writes': 'success',
      'an order moved to someone else between the walk and its write is not '
          'erased': 'success',
    }, reason: output);
    expect(success, isTrue, reason: output);
  });

  test('dartvel privacy erase erases the subject from the generated tables',
      () async {
    final String printed = eraseOutput.join('\n');
    expect(eraseExit, isNot(1), reason: printed);
    expect(printed, isNot(contains('_dv_version')), reason: printed);

    // Ada's row is gone: nothing about her is held by law.
    expect(await rows("SELECT * FROM users WHERE id = '1042'"), isEmpty);

    // Ada's orders are gone, and so is every value their history held.
    expect(await rows("SELECT * FROM orders WHERE userId = '1042'"), isEmpty);
    expect(await rows("SELECT * FROM orders WHERE id IN ('o1', 'o2')"),
        isEmpty);
    expect(
      await rows("SELECT * FROM orders__history WHERE record_key IN ('o1', 'o2')"),
      isEmpty,
      reason: "the log still holds the erased orders' notes",
    );

    // Nobody else's.
    expect(await rows("SELECT * FROM orders WHERE id = 'o3'"), hasLength(1));
    final Map<String, Object?> bob =
        (await rows("SELECT * FROM users WHERE id = '7'")).single;
    expect(bob['nationalId'], 'X-2');
    expect(
      (await rows("SELECT ${DVRecordTable.versionColumn} AS v FROM users "
              "WHERE id = 'legacy'"))
          .single['v'],
      2,
    );
  });
}
