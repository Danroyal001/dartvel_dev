/// What `dartvel dev` serves to a paired shell.
///
/// Over TLS only, with a self-signed certificate for this run's key: the key
/// the pairing link carries, which a device pins the connection to. The token
/// never crosses the network in the clear, and a machine on the LAN that saw
/// the traffic reads neither it nor the pages.
///
/// One endpoint. A request without this run's token gets a 401 and nothing
/// else; a request with it gets the current page documents sealed with this
/// run's key, stamped with the branch, the binding manifest the project needs
/// now, and a sequence that rises whenever what is served changes. Everything
/// is read at request time, so an edit is never answered with the bundle from
/// before it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:path/path.dart' as p;

import '../utils/lan_address.dart';
import 'dev_client_project.dart';

class DVDevClientBundleServer {
  DVDevClientBundleServer._(
    this._server,
    this._root,
    this.pairing,
    this._signer,
    this._branch,
    this._onDevice,
  );

  final HttpServer _server;
  final String _root;
  final String _branch;
  final DVDevClientSigner _signer;
  final void Function(DVDevClientDevice device)? _onDevice;

  /// Local connections waiting for their device to open a stream, by id.
  final Map<int, Socket> _waitingStreams = <int, Socket>{};
  int _streamId = 0;
  final Set<DVDevClientDevice> _devices = <DVDevClientDevice>{};

  /// What the link a device scans carries.
  final DVDevClientPairing pairing;

  String? _servedDigest;
  int _sequence = 0;

  int get port => _server.port;

  /// Starts serving [root]'s bundles for [branch].
  ///
  /// The key and the token are fresh on every start, so a pairing lasts as
  /// long as this run and a link from yesterday lets nobody in.
  static Future<DVDevClientBundleServer> start({
    required String root,
    required String branch,
    InternetAddress? address,
    int port = 8787,
    String? advertisedHost,
    void Function(DVDevClientDevice device)? onDevice,
  }) async {
    final DVDevClientSigner signer = DVDevClientSigner.generate();
    final HttpServer server = await HttpServer.bindSecure(
      address ?? InternetAddress.anyIPv4,
      port,
      dvDevClientServerContext(signer.certificate()),
    );
    final String host = advertisedHost ?? await dvDetectLanHost();
    final DVDevClientPairing pairing = DVDevClientPairing(
      server: Uri(scheme: 'https', host: host, port: server.port),
      branch: branch,
      publicKey: signer.publicKey,
      token: DVDevClientPairing.newToken(),
    );
    final DVDevClientBundleServer bundles = DVDevClientBundleServer._(
      server,
      root,
      pairing,
      signer,
      branch,
      onDevice,
    );
    server.listen(bundles._handle);
    return bundles;
  }

  Future<void> close() async {
    for (final DVDevClientDevice device in _devices.toList()) {
      await device.close();
    }
    for (final Socket waiting in _waitingStreams.values) {
      waiting.destroy();
    }
    _waitingStreams.clear();
    await _server.close(force: true);
  }

  bool _authorized(HttpRequest request) {
    final String? header = request.headers.value('authorization');
    final String? presented = header != null && header.startsWith('Bearer ')
        ? header.substring('Bearer '.length)
        : null;
    return DVDevClientPairing.tokenMatches(presented, pairing.token);
  }

  Future<void> _handle(HttpRequest request) async {
    if (request.uri.path == dvDevClientTunnelPath) {
      await _tunnel(request);
      return;
    }
    final HttpResponse response = request.response;
    try {
      if (request.uri.path != dvDevClientBundlePath) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final String? header = request.headers.value('authorization');
      final String? presented = header != null && header.startsWith('Bearer ')
          ? header.substring('Bearer '.length)
          : null;
      if (!DVDevClientPairing.tokenMatches(presented, pairing.token)) {
        response.statusCode = HttpStatus.unauthorized;
        response.write('Not paired with this dev server.');
        return;
      }
      final String target = request.uri.queryParameters['target'] ?? '';
      if (!dvDevClientTargets.contains(target)) {
        response.statusCode = HttpStatus.badRequest;
        response.write('No shell is built for "$target".');
        return;
      }

      final DVDevClientManifest manifest;
      try {
        manifest = dvProjectDevClientManifest(_root, target);
      } on DVDevClientProjectException catch (error) {
        response.statusCode = HttpStatus.serviceUnavailable;
        response.write(error.message);
        return;
      }

      final List<Object?> pages;
      try {
        pages = _pages();
      } on DVDevClientProjectException catch (error) {
        response.statusCode = HttpStatus.internalServerError;
        response.write(error.message);
        return;
      }

      final Map<String, Object?> bundle = <String, Object?>{'pages': pages};
      final String digest = sha256
          .convert(
            utf8.encode(
              jsonEncode(<String, Object?>{
                'version': dvDevClientBundleVersion(bundle),
                'requires': manifest.toJson(),
              }),
            ),
          )
          .toString();
      if (digest != _servedDigest) {
        _servedDigest = digest;
        _sequence++;
      }

      response.headers.contentType = ContentType.json;
      response.headers.set('cache-control', 'no-store');
      response.write(
        _signer.seal(
          bundle: bundle,
          channel: _branch,
          requires: manifest,
          sequence: _sequence,
        ),
      );
    } finally {
      await response.close();
    }
  }

  /// A development build's tunnel connection: `role=control` once per device,
  /// `role=stream` once for each connection made to that device's loopback
  /// port.
  ///
  /// Either way the token is checked first and the answer carries a proof
  /// over the device's nonce, which the device verifies against the key in
  /// its pairing link before it sends a byte.
  Future<void> _tunnel(HttpRequest request) async {
    final HttpResponse response = request.response;
    Future<void> refuse(int status, String message) async {
      response.statusCode = status;
      response.write(message);
      await response.close();
    }

    if (!_authorized(request)) {
      await refuse(HttpStatus.unauthorized, 'Not paired with this dev server.');
      return;
    }
    final String nonce = request.uri.queryParameters['nonce'] ?? '';
    // 32 random bytes is 43 characters of base64url. Anything shorter is not
    // a challenge worth signing.
    if (!RegExp(r'^[A-Za-z0-9_-]{43,128}$').hasMatch(nonce)) {
      await refuse(HttpStatus.badRequest, 'The tunnel needs a random nonce.');
      return;
    }
    final String role = request.uri.queryParameters['role'] ?? '';
    Socket? waiting;
    if (role == 'stream') {
      final int? id = int.tryParse(request.uri.queryParameters['id'] ?? '');
      waiting = id == null ? null : _waitingStreams.remove(id);
      if (waiting == null) {
        await refuse(HttpStatus.notFound, 'No stream was asked for with that id.');
        return;
      }
    } else if (role != 'control') {
      await refuse(HttpStatus.badRequest, 'A tunnel is a control or a stream.');
      return;
    }

    response.statusCode = HttpStatus.switchingProtocols;
    response.headers
      ..set('connection', 'Upgrade')
      ..set('upgrade', dvDevClientTunnelProtocol)
      ..set('x-dartvel-proof', dvDevClientTunnelProof(_signer, nonce));
    final Socket socket = await response.detachSocket(writeHeaders: true);

    if (waiting != null) {
      _pipe(waiting, socket);
      return;
    }
    await _control(socket);
  }

  Future<void> _control(Socket socket) async {
    final StreamIterator<String> lines = StreamIterator<String>(
      utf8.decoder.bind(socket).transform(const LineSplitter()),
    );
    void refuse(String message) {
      socket.write('refused ${message.replaceAll('\n', ' ')}\n');
      unawaited(socket.flush().whenComplete(socket.destroy));
    }

    final String hello;
    try {
      if (!await lines.moveNext().timeout(const Duration(seconds: 10))) {
        socket.destroy();
        return;
      }
      hello = lines.current;
    } on Object {
      socket.destroy();
      return;
    }

    final String vmService;
    final DVDevClientManifest shell;
    try {
      final Object? decoded = jsonDecode(hello);
      if (decoded is! Map) throw const FormatException('not an object');
      final Object? path = decoded['vmService'];
      if (path is! String || !RegExp(r'^/[A-Za-z0-9_=-]*/?$').hasMatch(path)) {
        throw const FormatException('no VM service path');
      }
      vmService = path.endsWith('/') ? path : '$path/';
      shell = DVDevClientManifest.fromJson(
        (decoded['manifest'] as Map<Object?, Object?>).cast<String, Object?>(),
      );
    } on Object catch (error) {
      refuse('The device\'s hello did not parse: $error');
      return;
    }

    final DVDevClientManifest project;
    try {
      project = dvProjectDevClientManifest(_root, shell.target);
    } on DVDevClientProjectException catch (error) {
      refuse(error.message);
      return;
    }
    final DVDevClientRefusal? refusal = dvDevClientCompatibility(
      shell: shell,
      bundle: project,
    );
    if (refusal != null) {
      refuse(refusal.toString());
      return;
    }

    final ServerSocket local = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final DVDevClientDevice device = DVDevClientDevice._(
      debugUrl: Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: local.port,
        path: vmService,
      ),
      manifest: shell,
      address: socket.remoteAddress.address,
    );
    final Set<int> mine = <int>{};
    device._onClose = () async {
      await local.close();
      for (final int id in mine) {
        _waitingStreams.remove(id)?.destroy();
      }
      socket.destroy();
      _devices.remove(device);
    };
    _devices.add(device);

    local.listen((Socket client) {
      final int id = ++_streamId;
      mine.add(id);
      _waitingStreams[id] = client;
      socket.write('open $id\n');
      // A device that never opens the stream leaves nothing half-connected.
      Timer(const Duration(seconds: 15), () {
        if (_waitingStreams.remove(id) != null) client.destroy();
      });
    });

    // Anything the device says after its hello is ignored; the connection
    // ending is the device going away.
    unawaited(() async {
      try {
        while (await lines.moveNext()) {}
      } on Object {
        // A reset is the device going away too.
      }
      await device.close();
    }());

    _onDevice?.call(device);
  }

  void _pipe(Socket a, Socket b) {
    void link(Socket from, Socket to) {
      from.listen(
        (List<int> data) {
          try {
            to.add(data);
          } on Object {
            from.destroy();
          }
        },
        onDone: to.destroy,
        onError: (Object _) => to.destroy(),
        cancelOnError: true,
      );
    }

    link(a, b);
    link(b, a);
  }

  List<Object?> _pages() {
    final Directory directory = Directory(p.join(_root, dvDevClientPagesDir));
    if (!directory.existsSync()) return const <Object?>[];
    final List<File> files =
        directory
            .listSync()
            .whereType<File>()
            .where((File f) => f.path.endsWith('.json'))
            .toList()
          ..sort((File a, File b) => a.path.compareTo(b.path));
    return <Object?>[for (final File file in files) _page(file)];
  }

  Object? _page(File file) {
    final String name = p.relative(file.path, from: _root);
    final Object? document;
    try {
      document = jsonDecode(file.readAsStringSync());
    } on FormatException catch (error) {
      throw DVDevClientProjectException('$name is not JSON: ${error.message}');
    }
    if (document is! Map ||
        document['route'] is! String ||
        (document['route'] as String).isEmpty) {
      throw DVDevClientProjectException(
        '$name is not a page document: it names no route.',
      );
    }
    return document;
  }
}

/// A development build connected to this dev server.
class DVDevClientDevice {
  DVDevClientDevice._({
    required this.debugUrl,
    required this.manifest,
    required this.address,
  });

  /// Where the device's Dart VM service is reached from this machine: a
  /// loopback port that leads through the tunnel. `flutter attach
  /// --debug-url` takes it as it is.
  final Uri debugUrl;

  /// The binding manifest the device's build recorded.
  final DVDevClientManifest manifest;

  /// The device's address, for telling devices apart in the log.
  final String address;

  final Completer<void> _closed = Completer<void>();
  Future<void> Function()? _onClose;

  /// Completes when the device disconnects or [close] is called.
  Future<void> get closed => _closed.future;

  Future<void> close() async {
    if (_closed.isCompleted) return;
    await _onClose?.call();
    if (!_closed.isCompleted) _closed.complete();
  }
}
