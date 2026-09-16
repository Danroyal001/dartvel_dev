// docs:start backend-hello
// lib/backend/functions/hello.get.dart is served at GET /api/hello.
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _hello(String name) async =>
    <String, Object?>{'greeting': 'Hello, $name'};
// docs:end
