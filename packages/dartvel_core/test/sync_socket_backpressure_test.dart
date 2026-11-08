// Backpressure on the sync carrier, both ways, against real local servers:
// a client may have only so many changes unacknowledged on the wire, holds
// a bounded queue behind them, and slows its publisher (or sheds the oldest)
// when that is full; the relay does the same per connection and closes a
// client too slow to keep up rather than buffering for it without limit.
// Unacknowledged changes are sent again after a reconnect, and the relay
// drops the repeats.
@TestOn('vm')
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

// The carrier is the framework's own, hidden from the barrel an application
// imports, so its tests reach for the framework library.
import 'package:dartvel_core/framework.dart';
import 'package:test/test.dart';

/// A bare WebSocket server that records every frame and acknowledges only
/// when told to: the far end of a slow or stalled link.
class _ManualPeer {
  final HttpServer http;
  final List<Map<String, Object?>> frames = <Map<String, Object?>>[];
  final List<WebSocket> sockets = <WebSocket>[];

  /// When set, the next connection is closed after its first change frame
  /// arrives, before any acknowledgement.
  bool dropAfterFirstChange = false;

  _ManualPeer(this.http) {
    http.listen((HttpRequest request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((Object? data) {
        final frame = jsonDecode(data! as String) as Map<String, Object?>;
        frames.add(frame);
        if (frame['op'] == 'change' && dropAfterFirstChange) {
          dropAfterFirstChange = false;
          unawaited(socket.close());
        }
      });
    });
  }

  static Future<_ManualPeer> start() async =>
      _ManualPeer(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  Uri get url => Uri.parse('ws://127.0.0.1:${http.port}/__dv/sync');

  List<Object?> get changeIds => <Object?>[
        for (final frame in frames)
          if (frame['op'] == 'change') (frame['envelope']! as Map)['model'],
      ].map((Object? model) => (model! as Map)['id']).toList();

  void ack(int upTo) =>
      sockets.last.add(jsonEncode(<String, Object?>{'op': 'ack', 'upTo': upTo}));

  Future<void> stop() async {
    for (final socket in sockets) {
      await socket.close();
    }
    await http.close(force: true);
  }
}

Map<String, Object?> _envelope(String id) => <String, Object?>{
      'type': 'Note',
      'kind': 'updated',
      'tenant': 'default',
      'model': <String, Object?>{'id': id, 'owner': 'ada'},
    };

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition never held');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 200));

void main() {
  group('the client', () {
    late _ManualPeer peer;

    setUp(() async => peer = await _ManualPeer.start());
    tearDown(() => peer.stop());

    test('puts no more than its window on the wire and makes the publisher '
        'wait when its queue is full', () async {
      final client =
          DVSyncSocket(peer.url, maxInFlight: 3, maxQueued: 2);
      addTearDown(client.close);
      await client.connect();

      for (var n = 1; n <= 5; n++) {
        await client.send(_envelope('c$n')).timeout(const Duration(seconds: 2));
      }
      var sixthDone = false;
      final sixth = client.send(_envelope('c6')).then((_) => sixthDone = true);

      await _settle();
      expect(peer.changeIds, <String>['c1', 'c2', 'c3']);
      expect(sixthDone, isFalse,
          reason: 'three on the wire and two queued is full');

      peer.ack(1);
      await sixth.timeout(const Duration(seconds: 5));
      await _until(() => peer.changeIds.length == 4);
      expect(peer.changeIds, <String>['c1', 'c2', 'c3', 'c4']);

      peer.ack(6);
      await _until(() => peer.changeIds.length == 6);
      expect(peer.changeIds, <String>['c1', 'c2', 'c3', 'c4', 'c5', 'c6']);
    });

    test('with dropOldest, sheds the oldest queued change instead of '
        'waiting, and counts it', () async {
      final client = DVSyncSocket(
        peer.url,
        maxInFlight: 1,
        maxQueued: 2,
        overflow: DVSyncOverflow.dropOldest,
      );
      addTearDown(client.close);
      await client.connect();

      for (var n = 1; n <= 5; n++) {
        await client.send(_envelope('d$n')).timeout(const Duration(seconds: 2));
      }
      expect(client.dropped, 2);

      peer.ack(1);
      await _until(() => peer.changeIds.length == 2);
      peer.ack(4);
      await _until(() => peer.changeIds.length == 3);
      expect(peer.changeIds, <String>['d1', 'd4', 'd5']);
    });

    test('sends an unacknowledged change again after a reconnect, under the '
        'same id', () async {
      peer.dropAfterFirstChange = true;
      final client = DVSyncSocket(
        peer.url,
        reconnect: const DVReconnectPolicy(
          initialDelay: Duration(milliseconds: 20),
          jitter: 0,
        ),
      );
      addTearDown(client.close);
      await client.connect();
      await client.send(_envelope('r1'));

      await _until(() => peer.changeIds.length == 2);
      expect(peer.changeIds, <String>['r1', 'r1']);
      final changes = peer.frames.where((f) => f['op'] == 'change').toList();
      expect(changes[0]['id'], changes[1]['id']);
      final hellos = peer.frames.where((f) => f['op'] == 'hello').toList();
      expect(hellos, hasLength(2));
      expect(hellos[0]['client'], hellos[1]['client'],
          reason: 'the relay tells repeats apart by client and id');
    });
  });

  group('the relay', () {
    late HttpServer http;
    late DVSyncRelay relay;

    Future<void> serve(DVSyncRelay hub) async {
      relay = hub;
      http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      http.listen((HttpRequest request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        relay.accept(DVSyncWire.of(socket, socket), tenant: 'default');
      });
    }

    Uri url() => Uri.parse('ws://127.0.0.1:${http.port}/__dv/sync');

    tearDown(() async {
      await relay.close();
      await http.close(force: true);
    });

    test('delivers a change sent again after a reconnect only once, and '
        'acknowledges both', () async {
      await serve(DVSyncRelay());
      final heard = <Object?>[];
      relay.incoming.listen((e) => heard.add((e['model']! as Map)['id']));

      Future<List<Map<String, Object?>>> exchange() async {
        final socket = await WebSocket.connect(url().toString());
        final replies = <Map<String, Object?>>[];
        socket.listen((Object? data) =>
            replies.add(jsonDecode(data! as String) as Map<String, Object?>));
        socket
          ..add(jsonEncode(<String, Object?>{'op': 'hello', 'client': 'phone-1'}))
          ..add(jsonEncode(<String, Object?>{
            'op': 'change',
            'id': 1,
            'envelope': _envelope('once'),
          }));
        await _until(() => replies.any((r) => r['op'] == 'ack'));
        await socket.close();
        return replies;
      }

      final first = await exchange();
      final second = await exchange();
      expect(first.firstWhere((r) => r['op'] == 'ack')['upTo'], 1);
      expect(second.firstWhere((r) => r['op'] == 'ack')['upTo'], 1);
      await _settle();
      expect(heard, <String>['once']);
    });

    test('closes a client too slow to keep up, and others get everything',
        () async {
      await serve(DVSyncRelay(window: 2, maxPending: 3));

      final stalled = await WebSocket.connect(url().toString());
      final stalledFrames = <Map<String, Object?>>[];
      final stalledClosed = Completer<void>();
      stalled.listen(
        (Object? data) => stalledFrames
            .add(jsonDecode(data! as String) as Map<String, Object?>),
        onDone: stalledClosed.complete,
      );

      final healthy = DVSyncSocket(url());
      addTearDown(healthy.close);
      await healthy.connect();
      final received = <Object?>[];
      healthy.incoming.listen((e) => received.add((e['model']! as Map)['id']));
      await _until(() => relay.connections == 2);

      // Paced by the healthy client, which acknowledges as it goes; the
      // stalled one never does.
      for (var n = 1; n <= 10; n++) {
        await relay.send(_envelope('s$n'));
        await _until(() => received.length == n);
      }

      await stalledClosed.future.timeout(const Duration(seconds: 5));
      expect(
        stalledFrames.where((f) => f['op'] == 'change'),
        hasLength(2),
        reason: 'never more than its window unacknowledged',
      );
      await _until(() => received.length == 10);
      expect(received, <String>[for (var n = 1; n <= 10; n++) 's$n']);
      expect(relay.connections, 1);
    });
  });
}
