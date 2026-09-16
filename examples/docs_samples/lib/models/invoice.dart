import 'package:dartvel_core/dartvel.dart';

// docs:start tenancy-model
@DVModel(tenantScoped: true)
class _Invoice {
  final String id;
  final int totalCents;

  const _Invoice({required this.id, required this.totalCents});
}
// docs:end
