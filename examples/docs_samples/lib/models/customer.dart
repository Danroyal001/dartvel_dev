import 'package:dartvel_core/dartvel.dart';

// docs:start privacy-model
@DVModel(
  subject: DVSubject.self,
  retain: DVRetention.days(730, from: 'lastOrderAt', then: DVRetention.anonymize),
)
class const _Customer({
  required final String id,
  required final String name,
  required final String lastOrderAt,
  @DVModel.sensitiveField(onErase: DVErase.anonymize)
  required final String email,
});
// docs:end
