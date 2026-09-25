import 'package:dartvel_core/dartvel.dart';

// docs:start capture-model
// Captured: every insert, update, delete, soft delete and restore is
// recorded, in the order it committed, and delivered to the destinations
// dartvel.capture in pubspec.yaml names. The email is named in each change
// and never carried in it. The subject is whose shipment it is, so an
// erasure reaches the row and every copy made from it.
@DVModel(subject: DVSubject.self, capture: true)
class _Shipment {
  final String id;
  final String reference;
  final int total;
  @DVModel.sensitiveField()
  final String customerEmail;

  const _Shipment({
    required this.id,
    required this.reference,
    required this.total,
    required this.customerEmail,
  });
}
// docs:end
