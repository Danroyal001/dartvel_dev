// `dartvel dev --release` serves a web-server build through the same handler
// shape the binary uses, so a page that is cross-origin isolated in
// production is isolated in the preview too -- otherwise skwasm runs one
// thread locally and two in production, and what was tested is not what
// ships.
import 'dart:io';

import 'package:dartvel_cli/src/build/server_options.dart';
import 'package:dartvel_cli/src/build/web_server.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

void main() {
  test('the preview sends the headers the build decided on', () async {
    final Directory root =
        await Directory.systemTemp.createTemp('dartvel_ws_isolation_');
    addTearDown(() => root.deleteSync(recursive: true));
    File(p.join(root.path, 'index.html'))
        .writeAsStringSync('<!DOCTYPE html><html><head></head><body></body></html>');
    File(p.join(root.path, 'main.dart.wasm')).writeAsStringSync('wasm');

    final DVServerOptions isolated =
        const DVServerOptions().withCrossOriginIsolation(true);
    final HttpServer server = await shelf_io.serve(
      dvWebServerHandler(
          webRoot: root.path, securityHeaders: isolated.securityHeaders),
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));

    final HttpClient client = HttpClient();
    addTearDown(client.close);
    for (final String path in <String>['/', '/main.dart.wasm']) {
      final HttpClientResponse response = await (await client.getUrl(
              Uri.parse('http://127.0.0.1:${server.port}$path')))
          .close();
      await response.drain<void>();
      expect(response.headers.value('cross-origin-opener-policy'),
          'same-origin', reason: path);
      expect(response.headers.value('cross-origin-embedder-policy'),
          'credentialless', reason: path);
      expect(response.headers.value('x-content-type-options'), 'nosniff');
    }
  });
}
