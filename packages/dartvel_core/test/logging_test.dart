// Logs were listed as built in and there was no sink anywhere in the
// runtime: `DV.log` on the Flutter side reached analytics, and on the server
// side nothing an application logged went anywhere at all. These tests pin
// the behaviour that makes a log line worth writing -- that it can be parsed
// by a machine, that it can be joined to the trace it happened inside, that a
// long-running process cannot be brought down by its own log buffer, and that
// a password in a context map does not end up in the log file.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('DVLogger', () {
    test('a record below the minimum level reaches no sink', () {
      final DVMemoryLogSink sink = DVMemoryLogSink();
      final DVLogger logger = DVLogger(
        minimumLevel: DVLogLevel.warn,
        sinks: <DVLogSink>[sink],
      );

      logger.info('routine');
      logger.debug('noise');
      logger.warn('look at this');

      expect(
        sink.records.map((DVLogRecord r) => r.message),
        <String>['look at this'],
      );
    });

    test('a log written inside a span carries that span for correlation', () {
      final DVMemoryLogSink sink = DVMemoryLogSink();
      final DVLogger logger = DVLogger(sinks: <DVLogSink>[sink]);
      final DVSpan span = DVTracer().startSpan('GET /checkout');

      dvInSpan(span, () => logger.info('charged the card'));

      expect(sink.records.single.traceId, span.traceId);
      expect(sink.records.single.spanId, span.spanId);
    });

    test('a log written outside any span carries no trace id', () {
      final DVMemoryLogSink sink = DVMemoryLogSink();
      final DVLogger logger = DVLogger(sinks: <DVLogSink>[sink]);

      logger.info('startup');

      expect(sink.records.single.traceId, isNull);
      expect(sink.records.single.spanId, isNull);
    });

    test('an explicit trace id is not overwritten by the ambient span', () {
      final DVMemoryLogSink sink = DVMemoryLogSink();
      final DVLogger logger = DVLogger(sinks: <DVLogSink>[sink]);
      final DVSpan span = DVTracer().startSpan('worker');

      dvInSpan(
        span,
        () => logger.info('replaying', traceId: 'a' * 32, spanId: 'b' * 16),
      );

      expect(sink.records.single.traceId, 'a' * 32);
      expect(sink.records.single.spanId, 'b' * 16);
    });

    test('a context value that is not JSON becomes a string, not a throw', () {
      final DVMemoryLogSink sink = DVMemoryLogSink();
      final DVLogger logger = DVLogger(sinks: <DVLogSink>[sink]);

      logger.info('order', context: <String, Object?>{
        'at': DateTime.utc(2026, 1, 2, 3, 4, 5),
        'total': 12.5,
        'items': <int>[1, 2],
      });

      final Object? decoded = jsonDecode(sink.records.single.toJsonLine());
      final Map<String, Object?> context =
          (decoded! as Map<String, Object?>)['context']! as Map<String, Object?>;
      expect(context['at'], '2026-01-02 03:04:05.000Z');
      expect(context['total'], 12.5);
      expect(context['items'], <int>[1, 2]);
    });

    test('secrets in the context are redacted rather than written out', () {
      final DVMemoryLogSink sink = DVMemoryLogSink();
      final DVLogger logger = DVLogger(sinks: <DVLogSink>[sink]);

      logger.info('sign in', context: <String, Object?>{
        'email': 'ada@example.com',
        'password': 'hunter2',
        'Authorization': 'Bearer abc.def',
        'refreshToken': 'rt_live_123',
      });

      final String line = sink.records.single.toJsonLine();
      expect(line, contains('ada@example.com'));
      expect(line, isNot(contains('hunter2')));
      expect(line, isNot(contains('abc.def')));
      expect(line, isNot(contains('rt_live_123')));
    });

    test('an error log keeps the error text and the stack', () {
      final DVMemoryLogSink sink = DVMemoryLogSink();
      final DVLogger logger = DVLogger(sinks: <DVLogSink>[sink]);

      try {
        throw StateError('card declined');
      } on Object catch (error, stack) {
        logger.error('charge failed', error: error, stackTrace: stack);
      }

      final DVLogRecord record = sink.records.single;
      expect(record.error, contains('card declined'));
      expect(record.stackTrace, contains('logging_test.dart'));
      expect(record.level, DVLogLevel.error);
    });
  });

  group('DVMemoryLogSink', () {
    test('drops the oldest once full, so a long run cannot exhaust memory', () {
      final DVMemoryLogSink sink = DVMemoryLogSink(capacity: 3);
      final DVLogger logger = DVLogger(sinks: <DVLogSink>[sink]);

      for (int i = 0; i < 10; i += 1) {
        logger.info('line $i');
      }

      expect(sink.records, hasLength(3));
      expect(
        sink.records.map((DVLogRecord r) => r.message),
        <String>['line 7', 'line 8', 'line 9'],
      );
    });
  });

  group('DVJsonLinesSink', () {
    test('writes exactly one parseable JSON object per record', () {
      final List<String> lines = <String>[];
      final DVLogger logger = DVLogger(
        sinks: <DVLogSink>[DVJsonLinesSink(lines.add)],
      );

      logger.info('first');
      logger.warn('second', context: <String, Object?>{'orderId': 7});

      expect(lines, hasLength(2));
      for (final String line in lines) {
        expect(line, isNot(contains('\n')));
      }
      final Map<String, Object?> second =
          jsonDecode(lines[1]) as Map<String, Object?>;
      expect(second['message'], 'second');
      expect(second['level'], 'warn');
      expect(second['context'], <String, Object?>{'orderId': 7});
      expect(second['time'], isA<String>());
    });
  });

  group('DVObservability logging', () {
    setUp(() {
      DVObservability.metrics.reset();
      DVObservability.useLogging(sinks: <DVLogSink>[DVMemoryLogSink()]);
    });

    tearDown(DVObservability.resetLogging);

    test('DV.log reaches the configured sink', () {
      DVObservability.log('checkout completed',
          context: <String, Object?>{'orderId': 41});

      expect(
        DVObservability.recentLogs.single.message,
        'checkout completed',
      );
    });

    test('an event is a record a machine can select on by name', () {
      DVObservability.event(
        'checkout_completed',
        <String, Object?>{'orderId': 41},
      );

      final Map<String, Object?> decoded =
          jsonDecode(DVObservability.recentLogs.single.toJsonLine())
              as Map<String, Object?>;
      expect(decoded['event'], 'checkout_completed');
      expect(decoded['context'], <String, Object?>{'orderId': 41});
    });

    test('a captured error is counted, so an error rate can be alerted on', () {
      DVObservability.captureError(
        StateError('gateway timeout'),
        StackTrace.current,
        message: 'charge failed',
      );

      expect(
        DVObservability.render(),
        contains('dartvel_logs_total{level="error"} 1'),
      );
    });

    test('ordinary logs are counted by level too', () {
      DVObservability.log('one');
      DVObservability.log('two');

      expect(
        DVObservability.render(),
        contains('dartvel_logs_total{level="info"} 2'),
      );
    });

    test('a dropped log is still counted, so silence is visible', () {
      DVObservability.logger.minimumLevel = DVLogLevel.error;

      DVObservability.log('never written');

      expect(DVObservability.recentLogs, isEmpty);
      expect(
        DVObservability.render(),
        contains('dartvel_logs_total{level="info"} 1'),
      );
    });
  });
}
