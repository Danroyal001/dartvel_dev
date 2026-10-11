/// `dartvel.billing` in pubspec.yaml and [DVBillingConfig] in code: one
/// declaration of which provider bills, what each plan costs there and what
/// it grants.
///
/// Neither form holds a key. `apiKey` and `webhookSecret` name the secrets
/// that do, and [DVBillingConfig.createProvider] resolves them through
/// [DVSecrets] -- the process environment, then `.env` -- when the provider
/// is built, so a pubspec committed to a public repository carries nothing
/// worth stealing.
library dartvel.billing.config;

import '../../dartvel.dart' show Entitlement, DVBillingProvider;
import '../secrets/secrets.dart';
import 'bachs.dart';
import 'paddle.dart';
import 'stripe.dart';
import 'webhooks.dart';

/// The official billing adapters.
enum DVBillingProviderName { stripe, paddle, bachs }

/// Thrown for a `dartvel.billing` block the reader does not understand.
class DVBillingConfigException implements Exception {
  const DVBillingConfigException(this.message);
  final String message;
  String get code => 'DV-BILLING-001';

  @override
  String toString() => '$code: $message';
}

class DVBillingConfig {
  const DVBillingConfig({
    required this.provider,
    this.prices = const <String, String>{},
    this.entitlements = const <String, List<String>>{},
    String? apiKey,
    String? webhookSecret,
    this.successUrl,
    this.cancelUrl,
  })  : _apiKey = apiKey,
        _webhookSecret = webhookSecret;

  final DVBillingProviderName provider;

  /// Plan id to the provider's identifier for it: a Stripe `price_`, a
  /// Paddle `pri_`, a Bachs `prod_`.
  final Map<String, String> prices;

  /// Plan id to the entitlement ids a subscription to it grants.
  final Map<String, List<String>> entitlements;

  final String? _apiKey;
  final String? _webhookSecret;

  /// Where a provider that takes return URLs sends the customer after paying
  /// (Stripe, Bachs). Paddle's checkout settings live in its dashboard.
  final String? successUrl;
  final String? cancelUrl;

  /// The secret holding the API key, defaulting per provider.
  String get apiKeySecret => _apiKey ?? _defaultApiKey[provider]!;

  /// The secret holding the webhook signing secret, defaulting per provider.
  String get webhookSecretName =>
      _webhookSecret ?? _defaultWebhookSecret[provider]!;

  static const Map<DVBillingProviderName, String> _defaultApiKey =
      <DVBillingProviderName, String>{
    DVBillingProviderName.stripe: 'STRIPE_SECRET_KEY',
    DVBillingProviderName.paddle: 'PADDLE_API_KEY',
    DVBillingProviderName.bachs: 'BACHS_SECRET_KEY',
  };

  static const Map<DVBillingProviderName, String> _defaultWebhookSecret =
      <DVBillingProviderName, String>{
    DVBillingProviderName.stripe: 'STRIPE_WEBHOOK_SECRET',
    DVBillingProviderName.paddle: 'PADDLE_WEBHOOK_SECRET',
    DVBillingProviderName.bachs: 'BACHS_WEBHOOK_SECRET',
  };

  static const Set<String> _keys = <String>{
    'provider',
    'prices',
    'entitlements',
    'apiKey',
    'webhookSecret',
    'successUrl',
    'cancelUrl',
  };

  /// What a credential looks like when someone pastes the value where the
  /// name of a secret belongs.
  static final RegExp _credential = RegExp(
      r'^(sk_|rk_|pk_|whsec_|pdl_|apikey_|ntfset_)', caseSensitive: false);

  /// Reads [block], the value of `dartvel.billing`.
  ///
  /// Throws [DVBillingConfigException] naming the key for anything it does
  /// not understand, so a build that reads the block fails before it
  /// generates a server that would bill against the wrong thing.
  static DVBillingConfig read(Object? block) {
    if (block is! Map) {
      throw const DVBillingConfigException(
          'dartvel.billing must be a map with at least a provider.');
    }
    for (final Object? key in block.keys) {
      if (!_keys.contains('$key')) {
        throw DVBillingConfigException(
            'dartvel.billing.$key is not a setting. dartvel.billing takes '
            '${(_keys.toList()..sort()).join(', ')}.');
      }
    }
    final Object? written = block['provider'];
    DVBillingProviderName? provider;
    for (final DVBillingProviderName name in DVBillingProviderName.values) {
      if (name.name == '$written') provider = name;
    }
    if (provider == null) {
      throw DVBillingConfigException(
          'dartvel.billing.provider is one of '
          '${DVBillingProviderName.values.map((DVBillingProviderName n) => n.name).join(', ')}; '
          '"$written" is not.');
    }

    Map<String, String> strings(String key) {
      final Object? value = block[key];
      if (value == null) return const <String, String>{};
      if (value is! Map ||
          value.values.any((Object? v) => v is! String || v.isEmpty)) {
        throw DVBillingConfigException(
            'dartvel.billing.$key maps each plan id to the provider\'s id '
            'for it, as text.');
      }
      return <String, String>{
        for (final MapEntry<Object?, Object?> e in value.entries)
          '${e.key}': e.value! as String,
      };
    }

    final Map<String, String> prices = strings('prices');
    final Object? grants = block['entitlements'];
    final Map<String, List<String>> entitlements = <String, List<String>>{};
    if (grants != null) {
      if (grants is! Map) {
        throw const DVBillingConfigException(
            'dartvel.billing.entitlements maps each plan id to a list of '
            'entitlement ids.');
      }
      for (final MapEntry<Object?, Object?> e in grants.entries) {
        final Object? ids = e.value;
        if (ids is! List || ids.any((Object? id) => id is! String)) {
          throw DVBillingConfigException(
              'dartvel.billing.entitlements.${e.key} is a list of entitlement '
              'ids.');
        }
        if (!prices.containsKey('${e.key}')) {
          throw DVBillingConfigException(
              'dartvel.billing.entitlements.${e.key} grants for a plan with no '
              'entry in dartvel.billing.prices, so nothing could ever be '
              'bought to unlock it.');
        }
        entitlements['${e.key}'] = List<String>.unmodifiable(ids.cast<String>());
      }
    }

    String? secretName(String key) {
      final Object? value = block[key];
      if (value == null) return null;
      if (value is! String || value.isEmpty) {
        throw DVBillingConfigException(
            'dartvel.billing.$key names the secret that holds it.');
      }
      if (_credential.hasMatch(value)) {
        throw DVBillingConfigException(
            'dartvel.billing.$key names an environment variable, such as '
            '${key == 'apiKey' ? _defaultApiKey[provider] : _defaultWebhookSecret[provider]}, '
            'not the key itself. A key in pubspec.yaml is a key in version '
            'control; remove it, rotate it, and set the variable instead.');
      }
      return value;
    }

    String? url(String key) {
      final Object? value = block[key];
      if (value == null) return null;
      final Uri? parsed = value is String ? Uri.tryParse(value) : null;
      if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
        throw DVBillingConfigException(
            'dartvel.billing.$key is an absolute URL; "$value" is not.');
      }
      return value as String;
    }

    final String? success = url('successUrl');
    final String? cancel = url('cancelUrl');
    if (provider != DVBillingProviderName.paddle &&
        (success == null || cancel == null)) {
      throw DVBillingConfigException(
          '${provider.name} sends the customer back after checkout, so '
          'dartvel.billing needs successUrl and cancelUrl.');
    }

    return DVBillingConfig(
      provider: provider,
      prices: prices,
      entitlements: entitlements,
      apiKey: secretName('apiKey'),
      webhookSecret: secretName('webhookSecret'),
      successUrl: success,
      cancelUrl: cancel,
    );
  }

  /// The block this was read from, for the build to carry into the
  /// generated server and read again there.
  Map<String, Object?> toMap() => <String, Object?>{
        'provider': provider.name,
        'prices': prices,
        'entitlements': entitlements,
        'apiKey': apiKeySecret,
        'webhookSecret': webhookSecretName,
        if (successUrl != null) 'successUrl': successUrl,
        if (cancelUrl != null) 'cancelUrl': cancelUrl,
      };

  /// Builds the configured provider, resolving its secrets now.
  ///
  /// Throws [DVSecretNotFoundException] naming a secret that is not set.
  /// [fetch] is the HTTP transport; tests inject one, and an application
  /// passes its own until the providers are built on DV.Http.
  DVBillingProvider createProvider({DVBillingFetch? fetch}) {
    const DVSecrets secrets = DVSecrets();
    final String key = secrets.get(apiKeySecret);
    final String webhook = secrets.get(webhookSecretName);
    // Entitlements are declared per plan and kept by providers per provider
    // id, because that is what a webhook names.
    final Map<String, Set<Entitlement>> byProviderId =
        <String, Set<Entitlement>>{
      for (final MapEntry<String, List<String>> e in entitlements.entries)
        prices[e.key]!: <Entitlement>{
          for (final String id in e.value) Entitlement(id),
        },
    };
    switch (provider) {
      case DVBillingProviderName.stripe:
        return DVStripeBillingProvider(
          secretKey: key,
          webhookSecret: webhook,
          prices: prices,
          entitlements: byProviderId,
          successUrl: Uri.parse(successUrl!),
          cancelUrl: Uri.parse(cancelUrl!),
          fetch: fetch,
        );
      case DVBillingProviderName.paddle:
        return DVPaddleBillingProvider(
          apiKey: key,
          webhookSecret: webhook,
          prices: prices,
          entitlements: byProviderId,
          fetch: fetch,
        );
      case DVBillingProviderName.bachs:
        return DVBachsBillingProvider(
          secretKey: key,
          webhookSecret: webhook,
          products: prices,
          entitlements: byProviderId,
          successUrl: Uri.parse(successUrl!),
          cancelUrl: Uri.parse(cancelUrl!),
          fetch: fetch,
        );
    }
  }
}
