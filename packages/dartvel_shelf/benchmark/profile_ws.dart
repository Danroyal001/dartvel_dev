import 'dart:async';
import 'dart:io';
import 'package:dartvel_shelf/dartvel_shelf.dart' as dv;
import 'package:dartvel_shelf/web_socket.dart' as native_ws;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart' as shelf_ws;

Future<void> main() async {
  dv.embedNativeServerLibrary(
    await File('lib/native/linux-x64/libdartvel_shelf.so').readAsBytes(),
  );
  var drainCount = 0;
  var wakeupCount = 0;
  final sw = Stopwatch()..start();
  const N = 500;
  var clientToSendUs = 0;
  var sendToClientUs = 0;
  var clientSendTimestamp = 0;
  var serverReceivedTimestamp = 0;

  final ws = native_ws.webSocketHandler((channel, _) {
    channel.stream.listen((msg) {
      serverReceivedTimestamp = sw.elapsedMicroseconds;
      clientToSendUs += (serverReceivedTimestamp - clientSendTimestamp);
      channel.sink.add(msg);
    });
  });
  final server = await dv.serve(
    (req) async {
      if (req.url.path == '/ws') return ws(req);
      return dv.Response.text('ok');
    },
    port: 0,
  );

  final clientWs = await WebSocket.connect('ws://127.0.0.1:${server.port}/ws');
  final messages = StreamIterator<Object?>(clientWs);
  final message = 'x' * 64;

  // Warmup
  for (var i = 0; i < 50; i++) {
    clientWs.add(message);
    await messages.moveNext();
  }

  sw.reset();
  sw.start();
  for (var i = 0; i < N; i++) {
    clientSendTimestamp = sw.elapsedMicroseconds;
    clientWs.add(message);
    if (!await messages.moveNext() || messages.current != message) {
      throw StateError('Mismatch');
    }
    final clientReceivedTimestamp = sw.elapsedMicroseconds;
    sendToClientUs += (clientReceivedTimestamp - serverReceivedTimestamp);
  }
  sw.stop();
  print('dartvel: ${N * 1000000 / sw.elapsedMicroseconds} msgs/s (${sw.elapsedMicroseconds / N} us/msg)');
  print('clientToSend: ${clientToSendUs / N} us, sendToClient: ${sendToClientUs / N} us');

  await clientWs.close();
  await messages.cancel();
  await server.stop();

  final shelfWs = shelf_ws.webSocketHandler((channel, _) {
    channel.stream.listen((msg) {
      channel.sink.add(msg);
    });
  });
  final shelfServer = await shelf_io.serve(
    (req) async {
      if (req.url.path == 'ws') return shelfWs(req);
      return shelf.Response.ok('ok');
    },
    '127.0.0.1',
    0,
  );

  final clientWs2 = await WebSocket.connect('ws://127.0.0.1:${shelfServer.port}/ws');
  final messages2 = StreamIterator<Object?>(clientWs2);
  for (var i = 0; i < 50; i++) {
    clientWs2.add(message);
    await messages2.moveNext();
  }

  final sw2 = Stopwatch()..start();
  for (var i = 0; i < N; i++) {
    clientWs2.add(message);
    if (!await messages2.moveNext() || messages2.current != message) {
      throw StateError('Mismatch');
    }
  }
  sw2.stop();
  print('shelf:   ${N * 1000000 / sw2.elapsedMicroseconds} msgs/s (${sw2.elapsedMicroseconds / N} us/msg)');

  await clientWs2.close();
  await messages2.cancel();
  await shelfServer.close(force: true);
}
