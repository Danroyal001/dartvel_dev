// Logging is DV.log and DV.ObservabilityAndLogging, on the server too.
//
// The specification names those two. Backend code had neither -- the DV
// facade lives in the Flutter layer, which a server build does not import --
// so every backend function and every framework file reached for
// DVObservability, and that is what the docs then showed.
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  setUp(DV.ObservabilityAndLogging.resetLogging);
  tearDown(DV.ObservabilityAndLogging.resetLogging);

  test('DV.log writes a record', () {
    DV.log('export 42 failed', level: DVLogLevel.warn);

    final DVLogRecord last = DV.ObservabilityAndLogging.recentLogs.last;
    expect(last.message, 'export 42 failed');
    expect(last.level, DVLogLevel.warn);
  });

  test('DV.ObservabilityAndLogging carries what a server reports', () {
    DV.ObservabilityAndLogging.event('checkout_completed',
        fields: <String, Object?>{'orderId': 'o1'});

    expect(DV.ObservabilityAndLogging.recentLogs.last.message,
        'checkout_completed');
    expect(DV.ObservabilityAndLogging.metrics, isNotNull);
    expect(DV.ObservabilityAndLogging.health, isNotNull);
  });

  test('the implementation is not the public surface', () {
    // DVObservability was the name every project learned, and it is not one
    // of the two the specification names.
    final String barrel = File('lib/dartvel.dart').readAsStringSync();

    expect(barrel, isNot(contains("export 'src/observability/observability.dart';")),
        reason: 'the implementation class is exported again');
  });
}
