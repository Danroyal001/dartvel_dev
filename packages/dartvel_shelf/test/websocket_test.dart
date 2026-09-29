import 'dart:async';
import 'dart:io';

import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:dartvel_shelf/web_socket.dart';
import 'package:test/test.dart';
import 'package:dartvel_core/src/websocket/ws.dart';

void main() {
  test('peer closure releases an unlistened channel', () async {
    final done = Completer<void>();
    final server = await serve(
      webSocketHandler((channel, _) {
        channel.sink.done.then((_) => done.complete());
      }),
      port: 0,
    );
    addTearDown(server.stop);
    final ws = await WebSocket.connect('ws://127.0.0.1:${server.port}/');
    final ended = ws.drain<void>();
    await ws.close();
    await ended;
    await done.future.timeout(const Duration(seconds: 1));
  });

  test('server heartbeat works without an application data listener', () async {
    final server = await serve(
      webSocketHandler(
        (channel, _) {},
        pingInterval: const Duration(milliseconds: 30),
      ),
      port: 0,
    );
    addTearDown(server.stop);
    final ws = await WebSocket.connect('ws://127.0.0.1:${server.port}/');
    final subscription = ws.listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(ws.readyState, WebSocket.open);
    await ws.close();
    await subscription.cancel();
  });

  test('a one-byte data limit still allows a normal close frame', () async {
    final closed = Completer<void>();
    final server = await serve(
      webSocketHandler((channel, _) {
        channel.sink
            .close(1000, 'done')
            .then((_) => closed.complete(), onError: closed.completeError);
      }, maxMessageSize: 1),
      port: 0,
    );
    addTearDown(server.stop);
    final ws = await WebSocket.connect('ws://127.0.0.1:${server.port}/');
    await closed.future;
    await ws.drain<void>();
    expect(ws.closeCode, 1000);
  });

  test('structured core handlers use the native transport', () async {
    final server = await serve(wsHandler(WsHandlers.echo), port: 0);
    addTearDown(server.stop);
    final ws = await WebSocket.connect('ws://127.0.0.1:${server.port}/');
    ws.add('{"type":"hello","data":42,"id":"one"}');
    expect(await ws.first, '{"type":"echo","data":42,"id":"one"}');
    await ws.close();
  });

  test('a stalled peer backpressures addStream and stop releases it', () async {
    var produced = 0;
    final completed = Completer<void>();
    Stream<List<int>> data() async* {
      final chunk = List<int>.filled(256 * 1024, 7);
      for (var i = 0; i < 1000; i++) {
        produced++;
        yield chunk;
      }
    }

    final server = await serve(
      webSocketHandler((channel, _) {
        channel.stream.listen((_) {});
        channel.sink
            .addStream(data())
            .catchError((Object _) {})
            .whenComplete(completed.complete);
      }),
      port: 0,
    );
    final ws = await WebSocket.connect('ws://127.0.0.1:${server.port}/');
    final subscription = ws.listen((_) {})..pause();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(
      produced,
      lessThan(1000),
      reason: 'a stalled client must not buffer the entire producer',
    );
    await server.stop();
    await completed.future.timeout(const Duration(seconds: 2));
    await subscription.cancel();
    await ws.close();
  });

  test(
    'real WebSocket echoes text and binary and negotiates protocol',
    () async {
      final server = await serve(
        webSocketHandler((channel, protocol) {
          expect(protocol, 'chat');
          channel.sink
              .addStream(channel.stream)
              .then((_) => channel.sink.close());
        }, protocols: ['chat']),
        port: 0,
      );
      addTearDown(server.stop);
      final ws = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/',
        protocols: ['chat'],
      );
      final messages = StreamIterator<Object?>(ws);
      expect(ws.protocol, 'chat');
      ws.add('hello');
      expect(await messages.moveNext(), isTrue);
      expect(messages.current, 'hello');
      ws.add([0, 255, 42]);
      expect(await messages.moveNext(), isTrue);
      expect(messages.current, [0, 255, 42]);
      // Ping/pong must remain live without application messages.
      ws.pingInterval = const Duration(milliseconds: 30);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(ws.readyState, WebSocket.open);
      await ws.close(1000, 'done');
      await messages.cancel();
    },
  );

  test('origin refusal and message size limit reach real clients', () async {
    final server = await serve(
      webSocketHandler(
        (channel, _) {
          channel.stream.listen((_) {}, onError: (Object _) {});
        },
        allowedOrigins: ['https://allowed.test'],
        maxMessageSize: 32,
      ),
      port: 0,
    );
    addTearDown(server.stop);
    final uri = 'ws://127.0.0.1:${server.port}/';
    await expectLater(
      WebSocket.connect(uri, headers: {'origin': 'https://evil.test'}),
      throwsA(isA<WebSocketException>()),
    );
    final ws = await WebSocket.connect(uri);
    final ended = ws.drain<void>();
    ws.add('x' * 33);
    await ended.timeout(const Duration(seconds: 3));
    expect(ws.closeCode, 1009);
  });

  test('a burst of 10,000 sink.add calls to a slow client does not throw and arrives in order', () async {
    const total = 10000;
    final server = await serve(
      webSocketHandler((channel, _) {
        for (var i = 0; i < total; i++) {
          channel.sink.add('msg-$i');
        }
        channel.sink.close(1000, 'done');
      }),
      port: 0,
    );
    addTearDown(server.stop);
    final ws = await WebSocket.connect('ws://127.0.0.1:${server.port}/');
    var received = 0;
    final completer = Completer<void>();
    late StreamSubscription subscription;
    subscription = ws.listen(
      (data) {
        expect(data, 'msg-$received');
        received++;
        if (received % 500 == 0) {
          subscription.pause();
          Timer(const Duration(milliseconds: 5), subscription.resume);
        }
      },
      onDone: completer.complete,
      onError: completer.completeError,
    );
    await completer.future.timeout(const Duration(seconds: 30));
    expect(received, total);
  });

  test(
    'pipelined client messages are echoed in order, text and binary',
    () async {
      const total = 5000;
      final server = await serve(
        webSocketHandler((channel, _) {
          channel.stream.listen(channel.sink.add);
        }),
        port: 0,
      );
      addTearDown(server.stop);
      final ws = await WebSocket.connect('ws://127.0.0.1:${server.port}/');
      final received = <Object?>[];
      final done = Completer<void>();
      ws.listen((data) {
        received.add(data);
        if (received.length == total) done.complete();
      });
      for (var i = 0; i < total; i++) {
        ws.add(i.isEven ? 'm$i' : <int>[i & 255, (i >> 8) & 255]);
      }
      await done.future.timeout(const Duration(seconds: 30));
      for (var i = 0; i < total; i++) {
        expect(received[i], i.isEven ? 'm$i' : [i & 255, (i >> 8) & 255]);
      }
      await ws.close();
    },
  );

  test(
    'frames added before close all arrive, then the close code and reason',
    () async {
      final server = await serve(
        webSocketHandler((channel, _) {
          for (var i = 0; i < 300; i++) {
            channel.sink.add('before-$i');
          }
          channel.sink.close(4001, 'bye');
        }),
        port: 0,
      );
      addTearDown(server.stop);
      final ws = await WebSocket.connect('ws://127.0.0.1:${server.port}/');
      final received = await ws.toList().timeout(const Duration(seconds: 10));
      expect(received, [for (var i = 0; i < 300; i++) 'before-$i']);
      expect(ws.closeCode, 4001);
      expect(ws.closeReason, 'bye');
    },
  );

  test(
    'awaited sends of large binary frames arrive whole and in order',
    () async {
      const count = 40;
      final server = await serve(
        webSocketHandler((channel, _) async {
          final native = channel as NativeWebSocketChannel;
          for (var i = 0; i < count; i++) {
            await native.send(List<int>.filled(200 * 1024, i));
          }
          await channel.sink.close(1000, 'sent');
        }),
        port: 0,
      );
      addTearDown(server.stop);
      final ws = await WebSocket.connect('ws://127.0.0.1:${server.port}/');
      final received = await ws.toList().timeout(const Duration(seconds: 20));
      expect(received, hasLength(count));
      for (var i = 0; i < count; i++) {
        final frame = received[i] as List<int>;
        expect(frame.length, 200 * 1024);
        expect(frame.first, i);
        expect(frame.last, i);
      }
      expect(ws.closeCode, 1000);
    },
  );
}
