import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';

import 'config.dart';
import 'events.dart';

/// What sending events to the Measurement Protocol came to.
final class GoogleAnalyticsResult {
  const GoogleAnalyticsResult.sent()
      : sent = true,
        reason = null;

  const GoogleAnalyticsResult.notSent(String this.reason) : sent = false;

  /// Whether Google received every request. Received is not the same as
  /// valid: the Measurement Protocol answers 2xx to a malformed event too,
  /// and [GoogleAnalyticsMeasurementProtocol.validate] is how to find out.
  final bool sent;

  /// Why nothing was sent, in words that never include the API secret.
  final String? reason;
}

/// Google Analytics 4's Measurement Protocol, called from the application's
/// backend.
///
/// `POST https://www.google-analytics.com/mp/collect` with the stream's
/// `measurement_id` and `api_secret` as query parameters, which is where
/// Google's protocol puts them. The secret is read from the server's
/// environment each time and appears in nothing this class returns or logs.
///
/// Sending never throws: every failure is a [GoogleAnalyticsResult].
final class GoogleAnalyticsMeasurementProtocol {
  GoogleAnalyticsMeasurementProtocol(this.config, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final GoogleAnalyticsConfig config;
  final DateTime Function() _clock;

  static const String hostName = 'googleAnalytics';
  static const String euHostName = 'googleAnalyticsEu';
  static const String baseUrl = 'https://www.google-analytics.com';
  static const String euBaseUrl = 'https://region1.google-analytics.com';

  /// The most events Google takes in one request.
  static const int batchLimit = 25;

  /// How far back an event may be dated before Google moves it.
  static const Duration oldestEvent = Duration(hours: 72);

  /// What an event is given as `engagement_time_msec` when the caller has
  /// no measurement of its own. Google asks for the parameter so the event
  /// counts towards engaged sessions; one millisecond claims no more than
  /// that somebody was there.
  static const int defaultEngagementMilliseconds = 1;

  DVHttpHost _host() {
    final String name = config.collectInEu ? euHostName : hostName;
    try {
      return const DVHttp().host(name);
    } on DVHttpUndeclaredHostException {
      const DVHttp().declare(
        name,
        DVHttpHostConfig(
          baseUrl: config.collectInEu ? euBaseUrl : baseUrl,
          timeout: const Duration(seconds: 10),
        ),
      );
      return const DVHttp().host(name);
    }
  }

  /// Sends [events] for the visitor [clientId].
  ///
  /// [clientId] is the id Google's tag gave the visitor's browser (two
  /// numbers joined by a period, or the whole `_ga` cookie), or one of the
  /// application's own for a device. [sessionId] joins the events to a
  /// session; [occurredAt] dates them when they happened earlier, up to 72
  /// hours ago.
  Future<GoogleAnalyticsResult> send({
    required String clientId,
    required List<GoogleAnalyticsEvent> events,
    String? userId,
    String? sessionId,
    int? engagementMilliseconds,
    DateTime? occurredAt,
    String? ipOverride,
  }) async {
    final Object? prepared = _prepare(
      clientId: clientId,
      events: events,
      userId: userId,
      sessionId: sessionId,
      engagementMilliseconds: engagementMilliseconds,
      occurredAt: occurredAt,
      ipOverride: ipOverride,
    );
    if (prepared is GoogleAnalyticsResult) return prepared;
    final (String query, String secret, List<Map<String, Object?>> bodies) =
        prepared! as (String, String, List<Map<String, Object?>>);
    for (final Map<String, Object?> body in bodies) {
      final int status;
      try {
        final Response response = await _host()
            .post('/mp/collect?$query', json: body, attempts: 1);
        status = response.status;
      } on Object catch (error) {
        return GoogleAnalyticsResult.notSent(
            'the Measurement Protocol could not be reached '
            '(${error.runtimeType})');
      }
      if (status < 200 || status >= 300) {
        // Google's own advice: correct the request, do not retry it.
        return GoogleAnalyticsResult.notSent(
            'the Measurement Protocol answered $status'
                .replaceAll(secret, '[redacted]'));
      }
    }
    return const GoogleAnalyticsResult.sent();
  }

  /// Asks Google's validation server what is wrong with [events], and
  /// answers with one line per problem: none when they are valid. Nothing
  /// sent this way is recorded in reports.
  Future<List<String>> validate({
    required String clientId,
    required List<GoogleAnalyticsEvent> events,
    String? sessionId,
  }) async {
    final Object? prepared =
        _prepare(clientId: clientId, events: events, sessionId: sessionId);
    if (prepared is GoogleAnalyticsResult) {
      return <String>[prepared.reason ?? 'not configured'];
    }
    final (String query, String _, List<Map<String, Object?>> bodies) =
        prepared! as (String, String, List<Map<String, Object?>>);
    final List<String> problems = <String>[];
    for (final Map<String, Object?> body in bodies) {
      try {
        final Response response = await _host()
            .post('/debug/mp/collect?$query', json: body, attempts: 1);
        final Object? decoded = jsonDecode(await response.body?.text() ?? '{}');
        final Object? messages =
            decoded is Map ? decoded['validationMessages'] : null;
        if (messages is List) {
          for (final Object? message in messages) {
            if (message is Map) {
              problems.add('${message['validationCode']}: '
                  '${message['description']} (${message['fieldPath']})');
            }
          }
        }
      } on Object catch (error) {
        problems.add('the validation server could not be reached '
            '(${error.runtimeType})');
      }
    }
    return problems;
  }

  /// The query and the request bodies, or the result that says why there
  /// are none.
  Object? _prepare({
    required String clientId,
    required List<GoogleAnalyticsEvent> events,
    String? userId,
    String? sessionId,
    int? engagementMilliseconds,
    DateTime? occurredAt,
    String? ipOverride,
  }) {
    final String? measurementId = config.resolvedMeasurementId;
    if (!config.isConfigured || measurementId == null) {
      return const GoogleAnalyticsResult.notSent(
          'no measurement id is configured');
    }
    final String? secret = const DVSecrets().maybeGet(config.apiSecretName);
    if (secret == null) {
      return GoogleAnalyticsResult.notSent(
          '${config.apiSecretName} is not set in the server\'s environment');
    }
    if (clientId.trim().isEmpty) {
      return const GoogleAnalyticsResult.notSent('no client id was given');
    }
    if (events.isEmpty) {
      return const GoogleAnalyticsResult.notSent('there were no events');
    }
    final DateTime now = _clock().toUtc();
    final bool dated = occurredAt != null &&
        occurredAt.toUtc().isAfter(now.subtract(oldestEvent)) &&
        occurredAt.toUtc().isBefore(now);
    final List<Map<String, Object?>> bodies = <Map<String, Object?>>[
      for (int start = 0; start < events.length; start += batchLimit)
        <String, Object?>{
          'client_id': clientId.trim(),
          'user_id': ?userId,
          if (dated) 'timestamp_micros': occurredAt.toUtc().microsecondsSinceEpoch,
          'ip_override': ?ipOverride,
          'events': <Object?>[
            for (final GoogleAnalyticsEvent event in events.sublist(
                start,
                start + batchLimit > events.length
                    ? events.length
                    : start + batchLimit))
              <String, Object?>{
                'name': event.name,
                'params': <String, Object?>{
                  ...event.params,
                  'session_id': ?sessionId,
                  'engagement_time_msec': engagementMilliseconds ??
                      defaultEngagementMilliseconds,
                },
              },
          ],
        },
    ];
    final String query = Uri(queryParameters: <String, String>{
      'measurement_id': measurementId,
      'api_secret': secret,
    }).query;
    return (query, secret, bodies);
  }
}
