// A page served with 200 is logged as 200.
//
// The router records every request it is given, and on a web-server build it
// is given each page first: it has no route for /docs, answers 404, and the
// server then renders the page and sends 200. dartvel.dev's log said
// "GET / 404" for a home page every visitor received, so the log could not be
// used to find a page that was really missing, and the 404 count in
// http_requests_total was mostly pages that worked.
import 'dart:io';

import 'package:dartvel_core/src/observability/observability.dart'
    show DVObservability, DVLogRecord;
import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _index = '<!DOCTYPE html><html><head><title>Shop</title>'
    '</head><body><div id="app"></div></body></html>';

void main() {
  late Directory site;

  setUp(() {
    site = Directory.systemTemp.createTempSync('dv_page_access_log_');
    File(p.join(site.path, 'index.html')).writeAsStringSync(_index);
    DVObservability.metrics.reset();
    DVObservability.resetLogging();
  });

  tearDown(() {
    DVObservability.resetLogging();
    site.deleteSync(recursive: true);
  });

  Future<int> get(int port, String path) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientResponse response =
          await (await client.getUrl(Uri.parse('http://127.0.0.1:$port$path')))
              .close();
      await response.drain<void>();
      return response.statusCode;
    } finally {
      client.close(force: true);
    }
  }

  List<DVLogRecord> accessRecords(String path) => <DVLogRecord>[
        for (final DVLogRecord record in DVObservability.recentLogs)
          if (record.context['path'] == path) record,
      ];

  test('a page the server renders is logged with the status it was sent',
      () async {
    final Router router = Router()
      ..get('/api/ping', (Request _) async => Response.text('pong'));
    final ServerHandle server = await serve(
      router.call,
      host: '127.0.0.1',
      port: 0,
      spaRoot: site.path,
    );
    addTearDown(server.stop);

    expect(await get(server.port, '/products/42'), 200);
    expect(await get(server.port, '/api/ping'), 200);

    final List<DVLogRecord> page = accessRecords('/products/42');
    expect(page, hasLength(1),
        reason: 'one record per request; logged: '
            '${DVObservability.recentLogs.map((DVLogRecord r) => r.context).toList()}');
    expect(page.single.context['status'], 200,
        reason: 'the page was sent with 200, whatever the router said first');
    expect(accessRecords('/api/ping').single.context['status'], 200);
    expect(
      DVObservability.render(),
      isNot(contains('status="404"')),
      reason: 'no request in this test was answered 404',
    );
  });
}
