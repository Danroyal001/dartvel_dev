/// Outbound webhooks: the events an application sends to its customers'
/// servers.
///
/// Deliveries ride the job layer and go out through `DV.Http`; there is no
/// webhook queue and no webhook HTTP client. What this adds is what those two
/// cannot know about: which event a customer asked for, the per-endpoint
/// ordering and partitioning that keeps one slow customer from delaying every
/// other, the signature a customer verifies, the address check that stops a
/// customer-supplied URL from pointing the server at itself, and the record of
/// every delivery that answers "we never got it".
library dartvel_core.webhooks;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../dartvel.dart';
import 'webhook_resolver_unsupported.dart'
    if (dart.library.io) 'webhook_resolver_io.dart' as resolver;

/// One event the application can send, declared once.
///
/// Emitting a name nobody declared is refused (`DV-WEBHOOK-006`), so the list
/// a customer reads in the application's documentation cannot drift from the
/// list the code sends.
class DVWebhookEvent {
  const DVWebhookEvent(this.name, {this.sensitiveFields = const <String>{}});

  final String name;

  /// Field names that never leave in a payload, wherever they appear in it.
  ///
  /// A generated model's `toPublicJson` already leaves its sensitive fields
  /// out; this is for a payload that is a map, so the same guarantee holds
  /// for data that did not come from a model.
  final Set<String> sensitiveFields;
}

/// `dartvel.webhooks` in `pubspec.yaml`.
class DVWebhooksConfig {
  const DVWebhooksConfig({
    this.allowPrivateAddresses = false,
    this.retention = const Duration(days: 30),
    this.disableAfter = 20,
    this.maxAttempts = 5,
    this.backoff = const Duration(seconds: 30),
    this.maxRedirects = 3,
  });

  /// Deliver to private, loopback and link-local addresses. Only for a
  /// deployment with no cloud metadata service to reach.
  final bool allowPrivateAddresses;

  /// How long a delivery's payload is kept. The record is kept for good.
  final Duration retention;

  /// Consecutive failed attempts after which an endpoint is disabled.
  final int disableAfter;

  /// Attempts at one delivery before it is dead-lettered.
  final int maxAttempts;

  /// Backoff between attempts, handed to the job layer.
  final Duration backoff;

  /// Redirects followed per attempt, each one checked like the endpoint.
  final int maxRedirects;
}

/// Where a customer asked for events to be sent.
class DVWebhookSubscription {
  const DVWebhookSubscription({
    required this.id,
    required this.url,
    required this.events,
    required this.signingSecret,
    required this.createdAt,
    this.previousSigningSecret,
    this.overlapUntil,
    this.tenant,
    this.disabled = false,
    this.consecutiveFailures = 0,
  });

  final String id;
  final Uri url;
  final Set<String> events;

  /// The name of the secret holding the signing key — a name, resolved
  /// through `DVSecrets` at signing time, never the key itself.
  final String signingSecret;

  /// The key being rotated out, signed with alongside [signingSecret] until
  /// [overlapUntil].
  final String? previousSigningSecret;
  final DateTime? overlapUntil;

  final String? tenant;
  final bool disabled;
  final int consecutiveFailures;
  final DateTime createdAt;

  DVWebhookSubscription _copyWith({
    String? signingSecret,
    String? previousSigningSecret,
    DateTime? overlapUntil,
    bool? disabled,
    int? consecutiveFailures,
  }) =>
      DVWebhookSubscription(
        id: id,
        url: url,
        events: events,
        signingSecret: signingSecret ?? this.signingSecret,
        previousSigningSecret:
            previousSigningSecret ?? this.previousSigningSecret,
        overlapUntil: overlapUntil ?? this.overlapUntil,
        tenant: tenant,
        disabled: disabled ?? this.disabled,
        consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
        createdAt: createdAt,
      );
}

enum DVWebhookDeliveryState {
  /// Waiting for its turn, or between attempts.
  pending,
  delivered,

  /// Every attempt failed (`DV-WEBHOOK-004`).
  deadLettered,

  /// The endpoint, or a redirect from it, resolved somewhere a delivery may
  /// not go (`DV-WEBHOOK-002`). Not retried: the answer will not change.
  refused,
}

/// The record of one delivery: kept indefinitely, with its payload kept for
/// the retention window.
class DVWebhookDelivery {
  const DVWebhookDelivery({
    required this.id,
    required this.subscriptionId,
    required this.event,
    required this.sequence,
    required this.createdAt,
    required this.state,
    required this.payload,
    this.attempts = 0,
    this.replays = 0,
    this.lastStatus,
    this.lastError,
    this.lastAttemptAt,
    this.lastDuration,
    this.deliveredAt,
    this.payloadPurgedAt,
  });

  /// Stable across retries and replays, and sent in `dartvel-webhook-id`, so a
  /// consumer can deduplicate an at-least-once delivery.
  final String id;
  final String subscriptionId;
  final String event;

  /// Emission order within the subscription.
  final int sequence;
  final DateTime createdAt;
  final DVWebhookDeliveryState state;

  /// The JSON body, or null once the retention window has passed.
  final String? payload;

  /// Attempts in the current series; a replay starts a new one.
  final int attempts;
  final int replays;
  final int? lastStatus;
  final String? lastError;
  final DateTime? lastAttemptAt;
  final Duration? lastDuration;
  final DateTime? deliveredAt;
  final DateTime? payloadPurgedAt;

  DVWebhookDelivery _copyWith({
    int? sequence,
    DVWebhookDeliveryState? state,
    String? payload,
    bool clearPayload = false,
    int? attempts,
    int? replays,
    int? lastStatus,
    String? lastError,
    DateTime? lastAttemptAt,
    Duration? lastDuration,
    DateTime? deliveredAt,
    DateTime? payloadPurgedAt,
  }) =>
      DVWebhookDelivery(
        id: id,
        subscriptionId: subscriptionId,
        event: event,
        sequence: sequence ?? this.sequence,
        createdAt: createdAt,
        state: state ?? this.state,
        payload: clearPayload ? null : (payload ?? this.payload),
        attempts: attempts ?? this.attempts,
        replays: replays ?? this.replays,
        lastStatus: lastStatus ?? this.lastStatus,
        lastError: lastError ?? this.lastError,
        lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
        lastDuration: lastDuration ?? this.lastDuration,
        deliveredAt: deliveredAt ?? this.deliveredAt,
        payloadPurgedAt: payloadPurgedAt ?? this.payloadPurgedAt,
      );
}

/// `DV-WEBHOOK-006`: an event name that is not in the declared catalog.
class DVWebhookUndeclaredEventException implements Exception {
  const DVWebhookUndeclaredEventException(this.event);
  final String event;
  String get code => 'DV-WEBHOOK-006';

  @override
  String toString() => '$code: "$event" is not a declared webhook event. '
      'Declare it with DVWebhookEvent before emitting it.';
}

/// `DV-WEBHOOK-002`: an endpoint address a delivery may not go to.
class DVWebhookAddressRefusedException implements Exception {
  const DVWebhookAddressRefusedException(this.url, this.reason);
  final Uri url;
  final String reason;
  String get code => 'DV-WEBHOOK-002';

  @override
  String toString() => '$code: refused webhook endpoint $url: $reason.';
}

/// `DV-WEBHOOK-005`: a replay requested after the payload retention window.
class DVWebhookReplayRefusedException implements Exception {
  const DVWebhookReplayRefusedException(this.deliveryId, this.reason);
  final String deliveryId;
  final String reason;
  String get code => 'DV-WEBHOOK-005';

  @override
  String toString() => '$code: delivery $deliveryId cannot be replayed: '
      '$reason. A delivery with no payload would arrive empty, and an empty '
      'delivery cannot be told from a real event.';
}

/// The signature scheme: HMAC-SHA256 over `timestamp.body`, hex, as `v1=`
/// entries in `dartvel-webhook-signature`.
///
/// The timestamp is signed so a captured delivery cannot be replayed a month
/// later; a consumer bounds its age with [verify]'s `tolerance`.
abstract final class DVWebhookSignature {
  static String compute(String secret, String timestamp, String body) =>
      Hmac(sha256, utf8.encode(secret))
          .convert(utf8.encode('$timestamp.$body'))
          .toString();

  /// The header value for [secrets], current key first.
  static String header({
    required String timestamp,
    required String body,
    required List<String> secrets,
  }) =>
      <String>[
        for (final String secret in secrets)
          'v1=${compute(secret, timestamp, body)}',
      ].join(',');

  /// Whether [header] carries a valid signature for [secret].
  ///
  /// Compares in constant time, and when [tolerance] is given refuses a
  /// timestamp further than that from [now] — the two things a consumer's own
  /// implementation gets wrong.
  static bool verify({
    required String secret,
    required String timestamp,
    required String body,
    required String header,
    Duration? tolerance,
    DateTime? now,
  }) {
    if (tolerance != null) {
      final int? seconds = int.tryParse(timestamp);
      if (seconds == null) return false;
      final DateTime at =
          DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
      if ((now ?? DateTime.now()).difference(at).abs() > tolerance) {
        return false;
      }
    }
    final List<int> expected = utf8.encode(compute(secret, timestamp, body));
    bool matched = false;
    for (final String part in header.split(',')) {
      final String entry = part.trim();
      if (!entry.startsWith('v1=')) continue;
      // Every entry is compared in full, so timing does not say which one or
      // how much of it matched.
      if (_constantTimeEquals(utf8.encode(entry.substring(3)), expected)) {
        matched = true;
      }
    }
    return matched;
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    int difference = a.length ^ b.length;
    final int length = a.length < b.length ? a.length : b.length;
    for (int i = 0; i < length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}

/// The job a subscription's queue carries: attempt the oldest undelivered
/// delivery for [subscriptionId].
///
/// Not "send delivery N". A retried job that named its own delivery would be
/// re-queued behind later ones, and event 2 would overtake a failing event 1;
/// a job that always takes the head of its endpoint's line cannot.
class DVWebhookDrainJob {
  const DVWebhookDrainJob(this.subscriptionId);
  final String subscriptionId;
}

/// `DV.Webhooks`.
class DVWebhooks {
  const DVWebhooks();

  static final Map<String, DVWebhookEvent> _events = <String, DVWebhookEvent>{};
  static final Map<String, DVWebhookSubscription> _subscriptions =
      <String, DVWebhookSubscription>{};
  static final Map<String, DVWebhookDelivery> _deliveries =
      <String, DVWebhookDelivery>{};
  static int _sequence = 0;
  static int _ids = 0;
  static bool _registered = false;

  static DVWebhooksConfig config = const DVWebhooksConfig();

  /// Injectable for tests, like `DVHttp.clock`.
  static DateTime Function() clock = DateTime.now;

  /// Every address a host resolves to. Injectable so a test can put a name
  /// on a private address without a DNS server.
  static Future<List<String>> Function(String host) resolveHost =
      resolver.dvWebhookResolveHost;

  /// Called when an endpoint is disabled, for telling its owner — wire it to
  /// `DV.Notifications`.
  static Future<void> Function(DVWebhookSubscription subscription)? onDisabled;

  static void reset() {
    _events.clear();
    _subscriptions.clear();
    _deliveries.clear();
    _sequence = 0;
    _ids = 0;
    _registered = false;
    config = const DVWebhooksConfig();
    clock = DateTime.now;
    resolveHost = resolver.dvWebhookResolveHost;
    onDisabled = null;
  }

  static String _queueFor(String subscriptionId) =>
      'dv.webhooks.$subscriptionId';

  void _ensureRegistered() {
    if (_registered) return;
    const DVQueues().register<DVWebhookDrainJob>(
      (DVWebhookDrainJob job) => _attemptHead(job.subscriptionId),
    );
    _registered = true;
  }

  // --- catalog and subscriptions --------------------------------------------

  void declare(DVWebhookEvent event) => _events[event.name] = event;

  List<DVWebhookEvent> get catalog =>
      List<DVWebhookEvent>.unmodifiable(_events.values);

  /// Subscribes [url] to [events], after checking the address.
  ///
  /// Throws [DVWebhookAddressRefusedException] for an address a delivery may
  /// not go to, and [DVWebhookUndeclaredEventException] for an event nobody
  /// declared.
  Future<DVWebhookSubscription> subscribe({
    required String url,
    required Set<String> events,
    required String signingSecret,
    String? tenant,
    String? id,
  }) async {
    for (final String event in events) {
      if (!_events.containsKey(event)) {
        throw DVWebhookUndeclaredEventException(event);
      }
    }
    final Uri uri = Uri.parse(url);
    await _checkAddress(uri);
    final DVWebhookSubscription subscription = DVWebhookSubscription(
      id: id ?? 'whsub_${++_ids}',
      url: uri,
      events: Set<String>.unmodifiable(events),
      signingSecret: signingSecret,
      tenant: tenant,
      createdAt: clock(),
    );
    _subscriptions[subscription.id] = subscription;
    return subscription;
  }

  DVWebhookSubscription? subscription(String id) => _subscriptions[id];

  List<DVWebhookSubscription> get subscriptions =>
      List<DVWebhookSubscription>.unmodifiable(_subscriptions.values);

  /// Signs with [newSecret] from now on, and with the current key as well
  /// until [overlap] has passed (`DV-WEBHOOK-007`), so a customer can switch
  /// keys without a window in which every delivery fails verification.
  Future<DVWebhookSubscription> rotateSigningKey(
    String subscriptionId,
    String newSecret, {
    required Duration overlap,
  }) async {
    final DVWebhookSubscription current = _require(subscriptionId);
    final DateTime until = clock().add(overlap);
    final DVWebhookSubscription rotated = current._copyWith(
      previousSigningSecret: current.signingSecret,
      signingSecret: newSecret,
      overlapUntil: until,
    );
    _subscriptions[subscriptionId] = rotated;
    DVObservability.log(
      'Webhook signing key rotated for $subscriptionId; both signatures are '
      'sent until ${until.toIso8601String()}.',
      level: DVLogLevel.info,
      code: 'DV-WEBHOOK-007',
      context: <String, Object?>{
        'subscription': subscriptionId,
        'overlapUntil': until.toIso8601String(),
      },
    );
    return rotated;
  }

  /// Re-enables a disabled endpoint and resumes its pending deliveries.
  Future<void> enable(String subscriptionId) async {
    final DVWebhookSubscription current = _require(subscriptionId);
    _subscriptions[subscriptionId] =
        current._copyWith(disabled: false, consecutiveFailures: 0);
    _ensureRegistered();
    for (final DVWebhookDelivery delivery in deliveries(subscriptionId)) {
      if (delivery.state == DVWebhookDeliveryState.pending) {
        await _dispatch(subscriptionId);
      }
    }
  }

  DVWebhookSubscription _require(String id) {
    final DVWebhookSubscription? subscription = _subscriptions[id];
    if (subscription == null) {
      throw ArgumentError('No webhook subscription "$id".');
    }
    return subscription;
  }

  // --- emitting -------------------------------------------------------------

  /// Records a delivery of [event] to every enabled subscription that asked
  /// for it, and queues them.
  ///
  /// The payload is serialized here, once: a model through `toPublicJson`, so
  /// its sensitive fields are absent by construction, and the event's own
  /// [DVWebhookEvent.sensitiveFields] are removed wherever they appear. An
  /// endpoint belongs to somebody else, so this is the one serializer whose
  /// output the application can never recall.
  Future<List<DVWebhookDelivery>> emit(String event, Object? payload) async {
    final DVWebhookEvent? declared = _events[event];
    if (declared == null) {
      final DVWebhookUndeclaredEventException error =
          DVWebhookUndeclaredEventException(event);
      DVObservability.log(error.toString(),
          level: DVLogLevel.error, code: error.code);
      throw error;
    }
    final Object? data = _strip(_publicForm(payload), declared.sensitiveFields);
    _ensureRegistered();

    final List<DVWebhookDelivery> created = <DVWebhookDelivery>[];
    for (final DVWebhookSubscription subscription in _subscriptions.values) {
      if (subscription.disabled || !subscription.events.contains(event)) {
        continue;
      }
      final String id =
          'whdel_${clock().microsecondsSinceEpoch}_${++_ids}';
      final String body = jsonEncode(<String, Object?>{
        'id': id,
        'event': event,
        'created': clock().toUtc().toIso8601String(),
        'data': data,
      });
      final DVWebhookDelivery delivery = DVWebhookDelivery(
        id: id,
        subscriptionId: subscription.id,
        event: event,
        sequence: ++_sequence,
        createdAt: clock(),
        state: DVWebhookDeliveryState.pending,
        payload: body,
      );
      _deliveries[id] = delivery;
      created.add(delivery);
      await _dispatch(subscription.id);
    }
    return created;
  }

  static Object? _publicForm(Object? payload) {
    if (payload == null || payload is num || payload is String ||
        payload is bool) {
      return payload;
    }
    if (payload is Map) return Map<String, Object?>.from(payload);
    if (payload is Iterable) return payload.map(_publicForm).toList();
    final dynamic model = payload;
    try {
      return model.toPublicJson();
    } on NoSuchMethodError {
      // Not a generated model. toJson is the only other shape there is, and
      // the event's declared sensitive fields still come out of it below.
      return model.toJson();
    }
  }

  static Object? _strip(Object? value, Set<String> sensitive) {
    if (sensitive.isEmpty) return value;
    if (value is Map) {
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> entry in value.entries)
          if (!sensitive.contains('${entry.key}'))
            '${entry.key}': _strip(entry.value, sensitive),
      };
    }
    if (value is List) {
      return <Object?>[for (final Object? item in value) _strip(item, sensitive)];
    }
    return value;
  }

  Future<void> _dispatch(String subscriptionId) async {
    await const DVQueues().dispatch<DVWebhookDrainJob>(
      DVWebhookDrainJob(subscriptionId),
      queue: _queueFor(subscriptionId),
      // Above the delivery's own limit: a delivery is dead-lettered by the
      // attempts recorded on it, and the job that carried the last attempt
      // must not be dead-lettered first.
      maxAttempts: config.maxAttempts + 1,
      backoff: config.backoff,
    );
  }

  // --- delivering -----------------------------------------------------------

  /// Runs one queued attempt for [subscriptionId].
  Future<void> drainOnce(String subscriptionId) async {
    _ensureRegistered();
    await const DVQueues().work(queue: _queueFor(subscriptionId));
  }

  /// Works [subscriptionId]'s queue until nothing is left in it.
  Future<void> drain(String subscriptionId) async {
    _ensureRegistered();
    final String queue = _queueFor(subscriptionId);
    // Bounded: every attempt either finishes a delivery or counts towards its
    // limit, so this many runs is enough to empty any queue.
    int budget = 0;
    for (final DVWebhookDelivery delivery in deliveries(subscriptionId)) {
      if (delivery.state == DVWebhookDeliveryState.pending) {
        budget += config.maxAttempts + 1;
      }
    }
    budget += 1;
    while (budget-- > 0) {
      final List<Object?> pending = await const DVQueues().pending(queue);
      if (pending.isEmpty) return;
      await const DVQueues().work(queue: queue);
    }
  }

  /// Drains every subscription at once, each in its own line, so an endpoint
  /// that takes thirty seconds to answer delays its own deliveries and nobody
  /// else's.
  Future<void> drainAll() => Future.wait(<Future<void>>[
        for (final String id in _subscriptions.keys.toList()) drain(id),
      ]);

  DVWebhookDelivery? _head(String subscriptionId) {
    DVWebhookDelivery? head;
    for (final DVWebhookDelivery delivery in _deliveries.values) {
      if (delivery.subscriptionId != subscriptionId ||
          delivery.state != DVWebhookDeliveryState.pending) {
        continue;
      }
      if (head == null || delivery.sequence < head.sequence) head = delivery;
    }
    return head;
  }

  Future<void> _attemptHead(String subscriptionId) async {
    final DVWebhookSubscription? subscription = _subscriptions[subscriptionId];
    if (subscription == null || subscription.disabled) return;
    final DVWebhookDelivery? head = _head(subscriptionId);
    if (head == null) return;
    final String? body = head.payload;
    if (body == null) return;

    final DateTime started = clock();
    int? status;
    String? error;
    try {
      status = await _send(subscription, head, body);
    } on DVWebhookAddressRefusedException catch (refused) {
      DVObservability.log(refused.toString(),
          level: DVLogLevel.warn,
          code: refused.code,
          context: <String, Object?>{
            'subscription': subscriptionId,
            'delivery': head.id,
          });
      _deliveries[head.id] = head._copyWith(
        state: DVWebhookDeliveryState.refused,
        attempts: head.attempts + 1,
        lastError: refused.toString(),
        lastAttemptAt: started,
        lastDuration: clock().difference(started),
      );
      await _countFailure(subscription);
      return;
    } catch (failure) {
      error = '$failure';
    }

    final int attempts = head.attempts + 1;
    if (status != null && status >= 200 && status < 300) {
      _deliveries[head.id] = head._copyWith(
        state: DVWebhookDeliveryState.delivered,
        attempts: attempts,
        lastStatus: status,
        lastAttemptAt: started,
        lastDuration: clock().difference(started),
        deliveredAt: clock(),
      );
      _subscriptions[subscriptionId] =
          (_subscriptions[subscriptionId] ?? subscription)
              ._copyWith(consecutiveFailures: 0);
      return;
    }

    final bool exhausted = attempts >= config.maxAttempts;
    _deliveries[head.id] = head._copyWith(
      state: exhausted ? DVWebhookDeliveryState.deadLettered : null,
      attempts: attempts,
      lastStatus: status,
      lastError: error ?? 'HTTP $status',
      lastAttemptAt: started,
      lastDuration: clock().difference(started),
    );
    if (exhausted) {
      DVObservability.log(
        'Webhook delivery ${head.id} to ${subscription.url} failed $attempts '
        'times and moved to dead letters.',
        level: DVLogLevel.warn,
        code: 'DV-WEBHOOK-004',
        context: <String, Object?>{
          'subscription': subscriptionId,
          'delivery': head.id,
          'status': status,
        },
      );
    }
    final bool nowDisabled = await _countFailure(subscription);
    // Thrown only while the delivery still has attempts left, so the job layer
    // re-queues this line and applies its backoff. A disabled endpoint's queue
    // stops instead.
    if (!exhausted && !nowDisabled) {
      throw StateError('Webhook delivery ${head.id} failed: '
          '${error ?? 'HTTP $status'}');
    }
  }

  /// Counts a failed attempt; disables the endpoint at the configured run.
  Future<bool> _countFailure(DVWebhookSubscription subscription) async {
    final DVWebhookSubscription latest =
        _subscriptions[subscription.id] ?? subscription;
    final int failures = latest.consecutiveFailures + 1;
    if (failures < config.disableAfter) {
      _subscriptions[subscription.id] =
          latest._copyWith(consecutiveFailures: failures);
      return false;
    }
    final DVWebhookSubscription disabled =
        latest._copyWith(consecutiveFailures: failures, disabled: true);
    _subscriptions[subscription.id] = disabled;
    await const DVQueues().flush(queue: _queueFor(subscription.id));
    DVObservability.log(
      'Webhook endpoint ${subscription.url} disabled after $failures '
      'consecutive failures.',
      level: DVLogLevel.warn,
      code: 'DV-WEBHOOK-003',
      context: <String, Object?>{'subscription': subscription.id},
    );
    await onDisabled?.call(disabled);
    return true;
  }

  List<String> _signingKeys(DVWebhookSubscription subscription) {
    const DVSecrets secrets = DVSecrets();
    final DateTime? until = subscription.overlapUntil;
    final String? previous = subscription.previousSigningSecret;
    return <String>[
      secrets.get(subscription.signingSecret),
      if (previous != null && until != null && clock().isBefore(until))
        secrets.get(previous),
    ];
  }

  /// One attempt: the address is checked, the body signed with the keys valid
  /// now, and redirects followed only after the same check.
  Future<int> _send(
    DVWebhookSubscription subscription,
    DVWebhookDelivery delivery,
    String body,
  ) async {
    Uri target = subscription.url;
    for (int hop = 0;; hop++) {
      await _checkAddress(target);
      final String timestamp =
          '${clock().toUtc().millisecondsSinceEpoch ~/ 1000}';
      final Response response = await const DVHttp().send(
        'POST',
        target,
        body: body,
        // One attempt per job run: retries belong to the job layer, which
        // keeps the line's order and applies the backoff.
        attempts: 1,
        headers: <String, String>{
          'content-type': 'application/json; charset=utf-8',
          'dartvel-webhook-id': delivery.id,
          'dartvel-webhook-event': delivery.event,
          'dartvel-webhook-timestamp': timestamp,
          'dartvel-webhook-signature': DVWebhookSignature.header(
            timestamp: timestamp,
            body: body,
            secrets: _signingKeys(subscription),
          ),
        },
      );
      final int status = response.status;
      if (status < 300 || status >= 400) return status;
      final String? location = response.headers.get('location');
      if (location == null || hop >= config.maxRedirects) return status;
      target = target.resolve(location);
    }
  }

  // --- the address check ----------------------------------------------------

  /// Refuses an endpoint a delivery may not go to: not HTTPS, or resolving to
  /// a private, loopback, link-local or metadata address.
  Future<void> _checkAddress(Uri url) async {
    DVWebhookAddressRefusedException refuse(String reason) =>
        DVWebhookAddressRefusedException(url, reason);

    if (url.scheme != 'https') throw refuse('deliveries are HTTPS POSTs');
    if (config.allowPrivateAddresses) return;

    final String host = url.host.toLowerCase();
    if (host.isEmpty) throw refuse('it has no host');
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host == 'metadata' ||
        host.endsWith('.internal')) {
      throw refuse('"$host" names a local or metadata service');
    }

    final List<int>? literal = _parseAddress(host);
    final List<List<int>> addresses;
    if (literal != null) {
      addresses = <List<int>>[literal];
    } else {
      final List<String> resolved = await resolveHost(host);
      if (resolved.isEmpty) throw refuse('"$host" does not resolve');
      addresses = <List<int>>[
        for (final String address in resolved)
          _parseAddress(address) ?? const <int>[],
      ];
    }
    for (final List<int> address in addresses) {
      final String? why = _nonPublic(address);
      if (why != null) throw refuse('"$host" resolves to $why');
    }
  }

  static List<int>? _parseAddress(String text) {
    try {
      return Uri.parseIPv4Address(text);
    } on FormatException {
      // Not IPv4.
    }
    try {
      return Uri.parseIPv6Address(text);
    } on FormatException {
      return null;
    }
  }

  /// Why [address] is not a public unicast address, or null when it is.
  static String? _nonPublic(List<int> address) {
    if (address.length == 4) return _nonPublic4(address);
    if (address.length != 16) return 'an address that could not be read';
    final List<int> b = address;
    bool zero(int from, int to) {
      for (int i = from; i < to; i++) {
        if (b[i] != 0) return false;
      }
      return true;
    }

    // IPv4 inside IPv6 is judged as the IPv4 address it is: mapped
    // (::ffff:a.b.c.d), compatible (::a.b.c.d) and NAT64 (64:ff9b::/96).
    if (zero(0, 10) && b[10] == 0xff && b[11] == 0xff) {
      return _nonPublic4(b.sublist(12));
    }
    if (b[0] == 0x00 && b[1] == 0x64 && b[2] == 0xff && b[3] == 0x9b &&
        zero(4, 12)) {
      return _nonPublic4(b.sublist(12));
    }
    if (zero(0, 15) && (b[15] == 0 || b[15] == 1)) {
      return b[15] == 1 ? 'the IPv6 loopback address' : 'the unspecified address';
    }
    if (zero(0, 12)) return _nonPublic4(b.sublist(12));
    if ((b[0] & 0xfe) == 0xfc) return 'an IPv6 unique local address';
    if (b[0] == 0xfe && (b[1] & 0xc0) == 0x80) return 'an IPv6 link-local address';
    if (b[0] == 0xfe && (b[1] & 0xc0) == 0xc0) return 'an IPv6 site-local address';
    if (b[0] == 0xff) return 'an IPv6 multicast address';
    return null;
  }

  static String? _nonPublic4(List<int> a) {
    final int x = a[0], y = a[1], z = a[2];
    if (x == 0) return 'the unspecified or "this network" range';
    if (x == 10) return 'a private address (10.0.0.0/8)';
    if (x == 127) return 'a loopback address';
    if (x == 100 && y >= 64 && y <= 127) return 'a carrier-grade NAT address';
    if (x == 169 && y == 254) {
      return 'a link-local address, where cloud metadata services live';
    }
    if (x == 172 && y >= 16 && y <= 31) return 'a private address (172.16.0.0/12)';
    if (x == 192 && y == 168) return 'a private address (192.168.0.0/16)';
    if (x == 192 && y == 0 && (z == 0 || z == 2)) return 'a reserved address';
    if (x == 198 && (y == 18 || y == 19)) return 'a benchmarking address';
    if (x == 198 && y == 51 && z == 100) return 'a documentation address';
    if (x == 203 && y == 0 && z == 113) return 'a documentation address';
    if (x >= 224) return 'a multicast or reserved address';
    return null;
  }

  // --- the record, retention and replay -------------------------------------

  DVWebhookDelivery? delivery(String id) => _deliveries[id];

  /// [subscriptionId]'s deliveries in the order they were emitted.
  List<DVWebhookDelivery> deliveries(String subscriptionId) {
    final List<DVWebhookDelivery> found = <DVWebhookDelivery>[
      for (final DVWebhookDelivery delivery in _deliveries.values)
        if (delivery.subscriptionId == subscriptionId) delivery,
    ]..sort((DVWebhookDelivery a, DVWebhookDelivery b) =>
        a.sequence.compareTo(b.sequence));
    return found;
  }

  /// Drops the payload of every finished delivery older than the retention
  /// window, keeping the record. Returns how many were dropped.
  ///
  /// A delivery still waiting keeps its payload: dropping it would leave a
  /// pending delivery that can only ever be sent empty.
  int purgeExpiredPayloads() {
    int dropped = 0;
    final DateTime now = clock();
    for (final DVWebhookDelivery delivery in _deliveries.values.toList()) {
      if (delivery.payload == null ||
          delivery.state == DVWebhookDeliveryState.pending ||
          now.difference(delivery.createdAt) <= config.retention) {
        continue;
      }
      _deliveries[delivery.id] =
          delivery._copyWith(clearPayload: true, payloadPurgedAt: now);
      dropped++;
    }
    return dropped;
  }

  /// Sends a delivery again, as the same delivery, while its payload is kept.
  ///
  /// Refused after the retention window (`DV-WEBHOOK-005`) — whether or not
  /// the purge has run yet — rather than sent without a body.
  Future<DVWebhookDelivery> replay(String deliveryId) async {
    final DVWebhookDelivery? delivery = _deliveries[deliveryId];
    if (delivery == null) {
      throw ArgumentError('No webhook delivery "$deliveryId".');
    }
    String? reason;
    if (delivery.payload == null) {
      reason = 'its payload was dropped after the retention window';
    } else if (clock().difference(delivery.createdAt) > config.retention) {
      reason = 'it is older than the ${config.retention.inDays}-day retention '
          'window';
    }
    if (reason != null) {
      final DVWebhookReplayRefusedException refused =
          DVWebhookReplayRefusedException(deliveryId, reason);
      DVObservability.log(refused.toString(),
          level: DVLogLevel.warn,
          code: refused.code,
          context: <String, Object?>{'delivery': deliveryId});
      throw refused;
    }
    final DVWebhookDelivery again = delivery._copyWith(
      sequence: ++_sequence,
      state: DVWebhookDeliveryState.pending,
      attempts: 0,
      replays: delivery.replays + 1,
    );
    _deliveries[deliveryId] = again;
    _ensureRegistered();
    await _dispatch(delivery.subscriptionId);
    return again;
  }
}
