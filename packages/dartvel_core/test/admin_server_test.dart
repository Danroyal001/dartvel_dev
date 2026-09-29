// Studio, at its mount, as pages of the application.
//
// Studio used to be a second Flutter application, built on its own and
// served as files under the mount. Serving files by path is how
// /__studio/index.html reached a signed-out visitor with the whole Studio UI.
// Now Studio's screens are routes of the application: the mount serves no
// file at all. A Studio page is the application's own shell rendered by
// dvRenderRoutePage, like every other page, and only to a caller the Studio
// grant admits -- except the sign-in, which is a page for anybody. Studio's
// code is the application's deferred library, whose parts the server holds
// in memory and hands to a granted session only.
//
// A person arriving signed out at a Studio page is sent to Studio's own
// sign-in at <mount>/login. For Studio's code and its API the answer to a
// caller who may not see the admin is "nothing here": null, so the request
// carries on to whatever the application answers for a path it does not
// serve.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

late Directory _root;
late Directory _web;

Request _get(
  String path, {
  Map<String, String>? headers,
  String method = 'GET',
}) => Request(
  method: method,
  url: Uri.parse('http://localhost:8080$path'),
  headers: Headers(headers),
  bodyStream: const Stream<List<int>>.empty(),
);

Future<String> _body(Response response) async =>
    utf8.decode(await response.body!.bytes());

const DVAdminMount _open = DVAdminMount(
  path: '/__studio',
  enabled: true,
  requiresAuth: false,
);
const DVAdminMount _guarded = DVAdminMount(
  path: '/__studio',
  enabled: true,
  requiresAuth: true,
);

/// The application's shell, which every page of it -- Studio's included --
/// is rendered from.
const String _shell =
    '<!DOCTYPE html>\n<html>\n<head>\n<meta charset="UTF-8">\n'
    '<title>Shop</title>\n</head>\n<body>\n'
    '<script src="flutter_bootstrap.js" async></script>\n</body>\n</html>\n';

/// Studio's code: one part of the application's Studio library.
final Map<String, Uint8List> _parts = <String, Uint8List>{
  'main.dart.js_7.part.js': Uint8List.fromList(
    utf8.encode('/* Studio screens */'),
  ),
};

DVAdminServer _server(
  DVAdminMount mount, {
  Map<String, Uint8List>? parts,
  bool shell = true,
}) => DVAdminServer(
  mount: mount,
  root: _root.path,
  webRoot: shell ? _web.path : null,
  title: 'Studio · Shop',
  studioParts: parts ?? _parts,
);

/// Not served Studio: either nothing, for the application to answer, or
/// sent to Studio's own sign-in.
final Matcher _refused = predicate<Response?>(
  (Response? r) =>
      r == null ||
      (r.status == 302 &&
          (r.headers.get('location') ?? '').startsWith('/__studio/login')),
  'refused: nothing, or a redirect to /__studio/login',
);

/// A Studio page: the application's shell, rendered for [route] by the same
/// function every page is, never a document from the admin root.
Future<void> _expectStudioPage(Response? response, {String? reason}) async {
  expect(response?.status, 200, reason: reason);
  expect(
    response!.headers.get('content-type'),
    'text/html; charset=utf-8',
    reason: reason,
  );
  expect(response.headers.get('cache-control'), 'no-store', reason: reason);
  expect(response.headers.get('x-frame-options'), 'DENY', reason: reason);
  final String html = await _body(response);
  expect(html, contains('<title>Studio · Shop</title>'), reason: reason);
  expect(
    html,
    contains('<meta name="robots" content="noindex, nofollow">'),
    reason: reason,
  );
  expect(html, contains('flutter_bootstrap.js'), reason: reason);
  expect(html, isNot(contains('OLD STUDIO APP')), reason: reason);
}

void main() {
  setUp(() {
    final Directory parent = Directory.systemTemp.createTempSync(
      'dartvel_admin_server_',
    );
    // The admin root, with a secret beside it that traversal must not reach.
    File('${parent.path}/secret.txt').writeAsStringSync('database password');
    _root = Directory('${parent.path}/admin')..createSync();
    // What an older build left there: a separately built Studio app. None
    // of it is ever served again.
    File('${_root.path}/index.html')
        .writeAsStringSync('<html><title>OLD STUDIO APP</title></html>');
    File('${_root.path}/admin.js').writeAsStringSync('// OLD STUDIO APP');
    File('${_root.path}/main.dart.js_2.part.js')
        .writeAsStringSync('/* OLD STUDIO APP chunk */');
    File('${_root.path}/graph.json').writeAsStringSync('{"models":[]}');
    _web = Directory('${parent.path}/web')..createSync();
    File('${_web.path}/index.html').writeAsStringSync(_shell);
    addTearDown(() => parent.deleteSync(recursive: true));
  });

  tearDown(() {
    DVSessionAuthentication.uninstall();
    DVAuthAuthorization.reset();
  });

  group('a caller who may see the admin', () {
    test('gets Studio at the mount as a page of the application, with and '
        'without the slash', () async {
      final DVAdminServer server = _server(_open);
      for (final String path in <String>['/__studio', '/__studio/']) {
        await _expectStudioPage(await server.respond(_get(path)), reason: path);
      }
    });

    test('the mount serves no file, whatever is on disk under it', () async {
      final DVAdminServer server = _server(_open);
      for (final String path in <String>[
        '/__studio/index.html',
        '/__studio/admin.js',
        '/__studio/graph.json',
        '/__studio/main.dart.js_2.part.js',
        '/__studio/models',
      ]) {
        final Response? response = await server.respond(_get(path));
        if (response != null) {
          expect(
            await _body(response),
            isNot(contains('OLD STUDIO APP')),
            reason: path,
          );
          expect(
            await _body(response),
            isNot(contains('"models"')),
            reason: path,
          );
        }
        // The application answers it, as it answers any path it does not
        // serve.
        expect(response, isNull, reason: path);
      }
    });

    test('with no application shell to render from, answers nothing', () async {
      expect(
        await _server(_open, shell: false).respond(_get('/__studio/')),
        isNull,
      );
    });

    test('cannot leave anything, however the dots are written', () async {
      final DVAdminServer server = _server(_open);
      for (final String path in <String>[
        '/__studio/%2e%2e/secret.txt',
        '/__studio/..%2fsecret.txt',
        '/__studio/%2E%2E%2Fsecret.txt',
        '/%2e%2e/secret.txt',
      ]) {
        final Response? response = await server.respond(_get(path));
        if (response != null) {
          expect(
            await _body(response),
            isNot(contains('password')),
            reason: path,
          );
        }
        expect(response, _refused, reason: path);
      }
    });
  });

  group("Studio's code", () {
    // The deferred library the application's Studio routes load. It is
    // served from memory, by exact path, to a caller the grant admits; to
    // anybody else it does not exist, exactly as a route that does not.
    test(
      'is served to a caller who may open Studio, never kept by a cache',
      () async {
        final Response? part = await _server(_open)
            .respond(_get('/main.dart.js_7.part.js'));
        expect(part?.status, 200);
        expect(
          part!.headers.get('content-type'),
          'text/javascript; charset=utf-8',
        );
        expect(part.headers.get('cache-control'), 'no-store');
        expect(await _body(part), '/* Studio screens */');
      },
    );

    test(
      'is nothing to a caller with no grant: not a redirect, not the code',
      () async {
        DVSessionAuthentication.install(sessions: DVSessions());
        final DVAdminServer server = _server(_guarded);
        for (final String method in <String>['GET', 'HEAD']) {
          expect(
            await server.respond(
              _get('/main.dart.js_7.part.js', method: method),
            ),
            isNull,
            reason: method,
          );
        }
      },
    );

    test('a path that is not one of its parts is the application\'s', () async {
      final DVAdminServer server = _server(_open);
      for (final String path in <String>[
        '/main.dart.js',
        '/main.dart.js_1.part.js',
        '/assets/main.dart.js_7.part.js',
        '/__studio/main.dart.js_7.part.js',
      ]) {
        expect(await server.respond(_get(path)), isNull, reason: path);
      }
    });

    test('a turned-off admin serves none of it', () async {
      const DVAdminMount off = DVAdminMount(
        path: '/__studio',
        enabled: false,
        requiresAuth: false,
      );
      expect(
        await _server(off).respond(_get('/main.dart.js_7.part.js')),
        isNull,
      );
    });
  });

  group('the application keeps', () {
    test('every path that is not the mount', () async {
      final DVAdminServer server = _server(_open);
      for (final String path in <String>['/', '/__studiox', '/api/health']) {
        expect(await server.respond(_get(path)), isNull, reason: path);
      }
    });

    test('the mount itself when the admin is turned off', () async {
      const DVAdminMount off = DVAdminMount(
        path: '/__studio',
        enabled: false,
        requiresAuth: false,
      );
      expect(await _server(off).respond(_get('/__studio/')), _refused);
    });
  });

  group("Studio's own sign-in", () {
    // Studio signs people in at its own mount, as wp-admin does, so it does
    // not depend on the application serving /login: an application can turn
    // its account pages off, or move them, and Studio still opens.
    test('a signed-out visit to any Studio path goes to <mount>/login, with '
        'where it was going', () async {
      DVSessionAuthentication.install(sessions: DVSessions());
      final DVAdminServer server = _server(_guarded);
      for (final String path in <String>[
        '/__studio',
        '/__studio/',
        '/__studio/index.html',
        '/__studio/index.html/',
        '/__studio/index.html#/data',
        '/__studio/anything',
        '/__studio/anything/',
        '/__studio/pages',
        '/__studio/admin.js',
        '/__studio/flutter_bootstrap.js',
      ]) {
        final Response? r = await server.respond(_get(path));
        expect(r?.status, 302, reason: path);
        expect(
          r!.headers.get('location'),
          '/__studio/login?from=${Uri.encodeQueryComponent(path)}',
          reason: path,
        );
        expect(r.headers.get('cache-control'), 'no-store', reason: path);
      }
    });

    test('follows a moved mount', () async {
      DVSessionAuthentication.install(sessions: DVSessions());
      const DVAdminMount moved = DVAdminMount(
        path: '/ops/desk',
        enabled: true,
        requiresAuth: true,
      );
      final DVAdminServer server = _server(moved);
      final Response? r = await server.respond(_get('/ops/desk/'));
      expect(r!.headers.get('location'), startsWith('/ops/desk/login?from='));
      final Response? page = await server.respond(_get('/ops/desk/login'));
      expect(page?.status, 200);
    });

    test('the sign-in is a page of the application: <mount>/login is its shell '
        'rendered for that route, to anybody', () async {
      DVSessionAuthentication.install(sessions: DVSessions());
      final DVAdminServer server = _server(_guarded);
      for (final String path in <String>[
        '/__studio/login',
        '/__studio/login/',
        '/__studio/login?from=/__studio/data',
      ]) {
        await _expectStudioPage(await server.respond(_get(path)), reason: path);
      }
    });

    test('a signed-out caller gets nothing of Studio but the sign-in page and '
        'the sign-in API', () async {
      DVSessionAuthentication.install(sessions: DVSessions());
      final DVAdminServer server = _server(_guarded);
      expect(await server.respond(_get('/__studio/graph.json')), isNull);
      expect(await server.respond(_get('/__studio/api/graph')), isNull);
      expect(await server.respond(_get('/__studio/api/grants')), isNull);
      expect(await server.respond(_get('/__studio/api/models')), isNull);
      expect(await server.respond(_get('/main.dart.js_7.part.js')), isNull);
      final Response? old = await server.respond(_get('/__studio/admin.js'));
      expect(old?.status, 302);
    });
    test('signs in through the application\'s own accounts, at the mount, '
        'with the CSRF header required', () async {
      final DVSessions sessions = DVSessions();
      DVSessionAuthentication.install(sessions: sessions);
      final LocalAuthProvider accounts = LocalAuthProvider();
      await accounts.signUp('ops@example.com', 'a-long-enough-password-1');
      DVAuthEndpoints.install(
        credentials: DVCredentialGuard(provider: accounts, refusalFloor: .zero),
      );
      addTearDown(DVAuthEndpoints.uninstall);
      final DVAdminServer server = _server(_guarded);
      Request post(
        String path,
        Map<String, Object?> body, {
        bool csrf = true,
      }) => Request(
        method: 'POST',
        url: Uri.parse('http://localhost:8080$path'),
        headers: Headers(<String, String>{
          'content-type': 'application/json',
          if (csrf) 'x-dartvel-csrf-token': 'c' * 32,
        }),
        bodyStream: Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
      );
      final Map<String, Object?> good = <String, Object?>{
        'email': 'ops@example.com',
        'password': 'a-long-enough-password-1',
      };
      final Response? noCsrf = await server.respond(
        post('/__studio/api/auth/sign-in', good, csrf: false),
      );
      expect(noCsrf?.status, 403);
      final Response? wrong = await server.respond(
        post('/__studio/api/auth/sign-in', <String, Object?>{
          'email': 'ops@example.com',
          'password': 'nope-nope-nope',
        }),
      );
      expect(wrong?.status, 400);
      final Response? ok = await server.respond(
        post('/__studio/api/auth/sign-in', good),
      );
      expect(ok?.status, 200);
      expect(ok!.headers.get('set-cookie'), contains('dv_session='));
    });

    test('<mount>/api/access says whether this caller may open Studio, and '
        'nothing else', () async {
      final DVSessions sessions = DVSessions();
      DVSessionAuthentication.install(sessions: sessions);
      final DVStudioGrants grants = DVStudioGrants(
        SqliteDVDatabaseAdapter.memory(),
      )..install();
      final DVIssuedSession issued = await sessions.create('u-operator');
      final DVAdminServer server = _server(_guarded);
      Future<Object?> access(Map<String, String> headers) async {
        final Response? r = await server.respond(
          _get('/__studio/api/access', headers: headers),
        );
        expect(r?.status, 200);
        expect(r!.headers.get('cache-control'), 'no-store');
        return jsonDecode(await _body(r));
      }

      expect(await access(const <String, String>{}), <String, Object?>{
        'granted': false,
      });
      final Map<String, String> bearer = <String, String>{
        'authorization': 'Bearer ${issued.token}',
      };
      expect(await access(bearer), <String, Object?>{'granted': false});
      await grants.grant('u-operator');
      expect(await access(bearer), <String, Object?>{'granted': true});
    });

    test('a turned-off admin has no sign-in page either', () async {
      const DVAdminMount off = DVAdminMount(
        path: '/__studio',
        enabled: false,
        requiresAuth: true,
      );
      final DVAdminServer server = _server(off);
      expect(await server.respond(_get('/__studio/login')), isNull);
      expect(await server.respond(_get('/__studio/')), isNull);
    });
  });

  group('a mount that requires a sign-in', () {
    test('answers nothing to a caller with no session', () async {
      DVSessionAuthentication.install(sessions: DVSessions());
      final DVAdminServer server = _server(_guarded);
      expect(await server.respond(_get('/__studio/')), _refused);
      expect(await server.respond(_get('/__studio/graph.json')), _refused);
    });

    test(
      'answers nothing to a session token that is not a live session',
      () async {
        DVSessionAuthentication.install(sessions: DVSessions());
        final DVAdminServer server = _server(_guarded);
        expect(
          await server.respond(
            _get(
              '/__studio/',
              headers: <String, String>{
                'authorization': 'Bearer ${DVSessions.tokenPrefix}forged',
              },
            ),
          ),
          _refused,
        );
      },
    );

    test(
      'answers nothing to a signed-in person nobody granted Studio',
      () async {
        // Signing up is open to anybody the application lets in: every
        // customer has a live session. A session alone opening the dashboard
        // hands every customer the application's models, routes and jobs.
        final DVSessions sessions = DVSessions();
        DVSessionAuthentication.install(sessions: sessions);
        DVStudioGrants(SqliteDVDatabaseAdapter.memory()).install();
        final DVIssuedSession customer = await sessions.create('u-customer');
        final DVAdminServer server = _server(_guarded);

        expect(
          await server.respond(
            _get(
              '/__studio/',
              headers: <String, String>{
                'authorization': 'Bearer ${customer.token}',
              },
            ),
          ),
          _refused,
        );
        expect(
          await server.respond(
            _get(
              '/__studio/graph.json',
              headers: <String, String>{
                'authorization': 'Bearer ${customer.token}',
              },
            ),
          ),
          _refused,
        );
      },
    );

    test(
      'answers nothing to a signed-in person when no policy is registered',
      () async {
        // Nothing installed a grant store and the application registered no
        // Studio.access policy: nobody, not everybody.
        final DVSessions sessions = DVSessions();
        DVSessionAuthentication.install(sessions: sessions);
        final DVIssuedSession issued = await sessions.create('u-operator');
        expect(
          await _server(_guarded).respond(
            _get(
              '/__studio/',
              headers: <String, String>{
                'authorization': 'Bearer ${issued.token}',
              },
            ),
          ),
          _refused,
        );
      },
    );

    test(
      'serves a person granted Studio, and stops when the grant goes',
      () async {
        final DVSessions sessions = DVSessions();
        DVSessionAuthentication.install(sessions: sessions);
        final DVStudioGrants grants = DVStudioGrants(
          SqliteDVDatabaseAdapter.memory(),
        )..install();
        final DVIssuedSession issued = await sessions.create('u-operator');
        await grants.grant('u-operator');
        final DVAdminServer server = _server(_guarded);

        final Response? bearer = await server.respond(
          _get(
            '/__studio/',
            headers: <String, String>{
              'authorization': 'Bearer ${issued.token}',
            },
          ),
        );
        expect(bearer?.status, 200);
        await _expectStudioPage(bearer);

        // And the cookie a browser carries, which is how the dashboard is
        // actually opened.
        const DVSessionCookie cookie = DVSessionCookie();
        final Response? browser = await server.respond(
          _get(
            '/__studio/',
            headers: <String, String>{
              'cookie':
                  '${cookie.cookieName(development: false)}=${issued.token}',
            },
          ),
        );
        expect(browser?.status, 200);

        // And the cookie a browser keeps when the binary is served over
        // http://localhost, which is every build run on the machine that
        // made it: Secure cannot be set there, so the name carries no
        // __Host- prefix. Studio answered the application's own page
        // instead of itself, and the developer saw their shop.
        final Response? local = await server.respond(
          _get(
            '/__studio/',
            headers: <String, String>{
              'host': 'localhost:8093',
              'cookie':
                  '${cookie.cookieName(development: true)}=${issued.token}',
            },
          ),
        );
        expect(local?.status, 200);

        // The same cookie from somewhere that is not this machine is not a
        // session: only the prefixed name counts there.
        expect(
          await server.respond(
            _get(
              '/__studio/',
              headers: <String, String>{
                'host': 'shop.example.com',
                'cookie':
                    '${cookie.cookieName(development: true)}=${issued.token}',
              },
            ),
          ),
          _refused,
        );
        // The grant is taken away: nothing again, on the same live session.
        expect(await grants.revoke('u-operator'), isTrue);
        expect(
          await server.respond(
            _get(
              '/__studio/',
              headers: <String, String>{
                'authorization': 'Bearer ${issued.token}',
              },
            ),
          ),
          _refused,
        );

        // Granted again, and the session revoked: nothing either.
        await grants.grant('u-operator');
        await sessions.revoke(issued.session.id);
        expect(
          await server.respond(
            _get(
              '/__studio/',
              headers: <String, String>{
                'authorization': 'Bearer ${issued.token}',
              },
            ),
          ),
          _refused,
        );
      },
    );

    test('a grant on one tenant opens nothing on another', () async {
      final DVStudioGrants grants = DVStudioGrants(
        SqliteDVDatabaseAdapter.memory(),
      );
      await grants.grant('u-operator', tenant: 'acme');
      expect(await grants.isGranted('u-operator', tenant: 'acme'), isTrue);
      expect(await grants.isGranted('u-operator', tenant: 'globex'), isFalse);
      expect(await grants.isGranted('u-operator'), isFalse);
      // Granting twice is one grant.
      await grants.grant('u-operator', tenant: 'acme');
      expect((await grants.list()).length, 1);
    });

    test(
      'the application\'s own Studio.access policy decides instead',
      () async {
        final DVSessions sessions = DVSessions();
        DVSessionAuthentication.install(sessions: sessions);
        DVStudioGrants(SqliteDVDatabaseAdapter.memory()).install();
        const DVAuthAuthorization().registerAction(
          dvStudioAccessAction,
          (Object? caller, Object? _) =>
              caller is DVSessionPrincipal && caller.userId == 'u-owner',
        );
        final DVAdminServer server = _server(_guarded);
        Future<Response?> as(String user) async {
          final DVIssuedSession issued = await sessions.create(user);
          return server.respond(
            _get(
              '/__studio/',
              headers: <String, String>{
                'authorization': 'Bearer ${issued.token}',
              },
            ),
          );
        }

        expect((await as('u-owner'))?.status, 200);
        expect(await as('u-customer'), _refused);
      },
    );
  });
}
