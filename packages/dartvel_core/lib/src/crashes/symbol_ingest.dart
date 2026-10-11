/// The crash backend's endpoint for symbols: what `dartvel symbols upload`
/// talks to.
///
/// It writes files a stranger supplies into a directory the backend later
/// parses, so the order of its checks is the whole of its safety: who is
/// asking, then whether the names are safe to write, then whether the bytes
/// are the ones the uploader meant. A symbols directory an attacker can write
/// to is a crash reporter that shows whatever stack the attacker likes.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import '../http/client_address.dart';
import '../observability/logging.dart';
import '../secrets/secrets.dart';
import 'symbols.dart';

/// What became of an upload.
enum DVSymbolIngestOutcome {
  stored,

  /// The caller did not present the token.
  unauthorized,

  /// No token is configured, so the endpoint does not exist for anybody.
  notConfigured,

  /// Too many wrong tokens from this source recently.
  limited,
  invalid,
  tooLarge,
  checksumMismatch,

  /// A manifest listing files that are not all there, or not as listed.
  incomplete,
  unavailable,
}

final class DVSymbolIngestResult {
  const DVSymbolIngestResult(this.outcome);

  final DVSymbolIngestOutcome outcome;

  int get status => switch (outcome) {
        DVSymbolIngestOutcome.stored => 200,
        DVSymbolIngestOutcome.unauthorized => 401,
        DVSymbolIngestOutcome.notConfigured => 404,
        DVSymbolIngestOutcome.limited => 429,
        DVSymbolIngestOutcome.invalid => 400,
        DVSymbolIngestOutcome.tooLarge => 413,
        DVSymbolIngestOutcome.checksumMismatch => 422,
        DVSymbolIngestOutcome.incomplete => 422,
        DVSymbolIngestOutcome.unavailable => 503,
      };

  String get message => switch (outcome) {
        DVSymbolIngestOutcome.stored => 'stored',
        DVSymbolIngestOutcome.unauthorized => 'a valid symbols token is required',
        DVSymbolIngestOutcome.notConfigured => 'not found',
        DVSymbolIngestOutcome.limited => 'too many failed attempts; try later',
        DVSymbolIngestOutcome.invalid => 'not a valid symbols upload',
        DVSymbolIngestOutcome.tooLarge => 'larger than a symbols file may be',
        DVSymbolIngestOutcome.checksumMismatch =>
          'the body does not match the x-dartvel-sha256 it was sent with',
        DVSymbolIngestOutcome.incomplete =>
          'the manifest lists files that have not all been uploaded as listed',
        DVSymbolIngestOutcome.unavailable => 'the symbols could not be stored',
      };

  Map<String, Object?> toJson() => <String, Object?>{
        'outcome': outcome.name,
        'stored': outcome == DVSymbolIngestOutcome.stored,
        'message': message,
      };
}

class DVSymbolIngest {
  DVSymbolIngest({
    required this.repository,
    Future<String?> Function()? token,
    this.maxFileBytes = 256 * 1024 * 1024,
    this.failuresPerHour = 20,
    DateTime Function()? clock,
    void Function(String line)? log,
  })  : _token = token ?? _tokenFromSecrets,
        _clock = clock ?? DateTime.now,
        _log = log ?? _defaultLog;

  /// The secret the uploader presents as `Authorization: Bearer <token>`.
  static const String tokenSecret = 'DARTVEL_SYMBOLS_TOKEN';

  /// The header carrying the SHA-256 the uploader computed.
  static const String checksumHeader = 'x-dartvel-sha256';

  /// Where the generated backend serves it, under the API base path:
  /// `PUT /_dartvel/symbols/<release>/<file>`.
  static const String path = '/_dartvel/symbols';

  final DVSymbolRepository repository;
  final int maxFileBytes;
  final int failuresPerHour;
  final Future<String?> Function() _token;
  final DateTime Function() _clock;
  final void Function(String line) _log;

  static const Duration _window = Duration(hours: 1);
  final Map<String, ListQueue<DateTime>> _failures =
      <String, ListQueue<DateTime>>{};

  static final DVLogger _logger = DVLogger();
  static void _defaultLog(String line) =>
      _logger.log(line, level: DVLogLevel.warn);

  static Future<String?> _tokenFromSecrets() async =>
      const DVSecrets().maybeGet(tokenSecret);

  Future<DVSymbolIngestResult> accept({
    required String release,
    required String name,
    required List<int> body,
    required String? authorization,
    required String? sha256,
    String source = DVClientAddress.unknownSource,
  }) async {
    final String? expected = await _token();
    if (expected == null || expected.isEmpty) {
      return const DVSymbolIngestResult(DVSymbolIngestOutcome.notConfigured);
    }

    final DateTime now = _clock();
    final ListQueue<DateTime> failed =
        _failures[source] ?? ListQueue<DateTime>();
    while (failed.isNotEmpty && now.difference(failed.first) >= _window) {
      failed.removeFirst();
    }
    if (failed.length >= failuresPerHour) {
      _failures[source] = failed;
      return const DVSymbolIngestResult(DVSymbolIngestOutcome.limited);
    }
    if (!_authorised(authorization, expected)) {
      _failures[source] = failed..add(now);
      if (failed.length == failuresPerHour) {
        // Not which address: a client address is personal data.
        _log('a client address is past $failuresPerHour wrong symbols tokens '
            'this hour; further requests from it are refused with 429');
      }
      return const DVSymbolIngestResult(DVSymbolIngestOutcome.unauthorized);
    }
    if (failed.isEmpty) _failures.remove(source);

    if (!dvSymbolReleaseOk(release) || !dvSymbolFileNameOk(name)) {
      return const DVSymbolIngestResult(DVSymbolIngestOutcome.invalid);
    }
    if (body.length > maxFileBytes) {
      return const DVSymbolIngestResult(DVSymbolIngestOutcome.tooLarge);
    }
    if (sha256 == null ||
        sha256.toLowerCase() != dvSymbolSha256(body)) {
      return const DVSymbolIngestResult(DVSymbolIngestOutcome.checksumMismatch);
    }

    try {
      if (name == DVSymbolsManifest.fileName) {
        return await _acceptManifest(release, body);
      }
      await repository.putFile(release, name, body);
      return const DVSymbolIngestResult(DVSymbolIngestOutcome.stored);
    } on Object catch (error) {
      // The type alone: a storage error can quote a path or a value.
      _log('symbols could not be stored (${error.runtimeType})');
      return const DVSymbolIngestResult(DVSymbolIngestOutcome.unavailable);
    }
  }

  Future<DVSymbolIngestResult> _acceptManifest(
      String release, List<int> body) async {
    final DVSymbolsManifest manifest;
    try {
      final Object? json = jsonDecode(utf8.decode(body));
      if (json is! Map) {
        return const DVSymbolIngestResult(DVSymbolIngestOutcome.invalid);
      }
      manifest = DVSymbolsManifest.fromJson(json.cast<String, Object?>());
    } on Object {
      return const DVSymbolIngestResult(DVSymbolIngestOutcome.invalid);
    }
    if (manifest.release != release) {
      return const DVSymbolIngestResult(DVSymbolIngestOutcome.invalid);
    }
    for (final DVSymbolFile file in manifest.files) {
      final List<int>? stored = await repository.readFile(release, file.name);
      if (stored == null ||
          stored.length != file.bytes ||
          dvSymbolSha256(stored) != file.sha256.toLowerCase()) {
        return const DVSymbolIngestResult(DVSymbolIngestOutcome.incomplete);
      }
    }
    await repository.putManifest(manifest);
    return const DVSymbolIngestResult(DVSymbolIngestOutcome.stored);
  }

  /// `Authorization: Bearer <token>` against [expected], comparing every byte
  /// so the time taken does not say how many leading characters were right.
  static bool _authorised(String? header, String expected) {
    const String scheme = 'Bearer ';
    if (header == null || !header.startsWith(scheme)) return false;
    final List<int> presented = utf8.encode(header.substring(scheme.length));
    final List<int> wanted = utf8.encode(expected);
    int difference = presented.length ^ wanted.length;
    for (int i = 0; i < wanted.length; i++) {
      final int a = i < presented.length ? presented[i] : 0;
      difference |= a ^ wanted[i];
    }
    return difference == 0;
  }
}
