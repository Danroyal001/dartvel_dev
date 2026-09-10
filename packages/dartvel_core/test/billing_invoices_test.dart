// Invoices, and the two ways a list of them goes wrong quietly.
//
// "invoices" is in the Billing feature list and nothing read or listed one.
// An application that wanted a billing history wrote the provider call
// itself, which is where both of these come from.
//
// The first is the amount. A provider sends minor units and a currency, and
// dropping the currency or reading the integer as major units produces a
// number that looks like money and is wrong by two orders of magnitude, on
// a page where nobody can tell by looking. DVMoney carries both.
//
// The second is whose invoice it is. The query filters by customer at the
// provider, so a row for somebody else means the filter did not apply --
// the wrong parameter name, a copied request, a provider that ignores an
// unknown key. Rendering it anyway shows one customer another customer's
// billing history, and the page looks perfectly normal.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

String stripeInvoice({
  String id = 'in_1',
  String customer = 'cus_123',
  int total = 4000,
  String currency = 'usd',
  String status = 'paid',
}) =>
    '{"id":"$id","customer":"$customer","number":"A-1","total":$total,'
    '"currency":"$currency","created":1788436800,"status":"$status",'
    '"hosted_invoice_url":"https://invoice.stripe.com/$id",'
    '"invoice_pdf":"https://invoice.stripe.com/$id.pdf"}';

void main() {
  group('Stripe', () {
    late List<(String, Uri)> calls;

    DVStripeBillingProvider provider(String body) {
      calls = <(String, Uri)>[];
      return DVStripeBillingProvider(
        secretKey: 'sk_test',
        webhookSecret: 'whsec_test',
        prices: const <String, String>{},
        entitlements: const <String, Set<Entitlement>>{},
        successUrl: Uri.parse('https://app.example/ok'),
        cancelUrl: Uri.parse('https://app.example/no'),
        fetch: (String method, Uri url, Map<String, String> h,
            String? b) async {
          calls.add((method, url));
          return (200, body);
        },
      );
    }

    test('an invoice comes back with its money intact', () async {
      final DVStripeBillingProvider p =
          provider('{"data":[${stripeInvoice()}]}');

      final List<DVInvoice> invoices = await p.invoices('cus_123');

      final DVInvoice invoice = invoices.single;
      expect(invoice.id, 'in_1');
      expect(invoice.number, 'A-1');
      expect(invoice.total, DVMoney(amount: 4000, currency: 'USD'));
      expect(invoice.status, DVInvoiceStatus.paid);
      expect(invoice.hostedUrl, Uri.parse('https://invoice.stripe.com/in_1'));
      expect(invoice.createdAt, DateTime.utc(2026, 9, 3, 12));

      final (String method, Uri url) = calls.single;
      expect(method, 'GET');
      expect(url.path, '/v1/invoices');
      expect(url.queryParameters['customer'], 'cus_123');
    });

    test('an invoice belonging to someone else is dropped', () async {
      final DVStripeBillingProvider p = provider(
          '{"data":[${stripeInvoice()},${stripeInvoice(id: 'in_2', customer: 'cus_999')}]}');

      final List<DVInvoice> invoices = await p.invoices('cus_123');

      expect(invoices.map((DVInvoice i) => i.id), <String>['in_1']);
    });

    test('a status nothing recognises is not paid', () async {
      // The quiet version reads an unknown status as settled, and an unpaid
      // invoice then shows as paid to the person who has not paid it.
      final DVStripeBillingProvider p =
          provider('{"data":[${stripeInvoice(status: 'something_new')}]}');

      expect((await p.invoices('cus_123')).single.status,
          DVInvoiceStatus.unknown);
    });

    test('a currency the provider did not send is refused, not assumed',
        () async {
      final DVStripeBillingProvider p = provider(
          '{"data":[{"id":"in_1","customer":"cus_123","total":4000,'
          '"created":1788436800,"status":"paid"}]}');

      await expectLater(
          p.invoices('cus_123'), throwsA(isA<DVBillingError>()));
    });
  });

  group('Paddle', () {
    test('a completed transaction is an invoice', () async {
      final DVPaddleBillingProvider p = DVPaddleBillingProvider(
        apiKey: 'pdl_live_key',
        webhookSecret: 's',
        prices: const <String, String>{},
        entitlements: const <String, Set<Entitlement>>{},
        fetch: (String method, Uri url, Map<String, String> h,
            String? b) async {
          expect(method, 'GET');
          expect(url.path, '/transactions');
          expect(url.queryParameters['customer_id'], 'ctm_1');
          return (
            200,
            '{"data":[{"id":"txn_1","customer_id":"ctm_1",'
                '"invoice_number":"B-2","status":"completed",'
                '"billed_at":"2026-09-03T12:00:00Z",'
                '"details":{"totals":{"total":"4000","currency_code":"USD"}}}]}'
          );
        },
      );

      final DVInvoice invoice = (await p.invoices('ctm_1')).single;
      expect(invoice.id, 'txn_1');
      expect(invoice.number, 'B-2');
      expect(invoice.total, DVMoney(amount: 4000, currency: 'USD'));
      expect(invoice.status, DVInvoiceStatus.paid);
    });

    test('a transaction for another customer is dropped', () async {
      final DVPaddleBillingProvider p = DVPaddleBillingProvider(
        apiKey: 'pdl_live_key',
        webhookSecret: 's',
        prices: const <String, String>{},
        entitlements: const <String, Set<Entitlement>>{},
        fetch: (String method, Uri url, Map<String, String> h,
                String? b) async =>
            (
              200,
              '{"data":[{"id":"txn_9","customer_id":"ctm_other",'
                  '"status":"completed","billed_at":"2026-09-03T12:00:00Z",'
                  '"details":{"totals":{"total":"4000","currency_code":"USD"}}}]}'
            ),
      );

      expect(await p.invoices('ctm_1'), isEmpty);
    });
  });

  test('the local provider has no invoices because nothing charged anybody',
      () async {
    expect(await DVLocalBillingProvider().invoices('u'), isEmpty);
  });
}
