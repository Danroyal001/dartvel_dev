/// What `dartvel dev --dev-client` serves to a paired shell.
///
/// One endpoint. A request without this run's token gets a 401 and nothing
/// else; a request with it gets the current page documents sealed with this
/// run's key, stamped with the branch, the binding manifest the project needs
/// now, and a sequence that rises whenever what is served changes. Everything
/// is read at request time, so an edit is never answered with the bundle from
/// before it.
library;

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
  );

  final HttpServer _server;
  final String _root;
  final String _branch;
  final DVDevClientSigner _signer;

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
  }) async {
    final HttpServer server = await HttpServer.bind(
      address ?? InternetAddress.anyIPv4,
      port,
    );
    final String host = advertisedHost ?? await dvDetectLanHost();
    final DVDevClientSigner signer = DVDevClientSigner.generate();
    final DVDevClientPairing pairing = DVDevClientPairing(
      server: Uri(scheme: 'http', host: host, port: server.port),
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
    );
    server.listen(bundles._handle);
    return bundles;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
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
