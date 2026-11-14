import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';

import 'config.dart';
import 'events.dart';

/// What sending a batch to the Conversions API came to.
final class MetaConversionsResult {
  const MetaConversionsResult.sent({required this.eventsReceived, this.status = 200})
      : sent = true,
        reason = null;

  const MetaConversionsResult.notSent(String this.reason, {this.status})
      : sent = false,
        eventsReceived = null;

  /// Whether Meta accepted every request the batch was sent in.
  final bool sent;

  /// `events_received`, as Meta counted them.
  final int? eventsReceived;

  /// The HTTP status of the request that failed, when one was made.
  final int? status;

  /// Why nothing was sent, in words that never include the access token.
  final String? reason;
}

/// Meta's Conversions API, called from the application's backend.
///
/// `POST https://graph.facebook.com/{version}/{pixel id}/events`, with the
/// events in `data` and the access token beside them in the request body.
/// The token is read from the server's environment each time it is needed
/// and goes nowhere else: not into an address, where access logs keep it,
/// and not into a log line or a result.
///
/// Sending never throws. Measuring is not what an order or a page should
/// fail on, so every failure is a [MetaConversionsResult] that says why.
final class MetaConversionsApi {
  MetaConversionsApi(this.config, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final MetaPixelConfig config;
  final DateTime Function() _clock;

  /// The name the Graph API is declared under with `DV.Http`.
  static const String hostName = 'metaGraph';
  static const String baseUrl = 'https://graph.facebook.com';

  /// The most events Meta takes in one request.
  static const int batchLimit = 1000;

  /// How far back an event may be dated. Meta refuses a request holding one
  /// older than seven days, and refuses every event in it.
  static const Duration oldestEvent = Duration(days: 7);

  static void _declareHost() {
    try {
      const DVHttp().host(hostName);
    } on DVHttpUndeclaredHostException {
      const DVHttp().declare(
        hostName,
        const DVHttpHostConfig(
          baseUrl: baseUrl,
          timeout: Duration(seconds: 10),
        ),
      );
    }
  }

  /// Sends [events], in as many requests as Meta's batch limit needs.
  Future<MetaConversionsResult> send(List<MetaServerEvent> events) async {
    final String? pixelId = config.resolvedPixelId;
    if (!config.isConfigured || pixelId == null) {
      return const MetaConversionsResult.notSent('no pixel id is configured');
    }
    final String? token =
        const DVSecrets().maybeGet(config.accessTokenSecret);
    if (token == null) {
      return MetaConversionsResult.notSent(
          '${config.accessTokenSecret} is not set in the server\'s '
          'environment');
    }
    final DateTime oldest = _clock().toUtc().subtract(oldestEvent);
    final List<MetaServerEvent> current = <MetaServerEvent>[
      for (final MetaServerEvent event in events)
        if (event.time.toUtc().isAfter(oldest)) event,
    ];
    if (current.isEmpty) {
      return const MetaConversionsResult.notSent(
          'every event was more than seven days old');
    }

    _declareHost();
    int received = 0;
    for (int start = 0; start < current.length; start += batchLimit) {
      final List<MetaServerEvent> batch = current.sublist(
          start,
          start + batchLimit > current.length
              ? current.length
              : start + batchLimit);
      final MetaConversionsResult result =
          await _post(pixelId, token, batch);
      if (!result.sent) return result;
      received += result.eventsReceived ?? 0;
    }
    return MetaConversionsResult.sent(eventsReceived: received);
  }

  Future<MetaConversionsResult> _post(
    String pixelId,
    String token,
    List<MetaServerEvent> batch,
  ) async {
    final String body = Uri(queryParameters: <String, String>{
      'data': jsonEncode(<Object?>[
        for (final MetaServerEvent event in batch) event.toJson(),
      ]),
      'access_token': token,
      'test_event_code': ?config.testEventCode,
    }).query;
    final Response response;
    try {
      response = await const DVHttp().host(hostName).post(
        '/${config.apiVersion}/$pixelId/events',
        body: body,
        headers: const <String, String>{
          'content-type': 'application/x-www-form-urlencoded',
        },
        // Meta de-duplicates on event_id, so a repeat after a timeout is
        // counted once.
        attempts: 1,
      );
    } on Object catch (error) {
      return MetaConversionsResult.notSent(
          'the Conversions API could not be reached '
          '(${_redact('${error.runtimeType}', token)})');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(await response.body?.text() ?? '');
    } on Object {
      decoded = null;
    }
    if (response.status < 200 || response.status >= 300) {
      final Object? error = decoded is Map ? decoded['error'] : null;
      final String detail = error is Map && error['message'] is String
          ? ': ${_redact(error['message'] as String, token)}'
          : '';
      return MetaConversionsResult.notSent(
          'the Conversions API answered ${response.status}$detail',
          status: response.status);
    }
    final Object? count = decoded is Map ? decoded['events_received'] : null;
    return MetaConversionsResult.sent(
        eventsReceived: count is int ? count : batch.length,
        status: response.status);
  }

  /// [text] with the access token struck out. Meta's own error messages
  /// have been known to repeat what they were sent.
  static String _redact(String text, String token) =>
      text.replaceAll(token, '[redacted]');
}
