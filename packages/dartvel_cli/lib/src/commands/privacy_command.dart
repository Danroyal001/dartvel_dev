import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:args/command_runner.dart';
import 'package:dartvel_core/dartvel.dart'
    show
        DVAnalyticsRuntime,
        DVAnalyticsSettings,
        DVDatabaseAdapter,
        DVDatabaseConnection,
        DVDatabaseEngine,
        DVErasureResult,
        DVExportArchive,
        DVKeptRecord,
        DVPrivacy,
        DVPrivacyAdapter,
        DVPrivacyFinding,
        DVPrivacyDeclarationError,
        DVPrivacyRuntime,
        DVRetentionPlan,
        DVSubject,
        SqliteDVDatabaseAdapter,
        dvPrivacyKeyFrom;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../generators/analytics_generator.dart';
import '../generators/privacy_declarations.dart';
import '../utils/logger.dart';
import '../utils/toolchain.dart' show isCiEnvironment;
import 'db_command.dart' show dvDatabaseSettings;

/// `dartvel privacy`: the model graph's subject paths and retention, and the
/// export, erasure and retention sweep they drive, run against the
/// application's own database.
///
/// Every subcommand here guards something that looks like success when it
/// goes wrong: an erasure nobody confirmed, one against tables it cannot
/// write at the version it read, an export written where nobody chose, a
/// retention plan that changed what it was describing.
class PrivacyCommand extends Command<void> {
  /// [root] is the project; the working directory when null. The rest are
  /// the process's own when null, and given by tests.
  PrivacyCommand({
    String? root,
    Map<String, String>? environment,
    bool? interactive,
    String? Function()? readLine,
    void Function(String line)? out,
    void Function(int code)? setExitCode,
    DateTime Function()? now,
  }) : _io = _PrivacyIo(
          root: root,
          environment: environment,
          interactive: interactive,
          readLine: readLine,
          out: out,
          setExitCode: setExitCode,
          now: now,
        ) {
    addSubcommand(_PrivacyCheckCommand(_io));
    addSubcommand(_PrivacyExportCommand(_io));
    addSubcommand(_PrivacyEraseCommand(_io));
    addSubcommand(_PrivacyRetentionCommand(_io));
  }

  final _PrivacyIo _io;

  @override
  final String name = 'privacy';

  @override
  final String description =
      'Check subject paths and retention, and export, erase or plan a '
      'retention sweep over the application database.';
}

class _PrivacyIo {
  _PrivacyIo({
    this._root,
    Map<String, String>? environment,
    bool? interactive,
    String? Function()? readLine,
    void Function(String line)? out,
    void Function(int code)? setExitCode,
    DateTime Function()? now,
  })  : environment = environment ?? Platform.environment,
        interactive = interactive ?? stdin.hasTerminal,
        readLine = readLine ?? stdin.readLineSync,
        out = out ?? Logger.log,
        setExitCode = setExitCode ?? ((int code) => exitCode = code),
        now = now ?? (() => DateTime.now().toUtc());

  final String? _root;
  final Map<String, String> environment;
  final bool interactive;
  final String? Function() readLine;
  final void Function(String line) out;
  final void Function(int code) setExitCode;
  final DateTime Function() now;

  String get root => _root ?? Directory.current.path;

  /// Reports [message] and fails the command with nothing done.
  void fail(String message) {
    out(message);
    setExitCode(1);
  }
}

/// A database the command opened, and how to let it go.
class _OpenDatabase {
  _OpenDatabase(this.adapter, this.engine);

  final DVDatabaseAdapter adapter;
  final DVDatabaseEngine engine;

  Future<void> close() async {
    final dynamic a = adapter;
    try {
      await (a.close() as FutureOr<void>);
    } on NoSuchMethodError {
      // An adapter with nothing to close.
    }
  }
}

abstract class _PrivacySubcommand extends Command<void> {
  _PrivacySubcommand(this.io);

  final _PrivacyIo io;

  /// The declarations, or null having said why there are none to use.
  DVPrivacyDeclarations? declarations() {
    try {
      return DVPrivacyDeclarations.discover(root: io.root);
    } on StateError catch (error) {
      io.fail(error.message);
      return null;
    }
  }

  /// The application database: `DATABASE_URL` when set, else the SQLite file
  /// `dartvel.database` names -- one that exists. A path that does not is
  /// refused rather than created: a new empty database would have nothing to
  /// erase and report the erasure complete.
  _OpenDatabase? openDatabase() {
    final DVDatabaseConnection? connection;
    try {
      connection = DVDatabaseConnection.fromEnvironment(io.environment);
    } on Object catch (error) {
      io.fail('DATABASE_URL cannot be read: $error');
      return null;
    }
    if (connection != null) {
      return _OpenDatabase(connection.open(), connection.engine);
    }
    final ({String provider, String path}) settings = dvDatabaseSettings(io.root);
    if (settings.provider != 'sqlite') {
      io.fail('dartvel.database uses ${settings.provider}, and DATABASE_URL is '
          'not set, so there is no connection to it. Set DATABASE_URL.');
      return null;
    }
    final String file = p.isAbsolute(settings.path)
        ? settings.path
        : p.join(io.root, settings.path);
    if (!File(file).existsSync()) {
      io.fail('No database exists at $file. Set DATABASE_URL, or '
          'dartvel.database.path to the application database.');
      return null;
    }
    return _OpenDatabase(
        SqliteDVDatabaseAdapter.file(file), DVDatabaseEngine.sqlite);
  }

  /// The signing key from `DARTVEL_PRIVACY_KEY`, or null having said why.
  List<int>? signingKey() {
    final String? raw =
        io.environment[DVPrivacyRuntime.keyVariable]?.trim();
    if (raw == null || raw.isEmpty) {
      io.fail('${DVPrivacyRuntime.keyVariable} is not set. It signs the '
          'receipt and derives the pseudonym every kept record uses, and it '
          'must be the key the application runs with, so it has no default.');
      return null;
    }
    try {
      return dvPrivacyKeyFrom(raw);
    } on StateError catch (error) {
      io.fail(error.message);
      return null;
    }
  }

  /// The subject `model:id` names, or null having said why.
  ///
  /// The model is the one whose rows are people -- `DVSubject.self` -- and
  /// the id is that row's key.
  ({DVPrivacyModelDeclaration model, String id})? subject(
    DVPrivacyDeclarations declared,
    String raw,
  ) {
    final int colon = raw.indexOf(':');
    if (colon <= 0 || colon == raw.length - 1) {
      usageException('--subject is model:id, such as user:1042.');
    }
    final String name = raw.substring(0, colon).trim().toLowerCase();
    final String id = raw.substring(colon + 1).trim();
    for (final DVPrivacyModelDeclaration m in declared.models) {
      if (m.name.toLowerCase() != name) continue;
      if (!identical(m.subject, DVSubject.self)) {
        io.fail('${m.name} is not a subject: its rows belong to a person '
            'rather than being one. Name the model declared '
            '@DVModel(subject: DVSubject.self).');
        return null;
      }
      return (model: m, id: id);
    }
    final List<String> subjects = <String>[
      for (final DVPrivacyModelDeclaration m in declared.models)
        if (identical(m.subject, DVSubject.self)) m.name.toLowerCase(),
    ];
    io.fail('No model is named $name. Subjects are the models declared '
        '@DVModel(subject: DVSubject.self)'
        '${subjects.isEmpty ? '' : ': ${subjects.join(', ')}'}.');
    return null;
  }

  /// The analytics store's adapters when the project declares analytics, so
  /// an erasure or export reaches events and consent records too.
  Future<List<DVPrivacyAdapter>> analyticsAdapters(DVDatabaseAdapter db) async {
    final File pubspec = File(p.join(io.root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return const <DVPrivacyAdapter>[];
    final Object? doc = loadYaml(pubspec.readAsStringSync());
    final Object? dv = doc is Map ? doc['dartvel'] : null;
    if (dv is! Map) return const <DVPrivacyAdapter>[];
    final DVAnalyticsSettings? settings = AnalyticsGenerator.read(dv);
    if (settings == null) return const <DVPrivacyAdapter>[];
    final DVAnalyticsRuntime runtime =
        DVAnalyticsRuntime.start(settings: settings, database: () => db);
    return (await runtime.pipeline).privacyAdapters();
  }

  /// The tables an erasure would write that it cannot write safely.
  ///
  /// Erasure deletes and anonymizes a row only at the version it read, so a
  /// table with no `_dv_version` column fails at the first write -- after
  /// the rows of an earlier table are already gone. Checked for every table
  /// first, so nothing is erased unless all of it can be.
  Future<List<String>> unwritableTables(
    _OpenDatabase db,
    DVPrivacyDeclarations declared,
  ) async {
    final List<String> problems = <String>[];
    for (final DVPrivacyModelDeclaration m in declared.models) {
      if (m.subject == null) continue;
      final List<Map<String, Object?>> columns = switch (db.engine) {
        DVDatabaseEngine.sqlite =>
          await db.adapter.query('PRAGMA table_info(${m.table})'),
        _ => await db.adapter.query(
            'SELECT column_name AS name FROM information_schema.columns '
            'WHERE table_name = ?',
            <Object?>[m.table]),
      };
      final Set<String> names = <String>{
        for (final Map<String, Object?> c in columns) '${c['name']}',
      };
      if (names.isEmpty) {
        problems.add('${m.table} (${m.name}) does not exist');
      } else if (!names.contains('_dv_version')) {
        problems.add('${m.table} (${m.name}) has no _dv_version column');
      }
    }
    return problems;
  }
}

class _PrivacyCheckCommand extends _PrivacySubcommand {
  _PrivacyCheckCommand(super.io);

  @override
  final String name = 'check';

  @override
  final String description =
      'List every model with its subject path and retention.';

  @override
  Future<void> run() async {
    final DVPrivacyDeclarations? declared = declarations();
    if (declared == null) return;
    final int width = declared.models.fold<int>(
        0, (int w, DVPrivacyModelDeclaration m) => max(w, m.name.length));
    for (final DVPrivacyModelDeclaration m in declared.models) {
      io.out('${m.name.padRight(width)}  '
          'subject: ${m.subjectDescription ?? '-'}  '
          'retention: ${m.retentionDescription ?? '-'}'
          '${m.retainedBecause == null ? '' : '  kept by law: ${m.retainedBecause}'}'
          '  (${m.source})');
    }
    for (final DVPrivacyFinding finding in declared.findings) {
      io.out('$finding');
    }
    if (declared.errors.isNotEmpty) io.setExitCode(1);
  }
}

class _PrivacyExportCommand extends _PrivacySubcommand {
  _PrivacyExportCommand(super.io) {
    argParser
      ..addOption('subject', help: 'The subject, as model:id -- user:1042.')
      ..addOption('out', help: 'Where to write the archive. Required.')
      ..addFlag('force',
          negatable: false, help: 'Replace a file already at --out.');
  }

  @override
  final String name = 'export';

  @override
  final String description =
      "Write a subject's records, as JSON, to the path --out names.";

  @override
  Future<void> run() async {
    final String? rawSubject = argResults!['subject'] as String?;
    final String? outPath = argResults!['out'] as String?;
    if (rawSubject == null) usageException('--subject is required.');
    if (outPath == null) {
      usageException('--out is required: an export is personal data, and '
          'it goes where somebody chose rather than a default.');
    }
    final File target = File(p.isAbsolute(outPath)
        ? outPath
        : p.join(io.root, outPath));
    if (target.existsSync() && !(argResults!['force'] as bool)) {
      io.fail('${target.path} already exists; nothing was written. Pass '
          '--force to replace it.');
      return;
    }
    final DVPrivacyDeclarations? declared = declarations();
    if (declared == null) return;
    final List<int>? key = signingKey();
    if (key == null) return;
    final ({DVPrivacyModelDeclaration model, String id})? who =
        subject(declared, rawSubject);
    if (who == null) return;
    final _OpenDatabase? db = openDatabase();
    if (db == null) return;
    try {
      final DVPrivacy privacy = DVPrivacy(
        models: declared.toPrivacyModels(db.adapter),
        database: db.adapter,
        signingKey: key,
        adapters: await analyticsAdapters(db.adapter),
        now: io.now,
      );
      await privacy.ensureSchema();
      final DVExportArchive archive = await privacy.export(
        subject: who.id,
        runBy: 'dartvel privacy export',
      );
      target.parent.createSync(recursive: true);
      target.writeAsStringSync(archive.toJson());
      io.out('Wrote the export for ${who.model.name} '
          '${privacy.pseudonym(who.id)} to ${target.path}.');
      for (final MapEntry<String, List<Map<String, Object?>>> e
          in archive.records.entries) {
        io.out('  ${e.key}: ${e.value.length}');
      }
      for (final String code in archive.codes.toSet()) {
        io.out('  $code');
      }
      if (archive.unreached.isNotEmpty) {
        io.fail('Incomplete: ${archive.unreached.join(', ')} could not be '
            'reached, so the archive does not hold what they have.');
      }
    } on DVPrivacyDeclarationError catch (error) {
      io.fail('$error');
    } finally {
      await db.close();
    }
  }
}

class _PrivacyEraseCommand extends _PrivacySubcommand {
  _PrivacyEraseCommand(super.io) {
    argParser
      ..addOption('subject', help: 'The subject, as model:id -- user:1042.')
      ..addOption('reason', help: 'Why, as the audit record will say.')
      ..addFlag('yes',
          negatable: false,
          help: 'Erase without asking. Required where nobody can be asked.');
  }

  @override
  final String name = 'erase';

  @override
  final String description =
      "Erase a subject's records: delete them, or keep and anonymize the ones "
      'a declared retention holds.';

  @override
  Future<void> run() async {
    final String? rawSubject = argResults!['subject'] as String?;
    final String? reason = argResults!['reason'] as String?;
    if (rawSubject == null) usageException('--subject is required.');
    if (reason == null || reason.trim().isEmpty) {
      usageException('--reason is required; it is what the audit record '
          'says this erasure was for.');
    }
    final DVPrivacyDeclarations? declared = declarations();
    if (declared == null) return;
    if (declared.errors.isNotEmpty) {
      io.fail('${declared.errors.join('\n')}\nNothing was erased: an erasure '
          'that cannot reach every table would report success anyway.');
      return;
    }
    final List<int>? key = signingKey();
    if (key == null) return;
    final ({DVPrivacyModelDeclaration model, String id})? who =
        subject(declared, rawSubject);
    if (who == null) return;

    // The subject is shown by pseudonym, here and below: this output lands
    // in terminals and in CI logs, and the id is personal data.
    final String pseudonym = DVPrivacy(
      models: const [],
      database: _NoDatabase(),
      signingKey: key,
    ).pseudonym(who.id);
    if (!(argResults!['yes'] as bool)) {
      final bool canAsk = io.interactive && !isCiEnvironment(io.environment);
      if (!canAsk) {
        io.fail('Nothing was erased: nobody can be asked here. Pass --yes to '
            'erase ${who.model.name} $pseudonym unattended.');
        return;
      }
      io.out('This erases every record of ${who.model.name} $pseudonym that '
          'a subject path reaches, and cannot be undone. Type yes to erase:');
      if (io.readLine()?.trim() != 'yes') {
        io.fail('Not confirmed; nothing was erased.');
        return;
      }
    }

    final _OpenDatabase? db = openDatabase();
    if (db == null) return;
    try {
      final List<String> problems = await unwritableTables(db, declared);
      if (problems.isNotEmpty) {
        io.fail('Nothing was erased. An erasure writes each row at the '
            'version it read, and these tables cannot be written that way:\n'
            '${problems.map((String l) => '  $l').join('\n')}\n'
            'Erasing the others first would remove part of the subject and '
            'leave the rest.');
        return;
      }
      final DVPrivacy privacy = DVPrivacy(
        models: declared.toPrivacyModels(db.adapter),
        database: db.adapter,
        signingKey: key,
        adapters: await analyticsAdapters(db.adapter),
        now: io.now,
      );
      await privacy.ensureSchema();
      final DVErasureResult result = await privacy.erase(
        subject: who.id,
        reason: reason,
        runBy: 'dartvel privacy erase',
      );
      io.out('Erased ${who.model.name} $pseudonym.');
      for (final MapEntry<String, int> e in result.deleted.entries) {
        io.out('  ${e.key}: ${e.value} deleted');
      }
      for (final MapEntry<String, int> e in result.anonymized.entries) {
        io.out('  ${e.key}: ${e.value} anonymized');
      }
      for (final DVKeptRecord kept in result.kept) {
        io.out('  kept ${kept.model} ${kept.key}: ${kept.because}');
      }
      for (final String code in result.codes.toSet()) {
        io.out('  $code');
      }
      io.out('  receipt ${result.receipt.signature}');
      if (result.late) io.out('  the erasure ran past its deadline');
      if (!result.complete) {
        io.fail('Incomplete: ${result.unreached.join(', ')} could not be '
            'reached, and the subject\'s data there was not removed.');
      }
    } finally {
      await db.close();
    }
  }
}

class _PrivacyRetentionCommand extends _PrivacySubcommand {
  _PrivacyRetentionCommand(super.io) {
    argParser.addFlag('plan',
        negatable: false,
        help: 'Say what the next sweep would delete or anonymize, changing '
            'nothing.');
  }

  @override
  final String name = 'retention';

  @override
  final String description =
      'Preview the next retention sweep (--plan). Sweeps run as a job.';

  @override
  Future<void> run() async {
    if (!(argResults!['plan'] as bool)) {
      usageException('retention takes --plan. The sweep itself runs as a '
          'durable job in the application, resumable and rate-limited; a '
          'deletion nobody previewed is one nobody can be talked out of.');
    }
    final DVPrivacyDeclarations? declared = declarations();
    if (declared == null) return;
    final _OpenDatabase? db = openDatabase();
    if (db == null) return;
    try {
      // A plan signs nothing and pseudonymizes nothing, so it does not need
      // the application's key; it must not write, so nothing below creates a
      // table.
      final String? raw =
          io.environment[DVPrivacyRuntime.keyVariable]?.trim();
      final List<int> key = raw == null || raw.isEmpty
          ? List<int>.generate(32, (_) => Random.secure().nextInt(256))
          : dvPrivacyKeyFrom(raw);
      final DVPrivacy privacy = DVPrivacy(
        models: declared.toPrivacyModels(db.adapter),
        database: db.adapter,
        signingKey: key,
        now: io.now,
      );
      final DVRetentionPlan plan = await privacy.planRetention(now: io.now());
      if (plan.deletions.isEmpty &&
          plan.anonymizations.isEmpty &&
          plan.held.isEmpty) {
        io.out('The next sweep would change nothing.');
      }
      for (final MapEntry<String, int> e in plan.deletions.entries) {
        io.out('${e.key}: would delete ${e.value}');
      }
      for (final MapEntry<String, int> e in plan.anonymizations.entries) {
        io.out('${e.key}: would anonymize ${e.value}');
      }
      for (final MapEntry<String, int> e in plan.held.entries) {
        io.out('${e.key}: ${e.value} expired and held by a longer retention '
            '(DV-PRIVACY-008)');
      }
    } on DVPrivacyDeclarationError catch (error) {
      io.fail('$error');
    } finally {
      await db.close();
    }
  }
}

/// A database nothing is asked of, for deriving a pseudonym before one is
/// opened.
class _NoDatabase implements DVDatabaseAdapter {
  @override
  Future<int> execute(String sql, [List<Object?>? params]) =>
      throw StateError('no database');

  @override
  Future<List<Map<String, Object?>>> query(String sql,
          [List<Object?>? params]) =>
      throw StateError('no database');
}
