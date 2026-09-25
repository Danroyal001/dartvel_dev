import 'package:dartvel_core/dartvel.dart';

/// An order someone placed.
///
/// Its status moves while the person watches: the roastery saves the order at
/// each step, the save publishes a change, and `Order.watch` on the orders
/// screen hears it. Nothing polls.
///
/// The customer is the person whose email the order carries, and an order is
/// kept for seven years because that is what the accounts need. It has no
/// public page: an order is somebody's purchase, not something to publish.
@DVModel(
  generatePublicPages: false,
  subject: DVSubject.field('email'),
  retain: DVRetention.days(2555, from: 'placedAt', then: DVRetention.anonymize),
)
@pragma('vm:entry-point')
class const _Order({
  required final String id,
  required final String email,

  /// What was bought, as the receipt lists it: "2 × Huila, 1 × Nyeri".
  required final String summary,
  required final int itemCount,
  required final int totalCents,

  /// placed, roasting, packed, shipped or delivered.
  required final String status,

  /// When it was placed, in milliseconds since the epoch.
  required final int placedAt,
});
