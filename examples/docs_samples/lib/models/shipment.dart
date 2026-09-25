import 'package:dartvel_core/dartvel.dart';

// docs:start capture-model
// Captured: every insert, update, delete, soft delete and restore lands in
// the process's log as a change, with the record's version, the tenant and
// the transaction it committed in. The email is named in the change and
// never carried in it.
// The subject is whose shipment it is, so an erasure reaches the row and the
// copies made from it: a captured model still answers a deletion request.
@DVModel(subject: DVSubject.self, capture: true)
class const _Shipment({
  required final String id,
  required final String reference,
  required final int total,
  @DVModel.sensitiveField() required final String customerEmail,
});
// docs:end
