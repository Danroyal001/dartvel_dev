// A path no route serves answers 404 on the server that ships.
//
// The backend answered every unknown path with the application shell and a
// 200: a soft 404, which a crawler indexes as a page. The shell is still the
// body, so the app draws its not-found page; only the status changes. A page
// published from Studio is a route the manifest does not list, so it is asked
// about before the answer is a 404.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/http.dart';
import 'package:dartvel_shelf/src/ssr_helper.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _shell = '<!DOCTYPE html><html><head><title>Acme</title></head>'
    '<body><div id="app"></div></body></html>';

Directory site({Map<String, Object?>? routes}) {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_404_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'index.html')).writeAsStringSync(_shell);
  File(p.join(root.path, 'dartvel_routes.json')).writeAsStringSync(jsonEncode(
    <String, Object?>{
      'routes': routes ??
          <String, Object?>{
            '/': <String, Object?>{'title': 'Home'},
            '/docs': <String, Object?>{'title': 'Documentation'},
            '/products/:id': <String, Object?>{'title': 'A product'},
          },
    },
  ));
  return root;
}

Future<Response> get(
  String path, {
  Directory? root,
  Future<Set<String>> Function()? publishedRoutes,
}) =>
    handleSsrFallback(
      Request(
        method: 'GET',
        url: Uri.parse('http://acme.example$path'),
        headers: Headers(),
        bodyStream: const Stream<List<int>>.empty(),
      ),
      (root ?? site()).path,
      publishedRoutes: publishedRoutes,
    );

Future<String> body(Response response) async => utf8.decode(<int>[
      for (final List<int> chunk in await response.body!.stream.toList())
        ...chunk,
    ]);

void main() {
  test('a route the manifest lists answers 200', () async {
    expect((await get('/docs')).status, 200);
    expect((await get('/products/42')).status, 200);
    expect((await get('/')).status, 200);
  });

  test('an unknown path answers 404 with the shell as the body', () async {
    final Response response = await get('/definitely-missing');

    expect(response.status, 404);
    expect(await body(response), contains('<div id="app">'));
  });

  test('a page published from Studio answers 200', () async {
    Future<Set<String>> published() async => <String>{'/menu'};

    expect((await get('/menu', publishedRoutes: published)).status, 200);
    expect(
        (await get('/nothing', publishedRoutes: published)).status, 404);
  });

  test('a manifest with no routes says nothing about what is missing',
      () async {
    final Directory root = site(routes: <String, Object?>{});

    expect((await get('/anything', root: root)).status, 200);
  });
}
