/// `dartvel.deepLinks`: Android App Links and iOS Universal Links.
///
/// A link to the application's site opens the application only after the
/// platform has fetched a JSON document from that site and found the
/// application named in it: `/.well-known/assetlinks.json` for Android,
/// `/.well-known/apple-app-site-association` for iOS. Both are functions of
/// what Dartvel already holds -- the route index and the application
/// identifiers -- so the build writes them, and the paths in them come from
/// the routes rather than from a second copy of the routing table that no
/// compiler reads.
///
/// ```yaml
/// dartvel:
///   deepLinks:
///     domains: [example.com, www.example.com]
///     android:
///       package: com.example.app
///       fingerprints: [14:6D:...:E5]     # or playAppSigning
///     ios:
///       appId: ABCDE12345.com.example.app
///     exclude: [/admin/**, /account/**]
/// ```
library;

import 'dart:convert';

/// The declared deep-link configuration.
class DVDeepLinks {
  const DVDeepLinks({
    required this.domains,
    this.androidPackage,
    this.androidFingerprints = const <String>[],
    this.playAppSigning = false,
    this.iosAppId,
    this.exclude = const <String>[],
  });

  /// Hosts the links point at, without a scheme: `example.com`.
  final List<String> domains;

  final String? androidPackage;

  /// SHA-256 certificate fingerprints, colon-separated upper-case hex.
  ///
  /// Under [playAppSigning], the Play signing certificate the project names:
  /// Google re-signs the binary it serves, so the certificate that matters
  /// is not the one on the machine that built it.
  final List<String> androidFingerprints;

  /// `fingerprints: playAppSigning`.
  final bool playAppSigning;

  /// `TEAMID.bundle.id`.
  final String? iosAppId;

  /// Route patterns the links never claim, `**` for any depth.
  final List<String> exclude;

  static const Set<String> _keys = <String>{
    'domains',
    'android',
    'ios',
    'exclude',
  };
  static const Set<String> _androidKeys = <String>{
    'package',
    'fingerprints',
    'playSigningCertificate',
  };
  static const Set<String> _iosKeys = <String>{'appId'};

  static final RegExp _sha256 = RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$');
  static final RegExp _host = RegExp(
    r'^(\*\.)?[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$',
  );

  /// `dartvel.deepLinks`, or null when nothing is declared.
  ///
  /// Throws [FormatException] for a key nothing reads or a value no platform
  /// accepts: a misspelt key would otherwise be a link file that silently
  /// leaves the application out.
  static DVDeepLinks? parse(Object? yaml) {
    if (yaml == null) return null;
    if (yaml is! Map) {
      throw const FormatException('dartvel.deepLinks must be a map.');
    }
    _refuseUnknown(yaml, _keys, 'dartvel.deepLinks');
    final List<String> domains = _strings(yaml['domains'], 'domains');
    for (final String domain in domains) {
      if (!_host.hasMatch(domain)) {
        throw FormatException(
          'dartvel.deepLinks.domains: "$domain" is not a host. Write the '
          'domain alone, as example.com, with no scheme, port or path.',
        );
      }
    }
    String? package;
    List<String> fingerprints = const <String>[];
    bool play = false;
    final Object? android = yaml['android'];
    if (android != null) {
      if (android is! Map) {
        throw const FormatException('dartvel.deepLinks.android must be a map.');
      }
      _refuseUnknown(android, _androidKeys, 'dartvel.deepLinks.android');
      package = android['package']?.toString();
      final Object? declared = android['fingerprints'];
      if (declared == 'playAppSigning') {
        play = true;
        final Object? certificate = android['playSigningCertificate'];
        fingerprints = certificate == null
            ? const <String>[]
            : <String>[_fingerprint(certificate.toString())];
      } else if (declared != null) {
        fingerprints = <String>[
          for (final String f in _strings(declared, 'android.fingerprints'))
            _fingerprint(f),
        ];
      }
    }
    String? appId;
    final Object? ios = yaml['ios'];
    if (ios != null) {
      if (ios is! Map) {
        throw const FormatException('dartvel.deepLinks.ios must be a map.');
      }
      _refuseUnknown(ios, _iosKeys, 'dartvel.deepLinks.ios');
      appId = ios['appId']?.toString();
    }
    return DVDeepLinks(
      domains: domains,
      androidPackage: package,
      androidFingerprints: fingerprints,
      playAppSigning: play,
      iosAppId: appId,
      exclude: yaml['exclude'] == null
          ? const <String>[]
          : _strings(yaml['exclude'], 'exclude'),
    );
  }

  /// `DV-LINKS-001` for each of [targets] the application builds that the
  /// declaration gives no identity for.
  List<String> missingIdentifiers(Set<String> targets) {
    if (domains.isEmpty) return const <String>[];
    final List<String> errors = <String>[];
    if (targets.contains('android')) {
      final List<String> missing = <String>[
        if (androidPackage == null) 'android.package',
        if (androidFingerprints.isEmpty)
          playAppSigning
              ? 'android.playSigningCertificate (the SHA-256 Play Console '
                    'shows under App signing)'
              : 'android.fingerprints',
      ];
      if (missing.isNotEmpty) {
        errors.add(
          'DV-LINKS-001: dartvel.deepLinks declares domains and the android '
          'target has no ${missing.join(' or ')}. Without it assetlinks.json '
          'names no application, and every link opens the browser.',
        );
      }
    }
    if (targets.contains('ios') && iosAppId == null) {
      errors.add(
        'DV-LINKS-001: dartvel.deepLinks declares domains and the ios target '
        'has no ios.appId (TEAMID.bundle.id). Without it '
        'apple-app-site-association names no application, and every link '
        'opens Safari.',
      );
    }
    return errors;
  }

  /// The paths the links claim, from the route index: every route except
  /// the [guarded] ones -- which the sitemap leaves out by the same rule --
  /// and the [exclude]d ones, with parameters as `*`.
  List<String> paths({
    required Iterable<String> routes,
    Set<String> guarded = const <String>{},
  }) {
    final List<String> out = <String>[];
    for (final String route in routes) {
      if (guarded.contains(route)) continue;
      if (exclude.any((String pattern) => _excluded(pattern, route))) continue;
      final String path = route
          .split('/')
          .map((String s) => s.startsWith(':') || s.startsWith('*') ? '*' : s)
          .join('/');
      final String normal = path.isEmpty ? '/' : path;
      if (!out.contains(normal)) out.add(normal);
    }
    return out;
  }

  /// `/.well-known/assetlinks.json`, or null without an Android identity.
  String? assetLinks() {
    if (androidPackage == null || androidFingerprints.isEmpty) return null;
    return const JsonEncoder.withIndent('  ').convert(<Object?>[
      <String, Object?>{
        'relation': <String>['delegate_permission/common.handle_all_urls'],
        'target': <String, Object?>{
          'namespace': 'android_app',
          'package_name': androidPackage,
          'sha256_cert_fingerprints': androidFingerprints,
        },
      },
    ]);
  }

  /// `/.well-known/apple-app-site-association` claiming [paths], or null
  /// without an iOS identity.
  String? appleAppSiteAssociation(List<String> paths) {
    final String? appId = iosAppId;
    if (appId == null) return null;
    return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'applinks': <String, Object?>{
        'details': <Object?>[
          <String, Object?>{
            'appIDs': <String>[appId],
            'components': <Object?>[
              for (final String path in paths) <String, Object?>{'/': path},
            ],
          },
        ],
      },
    });
  }

  static bool _excluded(String pattern, String route) {
    if (pattern.endsWith('/**')) {
      final String base = pattern.substring(0, pattern.length - 3);
      return route == base || route.startsWith('$base/');
    }
    return pattern == route;
  }

  static String _fingerprint(String value) {
    final String upper = value.trim().toUpperCase();
    if (!_sha256.hasMatch(upper)) {
      throw FormatException(
        'dartvel.deepLinks.android: "$value" is not a SHA-256 certificate '
        'fingerprint, 32 colon-separated hex bytes as keytool prints it.',
      );
    }
    return upper;
  }

  static void _refuseUnknown(
    Map<Object?, Object?> map,
    Set<String> known,
    String where,
  ) {
    for (final Object? key in map.keys) {
      if (!known.contains(key)) {
        throw FormatException(
          '$where.$key is not a setting. The settings are '
          '${known.join(', ')}.',
        );
      }
    }
  }

  static List<String> _strings(Object? value, String key) {
    if (value is String) return <String>[value];
    if (value is Iterable) {
      return <String>[for (final Object? v in value) '$v'];
    }
    throw FormatException('dartvel.deepLinks.$key must be a list.');
  }
}

/// Whether the platform opens [route] in the application for a served
/// [path]: `*` matches the rest of a segment, and anything after it.
bool dvDeepLinkCovers(String path, String route) {
  final String pattern = '^${RegExp.escape(path).replaceAll(r'\*', '.*')}\$';
  return RegExp(pattern).hasMatch(route);
}
