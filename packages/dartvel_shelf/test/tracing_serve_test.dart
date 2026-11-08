// A server started with dartvel.tracing sends its spans to the collector.
//
// Started on a real socket with a real collector beside it, because the
// exporter existing is not spans leaving a deployed server: serve() has to
// install it, and stopping has to flush what is still queued, or the last
// requests before a deploy are the ones that never appear.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show DVTracingConfig, dvTraced;
import 'package:dartvel_core/dv.dart' show DV;
import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:test/test.dart';

void main() {
  test('spans from served requests reach the declared OTLP collector',
      () async {
    final List<Map<String, Object?>> batches = <Map<String, Object?>>[];
    final HttpServer collector =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => collector.close(force: true));
    collector.listen((HttpRequest request) async {
      batches.add(jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, Object?>);
      request.response.statusCode = 200;
      await request.response.close();
    });

    final Router app = Router()
      ..get('/orders', (Request req) async => Response.text('ok'));
    final ServerHandle server = await serve(
      (Request req) =>
          dvTraced(DV.ObservabilityAndLogging.tracer, req, app.call),
      port: 0,
      tracing: DVTracingConfig.parse(<String, Object?>{
        'exporter': 'otlp',
        'endpoint': 'http://127.0.0.1:${collector.port}',
      }),
      serviceName: 'orders-api',
    );

    final HttpClient client = HttpClient();
    final HttpClientResponse response = await (await client
            .getUrl(Uri.parse('http://127.0.0.1:${server.port}/orders')))
        .close();
    await response.drain<void>();
    client.close(force: true);
    expect(response.headers.value('traceparent'), isNotNull);

    // Stopping flushes: the interval has not passed, so without it the span
    // would still be queued when the process ended.
    await server.stop();

    final String text = jsonEncode(batches);
    expect(batches, isNotEmpty);
    expect(text, contains('GET /orders'));
    expect(text, contains('orders-api'));
  });
}
