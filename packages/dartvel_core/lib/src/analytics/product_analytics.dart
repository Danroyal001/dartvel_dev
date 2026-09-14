/// Product analytics: typed events, checked against consent before they leave
/// the device, delivered in batches to the application's own store and to any
/// provider the application configured.
///
/// Every failure worth guarding here is silent. An event recorded while its
/// category was denied, or delivered after consent was withdrawn, looks like
/// one that was allowed. A sensitive field in a property map arrives in a
/// warehouse nobody at the application can recall it from. An id carried
/// across a withdrawal joins what the person refused to what they later
/// allowed. A sampled funnel is a wrong number that looks like a right one.
library dartvel_core.analytics.product_analytics;

import 'dart:async';
import 'dart:convert';

import '../../dartvel.dart' show DVJobEnvelope, DVQueues;
import '../database/adapter.dart';
import '../flags/flags.dart';
import '../observability/observability.dart';
import '../privacy/privacy.dart';
import '../secrets/secrets.dart';
import '../tenancy/tenants.dart';
import 'consent.dart';

/// An event is an ordinary data class with a name and a category.
///
/// ```dart
/// class CheckoutCompleted extends DVAnalyticsEvent {
///   const CheckoutCompleted(this.order);
///   final Order order;
///   @override String get name => 'checkout_completed';
///   @override DVConsentCategory get category => Categories.product;
///   @override Map<String, Object?> get properties => {'order': order};
/// }
/// ```
///
/// A model in [properties] is serialized through its public shape, which
/// leaves its sensitive fields out; a property that names a sensitive field
/// directly refuses the whole event (`DV-ANALYTICS-004`).
abstract class DVAnalyticsEvent {
  const DVAnalyticsEvent();

  String get name;
  DVConsentCategory get category;
  Map<String, Object?> get properties => const <String, Object?>{};
}

/// A feature flag's exposure, as the event Feature Flags records it as.
class DVFlagExposedEvent extends DVAnalyticsEvent {
  const DVFlagExposedEvent(this.exposure, this.category);

  final DVFlagExposure exposure;

  @override
  final DVConsentCategory category;

  @override
  String get name => 'dartvel.flag_exposed';

  @override
  Map<String, Object?> get properties => <String, Object?>{
        'flag': exposure.key,
        'value': exposure.value,
        'rulesVersion': exposure.rulesVersion,
      };
}

/// An event as it is stored and sent: after consent, after redaction.
///
/// Exactly one of [userId] and [anonymousId] is set. Stitching the two is
/// identity resolution, which the application declares for itself or does
/// not do.
final class DVAnalyticsRecord {
  const DVAnalyticsRecord({
    required this.id,
    required this.name,
    required this.category,
    required this.userId,
    required this.anonymousId,
    required this.sessionId,
    required this.occurredAt,
    required this.policyVersion,
    required this.properties,
    this.tenant,
  });

  final String id;
  final String name;
  final String category;
  final String? userId;
  final String? anonymousId;
  final String sessionId;
  final DateTime occurredAt;

  /// The consent policy version in force when the event was allowed.
  final String policyVersion;
  final Map<String, Object?> properties;
  final String? tenant;

  /// Whose event this is, whichever id it carries.
  String get subject => userId ?? anonymousId!;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'category': category,
        'userId': userId,
        'anonymousId': anonymousId,
        'sessionId': sessionId,
        'occurredAt': occurredAt.toIso8601String(),
        'policyVersion': policyVersion,
        'properties': properties,
        'tenant': tenant,
      };

  static DVAnalyticsRecord fromJson(Map<String, Object?> json) =>
      DVAnalyticsRecord(
        id: json['id']! as String,
        name: json['name']! as String,
        category: json['category']! as String,
        userId: json['userId'] as String?,
        anonymousId: json['anonymousId'] as String?,
        sessionId: json['sessionId']! as String,
        occurredAt: DateTime.parse(json['occurredAt']! as String),
        policyVersion: json['policyVersion']! as String,
        properties: <String, Object?>{
          for (final MapEntry<Object?, Object?> e
              in (json['properties']! as Map).entries)
            '${e.key}': e.value,
        },
        tenant: json['tenant'] as String?,
      );
}

/// Where events are delivered.
abstract interface class DVAnalyticsSink {
  String get name;

  /// Delivers [batch]. A throw leaves the batch queued for the next flush, so
  /// a sink should accept a record it already holds without duplicating it.
  Future<void> send(List<DVAnalyticsRecord> batch);
}

/// A hosted service — PostHog, Mixpanel, a GA-class tool.
///
/// It declares the categories it receives, and receives nothing else. One
/// that declares none is a configuration error (`DV-ANALYTICS-005`): it would
/// otherwise be a provider no consent decision is about.
abstract interface class DVAnalyticsProvider implements DVAnalyticsSink {
  Set<DVConsentCategory> get categories;
}

/// A sink that can remove and export one subject's events.
abstract interface class DVAnalyticsErasableSink implements DVAnalyticsSink {
  Future<void> eraseSubject(String subject);
  Future<List<Map<String, Object?>>> exportSubject(String subject);
}

/// The default store: the application's own database.
///
/// On SQLite for local development, and on any database adapter for volume —
/// the queries do not change when the adapter does.
class DVAnalyticsDatabaseStore implements DVAnalyticsErasableSink {
  DVAnalyticsDatabaseStore({required this.database});

  static const String table = 'dv_analytics_events';

  final DVDatabaseAdapter database;

  @override
  String get name => DVAnalytics.storeName;

  Future<void> ensureSchema() => database.execute(
        'CREATE TABLE IF NOT EXISTS $table (id, name, category, user_id, '
        'anonymous_id, session_id, occurred_at, policy_version, properties, '
        'tenant)',
      );

  @override
  Future<void> send(List<DVAnalyticsRecord> batch) async {
    for (final DVAnalyticsRecord r in batch) {
      final List<Map<String, Object?>> held = await database
          .query('SELECT id FROM $table WHERE id = ?', <Object?>[r.id]);
      if (held.isNotEmpty) continue;
      await database.execute(
        'INSERT INTO $table (id, name, category, user_id, anonymous_id, '
        'session_id, occurred_at, policy_version, properties, tenant) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          r.id,
          r.name,
          r.category,
          r.userId,
          r.anonymousId,
          r.sessionId,
          r.occurredAt.toIso8601String(),
          r.policyVersion,
          jsonEncode(r.properties),
          r.tenant,
        ],
      );
    }
  }

  static DVAnalyticsRecord _fromRow(Map<String, Object?> row) =>
      DVAnalyticsRecord(
        id: '${row['id']}',
        name: '${row['name']}',
        category: '${row['category']}',
        userId: row['user_id'] as String?,
        anonymousId: row['anonymous_id'] as String?,
        sessionId: '${row['session_id']}',
        occurredAt: DateTime.parse('${row['occurred_at']}'),
        policyVersion: '${row['policy_version']}',
        properties: <String, Object?>{
          for (final MapEntry<Object?, Object?> e
              in (jsonDecode('${row['properties']}') as Map).entries)
            '${e.key}': e.value,
        },
        tenant: row['tenant'] as String?,
      );

  /// Every stored event, or [subject]'s, in the order they were stored.
  Future<List<DVAnalyticsRecord>> events({String? subject}) async {
    final List<Map<String, Object?>> rows =
        await database.query('SELECT * FROM $table');
    return <DVAnalyticsRecord>[
      for (final Map<String, Object?> row in rows)
        if (subject == null ||
            row['user_id'] == subject ||
            row['anonymous_id'] == subject)
          _fromRow(row),
    ];
  }

  /// How many subjects reached each of [steps], each after the one before.
  ///
  /// Counted over the stored events, unsampled: a sampled denominator is
  /// wrong in a way that looks plausible on a chart.
  Future<List<int>> funnel(List<String> steps) async {
    final Map<String, List<DVAnalyticsRecord>> bySubject =
        <String, List<DVAnalyticsRecord>>{};
    for (final DVAnalyticsRecord r in await events()) {
      bySubject.putIfAbsent(r.subject, () => <DVAnalyticsRecord>[]).add(r);
    }
    final List<int> counts = List<int>.filled(steps.length, 0);
    for (final List<DVAnalyticsRecord> rows in bySubject.values) {
      rows.sort((DVAnalyticsRecord a, DVAnalyticsRecord b) =>
          a.occurredAt.compareTo(b.occurredAt));
      int reached = 0;
      for (final DVAnalyticsRecord r in rows) {
        if (reached < steps.length && r.name == steps[reached]) reached++;
      }
      for (int i = 0; i < reached; i++) {
        counts[i]++;
      }
    }
    return counts;
  }

  @override
  Future<void> eraseSubject(String subject) async {
    await database
        .execute('DELETE FROM $table WHERE user_id = ?', <Object?>[subject]);
    await database.execute(
        'DELETE FROM $table WHERE anonymous_id = ?', <Object?>[subject]);
  }

  @override
  Future<List<Map<String, Object?>>> exportSubject(String subject) async =>
      <Map<String, Object?>>[
        for (final DVAnalyticsRecord r in await events(subject: subject))
          r.toJson(),
      ];
}

/// What [DVAnalytics.track] did with an event.
final class DVTrackResult {
  const DVTrackResult._(this.accepted, this.code, this.reason);

  /// An event that was not recorded for a reason outside the pipeline, such
  /// as a pipeline that could not start.
  const DVTrackResult.refused({this.code, required String this.reason})
      : accepted = false;

  final bool accepted;

  /// The diagnostic that explains a drop, when there is one.
  final String? code;
  final String? reason;
}

/// A provider configured in a way consent cannot govern.
class DVAnalyticsConfigurationError implements Exception {
  DVAnalyticsConfigurationError(this.code, this.message);

  final String? code;
  final String message;

  @override
  String toString() =>
      'DVAnalyticsConfigurationError: ${code == null ? '' : '$code: '}$message';
}

/// The payload of a queued flush.
class DVAnalyticsFlushJob {
  const DVAnalyticsFlushJob();
}

class _SensitiveNamed implements Exception {
  _SensitiveNamed(this.field);
  final String field;
}

class _Unshaped implements Exception {
  _Unshaped(this.type);
  final String type;
}

/// The analytics pipeline for one install.
class DVAnalytics {
  DVAnalytics({
    required this.consent,
    required this.database,
    required this.store,
    List<DVAnalyticsProvider> providers = const <DVAnalyticsProvider>[],
    Set<String> sensitiveFields = const <String>{},
    this.sessionCap = 1000,
    this.batchSize = 100,
    DateTime Function()? clock,
    void Function(String code, String message)? onDiagnostic,
  })  : providers = List<DVAnalyticsProvider>.unmodifiable(providers),
        _sensitive = <String>{
          for (final String f in sensitiveFields) _fieldKey(f),
        },
        _clock = clock ?? DateTime.now,
        _diagnose = onDiagnostic ?? dvLogAnalyticsDiagnostic {
    if (sessionCap < 1) {
      throw ArgumentError.value(sessionCap, 'sessionCap', 'must be at least 1');
    }
    if (batchSize < 1) {
      throw ArgumentError.value(batchSize, 'batchSize', 'must be at least 1');
    }
    final Set<String> names = <String>{storeName};
    for (final DVAnalyticsProvider p in providers) {
      if (!names.add(p.name)) {
        throw DVAnalyticsConfigurationError(
            null, 'two sinks are named "${p.name}"');
      }
      if (p.categories.isEmpty) {
        const String message =
            'is configured with no consent category declared';
        _diagnose('DV-ANALYTICS-005', 'analytics provider "${p.name}" $message');
        throw DVAnalyticsConfigurationError(
            'DV-ANALYTICS-005', '"${p.name}" $message');
      }
      for (final DVConsentCategory c in p.categories) {
        if (consent.policy.declaration(c) == null) {
          throw DVAnalyticsConfigurationError(null,
              '"${p.name}" receives "${c.name}", which the consent policy does '
              'not declare');
        }
      }
    }
    consent.addListener(_onConsentChange);
  }

  /// The name the application's own store is delivered to under.
  static const String storeName = 'store';
  static const String outboxTable = 'dv_analytics_outbox';
  static const String identityTable = 'dv_analytics_identity';

  final DVConsent consent;
  final DVDatabaseAdapter database;
  final DVAnalyticsSink store;
  final List<DVAnalyticsProvider> providers;

  /// Events of one name per session past which the rest are dropped
  /// (`DV-ANALYTICS-003`). A runaway guard, not sampling: below it every event
  /// is kept.
  final int sessionCap;
  final int batchSize;

  final Set<String> _sensitive;
  final DateTime Function() _clock;
  final void Function(String code, String message) _diagnose;

  Future<void> _chain = Future<void>.value();
  late String _anonymousId = dvAnalyticsRandomId();
  String? _userId;
  String _sessionId = dvAnalyticsRandomId();
  final Map<String, int> _counts = <String, int>{};
  final Set<String> _capped = <String>{};
  int _seq = 0;

  /// The id events carry while nobody is signed in. Separate from the install
  /// id crash reports carry, which are sent without analytics consent, and
  /// replaced whenever consent is withdrawn or somebody signs out.
  String get anonymousId => _anonymousId;
  String? get userId => _userId;
  String get sessionId => _sessionId;

  static String _fieldKey(String name) =>
      name.toLowerCase().replaceAll('_', '');

  Future<void> ensureSchema() async {
    await database.execute(
      'CREATE TABLE IF NOT EXISTS $outboxTable (seq, sink, event_id, category, '
      'user_id, anonymous_id, record)',
    );
    await database
        .execute('CREATE TABLE IF NOT EXISTS $identityTable (id, value)');
    final DVAnalyticsSink s = store;
    if (s is DVAnalyticsDatabaseStore) await s.ensureSchema();
    final List<Map<String, Object?>> last = await database
        .query('SELECT seq FROM $outboxTable ORDER BY seq DESC LIMIT 1');
    if (last.isNotEmpty) {
      final Object? seq = last.first['seq'];
      _seq = seq is int ? seq : int.parse('$seq');
    }
    final List<Map<String, Object?>> id = await database.query(
        'SELECT value FROM $identityTable WHERE id = ?',
        <Object?>['anonymous']);
    if (id.isEmpty) {
      await _persistAnonymousId();
    } else {
      _anonymousId = '${id.first['value']}';
    }
  }

  Future<void> _persistAnonymousId() async {
    await database.execute(
        'DELETE FROM $identityTable WHERE id = ?', <Object?>['anonymous']);
    await database.execute(
      'INSERT INTO $identityTable (id, value) VALUES (?, ?)',
      <Object?>['anonymous', _anonymousId],
    );
  }

  /// Completes once every queued write and rotation has.
  Future<void> get idle async {
    while (true) {
      final Future<void> current = _chain;
      await current;
      if (identical(current, _chain)) return;
    }
  }

  Future<T> _serial<T>(Future<T> Function() op) {
    final Completer<T> done = Completer<T>();
    _chain = _chain.then((_) async {
      try {
        done.complete(await op());
      } on Object catch (error, stack) {
        done.completeError(error, stack);
      }
    });
    return done.future;
  }

  /// Starts a session: a new session id and a new count for the cap.
  Future<void> startSession({String? id}) {
    _sessionId = id ?? dvAnalyticsRandomId();
    _counts.clear();
    _capped.clear();
    return Future<void>.value();
  }

  /// Sets who later events belong to. Earlier events keep the id they had and
  /// nothing records that the two belong together.
  ///
  /// Signing out, or another person signing in, replaces the anonymous id, so
  /// the next person on the device is not joined to the last.
  void identify(String? userId) {
    if (userId == _userId) return;
    final bool leaving = _userId != null;
    _userId = userId;
    unawaited(startSession());
    if (leaving) _rotate();
  }

  void _rotate() {
    _anonymousId = dvAnalyticsRandomId();
    _sessionId = dvAnalyticsRandomId();
    _counts.clear();
    _capped.clear();
    unawaited(_serial(_persistAnonymousId).catchError((Object error) {
      DVObservability.log('analytics could not persist a new anonymous id',
          level: DVLogLevel.error, error: error);
    }));
  }

  void _onConsentChange(DVConsentChange change) {
    if (change.withdrawn.isEmpty) return;
    // Whatever was allowed before and is allowed again later must not share
    // an id or a session with it.
    _rotate();
    final Set<String> withdrawn = <String>{
      for (final DVConsentCategory c in change.withdrawn) c.name,
    };
    unawaited(_serial(() async {
      for (final String c in withdrawn) {
        await database.execute(
            'DELETE FROM $outboxTable WHERE category = ?', <Object?>[c]);
      }
    }).catchError((Object error) {
      DVObservability.log(
          'analytics could not clear withdrawn events from the outbox; they '
          'are dropped as they leave instead',
          level: DVLogLevel.error,
          error: error);
    }));
  }

  /// Checks consent, the cap and the payload, and queues the event.
  ///
  /// A denied category is dropped here, before anything is written
  /// (`DV-ANALYTICS-001`), so granting consent later does not send it.
  Future<DVTrackResult> track(DVAnalyticsEvent event) async {
    final DVConsentCategory category = event.category;
    if (consent.policy.declaration(category) == null) {
      throw ArgumentError.value(category.name, 'category',
          'of "${event.name}" is not declared in the consent policy');
    }
    if (!consent.isGranted(category)) {
      _diagnose(
        'DV-ANALYTICS-001',
        '"${event.name}" dropped on the device: "${category.name}" has no '
            'consent',
      );
      return const DVTrackResult._(false, 'DV-ANALYTICS-001', 'no consent');
    }

    final Map<String, Object?> properties;
    try {
      properties = _shapeMap(event.properties, direct: true);
    } on _SensitiveNamed catch (named) {
      _diagnose(
        'DV-ANALYTICS-004',
        '"${event.name}" names the sensitive field "${named.field}"; the event '
            'was not recorded',
      );
      return const DVTrackResult._(
          false, 'DV-ANALYTICS-004', 'names a sensitive field');
    } on _Unshaped catch (unshaped) {
      final String reason =
          'a ${unshaped.type} has no analytics shape (toPublicJson or toJson)';
      DVObservability.log('"${event.name}" not recorded: $reason',
          level: DVLogLevel.error);
      return DVTrackResult._(false, null, reason);
    }

    final int count = (_counts[event.name] ?? 0) + 1;
    _counts[event.name] = count;
    if (count > sessionCap) {
      if (_capped.add(event.name)) {
        _diagnose(
          'DV-ANALYTICS-003',
          '"${event.name}" reached the per-session cap of $sessionCap; '
              'further events of it are dropped this session',
        );
      }
      return const DVTrackResult._(false, 'DV-ANALYTICS-003', 'session cap');
    }

    final DVAnalyticsRecord record = DVAnalyticsRecord(
      id: dvAnalyticsRandomId(),
      name: event.name,
      category: category.name,
      userId: _userId,
      anonymousId: _userId == null ? _anonymousId : null,
      sessionId: _sessionId,
      occurredAt: _clock().toUtc(),
      policyVersion: consent.policy.version,
      properties: properties,
      tenant: const DVTenants().currentTenant,
    );
    final List<String> sinks = <String>[
      storeName,
      for (final DVAnalyticsProvider p in providers)
        if (p.categories.contains(category)) p.name,
    ];
    await _serial(() async {
      final String body = jsonEncode(record.toJson());
      for (final String sink in sinks) {
        await database.execute(
          'INSERT INTO $outboxTable (seq, sink, event_id, category, user_id, '
          'anonymous_id, record) VALUES (?, ?, ?, ?, ?, ?, ?)',
          <Object?>[
            ++_seq,
            sink,
            record.id,
            record.category,
            record.userId,
            record.anonymousId,
            body,
          ],
        );
      }
    });
    return const DVTrackResult._(true, null, null);
  }

  Map<String, Object?> _shapeMap(Map<Object?, Object?> map,
          {required bool direct}) =>
      <String, Object?>{
        for (final MapEntry<Object?, Object?> e in map.entries)
          if (!_isSensitive('${e.key}', direct: direct))
            '${e.key}': _isCredential('${e.key}')
                ? DVLogger.redactedValue
                : _shape(e.value, direct: direct),
      };

  /// A declared sensitive field named directly refuses the event; one that
  /// arrives inside a model's serialized form is left out of it.
  bool _isSensitive(String key, {required bool direct}) {
    if (!_sensitive.contains(_fieldKey(key))) return false;
    if (direct) throw _SensitiveNamed(key);
    return true;
  }

  static bool _isCredential(String key) {
    final String lower = key.toLowerCase();
    for (final String needle in DVLogger.defaultRedactedKeys) {
      if (lower.contains(needle)) return true;
    }
    return false;
  }

  Object? _shape(Object? value, {required bool direct}) {
    if (value == null || value is num || value is bool) return value;
    if (value is String) return dvRedactSecrets(value);
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Enum) return value.name;
    if (value is Map) return _shapeMap(value, direct: direct);
    if (value is Iterable) {
      return <Object?>[for (final Object? v in value) _shape(v, direct: direct)];
    }
    final dynamic model = value;
    Object? serialized;
    bool found = false;
    for (final Object? Function() read in <Object? Function()>[
      () => model.toAnalyticsJson(),
      () => model.toPublicJson(),
      () => model.toJson(),
    ]) {
      try {
        serialized = read();
        found = true;
        break;
      } on NoSuchMethodError {
        continue;
      }
    }
    // Never toString: it is whatever the class's author printed, which is
    // how an email address ends up as a property.
    if (!found) throw _Unshaped('${value.runtimeType}');
    return _shape(serialized, direct: false);
  }

  /// How many deliveries are queued, one per event per sink.
  Future<int> pending() async {
    await idle;
    final List<Map<String, Object?>> rows =
        await database.query('SELECT COUNT(*) AS n FROM $outboxTable');
    final Object? n = rows.first['n'];
    return n is int ? n : int.parse('$n');
  }

  /// Delivers queued events in batches of [batchSize], and returns how many
  /// deliveries succeeded.
  ///
  /// Consent is checked again as each event leaves: one withdrawn since it was
  /// tracked is dropped, not sent. A sink that throws keeps its events for the
  /// next flush and does not hold the others back.
  Future<int> flush({Set<String>? sinks}) async {
    await idle;
    return _serial(() async {
      int sent = 0;
      final List<DVAnalyticsSink> all = <DVAnalyticsSink>[store, ...providers];
      for (final DVAnalyticsSink sink in all) {
        if (sinks != null && !sinks.contains(sink.name)) continue;
        sent += await _flushSink(sink);
      }
      return sent;
    });
  }

  Future<int> _flushSink(DVAnalyticsSink sink) async {
    int sent = 0;
    final Set<String> reportedDrop = <String>{};
    while (true) {
      final List<Map<String, Object?>> rows = await database.query(
        'SELECT * FROM $outboxTable WHERE sink = ? ORDER BY seq LIMIT ?',
        <Object?>[sink.name, batchSize],
      );
      if (rows.isEmpty) return sent;
      final List<Map<String, Object?>> leaving = <Map<String, Object?>>[];
      for (final Map<String, Object?> row in rows) {
        final DVConsentCategory category =
            DVConsentCategory('${row['category']}');
        final bool allowed = consent.policy.declaration(category) != null &&
            consent.isGranted(category);
        if (allowed) {
          leaving.add(row);
          continue;
        }
        if (reportedDrop.add(category.name)) {
          _diagnose(
            'DV-ANALYTICS-001',
            'queued events dropped on the device: "${category.name}" no '
                'longer has consent',
          );
        }
        await _deleteOutbox(sink.name, row['seq']);
      }
      if (leaving.isNotEmpty) {
        try {
          await sink.send(<DVAnalyticsRecord>[
            for (final Map<String, Object?> row in leaving)
              DVAnalyticsRecord.fromJson(
                  jsonDecode('${row['record']}') as Map<String, Object?>),
          ]);
        } on Object catch (error) {
          DVObservability.log(
            'analytics delivery to ${sink.name} failed; ${leaving.length} '
            'events stay queued',
            level: DVLogLevel.warn,
            error: error,
          );
          return sent;
        }
        for (final Map<String, Object?> row in leaving) {
          await _deleteOutbox(sink.name, row['seq']);
        }
        sent += leaving.length;
      }
      if (rows.length < batchSize) return sent;
    }
  }

  Future<void> _deleteOutbox(String sink, Object? seq) => database.execute(
        'DELETE FROM $outboxTable WHERE sink = ? AND seq = ?',
        <Object?>[sink, seq],
      );

  /// Registers the flush handler on the durable job layer.
  void registerJobs(DVQueues queues) {
    queues.register<DVAnalyticsFlushJob>((DVAnalyticsFlushJob _) async {
      await flush();
    });
  }

  /// Queues a flush; a worker runs it.
  Future<DVJobEnvelope<DVAnalyticsFlushJob>> requestFlush({
    DVQueues queues = const DVQueues(),
    String queue = 'default',
  }) =>
      queues.dispatch<DVAnalyticsFlushJob>(const DVAnalyticsFlushJob(),
          queue: queue);

  /// Makes this pipeline Feature Flags' exposure sink.
  ///
  /// Exposure is recorded only when [category] is granted, and the flag
  /// runtime reports what consent withheld (`DV-FLAGS-007`).
  void connectFlags({required DVConsentCategory category}) {
    if (consent.policy.declaration(category) == null) {
      throw ArgumentError.value(category.name, 'category',
          'is not declared in the consent policy');
    }
    DVFlags.exposureConsent = () => consent.isGranted(category);
    DVFlags.onExposure = (DVFlagExposure exposure) {
      unawaited(track(DVFlagExposedEvent(exposure, category)).then(
        (DVTrackResult _) {},
        onError: (Object error) => DVObservability.log(
          'a flag exposure could not be queued',
          level: DVLogLevel.error,
          error: error,
        ),
      ));
    };
  }

  /// The Data Compliance adapters for everything analytics holds: the store
  /// and the outbox, the consent records, and each provider.
  List<DVPrivacyAdapter> privacyAdapters() => <DVPrivacyAdapter>[
        _DVAnalyticsEventsPrivacyAdapter(this),
        _DVConsentPrivacyAdapter(consent),
        for (final DVAnalyticsProvider p in providers)
          _DVAnalyticsProviderPrivacyAdapter(this, p),
      ];

  Future<void> _eraseOutbox(String subject) => _serial(() async {
        await database.execute(
            'DELETE FROM $outboxTable WHERE user_id = ?', <Object?>[subject]);
        await database.execute('DELETE FROM $outboxTable WHERE anonymous_id = ?',
            <Object?>[subject]);
      });

  Future<List<Map<String, Object?>>> _outboxFor(String subject) async {
    await idle;
    final Set<String> seen = <String>{};
    return <Map<String, Object?>>[
      for (final Map<String, Object?> row
          in await database.query('SELECT * FROM $outboxTable'))
        if ((row['user_id'] == subject || row['anonymous_id'] == subject) &&
            seen.add('${row['event_id']}'))
          jsonDecode('${row['record']}') as Map<String, Object?>,
    ];
  }
}

class _DVAnalyticsEventsPrivacyAdapter implements DVPrivacyAdapter {
  _DVAnalyticsEventsPrivacyAdapter(this.analytics);

  final DVAnalytics analytics;

  @override
  String get name => 'analytics:events';

  DVAnalyticsErasableSink get _store {
    final DVAnalyticsSink store = analytics.store;
    if (store is DVAnalyticsErasableSink) return store;
    throw StateError('the analytics store ${store.name} cannot erase a subject');
  }

  @override
  Future<void> erase(DVPrivacySubjectRef subject) async {
    await analytics._eraseOutbox('${subject.id}');
    await _store.eraseSubject('${subject.id}');
  }

  @override
  Future<Map<String, Object?>> export(DVPrivacySubjectRef subject) async =>
      <String, Object?>{
        'events': await _store.exportSubject('${subject.id}'),
        'unsent': await analytics._outboxFor('${subject.id}'),
      };
}

class _DVConsentPrivacyAdapter implements DVPrivacyAdapter {
  _DVConsentPrivacyAdapter(this.consent);

  final DVConsent consent;

  @override
  String get name => 'analytics:consent';

  /// Consent records are the evidence that consent existed and that the
  /// erasure ran, so they are kept under the pseudonym rather than deleted.
  @override
  Future<void> erase(DVPrivacySubjectRef subject) async {
    final int kept =
        await consent.pseudonymize('${subject.id}', subject.pseudonym);
    if (kept == 0) return;
    DVObservability.log(
      '$kept consent records were retained after erasure as evidence, '
      'carrying no personal fields',
      level: DVLogLevel.info,
      code: 'DV-PRIVACY-010',
      context: <String, Object?>{'subject': subject.pseudonym},
    );
  }

  @override
  Future<Map<String, Object?>> export(DVPrivacySubjectRef subject) async =>
      <String, Object?>{
        'records': <Map<String, Object?>>[
          for (final DVConsentRecord r
              in await consent.records(subject: '${subject.id}'))
            r.toJson(),
        ],
      };
}

class _DVAnalyticsProviderPrivacyAdapter implements DVPrivacyAdapter {
  _DVAnalyticsProviderPrivacyAdapter(this.analytics, this.provider);

  final DVAnalytics analytics;
  final DVAnalyticsProvider provider;

  @override
  String get name => 'analytics:${provider.name}';

  DVAnalyticsErasableSink get _erasable {
    final DVAnalyticsProvider p = provider;
    if (p is DVAnalyticsErasableSink) return p as DVAnalyticsErasableSink;
    throw StateError(
        'the analytics provider ${provider.name} has no erasure adapter');
  }

  @override
  Future<void> erase(DVPrivacySubjectRef subject) async {
    final DVAnalyticsErasableSink sink = _erasable;
    await analytics._eraseOutbox('${subject.id}');
    await sink.eraseSubject('${subject.id}');
  }

  @override
  Future<Map<String, Object?>> export(DVPrivacySubjectRef subject) async =>
      <String, Object?>{
        'events': await _erasable.exportSubject('${subject.id}'),
      };
}
