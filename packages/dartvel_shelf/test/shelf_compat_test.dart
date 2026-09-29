import 'dart:io';
import 'package:dartvel_shelf/dartvel_shelf.dart' as dv;
import 'package:dartvel_shelf/shelf.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_static/shelf_static.dart';
import 'package:test/test.dart';

void main() {
  test('unchanged Pipeline and Cascade preserve context, encoding and cookies', () async {
    final pipeline = const shelf.Pipeline().addMiddleware((next) => (req) =>
      next(req.change(context: {'marker': 'passed'}))).addHandler(
        shelf.Cascade().add((_) => shelf.Response.notFound('miss')).add((req) async =>
          shelf.Response.ok('${req.context['marker']}:${await req.readAsString()}',
            headers: {'set-cookie': ['a=1', 'b=2']})).handler);
    final server = await dv.serve(fromShelf(pipeline), port: 0, compression: false);
    final client = HttpClient();
    addTearDown(() async { client.close(force: true); await server.stop(); });
    final req = await client.postUrl(Uri.parse('http://127.0.0.1:${server.port}/'));
    req.headers.contentType = ContentType('text', 'plain', charset: 'iso-8859-1');
    req.add([233]);
    final res = await req.close();
    expect(res.headers['set-cookie'], ['a=1', 'b=2']);
    expect(await res.transform(const SystemEncoding().decoder).join(), 'passed:é');
  });

  test('unchanged shelf_static serves ranges, conditional requests and default documents', () async {
    final dir = await Directory.systemTemp.createTemp('shelf-compat-');
    await File('${dir.path}/index.txt').writeAsString('0123456789');
    // shelf_static truncates milliseconds but retains microseconds.
    await File('${dir.path}/index.txt').setLastModified(DateTime.utc(2026, 1, 1));
    final server = await dv.serve(fromShelf(createStaticHandler(dir.path,
      defaultDocument: 'index.txt')), port: 0, compression: false);
    final client = HttpClient();
    addTearDown(() async { client.close(force: true); await server.stop(); await dir.delete(recursive: true); });
    final uri = Uri.parse('http://127.0.0.1:${server.port}/');
    final req = await client.getUrl(uri);
    req.headers.set('range', 'bytes=2-5');
    final res = await req.close();
    expect(res.statusCode, 206);
    expect(await res.transform(const SystemEncoding().decoder).join(), '2345');
    final cached = await client.getUrl(uri);
    cached.headers.set('if-modified-since', res.headers.value('last-modified')!);
    final hit = await cached.close();
    expect(hit.statusCode, 304);
    await hit.drain<void>();
  });
}
