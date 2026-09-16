import 'package:dartvel_core/dartvel.dart';

// docs:start privacy-model
@DVModel(
  subject: DVSubject.self,
  retain: DVRetention.days(730, from: 'lastOrderAt', then: DVRetention.anonymize),
)
class _Customer {
  final String id;
  final String name;
  final String lastOrderAt;

  @DVModel.sensitiveField(onErase: DVErase.anonymize)
  final String email;

  const _Customer({
    required this.id,
    required this.name,
    required this.lastOrderAt,
    required this.email,
  });
}
// docs:end
