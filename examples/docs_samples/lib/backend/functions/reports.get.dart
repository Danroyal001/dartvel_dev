import 'package:dartvel_core/dartvel.dart';

// docs:start backend-middleware
@DVBackendFunction(middleware: <DVMiddlewareKey>[
  DVMiddlewares.auth,
  DVMiddlewares.rateLimit,
])
Future<List<String>> _listReports() async => <String>['2026-08', '2026-09'];
// docs:end
