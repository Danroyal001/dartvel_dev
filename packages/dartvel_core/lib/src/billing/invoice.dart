/// An invoice, as much of one as an application needs to list it.
///
/// The amount is a [DVMoney] rather than an integer for the same reason a
/// model's price is. A provider sends minor units and a currency separately,
/// and an integer that loses its currency still renders as money: 4000 reads
/// as forty dollars, four thousand yen, or forty of whatever the page
/// assumed, and nothing about the page looks wrong.
library dartvel.billing.invoice;

import 'money.dart';

/// Where an invoice got to.
///
/// [unknown] exists so that a status this code has not seen is not quietly
/// read as [paid]. Providers add states, and an unpaid invoice displayed as
/// settled is a bill nobody chases.
enum DVInvoiceStatus { draft, open, paid, uncollectible, voided, unknown }

/// One invoice from a billing provider.
class DVInvoice {
  const DVInvoice({
    required this.id,
    required this.total,
    required this.status,
    required this.createdAt,
    this.number,
    this.hostedUrl,
    this.pdfUrl,
  });

  /// The provider's identifier for it.
  final String id;

  /// The human-facing invoice number, when the provider issued one. A draft
  /// often has none.
  final String? number;

  final DVMoney total;
  final DVInvoiceStatus status;

  /// When the provider created it, in UTC.
  final DateTime createdAt;

  /// A page the customer can open, when the provider hosts one.
  final Uri? hostedUrl;

  /// A PDF, when the provider exposes one directly.
  final Uri? pdfUrl;

  @override
  String toString() => 'DVInvoice($id, $total, ${status.name})';
}
