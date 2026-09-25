// `dartvel db pull --local`: model suggestions from a local database schema.
//
// Adoption says `db pull` introspects drift, isar and sqflite schemas and
// suggests model annotations -- printed, never applied. A sensitiveField
// candidate is a judgement about meaning, and a tool that guessed would either
// over-redact or, worse, under-redact silently, so nothing here guesses one.
import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/adoption/local_schema.dart';
import 'package:dartvel_cli/src/commands/db_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _drift = r'''
import 'package:drift/drift.dart';

class Todos extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 80)();
  TextColumn get note => text().nullable()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  DateTimeColumn get dueAt => dateTime().nullable()();
  RealColumn get estimate => real()();
  BlobColumn get attachment => blob().nullable()();
  TextColumn get password => text()();
}

@DataClassName('Person')
class People extends Table {
  IntColumn get id => integer()();
}

// class Ghosts extends Table { IntColumn get id => integer()(); }
''';

const String _isar = r'''
import 'package:isar/isar.dart';

@collection
class Contact {
  Id id = Isar.autoIncrement;
  late String name;
  String? email;
  List<String>? tags;
  @ignore
  String? cached;
  int get initials => 0;
}
''';

const String _sqflite = r"""
import 'package:sqflite/sqflite.dart';

Future<void> onCreate(Database db, int version) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS todo_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      note TEXT,
      done BOOLEAN NOT NULL DEFAULT 0,
      photo BLOB,
      FOREIGN KEY (id) REFERENCES lists(id)
    )
  ''');
}
""";

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('dv_db_pull_local_'));
  tearDown(() => root.deleteSync(recursive: true));

  void write(String rel, String content) {
    File(p.join(root.path, rel))
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  DVLocalTable table(String name) =>
      dvLocalSchemas(root.path).singleWhere((DVLocalTable t) => t.table == name);

  group('drift', () {
    test('columns map to field types, nullability included', () {
      write('lib/db/tables.dart', _drift);

      final String suggestion = dvModelSuggestion(table('Todos'));

      expect(suggestion, contains('@DVModel()'));
      expect(
        suggestion,
        contains('class const _Todo({'),
        reason: 'drift names the row class by dropping the trailing s',
      );
      expect(suggestion, contains('required final int id,'));
      expect(suggestion, contains('required final String title,'));
      expect(suggestion, contains('final String? note,'));
      expect(suggestion, contains('required final bool done,'));
      expect(suggestion, contains('final DateTime? dueAt,'));
      expect(suggestion, contains('required final double estimate,'));
    });

    test('a column with no model type is named, not dropped', () {
      write('lib/db/tables.dart', _drift);

      final DVLocalTable todos = table('Todos');

      expect(dvModelSuggestion(todos), isNot(contains('attachment')));
      expect(todos.unmapped.single, contains('attachment'));
    });

    test('@DataClassName names the model', () {
      write('lib/db/tables.dart', _drift);

      expect(
        dvModelSuggestion(table('People')),
        contains('class const _Person({'),
      );
    });

    test('a commented-out table is not a table', () {
      write('lib/db/tables.dart', _drift);

      final List<String> names =
          dvLocalSchemas(root.path).map((DVLocalTable t) => t.table).toList();
      // The live tables are found, so an empty result cannot pass this.
      expect(names, containsAll(<String>['Todos', 'People']));
      expect(names, isNot(contains('Ghosts')));
    });
  });

  test('isar: a collection\'s fields, without ignored fields or getters', () {
    write('lib/db/contact.dart', _isar);

    final DVLocalTable contact = table('Contact');
    final String suggestion = dvModelSuggestion(contact);

    expect(contact.kind, 'isar');
    expect(suggestion, contains('required final int id,'));
    expect(suggestion, contains('required final String name,'));
    expect(suggestion, contains('final String? email,'));
    expect(suggestion, isNot(contains('cached')));
    expect(suggestion, isNot(contains('initials')));
    expect(contact.unmapped.single, contains('tags'));
  });

  test('sqflite: a CREATE TABLE in a string literal', () {
    write('lib/db/open.dart', _sqflite);

    final DVLocalTable items = table('todo_items');
    final String suggestion = dvModelSuggestion(items);

    expect(items.kind, 'sqflite');
    expect(suggestion, contains('class const _TodoItem({'));
    expect(
      suggestion,
      contains('required final int id,'),
      reason: 'a primary key is not null',
    );
    expect(suggestion, contains('required final String title,'));
    expect(suggestion, contains('final String? note,'));
    expect(suggestion, contains('required final bool done,'));
    expect(suggestion, isNot(contains('FOREIGN')));
    expect(items.unmapped.single, contains('photo'));
  });

  test('never guesses a sensitive field', () {
    write('lib/db/tables.dart', _drift);

    expect(dvModelSuggestion(table('Todos')), isNot(contains('sensitiveField')),
        reason: 'a column named password is still a judgement for a person');
  });

  group('the command', () {
    Future<String> run(List<String> args) async {
      final StringBuffer out = StringBuffer();
      await runZoned(
        () => (CommandRunner<void>('dartvel', 't')
              ..addCommand(DbCommand(root: root.path)))
            .run(<String>['db', ...args]),
        zoneSpecification: ZoneSpecification(
          print: (Zone _, ZoneDelegate __, Zone ___, String line) =>
              out.writeln(line),
        ),
      );
      return out.toString();
    }

    Map<String, String> snapshot() => <String, String>{
          for (final FileSystemEntity e in root.listSync(recursive: true))
            if (e is File) e.path: e.readAsStringSync(),
        };

    test('prints suggestions and writes nothing', () async {
      write('pubspec.yaml', 'name: local_db\n');
      write('lib/db/tables.dart', _drift);
      write('lib/db/open.dart', _sqflite);
      final Map<String, String> before = snapshot();

      final String out = await run(<String>['pull', '--local']);

      expect(out, contains('class const _Todo({'));
      expect(out, contains('class const _TodoItem({'));
      expect(out, contains('lib/db/tables.dart:3'));
      expect(out.toLowerCase(), contains('nothing was written'));
      expect(out, contains('sensitive'),
          reason: 'the reader is told sensitivity was not inferred');
      expect(snapshot(), before);
      expect(Directory(p.join(root.path, '.dart_tool')).existsSync(), isFalse);
    });

    test('says what it looked for when it finds nothing', () async {
      write('pubspec.yaml', 'name: no_db\n');
      write('lib/main.dart', 'void main() {}\n');

      final String out = await run(<String>['pull', '--local']);

      expect(out, contains('drift'));
      expect(out, contains('isar'));
      expect(out, contains('sqflite'));
    });
  });
}
