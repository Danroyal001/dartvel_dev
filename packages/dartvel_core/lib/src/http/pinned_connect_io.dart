/// A request that connects to an address it was given, not to whatever its
/// host resolves to now.
///
/// An address check that resolves a host and a connection that resolves it
/// again are two lookups, and a name with a short TTL can answer them
/// differently: a public address to the check, 127.0.0.1 to the connection.
/// That is DNS rebinding, and the only way to close it is for the connection
/// to use the address the check approved. The host name still does everything
/// else it did: TLS sends it as SNI and verifies the certificate against it,
/// and the Host header names it, so the far end sees the same request.
library dartvel_core.http.pinned_connect_io;

import 'dart:async';
import 'dart:io';

import 'transport.dart';

/// Sends [request] over a connection to [DVHttpRequest.connectAddress].
///
/// HTTP/1.1 through `dart:io`, with no proxy and no redirects followed: a
/// proxy would do its own resolution, and a redirect would name a host
/// nothing has checked. A 3xx comes back to the caller, which decides whether
/// the new location may be reached.
///
/// [context] is for a test that trusts its own certificate; the default
/// trusts the platform's roots.
Future<DVHttpStreamedResponse> dvPinnedStreamHttpRequest(
  DVHttpRequest request, {
  SecurityContext? context,
}) async {
  final String? pinned = request.connectAddress;
  if (pinned == null) {
    throw ArgumentError('dvPinnedStreamHttpRequest needs a connectAddress.');
  }
  final InternetAddress? address = InternetAddress.tryParse(pinned);
  if (address == null) {
    throw ArgumentError.value(
        pinned, 'connectAddress', 'is not an IP address');
  }
  final Uri url = request.url;
  final HttpClient client = HttpClient(context: context)
    ..findProxy = ((Uri _) => 'DIRECT')
    ..connectionFactory = (Uri target, String? proxyHost, int? proxyPort) async {
      if (target.host != url.host || target.port != url.port) {
        // Only the request's own origin is pinned. Nothing else should ask,
        // since redirects are not followed, and a connection to another host
        // at this address is exactly what pinning must not allow.
        throw StateError('A request pinned for ${url.host} was asked to '
            'connect to ${target.host}.');
      }
      final ConnectionTask<Socket> task =
          await Socket.startConnect(address, target.port);
      if (target.scheme != 'https') return task;
      return ConnectionTask.fromSocket(
        task.socket.then((Socket socket) async {
          try {
            // host: is the name, so SNI carries it and the certificate is
            // verified against it rather than against the address.
            return await SecureSocket.secure(socket,
                host: target.host, context: context);
          } catch (_) {
            socket.destroy();
            rethrow;
          }
        }),
        task.cancel,
      );
    };

  try {
    final HttpClientRequest outgoing =
        await client.openUrl(request.method, url);
    outgoing
      ..followRedirects = false
      ..persistentConnection = false;
    request.headers.forEach(outgoing.headers.set);
    outgoing.contentLength = request.body.length;
    outgoing.add(request.body);
    final HttpClientResponse response = await outgoing.close();
    final Map<String, String> headers = <String, String>{};
    response.headers.forEach((String name, List<String> values) {
      headers[name] = values.join(', ');
    });
    final StreamController<List<int>> body = StreamController<List<int>>();
    late StreamSubscription<List<int>> subscription;
    subscription = response.listen(
      body.add,
      onError: body.addError,
      onDone: () {
        client.close();
        unawaited(body.close());
      },
      cancelOnError: false,
    );
    body.onCancel = () async {
      await subscription.cancel();
      client.close(force: true);
    };
    return DVHttpStreamedResponse(
      statusCode: response.statusCode,
      headers: headers,
      body: body.stream,
      protocol: DVHttpProtocol.http11,
    );
  } catch (_) {
    client.close(force: true);
    rethrow;
  }
}
