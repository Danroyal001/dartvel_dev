// The admin dashboard, served by the generated backend.
//
// `dartvel preview` has served the dashboard for a while; the web-server
// binary, which is the deployment, never did. This is the half both of them
// share: which file a request under the mount gets, with what content type,
// and whether the caller may have it at all.
//
// A person arriving signed out at a Studio page is sent to Studio's own
// sign-in at <mount>/login. For the dashboard's files and its API the answer
// to a caller who may not see the admin is "nothing here": null, so the
// request carries on to whatever the application answers for a path it does
// not serve.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_core/binary_payload.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

late Directory _root;

Request _get(String path, {Map<String, String>? headers}) => Request(
      method: 'GET',
      url: Uri.parse('http://localhost:8080$path'),
      headers: Headers(headers),
      bodyStream: const Stream<List<int>>.empty(),
    );

Future<String> _body(Response response) async =>
    utf8.decode(await response.body!.bytes());

const DVAdminMount _open =
    DVAdminMount(path: '/__studio', enabled: true, requiresAuth: false);
const DVAdminMount _guarded =
    DVAdminMount(path: '/__studio', enabled: true, requiresAuth: true);

/// Not served Studio: either nothing, for the application to answer, or
/// sent to Studio's own sign-in.
final Matcher _refused = predicate<Response?>(
    (Response? r) =>
        r == null ||
        (r.status == 302 &&
            (r.headers.get('location') ?? '').startsWith('/__studio/login')),
    'refused: nothing, or a redirect to /__studio/login');

void main() {
  setUp(() {
    final Directory parent =
        Directory.systemTemp.createTempSync('dartvel_admin_server_');
    // The admin root, with a secret beside it that traversal must not reach.
    File('${parent.path}/secret.txt').writeAsStringSync('database password');
    _root = Directory('${parent.path}/admin')..createSync();
    File('${_root.path}/index.html')
        .writeAsStringSync('<html><title>Studio</title></html>');
    File('${_root.path}/admin.css').writeAsStringSync('body{}');
    File('${_root.path}/admin.js').writeAsStringSync('// admin');
    File('${_root.path}/graph.json').writeAsStringSync('{"models":[]}');
    addTearDown(() => parent.deleteSync(recursive: true));
  });

  tearDown(() {
    DVSessionAuthentication.uninstall();
    DVAuthAuthorization.reset();
  });

  group('a caller who may see the admin', () {
    test('gets the dashboard at the mount, with and without the slash',
        () async {
      final DVAdminServer server = DVAdminServer(mount: _open, root: _root.path);
      for (final String path in <String>['/__studio', '/__studio/']) {
        final Response? response = await server.respond(_get(path));
        expect(response?.status, 200, reason: path);
        expect(response!.headers.get('content-type'),
            'text/html; charset=utf-8');
        expect(await _body(response), contains('<title>Studio</title>'));
      }
    });

    test('gets each of the dashboard\'s files as its own type', () async {
      final DVAdminServer server = DVAdminServer(mount: _open, root: _root.path);
      final Map<String, String> expected = <String, String>{
        '/__studio/index.html': 'text/html; charset=utf-8',
        '/__studio/admin.css': 'text/css; charset=utf-8',
        '/__studio/admin.js': 'text/javascript; charset=utf-8',
        '/__studio/graph.json': 'application/json; charset=utf-8',
      };
      for (final MapEntry<String, String> file in expected.entries) {
        final Response? response = await server.respond(_get(file.key));
        expect(response?.status, 200, reason: file.key);
        expect(response!.headers.get('content-type'), file.value,
            reason: file.key);
      }
      final Response? graph =
          await server.respond(_get('/__studio/graph.json'));
      expect(await _body(graph!), '{"models":[]}');
    });

    test('is never cached by anything between it and the server', () async {
      // An authenticated dashboard kept by a shared cache is served to the
      // next person who asks, signed in or not.
      final Response? response = await DVAdminServer(
              mount: _open, root: _root.path)
          .respond(_get('/__studio/graph.json'));
      expect(response!.headers.get('cache-control'), contains('no-store'));
    });

    test('gets the dashboard shell for a route inside it', () async {
      final Response? response =
          await DVAdminServer(mount: _open, root: _root.path)
              .respond(_get('/__studio/models'));
      expect(response?.status, 200);
      expect(await _body(response!), contains('Studio'));
    });

    test('cannot leave the admin root, however the dots are written',
        () async {
      final DVAdminServer server = DVAdminServer(mount: _open, root: _root.path);
      for (final String path in <String>[
        '/__studio/%2e%2e/secret.txt',
        '/__studio/..%2fsecret.txt',
        '/__studio/%2E%2E%2Fsecret.txt',
      ]) {
        final Response? response = await server.respond(_get(path));
        if (response != null) {
          expect(await _body(response), isNot(contains('password')),
              reason: path);
        }
        expect(response, _refused, reason: path);
      }
    });
  });

  group('carried in a web-server binary', () {
    // The binary keeps the dashboard in its pack, every file protected, and
    // writes none of it out. Served from there, every answer is the one the
    // directory gives.
    late String packed;

    setUp(() {
      final List<DVAssetPackEntry> entries = <DVAssetPackEntry>[
        for (final FileSystemEntity f in _root.listSync(recursive: true))
          if (f is File)
            DVAssetPackEntry('admin/${f.path.substring(_root.path.length + 1)}', f.readAsBytesSync(),
                stored: Uint8List.fromList(gzip.encode(f.readAsBytesSync())),
                encoding: DVAssetEncoding.gzip,
                protected: true),
      ];
      final Uint8List bytes = dvWriteAssetPack(entries);
      final File server = File('${_root.parent.path}/server')..writeAsBytesSync(bytes);
      packed = '${server.path}/admin';
      DVAssetSources.register(
          packed, DVPackedAssets(DVAssetPack.open(server.path, offset: 0, length: bytes.length)!, prefix: 'admin/'));
      addTearDown(DVAssetSources.clear);
    });

    test('answers every request as the directory does', () async {
      for (final String path in <String>[
        '/__studio', '/__studio/', '/__studio/index.html', '/__studio/admin.css',
        '/__studio/admin.js', '/__studio/graph.json', '/__studio/models',
        '/__studio/../secret.txt', '/__studio/%2e%2e/secret.txt', '/__studio/nothing.js',
      ]) {
        final Response? fromDisk = await DVAdminServer(mount: _open, root: _root.path).respond(_get(path));
        final Response? fromPack = await DVAdminServer(mount: _open, root: packed).respond(_get(path));
        expect(fromPack?.status, fromDisk?.status, reason: path);
        expect(fromPack?.headers.get('content-type'), fromDisk?.headers.get('content-type'), reason: path);
        if (fromDisk != null && fromPack != null) {
          expect(await _body(fromPack), await _body(fromDisk), reason: path);
        }
      }
      expect(Directory(packed).existsSync(), isFalse, reason: 'nothing was written out');
    });

    test('is private and never stored', () async {
      final Response? response =
          await DVAdminServer(mount: _open, root: packed).respond(_get('/__studio/admin.js'));
      expect(response!.headers.get('cache-control'), 'private, no-store');
    });

    test('reads the queues from the graph in the pack', () {
      final Uint8List bytes = dvWriteAssetPack(<DVAssetPackEntry>[
        DVAssetPackEntry('admin/graph.json', Uint8List.fromList(utf8.encode('{"jobs":[{"queue":"mail"}]}')),
            protected: true),
      ]);
      final File server = File('${_root.parent.path}/other-server')..writeAsBytesSync(bytes);
      DVAssetSources.register('${server.path}/admin',
          DVPackedAssets(DVAssetPack.open(server.path, offset: 0, length: bytes.length)!, prefix: 'admin/'));
      expect(dvAdminGraphQueues('${server.path}/admin'), <String>['mail']);
    });
  });

  group('the application keeps', () {
    test('every path that is not the mount', () async {
      final DVAdminServer server = DVAdminServer(mount: _open, root: _root.path);
      for (final String path in <String>['/', '/__studiox', '/api/health']) {
        expect(await server.respond(_get(path)), _refused, reason: path);
      }
    });

    test('the mount itself when the admin is turned off', () async {
      const DVAdminMount off =
          DVAdminMount(path: '/__studio', enabled: false, requiresAuth: false);
      expect(
          await DVAdminServer(mount: off, root: _root.path)
              .respond(_get('/__studio/')),
          _refused);
    });
  });

  group("Studio's own sign-in", () {
    // Studio signs people in at its own mount, as wp-admin does, so it does
    // not depend on the application serving /login: an application can turn
    // its account pages off, or move them, and Studio still opens.
    test('a signed-out visit to a Studio page goes to <mount>/login, with where '
        'it was going', () async {
      DVSessionAuthentication.install(sessions: DVSessions());
      final DVAdminServer server =
          DVAdminServer(mount: _guarded, root: _root.path);
      for (final String path in <String>[
        '/__studio',
        '/__studio/',
        '/__studio/index.html',
        '/__studio/index.html/',
        '/__studio/index.html#/data',
        '/__studio/anything',
        '/__studio/anything/',
        '/__studio/pages',
      ]) {
        final Response? r = await server.respond(_get(path));
        expect(r?.status, 302, reason: path);
        expect(r!.headers.get('location'),
            '/__studio/login?from=${Uri.encodeQueryComponent(path)}',
            reason: path);
        expect(r.headers.get('cache-control'), 'no-store', reason: path);
      }
    });

    test('follows a moved mount', () async {
      DVSessionAuthentication.install(sessions: DVSessions());
      const DVAdminMount moved =
          DVAdminMount(path: '/ops/desk', enabled: true, requiresAuth: true);
      final DVAdminServer server = DVAdminServer(mount: moved, root: _root.path);
      final Response? r = await server.respond(_get('/ops/desk/'));
      expect(r!.headers.get('location'), startsWith('/ops/desk/login?from='));
      final Response? page = await server.respond(_get('/ops/desk/login'));
      expect(page?.status, 200);
    });

    test('the sign-in is a page of the Studio app: <mount>/login serves its '
        'shell to anybody', () async {
      // Studio is a Flutter application, and its sign-in is one of its
      // pages. The server serves the same shell it serves a granted person,
      // and the app draws the sign-in; there is no page of the server's own.
      DVSessionAuthentication.install(sessions: DVSessions());
      final DVAdminServer server =
          DVAdminServer(mount: _guarded, root: _root.path);
      final Response? r =
          await server.respond(_get('/__studio/login?from=/__studio/data'));
      expect(r?.status, 200);
      expect(r!.headers.get('content-type'), startsWith('text/html'));
      expect(r.headers.get('cache-control'), 'private, no-store');
      expect(await _body(r), '<html><title>Studio</title></html>');
    });

    test("the app's code is served to anybody, so the sign-in can run; the "
        "project's graph and Studio's data are not", () async {
      DVSessionAuthentication.install(sessions: DVSessions());
      final DVAdminServer server =
          DVAdminServer(mount: _guarded, root: _root.path);
      final Response? js = await server.respond(_get('/__studio/admin.js'));
      expect(js?.status, 200);
      expect(await _body(js!), '// admin');
      expect((await server.respond(_get('/__studio/admin.css')))?.status, 200);
      expect(await server.respond(_get('/__studio/graph.json')), isNull);
      expect(await server.respond(_get('/__studio/api/grants')), isNull);
      expect(await server.respond(_get('/__studio/api/models')), isNull);
    });

    test('signs in through the application\'s own accounts, at the mount, '
        'with the CSRF header required', () async {
      final DVSessions sessions = DVSessions();
      DVSessionAuthentication.install(sessions: sessions);
      final LocalAuthProvider accounts = LocalAuthProvider();
      await accounts.signUp('ops@example.com', 'a-long-enough-password-1');
      DVAuthEndpoints.install(
          credentials: DVCredentialGuard(provider: accounts, refusalFloor: .zero));
      addTearDown(DVAuthEndpoints.uninstall);
      final DVAdminServer server =
          DVAdminServer(mount: _guarded, root: _root.path);
      Request post(String path, Map<String, Object?> body, {bool csrf = true}) =>
          Request(
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
      final Response? noCsrf = await server
          .respond(post('/__studio/api/auth/sign-in', good, csrf: false));
      expect(noCsrf?.status, 403);
      final Response? wrong = await server.respond(post(
          '/__studio/api/auth/sign-in',
          <String, Object?>{'email': 'ops@example.com', 'password': 'nope-nope-nope'}));
      expect(wrong?.status, 400);
      final Response? ok =
          await server.respond(post('/__studio/api/auth/sign-in', good));
      expect(ok?.status, 200);
      expect(ok!.headers.get('set-cookie'), contains('dv_session='));
    });

    test('<mount>/api/access says whether this caller may open Studio, and '
        'nothing else', () async {
      final DVSessions sessions = DVSessions();
      DVSessionAuthentication.install(sessions: sessions);
      final DVStudioGrants grants =
          DVStudioGrants(SqliteDVDatabaseAdapter.memory())..install();
      final DVIssuedSession issued = await sessions.create('u-operator');
      final DVAdminServer server =
          DVAdminServer(mount: _guarded, root: _root.path);
      Future<Object?> access(Map<String, String> headers) async {
        final Response? r =
            await server.respond(_get('/__studio/api/access', headers: headers));
        expect(r?.status, 200);
        expect(r!.headers.get('cache-control'), 'no-store');
        return jsonDecode(await _body(r));
      }

      expect(await access(const <String, String>{}),
          <String, Object?>{'granted': false});
      final Map<String, String> bearer = <String, String>{
        'authorization': 'Bearer ${issued.token}',
      };
      expect(await access(bearer), <String, Object?>{'granted': false});
      await grants.grant('u-operator');
      expect(await access(bearer), <String, Object?>{'granted': true});
    });

    test('a turned-off admin has no sign-in page either', () async {
      const DVAdminMount off =
          DVAdminMount(path: '/__studio', enabled: false, requiresAuth: true);
      final DVAdminServer server = DVAdminServer(mount: off, root: _root.path);
      expect(await server.respond(_get('/__studio/login')), isNull);
      expect(await server.respond(_get('/__studio/')), isNull);
    });
  });

  group('a mount that requires a sign-in', () {
    test('answers nothing to a caller with no session', () async {
      DVSessionAuthentication.install(sessions: DVSessions());
      final DVAdminServer server =
          DVAdminServer(mount: _guarded, root: _root.path);
      expect(await server.respond(_get('/__studio/')), _refused);
      expect(await server.respond(_get('/__studio/graph.json')), _refused);
    });

    test('answers nothing to a session token that is not a live session',
        () async {
      DVSessionAuthentication.install(sessions: DVSessions());
      final DVAdminServer server =
          DVAdminServer(mount: _guarded, root: _root.path);
      expect(
          await server.respond(_get('/__studio/', headers: <String, String>{
            'authorization': 'Bearer ${DVSessions.tokenPrefix}forged',
          })),
          _refused);
    });

    test('answers nothing to a signed-in person nobody granted Studio',
        () async {
      // Signing up is open to anybody the application lets in: every
      // customer has a live session. A session alone opening the dashboard
      // hands every customer the application's models, routes and jobs.
      final DVSessions sessions = DVSessions();
      DVSessionAuthentication.install(sessions: sessions);
      DVStudioGrants(SqliteDVDatabaseAdapter.memory()).install();
      final DVIssuedSession customer = await sessions.create('u-customer');
      final DVAdminServer server =
          DVAdminServer(mount: _guarded, root: _root.path);

      expect(
          await server.respond(_get('/__studio/', headers: <String, String>{
            'authorization': 'Bearer ${customer.token}',
          })),
          _refused);
      expect(
          await server.respond(_get('/__studio/graph.json',
              headers: <String, String>{
                'authorization': 'Bearer ${customer.token}',
              })),
          _refused);
    });

    test('answers nothing to a signed-in person when no policy is registered',
        () async {
      // Nothing installed a grant store and the application registered no
      // Studio.access policy: nobody, not everybody.
      final DVSessions sessions = DVSessions();
      DVSessionAuthentication.install(sessions: sessions);
      final DVIssuedSession issued = await sessions.create('u-operator');
      expect(
          await DVAdminServer(mount: _guarded, root: _root.path)
              .respond(_get('/__studio/', headers: <String, String>{
            'authorization': 'Bearer ${issued.token}',
          })),
          _refused);
    });

    test('serves a person granted Studio, and stops when the grant goes',
        () async {
      final DVSessions sessions = DVSessions();
      DVSessionAuthentication.install(sessions: sessions);
      final DVStudioGrants grants =
          DVStudioGrants(SqliteDVDatabaseAdapter.memory())..install();
      final DVIssuedSession issued = await sessions.create('u-operator');
      await grants.grant('u-operator');
      final DVAdminServer server =
          DVAdminServer(mount: _guarded, root: _root.path);

      final Response? bearer = await server.respond(_get('/__studio/',
          headers: <String, String>{
            'authorization': 'Bearer ${issued.token}',
          }));
      expect(bearer?.status, 200);
      expect(await _body(bearer!), contains('Studio'));

      // And the cookie a browser carries, which is how the dashboard is
      // actually opened.
      const DVSessionCookie cookie = DVSessionCookie();
      final Response? browser = await server.respond(_get('/__studio/',
          headers: <String, String>{
            'cookie': '${cookie.cookieName(development: false)}=${issued.token}',
          }));
      expect(browser?.status, 200);

      // And the cookie a browser keeps when the binary is served over
      // http://localhost, which is every build run on the machine that
      // made it: Secure cannot be set there, so the name carries no
      // __Host- prefix. Studio answered the application's own page
      // instead of itself, and the developer saw their shop.
      final Response? local = await server.respond(_get('/__studio/',
          headers: <String, String>{
            'host': 'localhost:8093',
            'cookie':
                '${cookie.cookieName(development: true)}=${issued.token}',
          }));
      expect(local?.status, 200);

      // The same cookie from somewhere that is not this machine is not a
      // session: only the prefixed name counts there.
      expect(
        await server.respond(_get('/__studio/', headers: <String, String>{
          'host': 'shop.example.com',
          'cookie':
              '${cookie.cookieName(development: true)}=${issued.token}',
        })),
        _refused,
      );
      // The grant is taken away: nothing again, on the same live session.
      expect(await grants.revoke('u-operator'), isTrue);
      expect(
          await server.respond(_get('/__studio/', headers: <String, String>{
            'authorization': 'Bearer ${issued.token}',
          })),
          _refused);

      // Granted again, and the session revoked: nothing either.
      await grants.grant('u-operator');
      await sessions.revoke(issued.session.id);
      expect(
          await server.respond(_get('/__studio/', headers: <String, String>{
            'authorization': 'Bearer ${issued.token}',
          })),
          _refused);
    });

    test('a grant on one tenant opens nothing on another', () async {
      final DVStudioGrants grants =
          DVStudioGrants(SqliteDVDatabaseAdapter.memory());
      await grants.grant('u-operator', tenant: 'acme');
      expect(await grants.isGranted('u-operator', tenant: 'acme'), isTrue);
      expect(await grants.isGranted('u-operator', tenant: 'globex'), isFalse);
      expect(await grants.isGranted('u-operator'), isFalse);
      // Granting twice is one grant.
      await grants.grant('u-operator', tenant: 'acme');
      expect((await grants.list()).length, 1);
    });

    test('the application\'s own Studio.access policy decides instead',
        () async {
      final DVSessions sessions = DVSessions();
      DVSessionAuthentication.install(sessions: sessions);
      DVStudioGrants(SqliteDVDatabaseAdapter.memory()).install();
      const DVAuthAuthorization().registerAction(
        dvStudioAccessAction,
        (Object? caller, Object? _) =>
            caller is DVSessionPrincipal && caller.userId == 'u-owner',
      );
      final DVAdminServer server =
          DVAdminServer(mount: _guarded, root: _root.path);
      Future<Response?> as(String user) async {
        final DVIssuedSession issued = await sessions.create(user);
        return server.respond(_get('/__studio/', headers: <String, String>{
          'authorization': 'Bearer ${issued.token}',
        }));
      }

      expect((await as('u-owner'))?.status, 200);
      expect(await as('u-customer'), _refused);
    });
  });

  group('deferred library chunks', () {
    // Point 3 of the binding brief: deferred parts (.part.js, wasm,
    // anything matching the deferred chunk naming) are never served
    // without the Studio grant. A signed-out request gets 404,
    // exactly as a route that does not exist — never 302, never the chunk.
    test('a deferred chunk without a grant is 404, not 302 or the chunk',
        () async {
      DVSessionAuthentication.install(sessions: DVSessions());
      final DVAdminServer server =
          DVAdminServer(mount: _guarded, root: _root.path);
      // Create a fake deferred chunk file in the admin root.
      File('${_root.path}/main.dart.js_2.part.js')
          .writeAsStringSync('/* deferred chunk */');
      File('${_root.path}/main.dart.js_7.part.js')
          .writeAsStringSync('/* deferred chunk */');
      File('${_root.path}/main.dart.js')
          .writeAsStringSync('/* main */');
      for (final String path in <String>[
        '/__studio/main.dart.js_2.part.js',
        '/__studio/main.dart.js_7.part.js',
      ]) {
        final Response? r = await server.respond(_get(path));
        // Without a grant, deferred chunks must be hidden (null -> 404).
        // The sign-in redirect applies only to navigable pages, not chunks.
        expect(r, isNull, reason: path);
      }
    });

    test('a deferred chunk with a grant is served', () async {
      final DVSessions sessions = DVSessions();
      DVSessionAuthentication.install(sessions: sessions);
      final DVStudioGrants grants =
          DVStudioGrants(SqliteDVDatabaseAdapter.memory())..install();
      final DVIssuedSession issued = await sessions.create('u-operator');
      await grants.grant('u-operator');
      final DVAdminServer server =
          DVAdminServer(mount: _guarded, root: _root.path);
      File('${_root.path}/main.dart.js_2.part.js')
          .writeAsStringSync('/* deferred chunk */');
      final Response? r = await server.respond(_get(
        '/__studio/main.dart.js_2.part.js',
        headers: <String, String>{
          'authorization': 'Bearer ${issued.token}',
        },
      ));
      expect(r?.status, 200);
    });
  });
}
