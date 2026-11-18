// `dartvel.openTelemetry`: where traces, metrics and logs go.
//
// Two spellings feed one value. The pubspec says what a project wants and is
// read strictly, because a misspelt key replaced by its default looks exactly
// like a setting that was honoured. The standard OTEL_* environment variables
// say what a deployment wants and win, because that is how every OpenTelemetry
// SDK is configured and how an operator expects to point a service at a
// collector without rebuilding it -- and a mistyped variable must never stop a
// service from booting, so it is reported and ignored instead.
import 'package:dartvel_core/config.dart';
import 'package:test/test.dart';

void main() {
  group('the pubspec section', () {
    test('absent means off: nothing is exported by a project that never asked',
        () {
      final DVOpenTelemetryConfig config = DVOpenTelemetryConfig.parse(null);
      expect(config.enabled, isFalse);
      expect(config.exports, isFalse);
    });

    test('enabled with no endpoint sends to the OTLP default, localhost:4318',
        () {
      final DVOpenTelemetryConfig config =
          DVOpenTelemetryConfig.parse(<String, Object?>{'enabled': true});
      expect(config.exports, isTrue);
      expect(config.endpointFor(DVOtelSignal.traces).toString(),
          'http://localhost:4318/v1/traces');
      expect(config.endpointFor(DVOtelSignal.metrics).toString(),
          'http://localhost:4318/v1/metrics');
      expect(config.endpointFor(DVOtelSignal.logs).toString(),
          'http://localhost:4318/v1/logs');
      expect(config.protocol, DVOtlpProtocol.httpProtobuf,
          reason: 'http/protobuf is the OTLP default');
    });

    test('every setting is read', () {
      final DVOpenTelemetryConfig config =
          DVOpenTelemetryConfig.parse(<String, Object?>{
        'enabled': true,
        'endpoint': 'https://collector.internal:4318/',
        'protocol': 'http/json',
        'secretHeaders': <String, Object?>{'x-honeycomb-team': 'HONEYCOMB_KEY'},
        'serviceName': 'shop',
        'serviceVersion': '1.4.0',
        'resource': <String, Object?>{'deployment.environment.name': 'prod'},
        'traces': true,
        'metrics': false,
        'logs': true,
        'sampler': 'parentbased_traceidratio',
        'ratio': 0.25,
        'queue': 4096,
        'batch': 256,
        'scheduleDelayMs': 2000,
        'timeoutMs': 5000,
        'metricIntervalMs': 15000,
        'logLevel': 'warn',
      });
      expect(config.endpointFor(DVOtelSignal.traces).toString(),
          'https://collector.internal:4318/v1/traces',
          reason: 'a trailing slash on the base must not make //v1/traces');
      expect(config.protocol, DVOtlpProtocol.httpJson);
      expect(config.secretHeaders, <String, String>{'x-honeycomb-team': 'HONEYCOMB_KEY'});
      expect(config.serviceName, 'shop');
      expect(config.serviceVersion, '1.4.0');
      expect(config.resourceAttributes['deployment.environment.name'], 'prod');
      expect(config.metrics, isFalse);
      expect(config.endpointFor(DVOtelSignal.metrics), isNull,
          reason: 'a signal that is off has nowhere to go');
      expect(config.sampler, DVOtelSampler.parentBasedTraceIdRatio);
      expect(config.ratio, 0.25);
      expect(config.maxQueueSize, 4096);
      expect(config.maxExportBatchSize, 256);
      expect(config.scheduleDelay, const Duration(seconds: 2));
      expect(config.exportTimeout, const Duration(seconds: 5));
      expect(config.metricInterval, const Duration(seconds: 15));
      expect(config.logLevel, DVLogLevel.warn);
    });

    test('a misspelt key is refused, naming it', () {
      expect(
        () => DVOpenTelemetryConfig.parse(<String, Object?>{'endpiont': 'x'}),
        throwsA(isA<ArgumentError>().having((ArgumentError e) => e.name,
            'name', 'dartvel.openTelemetry.endpiont')),
      );
    });

    test('a literal header value is refused: headers carry keys, and a key '
        'written into pubspec.yaml is published with the repository', () {
      expect(
        () => DVOpenTelemetryConfig.parse(<String, Object?>{
          'headers': <String, Object?>{'x-api-key': 'abc'},
        }),
        throwsA(isA<ArgumentError>().having((ArgumentError e) => '${e.message}',
            'message', contains('secretHeaders'))),
      );
    });

    test('grpc is refused at build time rather than silently sent as HTTP', () {
      expect(
        () => DVOpenTelemetryConfig.parse(<String, Object?>{'protocol': 'grpc'}),
        throwsA(isA<ArgumentError>().having((ArgumentError e) => e.name,
            'name', 'dartvel.openTelemetry.protocol')),
      );
    });

    test('a ratio outside 0..1 is refused', () {
      expect(
        () => DVOpenTelemetryConfig.parse(<String, Object?>{'ratio': 1.5}),
        throwsArgumentError,
      );
    });

    test('an endpoint that is not an http(s) URL is refused', () {
      expect(
        () => DVOpenTelemetryConfig.parse(
            <String, Object?>{'endpoint': 'collector:4318'}),
        throwsArgumentError,
      );
    });

    test('the declaration round-trips: what the build embeds is what it read',
        () {
      final DVOpenTelemetryConfig read =
          DVOpenTelemetryConfig.parse(<String, Object?>{
        'enabled': true,
        'endpoint': 'https://c.example:4318',
        'secretHeaders': <String, Object?>{'authorization': 'OTEL_TOKEN'},
        'serviceName': 'shop',
        'resource': <String, Object?>{'team': 'checkout'},
        'logs': false,
        'sampler': 'traceidratio',
        'ratio': 0.5,
      });
      final DVOpenTelemetryConfig again =
          DVOpenTelemetryConfig.parse(read.toDeclaration());
      expect(again.toDeclaration(), read.toDeclaration());
      expect(again.logs, isFalse);
      expect(again.sampler, DVOtelSampler.traceIdRatio);
    });
  });

  group('the standard environment variables', () {
    test('OTEL_EXPORTER_OTLP_ENDPOINT alone turns export on: zero code, zero '
        'config, one variable on the deployment', () {
      final DVOpenTelemetryConfig config = DVOpenTelemetryConfig.parse(null)
          .withEnvironment(<String, String>{
        'OTEL_EXPORTER_OTLP_ENDPOINT': 'http://otel:4318',
      });
      expect(config.exports, isTrue);
      expect(config.endpointFor(DVOtelSignal.traces).toString(),
          'http://otel:4318/v1/traces');
    });

    test('a per-signal endpoint is used exactly as given, as the specification '
        'says', () {
      final DVOpenTelemetryConfig config = DVOpenTelemetryConfig.parse(null)
          .withEnvironment(<String, String>{
        'OTEL_EXPORTER_OTLP_ENDPOINT': 'http://otel:4318',
        'OTEL_EXPORTER_OTLP_TRACES_ENDPOINT': 'https://traces.example/ingest',
      });
      expect(config.endpointFor(DVOtelSignal.traces).toString(),
          'https://traces.example/ingest');
      expect(config.endpointFor(DVOtelSignal.logs).toString(),
          'http://otel:4318/v1/logs');
    });

    test('OTEL_SDK_DISABLED wins over everything', () {
      final DVOpenTelemetryConfig config =
          DVOpenTelemetryConfig.parse(<String, Object?>{'enabled': true})
              .withEnvironment(<String, String>{
        'OTEL_EXPORTER_OTLP_ENDPOINT': 'http://otel:4318',
        'OTEL_SDK_DISABLED': 'true',
      });
      expect(config.exports, isFalse);
    });

    test('headers are split and percent-decoded', () {
      final DVOpenTelemetryConfig config = DVOpenTelemetryConfig.parse(null)
          .withEnvironment(<String, String>{
        'OTEL_EXPORTER_OTLP_ENDPOINT': 'http://otel:4318',
        'OTEL_EXPORTER_OTLP_HEADERS':
            'x-honeycomb-team=abc%3D%3D, authorization=Bearer%20t0k',
      });
      expect(config.headers, <String, String>{
        'x-honeycomb-team': 'abc==',
        'authorization': 'Bearer t0k',
      });
    });

    test('service name and resource attributes, OTEL_SERVICE_NAME winning '
        'over a service.name in OTEL_RESOURCE_ATTRIBUTES', () {
      final DVOpenTelemetryConfig config =
          DVOpenTelemetryConfig.parse(<String, Object?>{'serviceName': 'from-pubspec'})
              .withEnvironment(<String, String>{
        'OTEL_RESOURCE_ATTRIBUTES':
            'service.name=from-resource,deployment.environment.name=staging,team=a%2Cb',
        'OTEL_SERVICE_NAME': 'from-env',
      });
      expect(config.serviceName, 'from-env');
      expect(config.resourceAttributes['deployment.environment.name'], 'staging');
      expect(config.resourceAttributes['team'], 'a,b');
    });

    test('the sampler and its argument', () {
      final DVOpenTelemetryConfig config = DVOpenTelemetryConfig.parse(null)
          .withEnvironment(<String, String>{
        'OTEL_TRACES_SAMPLER': 'parentbased_traceidratio',
        'OTEL_TRACES_SAMPLER_ARG': '0.1',
      });
      expect(config.sampler, DVOtelSampler.parentBasedTraceIdRatio);
      expect(config.ratio, 0.1);
    });

    test('OTEL_<SIGNAL>_EXPORTER=none turns that signal off', () {
      final DVOpenTelemetryConfig config = DVOpenTelemetryConfig.parse(null)
          .withEnvironment(<String, String>{
        'OTEL_EXPORTER_OTLP_ENDPOINT': 'http://otel:4318',
        'OTEL_METRICS_EXPORTER': 'none',
        'OTEL_LOGS_EXPORTER': 'none',
      });
      expect(config.traces, isTrue);
      expect(config.metrics, isFalse);
      expect(config.logs, isFalse);
    });

    test('the protocol, the timeout and the batch settings', () {
      final DVOpenTelemetryConfig config = DVOpenTelemetryConfig.parse(null)
          .withEnvironment(<String, String>{
        'OTEL_EXPORTER_OTLP_PROTOCOL': 'http/json',
        'OTEL_EXPORTER_OTLP_TIMEOUT': '3000',
        'OTEL_BSP_MAX_QUEUE_SIZE': '100',
        'OTEL_BSP_MAX_EXPORT_BATCH_SIZE': '10',
        'OTEL_BSP_SCHEDULE_DELAY': '250',
        'OTEL_METRIC_EXPORT_INTERVAL': '1000',
      });
      expect(config.protocol, DVOtlpProtocol.httpJson);
      expect(config.exportTimeout, const Duration(seconds: 3));
      expect(config.maxQueueSize, 100);
      expect(config.maxExportBatchSize, 10);
      expect(config.scheduleDelay, const Duration(milliseconds: 250));
      expect(config.metricInterval, const Duration(seconds: 1));
    });

    test('an unreadable value is reported and ignored, never a failed boot', () {
      final List<String> warnings = <String>[];
      final DVOpenTelemetryConfig config = DVOpenTelemetryConfig.parse(null)
          .withEnvironment(<String, String>{
        'OTEL_EXPORTER_OTLP_ENDPOINT': 'http://otel:4318',
        'OTEL_BSP_MAX_QUEUE_SIZE': 'lots',
        'OTEL_EXPORTER_OTLP_PROTOCOL': 'grpc',
        'OTEL_TRACES_SAMPLER': 'sometimes',
      }, warnings: warnings);
      expect(config.exports, isTrue);
      expect(config.maxQueueSize, 2048);
      expect(config.protocol, DVOtlpProtocol.httpProtobuf);
      expect(config.sampler, DVOtelSampler.parentBasedAlwaysOn);
      expect(warnings, hasLength(3));
      expect(warnings.join('\n'), contains('OTEL_EXPORTER_OTLP_PROTOCOL'));
    });
  });

  group('the Dart configuration class says the same thing', () {
    test('DartvelConfig.openTelemetry serialises to the pubspec section', () {
      const _Config config = _Config();
      final Map<String, Object?> pubspec = config.toPubspec();
      final DVOpenTelemetryConfig read =
          DVOpenTelemetryConfig.parse(pubspec['openTelemetry']);
      expect(read.toDeclaration(), config.openTelemetry!.toDeclaration());
      expect(read.serviceName, 'shop');
    });

    test('and the pubspec spelling reads back into the class', () {
      final DartvelPubspecConfig read =
          DartvelPubspecConfig.fromPubspec(<Object?, Object?>{
        'openTelemetry': <String, Object?>{
          'enabled': true,
          'serviceName': 'shop',
        },
      });
      expect(read.problems, isEmpty);
      expect(read.openTelemetry!.serviceName, 'shop');
      expect(read.toPubspec()['openTelemetry'],
          read.openTelemetry!.toDeclaration());
    });

    test('a pubspec problem is collected in the build\'s words', () {
      final DartvelPubspecConfig read =
          DartvelPubspecConfig.fromPubspec(<Object?, Object?>{
        'openTelemetry': <String, Object?>{'enabeld': true},
      });
      expect(read.problems.single, contains('dartvel.openTelemetry.enabeld'));
    });
  });
}

class _Config extends DartvelConfig {
  const _Config();

  @override
  DVOpenTelemetryConfig? get openTelemetry => const DVOpenTelemetryConfig(
        enabled: true,
        endpoint: 'https://collector.example:4318',
        serviceName: 'shop',
        secretHeaders: <String, String>{'authorization': 'OTEL_TOKEN'},
      );
}
