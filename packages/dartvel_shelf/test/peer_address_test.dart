// The connection's own address, from the native server into the Dart request.
//
// Nothing else can say who is on the other end of a socket: every header is
// something the client chose to send. Without this every per-source limit
// keyed on the first X-Forwarded-For address, which a client sets to anything,
// and every request that sent none shared one bucket.
//
// These start the real server and connect to it, because the address is only
// real on a real connection. A router-level test would pass against a library
// that never passed it.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:test/test.dart';

void main() {
  Router echo() => Router()
    ..get('/peer', (Request req) async {
      final DVPeerAddress? peer = req.peerAddress;
      return Response.json(<String, Object?>{
        'address': peer?.address.toString(),
        'port': peer?.port,
      });
    });

  Future<(Map<String, Object?>, int)> ask(
    String host,
    int port, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request =
          await client.getUrl(Uri.parse('http://$host:$port/peer'));
      headers.forEach(request.headers.set);
      final HttpClientResponse response = await request.close();
      // The client's own end of the connection, which is the server's peer.
      final int localPort = response.connectionInfo!.localPort;
      final Object? body =
          jsonDecode(await response.transform(utf8.decoder).join());
      expect(response.statusCode, 200);
      return (body! as Map<String, Object?>, localPort);
    } finally {
      client.close(force: true);
    }
  }

  test('an IPv4 connection reaches Dart as its address and port', () async {
    final ServerHandle server =
        await serve(echo().call, host: '127.0.0.1', port: 0);
    addTearDown(server.stop);

    final (Map<String, Object?> seen, int clientPort) =
        await ask('127.0.0.1', server.port);
    expect(seen['address'], '127.0.0.1');
    expect(seen['port'], clientPort,
        reason: 'the port is the client end of this connection');
  });

  test('a header cannot change the peer address', () async {
    final ServerHandle server =
        await serve(echo().call, host: '127.0.0.1', port: 0);
    addTearDown(server.stop);

    final (Map<String, Object?> seen, _) = await ask(
      '127.0.0.1',
      server.port,
      headers: <String, String>{
        'x-forwarded-for': '203.0.113.66',
        'forwarded': 'for=203.0.113.67',
        'x-real-ip': '203.0.113.68',
      },
    );
    expect(seen['address'], '127.0.0.1');
  });

  // Skipped only when the host cannot bind the address. A host the server
  // cannot even parse is a failure: every IPv6 host was once refused that way,
  // and a skip on any StateError reported it as an environment without IPv6.
  Future<ServerHandle?> serveOrSkip(String host, String why) async {
    try {
      return await serve(echo().call, host: host, port: 0);
    } on StateError catch (error) {
      if (!error.message.contains('could not bind')) rethrow;
      markTestSkipped('$why: $error');
      return null;
    }
  }

  test('an IPv6 connection reaches Dart as its IPv6 address', () async {
    final ServerHandle? server =
        await serveOrSkip('::1', 'no IPv6 loopback on this host');
    if (server == null) return;
    addTearDown(server.stop);

    final (Map<String, Object?> seen, int clientPort) =
        await ask('[::1]', server.port);
    expect(seen['address'], '::1');
    expect(seen['port'], clientPort);
  });

  test('an IPv4 client of a dual-stack socket is its IPv4 address', () async {
    // Bound to ::, an IPv4 client arrives as ::ffff:127.0.0.1. Passed through
    // as that, it compares unequal to 127.0.0.1 in every trusted-proxy list
    // and every limit.
    final ServerHandle? server =
        await serveOrSkip('::', 'no dual-stack socket on this host');
    if (server == null) return;
    addTearDown(server.stop);

    final Map<String, Object?> seen;
    try {
      (seen, _) = await ask('127.0.0.1', server.port);
    } on SocketException catch (error) {
      markTestSkipped('this host does not map IPv4 onto an IPv6 socket: '
          '$error');
      return;
    }
    expect(seen['address'], '127.0.0.1');
  });
}
