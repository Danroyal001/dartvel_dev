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
import 'dart:typed_data';

import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:dartvel_shelf/web_socket.dart';
import 'package:test/test.dart';

void main() {
  test('a burst echoed through addStream is flushed a few times, in order',
      () async {
    final channelReady = Completer<NativeWebSocketChannel>();
    final server = await serve(
      webSocketHandler((channel, _) {
        channelReady.complete(channel as NativeWebSocketChannel);
        channel.sink.addStream(channel.stream);
      }),
      host: '127.0.0.1',
      port: 0,
    );
    addTearDown(server.stop);
    // A raw client writing 1,000 masked frames in one write.
    final socket = await Socket.connect('127.0.0.1', server.port);
    addTearDown(socket.destroy);
    socket.write('GET / HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\n'
        'Connection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n'
        'Sec-WebSocket-Version: 13\r\n\r\n');
    const count = 1000;
    final burst = BytesBuilder();
    for (var i = 0; i < count; i++) {
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
        return;
      }
      if (bytes.length >= count * 8 && !done.isCompleted) done.complete();
    });
    await done.future.timeout(const Duration(seconds: 20));
    final echoes = received.toBytes();
    for (var i = 0; i < count; i++) {
      final frame = echoes.sublist(i * 8, i * 8 + 8);
      expect(frame[0], 0x81);
      expect(frame[1], 6);
      expect(String.fromCharCodes(frame.sublist(2)),
          'm${i.toString().padLeft(5, '0')}');
    }
    final channel = await channelReady.future;
    // One write per frame (1,000 here) is what awaiting each frame cost.
    // How many frames each drain finds depends on how far the native reader
    // has got when the isolate wakes, which a loaded machine moves; a
    // quarter of the frames still fails on that, and does not on load.
    expect(channel.flushCount, lessThan(count ~/ 4),
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
