/// One-time orders: a cart the application priced, paid once on the
/// provider's hosted page.
///
/// Subscriptions go through [DVBillingProvider.checkout] with a plan the
/// provider holds a price for. A shop is different: what is being bought is
/// decided per order -- a Pro tool, two months of a care plan, a quantity --
/// and the provider has no catalogue entry for it. [DVOneTimeCheckout] takes
/// the order as the application priced it and returns the provider's page.
///
/// The two places money and trust cross a boundary are the same as for a
/// subscription. The order's [DVBillingOrder.reference] is the provider's
/// transaction reference too, so one order is one payment and a retried
/// request opens the same checkout rather than a second one. And an order is
/// paid only when the provider's own API says so -- [DVOneTimeCheckout.orderStatus]
/// read after a signed webhook -- and only for the amount and currency the
/// application asked for ([DVBillingOrderStatus.paidInFull]). A browser coming
/// back to the success URL proves nothing: anyone can type that address.
library dartvel.billing.one_time;

import 'money.dart';

/// One line of an order: what it is, what one costs in the order currency's
/// minor units, and how many.
class DVBillingOrderLine {
  const DVBillingOrderLine({
    required this.name,
    required this.unitMinorUnits,
    this.quantity = 1,
  })  : assert(unitMinorUnits >= 0, 'a price is not negative'),
        assert(quantity > 0, 'a line has at least one of something');

  final String name;
  final int unitMinorUnits;
  final int quantity;

  int get totalMinorUnits => unitMinorUnits * quantity;
}

/// An order the application priced, to be paid once.
class DVBillingOrder {
  const DVBillingOrder({
    required this.reference,
    required this.currency,
    required this.lines,
    required this.customerEmail,
    required this.successUrl,
    required this.cancelUrl,
    this.customerName,
    this.metadata = const <String, String>{},
  });

  /// The application's own id for the order. The provider is given it as
  /// the transaction reference, so it identifies one payment for good.
  final String reference;

  /// ISO 4217, such as `NGN` or `USD`.
  final String currency;
  final List<DVBillingOrderLine> lines;
  final String customerEmail;
  final String? customerName;

  /// Where the provider sends the buyer after paying. The return proves
  /// nothing; it is where the application shows what the webhook recorded.
  final Uri successUrl;

  /// Where a buyer who abandons the payment is sent.
  final Uri cancelUrl;

  /// Extra words kept with the payment at the provider.
  final Map<String, String> metadata;

  int get totalMinorUnits => lines.fold(
      0, (int total, DVBillingOrderLine line) => total + line.totalMinorUnits);

  DVMoney get total => DVMoney(amount: totalMinorUnits, currency: currency);

  /// The lines in a few words, for the provider's page and receipt.
  String get description => lines
      .map((DVBillingOrderLine line) => '${line.quantity} × ${line.name}')
      .join('; ');
}

/// A started payment: the provider's id for it and the page to pay on.
class DVBillingOrderCheckout {
  const DVBillingOrderCheckout({
    required this.reference,
    required this.id,
    required this.url,
  });

  /// The order's own reference.
  final String reference;

  /// The provider's id for the payment page (a Bachs `chk_`), or the
  /// reference itself where the provider has no other.
  final String id;

  /// The provider's hosted page; send the buyer there.
  final Uri url;
}

/// What the provider's API says about one order's payment.
class DVBillingOrderStatus {
  const DVBillingOrderStatus({
    required this.reference,
    required this.checkoutId,
    required this.paid,
    this.amount,
    this.transactionId,
  });

  /// The reference the provider holds the payment under.
  final String reference;
  final String checkoutId;

  /// Whether the provider says the money was collected.
  final bool paid;

  /// What was charged; null when the provider gave an amount this could not
  /// read exactly.
  final DVMoney? amount;

  /// The provider's id for the charge, for refunds and reconciliation.
  final String? transactionId;

  /// Whether this is [order], paid, for exactly its total in its currency.
  ///
  /// The check an application fulfils on. A payment for less, or in another
  /// currency, is the silent failure: it is "paid", and it is not the order.
  bool paidInFull(DVBillingOrder order) =>
      paid &&
      reference == order.reference &&
      amount != null &&
      amount!.currency == order.currency &&
      amount!.amount == order.totalMinorUnits;
}

/// A billing provider that takes one-time orders.
abstract interface class DVOneTimeCheckout {
  /// Starts paying for [order] and returns the provider's page.
  ///
  /// Asked twice for the same reference, the provider returns the same
  /// checkout: the request carries an idempotency key derived from it.
  Future<DVBillingOrderCheckout> checkoutOrder(DVBillingOrder order);

  /// Asks the provider what happened to the payment for [reference].
  /// [checkoutId] is the id [checkoutOrder] returned, for a provider that
  /// looks payments up by its own id.
  Future<DVBillingOrderStatus> orderStatus({
    required String reference,
    String checkoutId = '',
  });
}

/// Whether [address] is one the providers refuse to send a buyer back to:
/// this machine. Bachs refuses them in its sandbox too, so a build on a
/// developer's machine leaves the return addresses out.
bool dvBillingLoopback(Uri address) =>
    const <String>['localhost', '127.0.0.1', '::1', '[::1]'].contains(address.host);
