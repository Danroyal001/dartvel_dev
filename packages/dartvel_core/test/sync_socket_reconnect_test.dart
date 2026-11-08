// Reconnect and heartbeat for the sync carrier, against a real local
// server that is stopped, restarted and made to go silent.
@TestOn('vm')
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

// The carrier is the framework's own, hidden from the barrel an application
// imports, so its tests reach for the framework library.
import 'package:dartvel_core/framework.dart';
import 'package:test/test.dart';

/// A listener on a fixed port so it can be stopped and started again at
/// the same address, the way a server restarts during a deploy.
class _Server {
  final int port;
  final Duration? idleTimeout;

  /// When set, connections are upgraded and then ignored: no relay, no
  /// pong, no close -- a half-dead link.
  final bool silent;

  HttpServer? _http;
  DVSyncRelay? relay;
  final List<WebSocket> _silentSockets = <WebSocket>[];
  int accepted = 0;

  _Server(this.port, {this.idleTimeout, this.silent = false});

  /// A free port below the kernel's ephemeral range, so that while this
  /// server is stopped for a restart nothing else in the run binding port 0
  /// can be handed its port.
  static Future<int> freePort() async {
    final random = Random();
    for (var tries = 0; tries < 200; tries++) {
      final port = 20000 + random.nextInt(12000);
      try {
        final probe =
            await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
        await probe.close();
        return port;
      } on SocketException {
        continue;
      }
    }
    throw StateError('no free port below the ephemeral range');
  }

  Future<void> start() async {
    final hub = DVSyncRelay(idleTimeout: idleTimeout);
    relay = hub;
    final http = await _bindAgain();
    _http = http;
    http.listen((HttpRequest request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      accepted++;
      if (silent) {
        _silentSockets.add(socket);
        socket.listen((_) {});
        return;
      }
      hub.accept(DVSyncWire.of(socket, socket), tenant: 'default');
    });
  }

  /// Binds the fixed port, waiting briefly if the socket the last run of
  /// this server held has not been released yet -- as a restarting server
  /// would.
  Future<HttpServer> _bindAgain() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (true) {
      try {
        return await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      } on SocketException catch (error) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('port $port stayed busy: $error');
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  Future<void> stop() async {
    await relay?.close();
    for (final socket in _silentSockets) {
      await socket.close();
    }
    _silentSockets.clear();
    await _http?.close(force: true);
    _http = null;
  }

  Uri get url => Uri.parse('ws://127.0.0.1:$port/__dv/sync');
}

Map<String, Object?> _envelope(String id) => <String, Object?>{
      'type': 'Note',
      'kind': 'updated',
      'tenant': 'default',
      'model': <String, Object?>{'id': id, 'owner': 'ada'},
    };

Object? _id(Map<String, Object?> envelope) =>
    (envelope['model']! as Map)['id'];

Future<T> _within<T>(Future<T> future) =>
    future.timeout(const Duration(seconds: 10));

const DVReconnectPolicy _fast = DVReconnectPolicy(
  initialDelay: Duration(milliseconds: 20),
  maxDelay: Duration(milliseconds: 100),
  jitter: 0,
);

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition never held');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  group('the reconnect policy', () {
    test('backs off exponentially up to its ceiling', () {
      const policy = DVReconnectPolicy(
        initialDelay: Duration(milliseconds: 100),
        maxDelay: Duration(seconds: 1),
        multiplier: 2,
        jitter: 0,
      );
      expect(
        <Duration?>[for (var attempt = 1; attempt <= 6; attempt++) policy.delayFor(attempt)],
        <Duration>[
          const Duration(milliseconds: 100),
          const Duration(milliseconds: 200),
          const Duration(milliseconds: 400),
          const Duration(milliseconds: 800),
          const Duration(seconds: 1),
          const Duration(seconds: 1),
        ],
      );
    });

    test('jitter spreads the delay so clients do not return in lockstep', () {
      const policy = DVReconnectPolicy(
        initialDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 1),
        jitter: 0.5,
      );
      final random = Random(7);
      final delays = <int>{
        for (var i = 0; i < 50; i++)
          policy.delayFor(3, random: random)!.inMilliseconds,
      };
      expect(delays.length, greaterThan(10));
      expect(delays.every((ms) => ms >= 500 && ms <= 1000), isTrue,
          reason: '$delays');
    });

    test('gives up after maxAttempts, and never when it is null', () {
      const limited = DVReconnectPolicy(maxAttempts: 3, jitter: 0);
      expect(limited.delayFor(3), isNotNull);
      expect(limited.delayFor(4), isNull);
      expect(const DVReconnectPolicy(jitter: 0).delayFor(10000), isNotNull);
      expect(DVReconnectPolicy.never.delayFor(1), isNull);
    });
  });

  group('over a real server', () {
    late _Server server;

    setUp(() async {
      server = _Server(await _Server.freePort());
      await server.start();
    });

    tearDown(() => server.stop());

    test('reconnects after a restart, keeps its stream, and sends what was '
        'written while the server was down', () async {
      final client = DVSyncSocket(server.url, reconnect: _fast);
      addTearDown(client.close);
      await _within(client.connect());
      final received = <Object?>[];
      client.incoming.listen((e) => received.add(_id(e)));

      await server.stop();
      await _until(() => client.state == DVSyncSocketState.reconnecting);
      // Written with nobody to take it: held, not thrown away or thrown.
      await client.send(_envelope('while-down'));

      final heard = <Object?>[];
      await server.start();
      server.relay!.incoming.listen((e) => heard.add(_id(e)));
      await _until(() => client.state == DVSyncSocketState.connected);
      await _until(() => heard.contains('while-down'));

      // The same incoming stream carries changes after the reconnect.
      await server.relay!.send(_envelope('after'));
      await _until(() => received.contains('after'));
      expect(server.accepted, 2);
    });

    test('close() ends reconnecting for good', () async {
      final client = DVSyncSocket(server.url, reconnect: _fast);
      await _within(client.connect());
      await client.close();
      await server.stop();
      await server.start();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(server.accepted, 1);
      expect(client.state, DVSyncSocketState.closed);
      await expectLater(client.send(_envelope('late')), throwsStateError);
    });

    test('a policy that runs out of attempts leaves the socket failed',
        () async {
      final client = DVSyncSocket(
        server.url,
        reconnect: const DVReconnectPolicy(
          initialDelay: Duration(milliseconds: 10),
          maxAttempts: 2,
          jitter: 0,
        ),
      );
      addTearDown(client.close);
      await _within(client.connect());
      await server.stop();
      await _until(() => client.state == DVSyncSocketState.failed);
      await expectLater(client.send(_envelope('nowhere')), throwsStateError);
    });

    test('the relay drops a connection that has gone silent, and a client '
        'that heartbeats stays', () async {
      await server.stop();
      server = _Server(server.port,
          idleTimeout: const Duration(milliseconds: 300));
      await server.start();

      final quiet = await DVSyncWire.connect(server.url);
      final quietDone = Completer<void>();
      quiet.messages.listen((_) {}, onDone: quietDone.complete);

      final alive = DVSyncSocket(
        server.url,
        reconnect: DVReconnectPolicy.never,
        heartbeat: const Duration(milliseconds: 50),
        // Generous, so a loaded machine delaying a pong cannot fail it.
        heartbeatTimeout: const Duration(seconds: 5),
      );
      addTearDown(alive.close);
      await _within(alive.connect());

      await _within(quietDone.future);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(alive.state, DVSyncSocketState.connected);
      expect(server.relay!.connections, 1);
    });
  });

  test('a half-dead link is noticed by the heartbeat and replaced', () async {
    final silent = _Server(await _Server.freePort(), silent: true);
    await silent.start();
    addTearDown(silent.stop);

    final client = DVSyncSocket(
      silent.url,
      reconnect: _fast,
      heartbeat: const Duration(milliseconds: 50),
      heartbeatTimeout: const Duration(milliseconds: 200),
    );
    addTearDown(client.close);
    await _within(client.connect());
    // No pong ever comes back, and the socket never closes on its own.
    await _until(() => silent.accepted >= 2);
  });
}
