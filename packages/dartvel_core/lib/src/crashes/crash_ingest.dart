/// The Dartvel backend sink: reports sent to the deployment's own backend,
/// and what that backend does with them.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../database/adapter.dart';
import '../observability/logging.dart';
import 'crash_report.dart';
import 'crash_reporting.dart';

/// Where the backend keeps the reports it accepts.
abstract class DVCrashReportRepository {
  /// Keeps [report], and returns false when a report with its id is already
  /// kept: a client that died between sending and noting the send sends it
  /// again, and that is one crash, not two.
  Future<bool> put(DVCrashReport report, {required DateTime receivedAt});
}

/// Reports in memory, for tests.
class DVMemoryCrashReportRepository implements DVCrashReportRepository {
  final List<DVCrashReport> stored = <DVCrashReport>[];

  @override
  Future<bool> put(DVCrashReport report, {required DateTime receivedAt}) async {
    if (stored.any((DVCrashReport kept) => kept.id == report.id)) return false;
    stored.add(report);
    return true;
  }
}

/// Reports in the application's database, in [table].
class DVDatabaseCrashReportRepository implements DVCrashReportRepository {
  DVDatabaseCrashReportRepository(this.database);

  /// The application's `DV.Database`, asked on every call.
  ///
  /// What the generated backend uses. Resolved per call rather than once,
  /// because a backend with no database configured must answer a report with
  /// 503 from inside the store -- where the failure is caught and the payload
  /// kept out of the log -- rather than throwing when the endpoint is built.
  DVDatabaseCrashReportRepository.application()
      : database = const _ApplicationDatabase();

  static const String table = 'dv_crash_reports';

  final DVDatabaseAdapter database;
  bool _schema = false;

  Future<void> ensureSchema() async {
    if (_schema) return;
    // app_release rather than release, which MySQL reserves.
    await database.execute(
      'CREATE TABLE IF NOT EXISTS $table ('
      'id VARCHAR(128) PRIMARY KEY, '
      'install_id VARCHAR(128) NOT NULL, '
      'app_release VARCHAR(128) NOT NULL, '
      'kind VARCHAR(16) NOT NULL, '
      'fingerprint VARCHAR(64) NOT NULL, '
      'occurred_at VARCHAR(40) NOT NULL, '
      'received_at VARCHAR(40) NOT NULL, '
      'report TEXT NOT NULL)',
    );
    _schema = true;
  }

  @override
  Future<bool> put(DVCrashReport report, {required DateTime receivedAt}) async {
    await ensureSchema();
    final List<Map<String, Object?>> existing = await database.query(
      'SELECT id FROM $table WHERE id = ?',
      <Object?>[report.id],
    );
    if (existing.isNotEmpty) return false;
    await database.execute(
      'INSERT INTO $table (id, install_id, app_release, kind, fingerprint, '
      'occurred_at, received_at, report) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        report.id,
        report.context.installId,
        report.context.release,
        report.kind.name,
        report.fingerprint,
        report.occurredAt.toUtc().toIso8601String(),
        receivedAt.toUtc().toIso8601String(),
        jsonEncode(report.toJson()),
      ],
    );
    return true;
  }
}

class _ApplicationDatabase implements DVDatabaseAdapter {
  const _ApplicationDatabase();

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?>? params,
  ]) =>
      const DVDatabase().query(sql, params);

  @override
  Future<int> execute(String sql, [List<Object?>? params]) =>
      const DVDatabase().execute(sql, params);
}

/// What became of a report the backend was sent.
enum DVCrashIngestOutcome {
  stored,
  duplicate,

  /// Counted and not stored: the install is past its hourly budget.
  limited,
  invalid,
  tooLarge,

  /// The store failed; the client keeps the report and sends it again.
  unavailable,
}

/// The answer to one report.
final class DVCrashIngestResult {
  const DVCrashIngestResult(this.outcome);

  final DVCrashIngestOutcome outcome;

  /// 2xx for every outcome the client should stop sending, 4xx for a report
  /// that will never be accepted, 5xx for one worth sending again.
  int get status => switch (outcome) {
        DVCrashIngestOutcome.stored => 201,
        DVCrashIngestOutcome.duplicate => 200,
        DVCrashIngestOutcome.limited => 202,
        DVCrashIngestOutcome.invalid => 400,
        DVCrashIngestOutcome.tooLarge => 413,
        DVCrashIngestOutcome.unavailable => 503,
      };

  /// Fixed text chosen here. Nothing from the request is ever in it.
  String get message => switch (outcome) {
        DVCrashIngestOutcome.stored => 'stored',
        DVCrashIngestOutcome.duplicate => 'already stored',
        DVCrashIngestOutcome.limited =>
          'counted: this install is past its crash reports for the hour',
        DVCrashIngestOutcome.invalid => 'not a crash report',
        DVCrashIngestOutcome.tooLarge => 'larger than a crash report may be',
        DVCrashIngestOutcome.unavailable =>
          'the report could not be stored; send it again later',
      };

  Map<String, Object?> toJson() => <String, Object?>{
        'outcome': outcome.name,
        'stored': outcome == DVCrashIngestOutcome.stored,
        'message': message,
      };
}

/// The backend's side of `sink: dartvel`: accepts a report, validates it,
/// limits it per install, and stores it.
///
/// Nothing a report carries is ever logged or answered, including when it is
/// refused or cannot be stored. A report's message is whatever the error said,
/// and a database error quotes the values it could not insert, so the store's
/// error is logged by its type alone.
class DVCrashIngest {
  DVCrashIngest({
    required this.repository,
    this.perInstallPerHour = 30,
    this.maxBytes = 262144,
    DateTime Function()? clock,
    void Function(String line)? log,
  })  : _clock = clock ?? DateTime.now,
        _log = log ?? _defaultLog;

  /// Where the generated backend serves it, under the API base path.
  static const String path = '/_dartvel/crashes';

  static const int _maxIdLength = 128;
  static const Duration _window = Duration(hours: 1);

  final DVCrashReportRepository repository;

  /// Reports stored per install per hour; past it they are counted.
  final int perInstallPerHour;

  /// The largest body accepted.
  final int maxBytes;

  final DateTime Function() _clock;
  final void Function(String line) _log;

  final Map<String, ListQueue<(DateTime, String)>> _recent =
      <String, ListQueue<(DateTime, String)>>{};
  final Map<String, int> _limited = <String, int>{};
  final Map<String, DateTime> _limitReported = <String, DateTime>{};

  static final DVLogger _logger = DVLogger();

  static void _defaultLog(String line) =>
      _logger.log(line, level: DVLogLevel.warn);

  /// How many of [installId]'s reports were counted rather than stored.
  int limited(String installId) => _limited[installId] ?? 0;

  Future<DVCrashIngestResult> accept(List<int> body) async {
    if (body.length > maxBytes) {
      return const DVCrashIngestResult(DVCrashIngestOutcome.tooLarge);
    }
    final DVCrashReport report;
    try {
      final Object? json = jsonDecode(utf8.decode(body));
      if (json is! Map<String, Object?>) {
        return const DVCrashIngestResult(DVCrashIngestOutcome.invalid);
      }
      report = DVCrashReport.fromJson(json);
    } on Object {
      return const DVCrashIngestResult(DVCrashIngestOutcome.invalid);
    }
    final String installId = report.context.installId;
    if (!_usable(report.id) ||
        !_usable(installId) ||
        !_usable(report.context.release)) {
      return const DVCrashIngestResult(DVCrashIngestOutcome.invalid);
    }

    final DateTime now = _clock();
    _sweep(now);
    final ListQueue<(DateTime, String)> recent =
        _recent.putIfAbsent(installId, ListQueue<(DateTime, String)>.new);
    while (recent.isNotEmpty && now.difference(recent.first.$1) >= _window) {
      recent.removeFirst();
    }
    // A resend of one already stored this hour is the same crash, and does
    // not spend the budget.
    if (recent.any(((DateTime, String) entry) => entry.$2 == report.id)) {
      return const DVCrashIngestResult(DVCrashIngestOutcome.duplicate);
    }
    if (recent.length >= perInstallPerHour) {
      _limited[installId] = limited(installId) + 1;
      final DateTime? reported = _limitReported[installId];
      if (reported == null || now.difference(reported) >= _window) {
        _limitReported[installId] = now;
        // Not which install: the id is the report's, and nothing of a report
        // is logged.
        _log('DV-CRASH-004: an install is past $perInstallPerHour crash '
            'reports this hour; further reports from it are counted, not '
            'stored');
      }
      return const DVCrashIngestResult(DVCrashIngestOutcome.limited);
    }

    final bool kept;
    try {
      kept = await repository.put(report, receivedAt: now);
    } on Object catch (error) {
      _log('a crash report could not be stored (${error.runtimeType}); the '
          'client keeps it and sends it again');
      return const DVCrashIngestResult(DVCrashIngestOutcome.unavailable);
    }
    if (!kept) {
      return const DVCrashIngestResult(DVCrashIngestOutcome.duplicate);
    }
    recent.add((now, report.id));
    return const DVCrashIngestResult(DVCrashIngestOutcome.stored);
  }

  static bool _usable(String value) =>
      value.trim().isNotEmpty && value.length <= _maxIdLength;

  int _accepted = 0;

  /// Forgets installs with nothing in the window, now and then, so a
  /// backend that has heard from a million devices does not remember them.
  void _sweep(DateTime now) {
    if (++_accepted % 1024 != 0) return;
    _recent.removeWhere((String _, ListQueue<(DateTime, String)> recent) =>
        recent.isEmpty || now.difference(recent.last.$1) >= _window);
    _limitReported.removeWhere(
        (String _, DateTime at) => now.difference(at) >= _window);
  }
}

/// `DVCrashSink.dartvel`: reports posted to the deployment's own backend.
class DVDartvelCrashSink implements DVCrashSink {
  DVDartvelCrashSink({
    required this.endpoint,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
    void Function(String line)? log,
  })  : _client = client,
        _log = log ?? DVCrashIngest._defaultLog;

  /// Read at send time, so the runtime's base URL is the one in force.
  final Uri Function() endpoint;
  final Duration timeout;
  final http.Client? _client;
  final void Function(String line) _log;

  /// Returns when the backend has the report or has refused it for good, and
  /// throws otherwise, which leaves the record for the next launch.
  ///
  /// A refusal (400, 413, 422) is final: the backend will never accept that
  /// report, and throwing would send it again on every launch forever. A 404
  /// is not, since a backend deployed before its crash endpoint is the usual
  /// reason for one.
  @override
  Future<void> send(DVCrashReport report) async {
    final http.Client client = _client ?? http.Client();
    try {
      final http.Response response = await client
          .post(
            endpoint(),
            headers: const <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(report.toJson()),
          )
          .timeout(timeout);
      final int status = response.statusCode;
      if (status >= 200 && status < 300) return;
      if (status == 400 || status == 413 || status == 422) {
        _log('the crash backend refused report ${report.id} ($status); it '
            'is not sent again');
        return;
      }
      throw StateError('the crash backend answered $status');
    } finally {
      if (_client == null) client.close();
    }
  }
}
