import 'dart:convert';
import 'dart:io';
import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late ServerHandle server;
  late HttpClient client;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('native-static-');
    await File('${dir.path}/file.txt').writeAsString('0123456789');
    server = await serve((_) async => Response.text('missing', status: 404),
      staticDir: dir.path, port: 0, compression: false);
    client = HttpClient();
  });
  tearDown(() async { client.close(force: true); await server.stop(); await dir.delete(recursive: true); });
  Future<HttpClientResponse> get([Map<String, String> headers = const {}]) async {
    final req = await client.getUrl(Uri.parse('http://127.0.0.1:${server.port}/static/file.txt'));
    headers.forEach(req.headers.set);
    return req.close();
  }
  test('starting another server does not change this servers static root', () async {
    final other = await serve((_) async => Response.text('other'), port: 0);
    addTearDown(other.stop);
    final res = await get();
    expect(res.statusCode, 200);
    expect(await res.transform(utf8.decoder).join(), '0123456789');
  });
  test('native static ranges and unsatisfiable ranges', () async {
    final res = await get({'range': 'bytes=2-5'});
    expect(res.statusCode, 206);
    expect(res.headers.value('content-range'), 'bytes 2-5/10');
    expect(await res.transform(utf8.decoder).join(), '2345');
    final bad = await get({'range': 'bytes=30-40'});
    expect(bad.statusCode, 416); await bad.drain<void>();
  });
  test('native static ETag and modification date revalidation', () async {
    final res = await get(); await res.drain<void>();
    expect(res.headers.value('etag'), isNotNull);
    final cached = await get({'if-none-match': res.headers.value('etag')!});
    expect(cached.statusCode, 304); await cached.drain<void>();
    final date = await get({'if-modified-since': res.headers.value('last-modified')!});
    expect(date.statusCode, 304); await date.drain<void>();
  });
  test('native static refuses symlinks outside its root', () async {
    final outside = await File('${dir.parent.path}/${dir.uri.pathSegments.where((s) => s.isNotEmpty).last}-secret').writeAsString('secret');
    addTearDown(() => outside.delete());
    await File('${dir.path}/file.txt').delete();
    await Link('${dir.path}/file.txt').create(outside.path);
    final res = await get();
    expect(res.statusCode, 404); await res.drain<void>();
  });
}
