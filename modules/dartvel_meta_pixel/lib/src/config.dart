import 'package:dartvel_core/dartvel.dart';

/// How the Meta Pixel module is set up.
///
/// The same settings whichever way they are written: under
/// `dartvel.modules.metaPixel.config` in `pubspec.yaml`, or as this class
/// passed to `DV.Modules.metaPixel.configure(...)`.
///
/// The pixel id is public: it is in the page's own requests to Meta. The
/// Conversions API access token is not, and is never one of these settings:
/// it is read from the server's environment by the name [accessTokenSecret]
/// and exists only in the backend process.
final class MetaPixelConfig {
  const MetaPixelConfig({
    this.pixelId,
    this.consentCategory = defaultConsentCategory,
    this.serverEvents = true,
    this.accessTokenSecret = defaultAccessTokenSecret,
    this.apiVersion = defaultApiVersion,
    this.testEventCode,
    this.excludedPaths = defaultExcludedPaths,
  });

  /// The consent category the pixel waits for, unless the application names
  /// another.
  static const String defaultConsentCategory = 'marketing';

  /// The environment variable the Conversions API access token is read from.
  static const String defaultAccessTokenSecret = 'META_CONVERSIONS_API_TOKEN';

  /// The environment variable the server reads the pixel id from when
  /// neither the mount nor a [MetaPixelConfig] gives one.
  static const String pixelIdVariable = 'META_PIXEL_ID';

  /// The Graph API version events are posted to: the one Meta's Conversions
  /// API documentation showed on 14 Nov 2026.
  static const String defaultApiVersion = 'v27.0';

  /// Pages that are the framework's rather than the application's.
  static const List<String> defaultExcludedPaths = <String>['/__studio'];

  /// The pixel's id, from Events Manager: digits only.
  final String? pixelId;

  /// The consent category (`dartvel.analytics.consent.categories`) that must
  /// be granted before anything is sent.
  final String consentCategory;

  /// Whether a client's events are also sent through the application's
  /// backend to the Conversions API, with the same event id as the browser's.
  final bool serverEvents;

  /// The name of the secret holding the Conversions API access token.
  final String accessTokenSecret;

  final String apiVersion;

  /// Events Manager's test code. Events sent with it appear under Test
  /// Events and nowhere else; leave it unset in production.
  final String? testEventCode;

  /// Paths, and everything beneath them, that are not page views.
  final List<String> excludedPaths;

  /// This configuration with some settings replaced.
  MetaPixelConfig copyWith({
    String? pixelId,
    String? consentCategory,
    bool? serverEvents,
    String? testEventCode,
  }) =>
      MetaPixelConfig(
        pixelId: pixelId ?? this.pixelId,
        consentCategory: consentCategory ?? this.consentCategory,
        serverEvents: serverEvents ?? this.serverEvents,
        accessTokenSecret: accessTokenSecret,
        apiVersion: apiVersion,
        testEventCode: testEventCode ?? this.testEventCode,
        excludedPaths: excludedPaths,
      );

  /// The pixel id this process uses: the configured one, or the server's
  /// `META_PIXEL_ID`.
  String? get resolvedPixelId {
    final String? configured = pixelId?.trim();
    if (configured != null && configured.isNotEmpty) return configured;
    return const DVSecrets().maybeGet(pixelIdVariable)?.trim();
  }

  /// Whether there is a usable pixel id. Without one every call does
  /// nothing.
  bool get isConfigured {
    final String? id = resolvedPixelId;
    return id != null && RegExp(r'^\d{5,24}$').hasMatch(id);
  }

  /// Whether [path] is one of the [excludedPaths] or beneath one.
  bool excludes(String path) => excludedPaths.any((String excluded) =>
      path == excluded || path.startsWith('$excluded/'));

  /// Reads `dartvel.modules.<id>.config`.
  ///
  /// Strict about names: a key it does not know is an [ArgumentError]
  /// rather than a setting the pubspec states and nothing applies. A key
  /// that looks like the access token is refused by name, because a mount's
  /// config is compiled into the client.
  factory MetaPixelConfig.fromModuleConfig(Map<String, Object?> config) {
    const Set<String> known = <String>{
      'pixelId',
      'consent',
      'serverEvents',
      'accessTokenSecret',
      'apiVersion',
      'testEventCode',
      'excludePaths',
    };
    for (final String key in config.keys) {
      if (const <String>{'accessToken', 'token', 'access_token'}
          .contains(key)) {
        throw ArgumentError(
          'dartvel.modules.metaPixel.config.$key: the Conversions API access '
          'token is not a setting. A mount\'s config is compiled into the '
          'client; set $defaultAccessTokenSecret in the server\'s '
          'environment instead.',
        );
      }
      if (!known.contains(key)) {
        throw ArgumentError(
          'dartvel.modules.metaPixel.config.$key is not a setting. The '
          'settings are ${known.join(', ')}.',
        );
      }
    }
    final Object? excluded = config['excludePaths'];
    return MetaPixelConfig(
      pixelId: config['pixelId'] == null ? null : '${config['pixelId']}',
      consentCategory: '${config['consent'] ?? defaultConsentCategory}',
      serverEvents: config['serverEvents'] != false,
      accessTokenSecret:
          '${config['accessTokenSecret'] ?? defaultAccessTokenSecret}',
      apiVersion: '${config['apiVersion'] ?? defaultApiVersion}',
      testEventCode:
          config['testEventCode'] == null ? null : '${config['testEventCode']}',
      excludedPaths: excluded is List
          ? <String>[for (final Object? path in excluded) '$path']
          : defaultExcludedPaths,
    );
  }
}
