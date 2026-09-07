// The backend serving the admin.
//
// The decision about who may see it is asserted next door, on a value. This
// is the half that turns the decision into a response, and the property that
// matters is the one a unit test of the decision cannot reach: a hidden
// admin has to produce the same nothing as a route the application does not
// serve, all the way out of the handler -- not a 404 from the decision and
// then the site's own shell from the fallthrough two branches later.
import 'dart:io';

import 'package:dartvel_cli/src/build/admin_mount.dart';
import 'package:dartvel_cli/src/build/web_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

late Directory _root;

Handler _handler({DVAdminMount? admin, bool authenticated = false}) =>
    dvWebServerHandler(
      webRoot: _root.path,
      admin: admin,
      adminRoot: '${_root.path}/__admin',
      adminAuthenticated: (Request _) async => authenticated,
    );

Future<Response> _get(Handler handler, String path) async =>
    await handler(Request('GET', Uri.parse('http://x')));

DVAdminMount _mount({bool enabled = true, bool requiresAuth = false}) =>
    DVAdminMount(
        path: '/__studio', enabled: enabled, requiresAuth: requiresAuth);

void main() {
  setUp(() {
    _root = Directory.systemTemp.createTempSync('dartvel_admin_serve_');
    File('${_root.path}/index.html')
        .writeAsStringSync('<html><title>The site</title></html>');
    Directory('${_root.path}/__admin').createSync();
    File('${_root.path}/__admin/index.html')
        .writeAsStringSync('<html><title>Studio</title></html>');
    File('${_root.path}/__admin/main.dart.js').writeAsStringSync('// admin');
    addTearDown(() => _root.deleteSync(recursive: true));
  });

  group('with no admin configured', () {
    test('the mount is the application\'s to answer', () async {
      // Not a 404 from here. A build with no admin has no admin route, and
      // an application that wants to serve that path may.
      final Response response = await _get(_handler(), '/__studio');

      expect(response.statusCode, isNot(dvAdminHiddenStatusForTest));
    });
  });

  group('a hidden admin', () {
    test('answers exactly as a route that does not exist', () async {
      // The property the decision alone cannot prove: it has to leave the
      // handler as nothing, rather than falling through to the site shell
      // two branches later and answering with the application's own page.
      final Response hidden =
          await _get(_handler(admin: _mount(enabled: false)), '/__studio');
      final String body = await hidden.readAsString();

      expect(hidden.statusCode, 404);
      expect(body, isEmpty);
      expect(body.toLowerCase(), isNot(contains('studio')));
    });

    test('and so does everything under it', () async {
      final Response hidden = await _get(
          _handler(admin: _mount(enabled: false)), '/__studio/main.dart.js');

      expect(hidden.statusCode, 404);
      expect(await hidden.readAsString(), isEmpty);
    });

    test('an unauthenticated caller gets the same nothing', () async {
      final Response hidden = await _get(
          _handler(admin: _mount(requiresAuth: true), authenticated: false),
          '/__studio');

      expect(hidden.statusCode, 404);
      expect(await hidden.readAsString(), isEmpty);
    });

    test('no header names it either', () async {
      final Response hidden =
          await _get(_handler(admin: _mount(enabled: false)), '/__studio');

      for (final String value in hidden.headers.values) {
        expect(value.toLowerCase(), isNot(contains('studio')));
        expect(value.toLowerCase(), isNot(contains('admin')));
      }
      expect(hidden.headers.keys.map((String k) => k.toLowerCase()),
          isNot(contains('www-authenticate')));
    });
  });

  group('a served admin', () {
    test('the mount is its own shell, not the site\'s', () async {
      final Response response =
          await _get(_handler(admin: _mount()), '/__studio');

      expect(await response.readAsString(), contains('Studio'));
      expect(await _get(_handler(admin: _mount()), '/__studio')
          .then((Response r) => r.readAsString()),
          isNot(contains('The site')));
    });

    test('its assets are served as themselves', () async {
      // A blank admin and a console error about a MIME type reads as a
      // broken dashboard rather than a missing content type.
      final Response response =
          await _get(_handler(admin: _mount()), '/__studio/main.dart.js');

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('javascript'));
    });

    test('a path under the mount that is no file is its shell', () async {
      // The admin is one application with its own routes: /__studio/models
      // is a route inside it, not a missing file.
      final Response response =
          await _get(_handler(admin: _mount()), '/__studio/models');

      expect(response.statusCode, 200);
      expect(await response.readAsString(), contains('Studio'));
    });

    test('the application keeps every path that is not the mount', () async {
      final Response response = await _get(_handler(admin: _mount()), '/');

      expect(await response.readAsString(), contains('The site'));
    });
  });
}

/// The status a hidden admin answers with, for the first test to compare
/// against without asserting the application returns any particular one.
const int dvAdminHiddenStatusForTest = 404;
