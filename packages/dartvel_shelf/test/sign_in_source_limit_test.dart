// The sign-in velocity limit per source, over a real connection.
//
// The per-source limit is what sees a hundred failures spread across a
// hundred accounts from one client. It counted the first X-Forwarded-For
// entry, so a client wrote a different one on every request and was never
// counted twice; the limit went on refusing each attempt as though it were working.
//
// Served by the real native server, because the address that counts comes
// from the socket, and signed in through DVAuthEndpoints with a real guard.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart'
    show
        DVAuthEndpoints,
        DVClientAddress,
        DVCredentialGuard,
        DVVelocityBudget,
        DVVelocityLimiter,
        LocalAuthProvider;
import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:test/test.dart';

void main() {
  late ServerHandle server;

  setUp(() async {
    DVAuthEndpoints.install(
      credentials: DVCredentialGuard(
        provider: LocalAuthProvider(),
        velocity: DVVelocityLimiter(
          // A roomy per-account budget, so only the source can trip.
          perAccount: const DVVelocityBudget(1000, Duration(minutes: 15)),
          perSource: const DVVelocityBudget(3, Duration(minutes: 15)),
        ),
        refusalFloor: Duration.zero,
      ),
    );
    final Router router = Router()
      ..post(DVAuthEndpoints.signInPath, DVAuthEndpoints.signIn);
    server = await serve(router.call, host: '127.0.0.1', port: 0);
  });

  tearDown(() async {
    await server.stop();
    DVAuthEndpoints.uninstall();
    DVClientAddress.reset();
  });

  Future<int> signIn(int attempt, {Map<String, String> headers = const {}}) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.postUrl(
          Uri.parse('http://127.0.0.1:${server.port}${DVAuthEndpoints.signInPath}'));
      request.headers.contentType = ContentType.json;
      headers.forEach(request.headers.set);
      // A different account every time: the attack a per-account limit
      // cannot see.
      request.write(jsonEncode(<String, String>{
        'email': 'person$attempt@example.test',
        'password': 'not the password',
      }));
      final HttpClientResponse response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    } finally {
      client.close(force: true);
    }
  }

  test('a new X-Forwarded-For on every attempt does not escape the limit',
      () async {
    final List<int> statuses = <int>[
      for (int i = 0; i < 5; i++)
        await signIn(i, headers: <String, String>{
          'x-forwarded-for': '203.0.113.${i + 1}',
          'x-real-ip': '198.51.100.${i + 1}',
        }),
    ];
    // 400 is the endpoint's one refusal for bad credentials, known or not.
    expect(statuses.take(3), everyElement(400));
    expect(statuses.skip(3), everyElement(429),
        reason: 'one socket address is one source, whatever it says it is');
  });

  test('behind a trusted proxy, the client it reports is the source', () async {
    // The server's own loopback address is the proxy here. Two clients behind
    // it are two sources: counted as the proxy, they would share one.
    DVClientAddress.install(DVClientAddress.parse(const <String>['127.0.0.1']));
    for (int i = 0; i < 3; i++) {
      expect(
          await signIn(i, headers: <String, String>{
            'x-forwarded-for': '203.0.113.10',
          }),
          400);
    }
    expect(
        await signIn(3, headers: <String, String>{
          'x-forwarded-for': '203.0.113.10',
        }),
        429);
    expect(
        await signIn(4, headers: <String, String>{
          'x-forwarded-for': '203.0.113.11',
        }),
        400,
        reason: 'a different client behind the same proxy is not limited');
    // And one the client wrote to the left of itself is not believed.
    expect(
        await signIn(5, headers: <String, String>{
          'x-forwarded-for': '6.6.6.6, 203.0.113.10',
        }),
        429);
  });
}
