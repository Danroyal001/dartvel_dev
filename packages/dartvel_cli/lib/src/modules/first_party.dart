/// The modules Dartvel maintains itself.
///
/// They live in this repository's `modules/` folder, one package each, and
/// are published to pub.dev with every release. A first-party module is a
/// normal module, checked like any other against the grant the application
/// writes; it is not pinned when it resolves with the framework itself (see
/// module_trust.dart). What the catalogue adds is that
/// `dartvel add <name>` knows the package, the id and the policy its carried
/// operations need, so nobody has to look them up.
///
/// The catalogue and the folder are kept in step by a test
/// (`test/add_first_party_test.dart`): a package in one and not the other
/// fails it.
library;

/// One first-party module, as `dartvel add` installs it.
class DVFirstPartyModule {
  const DVFirstPartyModule({
    required this.name,
    required this.package,
    required this.id,
    required this.summary,
    this.aliases = const <String>[],
    this.backendPolicy,
    this.settings = const <String>[],
    this.secrets = const <String>[],
    this.egress = const <String>[],
  });

  /// What it is added as: `dartvel add <name>`.
  final String name;

  /// Other names people call it by.
  final List<String> aliases;

  /// The pub package.
  final String package;

  /// What the application reaches it as: `DV.Modules.<id>`.
  final String id;

  /// One line for the installation plan.
  final String summary;

  /// Written as the mount's `backendPolicy` when the module carries
  /// operations to the backend, or null when it carries none.
  ///
  /// `public` is the only honest value for a module whose callers are
  /// visitors nobody has signed in: an analytics event, a checkout. The
  /// module's own README says what each carried operation accepts.
  final String? backendPolicy;

  /// The settings the mount's `config:` takes, for the plan.
  final List<String> settings;

  /// The names of the secrets the server's environment supplies, for the
  /// plan. Names only: values are never written into a pubspec.
  final List<String> secrets;

  /// The hosts its code calls, as a grant names them: a bare domain each.
  /// With [secrets], what `dartvel add` writes as the mount's `grant:`.
  final List<String> egress;
}

/// Every first-party module, in the order the docs list them.
const List<DVFirstPartyModule> dvFirstPartyModules = <DVFirstPartyModule>[
  DVFirstPartyModule(
    name: 'meta-pixel',
    aliases: <String>['facebook-pixel', 'meta_pixel', 'facebook_pixel', 'pixel'],
    package: 'dartvel_meta_pixel',
    id: 'metaPixel',
    summary: 'Meta (Facebook) Pixel and Conversions API',
    backendPolicy: 'public',
    settings: <String>['pixelId', 'consent'],
    secrets: <String>['META_PIXEL_ID', 'META_CONVERSIONS_API_TOKEN'],
    egress: <String>['graph.facebook.com'],
  ),
  DVFirstPartyModule(
    name: 'google-analytics',
    aliases: <String>['ga4', 'google_analytics', 'analytics', 'gtag'],
    package: 'dartvel_google_analytics',
    id: 'googleAnalytics',
    summary: 'Google Analytics 4: gtag on the web, Measurement Protocol '
        'everywhere else',
    backendPolicy: 'public',
    settings: <String>['measurementId', 'consent'],
    secrets: <String>['GA4_MEASUREMENT_ID', 'GA4_API_SECRET'],
    egress: <String>[
      'www.google-analytics.com',
      'region1.google-analytics.com',
    ],
  ),
  DVFirstPartyModule(
    name: 'woocommerce',
    aliases: <String>['woo', 'woo-commerce'],
    package: 'dartvel_woocommerce',
    id: 'woocommerce',
    summary: 'WooCommerce: catalogue, orders and checkout through the '
        'store\'s own payment gateways',
    backendPolicy: 'public',
    settings: <String>['storeUrl'],
    secrets: <String>[
      'WOOCOMMERCE_CONSUMER_KEY',
      'WOOCOMMERCE_CONSUMER_SECRET',
      'WOOCOMMERCE_WEBHOOK_SECRET',
    ],
  ),
];

/// The first-party module [name] names, by its name, an alias or its
/// package, whatever the case; or null.
DVFirstPartyModule? dvFirstPartyModule(String name) {
  final String wanted = name.trim().toLowerCase();
  for (final DVFirstPartyModule module in dvFirstPartyModules) {
    if (module.name == wanted ||
        module.package == wanted ||
        module.aliases.contains(wanted)) {
      return module;
    }
  }
  return null;
}
