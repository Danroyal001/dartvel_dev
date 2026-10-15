// `dartvel dev --release` serves a page published from Studio the way the
// web-server binary does: with what the page says about itself in its head,
// in the sitemap when it asks to be, and its media library's files at their
// public address.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/web_server.dart';
import 'package:dartvel_core/dartvel.dart'
    show
        DVLocalFileStorageAdapter,
        DVPublishedPages,
        DVRecordAdapter,
        MemoryDVDatabaseAdapter,
        dvStudioPagesShape,
        dvStudioPagesTable;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Handler handler;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('dartvel_dev_seo_');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/index.html').writeAsStringSync(
        '<html><head><title>Harbour</title></head><body></body></html>');
    File('${root.path}/dartvel_routes.json').writeAsStringSync(jsonEncode(
      <String, Object?>{
        'siteUrl': 'https://harbour.example',
        'routes': <String, Object?>{
          '/': <String, Object?>{'title': 'Home'},
        },
      },
    ));
    final MemoryDVDatabaseAdapter database = MemoryDVDatabaseAdapter();
    final DVRecordAdapter records = DVRecordAdapter.over(database);
    await records.ensure(dvStudioPagesShape);
    await records.insert(dvStudioPagesTable, <String, Object?>{
      'route': '/sale',
      'title': 'Autumn sale',
      'document': jsonEncode(<String, Object?>{
        'route': '/sale',
        'title': 'Autumn sale',
        'description': 'Our autumn sale.',
      }),
    });
    final DVLocalFileStorageAdapter media =
        DVLocalFileStorageAdapter(root: '${root.path}/media-store');
    await media.put('media/logo.png', <int>[0x89, 0x50, 0x4E, 0x47]);
    handler = dvWebServerHandler(
      webRoot: root.path,
      publishedPages: DVPublishedPages(database: () => database, media: media),
    );
  });

  Future<Response> get(String path) async =>
      await handler(Request('GET', Uri.parse('http://localhost:8080$path')));

  test('a Studio page is served with its own description', () async {
    final Response page = await get('/sale');
    expect(page.statusCode, 200);
    final String html = await page.readAsString();
    expect(html, contains('<title>Autumn sale</title>'));
    expect(html, contains('content="Our autumn sale."'));
  });

  test('the sitemap lists it', () async {
    final Response sitemap = await get('/sitemap.xml');
    expect(sitemap.statusCode, 200);
    expect(await sitemap.readAsString(),
        contains('<loc>https://harbour.example/sale</loc>'));
  });

  test('a media library file is served at its public address', () async {
    final Response file = await get('/_dartvel/media/logo.png');
    expect(file.statusCode, 200);
    expect(file.headers['x-content-type-options'], 'nosniff');
  });
}
