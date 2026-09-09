// `dartvel logs`, `dartvel traces` and `dartvel metrics`.
//
// These used to print hardcoded sample output -- a fixed trace id, "CPU
// Usage: 1.2%", "Backend server started successfully" -- whether or not
// anything was running. A number that looks like a real measurement and
// isn't is worse than the command not existing, because nothing about it
// looks fake.
//
// All three read a running server now. `metrics` fetches GET /metrics, which
// every Dartvel server answers with its Prometheus registry. `logs` and
// `traces` fetch GET /_dartvel/logs and GET /_dartvel/traces, which serve the
// runtime's recent log records and finished spans as newline-delimited JSON
// (packages/dartvel_core/lib/src/http/router.dart).
//
// Those two endpoints are off unless the server was started with
// DARTVEL_DIAGNOSTICS set, because a log buffer is where a service's most
// sensitive data all sits together. So the case these commands must handle
// well is not "no server" -- it is a perfectly healthy server answering 404,
// where "Not found" alone would send a developer hunting for a routing bug
// that is not there.
//
// Output goes to stdout unprefixed: a scrape target's Prometheus text has to
// stay parseable, and the other two commands should read the same way.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

/// What a fetch came back with.
///
/// A sealed-ish trio rather than exceptions, because each of these ends in a
/// different sentence for the developer and losing the difference is how a
/// command ends up saying "could not connect" to a server it just talked to.
class _Fetched {
  const _Fetched.body(this.body)
      : missing = false,
        failure = null;
  const _Fetched.missing()
      : body = '',
        missing = true,
        failure = null;
  const _Fetched.failure(this.failure)
      : body = '',
        missing = false;

  final String body;

  /// The server answered, and does not have this endpoint.
  final bool missing;

  /// Nothing answered.
  final String? failure;
}

Future<_Fetched> _fetch(Uri target) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request =
        await client.getUrl(target).timeout(const Duration(seconds: 3));
    final HttpClientResponse response =
        await request.close().timeout(const Duration(seconds: 5));
    final String body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 404) return const _Fetched.missing();
    if (response.statusCode != 200) {
      return _Fetched.failure(
        '$target responded with HTTP ${response.statusCode}.',
      );
    }
    return _Fetched.body(body);
  } on Object catch (error) {
    return _Fetched.failure(
      'Could not reach a Dartvel server at $target: $error. Start one with '
      '`dartvel dev`, or pass --url to point at a running instance.',
    );
  } finally {
    client.close(force: true);
  }
}

/// The NDJSON body as records, skipping anything that will not parse.
///
/// A truncated last line is normal when a response is read while the buffer
/// is being written to, and throwing on it would lose every record before it.
List<Map<String, Object?>> _records(String body) {
  final List<Map<String, Object?>> out = <Map<String, Object?>>[];
  for (final String line in body.split('\n')) {
    if (line.trim().isEmpty) continue;
    try {
      final Object? decoded = jsonDecode(line);
      if (decoded is Map<String, Object?>) out.add(decoded);
    } on FormatException {
      continue;
    }
  }
  return out;
}

String _diagnosticsOff(String command) =>
    'The server answered, but it is not serving $command. The diagnostics '
    'endpoints are off unless the server process was started with '
    'DARTVEL_DIAGNOSTICS=1, because a log buffer holds a service\'s most '
    'sensitive data. Restart it with that set -- `dartvel dev` does it for '
    'you -- and run this again.';

/// The shared plumbing: `--url`, `--limit`, `--json`.
abstract class _DiagnosticsCommand extends Command<void> {
  _DiagnosticsCommand() {
    argParser
      ..addOption(
        'url',
        defaultsTo: 'http://localhost:8080',
        help: 'Base URL of the running Dartvel server to read from.',
      )
      ..addOption(
        'limit',
        help: 'Show only the most recent N entries.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print each entry as the JSON the server sent, for piping.',
      );
  }

  /// The endpoint path this command reads.
  String get path;

  /// What to say when the server is up and holding nothing.
  String get emptyMessage;

  /// One line of output for one record.
  String render(Map<String, Object?> record);

  bool get _rawJson => argResults!['json'] as bool;

  @override
  Future<void> run() async {
    final String base = (argResults!['url'] as String).trim();
    final String? limit = argResults!['limit'] as String?;
    final Uri target = Uri.parse(base).replace(
      path: path,
      queryParameters: limit == null ? null : <String, String>{'limit': limit},
    );

    final _Fetched result = await _fetch(target);
    if (result.missing) {
      _emit(_diagnosticsOff(path));
      exitCode = 1;
      return;
    }
    if (result.failure != null) {
      _emit(result.failure!);
      exitCode = 1;
      return;
    }

    final List<Map<String, Object?>> records = _records(result.body);
    if (records.isEmpty) {
      _emit(emptyMessage);
      return;
    }

    for (final Map<String, Object?> record in records) {
      _emit(_rawJson ? jsonEncode(record) : render(record));
    }
  }
}

class LogsCommand extends _DiagnosticsCommand {
  @override
  final String name = 'logs';
  @override
  final String description =
      'Read the recent log records of a running Dartvel server.';

  @override
  String get path => '/_dartvel/logs';

  @override
  String get emptyMessage =>
      'No log records. The server is running and has not logged anything '
      'this buffer still holds.';

  @override
  String render(Map<String, Object?> record) {
    final StringBuffer line = StringBuffer()
      ..write(record['time'] ?? '')
      ..write('  ')
      // Padded so the messages line up: a level column that moves left and
      // right is the thing that makes a log wall unreadable at a glance.
      ..write('${record['level'] ?? 'info'}'.toUpperCase().padRight(5))
      ..write('  ')
      ..write(record['message'] ?? '');

    final Object? traceId = record['traceId'];
    if (traceId != null) line.write('  trace=$traceId');

    final Object? context = record['context'];
    if (context is Map && context.isNotEmpty) line.write('  ${jsonEncode(context)}');

    final Object? error = record['error'];
    if (error != null) line.write('\n        $error');

    return line.toString();
  }
}

class TracesCommand extends _DiagnosticsCommand {
  @override
  final String name = 'traces';
  @override
  final String description =
      'Read the recent trace spans of a running Dartvel server.';

  @override
  String get path => '/_dartvel/traces';

  @override
  String get emptyMessage =>
      'No spans. The server is running and nothing it still holds was '
      'traced.';

  @override
  String render(Map<String, Object?> record) {
    final Object? duration = record['durationMs'];
    final StringBuffer line = StringBuffer()
      ..write('${record['status'] ?? 'unset'}'.padRight(5))
      ..write('  ')
      ..write(duration == null ? '' : '${duration}ms'.padLeft(9))
      ..write('  ')
      ..write(record['name'] ?? '')
      ..write('  trace=${record['traceId']} span=${record['spanId']}');

    if (record['parentSpanId'] != null) {
      line.write(' parent=${record['parentSpanId']}');
    }

    final Object? attributes = record['attributes'];
    if (attributes is Map && attributes.isNotEmpty) {
      line.write('\n      ${jsonEncode(attributes)}');
    }

    return line.toString();
  }
}

class MetricsCommand extends Command<void> {
  @override
  final String name = 'metrics';
  @override
  final String description =
      'Fetch the /metrics endpoint of a running Dartvel server.';

  MetricsCommand() {
    argParser.addOption(
      'url',
      defaultsTo: 'http://localhost:8080',
      help: 'Base URL of the running Dartvel server to read /metrics from.',
    );
  }

  @override
  Future<void> run() async {
    final String base = (argResults!['url'] as String).trim();
    final Uri target = Uri.parse(base).resolve('/metrics');

    final _Fetched result = await _fetch(target);
    if (result.missing) {
      _emit(
        '$target answered 404. That is not a Dartvel server, or it is one '
        'whose application registered its own route at /metrics.',
      );
      exitCode = 1;
      return;
    }
    if (result.failure != null) {
      _emit(result.failure!);
      exitCode = 1;
      return;
    }

    if (result.body.trim().isEmpty) {
      _emit('No metrics recorded at $target.');
      return;
    }

    _emit(result.body.trimRight());
  }
}

// ignore: avoid_print
void _emit(String line) => print(line);
