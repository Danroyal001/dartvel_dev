// Two isolates starting a server at the same moment must each get their own.
//
// Registering a handler and starting a server are two FFI calls. The native
// side kept the handler in a process-global slot between them, so two
// isolates -- which is what `dart test` is, one library load and a suite per
// isolate -- interleave as register A, register B, start A, start B, and
// server A then answers its own port out of B's router.
//
// That is the failure worth a test, because it is the quiet one: A does not
// throw, it returns a perfectly ordinary 404 for a route it was built with,
// or B's body for a path they share. The loud version comes later, when B
// stops and frees a callback A is still holding and the next request into A
// aborts the process on "Callback invoked after it has been deleted".
//
// The window is the microseconds between the two calls, so this races them
// repeatedly rather than once. A single pass proves nothing here: the
// unpatched library passes an ordinary suite run most times.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:test/test.dart';

/// Serves one route that answers with [marker], asks its own server who it
/// is, and returns the answer.
///
/// Self-querying on purpose: the assertion is "this isolate's server answers
/// out of this isolate's router", which is exactly what the shared slot broke,
/// and it keeps each server's lifetime inside the isolate that made it.
Future<String> _whoAmI(String marker) async {
  final router = Router()
    ..get('/who', (Request request) async => Response.text(marker));

  final ServerHandle server = await serve(
    router.call,
    host: '127.0.0.1',
    port: 0,
  );

  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client
        .getUrl(Uri.parse('http://127.0.0.1:${server.port}/who'));
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    return response.statusCode == 200 ? body : 'status ${response.statusCode}';
  } finally {
    client.close(force: true);
    await server.stop();
  }
}

void main() {
  test('two isolates serving at once each answer out of their own router',
      () async {
    // Enough passes to hit a window measured in microseconds. Each pass is
    // two isolates and two short-lived servers, so this stays a few seconds.
    const int passes = 25;

    for (int pass = 1; pass <= passes; pass += 1) {
      final String a = 'A$pass';
      final String b = 'B$pass';

      // Started together and awaited together, so the two serve() calls
      // overlap rather than queue.
      final List<String> answers = await Future.wait<String>(<Future<String>>[
        Isolate.run(() => _whoAmI(a)),
        Isolate.run(() => _whoAmI(b)),
      ]);

      expect(
        answers,
        <String>[a, b],
        reason: 'pass $pass: each isolate must answer with its own marker. '
            'Getting the other isolate\'s marker, or a 404 for a route the '
            'isolate registered itself, means the two servers shared one '
            'handler slot.',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
