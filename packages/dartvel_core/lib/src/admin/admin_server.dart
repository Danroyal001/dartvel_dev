/// Studio at its mount, answered by whatever serves the backend: its pages,
/// which are routes of the application, its API, and its code.
///
/// `dartvel preview` served Studio and the web-server binary, which is
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

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../dartvel.dart' show DVAuthAuthorization, DVAuthEndpoints;
import '../auth/auth.dart' show DVAccountDirectory;
import '../auth/first_run_owner.dart';
import '../auth/session_authentication.dart';
import '../auth/sessions.dart' show DVSessionCookie;
import '../database/adapter.dart';
import '../http/wintercg.dart';
import '../middleware/middleware.dart' show dvWithRequestTenant;
import '../web/route_page.dart' show DVRoutePage, dvRenderRoutePage;
import 'studio_access.dart';
import 'studio_api.dart';
import 'studio_dev_grant.dart';
import 'studio_document.dart';

/// One of the application's own auth endpoints, as the mount answers it.
typedef DVAdminAuthEndpoint = Future<Response> Function(Request);

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

/// The content type of one of Studio's parts, or anything else Studio serves.
///
/// A script served as text/plain leaves a blank page and a console error
/// about a MIME type, which reads as a broken Studio rather than a missing
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

/// The queues the project graph in [root] names: every `@DVJob`'s queue.
///
/// The build writes the graph beside Studio, and it is the one place a
/// server knows its queue names from. Read on each request, so a graph that
/// is missing or unreadable lists no queue of its own rather than failing.
List<String> dvAdminGraphQueues(String root) {
  final File graph = File('$root${Platform.pathSeparator}graph.json');
  try {
    final Object? decoded = jsonDecode(graph.readAsStringSync());
    final Object? jobs = decoded is Map ? decoded['jobs'] : null;
    return <String>{
      if (jobs is List)
        for (final Object? job in jobs)
          if (job is Map &&
              job['queue'] is String &&
              '${job['queue']}'.isNotEmpty)
            '${job['queue']}',
    }.toList();
  } on Object {
    return const <String>[];
  }
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
Future<bool> dvAdminAuthorized(Request request) => dvWithRequestTenant(
  request,
  () async {
    final DVSessionAuthenticationResult result =
        await DVSessionAuthentication.authenticateRequest(
          plainLocal: DVSessionCookie.plainLocal(
            request.url,
            forwardedProto: request.headers.get('x-forwarded-proto'),
            host: request.headers.get('host'),
          ),
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
  },
);

/// The robots meta every Studio page carries: an operator's screen belongs
/// in no search index, and nothing on it is a link to follow.
const String dvStudioRobots = 'noindex, nofollow';

/// Studio, at [mount], answered by the generated backend.
///
/// Studio is not a second application with files of its own. Its screens are
/// routes of the application -- `<mount>` and `<mount>/login` -- and a
/// request for one is answered with the application's own shell, rendered
/// for that route by [dvRenderRoutePage] like every other page of it. Studio
/// itself is the application's deferred Studio library: its parts are
/// [studioParts], held in memory and handed out by exact path to a caller the
/// Studio grant admits, and to nobody else. Nothing under the mount is ever
/// a file.
class DVAdminServer {
  DVAdminServer({
    required this.mount,
    required this.root,
    Future<bool> Function(Request request)? authenticated,
    List<DVStudioModelSpec> models = const <DVStudioModelSpec>[],
    DVDatabaseAdapter? database,
    Future<String?> Function(Request request)? caller,
    DVAccountDirectory? accounts,
    List<String>? queues,
    this.apiBasePath = '/api',
    this.devGrant,
    String? sourceRoot,
    String? structureRoot,
    this.webRoot,
    this.title = 'Studio',
    Map<String, Uint8List> studioParts = const <String, Uint8List>{},
  }) : _authenticated = authenticated ?? devGrant?.check ?? dvAdminAuthorized,
       _database = database,
       this.models = models,
       studioParts = Map<String, Uint8List>.unmodifiable(studioParts),
       api = DVStudioApi(
         models: models,
         database: database,
         caller: caller,
         accounts: accounts,
         queues: queues == null ? () => dvAdminGraphQueues(root) : () => queues,
         root: root,
         sourceRoot: sourceRoot,
         structureRoot: structureRoot,
       );

  final DVAdminMount mount;

  /// Where the build put Studio's data: the project graph and each page's
  /// captured structure, which Studio reads through its API. Never served
  /// as files, and never under the web root a server serves every file of
  /// to anybody.
  final String root;

  /// The application's web root, whose `index.html` is the shell every page
  /// is rendered from -- Studio's included. Null renders no Studio page.
  final String? webRoot;

  /// Every data model the backend compiled, which is what Studio's documents
  /// name on the Data screen and what its API answers `api/models` from.
  final List<DVStudioModelSpec> models;

  /// The title of Studio's pages: `Studio · <application>`.
  final String title;

  /// Studio's code: the parts of the application's deferred Studio library,
  /// by path from the site root (`main.dart.js_7.part.js`). Served from
  /// memory to a caller who may open Studio, and answered as nothing to
  /// anybody else.
  final Map<String, Uint8List> studioParts;

  final Future<bool> Function(Request request) _authenticated;

  /// The adapter this mount reads, for the first-run check.
  final DVDatabaseAdapter? _database;

  /// Where the application's own auth endpoints answer, which the first-run
  /// screen drives. The application's setting, not a guess: a project that
  /// moved its API would otherwise get a setup screen posting into nothing.
  final String apiBasePath;

  /// The development grant, on a development server: the mount serves the
  /// browser that opened the grant's link, and nobody else.
  final DVStudioDevGrant? devGrant;

  /// Studio's data, under `<mount>/api/`: a model's records, the page
  /// builder's documents, the project graph and the grants, for exactly the
  /// callers Studio's pages are served to.
  final DVStudioApi api;

  static const Map<String, String> _json = <String, String>{
    'content-type': 'application/json',
    'cache-control': 'no-store',
  };

  /// Whether this caller may have what the mount guards.
  Future<bool> _allowed(Request request) async =>
      !mount.requiresAuth || await _authenticated(request);

  /// Studio's page for [route]: the application's shell, rendered for it by
  /// the function every page of the application is rendered by, carrying
  /// [document] -- the screen's own document, with a heading, the rail and
  /// everything the server knows is in it -- so a printer, a crawler, a
  /// reader whose browser will not run the app and the browser's own find all
  /// have something to read. Null for a page that carries nothing of its own,
  /// which the application then answers.
  Response? _page(
    Request request,
    String route, {
    String referrer = 'same-origin',
    DVStudioDocument? document,
  }) {
    final String? web = webRoot;
    if (web == null) return null;
    final File shell = File('$web${Platform.pathSeparator}index.html');
    final String html;
    try {
      html = shell.readAsStringSync();
    } on FileSystemException {
      return null;
    }
    final String page = dvRenderRoutePage(
      html,
      DVRoutePage(
        route: route,
        // The name the application gave Studio, not the screen's: a tab is
        // the window somebody has open, and the screen it is showing is named
        // by the heading in the document and by the address it is at.
        title: title,
        robots: dvStudioRobots,
        html: document?.html,
        text: document?.text ?? const <String>[],
      ),
    );
    return Response(
      200,
      headers: Headers(<String, String>{
        'content-type': 'text/html; charset=utf-8',
        // One person's view of their own Studio, never a shared cache's.
        'cache-control': 'no-store',
        // An operator's screen is not something any other site may frame.
        'x-frame-options': 'DENY',
        'referrer-policy': referrer,
      }),
      body: request.method == 'HEAD'
          ? const Stream<List<int>>.empty()
          : Stream<List<int>>.value(utf8.encode(page)),
    );
  }

  /// One of Studio's parts, for a caller already admitted.
  Response _part(Request request, String name, Uint8List bytes) => Response(
    200,
    headers: Headers(<String, String>{
      'content-type': dvAdminContentType(name),
      // Protected code: never kept by a proxy, which would hand it to
      // the next person who asked.
      'cache-control': 'no-store',
    }),
    body: request.method == 'HEAD'
        ? const Stream<List<int>>.empty()
        : Stream<List<int>>.value(bytes),
  );

  /// What the Studio app needs, signed out, to sign somebody in; null for
  /// everything else.
  Future<Response?> _signIn(
    Request request,
    String path,
    bool readable,
    String login,
  ) async {
    final String api = '${mount.path}/api/';
    if (request.method == 'POST') {
      final Response? auth = await _authPost(
        request,
        path,
        <String, DVAdminAuthEndpoint>{
          '${api}auth/sign-in': DVAuthEndpoints.signIn,
          '${api}auth/second-factor': DVAuthEndpoints.secondFactor,
          // Signing out revokes the session on the server and clears the
          // cookie: a browser that merely forgot its token would leave a live
          // one behind for whoever holds a copy.
          '${api}auth/sign-out': DVAuthEndpoints.signOut,
        },
      );
      if (auth != null) return auth;
    }
    if (!readable) return null;
    if (path == '${api}access') {
      final bool granted = await _authenticated(request);
      return Response(
        200,
        headers: Headers(_json),
        body: Stream<List<int>>.value(
          utf8.encode(jsonEncode(<String, Object?>{'granted': granted})),
        ),
      );
    }
    // The sign-in route, a page of the application like any other.
    if (path == login || path == '$login/') return _page(request, login);
    return null;
  }

  /// The setup, while the first owner still has their printed password.
  ///
  /// The same shape as [_signIn] and for the same reason: the setup is a
  /// route of the application, at `<mount>/setup`, rendered from its shell
  /// like every page, and what the server owes it besides is the four auth
  /// endpoints the page drives -- the application's own, answered at the
  /// mount, so the rate limit, the CSRF check and the session rotation are
  /// the ones already written rather than a second copy of each.
  ///
  /// Every other page on the mount is sent to the setup, and everything else
  /// -- the API, the graph, a file name -- is nothing at all: the graph and
  /// the records are not handed to somebody who has changed nothing yet.
  Future<Response?> _setup(Request request, String path, bool readable) async {
    final String api = '${mount.path}/api/';
    final String setup = '${mount.path}/setup';
    if (request.method == 'POST') {
      return _authPost(request, path, <String, DVAdminAuthEndpoint>{
        '${api}auth/sign-in': DVAuthEndpoints.signIn,
        '${api}auth/account/password': DVAuthEndpoints.changePassword,
        '${api}auth/factors/totp': DVAuthEndpoints.beginTotp,
        '${api}auth/factors/totp/confirm': DVAuthEndpoints.confirmTotp,
      });
    }
    if (!readable) return null;
    if (path.startsWith(api) || path == '${mount.path}/api') return null;
    if (path.split('/').last.contains('.')) return null;
    if (path == setup || path == '$setup/') {
      return _page(
        request,
        setup,
        referrer: 'no-referrer',
        document: _noProjectDocument(dvStudioSetupScreen, setup),
      );
    }
    return Response(
      302,
      headers: Headers(<String, String>{
        'location': setup,
        'cache-control': 'no-store',
      }),
      body: const Stream<List<int>>.empty(),
    );
  }

  /// One of [endpoints] under the mount's own API, with the CSRF header the
  /// browser transport sends and a cross-site form cannot. Null when [path]
  /// is none of them, so a caller can go on to decide.
  Future<Response?> _authPost(
    Request request,
    String path,
    Map<String, DVAdminAuthEndpoint> endpoints,
  ) async {
    final DVAdminAuthEndpoint? endpoint = endpoints[path];
    if (endpoint == null) return null;
    final String token = request.headers.get('x-dartvel-csrf-token') ?? '';
    if (token.length < 16) {
      return Response(
        403,
        headers: Headers(_json),
        body: Stream<List<int>>.value(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'error': 'csrf',
              'message': 'Missing CSRF header.',
            }),
          ),
        ),
      );
    }
    return endpoint(request);
  }

  /// Studio's answer to [request], or null for the application to answer.
  ///
  /// Null for a request that is not Studio's, and null for one the caller
  /// may not see: the application then answers it exactly as it answers any
  /// path it does not serve, which is the only way to be sure the two cannot
  /// be told apart.
  Future<Response?> respond(Request request) async {
    final String path = request.url.path.isEmpty ? '/' : request.url.path;
    final bool readable = request.method == 'GET' || request.method == 'HEAD';
    if (!mount.owns(path)) {
      // Studio's code, which the application's Studio routes load from the
      // site root like any deferred part. By exact path, from memory, and
      // only when the caller may open Studio -- asked only for one of its
      // parts, so no other request pays for a session lookup.
      final Uint8List? part = path.length > 1
          ? studioParts[path.substring(1)]
          : null;
      if (part == null || !readable || !mount.enabled) return null;
      if (!await _allowed(request)) return null;
      return _part(request, path.substring(1), part);
    }
    final Response? claimed = devGrant?.claim(request, mount);
    if (claimed != null) return claimed;
    // An application still on the password its first run printed is one
    // anybody who saw that console can open. Until the owner has replaced it
    // and turned on a second factor, every page on the mount is sent to
    // <mount>/setup, and nothing else on the mount is served at all.
    //
    // Before the sign-in check, because signing in is what the setup is for:
    // the owner has an address and a password and no session, so answering
    // them the way this mount answers a stranger would make the setup
    // unreachable by the only person who needs it. The setup is a route of
    // the application, rendered from its shell; it names nobody and carries
    // no data, and the only credential that opens anything behind it is 32
    // characters of secure random. It stops being sent the moment the setup
    // is done.
    if (mount.enabled &&
        await DVFirstRunOwner.setupPending(database: _database)) {
      return _setup(
        request,
        path,
        request.method == 'GET' || request.method == 'HEAD',
      );
    }
    // Studio's sign-in is a route of the application, at <mount>/login. What
    // the server does for somebody signed out is only what that page needs:
    // the page itself, the application's own sign-in and second factor
    // answered at the mount, and whether this caller may open Studio.
    // Everything else stays behind the grant.
    final String login = '${mount.path}/login';
    final String apiPrefix = '${mount.path}/api/';
    final bool isApi =
        path.startsWith(apiPrefix) || path == '${mount.path}/api';
    if (devGrant == null && mount.enabled && mount.requiresAuth) {
      final Response? signIn = await _signIn(request, path, readable, login);
      if (signIn != null) return signIn;
    }
    // Only asked on the mount, so no other route pays for a session lookup.
    final DVAdminRequest decision = dvAdminFor(
      path,
      mount,
      authenticated: mount.requiresAuth && await _authenticated(request),
    );
    if (decision == DVAdminRequest.hidden &&
        devGrant == null &&
        mount.enabled &&
        mount.requiresAuth &&
        readable &&
        !isApi &&
        path != '${mount.path}/graph.json') {
      // Any page under the mount, for a caller without a Studio grant, is
      // sent to the sign-in with where they were going. The API and the
      // graph stay hidden (null, answered as a path nothing serves).
      final String from =
          '${request.url.path}${request.url.hasQuery ? '?${request.url.query}' : ''}${request.url.hasFragment ? '#${request.url.fragment}' : ''}';
      return Response(
        302,
        headers: Headers(<String, String>{
          'location': '$login?from=${Uri.encodeQueryComponent(from)}',
          'cache-control': 'no-store',
        }),
        body: const Stream<List<int>>.empty(),
      );
    }
    if (decision != DVAdminRequest.serve) return null;
    if (path.startsWith(apiPrefix)) {
      // On the request's tenant, as every route of the application is, so a
      // tenant-scoped model shows this tenant's records and nobody else's.
      return dvWithRequestTenant(
        request,
        () => api.respond(request, path.substring(apiPrefix.length)),
      );
    }
    if (!readable) return null;
    // Studio's routes. Every screen has its own URL under the mount and
    // carries its own document, so a link to one can be printed, bookmarked
    // and shared; the sign-in and the setup are pages a caller who may not
    // see the rest still gets, and they carry no project. Both answer
    // whenever they are asked for, not only while a first run is waiting.
    final String setup = '${mount.path}/setup';
    if (path == login ||
        path == '$login/' ||
        path == setup ||
        path == '$setup/') {
      return _page(
        request,
        path,
        document: _noProjectDocument(
          path.startsWith(setup) ? dvStudioSetupScreen : dvStudioSignInScreen,
          path.startsWith(setup) ? setup : login,
        ),
      );
    }
    final DVStudioTarget? target = dvStudioTargetFor(path, mount: mount.path);
    if (target == null) return null;
    return _page(request, path, document: await _documentFor(target));
  }

  /// The document for [target]: the project graph the build wrote, and the
  /// models the backend compiled.
  ///
  /// Read on each request rather than kept: a graph is a build's output, and a
  /// server that started before the build finished would otherwise describe
  /// the project as it was when it started.
  Future<DVStudioDocument> _documentFor(DVStudioTarget target) async =>
      dvStudioDocumentFor(
        target,
        mount: mount.path,
        data: await _projectData(),
        models: models,
      );

  /// What the project graph names, plus the pages stored beside it.
  ///
  /// A server that started before a build finished would otherwise describe
  /// the project as it was when it started, so the graph is read on each
  /// request rather than kept.
  Future<DVStudioProjectData> _projectData() async {
    final DVStudioProjectData graph = DVStudioProjectData.fromGraph(root);
    return DVStudioProjectData(
      compiled: graph.compiled,
      pages: await api.sitePages(compiled: graph.compiled),
      models: models,
      functions: graph.functions,
      jobs: graph.jobs,
      queues: graph.queues,
      modules: graph.modules,
    );
  }

  /// The document the sign-in and the setup are served with: what Studio is,
  /// and nothing about what is behind it.
  ///
  /// No rail, no project, no links to a screen. Both are pages a visitor who
  /// has not signed in reaches, and a document that listed what is behind
  /// them would describe the project to the one person who is not allowed to
  /// see it.
  static DVStudioDocument _noProjectDocument(
    DVStudioScreenSpec screen,
    String at,
  ) => dvStudioDocumentFor(
    DVStudioTarget(screen: screen),
    mount: at,
    data: const DVStudioProjectData(),
    navigation: false,
  );
}
