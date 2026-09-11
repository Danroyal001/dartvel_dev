// `dartvel.web.server.streaming: shell`: the shell's head goes out before the
// route's data has resolved.
//
// With `true` the head is a separate write, but it is written after the data:
// the server awaits the resolver, renders the page, then splits it. Until the
// query returns the browser has received nothing, so main.dart.js, the
// renderer, the page's deferred parts and its images all wait on the
// database. NextFaster's shell-first rendering is the fix, and this is its
// shape here: everything the browser can start downloading goes first, the
// title and the data-shaped head after the data, then the body.
//
// A status code cannot follow a 200. So a route the build knows is guarded is
// never flushed early -- it answers exactly as before -- and a record that
// turns out hidden after the flush is a page marked noindex rather than a 404.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart'
    show DVPageData, DVPageDataResolver, DVPageRequest, DVPageVisibility;
import 'package:dartvel_core/http.dart';
import 'package:dartvel_shelf/src/ssr_helper.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String shell = '<!DOCTYPE html>\n<html>\n<head>\n'
    '<base href="/">\n'
    '<meta charset="UTF-8">\n'
    '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
    '<link rel="icon" type="image/png" href="favicon.png"/>\n'
    '<!-- dartvel:seo -->\n<title>Shell</title>\n<!-- /dartvel:seo -->\n'
    '<link rel="preconnect" href="https://www.gstatic.com" crossorigin>\n'
    '<link rel="preload" href="main.dart.js_2.part.js" as="script">\n'
    '<style id="dartvel-splash-style">#s{background:#fff}</style>\n'
    '</head>\n<body><div id="dartvel-splash"></div>'
    '<script src="flutter_bootstrap.js" async></script></body>\n</html>\n';

/// A built web-server directory.
Directory site({Object streaming = 'shell'}) {
  final Directory root =
      Directory.systemTemp.createTempSync('dartvel_shell_stream_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'index.html')).writeAsStringSync(shell);
  File(p.join(root.path, 'dartvel_routes.json')).writeAsStringSync(jsonEncode(
    <String, Object?>{
      'siteUrl': 'https://example.com',
      'server': <String, Object?>{'streaming': streaming},
      'routes': <String, Object?>{
        '/products/:id': <String, Object?>{
          'title': 'A product',
          'text': <String>['Our products'],
        },
        '/account/:id': <String, Object?>{'title': 'Account', 'guarded': true},
        '/partner/:id': <String, Object?>{
          'location': 'https://partner.example.com/p/:id',
        },
      },
    },
  ));
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

/// The first chunk, and a way to read the rest.
Future<(String, Future<String> Function())> firstChunk(Response response) async {
  final StreamIterator<List<int>> body =
      StreamIterator<List<int>>(response.body!.stream);
  expect(await body.moveNext(), isTrue);
  final String first = utf8.decode(body.current);
  Future<String> rest() async {
    final StringBuffer out = StringBuffer();
    while (await body.moveNext()) {
      out.write(utf8.decode(body.current));
    }
    return out.toString();
  }

  return (first, rest);
}

void main() {
  test('the shell is on the wire before the page data resolves', () async {
    final Completer<DVPageData> gate = Completer<DVPageData>();
    final Response response =
        await get(site(), '/products/5', (DVPageRequest r) => gate.future);

    expect(response.status, 200);
    expect(response.isStream, isTrue);
    final (String first, Future<String> Function() rest) =
        await firstChunk(response);

    expect(gate.isCompleted, isFalse,
        reason: 'the first chunk must not wait for the data');
    expect(first, startsWith('<!DOCTYPE html>'));
    expect(first, contains('<base href="/">'));
    expect(first, contains('<meta charset="UTF-8">'));
    expect(first, contains('rel="preconnect"'));
    expect(first, contains('href="main.dart.js_2.part.js"'));
    expect(first, contains('dartvel-splash-style'));
    // The bootstrap script is in the body, which cannot go out until the data
    // has; a preload for it lets the browser fetch it now.
    expect(first,
        contains('<link rel="preload" href="flutter_bootstrap.js" as="script">'));
    expect(first, isNot(contains('<title>')));
    expect(first, isNot(contains('</head>')));

    gate.complete(const DVPageData(
      title: 'Product 5',
      text: <String>['In stock'],
    ));
    final String after = await rest();
    expect(after, contains('<title>Product 5</title>'));
    expect(after, contains('In stock'));
    expect(after, contains('</head>'));
    expect(after, endsWith('</html>\n'));

    final String page = first + after;
    // Assembled from two renders, and still one of everything.
    for (final String once in <String>[
      '<base ',
      'main.dart.js_2.part.js',
      'dartvel-splash-style',
      '<title>',
      '</head>',
      '<body>',
    ]) {
      expect(RegExp(RegExp.escape(once)).allMatches(page), hasLength(1),
          reason: once);
    }
    expect(page, isNot(contains('noindex')));
  });

  test('the title comes before the body', () async {
    final Response response = await get(site(), '/products/5',
        (DVPageRequest r) async => const DVPageData(title: 'Product 5'));
    final List<String> chunks = <String>[
      for (final List<int> c in await response.body!.stream.toList())
        utf8.decode(c),
    ];
    expect(chunks, hasLength(3));
    expect(chunks[1], contains('<title>Product 5</title>'));
    expect(chunks[1], endsWith('</head>'));
    expect(chunks[2], startsWith('\n<body>'));
  });

  test('a hidden record after the flush is a page marked noindex', () async {
    final Response response = await get(site(), '/products/5',
        (DVPageRequest r) async => const DVPageData(
              title: 'Secret product',
              text: <String>['Secret stock'],
              visibility: DVPageVisibility.hidden,
            ));
    // 200 is already on the wire when the record is found to be hidden: a
    // soft 404, which is what this mode trades for the early head.
    expect(response.status, 200);
    final String page = (await response.body!.stream.toList())
        .map(utf8.decode)
        .join();
    expect(page, contains('<meta name="robots" content="noindex">'));
    expect(page, isNot(contains('Secret')));
    expect(page, contains('<title>Shell</title>'));
  });

  test('a resolver that throws still ends the page, marked noindex', () async {
    final Response response = await get(site(), '/products/5',
        (DVPageRequest r) async => throw StateError('database is down'));
    final String page = (await response.body!.stream.toList())
        .map(utf8.decode)
        .join();
    expect(page, contains('<meta name="robots" content="noindex">'));
    // The route's own title from the build, so the page is still a page.
    expect(page, contains('<title>A product</title>'));
    expect(page, endsWith('</html>\n'));
  });

  test('a guarded route is not flushed early, so it keeps its status',
      () async {
    final Completer<DVPageData> gate = Completer<DVPageData>();
    var answered = false;
    final Future<Response> pending = get(site(), '/account/7',
            (DVPageRequest r) => gate.future)
        .then((Response r) {
      answered = true;
      return r;
    });

    await pumpEventQueue();
    expect(answered, isFalse,
        reason: 'a guarded route must wait for the data to know its status');

    gate.complete(const DVPageData(
      title: 'Account 7',
      visibility: DVPageVisibility.unauthorized,
    ));
    final Response response = await pending;
    expect(response.status, 401);
  });

  test('a federated route is still redirected, never flushed', () async {
    final Response response = await get(site(), '/partner/3',
        (DVPageRequest r) async => const DVPageData(title: 'x'));
    expect(response.status, 302);
    expect(response.headers.get('location'), 'https://partner.example.com/p/3');
  });

  test('with `true` the response still waits for the data, as before',
      () async {
    final Completer<DVPageData> gate = Completer<DVPageData>();
    var answered = false;
    final Future<Response> pending = get(site(streaming: true), '/products/5',
            (DVPageRequest r) => gate.future)
        .then((Response r) {
      answered = true;
      return r;
    });

    await pumpEventQueue();
    expect(answered, isFalse);
    gate.complete(const DVPageData(title: 'Product 5'));
    final List<List<int>> chunks = await (await pending).body!.stream.toList();
    expect(chunks, hasLength(2));
    expect(utf8.decode(chunks.first), contains('<title>Product 5</title>'));
  });
}
