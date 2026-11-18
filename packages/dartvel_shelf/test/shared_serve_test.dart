// Several isolates serving one port, as `HttpServer.bind(shared: true)` lets
// dart:io do.
//
// One isolate runs every handler, so on a machine with cores to spare a
// server is bounded by that one thread however fast the native side parses.
// `serve(shared: true)` in each of N isolates puts N threads behind one
// address, and the kernel spreads connections over them.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:test/test.dart';

/// Serves `/who` answering [name] on [port], shared, and reports the bound
/// port; stops when told to.
Future<void> _serveShared((String, int, SendPort) message) async {
  final (name, port, reply) = message;
  final server = await serve(
    (Router()..get('/who', (Request request) async => Response.text(name)))
        .call,
    host: '127.0.0.1',
    port: port,
    shared: true,
  );
  final stop = ReceivePort();
  reply.send((server.port, stop.sendPort));
  await stop.first;
  await server.stop();
  reply.send(null);
}

Future<(int, SendPort, ReceivePort)> _spawn(String name, int port) async {
  final replies = ReceivePort();
  await Isolate.spawn(_serveShared, (name, port, replies.sendPort));
  final queue = StreamIterator<Object?>(replies);
  await queue.moveNext();
  final (bound, stop) = queue.current! as (int, SendPort);
  // The stop acknowledgement arrives on the same port.
  final done = ReceivePort();
  unawaited(queue.moveNext().then((_) => done.sendPort.send(null)));
  return (bound, stop, done);
}

void main() {
  test('isolates serving one port with shared: true each take connections',
      () async {
    final (port, stopA, doneA) = await _spawn('a', 0);
    expect(port, isNot(0));
    final (portB, stopB, doneB) = await _spawn('b', port);
    expect(portB, port, reason: 'the second server must listen where the first does');

    // New connections each time, so the kernel picks a listener per request.
    final answers = <String>{};
    for (var i = 0; i < 200 && answers.length < 2; i++) {
      final client = HttpClient();
      final response = await (await client
              .getUrl(Uri.parse('http://127.0.0.1:$port/who')))
          .close();
      expect(response.statusCode, 200);
      answers.add(await response.transform(utf8.decoder).join());
      client.close(force: true);
    }
    expect(answers, {'a', 'b'},
        reason: 'both isolates must answer requests on the shared port');

    stopA.send(null);
    await doneA.first;
    // With one gone the other still answers.
    final client = HttpClient();
    final response =
        await (await client.getUrl(Uri.parse('http://127.0.0.1:$port/who')))
            .close();
    expect(await response.transform(utf8.decoder).join(), 'b');
    client.close(force: true);
    stopB.send(null);
    await doneB.first;
  });

  test('without shared, a second server on a bound port still fails to bind',
      () async {
    final first = await serve(
      (Router()..get('/', (Request r) async => Response.text('one'))).call,
      host: '127.0.0.1',
      port: 0,
      shared: true,
    );
    addTearDown(first.stop);
    await expectLater(
      serve(
        (Router()..get('/', (Request r) async => Response.text('two'))).call,
        host: '127.0.0.1',
        port: first.port,
      ),
      throwsA(isA<StateError>()
          .having((e) => e.message, 'message', contains('bind'))),
      reason: 'only servers that all ask to share a port may share it',
    );
  });
}
