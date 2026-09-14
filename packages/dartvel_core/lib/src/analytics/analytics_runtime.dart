/// What a running application reaches as `DV.Analytics` and `DV.Privacy`.
///
/// The pipeline ([DVAnalytics]), consent ([DVConsent]) and the privacy walk
/// ([DVPrivacy]) are complete on their own and were reachable from nothing:
/// an application had to construct all three, in the right order, over the
/// right database, and remember to hand the analytics adapters to the
/// erasure. Every way of getting that wrong is silent, so it is done once
/// here and started by the generated runtime from `dartvel.analytics`.
library dartvel_core.analytics.runtime;

import 'dart:async';
import 'dart:convert';

import '../database/adapter.dart';
import '../observability/observability.dart';
import '../privacy/privacy.dart';
import 'consent.dart';
import 'product_analytics.dart';

/// `dartvel.analytics` from pubspec.yaml, checked.
final class DVAnalyticsSettings {
  DVAnalyticsSettings({
    required this.consent,
    this.flagExposureCategory,
    this.sessionCap = 1000,
  }) {
    final DVConsentCategory? flags = flagExposureCategory;
    if (flags != null && consent.declaration(flags) == null) {
      throw DVAnalyticsConfigurationError(
          null,
          'dartvel.analytics.flags.category: "${flags.name}" is not a '
          'category dartvel.analytics.consent declares');
    }
    if (sessionCap < 1) {
      throw DVAnalyticsConfigurationError(null,
          'dartvel.analytics.sessionCap: must be at least 1, not $sessionCap');
    }
  }

  /// Reads `dartvel.analytics`, refusing anything it does not understand.
  ///
  /// A misspelt key skipped is a setting the application believes it made:
  /// `consnet:` would leave the pipeline with no policy, and a flag category
  /// read as absent would leave an experiment recording nobody. So each is an
  /// error naming the key and what is accepted, and `dartvel build` stops on
  /// it.
  factory DVAnalyticsSettings.fromConfig(Map<Object?, Object?> analytics) {
    Never refuse(String message) =>
        throw DVAnalyticsConfigurationError(null, message);

    for (final Object? key in analytics.keys) {
      if (!_keys.contains(key)) {
        refuse('dartvel.analytics.$key is not a setting Dartvel reads; '
            'accepted: ${_keys.join(', ')}');
      }
    }

    final Object? store = analytics['store'];
    if (store != null && store != 'database') {
      refuse('dartvel.analytics.store: "$store" is not a store Dartvel has; '
          'accepted: database. A hosted provider is an adapter configured in '
          'code, not a store');
    }

    final Object? consent = analytics['consent'];
    if (consent is! Map) {
      refuse('dartvel.analytics.consent is required: analytics with no '
          'consent policy has nothing to check an event against. Declare a '
          'version and the categories');
    }
    final DVConsentPolicy policy;
    try {
      policy = DVConsentPolicy.fromConfig(<String, Object?>{
        for (final MapEntry<Object?, Object?> e in consent.entries)
          '${e.key}': e.value,
      });
    } on ArgumentError catch (error) {
      refuse('dartvel.analytics.consent: '
          '${error.name == null ? '' : '${error.name} '}${error.message}'
          '${error.invalidValue == null || error.invalidValue is Map ? '' : ' (${error.invalidValue})'}');
    }

    DVConsentCategory? flagCategory;
    final Object? flags = analytics['flags'];
    if (flags != null) {
      if (flags is! Map) {
        refuse('dartvel.analytics.flags must be a map, such as '
            '{ category: product }');
      }
      for (final Object? key in flags.keys) {
        if (key != 'category') {
          refuse('dartvel.analytics.flags.$key is not a setting Dartvel '
              'reads; accepted: category');
        }
      }
      final Object? category = flags['category'];
      if (category is! String || category.trim().isEmpty) {
        refuse('dartvel.analytics.flags.category must name a consent '
            'category');
      }
      flagCategory = DVConsentCategory(category.trim());
    }

    final Object? cap = analytics['sessionCap'];
    if (cap != null && (cap is! int || cap < 1)) {
      refuse('dartvel.analytics.sessionCap: must be a whole number of at '
          'least 1, not $cap');
    }

    return DVAnalyticsSettings(
      consent: policy,
      flagExposureCategory: flagCategory,
      sessionCap: cap is int ? cap : 1000,
    );
  }

  static const List<String> _keys = <String>[
    'store',
    'consent',
    'flags',
    'sessionCap',
  ];

  final DVConsentPolicy consent;

  /// The category Feature Flags' exposures are recorded under, or null when
  /// exposure is not recorded.
  final DVConsentCategory? flagExposureCategory;

  /// Events of one name per session past which the rest are dropped.
  final int sessionCap;
}

/// The analytics pipeline for this process, as `DV.Analytics`.
///
/// Started once, by the generated runtime. Everything it does waits for the
/// stored consent to have been read: an event tracked in the first
/// milliseconds of a launch would otherwise be judged against the declared
/// defaults rather than against what the person chose, and a category that
/// defaults to granted would record an event from somebody who withdrew it
/// yesterday.
class DVAnalyticsRuntime {
  DVAnalyticsRuntime._(this.settings, this._providers, this._sensitiveFields);

  static DVAnalyticsRuntime? _current;

  /// The name of the row in the identity table holding this install's id.
  static const String installIdKey = 'install';

  /// The configured runtime.
  ///
  /// Throws until one is started. An application that never declared
  /// analytics has no policy, and a pipeline invented for it would either
  /// record everything or nothing without saying which.
  static DVAnalyticsRuntime get current =>
      _current ??
      (throw StateError(
          'DV.Analytics is not configured. Declare dartvel.analytics, with a '
          'consent policy, in pubspec.yaml; the generated runtime starts it '
          'from there.'));

  /// Whether a runtime has been started in this process.
  static bool get isConfigured => _current != null;

  /// Forgets the runtime, for tests.
  static void resetForTest() => _current = null;

  final DVAnalyticsSettings settings;
  final List<DVAnalyticsProvider> _providers;
  final Set<String> _sensitiveFields;
  final Completer<DVAnalytics> _pipeline = Completer<DVAnalytics>();
  DVAnalytics? _ready;
  final List<void Function()> _readyListeners = <void Function()>[];

  /// Starts the pipeline over the database [database] opens, and makes it
  /// the process's `DV.Analytics`.
  ///
  /// Returns at once. The database is opened, the install id read or made,
  /// the stored consent loaded, Feature Flags connected when
  /// [DVAnalyticsSettings.flagExposureCategory] is set, and the analytics
  /// adapters installed into [DVPrivacyRuntime] -- in that order, and before
  /// any tracked event is judged.
  static DVAnalyticsRuntime start({
    required DVAnalyticsSettings settings,
    required FutureOr<DVDatabaseAdapter> Function() database,
    List<DVAnalyticsProvider> providers = const <DVAnalyticsProvider>[],
    Set<String> sensitiveFields = const <String>{},
  }) {
    final DVAnalyticsRuntime runtime =
        DVAnalyticsRuntime._(settings, providers, sensitiveFields);
    _current = runtime;
    // Handled here so a pipeline that cannot start is reported through
    // track's result rather than as an unhandled error in the zone.
    unawaited(runtime._pipeline.future.then((_) {}, onError: (Object _) {}));
    unawaited(runtime._start(database));
    return runtime;
  }

  Future<void> _start(FutureOr<DVDatabaseAdapter> Function() open) async {
    try {
      final DVDatabaseAdapter db = await open();
      final DVConsent consent = DVConsent(
        policy: settings.consent,
        database: db,
        installId: await _installId(db),
      );
      await consent.ensureSchema();
      final DVAnalytics analytics = DVAnalytics(
        consent: consent,
        database: db,
        store: DVAnalyticsDatabaseStore(database: db),
        providers: _providers,
        sensitiveFields: _sensitiveFields,
        sessionCap: settings.sessionCap,
      );
      await analytics.ensureSchema();
      await consent.load();
      final DVConsentCategory? flags = settings.flagExposureCategory;
      if (flags != null) analytics.connectFlags(category: flags);
      DVPrivacyRuntime.installAdapters(analytics.privacyAdapters());
      _ready = analytics;
      _pipeline.complete(analytics);
      for (final void Function() listener
          in List<void Function()>.of(_readyListeners)) {
        listener();
      }
    } on Object catch (error, stack) {
      DVObservability.log(
        'analytics could not start; events are dropped until it does',
        level: DVLogLevel.error,
        error: error,
      );
      _pipeline.completeError(error, stack);
    }
  }

  static Future<String> _installId(DVDatabaseAdapter db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS ${DVAnalytics.identityTable} '
        '(id, value)');
    final List<Map<String, Object?>> rows = await db.query(
        'SELECT value FROM ${DVAnalytics.identityTable} WHERE id = ?',
        <Object?>[installIdKey]);
    if (rows.isNotEmpty) return '${rows.first['value']}';
    final String id = dvAnalyticsRandomId();
    await db.execute(
        'INSERT INTO ${DVAnalytics.identityTable} (id, value) VALUES (?, ?)',
        <Object?>[installIdKey, id]);
    return id;
  }

  /// Completes once the stored consent has been read; with an error when the
  /// pipeline could not start.
  Future<void> get ready => _pipeline.future;

  /// The pipeline, once [ready].
  Future<DVAnalytics> get pipeline => _pipeline.future;

  /// Consent, once it has been read.
  Future<DVConsent> get consent async => (await pipeline).consent;

  /// Consent when it has already been read, and null before: for a widget
  /// that must not show a choice it cannot yet know the answer to.
  DVConsent? get loadedConsent => _ready?.consent;

  /// Calls [listener] once consent has been read. Called at once when it
  /// already has been.
  void whenReady(void Function() listener) {
    if (_ready != null) {
      listener();
      return;
    }
    _readyListeners.add(listener);
  }

  /// Checks consent, once it has been read, and queues [event].
  ///
  /// Never records anything a pipeline that could not start was asked to:
  /// the event is dropped and the result says why.
  Future<DVTrackResult> track(DVAnalyticsEvent event) async {
    final DVAnalytics analytics;
    try {
      analytics = await pipeline;
    } on Object catch (error) {
      return DVTrackResult.refused(reason: 'analytics could not start: $error');
    }
    return analytics.track(event);
  }

  /// Sets who later events belong to. See [DVAnalytics.identify].
  Future<void> identify(String? userId) async =>
      (await pipeline).identify(userId);

  /// Delivers queued events. See [DVAnalytics.flush].
  Future<int> flush() async => (await pipeline).flush();
}

/// Erasure, export and retention for this process, as `DV.Privacy`.
///
/// Configured where there is a database and a signing key -- the generated
/// server, from `DARTVEL_PRIVACY_KEY` -- and given every adapter the
/// framework's own stores provide without the application listing them. An
/// erasure missing the analytics adapters reports success while the
/// subject's events and consent records are still where they were.
abstract final class DVPrivacyRuntime {
  /// The environment variable holding the signing key.
  static const String keyVariable = 'DARTVEL_PRIVACY_KEY';

  static _DVPrivacyConfiguration? _configuration;
  static final Map<String, DVPrivacyAdapter> _installed =
      <String, DVPrivacyAdapter>{};
  static DVPrivacy? _built;

  /// Configures `DV.Privacy`. Declarations that cannot be honoured throw
  /// here ([DVPrivacyDeclarationError]) rather than at the first erasure.
  static void configure({
    required List<DVPrivacyModel> models,
    required DVDatabaseAdapter database,
    required List<int> signingKey,
    List<DVPrivacyAdapter> adapters = const <DVPrivacyAdapter>[],
    Duration deadline = const Duration(days: 30),
  }) {
    final _DVPrivacyConfiguration? previous = _configuration;
    _configuration = _DVPrivacyConfiguration(
        models, database, signingKey, adapters, deadline);
    try {
      _built = _build();
    } on Object {
      // A refused configuration leaves the last good one in force.
      _configuration = previous;
      _built = null;
      rethrow;
    }
  }

  /// Configures `DV.Privacy` from [keyVariable] in [environment].
  ///
  /// Returns false, configuring nothing, when the variable is not set:
  /// `DV.Privacy` then throws naming it. A key that is set and unusable is
  /// an error rather than a reason to carry on without one.
  static bool configureFromEnvironment({
    required Map<String, String> environment,
    required DVDatabaseAdapter? database,
    required List<DVPrivacyModel> models,
    Duration deadline = const Duration(days: 30),
  }) {
    final String? raw = environment[keyVariable]?.trim();
    if (raw == null || raw.isEmpty) return false;
    final List<int> key = dvPrivacyKeyFrom(raw);
    if (database == null) {
      throw StateError('$keyVariable is set and this process has no database '
          'for DV.Privacy to walk. Configure DV.Database or DATABASE_URL.');
    }
    configure(
        models: models, database: database, signingKey: key, deadline: deadline);
    return true;
  }

  /// Adds [adapters] to every `DV.Privacy` from now on, replacing any of the
  /// same name. Called by the framework's own stores as they start, so an
  /// adapter is installed whichever of the two is configured first.
  static void installAdapters(Iterable<DVPrivacyAdapter> adapters) {
    for (final DVPrivacyAdapter adapter in adapters) {
      _installed[adapter.name] = adapter;
    }
    _built = null;
  }

  /// Whether `DV.Privacy` is configured in this process.
  static bool get isConfigured => _configuration != null;

  /// The configured [DVPrivacy], with every installed adapter.
  static DVPrivacy get current {
    if (_configuration == null) {
      throw StateError(
          'DV.Privacy is not configured. Set $keyVariable -- at least 32 '
          'random bytes, as hex or base64 -- in the server environment; it '
          'signs erasure receipts and derives the pseudonyms records are kept '
          'under, so it has no default.');
    }
    return _built ??= _build();
  }

  static DVPrivacy _build() {
    final _DVPrivacyConfiguration c = _configuration!;
    final Map<String, DVPrivacyAdapter> adapters = <String, DVPrivacyAdapter>{
      ..._installed,
      // The application's own adapters win over a framework one of the same
      // name: it configured that one deliberately.
      for (final DVPrivacyAdapter a in c.adapters) a.name: a,
    };
    return DVPrivacy(
      models: c.models,
      database: c.database,
      signingKey: c.signingKey,
      adapters: adapters.values.toList(),
      deadline: c.deadline,
    );
  }

  /// Forgets the configuration and installed adapters, for tests.
  static void resetForTest() {
    _configuration = null;
    _installed.clear();
    _built = null;
  }
}

final class _DVPrivacyConfiguration {
  const _DVPrivacyConfiguration(
      this.models, this.database, this.signingKey, this.adapters, this.deadline);

  final List<DVPrivacyModel> models;
  final DVDatabaseAdapter database;
  final List<int> signingKey;
  final List<DVPrivacyAdapter> adapters;
  final Duration deadline;
}

/// The bytes of a privacy signing key written as hex or base64.
///
/// Throws [StateError] for anything shorter than 32 bytes, naming
/// [DVPrivacyRuntime.keyVariable]: a short key would still sign and still
/// derive pseudonyms, just ones somebody could reverse.
List<int> dvPrivacyKeyFrom(String raw) {
  final String text = raw.trim();
  List<int>? bytes;
  if (RegExp(r'^(?:[0-9a-fA-F]{2})+$').hasMatch(text)) {
    bytes = <int>[
      for (int i = 0; i < text.length; i += 2)
        int.parse(text.substring(i, i + 2), radix: 16),
    ];
  } else {
    try {
      bytes = base64.decode(base64.normalize(text.replaceAll('-', '+')
          .replaceAll('_', '/')));
    } on FormatException {
      bytes = null;
    }
  }
  if (bytes == null || bytes.length < 32) {
    throw StateError('${DVPrivacyRuntime.keyVariable} must decode, as hex or '
        'base64, to at least 32 bytes'
        '${bytes == null ? '' : '; it decodes to ${bytes.length}'}.');
  }
  return bytes;
}
