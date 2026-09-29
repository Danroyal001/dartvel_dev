// The documentation site, served by the backend runtime.
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

void main() {
  setUp(() {
    final Directory parent =
        Directory.systemTemp.createTempSync('dartvel_docs_server_');
    _root = Directory('${parent.path}/docs')..createSync();
    File('${_root.path}/index.html')
        .writeAsStringSync('<html><title>Docs</title></html>');
    File('${_root.path}/docs.json')
        .writeAsStringSync('{"application":"test","pages":[]}');
    File('${_root.path}/graph.json')
        .writeAsStringSync('{"models":[],"routes":[]}');
    File('${_root.path}/main.dart.js').writeAsStringSync('// docs app js');
    addTearDown(() => parent.deleteSync(recursive: true));
  });

  tearDown(() {
    DVSessionAuthentication.uninstall();
    DVAuthAuthorization.reset();
  });

  group('when disabled', () {
    test('returns null so application handles the route', () async {
      final DVDocsServer server = DVDocsServer(
        mount: const DVDocsMount(path: '/docs', enabled: false),
        root: _root.path,
      );
      expect(await server.respond(_get('/docs')), isNull);
      expect(await server.respond(_get('/docs/docs.json')), isNull);
    });
  });

  group('with studio access', () {
    const DVDocsMount studioMount =
        DVDocsMount(path: '/docs', enabled: true, access: DVDocsAccess.studio);

    test('signed-out callers get 302 to Studio login for page paths', () async {
      final DVDocsServer server = DVDocsServer(
        mount: studioMount,
        root: _root.path,
        authenticated: (_) async => false,
      );
      for (final String path in <String>[
        '/docs',
        '/docs/',
        '/docs/models',
        '/docs/overview'
      ]) {
        final Response? response = await server.respond(_get(path));
        expect(response, isNotNull, reason: path);
        expect(response!.status, 302, reason: path);
        expect(
          response.headers.get('location'),
          '/__studio/login?from=${Uri.encodeQueryComponent(path)}',
          reason: path,
        );
        expect(response.headers.get('cache-control'), contains('no-store'));
      }
    });

    test('custom admin mount login path is respected for 302 redirects',
        () async {
      final DVDocsServer server = DVDocsServer(
        mount: studioMount,
        root: _root.path,
        adminMount: const DVAdminMount(
            path: '/_ops', enabled: true, requiresAuth: true),
        authenticated: (_) async => false,
      );
      final Response? response = await server.respond(_get('/docs/models'));
      expect(response?.status, 302);
      expect(response!.headers.get('location'),
          '/_ops/login?from=${Uri.encodeQueryComponent('/docs/models')}');
    });

    test('signed-out callers get 404 for docs data (docs.json and graph.json)',
        () async {
      final DVDocsServer server = DVDocsServer(
        mount: studioMount,
        root: _root.path,
        authenticated: (_) async => false,
      );
      for (final String path in <String>[
        '/docs/docs.json',
        '/docs/graph.json'
      ]) {
        final Response? response = await server.respond(_get(path));
        expect(response, isNotNull, reason: path);
        expect(response!.status, 404, reason: path);
        expect(
            response.headers.get('content-type'), 'text/plain; charset=utf-8');
      }
    });

    test('callers signed in without a Studio grant get 404 for docs data',
        () async {
      final DVDocsServer server = DVDocsServer(
        mount: studioMount,
        root: _root.path,
        authenticated: (_) async => false,
      );
      final Response? response = await server.respond(_get('/docs/docs.json'));
      expect(response?.status, 404);
    });

    test('callers with Studio grant get 200 for pages and docs data',
        () async {
      final DVDocsServer server = DVDocsServer(
        mount: studioMount,
        root: _root.path,
        authenticated: (_) async => true,
      );
      for (final String path in <String>[
        '/docs',
        '/docs/',
        '/docs/overview'
      ]) {
        final Response? response = await server.respond(_get(path));
        expect(response?.status, 200, reason: path);
        expect(
            response!.headers.get('content-type'), 'text/html; charset=utf-8');
        expect(await _body(response), contains('<title>Docs</title>'));
      }

      final Response? docsJson =
          await server.respond(_get('/docs/docs.json'));
      expect(docsJson?.status, 200);
      expect(docsJson!.headers.get('content-type'), 'application/json');
      expect(await _body(docsJson), contains('"application":"test"'));

      final Response? graphJson =
          await server.respond(_get('/docs/graph.json'));
      expect(graphJson?.status, 200);
      expect(graphJson!.headers.get('content-type'), 'application/json');
      expect(await _body(graphJson), contains('"models"'));

      final Response? js = await server.respond(_get('/docs/main.dart.js'));
      expect(js?.status, 200);
      expect(js!.headers.get('content-type'),
          'application/javascript; charset=utf-8');
    });
  });

  group('with public access', () {
    const DVDocsMount publicMount =
        DVDocsMount(path: '/docs', enabled: true, access: DVDocsAccess.public);

    test('signed-out callers get 200 for pages without redirect', () async {
      final DVDocsServer server = DVDocsServer(
        mount: publicMount,
        root: _root.path,
        authenticated: (_) async => false,
      );
      for (final String path in <String>[
        '/docs',
        '/docs/',
        '/docs/overview'
      ]) {
        final Response? response = await server.respond(_get(path));
        expect(response?.status, 200, reason: path);
        expect(
            response!.headers.get('content-type'), 'text/html; charset=utf-8');
      }
    });

    test('signed-out callers get 200 for docs.json and graph.json', () async {
      final DVDocsServer server = DVDocsServer(
        mount: publicMount,
        root: _root.path,
        authenticated: (_) async => false,
      );
      final Response? docsJson =
          await server.respond(_get('/docs/docs.json'));
      expect(docsJson?.status, 200);
      expect(docsJson!.headers.get('content-type'), 'application/json');

      final Response? graphJson =
          await server.respond(_get('/docs/graph.json'));
      expect(graphJson?.status, 200);
      expect(graphJson!.headers.get('content-type'), 'application/json');
    });
  });
}
