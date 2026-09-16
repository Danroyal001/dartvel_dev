// The tunnel a development build opens to `dartvel dev --dev-client`, so the
// dev server can reach the app's Dart VM service on the device.
//
// The device dials out; nothing on the phone listens on the network. Its VM
// service stays on the phone's loopback, and the dev server gets a loopback
// port of its own that leads there -- which is what `flutter attach` is
// pointed at.
//
// Over real sockets, speaking the protocol the device's Java speaks. The
// Java itself is run against this server in android_dev_tunnel_java_test.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartvel_cli/src/devclient/dev_client_server.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

import 'dev_client_server_test.dart' show writeProject;

/// A raw connection to the tunnel path, reading the response head by hand the
/// way the device does, so nothing after the head is swallowed by a parser.
class RawTunnel {
  RawTunnel._(this.socket, this.status, this.headers, this.rest);

  final Socket socket;
  final int status;
  final Map<String, String> headers;

  /// Bytes after the head, as they arrive.
  final Stream<List<int>> rest;

  static Future<RawTunnel> open(
    int port, {
    required String query,
    String? token,
  }) async {
    final Socket socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
    );
    socket.write(
      'GET $dvDevClientTunnelPath?$query HTTP/1.1\r\n'
      'Host: 127.0.0.1:$port\r\n'
      '${token == null ? '' : 'Authorization: Bearer $token\r\n'}'
      'Connection: Upgrade\r\n'
      'Upgrade: $dvDevClientTunnelProtocol\r\n'
      '\r\n',
    );
    final StreamController<List<int>> rest = StreamController<List<int>>();
    final Completer<(int, Map<String, String>)> head =
        Completer<(int, Map<String, String>)>();
    final List<int> buffer = <int>[];
    socket.listen(
      (Uint8List chunk) {
        if (head.isCompleted) {
          rest.add(chunk);
          return;
        }
        buffer.addAll(chunk);
        final String text = latin1.decode(buffer);
        final int end = text.indexOf('\r\n\r\n');
        if (end < 0) return;
        final List<String> lines = text.substring(0, end).split('\r\n');
        final int status = int.parse(lines.first.split(' ')[1]);
        final Map<String, String> headers = <String, String>{
          for (final String line in lines.skip(1))
            line.substring(0, line.indexOf(':')).trim().toLowerCase(): line
                .substring(line.indexOf(':') + 1)
                .trim(),
        };
        head.complete((status, headers));
        if (buffer.length > end + 4) rest.add(buffer.sublist(end + 4));
      },
      onDone: () {
        if (!head.isCompleted) head.complete((0, <String, String>{}));
        rest.close();
      },
      onError: (Object _) {},
    );
    final (int status, Map<String, String> headers) = await head.future
        .timeout(const Duration(seconds: 5));
    return RawTunnel._(socket, status, headers, rest.stream.asBroadcastStream());
  }
}

String nonce() {
  final Random random = Random.secure();
  return base64Url
      .encode(List<int>.generate(32, (_) => random.nextInt(256)))
      .replaceAll('=', '');
}

void main() {
  late Directory root;
  late DVDevClientBundleServer server;
  late List<DVDevClientDevice> devices;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('dartvel_dev_tunnel_');
    writeProject(root);
    devices = <DVDevClientDevice>[];
    server = await DVDevClientBundleServer.start(
      root: root.path,
      branch: 'main',
      address: InternetAddress.loopbackIPv4,
      port: 0,
      advertisedHost: '127.0.0.1',
      onDevice: devices.add,
    );
  });

  tearDown(() async {
    await server.close();
    root.deleteSync(recursive: true);
  });

  Map<String, Object?> hello({List<String>? bindings}) => <String, Object?>{
    'vmService': '/Q52L-EEB5A0=/',
    'manifest': <String, Object?>{
      'target': 'android',
      'bindings': bindings ?? <String>['dartvel_flutter@0.4.0', 'plugin:jni'],
    },
  };

  Future<RawTunnel> control({List<String>? bindings}) async {
    final RawTunnel tunnel = await RawTunnel.open(
      server.port,
      query: 'role=control&nonce=${nonce()}',
      token: server.pairing.token,
    );
    expect(tunnel.status, 101);
    tunnel.socket.write('${jsonEncode(hello(bindings: bindings))}\n');
    return tunnel;
  }

  Stream<String> lines(RawTunnel tunnel) => tunnel.rest
      .transform(utf8.decoder)
      .transform(const LineSplitter());

  test('without the pairing token there is no tunnel', () async {
    final RawTunnel tunnel = await RawTunnel.open(
      server.port,
      query: 'role=control&nonce=${nonce()}',
      token: 'not-the-token',
    );
    expect(tunnel.status, 401);
    expect(tunnel.headers, isNot(contains('x-dartvel-proof')));
    tunnel.socket.destroy();
    expect(devices, isEmpty);
  });

  test('the server proves it holds the key the device paired with', () async {
    final String challenge = nonce();
    final RawTunnel tunnel = await RawTunnel.open(
      server.port,
      query: 'role=control&nonce=$challenge',
      token: server.pairing.token,
    );
    expect(tunnel.status, 101);
    final String proof = tunnel.headers['x-dartvel-proof']!;
    expect(
      dvDevClientTunnelProofValid(
        nonce: challenge,
        proof: proof,
        publicKey: server.pairing.publicKey,
      ),
      isTrue,
    );
    // Bound to the challenge: the same proof answers no other nonce, so a
    // recorded handshake cannot be replayed to a device.
    expect(
      dvDevClientTunnelProofValid(
        nonce: nonce(),
        proof: proof,
        publicKey: server.pairing.publicKey,
      ),
      isFalse,
    );
    // And to the key: another server's key does not verify it.
    expect(
      dvDevClientTunnelProofValid(
        nonce: challenge,
        proof: proof,
        publicKey: DVDevClientSigner.generate().publicKey,
      ),
      isFalse,
    );
    tunnel.socket.destroy();
  });

  test('a challenge that is too short to be random is refused', () async {
    final RawTunnel tunnel = await RawTunnel.open(
      server.port,
      query: 'role=control&nonce=abc',
      token: server.pairing.token,
    );
    expect(tunnel.status, 400);
    tunnel.socket.destroy();
  });

  test('a compatible device gets a loopback URL that reaches its VM service',
      () async {
    final RawTunnel device = await control();
    final Stream<String> commands = lines(device);
    final Future<String> firstCommand = commands.first;

    await _until(() => devices.isNotEmpty);
    final DVDevClientDevice attached = devices.single;
    expect(attached.debugUrl.host, '127.0.0.1');
    expect(attached.debugUrl.path, '/Q52L-EEB5A0=/');
    expect(attached.manifest.bindings, contains('plugin:jni'));

    // flutter attach connects to the loopback port...
    final Socket attach = await Socket.connect(
      InternetAddress.loopbackIPv4,
      attached.debugUrl.port,
    );
    // ...which asks the device to open a stream for it.
    final String open = await firstCommand.timeout(const Duration(seconds: 5));
    expect(open, startsWith('open '));
    final String id = open.substring('open '.length);

    final RawTunnel stream = await RawTunnel.open(
      server.port,
      query: 'role=stream&id=$id&nonce=${nonce()}',
      token: server.pairing.token,
    );
    expect(stream.status, 101);

    // Bytes both ways: the attach side's request reaches the device, and the
    // device's answer (the VM service's, on a phone) comes back.
    final Future<String> atDevice = stream.rest
        .transform(utf8.decoder)
        .first
        .timeout(const Duration(seconds: 5));
    attach.write('GET /Q52L-EEB5A0=/ws HTTP/1.1\r\n\r\n');
    expect(await atDevice, startsWith('GET /Q52L-EEB5A0=/ws'));

    final Future<String> atAttach = utf8.decoder
        .bind(attach)
        .first
        .timeout(const Duration(seconds: 5));
    stream.socket.write('HTTP/1.1 101 from the VM service\r\n\r\n');
    expect(await atAttach, startsWith('HTTP/1.1 101 from the VM service'));

    attach.destroy();
    stream.socket.destroy();
    device.socket.destroy();
  });

  test('a device missing a binding the project needs is refused', () async {
    final RawTunnel device = await control(
      bindings: <String>['dartvel_flutter@0.4.0'],
    );
    final String reply = await lines(
      device,
    ).first.timeout(const Duration(seconds: 5));
    expect(reply, startsWith('refused $dvDevClientMissingBinding'));
    expect(reply, contains('plugin:jni'));
    expect(reply, contains('dartvel build android --profile development'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(devices, isEmpty);
    device.socket.destroy();
  });

  test('a hello that is not JSON is refused and no device appears', () async {
    final RawTunnel device = await RawTunnel.open(
      server.port,
      query: 'role=control&nonce=${nonce()}',
      token: server.pairing.token,
    );
    device.socket.write('hello\n');
    final String reply = await lines(
      device,
    ).first.timeout(const Duration(seconds: 5));
    expect(reply, startsWith('refused'));
    expect(devices, isEmpty);
    device.socket.destroy();
  });

  test('a stream nobody asked for is refused', () async {
    final RawTunnel stream = await RawTunnel.open(
      server.port,
      query: 'role=stream&id=999&nonce=${nonce()}',
      token: server.pairing.token,
    );
    expect(stream.status, 404);
    stream.socket.destroy();
  });

  test('when the device goes, so does its loopback port', () async {
    final RawTunnel device = await control();
    await _until(() => devices.isNotEmpty);
    final DVDevClientDevice attached = devices.single;

    device.socket.destroy();
    await attached.closed.timeout(const Duration(seconds: 5));
    await expectLater(
      Socket.connect(InternetAddress.loopbackIPv4, attached.debugUrl.port),
      throwsA(isA<SocketException>()),
    );
  });
}

Future<void> _until(bool Function() condition) async {
  final Stopwatch watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > const Duration(seconds: 5)) {
      fail('timed out waiting');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
