/// Turning OpenTelemetry export on for a process: the tracer, the logger and
/// the metrics registry each given an OTLP destination.
library dartvel.observability.open_telemetry;

import 'dart:async';
import 'dart:math';

import '../secrets/secrets.dart';
import 'logging.dart';
import 'metrics.dart';
import 'observability.dart' show DVObservability;
import 'open_telemetry_config.dart';
import 'otel_process_unsupported.dart'
    if (dart.library.io) 'otel_process_io.dart';
import 'otlp.dart';
import 'tracing.dart';

/// OpenTelemetry export for this process.
///
/// A generated server, worker or cron process calls [install] at start with
/// the project's `dartvel.openTelemetry` section and the process environment,
/// so a project exports with no code at all. Code that wants control calls it
/// itself with a [DVOpenTelemetryConfig] -- `DV.ObservabilityAndLogging
/// .useOpenTelemetry(...)` is the same call.
abstract final class DVOpenTelemetry {
  static DVOtlpExporter? _exporter;
  static Timer? _metricTimer;

  /// The exporter in use, or null when nothing is exported.
  static DVOtlpExporter? get exporter => _exporter;

  /// Whether this process is exporting anything.
  static bool get installed => _exporter != null;

  /// Starts exporting as [config] says, replacing any earlier installation.
  ///
  /// [environment] is applied over [config] with
  /// [DVOpenTelemetryConfig.withEnvironment] -- the process environment on a
  /// server, nothing in a browser -- and what it could not read is logged.
  /// `secretHeaders` are resolved through `DV.Secrets` here, and a missing
  /// secret throws naming it: export that silently went out unauthenticated
  /// would be rejected by the collector and look exactly like no traffic.
  ///
  /// Returns the configuration in force.
  static DVOpenTelemetryConfig install(
    DVOpenTelemetryConfig config, {
    Map<String, String>? environment,
    DVOtlpSend? send,
    Map<String, Object> resource = const <String, Object>{},
  }) {
    final List<String> warnings = <String>[];
    final DVOpenTelemetryConfig effective = config.withEnvironment(
        environment ?? dvOtelEnvironment(),
        warnings: warnings);
    for (final String warning in warnings) {
      DVObservability.log(warning,
          level: DVLogLevel.warn, tag: dvOtelLogTag, code: 'DV-TRACE-011');
    }
    _stop();
    if (!effective.exports) return effective;

    final Map<String, String> headers = <String, String>{
      for (final MapEntry<String, String> header
          in effective.secretHeaders.entries)
        header.key: const DVSecrets().get(header.value),
    };
    final Map<String, String> env = environment ?? dvOtelEnvironment();
    final DVOtlpExporter exporter = DVOtlpExporter(
      config: effective,
      headers: headers,
      send: send,
      resource: <String, Object>{
        'service.instance.id': _instanceId(),
        if (env['DARTVEL_ENVIRONMENT'] case final String name when name.isNotEmpty)
          'deployment.environment.name': name,
        if (env['DARTVEL_ROLE'] case final String role when role.isNotEmpty)
          'dartvel.process.role': role,
        ...dvOtelProcessResource(),
        ...resource,
      },
    );
    _exporter = exporter;

    if (effective.traces) {
      DVObservability.useTracing(
        exporter: exporter.spans,
        sampler: _sampler(effective),
      );
    }
    if (effective.logs) DVObservability.useOpenTelemetryLogs(exporter.logs);
    if (effective.metrics) {
      DVObservability.semanticMetrics = true;
      _metricTimer = Timer.periodic(effective.metricInterval, (_) {
        unawaited(exportMetricsNow());
      });
    }
    DVObservability.log(
      'OpenTelemetry export is on: ${<String>[
        if (effective.traces) 'traces',
        if (effective.metrics) 'metrics',
        if (effective.logs) 'logs',
      ].join(', ')} to ${effective.endpointFor(DVOtelSignal.traces) ?? effective.endpointFor(DVOtelSignal.metrics) ?? effective.endpointFor(DVOtelSignal.logs)} '
      'as ${exporter.resource['service.name']}.',
      tag: dvOtelLogTag,
    );
    return effective;
  }

  /// Collects the registry and sends it now, with the runtime gauges brought
  /// up to date first.
  static Future<void> exportMetricsNow() async {
    final DVOtlpExporter? exporter = _exporter;
    if (exporter == null) return;
    recordRuntimeMetrics();
    await exporter.exportMetrics(DVObservability.metrics.collect());
  }

  /// The runtime gauges: uptime and, where the platform says, memory.
  static void recordRuntimeMetrics() {
    final DVMetrics metrics = DVObservability.metrics;
    DVObservability.refresh();
    metrics.setUnit('process.uptime', 's');
    metrics
        .gauge('process.uptime', const <String, String>{},
            'The time the process has been running.')
        .set(DVObservability.health.uptime.inMilliseconds / 1000);
    final ({int current, int peak})? memory = dvOtelProcessMemory();
    if (memory != null) {
      metrics.setUnit('process.memory.usage', 'By');
      metrics
          .gauge('process.memory.usage', const <String, String>{},
              'The amount of physical memory in use (resident set size).')
          .set(memory.current.toDouble());
      metrics.setUnit('dartvel.process.memory.peak', 'By');
      metrics
          .gauge('dartvel.process.memory.peak', const <String, String>{},
              'The most physical memory the process has held.')
          .set(memory.peak.toDouble());
    }
  }

  /// Sends everything queued now.
  static Future<void> forceFlush() async {
    await exportMetricsNow();
    await _exporter?.forceFlush();
  }

  /// Sends what is left and stops exporting. A server calls this when it is
  /// told to stop, or the last seconds of spans go with the process.
  static Future<void> shutdown() async {
    final DVOtlpExporter? exporter = _exporter;
    if (exporter == null) return;
    await exportMetricsNow();
    _stop();
    await exporter.shutdown();
  }

  static void _stop() {
    _metricTimer?.cancel();
    _metricTimer = null;
    if (_exporter != null) {
      DVObservability.resetTracing();
      DVObservability.useOpenTelemetryLogs(null);
      DVObservability.semanticMetrics = false;
    }
    _exporter = null;
  }

  static DVTraceSampler _sampler(DVOpenTelemetryConfig config) =>
      switch (config.sampler) {
        DVOtelSampler.alwaysOn => DVTraceSampler.ratio(1, parentBased: false),
        DVOtelSampler.alwaysOff => DVTraceSampler.ratio(0, parentBased: false),
        DVOtelSampler.traceIdRatio =>
          DVTraceSampler.ratio(config.ratio, parentBased: false),
        DVOtelSampler.parentBasedAlwaysOn => DVTraceSampler.always(),
        DVOtelSampler.parentBasedAlwaysOff => DVTraceSampler.never(),
        DVOtelSampler.parentBasedTraceIdRatio =>
          DVTraceSampler.ratio(config.ratio),
      };

  /// A random id for this process, so two replicas of one service are two
  /// instances in the backend rather than one that is mysteriously busy.
  static String _instanceId() {
    final Random random = Random.secure();
    return List<String>.generate(
            16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
