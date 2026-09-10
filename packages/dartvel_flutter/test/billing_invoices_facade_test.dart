// A billing history is reachable from DV.Billing.
//
// Providers can list invoices now, and a page that wants to render one goes
// through the facade like everything else. Without this the method is on the
// concrete provider only, which puts an application back to importing
// dartvel_core and knowing which provider it configured -- the position that
// had webhook verification being written a second time by hand.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(DV.Test.resetBillingProvider);

  test('invoices come back through the facade with their money', () async {
    DV.Billing.useProvider(DVStripeBillingProvider(
      secretKey: 'sk_test',
      webhookSecret: 'whsec_test',
      prices: const <String, String>{},
      entitlements: const <String, Set<Entitlement>>{},
      successUrl: Uri.parse('https://app.example/ok'),
      cancelUrl: Uri.parse('https://app.example/no'),
      fetch: (String method, Uri url, Map<String, String> h, String? b) async {
        expect(url.queryParameters['customer'], 'cus_123');
        return (
          200,
          '{"data":[{"id":"in_1","customer":"cus_123","number":"A-1",'
              '"total":4000,"currency":"usd","created":1788436800,'
              '"status":"paid"}]}'
        );
      },
    ));

    final List<DVInvoice> invoices = await DV.Billing.invoices('cus_123');

    expect(invoices.single.total, DVMoney(amount: 4000, currency: 'USD'));
    expect(invoices.single.status, DVInvoiceStatus.paid);
  });

  test('asking with no provider configured says so', () async {
    DV.Test.resetBillingProvider();

    await expectLater(
      () => DV.Billing.invoices('cus_123'),
      throwsA(isA<StateError>()),
    );
  });
}
