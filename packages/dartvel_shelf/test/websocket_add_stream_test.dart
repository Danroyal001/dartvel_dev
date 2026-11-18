// sink.addStream is how an echo or a relay is written. It used to await
// each message, which paused the incoming stream after every frame: each
// frame was drained, queued and flushed -- a system call -- on its own, so a
// burst of a thousand frames cost a thousand writes. It now takes frames as
// they come while the native queue has room and pauses only when it is full,
// so a burst goes out in a few writes. What must not change: every frame,
// in order; addStream completing once the source is done and all of it is
// queued; and an error in the source ending addStream with that error.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:dartvel_shelf/web_socket.dart';
import 'package:test/test.dart';

const int _burst = 1000;

/// A raw WebSocket peer: upgrades, writes [_burst] masked frames in one
/// write, says 'written' once they are flushed to the operating system,
/// then reads every echo and says 'in order' or what was wrong.
Future<void> _burstPeer((int, SendPort) args) async {
  final (int port, SendPort report) = args;
  final socket = await Socket.connect('127.0.0.1', port);
  socket.write('GET / HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\n'
      'Connection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n'
      'Sec-WebSocket-Version: 13\r\n\r\n');
  final burst = BytesBuilder();
  for (var i = 0; i < _burst; i++) {
    final payload = 'm${i.toString().padLeft(5, '0')}'.codeUnits; // 6 bytes
    burst.add(<int>[0x81, 0x80 | payload.length, 0, 0, 0, 0, ...payload]);
  }
  final received = BytesBuilder();
  var upgraded = false;
  final done = Completer<void>();
  socket.listen((data) {
    received.add(data);
    final bytes = received.toBytes();
    if (!upgraded) {
      final text = String.fromCharCodes(bytes);
      final end = text.indexOf('\r\n\r\n');
      if (end < 0) return;
      upgraded = true;
      received.clear();
      received.add(bytes.sublist(end + 4));
      socket.add(burst.takeBytes());
      // Flushed to the operating system: on loopback the bytes are then in
      // the server's receive buffer.
      socket.flush().then((_) => report.send('written'));
      return;
    }
    if (bytes.length >= _burst * 8 && !done.isCompleted) done.complete();
  });
  await done.future.timeout(const Duration(seconds: 20));
  final echoes = received.toBytes();
  String result = 'in order';
  for (var i = 0; i < _burst; i++) {
    final frame = echoes.sublist(i * 8, i * 8 + 8);
    final expected = 'm${i.toString().padLeft(5, '0')}';
    if (frame[0] != 0x81 || frame[1] != 6 ||
        String.fromCharCodes(frame.sublist(2)) != expected) {
      result = 'frame $i was ${frame.toList()}, expected $expected';
      break;
    }
  }
  socket.destroy();
  report.send(result);
}

void main() {
  test('a burst echoed through addStream is flushed a few times, in order',
      () async {
    final channelReady = Completer<NativeWebSocketChannel>();
    // The echo starts once the whole burst is in the server's socket: what
    // is measured is how the server batches frames that are all there, not
    // how fast a loaded machine delivers them to it.
    final burstWritten = Completer<void>();
    final server = await serve(
      webSocketHandler((channel, _) {
        channelReady.complete(channel as NativeWebSocketChannel);
        burstWritten.future.then((_) => channel.sink.addStream(channel.stream));
      }),
      host: '127.0.0.1',
      port: 0,
    );
    addTearDown(server.stop);
    // The peer runs in an isolate of its own and reads the echoes as they
    // come, as a real peer does. Run in this isolate it read them only when
    // the server's turns let it, so on a loaded machine the echoes backed up
    // in the socket and the server wrote a few at a time because it had to.
    final events = ReceivePort();
    final messages = StreamIterator<Object?>(events);
    await Isolate.spawn(_burstPeer, (server.port, events.sendPort));
    expect(await messages.moveNext(), isTrue);
    expect(messages.current, 'written');
    burstWritten.complete();
    expect(await messages.moveNext(), isTrue);
    final Object? result = messages.current;
    await messages.cancel();
    expect(result, 'in order', reason: '$result');
    final channel = await channelReady.future;
    // One write per frame (1,000 here) is what awaiting each frame cost.
    expect(channel.flushCount, lessThan(_burst ~/ 10),
        reason: 'frames that arrived together go out together');
  });

  test('addStream completes once its source is done and all of it is queued',
      () async {
    final result = Completer<Object?>();
    final server = await serve(
      webSocketHandler((channel, _) {
        Stream<String> source() async* {
          for (var i = 0; i < 300; i++) {
            yield 'n$i';
          }
        }

        channel.sink.addStream(source()).then(
            (_) => result.complete('done'),
            onError: (Object e) => result.complete(e));
      }),
      host: '127.0.0.1',
      port: 0,
    );
    addTearDown(server.stop);
    final ws = await WebSocket.connect('ws://127.0.0.1:${server.port}/');
    final messages = await ws.take(300).toList();
    expect(messages, <String>[for (var i = 0; i < 300; i++) 'n$i']);
    expect(await result.future, 'done');
    await ws.close();
  });

  test('an error in the source ends addStream with that error', () async {
    final result = Completer<Object?>();
    final server = await serve(
      webSocketHandler((channel, _) {
        Stream<String> source() async* {
          yield 'first';
          throw const FormatException('broken source');
        }

        channel.sink.addStream(source()).then(
            (_) => result.complete('done'),
            onError: (Object e) => result.complete(e));
      }),
      host: '127.0.0.1',
      port: 0,
    );
    addTearDown(server.stop);
    final ws = await WebSocket.connect('ws://127.0.0.1:${server.port}/');
    expect(await ws.first, 'first');
    expect(await result.future, isA<FormatException>());
    await ws.close();
  });
}
