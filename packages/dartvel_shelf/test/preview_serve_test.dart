// Preview Environments, where the server starts.
//
// The access gate has to sit outside everything serve() answers, not just the
// router it was handed: the built site's files and its assembled pages are
// served by serve() itself, around the router, and a gate installed on the
// router alone would leave a link-only preview's whole web build readable to
// anybody and indexable by everything.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart'
    show
        DVPreviewDeployment,
        DVPreviewIdentity,
        DVPreviewServer,
        DVPreviewVisibility;
import 'package:dartvel_shelf/dartvel_shelf.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final DVPreviewIdentity id = DVPreviewIdentity.forBranch(
  app: 'shop',
  branch: 'feature/cart',
);

Map<String, String> previewEnvironment(
  DVPreviewVisibility visibility, {
  String? linkToken,
}) => DVPreviewDeployment(
  identity: id,
  visibility: visibility,
  secrets: const <String, String>{},
  linkDigest: linkToken == null
      ? null
      : sha256.convert(utf8.encode(linkToken)).toString(),
  productionOrigin: 'https://shop.example',
  productionDatabase: 'shop',
).variables;

const String _index =
    '<!DOCTYPE html><html><head><title>Shop</title>'
    '<link rel="canonical" href="https://preview.example/somewhere">'
    '</head><body><div id="app"></div></body></html>';

void main() {
  late Directory site;

  setUp(() {
    site = Directory.systemTemp.createTempSync('dv_preview_serve_');
    File(p.join(site.path, 'index.html')).writeAsStringSync(_index);
    File(p.join(site.path, 'app.js')).writeAsStringSync('console.log(1)');
  });

  tearDown(() {
    DVPreviewServer.reset();
    site.deleteSync(recursive: true);
  });

  Router router() =>
      Router()..get('/api/ping', (Request req) async => Response.text('pong'));

  Future<({int status, String? robots, String body})> get(
    int port,
    String path,
  ) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port$path'),
      );
      request.followRedirects = false;
      final HttpClientResponse response = await request.close();
      final String body = await response.transform(utf8.decoder).join();
      return (
        status: response.statusCode,
        robots: response.headers.value('x-robots-tag'),
        body: body,
      );
    } finally {
      client.close(force: true);
    }
  }

  test(
    'in a preview every response is noindex, files and pages included',
    () async {
      DVPreviewServer.start(previewEnvironment(DVPreviewVisibility.public));
      final ServerHandle server = await serve(
        router().call,
        host: '127.0.0.1',
        port: 0,
        spaRoot: site.path,
      );
      addTearDown(server.stop);

      final ping = await get(server.port, '/api/ping');
      expect(ping.status, 200);
      expect(ping.robots, contains('noindex'));

      final asset = await get(server.port, '/app.js');
      expect(asset.body, contains('console.log(1)'));
      expect(
        asset.robots,
        contains('noindex'),
        reason: 'a file served from the site is a response too',
      );

      final robots = await get(server.port, '/robots.txt');
      expect(robots.body, contains('Disallow: /'));

      final page = await get(server.port, '/products/42');
      expect(page.robots, contains('noindex'));
      expect(page.body, contains('https://shop.example/products/42'));
      expect(page.body, isNot(contains('preview.example')));
    },
  );

  test('a link preview serves none of its site without the link', () async {
    DVPreviewServer.start(
      previewEnvironment(DVPreviewVisibility.link, linkToken: 'tok3n'),
    );
    final ServerHandle server = await serve(
      router().call,
      host: '127.0.0.1',
      port: 0,
      spaRoot: site.path,
    );
    addTearDown(server.stop);

    expect((await get(server.port, '/api/ping')).status, 404);
    final asset = await get(server.port, '/app.js');
    expect(asset.status, 404);
    expect(asset.body, isNot(contains('console.log')));
    expect((await get(server.port, '/')).body, isNot(contains('id="app"')));
  });

  test('outside a preview the server installs nothing', () async {
    final ServerHandle server = await serve(
      router().call,
      host: '127.0.0.1',
      port: 0,
      spaRoot: site.path,
    );
    addTearDown(server.stop);

    final ping = await get(server.port, '/api/ping');
    expect(ping.status, 200);
    expect(ping.robots, isNull);
    expect((await get(server.port, '/app.js')).robots, isNull);
    expect(
      (await get(server.port, '/robots.txt')).body,
      isNot(contains('Disallow')),
    );
    expect(
      (await get(server.port, '/products/42')).body,
      contains('https://preview.example/somewhere'),
    );
  });
}
