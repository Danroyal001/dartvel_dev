import 'package:dartvel_core/dartvel.dart';

/// How page views reach Google Analytics in a browser.
enum GoogleAnalyticsPageViews {
  /// The module sends a `page_view` for the first page and for each route
  /// change. Turn off "Page changes based on browser history events" in the
  /// web stream's Enhanced Measurement settings, or Google Analytics counts
  /// each route change twice: once from the module and once from its own
  /// listener on the browser's history.
  manual,

  /// Google's tag sends them: one when it loads, and one per history change
  /// when Enhanced Measurement is on. The module sends none in a browser.
  automatic,

  /// No page views at all.
  off,
}

/// How the Google Analytics module is set up.
///
/// The same settings whichever way they are written: under
/// `dartvel.modules.googleAnalytics.config` in `pubspec.yaml`, or as this
/// class passed to `DV.Modules.googleAnalytics.configure(...)`.
///
/// The measurement id is public: it is in the page's own requests to
/// Google. The Measurement Protocol API secret is not, and is never one of
/// these settings: it is read from the server's environment by the name
/// [apiSecretName] and exists only in the backend process.
final class GoogleAnalyticsConfig {
  const GoogleAnalyticsConfig({
    this.measurementId,
    this.consentCategory = defaultConsentCategory,
    this.pageViews = GoogleAnalyticsPageViews.manual,
    this.apiSecretName = defaultApiSecretName,
    this.collectInEu = false,
    this.origin,
    this.excludedPaths = defaultExcludedPaths,
  });

  /// The consent category the module waits for, unless the application
  /// names another.
  static const String defaultConsentCategory = 'product';

  /// The environment variable the Measurement Protocol API secret is read
  /// from.
  static const String defaultApiSecretName = 'GA4_API_SECRET';

  /// The environment variable the server reads the measurement id from when
  /// neither the mount nor a [GoogleAnalyticsConfig] gives one.
  static const String measurementIdVariable = 'GA4_MEASUREMENT_ID';

  /// Pages that are the framework's rather than the application's.
  static const List<String> defaultExcludedPaths = <String>['/__studio'];

  /// The web stream's measurement id: `G-` and letters and digits.
  final String? measurementId;

  /// The consent category (`dartvel.analytics.consent.categories`) that must
  /// be granted before anything is sent.
  final String consentCategory;

  final GoogleAnalyticsPageViews pageViews;

  /// The name of the secret holding the Measurement Protocol API secret.
  final String apiSecretName;

  /// Sends Measurement Protocol events to `region1.google-analytics.com`,
  /// which Google documents for data to be collected in the EU.
  final bool collectInEu;

  /// The address a device's pages are reported under, such as
  /// `https://example.com`. A device has no page address of its own, and
  /// Google Analytics requires `page_location` to be a full URL.
  final String? origin;

  /// Paths, and everything beneath them, that are not page views.
  final List<String> excludedPaths;

  /// This configuration with some settings replaced.
  GoogleAnalyticsConfig copyWith({
    String? measurementId,
    String? consentCategory,
    GoogleAnalyticsPageViews? pageViews,
    bool? collectInEu,
    String? origin,
  }) =>
      GoogleAnalyticsConfig(
        measurementId: measurementId ?? this.measurementId,
        consentCategory: consentCategory ?? this.consentCategory,
        pageViews: pageViews ?? this.pageViews,
        apiSecretName: apiSecretName,
        collectInEu: collectInEu ?? this.collectInEu,
        origin: origin ?? this.origin,
        excludedPaths: excludedPaths,
      );

  /// The measurement id this process uses: the configured one, or the
  /// server's `GA4_MEASUREMENT_ID`.
  String? get resolvedMeasurementId {
    final String? configured = measurementId?.trim();
    if (configured != null && configured.isNotEmpty) return configured;
    return const DVSecrets().maybeGet(measurementIdVariable)?.trim();
  }

  /// Whether there is a usable measurement id. Without one every call does
  /// nothing.
  bool get isConfigured {
    final String? id = resolvedMeasurementId;
    return id != null && RegExp(r'^G-[A-Z0-9]{4,20}$').hasMatch(id);
  }

  /// Whether [path] is one of the [excludedPaths] or beneath one.
  bool excludes(String path) => excludedPaths.any((String excluded) =>
      path == excluded || path.startsWith('$excluded/'));

  /// Reads `dartvel.modules.<id>.config`.
  ///
  /// Strict about names: a key it does not know is an [ArgumentError]
  /// rather than a setting the pubspec states and nothing applies. A key
  /// that looks like the API secret is refused by name, because a mount's
  /// config is compiled into the client.
  factory GoogleAnalyticsConfig.fromModuleConfig(Map<String, Object?> config) {
    const Set<String> known = <String>{
      'measurementId',
      'consent',
      'pageViews',
      'apiSecretName',
      'collectInEu',
      'origin',
      'excludePaths',
    };
    for (final String key in config.keys) {
      if (const <String>{'apiSecret', 'api_secret', 'secret'}.contains(key)) {
        throw ArgumentError(
          'dartvel.modules.googleAnalytics.config.$key: the Measurement '
          'Protocol API secret is not a setting. A mount\'s config is '
          'compiled into the client; set $defaultApiSecretName in the '
          'server\'s environment instead.',
        );
      }
      if (!known.contains(key)) {
        throw ArgumentError(
          'dartvel.modules.googleAnalytics.config.$key is not a setting. '
          'The settings are ${known.join(', ')}.',
        );
      }
    }
    final Object? pageViews = config['pageViews'];
    final GoogleAnalyticsPageViews mode = switch (pageViews) {
      null || 'manual' => GoogleAnalyticsPageViews.manual,
      'automatic' => GoogleAnalyticsPageViews.automatic,
      'off' || false => GoogleAnalyticsPageViews.off,
      _ => throw ArgumentError(
          'dartvel.modules.googleAnalytics.config.pageViews is "$pageViews"; '
          'it is manual, automatic or off.'),
    };
    final Object? excluded = config['excludePaths'];
    return GoogleAnalyticsConfig(
      measurementId:
          config['measurementId'] == null ? null : '${config['measurementId']}',
      consentCategory: '${config['consent'] ?? defaultConsentCategory}',
      pageViews: mode,
      apiSecretName: '${config['apiSecretName'] ?? defaultApiSecretName}',
      collectInEu: config['collectInEu'] == true,
      origin: config['origin'] == null ? null : '${config['origin']}',
      excludedPaths: excluded is List
          ? <String>[for (final Object? path in excluded) '$path']
          : defaultExcludedPaths,
    );
  }
}
