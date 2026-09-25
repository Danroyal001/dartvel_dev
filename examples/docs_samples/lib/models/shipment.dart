import 'package:dartvel_core/dartvel.dart';

// docs:start capture-model
// Captured: every insert, update, delete, soft delete and restore is
// recorded, in the order it committed, and delivered to the destinations
// dartvel.capture in pubspec.yaml names. The email is named in each change
// and never carried in it. The subject is whose shipment it is, so an
// erasure reaches the row and every copy made from it.
@DVModel(subject: DVSubject.self, capture: true)
class const _Shipment({
  required final String id,
  required final String reference,
  required final int total,
  @DVModel.sensitiveField() required final String customerEmail,
});
// docs:end
