import 'package:dartvel_core/dartvel.dart';

// docs:start tenancy-model
@DVModel(tenantScoped: true)
class const _Invoice({required final String id, required final int totalCents});
// docs:end
