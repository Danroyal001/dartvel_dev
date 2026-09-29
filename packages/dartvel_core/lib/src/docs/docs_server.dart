/// The documentation server that responds to requests under the docs mount.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../admin/admin_server.dart'
    show
        DVAdminMount,
        dvAdminAuthorized,
        dvAdminHiddenHeaders,
        dvAdminHiddenStatus;
import '../admin/studio_dev_grant.dart';
import '../http/wintercg.dart';
import 'docs_mount.dart';

/// The documentation server that responds to requests under [DVDocsMount.path].
///
/// Built on the same principles and access mechanisms as Studio:
/// - With [DVDocsAccess.studio], signed-out callers get a 302 redirect to the
///   Studio sign-in (`<adminMount.path>/login?from=...`), docs data (`docs.json`,
///   `graph.json`) answers 404 without a Studio grant, and authorized callers
///   receive the docs app and data.
/// - With [DVDocsAccess.public], any caller can access the documentation site
///   and its data without authentication.
class DVDocsServer {
  DVDocsServer({
    required this.mount,
    required this.root,
    this.adminMount = const DVAdminMount(
      path: '/__studio',
      enabled: true,
      requiresAuth: true,
    ),
    Future<bool> Function(Request request)? authenticated,
    this.devGrant,
  }) : _authenticated = authenticated ?? devGrant?.check ?? dvAdminAuthorized;

  final DVDocsMount mount;

  /// The directory on disk holding the compiled docs application, `docs.json`,
  /// and `graph.json`.
  final String root;

  /// Studio's mount, where login and sign-in live.
  final DVAdminMount adminMount;

  final Future<bool> Function(Request request) _authenticated;

  /// Development grant, if any.
  final DVStudioDevGrant? devGrant;

  /// Whether [path] under the mount is a page a person navigates to, rather
  /// than an asset file with an extension or data.
  bool _isPage(String path) {
    if (path == mount.path || path == '${mount.path}/') return true;
    final String last = path.split('/').last;
    return !last.contains('.');
  }

  /// Responds to [request] if it falls under the docs mount.
  /// Returns null if the request is not under the mount or the mount is disabled.
  Future<Response?> respond(Request request) async {
    final String path = request.url.path.isEmpty ? '/' : request.url.path;
    if (!mount.owns(path)) return null;
    if (!mount.enabled) return null;

    final Response? claimed = devGrant?.claim(request, adminMount);
    if (claimed != null) return claimed;

    final bool authorized = mount.access == DVDocsAccess.public
        ? true
        : await _authenticated(request);

    // Docs data: docs.json and graph.json
    final bool isDocsData =
        path == '${mount.path}/docs.json' || path == '${mount.path}/graph.json';
    if (isDocsData) {
      if (!authorized) {
        return Response(
          dvAdminHiddenStatus,
          headers: Headers(dvAdminHiddenHeaders),
          body: const Stream<List<int>>.empty(),
        );
      }
      final String filename =
          path.endsWith('graph.json') ? 'graph.json' : 'docs.json';
      final File file = File(p.join(root, filename));
      if (!file.existsSync()) {
        return Response(
          dvAdminHiddenStatus,
          headers: Headers(dvAdminHiddenHeaders),
          body: const Stream<List<int>>.empty(),
        );
      }
      return Response(
        200,
        headers: Headers(<String, String>{
          'content-type': 'application/json',
          'cache-control': 'no-store',
        }),
        body: Stream<List<int>>.value(file.readAsBytesSync()),
      );
    }

    // Page navigation (e.g. /docs, /docs/, /docs/overview, /docs/models)
    if (_isPage(path)) {
      if (!authorized) {
        final String login = '${adminMount.path}/login';
        return Response(
          302,
          headers: Headers(<String, String>{
            'location': '$login?from=${Uri.encodeQueryComponent(path)}',
            'cache-control': 'no-store',
          }),
          body: const Stream<List<int>>.empty(),
        );
      }
      final File indexFile = File(p.join(root, 'index.html'));
      if (!indexFile.existsSync()) {
        return Response(
          dvAdminHiddenStatus,
          headers: Headers(dvAdminHiddenHeaders),
          body: const Stream<List<int>>.empty(),
        );
      }
      return Response(
        200,
        headers: Headers(<String, String>{
          'content-type': 'text/html; charset=utf-8',
          'cache-control': 'no-store',
        }),
        body: Stream<List<int>>.value(indexFile.readAsBytesSync()),
      );
    }

    // Static assets (main.dart.js, flutter_bootstrap.js, canvaskit, etc.)
    if (!authorized) {
      return Response(
        dvAdminHiddenStatus,
        headers: Headers(dvAdminHiddenHeaders),
        body: const Stream<List<int>>.empty(),
      );
    }

    final String rest = path.substring(mount.path.length);
    final String relative = rest.startsWith('/') ? rest.substring(1) : rest;
    final File asset = File(p.join(root, relative));
    if (!asset.existsSync() || !p.isWithin(root, asset.path)) {
      return Response(
        dvAdminHiddenStatus,
        headers: Headers(dvAdminHiddenHeaders),
        body: const Stream<List<int>>.empty(),
      );
    }
    return Response(
      200,
      headers: Headers(<String, String>{
        'content-type': _mimeType(asset.path),
        'cache-control': 'no-store',
      }),
      body: Stream<List<int>>.value(asset.readAsBytesSync()),
    );
  }

  static String _mimeType(String path) {
    final String ext = p.extension(path).toLowerCase();
    return switch (ext) {
      '.html' => 'text/html; charset=utf-8',
      '.js' => 'application/javascript; charset=utf-8',
      '.css' => 'text/css; charset=utf-8',
      '.json' => 'application/json',
      '.wasm' => 'application/wasm',
      '.png' => 'image/png',
      '.svg' => 'image/svg+xml',
      '.woff2' => 'font/woff2',
      '.ttf' => 'font/ttf',
      _ => 'application/octet-stream',
    };
  }
}
