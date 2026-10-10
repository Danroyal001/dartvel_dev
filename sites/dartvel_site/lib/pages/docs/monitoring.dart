import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

// Monitoring, tracing, crash reports, alerts and product analytics: what a
// running Dartvel app tells you about itself. Every line here is checked
// against docs/spec-status.json, whose "absent" notes are the source for each
// status box.
@DVPage(
  title: 'Dartvel monitoring: metrics, traces, crashes and alerts',
  description: 'Every generated backend serves Prometheus metrics and a health '
      'check, and every app records its own crashes. Traces, alerts '
      'and error budgets build on the same signals.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsMonitoringPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsmonitoring,
      lead: <String>[
        'Every generated backend serves metrics and a health check, and every '
            'app records its own crashes, with nothing to install.',
        'Alerts, incidents and consent-aware analytics build on the same '
            'signals.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'metrics',
          title: 'Read metrics and health from any backend',
          children: <Widget>[
            DocsShell(<String>[
              'curl https://your-host/metrics',
              'curl https://your-host/health',
              'dartvel metrics',
            ]),
            Bullets(<String>[
              'GET /metrics serves Prometheus text, so any Prometheus-compatible '
                  'scraper can read it.',
              'GET /health runs real checks with a deadline and answers with '
                  'each result.',
              '`dartvel metrics` fetches the running server\'s /metrics and says '
                  'plainly when no server answers.',
            ]),
            DocsCode('monitoring-server-metrics'),
            DocsCode('monitoring-server-health'),
          ],
        ),
        DocsSection(
          id: 'logging',
          title: 'One log stream, on the device and on the server',
          children: <Widget>[
            Bullets(<String>[
              'DV.log writes one record: a message, a tag and the fields as '
                  'data. It takes the same arguments in the app and on the '
                  'server, and there is a method per level, like DV.log.warn.',
              'The framework logs through it too, so your lines and Dartvel\'s '
                  'arrive in one stream.',
              'Each record also goes to the platform\'s own log: logcat on '
                  'Android, the unified log on iOS and macOS, journald or '
                  'stderr on Linux, the console in a browser, and JSON lines '
                  'on stdout from a server.',
              'Sensitive data model fields, tokens, passwords in URLs and '
                  'secrets your app has read are redacted before any of them '
                  'sees the record.',
              'A code is what an alert rule matches on, so it survives a '
                  'rewording of the message.',
            ]),
            DocsCode('monitoring-log'),
            DocsCode('monitoring-server-log'),
          ],
        ),
        DocsSection(
          id: 'device-logs',
          title: 'Keep logs on the device and send them when asked',
          children: <Widget>[
            Bullets(<String>[
              'On a phone or desktop, records also go to a log file that never '
                  'grows past 2 MB, by default, and drops files older than 7 '
                  'days. Set the size and age under dartvel.logging.file, or '
                  'turn it off with file: false.',
              'DV.log.export returns what was kept, and DV.log.share opens '
                  'the share sheet with it. DV.log.clear deletes it.',
              'Warnings and errors also become crash report breadcrumbs, so a '
                  'crash report shows the lines that came before it.',
              'To collect device logs on your own backend, set '
                  'dartvel.logging.ship.enabled to true. Devices then send '
                  'warnings and errors with a random install id, the release '
                  'and the platform, and nothing that names a person.',
              'The backend writes those records into its own log stream. On a '
                  'deployment Dartvel Cloud hosts, it can also pass them on to '
                  'the hosting log service.',
            ]),
            DocsCode('monitoring-log-export'),
          ],
        ),
        DocsSection(
          id: 'tracing',
          title: 'Follow one request across services',
          children: <Widget>[
            Bullets(<String>[
              'Each request joins the W3C traceparent it arrives with, or '
                  'starts one, and sends it back on the response.',
              'Sampling is decided from the trace id, so every service in a '
                  'trace makes the same choice without talking to the others.',
              'Recent spans are kept in memory and served at /_dartvel/traces '
                  'when diagnostics endpoints are on.',
            ]),
            DocsCode('monitoring-trace'),
            DocsCode('monitoring-server-trace'),
            DocsStatus('Distributed Tracing', missing: <String>[
              'No OTLP exporter, so spans do not reach a collector yet.',
              'Only the request itself gets a span. Database queries, outbound '
                  'HTTP, jobs and AI calls do not.',
              'A job is not linked back to the request that queued it.',
            ]),
          ],
        ),
        DocsSection(
          id: 'crashes',
          title: 'Crash reports are on from the first build',
          children: <Widget>[
            Bullets(<String>[
              'The generated client installs crash reporting at startup. A '
                  'crash is written as it happens and sent on the next launch, '
                  'once.',
              'DV.Crashes.record reports an error you caught. On the web, '
                  'uncaught errors and rejected promises are recorded too.',
              'With sink: dartvel under dartvel.crashes, your own backend '
                  'receives reports. Server processes record a 500, a failing '
                  'schedule and a dead-lettered job.',
            ]),
            DocsStatus('Crash Reporting and Release Health', missing: <String>[
              'No native crash handlers for Android, iOS or Windows, so a crash '
                  'below Dart is not caught.',
              'Nothing reads stored reports back yet: no grouping, no Studio '
                  'view and no Sentry or Crashlytics sink.',
              'No symbol upload or source maps, so stack traces are not '
                  'symbolicated.',
            ]),
          ],
        ),
        DocsSection(
          id: 'alerts',
          title: 'Alert on error budgets and open incidents',
          children: <Widget>[
            Bullets(<String>[
              'DVServiceLevel sets a success-rate objective and reports how '
                  'fast the error budget is burning.',
              'DVAlerting fires a rule after it has held for a set time and '
                  'delivers through DV.Notifications or PagerDuty, once per '
                  'episode.',
              'An alert opens an incident with a timeline, and a status '
                  'snapshot shows each component\'s health without internal '
                  'detail.',
            ]),
            DocsCode('monitoring-slo'),
            DocsStatus('Alerting, SLOs and Status Pages', missing: <String>[
              'No hosted status page yet, and no incidents view in Studio.',
              'Rule state and incident history live in memory and are lost on '
                  'restart.',
              'PagerDuty is the only pager, and there is no latency objective.',
            ]),
          ],
        ),
        DocsSection(
          id: 'analytics',
          title: 'Product analytics that respect consent',
          children: <Widget>[
            Bullets(<String>[
              'Declare consent categories under dartvel.analytics. Events in a '
                  'denied category are dropped at the call, never sent later.',
              'Events are typed classes. One that names a sensitive model field '
                  'is refused.',
              'The generated app shows a consent banner and a settings page, '
                  'and asks again when your policy version changes.',
            ]),
            DocsStatus('Product Analytics and Consent', missing: <String>[
              'On the web, consent is held in memory, so the banner asks again '
                  'on each visit.',
              'Events from the app stay on the device. No backend endpoint '
                  'receives them yet.',
              'No PostHog or Mixpanel adapter, and the banner is English only.',
            ]),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Monitoring and Observability', missing: <String>[
              'Worker and cron processes have no sink yet, so what they log '
                  'stays in a buffer in the process.',
              'The Rust server core still prints its own messages as plain '
                  'text, outside the JSON stream.',
              'There is no logs view in Studio, and `dartvel logs` does not '
                  'read a device\'s log file.',
            ]),
          ],
        ),
      ],
    );
