// aw_start spawned a thread and returned a positive server id before the bind
// was attempted. A bind that failed panicked inside that detached thread,
// while Dart already held a ServerHandle that looked healthy — so a server
// that never started reported success, and the first sign of trouble was a
// connection refused somewhere else entirely.
//
// That is what made test/stream_test.dart flaky. It derives its port from the
// wall clock (`8300 + microsecondsSinceEpoch % 400`), so two tests running a
// multiple of 400us apart pick the same one, the second bind fails, and the
// failure is invisible until the request is refused.
import 'dart:io';

import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:test/test.dart';

void main() {
  Router emptyRouter() => Router()..get('/', (Request req) async => Response.text('ok'));

  test('a port already in use fails loudly rather than returning a handle',
      () async {
    // Held by something that is definitely listening, so the bind cannot win.
    final blocker = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => blocker.close());

    // Naming the port rather than accepting any throw. The loose form passed
    // against a stale library, where the failure was a missing FFI symbol and
    // had nothing to do with binding — a green test asserting the opposite of
    // what it claims.
    await expectLater(
      serve(emptyRouter().call, host: '127.0.0.1', port: blocker.port),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          allOf(contains('bind'), contains('${blocker.port}')),
        ),
      ),
      reason: 'a bind that cannot succeed must not produce a ServerHandle, '
          'and must say that binding is what failed',
    );
  });

  test('port 0 reports the port the OS actually assigned', () async {
    // The fix for the flakiness rather than a workaround for it: a test that
    // never names a port cannot collide with one. It only works if the handle
    // carries the real port back, since 0 is not an address anyone can call.
    final server = await serve(emptyRouter().call, host: '127.0.0.1', port: 0);
    addTearDown(() => server.stop());

    expect(server.port, isNot(0),
        reason: 'the handle must carry the assigned port, not the request');

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final response =
        await (await client.getUrl(Uri.parse('http://127.0.0.1:${server.port}/')))
            .close();
    expect(response.statusCode, 200);
  });

  test('two servers in one process each serve their own routes', () async {
    // The Dart request handler was a single global that each aw_start
    // overwrote, so the last server to start answered for all of them. The
    // symptom is a plausible 404 rather than an error: the request is served,
    // by the wrong router, and nothing says so.
    //
    // dart test runs suites concurrently in one process and the native library
    // is shared across them, so this is not a hypothetical arrangement — it is
    // what this package's own test run does.
    final first = await serve(
      (Router()..get('/first', (Request req) async => Response.text('first'))).call,
      host: '127.0.0.1',
      port: 0,
    );
    addTearDown(() => first.stop());

    final second = await serve(
      (Router()..get('/second', (Request req) async => Response.text('second'))).call,
      host: '127.0.0.1',
      port: 0,
    );
    addTearDown(() => second.stop());

    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    Future<String> get(int port, String path) async {
      final response =
          await (await client.getUrl(Uri.parse('http://127.0.0.1:$port$path')))
              .close();
      return response.transform(const SystemEncoding().decoder).join();
    }

    // The second server started last, so under the old global handler this one
    // passed and the first server's did not.
    expect(await get(second.port, '/second'), 'second');
    expect(await get(first.port, '/first'), 'first',
        reason: 'the first server must still answer its own routes after a '
            'second one starts');
  });
}
