import 'package:dartvel_core/dartvel.dart';

// docs:start capture-model
// Captured: every insert, update, delete, soft delete and restore lands in
// the process's log as a change, with the record's version, the tenant and
// the transaction it committed in. The email is named in the change and
// never carried in it.
// The subject is whose shipment it is, so an erasure reaches the row and the
// copies made from it: a captured model still answers a deletion request.
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
