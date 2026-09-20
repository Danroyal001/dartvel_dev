// The admin dashboard, served by the generated backend.
//
// `dartvel preview` has served the dashboard for a while; the web-server
// binary, which is the deployment, never did. This is the half both of them
// share: which file a request under the mount gets, with what content type,
// and whether the caller may have it at all.
//
// The backend's answer for a caller who may not see the admin is "nothing
// here": null, so the request carries on to whatever the application answers
// for a path it does not serve. A 404 of its own would be an oracle on a
// server whose unknown routes answer with the site's shell.
import 'dart:convert';
import 'dart:io';

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
        expect(response, isNull, reason: path);
      }
    });
  });

  group('the application keeps', () {
    test('every path that is not the mount', () async {
      final DVAdminServer server = DVAdminServer(mount: _open, root: _root.path);
      for (final String path in <String>['/', '/__studiox', '/api/health']) {
        expect(await server.respond(_get(path)), isNull, reason: path);
      }
    });

    test('the mount itself when the admin is turned off', () async {
      const DVAdminMount off =
          DVAdminMount(path: '/__studio', enabled: false, requiresAuth: false);
      expect(
          await DVAdminServer(mount: off, root: _root.path)
              .respond(_get('/__studio/')),
          isNull);
    });
  });

  group('a mount that requires a sign-in', () {
    test('answers nothing to a caller with no session', () async {
      DVSessionAuthentication.install(sessions: DVSessions());
      final DVAdminServer server =
          DVAdminServer(mount: _guarded, root: _root.path);
      expect(await server.respond(_get('/__studio/')), isNull);
      expect(await server.respond(_get('/__studio/graph.json')), isNull);
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
          isNull);
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
          isNull);
      expect(
          await server.respond(_get('/__studio/graph.json',
              headers: <String, String>{
                'authorization': 'Bearer ${customer.token}',
              })),
          isNull);
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
          isNull);
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
        isNull,
      );
      // The grant is taken away: nothing again, on the same live session.
      expect(await grants.revoke('u-operator'), isTrue);
      expect(
          await server.respond(_get('/__studio/', headers: <String, String>{
            'authorization': 'Bearer ${issued.token}',
          })),
          isNull);

      // Granted again, and the session revoked: nothing either.
      await grants.grant('u-operator');
      await sessions.revoke(issued.session.id);
      expect(
          await server.respond(_get('/__studio/', headers: <String, String>{
            'authorization': 'Bearer ${issued.token}',
          })),
          isNull);
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
      expect(await as('u-customer'), isNull);
    });
  });
}
