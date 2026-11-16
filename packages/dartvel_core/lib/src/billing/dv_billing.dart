/// `DV.Billing`: the one billing surface, on the server and in the app.
///
/// A project declares its provider once, in `dartvel.billing` in
/// pubspec.yaml. The generated server hands that block to [DVBilling.configure]
/// before it serves anything, and the provider is built the first time
/// something asks for it, with its keys read through [DVSecrets] then -- so a
/// server whose keys are not set yet still starts, and checkout says "not set
/// up" rather than the process refusing to boot.
///
/// Two framework variables change what was declared without a rebuild:
///
/// * `DARTVEL_BILLING_PROVIDER` names another official provider (`paystack`,
///   say, when `flutterwave` is declared). The return addresses stay; the
///   keys are read from that provider's default variables
///   (`PAYSTACK_SECRET_KEY`), because a secret named for one provider is
///   never another's.
/// * `DARTVEL_BILLING_SITE_URL` is the origin this deployment is reached at.
///   The declared return addresses keep their paths and take this origin, so
///   a staging copy or a test on a spare port sends its buyers back to
///   itself rather than to production.
///
/// [DVBilling.useProvider] still installs a provider in code, and wins over
/// the block.
library dartvel.billing.dv_billing;

import '../../dartvel.dart'
    show
        BillingPlan,
        DVBillingCheckoutSession,
        DVBillingProvider,
        DVLocalBillingProvider,
        DVUsageMeter,
        Entitlement;
import '../http/outbound.dart' show DVHttp;
import '../secrets/secrets.dart';
import '../secrets/secrets_unsupported.dart'
    if (dart.library.io) '../secrets/secrets_io.dart' as env;
import 'config.dart';
import 'invoice.dart';
import 'one_time.dart';
import 'webhooks.dart';

class DVBilling {
  const DVBilling();

  /// The variable naming the provider to use in place of the declared one.
  static const String providerVariable = 'DARTVEL_BILLING_PROVIDER';

  /// The variable naming the origin the return addresses are moved to.
  static const String siteUrlVariable = 'DARTVEL_BILLING_SITE_URL';

  static DVBillingProvider? _provider;
  static DVBillingConfig? _declared;
  static DVBillingFetch? _fetch;
  static Map<String, String>? _environment;
  static final Map<DVBillingProviderName, DVBillingProvider> _built =
      <DVBillingProviderName, DVBillingProvider>{};

  /// Forgets the configuration, the installed provider and every provider
  /// built from the block. For tests.
  static void reset() {
    _provider = null;
    _declared = null;
    _fetch = null;
    _environment = null;
    _built.clear();
  }

  /// Bills through [config], the project's `dartvel.billing`. The generated
  /// server calls this at start; nothing is built and no key is read yet.
  ///
  /// [fetch] is the HTTP transport, defaulting to DV.Http sending only to the
  /// provider's own API ([transportFor]). [environment] is read in place of
  /// the process's variables for `DARTVEL_BILLING_PROVIDER` and
  /// `DARTVEL_BILLING_SITE_URL`, for tests.
  void configure(
    DVBillingConfig config, {
    DVBillingFetch? fetch,
    Map<String, String>? environment,
  }) {
    _declared = config;
    _fetch = fetch;
    _environment = environment;
    _built.clear();
  }

  /// Bills through [provider], built in code. Wins over `dartvel.billing`.
  void useProvider(DVBillingProvider provider) {
    _provider = provider;
  }

  String? _variable(String name) {
    final Map<String, String>? given = _environment;
    final String? value =
        given != null ? given[name] : env.readEnvironment(name);
    final String trimmed = (value ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// The configuration in effect: `dartvel.billing` with
  /// `DARTVEL_BILLING_PROVIDER` and `DARTVEL_BILLING_SITE_URL` applied, or
  /// null when nothing was declared.
  ///
  /// Throws [DVBillingConfigException] for a variable naming a provider
  /// Dartvel does not have, or an origin that is not one: a typo in an
  /// operator's switch must stop checkout, not bill through the old provider.
  DVBillingConfig? get config {
    final DVBillingConfig? declared = _declared;
    if (declared == null) return null;
    return _effective(declared, _switchedProvider(declared.provider));
  }

  DVBillingProviderName _switchedProvider(DVBillingProviderName declared) {
    final String? named = _variable(providerVariable);
    if (named == null) return declared;
    for (final DVBillingProviderName name in DVBillingProviderName.values) {
      if (name.name == named.toLowerCase()) return name;
    }
    throw DVBillingConfigException(
        '$providerVariable is one of '
        '${DVBillingProviderName.values.map((DVBillingProviderName n) => n.name).join(', ')}; '
        '"$named" is not.');
  }

  DVBillingConfig _effective(
      DVBillingConfig declared, DVBillingProviderName provider) {
    final bool same = provider == declared.provider;
    return DVBillingConfig(
      provider: provider,
      prices: declared.prices,
      entitlements: declared.entitlements,
      // A secret named for one provider is never another's.
      apiKey: same ? declared.apiKeySecret : null,
      webhookSecret: same ? declared.webhookSecretName : null,
      successUrl: _moved(declared.successUrl),
      cancelUrl: _moved(declared.cancelUrl),
    );
  }

  String? _moved(String? address) {
    final String? origin = _variable(siteUrlVariable);
    if (address == null || origin == null) return address;
    final Uri? site = Uri.tryParse(origin);
    if (site == null ||
        (site.scheme != 'https' && site.scheme != 'http') ||
        site.host.isEmpty) {
      throw DVBillingConfigException(
          '$siteUrlVariable is the origin this deployment is reached at, such '
          'as https://staging.example.com; "$origin" is not.');
    }
    return Uri.parse(address)
        .replace(scheme: site.scheme, host: site.host, port: site.port)
        .toString();
  }

  /// The provider bills go through: the one [useProvider] installed, else
  /// the one `dartvel.billing` declares, built now if its keys are set.
  /// Null when nothing is configured or its keys are not set.
  DVBillingProvider? get provider {
    final DVBillingProvider? installed = _provider;
    if (installed != null) return installed;
    final DVBillingConfig? declared = _declared;
    if (declared == null) return null;
    return providerNamed(_switchedProvider(declared.provider));
  }

  /// Whether a payment can be taken: a provider is configured and its keys
  /// are set.
  bool get isSetUp => provider != null;

  /// The configured provider's name, whether or not its keys are set; null
  /// when nothing is configured or the installed provider is not one of the
  /// official adapters.
  DVBillingProviderName? get providerName {
    final DVBillingProvider? installed = _provider;
    if (installed != null) return DVBillingProviderName.of(installed);
    final DVBillingConfig? declared = _declared;
    return declared == null ? null : _switchedProvider(declared.provider);
  }

  /// Whether a buyer coming back from the configured provider may confirm a
  /// payment through its API ([DVBillingProviderName.confirmsOnReturn]).
  /// False when nothing is configured.
  bool get confirmsOnReturn => providerName?.confirmsOnReturn ?? false;

  /// The official provider [name], built from the same `dartvel.billing`
  /// block with that provider's default keys, or null when they are not set.
  ///
  /// For a provider's own webhook route: after a switch, payments started
  /// with the previous provider still report to their own route, and are
  /// verified with that provider's secret. The configured provider by its
  /// name is the configured provider itself.
  DVBillingProvider? providerNamed(DVBillingProviderName name) {
    final DVBillingProvider? installed = _provider;
    if (installed != null && DVBillingProviderName.of(installed) == name) {
      return installed;
    }
    final DVBillingProvider? built = _built[name];
    if (built != null) return built;
    final DVBillingConfig? declared = _declared;
    if (declared == null) return null;
    try {
      return _built[name] = _effective(declared, name)
          .createProvider(fetch: _fetch ?? transportFor(name));
    } on DVSecretNotFoundException {
      return null;
    }
  }

  /// The declared address a buyer returns to after paying, on this
  /// deployment's origin; null when none is declared.
  Uri? get successUrl {
    final String? address = config?.successUrl;
    return address == null ? null : Uri.parse(address);
  }

  /// The declared address a buyer who abandons a payment is sent to.
  Uri? get cancelUrl {
    final String? address = config?.cancelUrl;
    return address == null ? null : Uri.parse(address);
  }

  DVBillingProvider get _configuredProvider {
    final DVBillingProvider? configured = provider;
    if (configured != null) return configured;
    if (_declared == null) {
      // Nothing configured at all is a mistake in the program, not a server
      // waiting for its keys.
      throw StateError(
        'DV.Billing has no configured provider. Declare dartvel.billing in '
        'pubspec.yaml, or call DV.Billing.useProvider, before use.',
      );
    }
    throw DVBillingError(_notSetUp(providerName));
  }

  String _notSetUp(DVBillingProviderName? name) {
    final DVBillingConfig? declared = _declared;
    if (name == null || declared == null) {
      return 'Billing is not set up: declare dartvel.billing in pubspec.yaml, '
          'or call DV.Billing.useProvider.';
    }
    final DVBillingConfig effective = _effective(declared, name);
    const DVSecrets secrets = DVSecrets();
    final List<String> missing = <String>[
      for (final String secret in <String>{
        effective.apiKeySecret,
        effective.webhookSecretName,
      })
        if (!secrets.has(secret)) secret,
    ];
    return 'Billing through ${name.name} is not set up: '
        '${missing.join(' and ')} ${missing.length == 1 ? 'is' : 'are'} not set.';
  }

  Future<DVBillingCheckoutSession> checkout({
    required BillingPlan plan,
    required Object customer,
  }) {
    return _configuredProvider.checkout(plan: plan, customer: customer);
  }

  /// Starts paying for [order] on the configured provider's page.
  ///
  /// Throws [DVBillingError] when billing is not set up, or the configured
  /// provider does not take one-time orders.
  Future<DVBillingOrderCheckout> checkoutOrder(DVBillingOrder order) async =>
      _oneTime.checkoutOrder(order);

  /// Asks the configured provider what happened to the payment for
  /// [reference].
  Future<DVBillingOrderStatus> orderStatus({
    required String reference,
    String checkoutId = '',
  }) async =>
      _oneTime.orderStatus(reference: reference, checkoutId: checkoutId);

  DVOneTimeCheckout get _oneTime {
    final DVBillingProvider configured = _configuredProvider;
    if (configured is DVOneTimeCheckout) return configured as DVOneTimeCheckout;
    throw DVBillingError(
        '${configured.runtimeType} does not take one-time orders.');
  }

  Future<bool> hasEntitlement(Object customer, Entitlement entitlement) {
    return _configuredProvider.hasEntitlement(customer, entitlement);
  }

  /// [customer]'s billing history, newest first.
  ///
  /// Only theirs: the provider filters, and the implementations drop any row
  /// that comes back for somebody else rather than render one customer
  /// another customer's invoices on a page that looks entirely normal.
  Future<List<DVInvoice>> invoices(Object customer, {int limit = 20}) {
    return _configuredProvider.invoices(customer, limit: limit);
  }

  /// Verifies a webhook and applies it, against the configured provider or,
  /// with [provider], against that one ([providerNamed]).
  ///
  /// [headers] is the request's headers; the signature is found under the
  /// name the provider signs with, matched without regard to case because
  /// servers hand header names over differently. Throws when billing is not
  /// set up, or the signature is missing, forged, or too old, and changes
  /// nothing in that case.
  ///
  /// This exists so the route that receives a webhook does not have to. The
  /// alternative was downcasting to whichever provider was configured, or
  /// writing the HMAC comparison again next to the handler -- and a
  /// verification written twice is the one that gets simplified until an
  /// unsigned "subscription activated" is accepted.
  Future<DVBillingWebhookResult> handleWebhook(
    String payload,
    Map<String, String> headers, {
    DVBillingProviderName? provider,
  }) async {
    final DVBillingProvider configured;
    if (provider == null) {
      configured = _configuredProvider;
    } else {
      configured =
          providerNamed(provider) ?? (throw DVBillingError(_notSetUp(provider)));
    }
    if (configured is! DVBillingWebhookReceiver) {
      throw StateError(
        '${configured.runtimeType} does not receive webhooks, so there is no '
        'signature to check and nothing here will apply the payload. '
        'Configure a provider that signs its webhooks.',
      );
    }
    final DVBillingWebhookReceiver receiver =
        configured as DVBillingWebhookReceiver;
    final String wanted = receiver.signatureHeaderName.toLowerCase();
    String? signature;
    for (final MapEntry<String, String> header in headers.entries) {
      if (header.key.toLowerCase() == wanted) {
        signature = header.value;
        break;
      }
    }
    if (signature == null) {
      throw DVBillingError(
        'The request carries no ${receiver.signatureHeaderName} header, so '
        'nothing about it can be believed.',
      );
    }
    return receiver.handleWebhook(payload, signature);
  }

  /// Records [quantity] against [meter] for [customer].
  ///
  /// [idempotencyKey] is required, and the reason is worth repeating here
  /// because this is where application code calls it from: usage is reported
  /// from jobs, jobs are redelivered, and a provider counts one record per
  /// identifier. A key derived from the work -- the job id, the request id,
  /// the row being charged for -- is the same on the retry. A fresh one
  /// every call bills twice.
  Future<void> recordUsage({
    required Object customer,
    required DVUsageMeter meter,
    required int quantity,
    required String idempotencyKey,
    DateTime? at,
  }) {
    return _configuredProvider.recordUsage(
      customer: customer,
      meter: meter,
      quantity: quantity,
      idempotencyKey: idempotencyKey,
      at: at,
    );
  }

  void grantLocalEntitlement(Object customer, Entitlement entitlement) {
    final provider = _configuredProvider;
    if (provider is! DVLocalBillingProvider) {
      throw StateError(
        'Local entitlements require DVLocalBillingProvider.',
      );
    }
    provider.grant(customer, entitlement);
  }

  void revokeLocalEntitlement(Object customer, Entitlement entitlement) {
    final provider = _configuredProvider;
    if (provider is! DVLocalBillingProvider) {
      throw StateError(
        'Local entitlements require DVLocalBillingProvider.',
      );
    }
    provider.revoke(customer, entitlement);
  }

  /// The hosts each official provider's API answers on.
  static const Map<DVBillingProviderName, Set<String>> _apiHosts =
      <DVBillingProviderName, Set<String>>{
    DVBillingProviderName.stripe: <String>{'api.stripe.com'},
    DVBillingProviderName.paddle: <String>{
      'api.paddle.com',
      'sandbox-api.paddle.com',
    },
    DVBillingProviderName.bachs: <String>{
      'api.bachs.io',
      'sandbox-api.bachs.io',
    },
    DVBillingProviderName.paystack: <String>{'api.paystack.co'},
    DVBillingProviderName.flutterwave: <String>{'api.flutterwave.com'},
  };

  /// The transport a provider built from `dartvel.billing` sends with:
  /// DV.Http, over HTTPS, to [name]'s own API hosts and nowhere else.
  ///
  /// The provider puts its secret key on every request, so the destination
  /// is fixed here rather than trusted to whatever URL reaches the call.
  static DVBillingFetch transportFor(DVBillingProviderName name) =>
      (String method, Uri url, Map<String, String> headers, String? body) async {
        if (url.scheme != 'https' || !_apiHosts[name]!.contains(url.host)) {
          throw DVBillingError(
              '${name.name} is reached only over HTTPS at '
              '${_apiHosts[name]!.join(' or ')}; ${url.scheme}://${url.host} '
              'was refused.');
        }
        try {
          final response = await const DVHttp().send(method, url,
              headers: headers, body: body, allowUndeclaredHost: true);
          return (response.status, await response.body?.text() ?? '');
        } on DVBillingError {
          rethrow;
        } on Object catch (error) {
          throw DVBillingError(
              '${name.name} could not be reached (${error.runtimeType}).');
        }
      };
}
