// docs:start backend-stream
// lib/backend/functions/stream/ticks.get.dart
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Stream<String> _getTicks() => Stream<String>.periodic(
      const Duration(seconds: 1),
      (int i) => 'tick $i',
    ).take(10);
// docs:end
