// The router writes one access record per request only up to a rate.
//
// Past it a line per request is the cost of the request, not a record of it:
// at tens of thousands of requests a second the JSON lines, the redaction
// scans and the write to stdout took more of the isolate than the handlers
// did, and a log shipper billed per line turns that into money (Adbirt's
// disk and bill, October 2026). Past the rate the rest of that second is one
// summary line with its count. Failures are always written, one each, and the
// metrics count every request whatever the log does.
import 'package:dartvel_core/http.dart';
import 'package:dartvel_core/src/observability/observability.dart'
    show DVObservability, DVLogRecord, DVLogLevel;
import 'package:test/test.dart';

Request _get(String path) => Request(
      method: 'GET',
      url: Uri.parse('http://localhost$path'),
      headers: Headers(),
      bodyStream: const Stream<List<int>>.empty(),
    );

List<DVLogRecord> _access() => <DVLogRecord>[
      for (final DVLogRecord record in DVObservability.recentLogs)
        if (record.context.containsKey('status')) record,
    ];

void main() {
  setUp(() {
    DVObservability.metrics.reset();
    DVObservability.resetLogging();
    DVObservability.useLogging(sinks: const [], level: DVLogLevel.info);
  });
  tearDown(() {
    Router.accessLogsPerSecond = Router.defaultAccessLogsPerSecond;
    DVObservability.resetLogging();
  });

  test('past the rate, the rest of the second is summed up in one line',
      () async {
    Router.accessLogsPerSecond = 10;
    final Router router = Router()
      ..get('/ok', (Request _) async => Response.text('ok'))
      ..get('/boom', (Request _) async => Response.text('no', status: 503));

    for (var i = 0; i < 50; i++) {
      await router.call(_get('/ok'));
    }
    await router.call(_get('/boom'));

    final List<DVLogRecord> written = _access();
    expect(written.where((r) => r.context['status'] == 200), hasLength(10),
        reason: 'ten a second, then no more individual 200 lines');
    expect(written.where((r) => r.context['status'] == 503), hasLength(1),
        reason: 'a failure is written whatever the rate');
    expect(
      DVObservability.metrics
          .valueOf('http_requests_total', {'method': 'GET', 'status': '200'}),
      50,
      reason: 'the metrics still count every request',
    );

    // The summary comes when the second is over, with nothing else asked.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final DVLogRecord summary = DVObservability.recentLogs.lastWhere(
        (DVLogRecord r) => r.context.containsKey('notLogged'),
        orElse: () => throw TestFailure('no summary line was written'));
    expect(summary.context['notLogged'], 40);
    expect(summary.level, DVLogLevel.info);
  });

  test('under the rate every request is written', () async {
    final Router router = Router()
      ..get('/ok', (Request _) async => Response.text('ok'));
    for (var i = 0; i < 20; i++) {
      await router.call(_get('/ok'));
    }
    expect(_access(), hasLength(20));
    expect(Router.defaultAccessLogsPerSecond, greaterThanOrEqualTo(20));
  });

  test('a rate of zero writes no 2xx access lines, and still counts', () async {
    Router.accessLogsPerSecond = 0;
    final Router router = Router()
      ..get('/ok', (Request _) async => Response.text('ok'));
    for (var i = 0; i < 5; i++) {
      await router.call(_get('/ok'));
    }
    expect(_access().where((r) => r.context['status'] == 200), isEmpty);
    expect(
      DVObservability.metrics
          .valueOf('http_requests_total', {'method': 'GET', 'status': '200'}),
      5,
    );
  });
}
