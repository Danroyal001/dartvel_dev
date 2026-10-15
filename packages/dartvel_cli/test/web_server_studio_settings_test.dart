// `dartvel dev --release` applies Studio's Settings as the web-server binary
// does: maintenance mode closes the site's pages, and the default description
// is the site's.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/web_server.dart';
import 'package:dartvel_core/dartvel.dart' as core
    show
        DVAdminMount,
        DVAdminServer,
        DVPublishedPages,
        Headers,
        MemoryDVDatabaseAdapter,
        Request;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late core.MemoryDVDatabaseAdapter database;
  late core.DVAdminServer studio;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dartvel_dev_settings_');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/index.html').writeAsStringSync(
        '<html><head><title>Harbour</title></head><body></body></html>');
    File('${root.path}/dartvel_routes.json').writeAsStringSync(jsonEncode(
      <String, Object?>{
        'siteUrl': 'https://harbour.example',
        'site': <String, Object?>{'description': 'Built description.'},
        'routes': <String, Object?>{
          '/': <String, Object?>{'title': 'Home'},
        },
      },
    ));
    database = core.MemoryDVDatabaseAdapter();
    studio = core.DVAdminServer(
      mount: const core.DVAdminMount(
          path: '/__studio', enabled: true, requiresAuth: false),
      root: root.path,
      database: database,
    );
  });

  Future<void> settle(Map<String, Object?> settings) async {
    final saved = (await studio.respond(core.Request(
      method: 'PUT',
      url: Uri.parse('http://localhost:8080/__studio/api/settings'),
      headers: core.Headers(<String, String>{
        'content-type': 'application/json',
        'x-dartvel-csrf-token': 'abcdefghijklmnopqrstuvwxyz012345',
      }),
      bodyStream: Stream<List<int>>.value(utf8.encode(
          jsonEncode(<String, Object?>{'siteTitle': 'Harbour', ...settings}))),
    )))!;
    expect(saved.status, 200);
  }

  Future<Response> get(String path, {bool admitted = false}) async =>
      await dvWebServerHandler(
        webRoot: root.path,
        publishedPages: core.DVPublishedPages(
          database: () => database,
          passesMaintenance: (_) async => admitted,
        ),
      )(Request('GET', Uri.parse('http://localhost:8080$path')));

  test('maintenance closes the pages, with the message Settings give',
      () async {
    await settle(<String, Object?>{
      'maintenanceMode': true,
      'maintenanceMessage': 'Back at noon.',
    });
    final Response page = await get('/');
    expect(page.statusCode, 503);
    expect(await page.readAsString(), contains('Back at noon.'));
    expect((await get('/', admitted: true)).statusCode, 200);
  });

  test('the description Settings give comes before the build\'s', () async {
    await settle(<String, Object?>{'defaultSeoDescription': 'Boats by the hour.'});
    final String html = await (await get('/')).readAsString();
    expect(html, contains('content="Boats by the hour."'));
    expect(html, isNot(contains('Built description.')));
  });
}
