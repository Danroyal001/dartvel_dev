// `dartvel preview` under `dartvel.web.server.streaming: shell`.
//
// The deployed server sends the shell's head before a route's data resolves.
// The preview server did not: it had only the older split, head after the
// data. A developer previewing `shell` saw every page wait on the resolver
// and deployed something that behaved differently -- the same drift an
// earlier comment in dartvel_shelf's streaming test records happening once
// already, the other way round. Both now stream through one function in
// core.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/web_server.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

const String shell = '<!DOCTYPE html>\n<html>\n<head>\n'
    '<base href="/">\n'
    '<meta charset="UTF-8">\n'
    '<!-- dartvel:seo -->\n<title>Shell</title>\n<!-- /dartvel:seo -->\n'
    '</head>\n<body>'
    '<script src="flutter_bootstrap.js" async></script></body>\n</html>\n';

Directory site({Object streaming = 'shell'}) {
  final Directory root =
      Directory.systemTemp.createTempSync('dartvel_preview_shell_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'index.html')).writeAsStringSync(shell);
  File(p.join(root.path, 'dartvel_routes.json')).writeAsStringSync(jsonEncode(
    <String, Object?>{
      'server': <String, Object?>{'streaming': streaming},
      'routes': <String, Object?>{
        '/products/:id': <String, Object?>{'title': 'A product'},
        '/account/:id': <String, Object?>{'title': 'Account', 'guarded': true},
      },
    },
  ));
  File(p.join(root.path, 'dartvel_prefetch.json')).writeAsStringSync(jsonEncode(
    <String, Object?>{
      'routes': <String, Object?>{
        '/products/:id': <String, Object?>{
          'scripts': <String>['main.dart.js_7.part.js'],
          'images': <Object?>[],
        },
      },
    },
  ));
  return root;
}

Future<Response> get(Directory root, String path, DVPageDataResolver resolver) async =>
    await dvWebServerHandler(webRoot: root.path, pageData: resolver)(
      Request('GET', Uri.parse('http://localhost$path')),
    );

void main() {
  test('the head goes out before gated data, with the route\'s parts', () async {
    final Completer<DVPageData> gate = Completer<DVPageData>();
    final Response response =
        await get(site(), '/products/5', (DVPageRequest r) => gate.future);

    expect(response.statusCode, 200);
    final StreamIterator<List<int>> body =
        StreamIterator<List<int>>(response.read());
    expect(await body.moveNext(), isTrue);
    final String first = utf8.decode(body.current);

    expect(gate.isCompleted, isFalse,
        reason: 'the first chunk must not wait for the data');
    expect(first, contains('<base href="/">'));
    expect(first,
        contains('<link rel="preload" href="main.dart.js_7.part.js" as="script">'));
    expect(first,
        contains('<link rel="preload" href="flutter_bootstrap.js" as="script">'));
    expect(first, isNot(contains('<title>')));

    gate.complete(const DVPageData(title: 'Product 5'));
    final StringBuffer rest = StringBuffer();
    while (await body.moveNext()) {
      rest.write(utf8.decode(body.current));
    }
    expect(rest.toString(), contains('<title>Product 5</title>'));
    expect(rest.toString(), endsWith('</html>\n'));
  });

  test('a guarded route waits for its data and keeps its status', () async {
    final Completer<DVPageData> gate = Completer<DVPageData>();
    var answered = false;
    final Future<Response> pending =
        get(site(), '/account/7', (DVPageRequest r) => gate.future)
            .then((Response r) {
      answered = true;
      return r;
    });

    await pumpEventQueue();
    expect(answered, isFalse);
    gate.complete(const DVPageData(
      title: 'Account 7',
      visibility: DVPageVisibility.unauthorized,
    ));
    expect((await pending).statusCode, 401);
  });

  test('a hidden record after the flush is marked noindex', () async {
    final Response response = await get(
      site(),
      '/products/5',
      (DVPageRequest r) async => const DVPageData(
        title: 'Secret',
        visibility: DVPageVisibility.hidden,
      ),
    );
    expect(response.statusCode, 200);
    final String page = await response.readAsString();
    expect(page, contains('<meta name="robots" content="noindex">'));
    expect(page, isNot(contains('Secret')));
  });

  test('without shell, the head still names the route\'s parts', () async {
    final Response response = await get(
      site(streaming: false),
      '/products/5',
      (DVPageRequest r) async => const DVPageData(title: 'Product 5'),
    );
    final String page = await response.readAsString();
    expect(page.indexOf('main.dart.js_7.part.js'), isNonNegative);
    expect(page.indexOf('main.dart.js_7.part.js'),
        lessThan(page.indexOf('</head>')));
  });
}
