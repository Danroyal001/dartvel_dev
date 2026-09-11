// Shell-first rendering through the real native server.
//
// ssr_shell_streaming_test.dart proves the handler produces the shell before
// the data. That proves nothing about what a browser receives: the Rust
// runtime gathers the whole body of a response it is not told is a stream and
// sends it with a content-length, which would put the early head back behind
// the data. This asks the running server, over a socket, and holds the data
// back until the first bytes have arrived.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show DVPageData, DVPageRequest;
import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:dartvel_shelf/src/ssr_helper.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String shell = '<!DOCTYPE html>\n<html>\n<head>\n<base href="/">\n'
    '<meta charset="UTF-8">\n'
    '<!-- dartvel:seo -->\n<title>Shell</title>\n<!-- /dartvel:seo -->\n'
    '<link rel="preload" href="main.dart.js_2.part.js" as="script">\n'
    '</head>\n<body><script src="flutter_bootstrap.js" async></script>'
    '</body>\n</html>\n';

void main() {
  test('the early head reaches the socket while the data is still pending',
      () async {
    final Directory root =
        Directory.systemTemp.createTempSync('dartvel_shell_native_');
    addTearDown(() => root.deleteSync(recursive: true));
    File(p.join(root.path, 'index.html')).writeAsStringSync(shell);
    File(p.join(root.path, 'dartvel_routes.json')).writeAsStringSync(jsonEncode(
      <String, Object?>{
        'server': <String, Object?>{'streaming': 'shell'},
        'routes': <String, Object?>{
          '/products/:id': <String, Object?>{'title': 'A product'},
        },
      },
    ));

    final Completer<DVPageData> gate = Completer<DVPageData>();
    final ServerHandle server = await serve(
      (Request req) => handleSsrFallback(req, root.path,
          pageData: (DVPageRequest r) => gate.future),
      host: '127.0.0.1',
      port: 0,
    );
    final HttpClient client = HttpClient();
    addTearDown(() async {
      if (!gate.isCompleted) gate.complete(const DVPageData(title: 'x'));
      client.close(force: true);
      await server.stop();
    });

    final HttpClientResponse response = await (await client
            .getUrl(Uri.parse('http://127.0.0.1:${server.port}/products/5')))
        .close()
        .timeout(const Duration(seconds: 10));
    expect(response.statusCode, 200);

    final StreamIterator<String> body =
        StreamIterator<String>(response.transform(utf8.decoder));
    final StringBuffer early = StringBuffer();
    // Read until the early head is in: a socket may split one write in two.
    while (!early.toString().contains('main.dart.js_2.part.js')) {
      expect(await body.moveNext().timeout(const Duration(seconds: 10)),
          isTrue);
      early.write(body.current);
    }
    expect(gate.isCompleted, isFalse,
        reason: 'the bytes arrived before the data existed');
    expect(early.toString(), isNot(contains('<title>')));

    gate.complete(const DVPageData(title: 'Product 5'));
    final StringBuffer rest = StringBuffer();
    while (await body.moveNext().timeout(const Duration(seconds: 10))) {
      rest.write(body.current);
    }
    expect(rest.toString(), contains('<title>Product 5</title>'));
    expect(rest.toString(), endsWith('</html>\n'));
  });
}
