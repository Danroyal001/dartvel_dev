import '../dartvel_client/dartvel_client.dart';

/// The account that pays, which is what a grant is written against.
///
/// Two objects loaded from the same row answer as the same customer, which
/// object identity does not give.
class const Workspace(final String id, final String stripeId)
    implements DVBillingCustomer {
  @override
  String get billingCustomerId => stripeId;
}

// docs:start billing-plans
// What you sell, and what each plan turns on. The price is the number the
// application is held to: checkout reads the provider's own price first and
// refuses when the two disagree, so a page cannot show one price and charge
// another.
const BillingPlan team = BillingPlan(
  id: 'team',
  displayName: 'Team',
  priceMinorUnits: 4900,
  currency: 'USD',
  trialDays: 14,
);

const Entitlement reports = Entitlement('reports');
// docs:end

// docs:start billing-provider
void useStripe() {
  DV.Billing.useProvider(DVStripeBillingProvider(
    secretKey: DV.Secrets.get('STRIPE_SECRET_KEY'),
    webhookSecret: DV.Secrets.get('STRIPE_WEBHOOK_SECRET'),
    // Your plan id on the left, the provider's price on the right.
    prices: const <String, String>{'team': 'price_1234'},
    // What each plan grants once the subscription is live.
    entitlements: const <String, Set<Entitlement>>{
      'team': <Entitlement>{reports},
    },
    successUrl: Uri.parse('https://example.com/billing/done'),
    cancelUrl: Uri.parse('https://example.com/pricing'),
  ));
}
// docs:end

// docs:start billing-checkout
Future<Uri?> subscribe(Workspace workspace) async {
  final DVBillingCheckoutSession session =
      await DV.Billing.checkout(plan: team, customer: workspace);
  // Null when the provider gave back no hosted page. Send the customer
  // nowhere; a blank tab is worse.
  return session.checkoutUrl;
}
// docs:end

// docs:start billing-entitlement
// Asked on the server, never read off the client: the page that shows a
// feature and the code that allows it must not be two different answers.
Future<bool> mayExport(Workspace workspace) =>
    DV.Billing.hasEntitlement(workspace, reports);
// docs:end
