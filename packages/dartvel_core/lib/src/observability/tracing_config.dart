/// `dartvel.tracing`: where a server's spans go, and how many of them.
library dartvel.observability.tracing_config;

import '../http/transport.dart';
import 'observability.dart';

/// The exporters a declaration can name. OTLP is the only remote one, because
/// every trace backend worth sending to accepts it.
enum DVTracingExporterKind { none, otlp }

/// Tracing as a project declares it.
///
/// ```yaml
/// dartvel:
///   tracing:
///     ratio: 0.1                 # of traces kept, decided from the trace id
///     exporter: otlp             # otlp | none
///     endpoint: https://collector.internal:4318
///     queue: 2048                # spans held for export before dropping
///     maxSpanDuration: 5m        # an open span past this is closed, incomplete
/// ```
///
/// Read strictly, for the reason `dartvel.logging` is: every setting has a
/// default, so a misspelt key would be replaced by the default and look
/// exactly like a setting that was honoured. Each is refused, naming the key.
final class DVTracingConfig {
  const DVTracingConfig({
    this.ratio = 1,
    this.exporter = DVTracingExporterKind.none,
    this.endpoint,
    this.queue = 2048,
    this.maxSpanDuration,
  });

  /// The share of traces recorded. Everything by default: a framework that
  /// drops traces out of the box is one where the first question anybody
  /// debugging it asks is whether tracing is on.
  final double ratio;
  final DVTracingExporterKind exporter;

  /// The collector's OTLP/HTTP base URL; `/v1/traces` is appended unless it
  /// is already there.
  final Uri? endpoint;

  /// Spans held for export. Past it they are dropped and counted
  /// (`DV-TRACE-002`) rather than queued without bound.
  final int queue;

  /// How long a span may stay open before it is closed as incomplete
  /// (`DV-TRACE-009`), written `250ms`, `30s`, `5m` or `1h`. Unset tracks
  /// nothing.
  final Duration? maxSpanDuration;

  static const Set<String> _keys = <String>{
    'ratio',
    'exporter',
    'endpoint',
    'queue',
    'maxSpanDuration',
  };

  /// Reads the `dartvel.tracing` block, or the defaults for none.
  static DVTracingConfig parse(Object? value) {
    if (value == null) return const DVTracingConfig();
    if (value is! Map) {
      throw ArgumentError.value(value, 'tracing', 'must be a map of settings');
    }
    for (final Object? key in value.keys) {
      if (!_keys.contains(key)) {
        throw ArgumentError.value(value[key], 'tracing.$key',
            'is not a tracing setting (${_keys.join(', ')})');
      }
    }

    final Object? ratio = value['ratio'];
    if (ratio != null && (ratio is! num || ratio < 0 || ratio > 1)) {
      throw ArgumentError.value(
          ratio, 'tracing.ratio', 'must be a number from 0 to 1');
    }

    final Object? exporter = value['exporter'];
    final DVTracingExporterKind kind = switch (exporter) {
      null || 'none' => DVTracingExporterKind.none,
      'otlp' => DVTracingExporterKind.otlp,
      _ => throw ArgumentError.value(exporter, 'tracing.exporter',
          'must be otlp or none; every trace backend accepts OTLP'),
    };

    final Object? endpoint = value['endpoint'];
    Uri? uri;
    if (endpoint != null) {
      uri = endpoint is String ? Uri.tryParse(endpoint) : null;
      if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
        throw ArgumentError.value(
            endpoint, 'tracing.endpoint', 'must be an http or https URL');
      }
    }

    final Object? queue = value['queue'];
    if (queue != null && (queue is! int || queue < 1)) {
      throw ArgumentError.value(
          queue, 'tracing.queue', 'must be a whole number above 0');
    }

    final Object? maximum = value['maxSpanDuration'];
    Duration? maxSpanDuration;
    if (maximum != null) {
      maxSpanDuration = maximum is String ? _duration(maximum) : null;
      if (maxSpanDuration == null || maxSpanDuration <= Duration.zero) {
        throw ArgumentError.value(maximum, 'tracing.maxSpanDuration',
            'must be a positive duration such as 250ms, 30s, 5m or 1h');
      }
    }

    return DVTracingConfig(
      ratio: (ratio as num?)?.toDouble() ?? 1,
      exporter: kind,
      endpoint: uri,
      queue: (queue as int?) ?? 2048,
      maxSpanDuration: maxSpanDuration,
    );
  }

  /// This configuration as the block [parse] reads, so a generator can write
  /// it into a server's source.
  Map<String, Object?> toDeclaration() => <String, Object?>{
        'ratio': ratio,
        'exporter': exporter.name,
        if (endpoint != null) 'endpoint': '$endpoint',
        'queue': queue,
        if (maxSpanDuration != null)
          'maxSpanDuration': '${maxSpanDuration!.inMilliseconds}ms',
      };
}

final RegExp _durationPattern = RegExp(r'^(\d+)(ms|s|m|h)$');

Duration? _duration(String text) {
  final RegExpMatch? match = _durationPattern.firstMatch(text.trim());
  if (match == null) return null;
  final int amount = int.parse(match.group(1)!);
  return switch (match.group(2)) {
    'ms' => Duration(milliseconds: amount),
    's' => Duration(seconds: amount),
    'm' => Duration(minutes: amount),
    _ => Duration(hours: amount),
  };
}

/// [declared] with the environment's overrides applied.
///
/// The environment wins because it is what a deployment controls: the
/// collector for staging and the one for production are the same build.
/// `DARTVEL_TRACING_EXPORTER`, `DARTVEL_TRACING_ENDPOINT` and
/// `DARTVEL_TRACING_RATIO` are read, and the OpenTelemetry names
/// (`OTEL_EXPORTER_OTLP_TRACES_ENDPOINT`, `OTEL_EXPORTER_OTLP_ENDPOINT`) too,
/// since a platform that injects a collector sets those. An endpoint in the
/// environment with no exporter named is a request to export.
///
/// An unreadable value keeps the declared one rather than throwing: a typo in
/// a deployment's environment must not be the reason a service will not boot.
DVTracingConfig dvResolveTracingConfig(
  Map<String, String> environment, {
  DVTracingConfig declared = const DVTracingConfig(),
}) {
  String? read(String name) {
    final String value = (environment[name] ?? '').trim();
    return value.isEmpty ? null : value;
  }

  double ratio = declared.ratio;
  final double? envRatio = double.tryParse(read('DARTVEL_TRACING_RATIO') ?? '');
  if (envRatio != null && envRatio >= 0 && envRatio <= 1) ratio = envRatio;

  Uri? endpoint = declared.endpoint;
  final String? envEndpoint = read('DARTVEL_TRACING_ENDPOINT') ??
      read('OTEL_EXPORTER_OTLP_TRACES_ENDPOINT') ??
      read('OTEL_EXPORTER_OTLP_ENDPOINT');
  final Uri? parsedEndpoint =
      envEndpoint == null ? null : Uri.tryParse(envEndpoint);
  final bool endpointFromEnvironment = parsedEndpoint != null &&
      (parsedEndpoint.isScheme('http') || parsedEndpoint.isScheme('https'));
  if (endpointFromEnvironment) endpoint = parsedEndpoint;

  DVTracingExporterKind exporter = declared.exporter;
  if (endpointFromEnvironment) exporter = DVTracingExporterKind.otlp;
  switch (read('DARTVEL_TRACING_EXPORTER')?.toLowerCase()) {
    case 'none':
      exporter = DVTracingExporterKind.none;
    case 'otlp':
      exporter = DVTracingExporterKind.otlp;
  }

  return DVTracingConfig(
    ratio: ratio,
    exporter: exporter,
    endpoint: endpoint,
    queue: declared.queue,
    maxSpanDuration: declared.maxSpanDuration,
  );
}

/// Installs the server's tracing: the sampling ratio, and the OTLP exporter
/// when one is configured. Returns that exporter so shutdown can flush it.
///
/// Says where spans go, once, at startup: `DV-TRACE-006` when they stay in the
/// process, `DV-TRACE-007` when the endpoint listing them is open.
DVOtlpTraceExporter? dvConfigureRuntimeTracing(
  Map<String, String> environment, {
  DVTracingConfig declared = const DVTracingConfig(),
  String serviceName = 'dartvel',
  DVHttpSend? send,
}) {
  final DVTracingConfig config =
      dvResolveTracingConfig(environment, declared: declared);
  final Uri? endpoint = config.endpoint;

  DVOtlpTraceExporter? exporter;
  if (config.exporter == DVTracingExporterKind.otlp && endpoint != null) {
    final String? service = environment['OTEL_SERVICE_NAME']?.trim();
    exporter = DVOtlpTraceExporter(
      endpoint: endpoint,
      serviceName: service == null || service.isEmpty ? serviceName : service,
      headers: _otelHeaders(environment['OTEL_EXPORTER_OTLP_HEADERS']),
      queueCapacity: config.queue,
      send: send,
    );
  } else {
    DVObservability.log(
      config.exporter == DVTracingExporterKind.otlp
          ? 'DV-TRACE-006: tracing.exporter is otlp and no endpoint is '
              'configured; spans stay in the in-process buffer.'
          : 'DV-TRACE-006: no trace exporter is configured; spans stay in the '
              'in-process buffer.',
      code: 'DV-TRACE-006',
    );
  }

  DVObservability.useTracing(
    exporter: exporter,
    ratio: config.ratio,
    maxSpanDuration: config.maxSpanDuration,
  );

  if (dvDiagnosticsEnabled(environment)) {
    DVObservability.log(
      'DV-TRACE-007: the trace diagnostics endpoint /_dartvel/traces is '
      'enabled; it lists recent requests and is off by default.',
      level: DVLogLevel.warn,
      code: 'DV-TRACE-007',
    );
  }
  return exporter;
}

/// `OTEL_EXPORTER_OTLP_HEADERS`: `key=value` pairs separated by commas, values
/// percent-encoded, as the OpenTelemetry specification defines it.
Map<String, String> _otelHeaders(String? value) {
  final Map<String, String> headers = <String, String>{};
  for (final String pair in (value ?? '').split(',')) {
    final int equals = pair.indexOf('=');
    if (equals <= 0) continue;
    final String key = pair.substring(0, equals).trim().toLowerCase();
    String headerValue = pair.substring(equals + 1).trim();
    try {
      headerValue = Uri.decodeComponent(headerValue);
    } on ArgumentError {
      // Not percent-encoded after all; send it as written.
    }
    if (key.isNotEmpty) headers[key] = headerValue;
  }
  return headers;
}
