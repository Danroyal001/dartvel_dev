// The WebSocket carrier model sync and presence ride between processes, run
// against a real local server: an HTTP listener upgrading to WebSocket, the
// framework's relay behind it, and clients connecting over the wire. The same
// carrier compiled by dart2js runs under Node, whose WebSocket is the WHATWG
// one a browser has, so the web code path is exercised too.
@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:io' as io show Platform;

import 'package:dartvel_core/dartvel.dart';
// The carrier and relay are the framework's own, hidden from the barrel an
// application imports, so their tests reach for the framework library.
import 'package:dartvel_core/framework.dart';
import 'package:test/test.dart';

class _Note {
  final String id;
  final String owner;

  const _Note(this.id, this.owner);

  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'owner': owner};

  static _Note fromJson(Map<String, Object?> json) =>
      _Note(json['id']! as String, json['owner']! as String);
}

/// A real listener: `/__dv/sync` upgrades to WebSocket and hands the
/// connection to the relay under the tenant named in the query, standing in
/// for the tenant an authenticated request resolves to.
class _SyncServer {
  final HttpServer http;
  final DVSyncRelay relay;

  _SyncServer(this.http, this.relay);

  static Future<_SyncServer> start({DVSyncRelay? relay}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final hub = relay ?? DVSyncRelay();
    server.listen((HttpRequest request) async {
      if (request.uri.path != '/__dv/sync' ||
          !WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      hub.accept(
        DVSyncWire.of(socket, socket),
        tenant: request.uri.queryParameters['tenant'] ?? 'default',
      );
    });
    return _SyncServer(server, hub);
  }

  Uri url({String tenant = 'default'}) =>
      Uri.parse('ws://127.0.0.1:${http.port}/__dv/sync?tenant=$tenant');

  Future<void> stop() async {
    await relay.close();
    await http.close(force: true);
  }
}

Map<String, Object?> _envelope(String id, {String tenant = 'default'}) =>
    <String, Object?>{
      'type': 'Note',
      'kind': 'updated',
      'tenant': tenant,
      'model': <String, Object?>{'id': id, 'owner': 'ada'},
    };

Future<T> _within<T>(Future<T> future) =>
    future.timeout(const Duration(seconds: 10));

void main() {
  late _SyncServer server;

  setUp(() async {
    server = await _SyncServer.start();
  });

  tearDown(() async {
    await DVModelSync.reset();
    await server.stop();
  });

  test('a change published on one client reaches another over the wire',
      () async {
    DVModelSync.registerCodec<_Note>(
      name: 'Note',
      encode: (note) => note.toJson(),
      decode: _Note.fromJson,
    );
    final local = DVSyncSocket(server.url());
    addTearDown(local.close);
    await _within(local.connect());
    DVModelSync.useTransport(local);

    final peer = DVSyncSocket(server.url());
    addTearDown(peer.close);
    await _within(peer.connect());
    final arriving = peer.incoming.first;

    await DVModelSync.publish(
      const _Note('n1', 'ada'),
      kind: DVModelChangeKind.created,
    );
    final envelope = await _within(arriving);
    expect(envelope['type'], 'Note');
    expect(envelope['kind'], 'created');
    expect(envelope['tenant'], 'default');
    expect(envelope['model'], <String, Object?>{'id': 'n1', 'owner': 'ada'});

    // And the other way: the peer's change lands in local typed watchers.
    final received = DVModelSync.changes<_Note>().first;
    await peer.send(_envelope('from-peer'));
    final change = await _within(received);
    expect(change.model.id, 'from-peer');
    expect(change.kind, DVModelChangeKind.updated);
  });

  test('the sender does not receive its own change back', () async {
    final sender = DVSyncSocket(server.url());
    final other = DVSyncSocket(server.url());
    addTearDown(sender.close);
    addTearDown(other.close);
    await _within(sender.connect());
    await _within(other.connect());

    final echoed = <Map<String, Object?>>[];
    sender.incoming.listen(echoed.add);
    final delivered = other.incoming.first;
    await sender.send(_envelope('once'));
    await _within(delivered);
    // A round trip through the relay after the change proves nothing is
    // still on its way back to the sender.
    final marker = sender.incoming.first;
    await other.send(_envelope('marker'));
    await _within(marker);
    expect(
      echoed.map((e) => (e['model']! as Map)['id']),
      <String>['marker'],
    );
  });

  test('a change never crosses tenants, whatever tenant the client claims',
      () async {
    final ours = DVSyncSocket(server.url());
    final theirs = DVSyncSocket(server.url(tenant: 'acme'));
    final acmePeer = DVSyncSocket(server.url(tenant: 'acme'));
    addTearDown(ours.close);
    addTearDown(theirs.close);
    addTearDown(acmePeer.close);
    await _within(ours.connect());
    await _within(theirs.connect());
    await _within(acmePeer.connect());

    final leaked = <Map<String, Object?>>[];
    ours.incoming.listen(leaked.add);

    // Acme's client claims the default tenant; the relay stamps the tenant
    // its connection was accepted under, so the claim is not believed.
    final acmeReceives = acmePeer.incoming.first;
    await theirs.send(_envelope('spoofed', tenant: 'default'));
    final delivered = await _within(acmeReceives);
    expect(delivered['tenant'], 'acme');

    // A default-tenant marker sent after it arrives behind anything that was
    // queued for us, so seeing only the marker shows nothing leaked.
    final marker = ours.incoming.first;
    await server.relay.send(_envelope('marker'));
    await _within(marker);
    expect(
      leaked.map((e) => (e['model']! as Map)['id']),
      <String>['marker'],
    );
  });

  test('the server process hears clients and its own changes reach them',
      () async {
    final client = DVSyncSocket(server.url());
    addTearDown(client.close);
    await _within(client.connect());

    final heard = server.relay.incoming.first;
    await client.send(_envelope('up'));
    final up = await _within(heard);
    expect((up['model']! as Map)['id'], 'up');
    expect(up['tenant'], 'default');

    final down = client.incoming.first;
    await server.relay.send(_envelope('down'));
    expect(((await _within(down))['model']! as Map)['id'], 'down');
  });

  test('connecting to a path that is not a sync endpoint fails loudly',
      () async {
    final wrong = DVSyncSocket(
      Uri.parse('ws://127.0.0.1:${server.http.port}/elsewhere'),
    );
    addTearDown(wrong.close);
    await expectLater(_within(wrong.connect()), throwsA(isA<Object>()));
  });

  final bool hasNode = Process.runSync('which', <String>['node']).exitCode == 0;

  test(
    'dart2js: the web carrier sends and receives through the same relay',
    () async {
      final dir = Directory('.dart_tool/dv_sync_socket_web')
        ..createSync(recursive: true);
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/main.dart').writeAsStringSync(r'''
import 'dart:async';
import 'dart:convert';

import 'package:dartvel_core/framework.dart';

Future<void> main() async {
  final socket = DVSyncSocket(Uri.parse(const String.fromEnvironment('url')));
  await socket.connect();
  final first = socket.incoming.first;
  print('ready');
  final envelope = await first.timeout(const Duration(seconds: 10));
  print('got ${jsonEncode(envelope)}');
  await socket.send(<String, Object?>{
    'type': 'Note',
    'kind': 'created',
    'tenant': 'default',
    'model': <String, Object?>{'id': 'from-web', 'owner': 'ada'},
  });
  await Future<void>.delayed(const Duration(milliseconds: 200));
  await socket.close();
  print('closed');
}
''');
      final compiled = await Process.run(io.Platform.resolvedExecutable, <String>[
        'compile',
        'js',
        '-O1',
        '-Durl=${server.url()}',
        '-o',
        '${dir.path}/main.js',
        '${dir.path}/main.dart',
      ]);
      expect(compiled.exitCode, 0,
          reason: '${compiled.stdout}\n${compiled.stderr}');
      File('${dir.path}/run.js').writeAsStringSync(
        'globalThis.self = globalThis;\nrequire("./main.js");\n',
      );

      final web = await Process.start('node', <String>['${dir.path}/run.js']);
      final lines = web.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream();
      final stderrText = web.stderr.transform(utf8.decoder).join();
      final ready = lines.firstWhere((l) => l == 'ready');
      await _within(ready).catchError((Object error) async {
        web.kill();
        fail('web client never connected: ${await stderrText}');
      });

      final fromWeb = server.relay.incoming.first;
      final got = lines.firstWhere((l) => l.startsWith('got '));
      final closed = lines.firstWhere((l) => l == 'closed');
      await server.relay.send(_envelope('to-web'));

      final gotLine = await _within(got);
      final toWeb = jsonDecode(gotLine.substring(4)) as Map<String, Object?>;
      expect((toWeb['model']! as Map)['id'], 'to-web');

      final up = await _within(fromWeb);
      expect((up['model']! as Map)['id'], 'from-web');
      expect(up['tenant'], 'default');

      await _within(closed);
      expect(await _within(web.exitCode), 0, reason: await stderrText);
    },
    skip: hasNode ? false : 'node is not installed',
  );
}
