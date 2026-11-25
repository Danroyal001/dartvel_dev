import 'package:material_ui/material_ui.dart';

import '../../dartvel_client/dartvel_client.dart';

// Taking money: subscriptions through Stripe, Paddle or Bachs, app store purchases,
// tax, promotions and refunds, and usage limits per tenant. None of the
// payment providers has been run against the live service, and each status
// box says so. Source: the "absent" notes in docs/spec-status.json.
@DVPage(
  title: 'Dartvel billing: subscriptions, purchases, tax and usage',
  description:
      'Sell subscriptions through Stripe, Paddle or Bachs and one-time orders through Bachs, Paystack or Flutterwave, check store '
      'purchases on your server, charge with tax and promotions, and '
      'cap usage per customer.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsBillingPage(BuildContext context) => const DocsArticle(
  page: DVRoutes.docsbilling,
  lead: <String>[
    'Sell subscriptions, charge with tax and promotions, and cap usage per '
        'customer, with every grant checked on the server.',
    'Stripe, Paddle, Bachs and the store paths are tested against fakes. None has '
        'been run against the live service yet.',
  ],
  sections: <DocsSection>[
    DocsSection(
      id: 'subscriptions',
      title: 'Sell a plan through Stripe, Paddle or Bachs',
      children: <Widget>[
        Bullets(<String>[
          'Checkout reads the plan\'s price from the provider first and '
              'refuses when it differs from your plan, so a page cannot '
              'show one price and charge another.',
          'Webhooks grant and revoke entitlements from subscription '
              'status, and each is believed only when its signature '
              'matches within five minutes.',
          'Trials and usage meters are passed through to the provider.',
          'Choose the provider in pubspec.yaml under dartvel.billing '
              '(provider: stripe, paddle or bachs). The block names the '
              'secrets that hold the keys, never the keys themselves.',
          'Bachs charges cards in dollars or naira, and takes bank '
              'transfer and mobile money in local currencies. A sandbox '
              'key talks only to '
              'the Bachs sandbox, and a webhook is accepted while any of '
              'its current signing secrets matches, so rotating a secret '
              'drops nothing.',
        ]),
        DocsCode('billing-plans'),
        DocsCode('billing-provider'),
        DocsCode('billing-checkout'),
        DocsCode('billing-entitlement'),
        DocsStatus(
          'Billing',
          missing: <String>[
            'No provider has been exercised against the live service.',
            'Stripe, Paddle and Bachs keep webhook grants in memory, so a refund '
                'revokes a grant only with the local provider.',
          ],
        ),
      ],
    ),
    DocsSection(
      id: 'one-time',
      title: 'Sell one-time orders through Bachs, Paystack or Flutterwave',
      children: <Widget>[
        Bullets(<String>[
          'A shop prices each order itself: build a DVBillingOrder (a '
              'reference, the lines in minor units, the buyer\'s email and '
              'where to come back to) and checkoutOrder returns the '
              'provider\'s hosted page.',
          'The order\'s reference is the provider\'s transaction reference '
              'and its idempotency key, so one order is one payment and a '
              'retried request opens the same checkout.',
          'A webhook names the order (DVBillingWebhookResult.reference); '
              'whether it is paid is asked of the provider\'s API with '
              'orderStatus, and paidInFull is true only for the exact total '
              'and currency. The return address proves nothing.',
          'Bachs takes the total as a decimal string and signs webhooks '
              'with X-Bachs-Signature-V2; Paystack counts kobo and signs with '
              'HMAC-SHA512 of the body; Flutterwave counts naira and sends '
              'the secret hash in verif-hash. Choose one with provider: '
              'bachs, paystack or flutterwave.',
        ]),
        DocsStatus(
          'Billing',
          missing: <String>[
            'Paystack and Flutterwave are tested against fakes only.',
            'Fulfilment is the application\'s: Dartvel says which order '
                'and whether it is paid, the application marks it paid.',
          ],
        ),
      ],
    ),
    DocsSection(
      id: 'configure',
      title: 'Choose the provider in pubspec.yaml, switch it without a rebuild',
      children: <Widget>[
        Bullets(<String>[
          'dartvel.billing names the provider, its return addresses and the '
              'secrets that hold its keys: provider: flutterwave, successUrl: '
              'https://example.com/payments/return, cancelUrl: '
              'https://example.com/cart. The build reads it and the server '
              'hands it to DV.Billing at start; no provider is built in code.',
          'DV.Billing builds the provider the first time something asks for '
              'it and reads the keys then, so a server without its keys still '
              'starts: DV.Billing.isSetUp is false and checkout says which '
              'variable is missing.',
          'Backend functions reach the same DV.Billing as pages, through '
              'package:dartvel_core/dv.dart: DV.Billing.checkoutOrder, '
              'orderStatus, providerName, successUrl and cancelUrl.',
          'DV.Billing.confirmsOnReturn says whether a buyer coming back may '
              'confirm a payment by asking the provider\'s API: yes for '
              'Paystack and Flutterwave, no for Bachs, whose signed webhook '
              'is the only answer it documents.',
          'Each provider keeps its own webhook route: '
              'DV.Billing.handleWebhook(body, headers, provider: .paystack) '
              'verifies with that provider\'s secret, so payments started '
              'before a switch are still believed.',
          'DARTVEL_BILLING_PROVIDER=paystack moves billing to another '
              'provider on the next start, with that provider\'s own key '
              'variables (PAYSTACK_SECRET_KEY). DARTVEL_BILLING_SITE_URL '
              'sends buyers back to another origin, for a staging copy or a '
              'test on a spare port.',
        ]),
        DocsStatus(
          'Billing',
          missing: <String>[
            'Plan ids in dartvel.billing.prices belong to the declared '
                'provider, so a switch covers one-time orders unless the '
                'prices hold the new provider\'s ids.',
          ],
        ),
      ],
    ),
    DocsSection(
      id: 'purchases',
      title: 'Sell in-app purchases, checked on your server',
      children: <Widget>[
        Bullets(<String>[
          'DV.Purchases.buy opens StoreKit 2 on iOS and macOS and Play '
              'Billing on Android, the gateway checkout on the web and '
              'desktop. A store that writes its own invoices, such as Telegram '
              'Stars, plugs in as a store adapter from a paid runtime '
              'package.',
          'Subscriptions with trials and offers, non-consumables and '
              'consumables. Ask to Buy and slow payments come back as '
              'pending and finish later.',
          'The device sends the receipt to your server, which asks the '
              'store. Only then is the purchase finished, and only what the '
              'server accepted.',
          'DVPurchases writes a grant only from the store\'s own answer '
              'and refuses one bought under another account.',
          'App Store Server Notifications v2 and Play Real-time Developer '
              'Notifications are signature-checked, applied once and in '
              'order. A refund or chargeback is told apart from a lapse.',
          'Play: the service account lives in DV.Secrets '
              '(PLAY_SERVICE_ACCOUNT_JSON), the package name and the Pub/Sub '
              'push audience under dartvel.purchases.play, and a push is '
              'believed only with Google\'s signed token for that audience.',
          '`dartvel build android --format aab` also writes the Play Data '
              'safety answers (data-safety.csv and a worksheet) beside the '
              'bundle. It fills in only what Dartvel itself sends and lists '
              'the rest as questions for you.',
        ]),
        DocsCode('purchases-products'),
        DocsCode('purchases-buy'),
        DocsCode('purchases-watch'),
        DocsCode('purchases-server'),
        DocsStatus(
          'Purchases and Entitlements',
          missing: <String>[
            'The StoreKit 2 binding has not run on a Mac, and no purchase '
                'has gone through a real App Store or Play sandbox. '
                'The Play Billing binding has not run on an Android device, '
                'and the Play adapter has only met recorded Google responses.',
            'Products are not generated from models.',
          ],
        ),
      ],
    ),
    DocsSection(
      id: 'commerce',
      title: 'Charge with tax and promotions, and refund cleanly',
      children: <Widget>[
        Bullets(<String>[
          'DVTax asks your tax provider and refuses the sale when the '
              'answer does not add up. Nothing is ever taxed at zero by '
              'accident.',
          'Promotions stack by group, respect global and per-customer '
              'limits under load, and are checked on the server.',
          'DVCommerce.charge captures last, so a failure at any step '
              'leaves nothing behind. A refund reverses tax and revokes '
              'what the sale granted.',
        ]),
        DocsStatus(
          'Commerce: Tax, Promotions, Disputes and Payouts',
          missing: <String>[
            'Tested against fakes only. No live tax, payment or payout '
                'provider has been run.',
            'DVTaxTable ships no rates. It is the offline fallback and the '
                'reference for rounding.',
          ],
        ),
      ],
    ),
    DocsSection(
      id: 'usage',
      title: 'Meter usage and cap it per tenant',
      children: <Widget>[
        Bullets(<String>[
          'Count or gauge anything per tenant, in memory or in your '
              'database. Each record needs an idempotency key, so a retry '
              'is not counted twice.',
          'Limits can block, throttle or allow and bill, with thresholds '
              'announced once.',
          'Each period\'s usage is reported to your billing provider, with '
              'a retry queue and a reconcile that is safe to run again.',
        ]),
        DocsStatus(
          'Usage Metering and Quotas',
          missing: <String>[
            'No @DVMeter annotations, so meters are not generated or counted '
                'for you.',
            'No `dartvel meters` commands, no Studio view, and no scheduled '
                'period close.',
          ],
        ),
      ],
    ),
  ],
);
