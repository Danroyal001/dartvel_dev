/// `dartvel.openTelemetry`: where a process sends its traces, metrics and
/// logs, in OTLP, to any OpenTelemetry collector.
library dartvel.observability.open_telemetry_config;

import 'logging.dart' show DVLogLevel;

/// The three OpenTelemetry signals.
enum DVOtelSignal { traces, metrics, logs }

/// How OTLP is put on the wire. Both are OTLP over HTTP; gRPC is not built
/// (see the docs page for why), and a collector serves HTTP on 4318 by
/// default.
enum DVOtlpProtocol {
  /// `http/protobuf`: the OTLP default, and the smaller body.
  httpProtobuf('http/protobuf'),

  /// `http/json`: readable on the wire, for a collector or proxy that wants it.
  httpJson('http/json');

  const DVOtlpProtocol(this.spelling);

  /// The name `OTEL_EXPORTER_OTLP_PROTOCOL` and the pubspec use.
  final String spelling;
}

/// The OpenTelemetry samplers, by their `OTEL_TRACES_SAMPLER` names.
enum DVOtelSampler {
  alwaysOn('always_on'),
  alwaysOff('always_off'),
  traceIdRatio('traceidratio'),
  parentBasedAlwaysOn('parentbased_always_on'),
  parentBasedAlwaysOff('parentbased_always_off'),
  parentBasedTraceIdRatio('parentbased_traceidratio');

  const DVOtelSampler(this.spelling);
  final String spelling;

  bool get parentBased => name.startsWith('parentBased');
}

/// OpenTelemetry export as a project declares it, and as a deployment's
/// environment overrides it.
///
/// ```yaml
/// dartvel:
///   openTelemetry:
///     enabled: true
///     endpoint: https://collector.internal:4318   # OTLP/HTTP base URL
///     protocol: http/protobuf                     # or http/json
///     secretHeaders:                              # header: DV.Secrets name
///       x-honeycomb-team: HONEYCOMB_API_KEY
///     serviceName: shop                           # default: the package name
///     resource:
///       deployment.environment.name: production
///     traces: true
///     metrics: true
///     logs: true
///     sampler: parentbased_traceidratio
///     ratio: 0.1
/// ```
///
/// The pubspec is read strictly, for the reason every `dartvel.*` section is:
/// each setting has a default, so a misspelt key or a string where a number
/// belongs would be replaced by it and look exactly like a setting that was
/// honoured. The standard `OTEL_*` variables are read leniently by
/// [withEnvironment], and win.
final class DVOpenTelemetryConfig {
  const DVOpenTelemetryConfig({
    this.enabled = false,
    this.endpoint,
    this.tracesEndpoint,
    this.metricsEndpoint,
    this.logsEndpoint,
    this.protocol = DVOtlpProtocol.httpProtobuf,
    this.headers = const <String, String>{},
    this.secretHeaders = const <String, String>{},
    this.serviceName,
    this.serviceVersion,
    this.resourceAttributes = const <String, String>{},
    this.traces = true,
    this.metrics = true,
    this.logs = true,
    this.sampler = DVOtelSampler.parentBasedAlwaysOn,
    this.ratio = 1,
    this.maxQueueSize = 2048,
    this.maxExportBatchSize = 512,
    this.scheduleDelay = const Duration(seconds: 5),
    this.exportTimeout = const Duration(seconds: 10),
    this.metricInterval = const Duration(seconds: 60),
    this.logLevel = DVLogLevel.info,
  });

  /// Whether anything is exported at all. Off unless the project says so or
  /// the deployment names an OTLP endpoint.
  final bool enabled;

  /// The collector's OTLP/HTTP base URL; each signal is sent to
  /// `<endpoint>/v1/<signal>`. Null means `http://localhost:4318`.
  final String? endpoint;

  /// A signal's own URL, used exactly as given, as
  /// `OTEL_EXPORTER_OTLP_<SIGNAL>_ENDPOINT` is.
  final String? tracesEndpoint;
  final String? metricsEndpoint;
  final String? logsEndpoint;

  final DVOtlpProtocol protocol;

  /// Headers sent with every export, with their values. Only the environment
  /// sets these (`OTEL_EXPORTER_OTLP_HEADERS`), because a header usually
  /// carries a key and a key in pubspec.yaml is published with the repository.
  final Map<String, String> headers;

  /// Headers whose values are `DV.Secrets` names, resolved when export starts.
  final Map<String, String> secretHeaders;

  /// `service.name`. Null means the application's package name.
  final String? serviceName;

  /// `service.version`. Null means the application's pubspec version.
  final String? serviceVersion;

  /// More resource attributes, as `OTEL_RESOURCE_ATTRIBUTES` gives them.
  final Map<String, String> resourceAttributes;

  /// Whether each signal is exported.
  final bool traces;
  final bool metrics;
  final bool logs;

  final DVOtelSampler sampler;

  /// The share of traces a ratio sampler keeps, 0 to 1.
  final double ratio;

  /// Spans or log records held for export; past it new ones are dropped and
  /// counted, never queued without bound.
  final int maxQueueSize;

  /// The most spans or records in one export request.
  final int maxExportBatchSize;

  /// How long a part-full batch waits before it is sent anyway.
  final Duration scheduleDelay;

  /// How long one export request may take.
  final Duration exportTimeout;

  /// How often metrics are collected and sent.
  final Duration metricInterval;

  /// The lowest log level exported.
  final DVLogLevel logLevel;

  /// Whether this configuration sends anything anywhere.
  bool get exports => enabled && (traces || metrics || logs);

  /// Where [signal] is sent, or null when it is not exported.
  Uri? endpointFor(DVOtelSignal signal) {
    if (!enabled) return null;
    final bool on = switch (signal) {
      DVOtelSignal.traces => traces,
      DVOtelSignal.metrics => metrics,
      DVOtelSignal.logs => logs,
    };
    if (!on) return null;
    final String? own = switch (signal) {
      DVOtelSignal.traces => tracesEndpoint,
      DVOtelSignal.metrics => metricsEndpoint,
      DVOtelSignal.logs => logsEndpoint,
    };
    if (own != null) return Uri.parse(own);
    String base = endpoint ?? 'http://localhost:4318';
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return Uri.parse('$base/v1/${signal.name}');
  }

  static const String _section = 'dartvel.openTelemetry';

  /// The settings the pubspec section takes.
  static const List<String> settings = <String>[
    'enabled',
    'endpoint',
    'tracesEndpoint',
    'metricsEndpoint',
    'logsEndpoint',
    'protocol',
    'secretHeaders',
    'serviceName',
    'serviceVersion',
    'resource',
    'traces',
    'metrics',
    'logs',
    'sampler',
    'ratio',
    'queue',
    'batch',
    'scheduleDelayMs',
    'timeoutMs',
    'metricIntervalMs',
    'logLevel',
  ];

  /// Reads the `dartvel.openTelemetry` section, or the defaults when there is
  /// none. Throws [ArgumentError] naming the key for anything it cannot
  /// honour.
  factory DVOpenTelemetryConfig.parse(Object? section) {
    if (section == null) return const DVOpenTelemetryConfig();
    if (section is! Map) {
      throw ArgumentError.value(section, _section, 'must be a map of settings');
    }
    if (section.containsKey('headers')) {
      throw ArgumentError.value(
          section['headers'],
          '$_section.headers',
          'is not a setting: a header usually carries a key, and a key written '
              'into pubspec.yaml is published with the repository. Use '
              'secretHeaders, whose values name DV.Secrets entries, or '
              'OTEL_EXPORTER_OTLP_HEADERS on the deployment');
    }
    for (final Object? name in section.keys) {
      if (!settings.contains('$name')) {
        throw ArgumentError.value(section[name], '$_section.$name',
            'is not a setting here; the settings are ${settings.join(', ')}');
      }
    }
    const DVOpenTelemetryConfig defaults = DVOpenTelemetryConfig();
    final DVOtelSampler sampler = _choice(section['sampler'], '$_section.sampler',
        DVOtelSampler.values, (DVOtelSampler s) => s.spelling, defaults.sampler);
    return DVOpenTelemetryConfig(
      enabled: _bool(section['enabled'], 'enabled', defaults.enabled),
      endpoint: _url(section['endpoint'], 'endpoint'),
      tracesEndpoint: _url(section['tracesEndpoint'], 'tracesEndpoint'),
      metricsEndpoint: _url(section['metricsEndpoint'], 'metricsEndpoint'),
      logsEndpoint: _url(section['logsEndpoint'], 'logsEndpoint'),
      protocol: _protocol(section['protocol']),
      secretHeaders: _stringMap(section['secretHeaders'], 'secretHeaders'),
      serviceName: _string(section['serviceName'], 'serviceName'),
      serviceVersion: _string(section['serviceVersion'], 'serviceVersion'),
      resourceAttributes: _stringMap(section['resource'], 'resource'),
      traces: _bool(section['traces'], 'traces', true),
      metrics: _bool(section['metrics'], 'metrics', true),
      logs: _bool(section['logs'], 'logs', true),
      sampler: sampler,
      ratio: _ratio(section['ratio']),
      maxQueueSize:
          _int(section['queue'], 'queue', defaults.maxQueueSize, minimum: 1),
      maxExportBatchSize: _int(
          section['batch'], 'batch', defaults.maxExportBatchSize,
          minimum: 1),
      scheduleDelay: Duration(
          milliseconds: _int(section['scheduleDelayMs'], 'scheduleDelayMs',
              defaults.scheduleDelay.inMilliseconds,
              minimum: 1)),
      exportTimeout: Duration(
          milliseconds: _int(section['timeoutMs'], 'timeoutMs',
              defaults.exportTimeout.inMilliseconds,
              minimum: 1)),
      metricInterval: Duration(
          milliseconds: _int(section['metricIntervalMs'], 'metricIntervalMs',
              defaults.metricInterval.inMilliseconds,
              minimum: 100)),
      logLevel: _choice(section['logLevel'], '$_section.logLevel',
          DVLogLevel.values, (DVLogLevel l) => l.name, defaults.logLevel),
    );
  }

  /// This configuration with the standard OpenTelemetry environment
  /// variables applied over it.
  ///
  /// The environment wins: it is how every OpenTelemetry SDK is configured,
  /// and how an operator points a service at a collector without rebuilding
  /// it. An `OTEL_EXPORTER_OTLP_*ENDPOINT` turns export on by itself.
  /// A value that cannot be read is added to [warnings] and ignored -- a
  /// mistyped variable must never be the reason a service will not boot.
  DVOpenTelemetryConfig withEnvironment(
    Map<String, String> environment, {
    List<String>? warnings,
  }) {
    final List<String> problems = warnings ?? <String>[];
    String? read(String key) {
      final String? value = environment[key]?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    bool on = enabled;
    String? base = endpoint;
    String? traceUrl = tracesEndpoint;
    String? metricUrl = metricsEndpoint;
    String? logUrl = logsEndpoint;

    String? url(String key) {
      final String? value = read(key);
      if (value == null) return null;
      final Uri? parsed = Uri.tryParse(value);
      if (parsed == null || !(parsed.isScheme('http') || parsed.isScheme('https'))) {
        problems.add('$key=$value is not an http(s) URL; ignored.');
        return null;
      }
      on = true;
      return value;
    }

    base = url('OTEL_EXPORTER_OTLP_ENDPOINT') ?? base;
    traceUrl = url('OTEL_EXPORTER_OTLP_TRACES_ENDPOINT') ?? traceUrl;
    metricUrl = url('OTEL_EXPORTER_OTLP_METRICS_ENDPOINT') ?? metricUrl;
    logUrl = url('OTEL_EXPORTER_OTLP_LOGS_ENDPOINT') ?? logUrl;

    DVOtlpProtocol wire = protocol;
    final String? protocolValue = read('OTEL_EXPORTER_OTLP_PROTOCOL');
    if (protocolValue != null) {
      final DVOtlpProtocol? known = DVOtlpProtocol.values
          .where((DVOtlpProtocol p) => p.spelling == protocolValue)
          .firstOrNull;
      if (known == null) {
        problems.add('OTEL_EXPORTER_OTLP_PROTOCOL=$protocolValue is not '
            'supported; Dartvel sends http/protobuf or http/json, so '
            '${wire.spelling} is used. Point the endpoint at the collector\'s '
            'OTLP/HTTP port (4318), not its gRPC one (4317).');
      } else {
        wire = known;
      }
    }

    final Map<String, String> sentHeaders = <String, String>{...headers};
    final String? headerValue = read('OTEL_EXPORTER_OTLP_HEADERS');
    if (headerValue != null) {
      final Map<String, String>? parsed =
          _keyValues(headerValue, 'OTEL_EXPORTER_OTLP_HEADERS', problems);
      if (parsed != null) sentHeaders.addAll(parsed);
    }

    final Map<String, String> resource = <String, String>{...resourceAttributes};
    final String? resourceValue = read('OTEL_RESOURCE_ATTRIBUTES');
    String? name = serviceName;
    if (resourceValue != null) {
      final Map<String, String>? parsed =
          _keyValues(resourceValue, 'OTEL_RESOURCE_ATTRIBUTES', problems);
      if (parsed != null) {
        final String? named = parsed.remove('service.name');
        if (named != null) name = named;
        resource.addAll(parsed);
      }
    }
    name = read('OTEL_SERVICE_NAME') ?? name;

    bool signal(String key, bool current) {
      final String? value = read(key);
      if (value == null) return current;
      if (value == 'none') return false;
      if (value == 'otlp') return true;
      problems.add('$key=$value is not supported; Dartvel exports otlp or '
          'none, so it stays ${current ? 'otlp' : 'none'}.');
      return current;
    }

    DVOtelSampler chosen = sampler;
    final String? samplerValue = read('OTEL_TRACES_SAMPLER');
    if (samplerValue != null) {
      final DVOtelSampler? known = DVOtelSampler.values
          .where((DVOtelSampler s) => s.spelling == samplerValue)
          .firstOrNull;
      if (known == null) {
        problems.add('OTEL_TRACES_SAMPLER=$samplerValue is not a sampler '
            'Dartvel knows; ${chosen.spelling} is used.');
      } else {
        chosen = known;
      }
    }
    double share = ratio;
    final String? ratioValue = read('OTEL_TRACES_SAMPLER_ARG');
    if (ratioValue != null) {
      final double? parsed = double.tryParse(ratioValue);
      if (parsed == null || parsed < 0 || parsed > 1) {
        problems.add('OTEL_TRACES_SAMPLER_ARG=$ratioValue is not a ratio '
            'between 0 and 1; $share is used.');
      } else {
        share = parsed;
      }
    }

    int number(String key, int current, {int minimum = 1}) {
      final String? value = read(key);
      if (value == null) return current;
      final int? parsed = int.tryParse(value);
      if (parsed == null || parsed < minimum) {
        problems.add('$key=$value is not a whole number of at least $minimum; '
            '$current is used.');
        return current;
      }
      return parsed;
    }

    if (read('OTEL_SDK_DISABLED')?.toLowerCase() == 'true') on = false;

    return DVOpenTelemetryConfig(
      enabled: on,
      endpoint: base,
      tracesEndpoint: traceUrl,
      metricsEndpoint: metricUrl,
      logsEndpoint: logUrl,
      protocol: wire,
      headers: sentHeaders,
      secretHeaders: secretHeaders,
      serviceName: name,
      serviceVersion: serviceVersion,
      resourceAttributes: resource,
      traces: signal('OTEL_TRACES_EXPORTER', traces),
      metrics: signal('OTEL_METRICS_EXPORTER', metrics),
      logs: signal('OTEL_LOGS_EXPORTER', logs),
      sampler: chosen,
      ratio: share,
      maxQueueSize: number('OTEL_BSP_MAX_QUEUE_SIZE', maxQueueSize),
      maxExportBatchSize:
          number('OTEL_BSP_MAX_EXPORT_BATCH_SIZE', maxExportBatchSize),
      scheduleDelay: Duration(
          milliseconds: number(
              'OTEL_BSP_SCHEDULE_DELAY', scheduleDelay.inMilliseconds)),
      exportTimeout: Duration(
          milliseconds: number(
              'OTEL_EXPORTER_OTLP_TIMEOUT', exportTimeout.inMilliseconds)),
      metricInterval: Duration(
          milliseconds: number('OTEL_METRIC_EXPORT_INTERVAL',
              metricInterval.inMilliseconds,
              minimum: 100)),
      logLevel: logLevel,
    );
  }

  /// The section as [parse] reads it: what the build embeds in the generated
  /// runtime, and what a `DartvelConfig` class serialises to. Literal
  /// [headers] are never part of it.
  Map<String, Object?> toDeclaration() => <String, Object?>{
        'enabled': enabled,
        if (endpoint != null) 'endpoint': endpoint,
        if (tracesEndpoint != null) 'tracesEndpoint': tracesEndpoint,
        if (metricsEndpoint != null) 'metricsEndpoint': metricsEndpoint,
        if (logsEndpoint != null) 'logsEndpoint': logsEndpoint,
        'protocol': protocol.spelling,
        if (secretHeaders.isNotEmpty) 'secretHeaders': secretHeaders,
        if (serviceName != null) 'serviceName': serviceName,
        if (serviceVersion != null) 'serviceVersion': serviceVersion,
        if (resourceAttributes.isNotEmpty) 'resource': resourceAttributes,
        'traces': traces,
        'metrics': metrics,
        'logs': logs,
        'sampler': sampler.spelling,
        'ratio': ratio,
        'queue': maxQueueSize,
        'batch': maxExportBatchSize,
        'scheduleDelayMs': scheduleDelay.inMilliseconds,
        'timeoutMs': exportTimeout.inMilliseconds,
        'metricIntervalMs': metricInterval.inMilliseconds,
        'logLevel': logLevel.name,
      };

  /// The same configuration with [serviceName] and [serviceVersion] filled
  /// in where nothing set them: the build passes the package's own.
  DVOpenTelemetryConfig withServiceDefaults({String? name, String? version}) =>
      DVOpenTelemetryConfig.parse(<String, Object?>{
        ...toDeclaration(),
        if (serviceName == null && name != null) 'serviceName': name,
        if (serviceVersion == null && version != null) 'serviceVersion': version,
      })._withHeaders(headers);

  DVOpenTelemetryConfig _withHeaders(Map<String, String> literal) =>
      literal.isEmpty
          ? this
          : DVOpenTelemetryConfig(
              enabled: enabled,
              endpoint: endpoint,
              tracesEndpoint: tracesEndpoint,
              metricsEndpoint: metricsEndpoint,
              logsEndpoint: logsEndpoint,
              protocol: protocol,
              headers: literal,
              secretHeaders: secretHeaders,
              serviceName: serviceName,
              serviceVersion: serviceVersion,
              resourceAttributes: resourceAttributes,
              traces: traces,
              metrics: metrics,
              logs: logs,
              sampler: sampler,
              ratio: ratio,
              maxQueueSize: maxQueueSize,
              maxExportBatchSize: maxExportBatchSize,
              scheduleDelay: scheduleDelay,
              exportTimeout: exportTimeout,
              metricInterval: metricInterval,
              logLevel: logLevel,
            );

  // --- strict pubspec readers ----------------------------------------------

  static bool _bool(Object? value, String key, bool fallback) {
    if (value == null) return fallback;
    if (value is! bool) {
      throw ArgumentError.value(value, '$_section.$key', 'must be true or false');
    }
    return value;
  }

  static String? _string(Object? value, String key) {
    if (value == null) return null;
    if (value is! String || value.trim().isEmpty) {
      throw ArgumentError.value(value, '$_section.$key', 'must be a non-empty string');
    }
    return value.trim();
  }

  static String? _url(Object? value, String key) {
    final String? text = _string(value, key);
    if (text == null) return null;
    final Uri? parsed = Uri.tryParse(text);
    if (parsed == null ||
        !(parsed.isScheme('http') || parsed.isScheme('https')) ||
        parsed.host.isEmpty) {
      throw ArgumentError.value(value, '$_section.$key',
          'must be an http:// or https:// URL, such as http://localhost:4318');
    }
    return text;
  }

  static DVOtlpProtocol _protocol(Object? value) {
    if (value == null) return DVOtlpProtocol.httpProtobuf;
    final DVOtlpProtocol? known = DVOtlpProtocol.values
        .where((DVOtlpProtocol p) => p.spelling == value)
        .firstOrNull;
    if (known == null) {
      throw ArgumentError.value(
          value,
          '$_section.protocol',
          'must be http/protobuf or http/json; Dartvel exports OTLP over HTTP '
              '(the collector\'s port 4318), not gRPC');
    }
    return known;
  }

  static Map<String, String> _stringMap(Object? value, String key) {
    if (value == null) return const <String, String>{};
    if (value is! Map) {
      throw ArgumentError.value(value, '$_section.$key', 'must be a map of names to strings');
    }
    final Map<String, String> out = <String, String>{};
    value.forEach((Object? name, Object? entry) {
      if (entry is! String && entry is! num && entry is! bool) {
        throw ArgumentError.value(entry, '$_section.$key.$name', 'must be a string');
      }
      out['$name'] = '$entry';
    });
    return Map<String, String>.unmodifiable(out);
  }

  static double _ratio(Object? value) {
    if (value == null) return 1;
    if (value is! num || value < 0 || value > 1) {
      throw ArgumentError.value(value, '$_section.ratio', 'must be a number from 0 to 1');
    }
    return value.toDouble();
  }

  static int _int(Object? value, String key, int fallback, {required int minimum}) {
    if (value == null) return fallback;
    if (value is! int || value < minimum) {
      throw ArgumentError.value(
          value, '$_section.$key', 'must be a whole number, $minimum or more');
    }
    return value;
  }

  static T _choice<T>(Object? value, String key, List<T> values,
      String Function(T) spelling, T fallback) {
    if (value == null) return fallback;
    final T? known = values.where((T v) => spelling(v) == value).firstOrNull;
    if (known == null) {
      throw ArgumentError.value(
          value, key, 'must be one of ${values.map(spelling).join(', ')}');
    }
    return known;
  }

  /// `k=v,k2=v2`, percent-decoded, as the OpenTelemetry environment
  /// specification writes headers and resource attributes.
  static Map<String, String>? _keyValues(
      String text, String key, List<String> problems) {
    final Map<String, String> out = <String, String>{};
    for (final String pair in text.split(',')) {
      if (pair.trim().isEmpty) continue;
      final int equals = pair.indexOf('=');
      if (equals <= 0) {
        problems.add('$key has an entry without a name=value form; the whole '
            'variable is ignored.');
        return null;
      }
      try {
        out[Uri.decodeComponent(pair.substring(0, equals).trim())] =
            Uri.decodeComponent(pair.substring(equals + 1).trim());
      } on Object {
        problems.add('$key has an entry that is not percent-encoded '
            'correctly; the whole variable is ignored.');
        return null;
      }
    }
    return out;
  }
}
