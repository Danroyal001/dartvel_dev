// A site carried in a pack, served by the real native server.
//
// asset_response_test.dart proves what the handler answers. This proves what
// reaches the socket: the Rust side compresses responses on the way out, and
// a body already in brotli must pass through untouched, a range must not be
// gzipped, and Vary must be said once. And the page itself -- the shell and
// the manifest -- has to come from the pack, with no file of the site on
// disk anywhere.
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_core/binary_payload.dart';
import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:dartvel_shelf/src/native_codec.dart';
import 'package:dartvel_shelf/src/native_library.dart' show nativeServerLibraryLocation;
import 'package:dartvel_shelf/src/ssr_helper.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory work;
  late ServerHandle server;
  late HttpClient client;
  late DVNativeCodec codec;
  const String root = '/nonexistent/server/web';

  final Uint8List js = Uint8List.fromList(utf8.encode(
      List<String>.generate(3000, (int i) => 'function f$i(){return $i}').join('\n')));
  const String shell = '<!DOCTYPE html><html><head><title>Shell</title></head>'
      '<body><script src="flutter_bootstrap.js" async></script></body></html>';

  setUpAll(() async {
    final ({String subdir, String name}) location = nativeServerLibraryLocation();
    codec = DVNativeCodec.of(ffi.DynamicLibrary.open('lib/native/${location.subdir}/${location.name}'))!;
    work = Directory.systemTemp.createTempSync('dv_embedded_site_');
    DVAssetPackEntry br(String path, Uint8List bytes) => DVAssetPackEntry(path, bytes,
        stored: codec.encode(DVAssetEncoding.br, bytes), encoding: DVAssetEncoding.br);
    final Uint8List pack = dvWriteAssetPack(<DVAssetPackEntry>[
      br('web/main.dart.js', js),
      br('web/index.html', Uint8List.fromList(utf8.encode(shell))),
      br('web/dartvel_routes.json', Uint8List.fromList(utf8.encode(jsonEncode(<String, Object?>{
        'routes': <String, Object?>{
          '/docs': <String, Object?>{'title': 'The docs', 'text': <String>['Read me']},
        },
      })))),
    ]);
    final File server0 = File(p.join(work.path, 'server'))..writeAsBytesSync(pack);
    DVAssetSources.register(
        root, DVPackedAssets(DVAssetPack.open(server0.path, offset: 0, length: pack.length)!, prefix: 'web/'));
    server = await serve(
      (Request req) async => Response(404, body: const Stream<List<int>>.empty()),
      host: '127.0.0.1',
      port: 0,
      spaRoot: root,
    );
    client = HttpClient()..autoUncompress = false;
  });

  tearDownAll(() async {
    client.close(force: true);
    await server.stop();
    DVAssetSources.clear();
    work.deleteSync(recursive: true);
  });

  Future<(HttpClientResponse, Uint8List)> get(String path, Map<String, String> headers) async {
    final HttpClientRequest request =
        await client.getUrl(Uri.parse('http://127.0.0.1:${server.port}$path'));
    // dart:io asks for gzip unless told otherwise.
    request.headers.removeAll(HttpHeaders.acceptEncodingHeader);
    headers.forEach(request.headers.set);
    final HttpClientResponse response = await request.close();
    final BytesBuilder out = BytesBuilder(copy: false);
    await for (final List<int> chunk in response) {
      out.add(chunk);
    }
    return (response, out.takeBytes());
  }

  test('brotli goes through as it was kept, with one Vary', () async {
    final (HttpClientResponse r, Uint8List bytes) = await get('/main.dart.js', <String, String>{'accept-encoding': 'br'});
    expect(r.statusCode, 200);
    expect(r.headers.value('content-encoding'), 'br');
    expect(r.headers['vary'], hasLength(1));
    expect(codec.decode(DVAssetEncoding.br, bytes, js.length), js);
    expect(r.headers.contentLength, bytes.length);
  });

  test('a gzip client gets the file gzipped by the transport, with one Vary', () async {
    final (HttpClientResponse r, Uint8List bytes) = await get('/main.dart.js', <String, String>{'accept-encoding': 'gzip'});
    expect(r.headers.value('content-encoding'), 'gzip');
    expect(r.headers['vary'], hasLength(1));
    expect(gzip.decode(bytes), js);
    expect(r.headers.value('etag'), startsWith('W/'));
  });

  test('a client that takes neither gets the file itself', () async {
    final (HttpClientResponse r, Uint8List bytes) = await get('/main.dart.js', <String, String>{});
    expect(r.headers.value('content-encoding'), isNull);
    expect(bytes, js);
  });

  test('a revalidation is a 304 on the wire', () async {
    final (HttpClientResponse first, _) = await get('/main.dart.js', <String, String>{'accept-encoding': 'br'});
    final (HttpClientResponse again, Uint8List bytes) = await get('/main.dart.js',
        <String, String>{'accept-encoding': 'br', 'if-none-match': first.headers.value('etag')!});
    expect(again.statusCode, 304);
    expect(bytes, isEmpty);
  });

  test('a range is sent as it is, never compressed around', () async {
    final (HttpClientResponse r, Uint8List bytes) =
        await get('/main.dart.js', <String, String>{'accept-encoding': 'gzip, br', 'range': 'bytes=5-24'});
    expect(r.statusCode, 206);
    expect(r.headers.value('content-encoding'), isNull);
    expect(bytes, js.sublist(5, 25));
  });

  test('a page is rendered from the shell and manifest in the pack', () async {
    final (HttpClientResponse r, Uint8List bytes) = await get('/docs', <String, String>{});
    expect(r.statusCode, 200);
    final String page = utf8.decode(bytes);
    expect(page, contains('The docs'));
    expect(page, contains('flutter_bootstrap.js'));
    final (HttpClientResponse missing, _) = await get('/nothing-here', <String, String>{});
    expect(missing.statusCode, 404);
  });

  test('nothing of the site was written to disk', () {
    expect(Directory('/nonexistent').existsSync(), isFalse);
    expect(work.listSync().map((FileSystemEntity e) => p.basename(e.path)), <String>['server']);
  });
}
