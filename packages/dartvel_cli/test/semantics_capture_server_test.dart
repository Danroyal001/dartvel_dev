// The little server the semantics capture drives a browser against.
//
// It serves `build/web`, which after `flutter build web` holds one
// index.html at the root and nothing else -- the per-route index.html files
// are written later, from the very capture this server exists to enable. So a
// plain static handler answers 404 for every route but `/`, the Flutter app
// never boots on those pages, no semantics tree is ever built, and the capture
// reports 1 of 4.
//
// That is what "Captured 1 of 4 routes" was: not a slow page or a missing
// browser, but three requests that never reached the application at all.
import 'dart:io';

import 'package:dartvel_cli/src/build/semantics_capture.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

void main() {
  late Directory web;
  late HttpServer server;
  late String base;

  setUp(() async {
    web = Directory.systemTemp.createTempSync('dv_capture_');
    File('${web.path}/index.html').writeAsStringSync('<html>app shell</html>');
    File('${web.path}/main.dart.js').writeAsStringSync('console.log(1);');

    server = await shelf_io.serve(
      dvCaptureHandler(web.path),
      InternetAddress.loopbackIPv4,
      0,
    );
    base = 'http://${server.address.host}:${server.port}';
  });

  tearDown(() async {
    await server.close(force: true);
    web.deleteSync(recursive: true);
  });

  test('the root serves the shell', () async {
    final http.Response response = await http.get(Uri.parse('$base/'));
    expect(response.statusCode, 200);
    expect(response.body, contains('app shell'));
  });

  test('a route with no file on disk still serves the shell', () async {
    // The whole fix. Without it this is a 404, the application never boots,
    // and the route captures nothing.
    final http.Response response = await http.get(Uri.parse('$base/docs'));

    expect(response.statusCode, 200);
    expect(response.body, contains('app shell'));
  });

  test('a nested route serves the shell too', () async {
    final http.Response response =
        await http.get(Uri.parse('$base/docs/getting-started'));
    expect(response.statusCode, 200);
    expect(response.body, contains('app shell'));
  });

  test('a real file is still served as itself', () async {
    // The fallback must not swallow the application's own assets: answering
    // main.dart.js with HTML would stop the app booting on every route.
    final http.Response response =
        await http.get(Uri.parse('$base/main.dart.js'));

    expect(response.statusCode, 200);
    expect(response.body, contains('console.log'));
  });

  test('a missing asset is a 404, not the shell', () async {
    // An asset request answered with HTML fails in a way that looks like a
    // corrupt file rather than a missing one, and Flutter's loader hangs on
    // it instead of reporting.
    for (final String path in <String>[
      '/missing.js',
      '/assets/nope.png',
      '/canvaskit/canvaskit.wasm',
      '/style.css',
    ]) {
      final http.Response response = await http.get(Uri.parse('$base$path'));
      expect(response.statusCode, 404, reason: path);
    }
  });

  test('a route that looks like a file but is not gets the shell', () async {
    // Routes have no extension; assets do. `/pricing` is a route,
    // `/pricing.js` is a missing asset.
    expect((await http.get(Uri.parse('$base/pricing'))).statusCode, 200);
    expect((await http.get(Uri.parse('$base/pricing.js'))).statusCode, 404);
  });
}
