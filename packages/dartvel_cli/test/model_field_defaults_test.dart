import 'dart:io';

import 'package:dartvel_cli/src/commands/db_command.dart';
import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:dartvel_core/dartvel.dart' show SqliteDVDatabaseAdapter;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('dv_field_defaults_');
    Directory(p.join(root.path, 'lib/models')).createSync(recursive: true);
    Directory(p.join(root.path, 'lib/dartvel_client'))
        .createSync(recursive: true);
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: defaults_probe
environment:
  sdk: ^3.13.0
dartvel:
  database:
    provider: sqlite
    path: app.db
''');
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<String> generate(String declaration) async {
    File(p.join(root.path, 'lib/models/player.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';
enum Mood { calm, happy }
@DVModel()
$declaration
''');
    await ModelGenerator.generate(root: root.path, pkgName: 'defaults_probe');
    return File(p.join(root.path, 'lib/dartvel_client/models.g.dart'))
        .readAsStringSync();
  }

  const primary = '''class _Player({
required final String id,
final String storyJson = '',
final int score = 7,
final double weight = 1.5,
final bool ready = true,
final DateTime joined = DateTime(2020, 1, 2),
final Mood mood = .happy,
final String quoted = "it's fine",
});''';
  const classic = '''class _Player {
final String id;
final String storyJson;
final int score;
final double weight;
final bool ready;
final DateTime joined;
final Mood mood;
final String quoted = "it's fine";
_Player({required this.id, this.storyJson = '', this.score = 7,
this.weight = 1.5, this.ready = true, DateTime? joined,
this.mood = .happy}) : joined = joined ?? DateTime(2020, 1, 2);
}''';

  // Execute the emitted reader itself with a small model, avoiding Flutter UI
  // dependencies while keeping conversions and fallback expressions untouched.
  Future<ProcessResult> runReader(String source, String checks) async {
    final start = source.indexOf('  static Player _fromRow(');
    expect(start, greaterThanOrEqualTo(0));
    final end = source.indexOf('\n  }', start) + 4;
    final helperStart = source.indexOf('num _dvAsNum(');
    final helperEnd = source.indexOf('/// Generated public model');
    final sqlStart = source.indexOf('  String get createTableSql =>');
    final sqlEnd = source.indexOf('\n', sqlStart);
    final script = File(p.join(root.path, 'reader.dart'));
    // The generated models file imports dart:convert as convert; its helpers
    // (_dvAsJson) rely on that.
    script.writeAsStringSync('''
import 'dart:convert' as convert;
${source.substring(helperStart, helperEnd)}
String dvTenantTable(String table) => table;
class Player({required final String id, required final String storyJson,
required final int score, required final double weight, required final bool ready,
required final DateTime joined, required final Mood mood, required final String quoted}) {
${source.substring(start, end)}
${source.substring(sqlStart, sqlEnd)}
}
void main() { $checks }
''');
    return Process.run(Platform.resolvedExecutable, [script.path]);
  }

  for (final shape in ['primary', 'classic', 'classic positional']) {
    test(
      '$shape declared defaults read missing and null legacy fields',
      () async {
        // Classic DateTime uses a field initializer rather than an optional
        // constructor expression, both supported declaration styles.
        var declaration = shape == 'primary'
            ? primary
            : classic
                  .replaceAll(
                    'final DateTime joined;',
                    'final DateTime joined = DateTime(2020, 1, 2);',
                  )
                  .replaceAll(', DateTime? joined', '')
                  .replaceAll(' : joined = joined ?? DateTime(2020, 1, 2)', '');
        if (shape == 'classic positional') {
          declaration = declaration.replaceAll(
            '_Player({required this.id,', '_Player(this.id, {');
        }
        final source = await generate(declaration);
        final result = await runReader(source, '''
for (final row in <Map<String, Object?>>[{'id': 'old'}, {'id': 'old', 'storyJson': null, 'score': null, 'ready': null}]) {
final player = Player._fromRow(row);
if (player.storyJson != '' || player.score != 7 || player.weight != 1.5 || !player.ready || player.joined != DateTime(2020, 1, 2) || player.mood != Mood.happy || player.quoted != "it's fine") throw StateError('wrong defaults');
}
final player = Player._fromRow({'id': 'new', 'storyJson': 'story', 'score': '0', 'weight': '0.0', 'ready': '0', 'joined': '2021-01-01', 'mood': 'calm', 'quoted': ''});
if (player.storyJson != 'story' || player.score != 0 || player.weight != 0 || player.ready || player.mood != Mood.calm || player.quoted != '') throw StateError('overwrote values');
''');
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
      },
    );
  }

  test('missing required field names model, field and record id', () async {
    final source = await generate(
      primary.replaceAll(
        "final String storyJson = ''",
        'required final String storyJson',
      ),
    );
    final result = await runReader(source, '''
try { Player._fromRow({'id': 'legacy-12'}); throw StateError('accepted missing field'); }
catch (error) {
final message = error.toString();
if (!message.contains('Player') || !message.contains('storyJson') || !message.contains('legacy-12')) rethrow;
}
''');
    expect(result.exitCode, 0, reason: '${result.stderr}');
  });

  test('document engines can return DateTime and enum objects', () async {
    final source = await generate(primary);
    final result = await runReader(source, '''
final player = Player._fromRow({'id': 'document', 'joined': DateTime(2021), 'mood': Mood.calm});
if (player.joined != DateTime(2021) || player.mood != Mood.calm) throw StateError('wrong document values');
''');
    expect(result.exitCode, 0, reason: '${result.stderr}');
  });

  test('comments on declared defaults preserve reads and SQL backfill', () async {
    final db = SqliteDVDatabaseAdapter.file(p.join(root.path, 'app.db'));
    addTearDown(db.close);
    await db.execute('CREATE TABLE players (id TEXT)');
    await db.execute("INSERT INTO players VALUES ('old')");
    final source = await generate(primary
        .replaceAll("storyJson = ''", "storyJson = '' // old records\n")
        .replaceAll('score = 7', 'score = /* initial score */ 7'));
    final result = await runReader(source, "Player._fromRow({'id': 'old'});");
    expect(result.exitCode, 0, reason: '${result.stderr}');
    await dvApplyMigrations(root.path);
    final rows = await db.query('SELECT * FROM players');
    expect(rows.single['storyJson'], '');
    expect(rows.single['score'].toString(), '7');
  });

  test('an encrypted initialized field never backfills plaintext', () async {
    final db = SqliteDVDatabaseAdapter.file(p.join(root.path, 'app.db'));
    addTearDown(db.close);
    await db.execute('CREATE TABLE players (id TEXT)');
    await db.execute("INSERT INTO players VALUES ('old')");
    await generate('''class _Player {
final String id;
@DVModel.sensitiveField(encrypted: true)
final String secret = 'private';
_Player({required this.id});
}''');
    await dvApplyMigrations(root.path);
    final rows = await db.query('SELECT * FROM players');
    expect(
      rows.single['secret'],
      isNull,
      reason: 'an encrypted column must not contain a plaintext SQL default',
    );
  });

  test('migration backfills SQL literals in existing rows', () async {
    final db = SqliteDVDatabaseAdapter.file(p.join(root.path, 'app.db'));
    await db.execute('CREATE TABLE players (id TEXT)');
    await db.execute("INSERT INTO players VALUES ('old')");
    await generate(primary);
    await dvApplyMigrations(root.path);
    final rows = await db.query('SELECT * FROM players');
    expect(rows.single['storyJson'], '');
    expect(rows.single['score'].toString(), '7');
    expect(rows.single['ready'].toString(), '1');
    expect(rows.single['quoted'], "it's fine");
    final columns = await db.query('PRAGMA table_info(players)');
    expect(
      columns.singleWhere((c) => c['name'] == 'storyJson')['dflt_value'],
      "''",
    );
    db.close();
  });
}
