import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

// OpenTelemetry: traces, metrics and logs from any Dartvel process to any
// OTLP collector. Every claim here is checked against the code and against
// docs/spec-status.json ("Distributed Tracing"), whose absent note is the
// source of the status box.
@DVPage(
  title: 'Dartvel and OpenTelemetry: traces, metrics and logs over OTLP',
  description: 'Send a Dartvel app\'s traces, metrics and logs to Jaeger, '
      'Grafana Tempo, Honeycomb, Datadog or any OpenTelemetry collector, with '
      'one pubspec section or one environment variable.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsOpenTelemetryPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsopentelemetry,
      lead: <String>[
        'A Dartvel server sends its traces, metrics and logs to any '
            'OpenTelemetry collector over OTLP. Turning it on is one pubspec '
            'section, or one environment variable on the deployment, and no '
            'code.',
        'Every request, database query, outbound call, job, schedule and page '
            'render is recorded the way the OpenTelemetry semantic conventions '
            'name them, so Jaeger, Grafana Tempo, Honeycomb and Datadog draw '
            'them without any mapping.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'turn-on',
          title: 'Turn it on',
          children: <Widget>[
            DocsText('On the deployment, with nothing in the project:'),
            DocsShell(<String>[
              'OTEL_EXPORTER_OTLP_ENDPOINT=http://collector:4318 ./server',
            ]),
            DocsText('Or in the project, for every deployment:'),
            DocsYaml('yaml-opentelemetry'),
            Bullets(<String>[
              'Export is off until one of the two says otherwise. A project '
                  'that says nothing sends nothing anywhere.',
              'The service is named after the package and versioned by its '
                  'pubspec version unless serviceName or OTEL_SERVICE_NAME '
                  'says otherwise.',
              'Web, worker and cron processes all export. Each run of a '
                  'generated server installs it before the first request, '
                  'job or schedule, and sends what is still queued when the '
                  'process is told to stop.',
              'Header values that carry a key are never written in '
                  'pubspec.yaml: secretHeaders names a DV.Secrets entry, and '
                  'OTEL_EXPORTER_OTLP_HEADERS sets them on the deployment. A '
                  'literal headers key is refused at build time.',
              'Every setting is checked at build time, naming the key. A '
                  'mistyped OTEL_* variable is logged and ignored instead, so '
                  'it never stops a server from starting.',
            ]),
          ],
        ),
        DocsSection(
          id: 'recorded',
          title: 'What is recorded without code',
          children: <Widget>[
            DocsTable(columns: <String>[
              'Span',
              'Kind and name',
              'Attributes',
            ], rows: <List<String>>[
              <String>['Every request', 'server, GET /orders/:id', 'http.request.method, http.route, url.path, http.response.status_code, server.address, user_agent.original'],
              <String>['Database statement', 'client, SELECT orders', 'db.system.name, db.operation.name, db.collection.name, db.query.text with every literal replaced by ?'],
              <String>['Outbound DV.Http call', 'client, GET', 'http.request.method, server.address, url.full without its query string, http.response.status_code'],
              <String>['Job dispatched', 'producer, publish <queue>', 'messaging.operation.type send, messaging.destination.name'],
              <String>['Job run', 'consumer, process <queue>', 'messaging.operation.type process, messaging.message.id, the attempt'],
              <String>['Scheduled run', 'internal, cron <name>', 'dartvel.schedule.name, the occurrence'],
              <String>['Server-rendered page', 'internal, render /blog/:slug', 'http.route, inside the request span'],
              <String>['Studio', 'the request span, named /__studio/api/<action>', 'dartvel.studio.action or dartvel.studio.screen'],
            ]),
            Bullets(<String>[
              'A request span is named after the route template, never the '
                  'path: one name per order id is how a tracing backend\'s '
                  'index fills up.',
              'Spans join the W3C traceparent a request arrives with, and the '
                  'response sends one back, so a support ticket can quote it.',
              'Database, outbound, job and render spans are made only inside a '
                  'trace. A queue poll every second is not a trace anybody '
                  'wants.',
              'Every log line, yours and the framework\'s, goes to the '
                  'collector as an OpenTelemetry log record carrying the trace '
                  'and span it was written in, so a backend links the line to '
                  'the trace.',
            ]),
            DocsTable(columns: <String>[
              'Metric',
              'What it is',
            ], rows: <List<String>>[
              <String>['http.server.request.duration', 'Histogram in seconds, by method, route, status and scheme'],
              <String>['http.server.active_requests', 'Requests being served now'],
              <String>['db.client.operation.duration', 'Histogram in seconds, by database, operation and table'],
              <String>['process.memory.usage, process.uptime', 'Resident memory in bytes, seconds since start'],
              <String>['dartvel.*', 'Every metric the Prometheus endpoint serves, yours included'],
            ]),
          ],
        ),
        DocsSection(
          id: 'environment',
          title: 'The standard environment variables',
          children: <Widget>[
            DocsTable(columns: <String>[
              'Variable',
              'What it does',
            ], rows: <List<String>>[
              <String>['OTEL_EXPORTER_OTLP_ENDPOINT', 'The collector; each signal goes to <endpoint>/v1/<signal>. Setting it turns export on'],
              <String>['OTEL_EXPORTER_OTLP_TRACES_ENDPOINT (and _METRICS_, _LOGS_)', 'One signal\'s URL, used exactly as given'],
              <String>['OTEL_EXPORTER_OTLP_HEADERS', 'name=value pairs, comma-separated and percent-encoded'],
              <String>['OTEL_EXPORTER_OTLP_PROTOCOL', 'http/protobuf (default) or http/json'],
              <String>['OTEL_EXPORTER_OTLP_TIMEOUT', 'Milliseconds one export may take'],
              <String>['OTEL_SERVICE_NAME, OTEL_RESOURCE_ATTRIBUTES', 'The service name and more resource attributes'],
              <String>['OTEL_TRACES_SAMPLER, OTEL_TRACES_SAMPLER_ARG', 'always_on, always_off, traceidratio and the parentbased_ forms'],
              <String>['OTEL_TRACES_EXPORTER, OTEL_METRICS_EXPORTER, OTEL_LOGS_EXPORTER', 'none turns that signal off'],
              <String>['OTEL_BSP_MAX_QUEUE_SIZE, OTEL_BSP_MAX_EXPORT_BATCH_SIZE, OTEL_BSP_SCHEDULE_DELAY', 'The batch queue'],
              <String>['OTEL_METRIC_EXPORT_INTERVAL', 'Milliseconds between metric exports'],
              <String>['OTEL_SDK_DISABLED', 'true turns everything off, whatever else says on'],
            ]),
          ],
        ),
        DocsSection(
          id: 'backends',
          title: 'Point it at your backend',
          children: <Widget>[
            DocsShell(<String>[
              '# A collector you run, in front of Jaeger, Tempo, Prometheus or Loki',
              'OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318',
              '',
              '# Honeycomb',
              'OTEL_EXPORTER_OTLP_ENDPOINT=https://api.honeycomb.io',
              'OTEL_EXPORTER_OTLP_HEADERS=x-honeycomb-team=<your API key>',
              '',
              '# Grafana Cloud',
              'OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp-gateway-<zone>.grafana.net/otlp',
              'OTEL_EXPORTER_OTLP_HEADERS=Authorization=Basic%20<base64 instance:token>',
              '',
              '# Datadog: the Agent\'s OTLP receiver',
              'OTEL_EXPORTER_OTLP_ENDPOINT=http://datadog-agent:4318',
            ]),
            Bullets(<String>[
              'Dartvel sends OTLP over HTTP, protobuf or JSON, so the endpoint '
                  'is the collector\'s HTTP port, 4318 by default. Its gRPC port, '
                  '4317, does not take it.',
              'Jaeger takes OTLP directly on 4318 too, for traces.',
            ]),
          ],
        ),
        DocsSection(
          id: 'code',
          title: 'Control it in code',
          children: <Widget>[
            DocsCode('otel-code'),
            DocsCode('monitoring-server-trace'),
            Bullets(<String>[
              'tracer.trace hangs the span off the one the code is already '
                  'inside, makes it current while the work runs, and ends it '
                  'when the work returns or throws, recording the exception.',
              'An attribute keeps its type: a string, a number, a bool or a '
                  'list of one of those.',
              'Metrics you register on DV.ObservabilityAndLogging.metrics are '
                  'exported with the framework\'s.',
              'The same useOpenTelemetry call works in an app on a phone, a '
                  'desktop or in a browser. A browser needs the collector to '
                  'answer CORS, and any key in a header ships inside every '
                  'copy of the app, so point clients at an endpoint that takes '
                  'no secret.',
            ]),
          ],
        ),
        DocsSection(
          id: 'privacy',
          title: 'What never leaves',
          children: <Widget>[
            Bullets(<String>[
              'Span attributes and log records pass the same redaction: '
                  'secrets the process has read, bearer and basic credentials, '
                  'JWTs and passwords in URLs are struck out wherever they '
                  'appear.',
              'An attribute named after a @DVModel.sensitiveField() or a '
                  'credential, like http.request.header.authorization or '
                  'access_token, is redacted whatever its value.',
              'Database spans carry the statement with its literals replaced '
                  'by ?, and never the values bound to it.',
              'url.full leaves out the query string, where API keys travel.',
            ]),
          ],
        ),
        DocsSection(
          id: 'cost',
          title: 'What it costs a request',
          children: <Widget>[
            Bullets(<String>[
              'Off, a request pays for a few field reads. No span, id or '
                  'timer is made.',
              'On, ending a span or writing a line adds it to a bounded queue '
                  'and returns. Batches are encoded and sent in the background, '
                  'and nothing a request does waits for the collector.',
              'A full queue drops new items and counts them in '
                  'dartvel_otel_dropped_total. A collector that answers 429, '
                  '502, 503 or 504, or does not answer, is retried with growing '
                  'backoff, then the batch is dropped and counted.',
              'packages/dartvel_core/benchmark/otel_overhead.dart measures it. '
                  'Run it with `dart run benchmark/otel_overhead.dart` in that '
                  'package.',
              'Measured on 18 Nov 2026 (Dart 3.13.4, 100,000 requests per '
                  'mode, two runs on a shared server with a load average of 9 '
                  'to 16, so the differences matter more than the exact times): a '
                  'request with telemetry off took 46 to 51 µs in process. '
                  'Recording spans added about 30 µs, exporting traces about 80 '
                  'to 100 µs, traces, metrics and logs together about 110 to '
                  '125 µs, and the same sent as OTLP/JSON about 140 to 165 µs.',
            ]),
          ],
        ),
        DocsSection(
          id: 'why-built-in',
          title: 'Why Dartvel has its own exporter',
          children: <Widget>[
            Bullets(<String>[
              'The exporter is part of dartvel_core, which every Dartvel app '
                  'imports, the web included. The Dart OpenTelemetry SDKs on '
                  'pub.dev bring gRPC and protobuf runtimes with them, and the '
                  'most used one does not list web support.',
              'Dartvel already had spans, W3C context and redaction in every '
                  'process. A second span model beside them would record each '
                  'request twice.',
              'What makes services interoperate is on the wire: W3C Trace '
                  'Context and OTLP. A Flutter app instrumented with another '
                  'OpenTelemetry SDK that calls a Dartvel backend is one trace, '
                  'and both export to the same collector.',
            ]),
            DocsStatus('Distributed Tracing', missing: <String>[
              'gRPC export. OTLP over HTTP is what every collector and vendor '
                  'listed here accepts.',
              'A zero-config client export through the app\'s own backend. '
                  'Clients export with useOpenTelemetry in code.',
              'A job is not linked back to the request that queued it: it '
                  'starts its own trace.',
              'Code written against another Dart OpenTelemetry API does not '
                  'yet create Dartvel spans in the same process.',
              'Garbage collection and database pool metrics.',
            ]),
          ],
        ),
      ],
    );
