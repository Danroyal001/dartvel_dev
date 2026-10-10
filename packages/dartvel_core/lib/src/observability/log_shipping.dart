/// Sending a device's log records to the application's own backend, and the
/// backend's side of receiving them.
///
/// Off unless `dartvel.logging.ship.enabled` says otherwise. What leaves the
/// device is records at warn and above, already redacted where they were
/// written, with a random install id, the release and the platform. Nothing
/// names a person: no user id, no device name, no address. Records go to the
/// deployment's own backend and never straight to a third party, so a write
/// key is not shipped inside every copy of the application.
library dartvel.observability.log_shipping;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'logging.dart';
import 'observability.dart' show DVObservability;

/// Buffers records on the device and posts them in batches.
///
/// [post] sends one body and answers the status; the generated runtime
/// passes a POST to `<api>/_dartvel/client-logs`. Nothing here logs through
/// the logger it is a sink of -- a failed send that logged would be a record
/// that has to be sent, which fails, which logs.
class DVLogShipper implements DVLogSink {
  DVLogShipper({
    required Future<int> Function(String body) post,
    required this.installId,
    required this.release,
    required this.platform,
    this.level = DVLogLevel.warn,
    this.batch = 50,
    this.queue = 500,
    this.interval = const Duration(seconds: 30),
  }) : _post = post;

  /// Posts to the application's own backend at [endpoint], read at send time
  /// so the runtime's base URL is the one in force.
  factory DVLogShipper.toBackend({
    required Uri Function() endpoint,
    required String installId,
    required String release,
    required String platform,
    DVLogLevel level = DVLogLevel.warn,
    int batch = 50,
    http.Client? client,
    Duration timeout = const Duration(seconds: 15),
  }) =>
      DVLogShipper(
        post: (String body) async {
          final http.Client sending = client ?? http.Client();
          try {
            final http.Response response = await sending
                .post(endpoint(),
                    headers: const <String, String>{
                      'content-type': 'application/json; charset=utf-8',
                    },
                    body: body)
                .timeout(timeout);
            return response.statusCode;
          } finally {
            if (client == null) sending.close();
          }
        },
        installId: installId,
        release: release,
        platform: platform,
        level: level,
        batch: batch,
      );

  final String installId;
  final String release;
  final String platform;

  /// The lowest level queued.
  final DVLogLevel level;

  /// Records per request.
  final int batch;

  /// Records held while the backend cannot be reached; past it the oldest
  /// go, counted in [dropped].
  final int queue;

  /// How long a partial batch waits before it is sent anyway.
  final Duration interval;

  final Future<int> Function(String body) _post;
  final ListQueue<DVLogRecord> _pending = ListQueue<DVLogRecord>();
  Timer? _timer;
  bool _sending = false;
  int _dropped = 0;

  /// Records waiting to be sent.
  int get pending => _pending.length;

  /// Records that will never be sent: pushed out of a full queue, or in a
  /// batch the backend refused for good.
  int get dropped => _dropped;

  @override
  void write(DVLogRecord record) {
    if (!record.level.atLeast(level)) return;
    _pending.add(record);
    while (_pending.length > queue) {
      _pending.removeFirst();
      _dropped++;
    }
    if (_pending.length >= batch) {
      unawaited(flush());
    } else {
      _timer ??= Timer(interval, () {
        _timer = null;
        unawaited(flush());
      });
    }
  }

  /// Sends what is queued, a batch at a time, until a send does not succeed.
  /// Answers how many records were accepted.
  Future<int> flush() async {
    if (_sending) return 0;
    _sending = true;
    int accepted = 0;
    try {
      while (_pending.isNotEmpty) {
        final List<DVLogRecord> sending =
            _pending.take(batch).toList(growable: false);
        final int status;
        try {
          status = await _post(jsonEncode(<String, Object?>{
            'install': installId,
            'release': release,
            'platform': platform,
            'records': <Object?>[
              for (final DVLogRecord record in sending) record.toJson(),
            ],
          }));
        } on Object {
          break; // Unreachable: kept, and sent with the next flush.
        }
        if (status >= 200 && status < 300) {
          _removeFirst(sending.length);
          accepted += sending.length;
          continue;
        }
        // Worth sending again: a busy backend, or one deployed before it
        // served this endpoint.
        if (status == 404 || status == 429 || status >= 500) break;
        // Any other 4xx is a batch that will never be accepted.
        _removeFirst(sending.length);
        _dropped += sending.length;
      }
    } finally {
      _sending = false;
    }
    return accepted;
  }

  void _removeFirst(int count) {
    for (int index = 0; index < count && _pending.isNotEmpty; index++) {
      _pending.removeFirst();
    }
  }

  /// Stops the timer. Queued records stay queued.
  void close() {
    _timer?.cancel();
    _timer = null;
  }
}

/// What the client-logs endpoint answered.
enum DVLogIngestOutcome { stored, limited, invalid, tooLarge }

final class DVLogIngestResult {
  const DVLogIngestResult(this.outcome, {this.accepted = 0});

  final DVLogIngestOutcome outcome;
  final int accepted;

  int get status => switch (outcome) {
        DVLogIngestOutcome.stored => 201,
        DVLogIngestOutcome.limited => 202,
        DVLogIngestOutcome.invalid => 400,
        DVLogIngestOutcome.tooLarge => 413,
      };

  /// Fixed text chosen here. Nothing from the request is ever in it.
  Map<String, Object?> toJson() => <String, Object?>{
        'status': outcome.name,
        'accepted': accepted,
      };
}

/// The backend's side: `POST <apiBasePath>/_dartvel/client-logs`.
///
/// Each record is written into the server's own log stream -- stdout as JSON
/// lines on a deployed backend -- with the client's install, release and
/// platform beside it, and redacted again on the way in, so a client built
/// before a field was declared sensitive cannot put it in the server's logs.
/// The client address is used for nothing and kept nowhere.
///
/// [forward] is the hosting hook: when it is set (the generated backend sets
/// it from `DARTVEL_LOG_FORWARD_URL`, which Dartvel Cloud provides on the
/// deployments it hosts) the accepted batch, as redacted here, is handed on.
class DVLogIngest {
  DVLogIngest({
    DVLogger? logger,
    this.perInstallPerHour = 600,
    this.maxBytes = 262144,
    this.forward,
    DateTime Function()? clock,
  })  : _logger = logger,
        _clock = clock ?? DateTime.now;

  /// Where the generated backend serves it, under the API base path.
  static const String path = '/_dartvel/client-logs';

  /// The forwarding hook a hosting platform turns on from the process
  /// environment: `DARTVEL_LOG_FORWARD_URL` (https, or http to this machine)
  /// and an optional `DARTVEL_LOG_FORWARD_TOKEN` sent as a bearer token.
  /// Dartvel Cloud sets both on the deployments it hosts. Null when the URL
  /// is absent or not one records may be sent to.
  static Future<void> Function(String body)? forwarderFrom(
    Map<String, String> environment, {
    http.Client? client,
  }) {
    final Uri? url =
        Uri.tryParse(environment['DARTVEL_LOG_FORWARD_URL']?.trim() ?? '');
    if (url == null || !url.hasAuthority) return null;
    final bool local = url.host == 'localhost' || url.host == '127.0.0.1';
    if (url.scheme != 'https' && !(url.scheme == 'http' && local)) return null;
    final String? token = environment['DARTVEL_LOG_FORWARD_TOKEN']?.trim();
    return (String body) async {
      final http.Client sending = client ?? http.Client();
      try {
        await sending
            .post(url,
                headers: <String, String>{
                  'content-type': 'application/json; charset=utf-8',
                  if (token != null && token.isNotEmpty)
                    'authorization': 'Bearer $token',
                },
                body: body)
            .timeout(const Duration(seconds: 10));
      } finally {
        if (client == null) sending.close();
      }
    };
  }

  static final RegExp _installShape = RegExp(r'^[0-9a-f]{32}$');
  static const int _maxLabel = 64;
  static const Duration _window = Duration(hours: 1);

  final DVLogger? _logger;
  final int perInstallPerHour;
  final int maxBytes;
  final Future<void> Function(String body)? forward;
  final DateTime Function() _clock;

  final Map<String, ListQueue<DateTime>> _recent =
      <String, ListQueue<DateTime>>{};
  final Map<String, int> _limited = <String, int>{};

  /// The process logger unless one was given, read when a batch arrives so
  /// a logger configured after the ingest was made is the one used.
  DVLogger get _target => _logger ?? DVObservability.logger;

  /// How many of [installId]'s records were counted rather than written.
  int limited(String installId) => _limited[installId] ?? 0;

  Future<DVLogIngestResult> accept(List<int> body) async {
    if (body.length > maxBytes) {
      return const DVLogIngestResult(DVLogIngestOutcome.tooLarge);
    }
    final Map<String, Object?> batch;
    try {
      final Object? json = jsonDecode(utf8.decode(body));
      if (json is! Map<String, Object?>) {
        return const DVLogIngestResult(DVLogIngestOutcome.invalid);
      }
      batch = json;
    } on Object {
      return const DVLogIngestResult(DVLogIngestOutcome.invalid);
    }
    final Object? install = batch['install'];
    final Object? release = batch['release'];
    final Object? platform = batch['platform'];
    final Object? records = batch['records'];
    if (install is! String ||
        !_installShape.hasMatch(install) ||
        !_label(release) ||
        !_label(platform) ||
        records is! List) {
      return const DVLogIngestResult(DVLogIngestOutcome.invalid);
    }

    final DateTime now = _clock();
    final ListQueue<DateTime> recent =
        _recent.putIfAbsent(install, () => ListQueue<DateTime>());
    while (recent.isNotEmpty && now.difference(recent.first) >= _window) {
      recent.removeFirst();
    }

    final Map<String, Object?> client = <String, Object?>{
      'install': install,
      'release': release,
      'platform': platform,
    };
    final DVLogger target = _target;
    final DVMemoryLogSink redacted = DVMemoryLogSink(capacity: records.length + 1);
    final DVLogger redactor =
        DVLogger(minimumLevel: DVLogLevel.trace, sinks: <DVLogSink>[redacted]);
    int accepted = 0;
    int over = 0;
    for (final Object? item in records) {
      if (item is! Map<String, Object?>) continue;
      final DVLogRecord record;
      try {
        record = DVLogRecord.fromJson(item);
      } on FormatException {
        continue;
      }
      if (recent.length >= perInstallPerHour) {
        over++;
        continue;
      }
      recent.add(now);
      final Map<String, Object?> context = <String, Object?>{
        ...record.context,
        'client': client,
      };
      redactor.log(
        record.message,
        level: record.level,
        tag: record.tag,
        context: context,
        event: record.event,
        code: record.code,
        error: record.error,
        stackTrace:
            record.stackTrace == null ? null : StackTrace.fromString(record.stackTrace!),
        traceId: record.traceId,
        spanId: record.spanId,
        time: record.time,
      );
      final DVLogRecord clean = redacted.records.last;
      target.log(
        clean.message,
        level: clean.level,
        tag: clean.tag,
        context: clean.context,
        event: clean.event,
        code: clean.code,
        error: clean.error,
        stackTrace: clean.stackTrace == null
            ? null
            : StackTrace.fromString(clean.stackTrace!),
        traceId: clean.traceId,
        spanId: clean.spanId,
        time: clean.time,
      );
      accepted++;
    }
    if (recent.isEmpty) _recent.remove(install);
    if (over > 0) {
      _limited[install] = limited(install) + over;
      // Not which install: the id is the client's, and this says what
      // happened, not to whom.
      target.log(
          'DV-LOG-001: an install is past $perInstallPerHour log records this '
          'hour; $over were counted, not written',
          level: DVLogLevel.warn,
          tag: 'dartvel.logs',
          code: 'DV-LOG-001');
    }

    final Future<void> Function(String body)? forwarding = forward;
    if (forwarding != null && accepted > 0) {
      try {
        await forwarding(jsonEncode(<String, Object?>{
          ...client,
          'records': <Object?>[
            for (final DVLogRecord record in redacted.records) record.toJson(),
          ],
        }));
      } on Object {
        // Forwarding is best effort: the records are already in this
        // server's own stream.
      }
    }
    return DVLogIngestResult(
      over > 0 ? DVLogIngestOutcome.limited : DVLogIngestOutcome.stored,
      accepted: accepted,
    );
  }

  static bool _label(Object? value) =>
      value is String && value.isNotEmpty && value.length <= _maxLabel;
}
