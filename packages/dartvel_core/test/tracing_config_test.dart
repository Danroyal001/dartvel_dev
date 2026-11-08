// dartvel.tracing, and the environment that overrides it at deploy time.
//
// The exporter existing is not spans reaching a collector: something has to
// turn it on in a deployed server. The silent failures are a misspelt key
// read as "use the default" and a server that exports nowhere without saying
// so -- the tracing that looks switched on and finds nothing.
import 'package:dartvel_core/src/http/transport.dart';
import 'package:dartvel_core/src/observability/observability.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    DVObservability.resetLogging();
    DVObservability.resetTracing();
  });
  tearDown(DVObservability.resetTracing);

  group('dartvel.tracing', () {
    test('nothing declared is no exporter, sampling everything', () {
      final DVTracingConfig config = DVTracingConfig.parse(null);
      expect(config.exporter, DVTracingExporterKind.none);
      expect(config.ratio, 1);
      expect(config.queue, 2048);
    });

    test('the declared block is read', () {
      final DVTracingConfig config = DVTracingConfig.parse(<String, Object?>{
        'ratio': 0.1,
        'exporter': 'otlp',
        'endpoint': 'https://collector.internal:4318',
        'queue': 512,
      });
      expect(config.exporter, DVTracingExporterKind.otlp);
      expect(config.ratio, 0.1);
      expect(config.endpoint, Uri.parse('https://collector.internal:4318'));
      expect(config.queue, 512);
    });

    test('a misspelt key, a ratio out of range and an unknown exporter are '
        'refused, naming the key', () {
      expect(
        () => DVTracingConfig.parse(<String, Object?>{'ration': 0.1}),
        throwsA(isA<ArgumentError>()
            .having((ArgumentError e) => e.name, 'name', 'tracing.ration')),
      );
      expect(
        () => DVTracingConfig.parse(<String, Object?>{'ratio': 10}),
        throwsA(isA<ArgumentError>()
            .having((ArgumentError e) => e.name, 'name', 'tracing.ratio')),
      );
      expect(
        () => DVTracingConfig.parse(<String, Object?>{'exporter': 'jaeger'}),
        throwsA(isA<ArgumentError>()
            .having((ArgumentError e) => e.name, 'name', 'tracing.exporter')),
      );
      expect(
        () => DVTracingConfig.parse(<String, Object?>{'queue': 0}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('round-trips through its declaration', () {
      final DVTracingConfig config = DVTracingConfig.parse(<String, Object?>{
        'ratio': 0.25,
        'exporter': 'otlp',
        'endpoint': 'http://127.0.0.1:4318',
      });
      final DVTracingConfig again =
          DVTracingConfig.parse(config.toDeclaration());
      expect(again.ratio, 0.25);
      expect(again.exporter, DVTracingExporterKind.otlp);
      expect(again.endpoint, config.endpoint);
    });
  });

  group('at startup', () {
    test('with no exporter, spans stay in the buffer and DV-TRACE-006 says so',
        () {
      final DVOtlpTraceExporter? exporter =
          dvConfigureRuntimeTracing(const <String, String>{});
      expect(exporter, isNull);
      expect(
        DVObservability.recentLogs.where((r) => r.code == 'DV-TRACE-006'),
        hasLength(1),
      );
    });

    test('a declared OTLP exporter is installed, and spans reach it as well '
        'as the local buffer', () async {
      final List<DVHttpRequest> sent = <DVHttpRequest>[];
      final DVOtlpTraceExporter? exporter = dvConfigureRuntimeTracing(
        const <String, String>{},
        declared: DVTracingConfig.parse(<String, Object?>{
          'exporter': 'otlp',
          'endpoint': 'http://collector.test:4318',
        }),
        serviceName: 'shop',
        send: (DVHttpRequest request) async {
          sent.add(request);
          return const DVHttpResponse(statusCode: 200, body: '');
        },
      );
      expect(exporter, isNotNull);
      expect(exporter!.serviceName, 'shop');

      DVObservability.tracer.startSpan('GET /').end();
      await exporter.flush();

      expect(sent.single.url.toString(), 'http://collector.test:4318/v1/traces');
      expect(DVObservability.recentSpans, hasLength(1));
      expect(
        DVObservability.recentLogs.where((r) => r.code == 'DV-TRACE-006'),
        isEmpty,
      );
    });

    test('the environment overrides the declaration, OpenTelemetry names too',
        () {
      final DVOtlpTraceExporter? exporter = dvConfigureRuntimeTracing(
        const <String, String>{
          'OTEL_EXPORTER_OTLP_ENDPOINT': 'https://api.honeycomb.io',
          'OTEL_EXPORTER_OTLP_HEADERS': 'x-honeycomb-team=abc123,x-extra=1',
          'OTEL_SERVICE_NAME': 'checkout',
          'DARTVEL_TRACING_RATIO': '0.5',
        },
      );
      expect(exporter, isNotNull,
          reason: 'an endpoint in the environment is a request to export');
      expect(exporter!.endpoint.toString(), 'https://api.honeycomb.io/v1/traces');
      expect(exporter.headers['x-honeycomb-team'], 'abc123');
      expect(exporter.headers['x-extra'], '1');
      expect(exporter.serviceName, 'checkout');
    });

    test('DARTVEL_TRACING_EXPORTER=none wins over a declared exporter', () {
      final DVOtlpTraceExporter? exporter = dvConfigureRuntimeTracing(
        const <String, String>{'DARTVEL_TRACING_EXPORTER': 'none'},
        declared: DVTracingConfig.parse(<String, Object?>{
          'exporter': 'otlp',
          'endpoint': 'http://collector.test:4318',
        }),
      );
      expect(exporter, isNull);
    });

    test('an unreadable ratio in the environment keeps the declared one and '
        'does not stop the boot', () {
      final DVTracingConfig resolved = dvResolveTracingConfig(
        const <String, String>{'DARTVEL_TRACING_RATIO': 'ten percent'},
        declared: DVTracingConfig.parse(<String, Object?>{'ratio': 0.2}),
      );
      expect(resolved.ratio, 0.2);
    });

    test('the sampling ratio is applied', () {
      dvConfigureRuntimeTracing(
        const <String, String>{'DARTVEL_TRACING_RATIO': '0'},
      );
      for (int i = 0; i < 20; i++) {
        DVObservability.tracer.startSpan('GET /').end();
      }
      expect(DVObservability.recentSpans, isEmpty);
    });

    test('diagnostics endpoints on is reported as DV-TRACE-007', () {
      dvConfigureRuntimeTracing(
          const <String, String>{'DARTVEL_DIAGNOSTICS': '1'});
      expect(
        DVObservability.recentLogs.where((r) => r.code == 'DV-TRACE-007'),
        hasLength(1),
      );
    });
  });
}
