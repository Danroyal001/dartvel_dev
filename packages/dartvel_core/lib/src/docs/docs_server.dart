/// The documentation site, served by the backend at its mount.
///
/// The same rules Studio's own files are served by, because with
/// `access: studio` the documentation is Studio's: the project's models,
/// functions, routes and policies, which is exactly what the Studio grant
/// exists to keep from a stranger.
///
/// - A person without the grant who navigates to a page of the site is sent
///   to Studio's sign-in, and a script asking for one of its files -- the
///   document, the graph, the compiled app -- gets what a path nobody serves
///   gets: the application's own answer, so the two cannot be told apart.
/// - With the grant, or with `access: public`, the files are served, and a
///   path under the mount that is no file is the site's shell: the site is
///   one application with its own routes.
library;

import '../admin/admin_server.dart'
    show DVAdminAsset, DVAdminMount, dvAdminAsset, dvAdminAuthorized;
import '../http/wintercg.dart';
import 'docs_mount.dart';

/// Answers the requests under [DVDocsMount.path].
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
  }) : _authenticated = authenticated ?? dvAdminAuthorized;

  final DVDocsMount mount;

  /// The directory holding the compiled site, `docs.json` and `graph.json`.
  final String root;

  /// Studio's mount: its sign-in is where a signed-out reader is sent.
  final DVAdminMount adminMount;

  /// Whether a request carries the Studio grant; Studio's own check unless a
  /// test says otherwise.
  final Future<bool> Function(Request request) _authenticated;

  /// Whether [path] is a page a person navigates to, rather than a file of
  /// the site.
  bool _isPage(String path) {
    if (path == mount.path || path == '${mount.path}/') return true;
    return !path.split('/').last.contains('.');
  }

  /// The answer to [request], or null for the application to answer.
  ///
  /// Null for a request that is not the site's, for a mount that is off, and
  /// for a file the caller may not see: the application then answers it
  /// exactly as it answers any path it does not serve.
  Future<Response?> respond(Request request) async {
    final String path = request.url.path.isEmpty ? '/' : request.url.path;
    if (!mount.enabled || !mount.owns(path)) return null;
    if (request.method != 'GET' && request.method != 'HEAD') return null;

    final bool granted = !mount.requiresAuth || await _authenticated(request);
    if (!granted) {
      if (!_isPage(path)) return null;
      final String from =
          '$path${request.url.hasQuery ? '?${request.url.query}' : ''}';
      return Response(
        302,
        headers: Headers(<String, String>{
          'location':
              '${adminMount.path}/login?from=${Uri.encodeQueryComponent(from)}',
          'cache-control': 'no-store',
        }),
        body: const Stream<List<int>>.empty(),
      );
    }

    // Resolved exactly as Studio's files are: decoded before it is checked,
    // never outside [root], and the shell for a path that is no file.
    final DVAdminAsset? asset = dvAdminAsset(
      root,
      DVAdminMount(path: mount.path, enabled: true, requiresAuth: false),
      path,
    );
    if (asset == null) return null;
    return Response(
      200,
      headers: Headers(asset.headers),
      body: request.method == 'HEAD'
          ? const Stream<List<int>>.empty()
          : Stream<List<int>>.value(asset.bytes),
    );
  }
}
