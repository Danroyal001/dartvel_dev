import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

// Taking money: subscriptions through Stripe or Paddle, app store purchases,
// tax, promotions and refunds, and usage limits per tenant. None of the
// payment providers has been run against the live service, and each status
// box says so. Source: the "absent" notes in docs/spec-status.json.
@DVPage(title: 'Dartvel billing: subscriptions, purchases, tax and usage', showAppBar: false)
@pragma('vm:entry-point')
Widget _docsBillingPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsbilling,
      lead: <String>[
        'Sell subscriptions, charge with tax and promotions, and cap usage per '
            'customer, with every grant checked on the server.',
        'Stripe, Paddle and the store paths are tested against fakes. None has '
            'been run against the live service yet.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'subscriptions',
          title: 'Sell a plan through Stripe or Paddle',
          children: <Widget>[
            Bullets(<String>[
              'Checkout reads the plan\'s price from the provider first and '
                  'refuses when it differs from your plan, so a page cannot '
                  'show one price and charge another.',
              'Webhooks grant and revoke entitlements from subscription '
                  'status, and each is believed only when its signature '
                  'matches within five minutes.',
              'Trials and usage meters are passed through to the provider.',
            ]),
            DocsStatus('Billing', missing: <String>[
              'Neither provider has been exercised against the live service.',
              'Stripe and Paddle keep webhook grants in memory, so a refund '
                  'revokes a grant only with the local provider.',
            ]),
          ],
        ),
        DocsSection(
          id: 'purchases',
          title: 'Check app store purchases on your server',
          children: <Widget>[
            Bullets(<String>[
              'DVPurchases writes a grant only from the store\'s own answer '
                  'about a receipt, and refuses one bought under another '
                  'account.',
              'Store notifications are signature-checked, applied once and in '
                  'order, and access ends when the paid period and grace end.',
              'A refund or chargeback is told apart from a lapse, so '
                  'DVCommerce can reverse the sale.',
            ]),
            DocsStatus('Purchases and Entitlements', missing: <String>[
              'No real App Store or Play adapters yet, and no StoreKit or Play '
                  'Billing binding, so DV.Purchases.buy does not exist.',
              'Products are not generated from models.',
            ]),
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
            DocsStatus('Commerce: Tax, Promotions, Disputes and Payouts',
                missing: <String>[
              'Tested against fakes only. No live tax, payment or payout '
                  'provider has been run.',
              'DVTaxTable ships no rates. It is the offline fallback and the '
                  'reference for rounding.',
            ]),
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
            DocsStatus('Usage Metering and Quotas', missing: <String>[
              'No @DVMeter annotations, so meters are not generated or counted '
                  'for you.',
              'No dartvel meters commands, no Studio view, and no scheduled '
                  'period close.',
            ]),
          ],
        ),
      ],
    );
