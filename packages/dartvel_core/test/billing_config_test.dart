// dartvel.billing in pubspec.yaml and DVBillingConfig in code are one
// declaration: the reader turns the block into the class, the class turns
// back into the block, and neither ever holds a key -- only the names of the
// secrets that do, which are resolved from the environment when the provider
// is built.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  tearDown(DVSecrets.reset);

  final Map<String, Object?> bachsBlock = <String, Object?>{
    'provider': 'bachs',
    'prices': <String, Object?>{'team': 'prod_team'},
    'entitlements': <String, Object?>{
      'team': <Object?>['reports'],
    },
    'successUrl': 'https://example.com/billing/done',
    'cancelUrl': 'https://example.com/pricing',
  };

  test('a pubspec block and the config class are the same declaration', () {
    final DVBillingConfig read = DVBillingConfig.read(bachsBlock);
    const DVBillingConfig written = DVBillingConfig(
      provider: DVBillingProviderName.bachs,
      prices: <String, String>{'team': 'prod_team'},
      entitlements: <String, List<String>>{
        'team': <String>['reports'],
      },
      successUrl: 'https://example.com/billing/done',
      cancelUrl: 'https://example.com/pricing',
    );
    expect(read.toMap(), written.toMap());
    expect(DVBillingConfig.read(read.toMap()).toMap(), read.toMap());
    // The secret names default per provider.
    expect(read.apiKeySecret, 'BACHS_SECRET_KEY');
    expect(read.webhookSecretName, 'BACHS_WEBHOOK_SECRET');
  });

  test('the provider is built with keys from the environment, entitlements '
      'keyed by the provider\'s product', () async {
    DVSecrets.configure(<String, String>{
      'BACHS_SECRET_KEY': 'sk_sandbox_from_env',
      'BACHS_WEBHOOK_SECRET': 'whsec_from_env_value',
    });
    final DVBillingProvider provider =
        DVBillingConfig.read(bachsBlock).createProvider();
    expect(provider, isA<DVBachsBillingProvider>());
    final DVBachsBillingProvider bachs = provider as DVBachsBillingProvider;
    expect(bachs.products, <String, String>{'team': 'prod_team'});
    expect(bachs.entitlements, <String, Set<Entitlement>>{
      'prod_team': <Entitlement>{const Entitlement('reports')},
    });
  });

  test('Paddle is built from the same shape', () {
    DVSecrets.configure(<String, String>{
      'PADDLE_API_KEY': 'pdl_sdbx_apikey_value',
      'PADDLE_WEBHOOK_SECRET': 'pdl_ntf_secret_value',
    });
    final DVBillingProvider provider = DVBillingConfig.read(<String, Object?>{
      'provider': 'paddle',
      'prices': <String, Object?>{'pro': 'pri_pro'},
      'entitlements': <String, Object?>{'pro': <Object?>['analytics']},
    }).createProvider();
    expect(provider, isA<DVPaddleBillingProvider>());
    expect((provider as DVPaddleBillingProvider).entitlements,
        <String, Set<Entitlement>>{'pri_pro': <Entitlement>{Entitlement.analytics}});
  });

  test('a missing secret fails when the provider is built, naming it', () {
    expect(
      () => DVBillingConfig.read(bachsBlock).createProvider(),
      throwsA(isA<DVSecretNotFoundException>().having(
          (DVSecretNotFoundException e) => e.key, 'key', 'BACHS_SECRET_KEY')),
    );
  });

  group('the reader refuses', () {
    void refuses(Map<String, Object?> block, String mentions) {
      expect(
        () => DVBillingConfig.read(block),
        throwsA(isA<DVBillingConfigException>().having(
            (DVBillingConfigException e) => e.message, 'message', contains(mentions))),
        reason: '$block',
      );
    }

    test('an unknown key or provider', () {
      refuses(<String, Object?>{...bachsBlock, 'colour': 'blue'}, 'colour');
      refuses(<String, Object?>{...bachsBlock, 'provider': 'paypal'}, 'paypal');
    });

    test('a key written into pubspec instead of the name of a secret', () {
      refuses(<String, Object?>{...bachsBlock, 'apiKey': 'sk_live_abc123'},
          'environment');
      refuses(<String, Object?>{...bachsBlock, 'webhookSecret': 'whsec_abc'},
          'environment');
    });

    test('an entitlement for a plan with no price', () {
      refuses(<String, Object?>{
        ...bachsBlock,
        'entitlements': <String, Object?>{'ghost': <Object?>['reports']},
      }, 'ghost');
    });

    test('a checkout provider with no return URLs', () {
      refuses(<String, Object?>{
        'provider': 'stripe',
        'prices': <String, Object?>{'team': 'price_1'},
      }, 'successUrl');
    });
  });
}
