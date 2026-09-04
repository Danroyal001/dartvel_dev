// A parent answering a federated module's path.
//
// The specification asks for a micro-site that serves its own HTML while
// still appearing in the parent's route index and sitemap. Both halves are
// needed at once: listed but unanswered, a crawler following the link gets
// the parent's not-found page, and answered but unlisted, nobody finds it.
//
// The parent answers and sends the reader on. The module serves the HTML,
// which is what makes it federated rather than compiled in.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/http.dart';
import 'package:dartvel_shelf/src/ssr_helper.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A built web-server directory: a shell and a manifest.
Directory site(Map<String, Object?> routes) {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_fed_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'index.html'))
      .writeAsStringSync('<html><head><title>Shell</title></head><body></body></html>');
  File(p.join(root.path, 'dartvel_routes.json')).writeAsStringSync(jsonEncode(
    <String, Object?>{
      'siteUrl': 'https://example.com',
      'server': <String, Object?>{},
      'routes': routes,
    },
  ));
  return root;
}

Future<Response> get(Directory root, String path) => handleSsrFallback(
      Request(
        method: 'GET',
        url: Uri.parse('http://example.com$path'),
        headers: Headers(),
        bodyStream: const Stream<List<int>>.empty(),
      ),
      root.path,
    );

void main() {
  test('a federated path is answered by sending the reader to the module',
      () async {
    final Directory root = site(<String, Object?>{
      '/': <String, Object?>{'title': 'Home'},
      '/store': <String, Object?>{'location': 'https://store.example.com/'},
    });

    final Response response = await get(root, '/store');

    expect(response.status, 302);
    expect(response.headers.get('location'), 'https://store.example.com/');
  });

  test('a parameterised federated route carries its parameters across',
      () async {
    // The reader asked for one product. Sending them to the module's index
    // would lose the only part of the request that mattered.
    final Directory root = site(<String, Object?>{
      '/store/products/:id': <String, Object?>{
        'location': 'https://store.example.com/products/:id',
      },
    });

    final Response response = await get(root, '/store/products/pro-kit');

    expect(response.status, 302);
    expect(response.headers.get('location'),
        'https://store.example.com/products/pro-kit');
  });

  test('the parent still renders its own pages', () async {
    final Directory root = site(<String, Object?>{
      '/': <String, Object?>{'title': 'Home'},
      '/store': <String, Object?>{'location': 'https://store.example.com/'},
    });

    final Response response = await get(root, '/');

    expect(response.status, 200);
  });

  test('a location that is not an address is not a redirect', () async {
    // A manifest is data and can be edited. Sending a reader to whatever the
    // string happens to be is how an open redirect starts.
    final Directory root = site(<String, Object?>{
      '/store': <String, Object?>{'location': 'javascript:alert(1)'},
    });

    final Response response = await get(root, '/store');

    expect(response.status, isNot(302));
  });
}
