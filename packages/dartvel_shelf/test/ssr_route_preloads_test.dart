// A served route's own code and images, named in the head the server sends.
//
// The static build writes each page's preloads into that page. The server
// answers every route from one shell, so until now none of its pages named
// the route's own deferred parts: under `streaming: shell` the head went out
// before the data carrying the renderer and the bootstrap, and nothing that
// would let the browser start on the page's own code while the server
// queried. The build's prefetch manifest says what each route loads; the
// server reads it and puts the route's list in the head.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart'
    show DVPageData, DVPageDataResolver, DVPageRequest;
import 'package:dartvel_core/http.dart';
import 'package:dartvel_shelf/src/ssr_helper.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String shell = '<!DOCTYPE html>\n<html>\n<head>\n'
    '<base href="/">\n'
    '<meta charset="UTF-8">\n'
    '<!-- dartvel:seo -->\n<title>Shell</title>\n<!-- /dartvel:seo -->\n'
    '<link rel="preload" href="main.dart.js_2.part.js" as="script">\n'
    '</head>\n<body>'
    '<script src="flutter_bootstrap.js" async></script></body>\n</html>\n';

String prefetchFor(List<String> productScripts) => jsonEncode(<String, Object?>{
      'routes': <String, Object?>{
        '/products/:id': <String, Object?>{
          'scripts': productScripts,
          'images': <Object?>[
            <String, Object?>{'url': 'assets/assets/p.png', 'as': 'fetch'},
          ],
        },
        '/about': <String, Object?>{
          'scripts': <String>[],
          'images': <Object?>[],
        },
      },
    });

Directory site({Object streaming = 'shell', String? prefetch}) {
  final Directory root =
      Directory.systemTemp.createTempSync('dartvel_route_preloads_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'index.html')).writeAsStringSync(shell);
  File(p.join(root.path, 'dartvel_routes.json')).writeAsStringSync(jsonEncode(
    <String, Object?>{
      'server': <String, Object?>{'streaming': streaming},
      'routes': <String, Object?>{
        '/products/:id': <String, Object?>{'title': 'A product'},
        '/about': <String, Object?>{'title': 'About'},
      },
    },
  ));
  if (prefetch != null) {
    File(p.join(root.path, 'dartvel_prefetch.json'))
        .writeAsStringSync(prefetch);
  }
  return root;
}

Future<Response> get(Directory root, String path, DVPageDataResolver resolver) =>
    handleSsrFallback(
      Request(
        method: 'GET',
        url: Uri.parse('http://example.com$path'),
        headers: Headers(),
        bodyStream: const Stream<List<int>>.empty(),
      ),
      root.path,
      pageData: resolver,
    );

Future<List<String>> chunks(Response response) async => <String>[
      for (final List<int> c in await response.body!.stream.toList())
        utf8.decode(c),
    ];

void main() {
  test('shell: the route\'s parts are in the first chunk, before its data',
      () async {
    final Completer<DVPageData> gate = Completer<DVPageData>();
    final Response response = await get(
      site(prefetch: prefetchFor(<String>['main.dart.js_7.part.js'])),
      '/products/5',
      (DVPageRequest r) => gate.future,
    );

    final StreamIterator<List<int>> body =
        StreamIterator<List<int>>(response.body!.stream);
    expect(await body.moveNext(), isTrue);
    final String first = utf8.decode(body.current);

    expect(gate.isCompleted, isFalse,
        reason: 'the route\'s preloads must not wait for its data');
    expect(first,
        contains('<link rel="preload" href="main.dart.js_7.part.js" as="script">'));
    expect(
        first,
        contains('<link rel="preload" href="assets/assets/p.png" as="fetch" '
            'crossorigin="anonymous">'));
    expect(first, isNot(contains('<title>')));

    gate.complete(const DVPageData(title: 'Product 5'));
    while (await body.moveNext()) {}
  });

  test('a route with nothing to preload gets nothing extra', () async {
    final Response response = await get(
      site(prefetch: prefetchFor(<String>['main.dart.js_7.part.js'])),
      '/about',
      (DVPageRequest r) async => const DVPageData(title: 'About'),
    );
    final String page = (await chunks(response)).join();
    expect(page, isNot(contains('main.dart.js_7')));
    expect(page, isNot(contains('p.png')));
  });

  test('what the shell already names is not preloaded twice', () async {
    final Response response = await get(
      site(prefetch: prefetchFor(<String>['main.dart.js_2.part.js'])),
      '/products/5',
      (DVPageRequest r) async => const DVPageData(title: 'Product 5'),
    );
    final String page = (await chunks(response)).join();
    expect(RegExp('main.dart.js_2.part.js').allMatches(page), hasLength(1));
  });

  test('without streaming, the head still carries them', () async {
    final Response response = await get(
      site(streaming: false, prefetch: prefetchFor(<String>['main.dart.js_7.part.js'])),
      '/products/5',
      (DVPageRequest r) async => const DVPageData(title: 'Product 5'),
    );
    final String page = (await chunks(response)).join();
    expect(page.indexOf('main.dart.js_7.part.js'), isNonNegative);
    expect(page.indexOf('main.dart.js_7.part.js'),
        lessThan(page.indexOf('</head>')));
  });

  test('with `true`, they are in the head chunk', () async {
    final Response response = await get(
      site(streaming: true, prefetch: prefetchFor(<String>['main.dart.js_7.part.js'])),
      '/products/5',
      (DVPageRequest r) async => const DVPageData(title: 'Product 5'),
    );
    final List<String> parts = await chunks(response);
    expect(parts.first, contains('main.dart.js_7.part.js'));
    expect(parts.first, endsWith('</head>'));
  });

  test('a build without a prefetch manifest is served as before', () async {
    final Response response = await get(
      site(),
      '/products/5',
      (DVPageRequest r) async => const DVPageData(title: 'Product 5'),
    );
    final String page = (await chunks(response)).join();
    expect(page, isNot(contains('main.dart.js_7')));
  });

  test('a redeploy\'s manifest is read, not the first one kept forever',
      () async {
    final Directory root =
        site(streaming: false, prefetch: prefetchFor(<String>['main.dart.js_7.part.js']));
    Future<String> page() async => (await chunks(await get(
          root,
          '/products/5',
          (DVPageRequest r) async => const DVPageData(title: 'Product 5'),
        )))
            .join();

    expect(await page(), contains('main.dart.js_7.part.js'));

    final File manifest = File(p.join(root.path, 'dartvel_prefetch.json'))
      ..writeAsStringSync(prefetchFor(<String>['main.dart.js_9.part.js']));
    manifest.setLastModifiedSync(DateTime.now().add(const Duration(seconds: 5)));

    final String after = await page();
    expect(after, contains('main.dart.js_9.part.js'));
    expect(after, isNot(contains('main.dart.js_7.part.js')));
  });
}
