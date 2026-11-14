import 'package:dartvel_core/dartvel.dart';

/// How the WooCommerce module is set up.
///
/// The same settings whichever way they are written: under
/// `dartvel.modules.woocommerce.config` in `pubspec.yaml`, or as this class
/// passed to `DV.Modules.woocommerce.configure(...)`.
///
/// The store's consumer key, consumer secret and webhook secret are never
/// settings. They are read from the server's environment by the names here,
/// and exist only in the backend process: a client asks the application's
/// backend, and the backend asks the store.
final class WooCommerceConfig {
  const WooCommerceConfig({
    this.storeUrl,
    this.consumerKeyName = defaultConsumerKeyName,
    this.consumerSecretName = defaultConsumerSecretName,
    this.webhookSecretName = defaultWebhookSecretName,
    this.paidStatuses = defaultPaidStatuses,
    this.pollInterval = const Duration(seconds: 5),
    this.pollTimeout = const Duration(minutes: 20),
  });

  static const String defaultConsumerKeyName = 'WOOCOMMERCE_CONSUMER_KEY';
  static const String defaultConsumerSecretName = 'WOOCOMMERCE_CONSUMER_SECRET';
  static const String defaultWebhookSecretName = 'WOOCOMMERCE_WEBHOOK_SECRET';

  /// The environment variable the server reads the store's address from
  /// when neither the mount nor a [WooCommerceConfig] gives one.
  static const String storeUrlVariable = 'WOOCOMMERCE_URL';

  /// The statuses WooCommerce itself counts as paid
  /// (`wc_get_is_paid_statuses`).
  static const Set<String> defaultPaidStatuses = <String>{
    'processing',
    'completed',
  };

  /// The statuses after which an unpaid order will not become paid by
  /// itself.
  static const Set<String> endedStatuses = <String>{
    'failed',
    'cancelled',
    'refunded',
    'trash',
  };

  /// The store's address: `https://shop.example.com`, with the folder
  /// WordPress is in when it is in one.
  final String? storeUrl;

  final String consumerKeyName;
  final String consumerSecretName;
  final String webhookSecretName;

  /// The order statuses that mean the money has arrived.
  final Set<String> paidStatuses;

  /// How often a watched order is asked about.
  final Duration pollInterval;

  /// How long a watched order is asked about before giving up.
  final Duration pollTimeout;

  /// The store address this process uses: the configured one, or the
  /// server's `WOOCOMMERCE_URL`, without a trailing slash.
  String? get resolvedStoreUrl {
    final String? configured = storeUrl?.trim();
    final String? url = configured != null && configured.isNotEmpty
        ? configured
        : const DVSecrets().maybeGet(storeUrlVariable)?.trim();
    return url?.replaceFirst(RegExp(r'/+$'), '');
  }

  /// The webhook's address path on the application's backend.
  static const String webhookPath = '/_dartvel/woocommerce/webhook';

  /// Reads `dartvel.modules.<id>.config`.
  ///
  /// Strict about names: a key it does not know is an [ArgumentError], and
  /// one that looks like a credential is refused by name, because a mount's
  /// config is compiled into the client.
  factory WooCommerceConfig.fromModuleConfig(Map<String, Object?> config) {
    const Set<String> known = <String>{
      'storeUrl',
      'consumerKeyName',
      'consumerSecretName',
      'webhookSecretName',
      'paidStatuses',
      'pollSeconds',
      'pollTimeoutMinutes',
    };
    for (final String key in config.keys) {
      if (const <String>{
        'consumerKey',
        'consumerSecret',
        'webhookSecret',
        'consumer_key',
        'consumer_secret',
        'secret',
        'key',
      }.contains(key)) {
        throw ArgumentError(
          'dartvel.modules.woocommerce.config.$key: the store\'s keys are '
          'not settings. A mount\'s config is compiled into the client; set '
          '$defaultConsumerKeyName, $defaultConsumerSecretName and '
          '$defaultWebhookSecretName in the server\'s environment instead.',
        );
      }
      if (!known.contains(key)) {
        throw ArgumentError(
          'dartvel.modules.woocommerce.config.$key is not a setting. The '
          'settings are ${known.join(', ')}.',
        );
      }
    }
    final Object? paid = config['paidStatuses'];
    final Object? seconds = config['pollSeconds'];
    final Object? minutes = config['pollTimeoutMinutes'];
    return WooCommerceConfig(
      storeUrl: config['storeUrl'] == null ? null : '${config['storeUrl']}',
      consumerKeyName: '${config['consumerKeyName'] ?? defaultConsumerKeyName}',
      consumerSecretName:
          '${config['consumerSecretName'] ?? defaultConsumerSecretName}',
      webhookSecretName:
          '${config['webhookSecretName'] ?? defaultWebhookSecretName}',
      paidStatuses: paid is List
          ? <String>{for (final Object? status in paid) '$status'}
          : defaultPaidStatuses,
      pollInterval:
          Duration(seconds: seconds is int && seconds > 0 ? seconds : 5),
      pollTimeout:
          Duration(minutes: minutes is int && minutes > 0 ? minutes : 20),
    );
  }
}
