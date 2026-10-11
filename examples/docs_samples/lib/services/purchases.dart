import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';
import 'billing.dart';

// docs:start purchases-products
// What the application sells, declared once and read by both halves.
const DVPurchaseProduct proMonthly = DVPurchaseProduct(
  'pro_monthly',
  billable: DVBillable.digital(appStore: 'com.example.pro', play: 'pro'),
  entitlements: <Entitlement>{Entitlement('pro')},
);
const DVPurchaseProduct coins = DVPurchaseProduct(
  'coins_100',
  billable: DVBillable.digital(
      appStore: 'com.example.coins', play: 'coins',
      telegram: 'coins', telegramStars: 50),
  entitlements: <Entitlement>{},
  kind: DVPurchaseKind.consumable,
);
// docs:end

void creditCoins(Set<String> consumed) {}
void showWaitingForApproval() {}
void showError(String reason) {}

Future<void> buyPro() async {
  // docs:start purchases-buy
  // In the app. The store sheet on iOS and Android, the gateway checkout on
  // the web and desktop, Stars in Telegram: one call, no platform branch.
  DVPurchases.configure(DVPurchases.device(products: <DVPurchaseProduct>[
    proMonthly,
    coins,
  ]));
  await DV.Purchases.refreshEntitlements();

  final DVPurchaseOutcome outcome = await DV.Purchases.buy(proMonthly);
  switch (outcome) {
    case DVPurchaseCompleted(:final Set<String> consumed):
      creditCoins(consumed);
    case DVPurchasePending():
      showWaitingForApproval();
    case DVPurchaseCancelled() || DVPurchaseRedirected():
      break;
    case DVPurchaseFailed(:final String reason):
      showError(reason);
  }
  // docs:end
}

class ProDashboard extends StatelessWidget {
  const ProDashboard({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class Upgrade extends StatelessWidget {
  const Upgrade({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class ProGate extends StatelessWidget {
  const ProGate({super.key});

  @override
  // docs:start purchases-watch
  // Rebuilds when the server says what is held changed: a purchase, an Ask
  // to Buy approved later, a refund at the next sync.
  Widget build(BuildContext context) =>
      DV.Purchases.watch(context, const Entitlement('pro'))
          ? const ProDashboard()
          : const Upgrade();
  // docs:end
}

void configurePurchasesServer(DVBillingProvider stripe) {
  // docs:start purchases-server
  // On the server. pubspec.yaml declares `dartvel: purchases: {}`, which
  // serves /_dartvel/purchases/verify, entitlements and the stores'
  // notification endpoints.
  DVPurchases.configure(DVPurchases(
    products: <DVPurchaseProduct>[proMonthly, coins],
    stores: <DVStoreAdapter>[
      DVAppStoreAdapter(bundleId: 'com.example.app'),
      // The service account comes from DV.Secrets (PLAY_SERVICE_ACCOUNT_JSON);
      // the rest is `dartvel: purchases: play:` in pubspec.yaml.
      DVPlayStoreAdapter.fromSecrets(const DVPlayStoreConfig(
        packageName: 'com.example.app',
        pushAudience:
            'https://example.com/api/_dartvel/purchases/notifications/play',
        pushServiceAccount: 'play-push@example.iam.gserviceaccount.com',
      )),
    ],
    ledger: DVDatabasePurchaseLedger(DV.Database.configuredAdapter!),
    // Optional: what the web and desktop sell through.
    gateway: stripe,
    gatewayPlans: const <String, BillingPlan>{'pro_monthly': team},
  ));
  // docs:end
}
