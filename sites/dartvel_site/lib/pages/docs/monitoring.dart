import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

// Monitoring, tracing, crash reports, alerts and product analytics: what a
// running Dartvel app tells you about itself. Every line here is checked
// against docs/spec-status.json, whose "absent" notes are the source for each
// status box.
@DVPage(title: 'Dartvel monitoring: metrics, traces, crashes and alerts', showAppBar: false)
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
              'dartvel metrics fetches the running server\'s /metrics and says '
                  'plainly when no server answers.',
            ]),
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
              'There is no log sink, so what an app logs goes nowhere yet.',
              'dartvel logs and dartvel traces say so when they have nothing '
                  'to read.',
            ]),
          ],
        ),
      ],
    );
