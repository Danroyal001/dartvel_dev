/// The admin dashboard, served at its mount by whatever serves the backend.
///
/// `dartvel preview` served the dashboard and the web-server binary, which is
/// the deployment, did not: the rules lived in the CLI and the generated
/// backend cannot depend on the CLI. They live here so both servers answer
/// the same request the same way, rather than as two copies that drift.
///
/// Three answers, and the difference between two of them is the whole
/// security posture of the feature. A request refused because nobody signed
/// in has to be indistinguishable from a request for a route that does not
/// exist. An admin answering 401 where the rest of the site answers
/// something else is an oracle: it tells whoever is scanning that the host is
/// a Dartvel application, that it has a studio, and where.
library;

import 'dart:io';
import 'dart:typed_data';

import '../../dartvel.dart' show DVAuthAuthorization;
import '../auth/auth.dart' show DVAccountDirectory;
import '../auth/session_authentication.dart';
import '../database/adapter.dart';
import '../http/wintercg.dart';
import '../middleware/middleware.dart' show dvWithRequestTenant;
import 'studio_access.dart';
import 'studio_api.dart';

/// Everything below the mount belongs to the admin.
class DVAdminMount {
  const DVAdminMount({
    required this.path,
    required this.enabled,
    required this.requiresAuth,
  });

  /// The mount, with no trailing slash.
  final String path;

  /// Whether the backend serves it at all.
  final bool enabled;

  /// Whether a request has to be authenticated before it sees anything.
  ///
  /// Not a setting of its own. An admin reachable without a sign-in on a
  /// deployed application is the whole of the risk here, and making that
  /// optional is offering somebody a way to get it wrong on the one
  /// question where being wrong is expensive.
  final bool requiresAuth;

  /// Whether [route] is the admin's rather than the application's.
  bool owns(String route) => route == path || route.startsWith('$path/');
}

/// What to do with one request.
enum DVAdminRequest {
  /// Not the admin's. The application answers it.
  notTheAdmin,

  /// The admin's, and this caller may have it.
  serve,

  /// The admin's, and this caller may not know that. Answered exactly as a
  /// route the application does not serve is answered.
  hidden,
}

/// The status a hidden request is answered with, by a server whose unknown
/// routes answer 404.
///
/// A number rather than a convention, because two people implementing
/// "hidden" independently is how one of them becomes a 403.
const int dvAdminHiddenStatus = 404;

/// The headers a hidden request is answered with.
///
/// Nothing that names the admin. A `WWW-Authenticate` here, or a body that
/// mentions a studio, gives away in one response everything the status code
/// was chosen to withhold.
const Map<String, String> dvAdminHiddenHeaders = <String, String>{
  'content-type': 'text/plain; charset=utf-8',
};

/// What the backend should do with [path].
///
/// [authenticated] is the caller's state as the application's own auth
/// decided it -- this does not authenticate anybody, it decides what an
/// already-known answer means for this route.
DVAdminRequest dvAdminFor(
  String path,
  DVAdminMount mount, {
  required bool authenticated,
}) {
  // The mount, not the default path. A project that moved its admin
  // somewhere private must not lose the check by doing so.
  if (!mount.owns(path)) return DVAdminRequest.notTheAdmin;
  if (!mount.enabled) return DVAdminRequest.hidden;
  if (mount.requiresAuth && !authenticated) return DVAdminRequest.hidden;
  return DVAdminRequest.serve;
}

/// One file of the dashboard, ready to send.
class DVAdminAsset {
  const DVAdminAsset(this.bytes, this.contentType);

  final Uint8List bytes;
  final String contentType;

  /// The headers it goes out with.
  ///
  /// Never stored by a shared cache: a dashboard kept by a proxy after one
  /// signed-in request is served to the next person who asks, signed in or
  /// not.
  Map<String, String> get headers => <String, String>{
        'content-type': contentType,
        'cache-control': 'no-store',
      };
}

/// The file under [root] that [path], a request path under [mount], names.
///
/// The mount itself is `index.html`, and a path under it that is no file is
/// the shell too: the admin is one application with its own routes. Null
/// when the path tries to leave [root] or there is no shell to fall back to.
DVAdminAsset? dvAdminAsset(String root, DVAdminMount mount, String path) {
  final String rest = path.substring(mount.path.length);
  final String relative =
      rest.isEmpty || rest == '/' ? 'index.html' : rest.substring(1);
  // Decoded before it is checked, so %2e%2e is the same two dots here as it
  // is to any proxy in front of this. An invalid escape is not a filename.
  final String decoded;
  try {
    decoded = Uri.decodeComponent(relative).replaceAll(r'\', '/');
  } on ArgumentError {
    return null;
  }
  final List<String> segments = <String>[];
  for (final String segment in decoded.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    // Refused rather than resolved. A dot-dot that stays inside the root is
    // still a request nobody's dashboard makes.
    if (segment == '..' || segment.contains(':')) return null;
    segments.add(segment);
  }
  if (decoded.startsWith('/')) return null;
  final String separator = Platform.pathSeparator;
  final File asset = File(<String>[root, ...segments].join(separator));
  if (segments.isNotEmpty && asset.existsSync()) {
    return DVAdminAsset(
        asset.readAsBytesSync(), dvAdminContentType(segments.last));
  }
  final File shell = File('$root${separator}index.html');
  if (!shell.existsSync()) return null;
  return DVAdminAsset(shell.readAsBytesSync(), 'text/html; charset=utf-8');
}

/// The content type for a file the admin serves.
///
/// Serving admin.js as text/plain leaves a blank page and a console error
/// about a MIME type, which reads as a broken admin rather than a missing
/// line here.
String dvAdminContentType(String relative) {
  final String name = relative.toLowerCase();
  if (name.endsWith('.html')) return 'text/html; charset=utf-8';
  if (name.endsWith('.js') || name.endsWith('.mjs')) {
    return 'text/javascript; charset=utf-8';
  }
  if (name.endsWith('.css')) return 'text/css; charset=utf-8';
  if (name.endsWith('.json')) return 'application/json; charset=utf-8';
  if (name.endsWith('.wasm')) return 'application/wasm';
  if (name.endsWith('.png')) return 'image/png';
  if (name.endsWith('.svg')) return 'image/svg+xml';
  if (name.endsWith('.woff2')) return 'font/woff2';
  if (name.endsWith('.ttf')) return 'font/ttf';
  return 'application/octet-stream';
}

/// Whether [request] comes from somebody allowed to open Studio.
///
/// Two questions, and a session answers only the first. The request has to
/// carry a live session of the application's own -- the same stage the
/// generated backend authenticates every route with, on the tenant the
/// request names; a revoked, expired or forged one is nobody, and so is an
/// API key, because the dashboard is opened by a person. Then
/// `DV.Auth.authorization` has to allow that person [dvStudioAccessAction],
/// which it does for nobody unless a grant or the application's own policy
/// says so. Signing up to the application is not signing up to its admin.
Future<bool> dvAdminAuthorized(Request request) =>
    dvWithRequestTenant(request, () async {
      final DVSessionAuthenticationResult result =
          await DVSessionAuthentication.authenticateRequest(
        authorization: request.headers.get('authorization'),
        cookie: request.headers.get('cookie'),
      );
      final DVSessionPrincipal? principal = result.principal;
      if (result.refused || principal == null) return false;
      const DVAuthAuthorization authorization = DVAuthAuthorization();
      // The application's user where its policy is written against that
      // type, the principal otherwise: the choice every route makes.
      final Object? user = principal.user;
      final Object caller =
          user != null && authorization.acceptsCaller(dvStudioAccessAction, user)
              ? user
              : principal;
      return DVSessionPrincipal.actingAs(
        principal,
        () => authorization.canAction(caller, dvStudioAccessAction),
      );
    });

/// The dashboard in [root], served at [mount] by the generated backend.
class DVAdminServer {
  DVAdminServer({
    required this.mount,
    required this.root,
    Future<bool> Function(Request request)? authenticated,
    List<DVStudioModelSpec> models = const <DVStudioModelSpec>[],
    DVDatabaseAdapter? database,
    Future<String?> Function(Request request)? caller,
    DVAccountDirectory? accounts,
  })  : _authenticated = authenticated ?? dvAdminAuthorized,
        api = DVStudioApi(
          models: models,
          database: database,
          caller: caller,
          accounts: accounts,
        );

  final DVAdminMount mount;

  /// The directory the dashboard's files are in. Never under the web root a
  /// server serves every file of to anybody.
  final String root;

  final Future<bool> Function(Request request) _authenticated;

  /// Studio's data, under `<mount>/api/`: a model's records, the page
  /// builder's documents and the grants, for exactly the callers the
  /// dashboard's files are served to.
  final DVStudioApi api;

  /// The dashboard's answer to [request], or null for the application to
  /// answer.
  ///
  /// Null for a request that is not the admin's, and null for one the
  /// caller may not see: the application then answers it exactly as it
  /// answers any path it does not serve, which is the only way to be sure
  /// the two cannot be told apart. A server whose unknown routes render the
  /// site's shell would turn a 404 of this class's own into the oracle it
  /// exists to avoid.
  Future<Response?> respond(Request request) async {
    final String path = request.url.path.isEmpty ? '/' : request.url.path;
    if (!mount.owns(path)) return null;
    // Only asked on the mount, so no other route pays for a session lookup.
    final DVAdminRequest decision = dvAdminFor(
      path,
      mount,
      authenticated: mount.requiresAuth && await _authenticated(request),
    );
    if (decision != DVAdminRequest.serve) return null;
    final String apiPrefix = '${mount.path}/api/';
    if (path.startsWith(apiPrefix)) {
      // On the request's tenant, as every route of the application is, so a
      // tenant-scoped model shows this tenant's records and nobody else's.
      return dvWithRequestTenant(
          request, () => api.respond(request, path.substring(apiPrefix.length)));
    }
    if (request.method != 'GET' && request.method != 'HEAD') return null;
    final DVAdminAsset? asset = dvAdminAsset(root, mount, path);
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
