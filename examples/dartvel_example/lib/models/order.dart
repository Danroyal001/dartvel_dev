import 'package:dartvel_core/dartvel.dart';

/// An order someone placed.
///
/// Its status moves while the person watches: the roastery saves the order at
/// each step, the save publishes a change, and `Order.watch` on the orders
/// screen hears it. Nothing polls.
///
/// The customer is the person whose email the order carries, and an order is
/// kept for seven years because that is what the accounts need.
@DVModel(
  subject: DVSubject.field('email'),
  retain: DVRetention.days(2555, from: 'placedAt', then: DVRetention.anonymize),
)
@pragma('vm:entry-point')
class _Order {
  final String id;
  final String email;

  /// What was bought, as the receipt lists it: "2 × Huila, 1 × Nyeri".
  final String summary;
  final int itemCount;
  final int totalCents;

  /// placed, roasting, packed, shipped or delivered.
  final String status;

  /// When it was placed, in milliseconds since the epoch.
  final int placedAt;

  const _Order({
    required this.id,
    required this.email,
    required this.summary,
    required this.itemCount,
    required this.totalCents,
    required this.status,
    required this.placedAt,
  });
}
