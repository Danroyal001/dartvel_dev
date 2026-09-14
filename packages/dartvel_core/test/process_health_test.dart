// The health endpoint a worker or a cron process serves when asked to.
//
// Those processes serve nothing, so a supervisor, a container orchestrator or
// a load balancer's health check had nothing to ask whether one was up. The
// quiet failures: a health port that also answers the application -- a
// worker reachable over HTTP by anybody who finds the port -- and one that
// keeps answering after the process has stopped working.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' hide Platform;
import 'package:test/test.dart';

Future<(int, String)> request(int port, String method, String path) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    final HttpClientResponse response = await request.close();
    return (response.statusCode, await response.transform(utf8.decoder).join());
  } finally {
    client.close(force: true);
  }
}

void main() {
  late DVProcessHealth health;

  setUp(() async {
    health = await DVProcessHealth.serve(
      host: '127.0.0.1',
      port: 0,
      role: DVProcessRole.worker,
    );
  });
  tearDown(() => health.close());

  test('GET /healthz answers 200, naming the role', () async {
    final (int status, String body) =
        await request(health.port, 'GET', '/healthz');
    expect(status, 200);
    expect(jsonDecode(body), <String, Object?>{
      'status': 'ok',
      'role': 'worker',
    });
  });

  test('HEAD /healthz answers 200 too', () async {
    final (int status, String _) =
        await request(health.port, 'HEAD', '/healthz');
    expect(status, 200);
  });

  test('nothing else is served', () async {
    for (final String path in <String>[
      '/',
      '/api/ping',
      '/healthz/extra',
      '/metrics',
    ]) {
      final (int status, String body) =
          await request(health.port, 'GET', path);
      expect(status, 404, reason: path);
      expect(body, isEmpty, reason: path);
    }
    final (int status, String _) =
        await request(health.port, 'POST', '/healthz');
    expect(status, 405);
  });

  test('closed, it answers nothing', () async {
    final int port = health.port;
    await health.close();
    await expectLater(
      Socket.connect('127.0.0.1', port),
      throwsA(isA<SocketException>()),
    );
  });
}
