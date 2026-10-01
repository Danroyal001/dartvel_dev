// The preview server answering Studio.
//
// The decision about who may see Studio is asserted beside DVAdminServer.
// This is the half that turns it into a response on `dartvel dev --release`, and
// the property that matters is the one a unit test of the decision cannot
// reach: a hidden Studio has to produce the same nothing as a route the
// application does not serve, all the way out of the handler. And Studio is
// pages of the application, rendered from its shell, with its code handed
// out from memory -- nothing is ever served from an admin directory on disk.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_cli/src/build/admin_mount.dart';
import 'package:dartvel_cli/src/build/web_server.dart';
import 'package:dartvel_core/dartvel.dart' as core show DVAdminServer, Request;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

late Directory _root;

final Map<String, Uint8List> _parts = <String, Uint8List>{
  'main.dart.js_7.part.js':
      Uint8List.fromList(utf8.encode('/* Studio screens */')),
};

Handler _handler({DVAdminMount? admin, bool server = true}) =>
    dvWebServerHandler(
      webRoot: _root.path,
      admin: admin,
      adminServer: admin == null || !server
          ? null
          : core.DVAdminServer(
              mount: admin,
              root: '${_root.path}/../studio-data',
              webRoot: _root.path,
              title: 'Studio · shop',
              studioParts: _parts,
              authenticated: (core.Request _) async => false,
            ),
    );

/// A request for [path].
///
/// This used to build `Uri.parse('http://x')` and drop the argument, so
/// every test in this file asked for `/` and none of them tested the path it
/// named. A parameter nothing reads is the quietest way for a suite to prove
/// nothing at all.
Future<Response> _get(Handler handler, String path) async =>
    await handler(Request('GET', Uri.parse('http://x$path')));

DVAdminMount _mount({bool enabled = true, bool requiresAuth = false}) =>
    DVAdminMount(
        path: '/__studio', enabled: enabled, requiresAuth: requiresAuth);

void main() {
  setUp(() {
    _root = Directory.systemTemp.createTempSync('dartvel_admin_serve_');
    File('${_root.path}/index.html').writeAsStringSync(
        '<html><head><title>The site</title></head><body>'
        '<script src="flutter_bootstrap.js"></script></body></html>');
    File('${_root.path}/main.dart.js').writeAsStringSync('// the site');
    // What an older build left: a separately built Studio under the web
    // root. None of it is served.
    Directory('${_root.path}/__admin').createSync();
    File('${_root.path}/__admin/index.html')
        .writeAsStringSync('<html><title>OLD STUDIO APP</title></html>');
    File('${_root.path}/__admin/main.dart.js').writeAsStringSync('// OLD');
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

    test('a mount with no Studio server behind it serves nothing', () async {
      final Response hidden =
          await _get(_handler(admin: _mount(), server: false), '/__studio');

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

    test("Studio's code, to a caller with no grant, is a path that does not "
        'exist', () async {
      final Handler handler = _handler(admin: _mount(requiresAuth: true));
      final Response part = await _get(handler, '/main.dart.js_7.part.js');
      final Response nowhere = await _get(handler, '/main.dart.js_8.part.js');

      expect(part.statusCode, nowhere.statusCode);
      expect(await part.readAsString(), await nowhere.readAsString());
    });
  });

  group('a served admin', () {
    test('the mount is a page of the application, rendered from its shell',
        () async {
      final Response response =
          await _get(_handler(admin: _mount()), '/__studio');
      final String html = await response.readAsString();

      expect(response.statusCode, 200);
      expect(html, contains('<title>Studio · shop</title>'));
      expect(html, contains('flutter_bootstrap.js'));
      expect(html, isNot(contains('OLD STUDIO APP')));
    });

    test('nothing under the mount is a file', () async {
      for (final String path in <String>[
        '/__studio/main.dart.js',
        '/__studio/index.html',
        '/__studio/models',
      ]) {
        final Response response = await _get(_handler(admin: _mount()), path);
        expect(response.statusCode, 404, reason: path);
        expect(await response.readAsString(), isNot(contains('OLD')),
            reason: path);
      }
    });

    test("Studio's code is served from memory, from the site root", () async {
      final Response response =
          await _get(_handler(admin: _mount()), '/main.dart.js_7.part.js');

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('javascript'));
      expect(response.headers['cache-control'], 'no-store');
      expect(await response.readAsString(), '/* Studio screens */');
    });

    test('the application keeps every path that is not the mount', () async {
      final Response response = await _get(_handler(admin: _mount()), '/');

      expect(await response.readAsString(), contains('The site'));
      final Response script =
          await _get(_handler(admin: _mount()), '/main.dart.js');
      expect(await script.readAsString(), '// the site');
    });
  });
}

/// The status a hidden admin answers with, for the first test to compare
/// against without asserting the application returns any particular one.
const int dvAdminHiddenStatusForTest = 404;
