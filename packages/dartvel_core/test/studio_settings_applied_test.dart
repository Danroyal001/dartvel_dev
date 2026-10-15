// Settings changed in Studio change the site. Maintenance mode and the
// default description were stored and read back by Studio alone: switching
// maintenance on left the site exactly as it was.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Request _request(String method, String path, {Object? json}) => Request(
  method: method,
  url: Uri.parse('http://localhost:8080$path'),
  headers: Headers(<String, String>{
    if (json != null) 'content-type': 'application/json',
    'x-dartvel-csrf-token': 'abcdefghijklmnopqrstuvwxyz012345',
  }),
  bodyStream: json == null
      ? const Stream<List<int>>.empty()
      : Stream<List<int>>.value(utf8.encode(jsonEncode(json))),
);

void main() {
  late Directory root;
  late MemoryDVDatabaseAdapter database;
  late DVAdminServer studio;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dartvel_settings_applied_');
    addTearDown(() => root.deleteSync(recursive: true));
    database = MemoryDVDatabaseAdapter();
    studio = DVAdminServer(
      mount: const DVAdminMount(path: '/__studio', enabled: true, requiresAuth: false),
      root: root.path,
      database: database,
    );
  });

  Future<void> settle(Map<String, Object?> settings) async {
    final Response saved = (await studio.respond(_request('PUT', '/__studio/api/settings', json: <String, Object?>{
      'siteTitle': 'Harbour',
      ...settings,
    })))!;
    expect(saved.status, 200, reason: utf8.decode(await saved.body!.bytes()));
  }

  DVPublishedPages site({bool admitted = false}) => DVPublishedPages(
    database: () => database,
    passesMaintenance: (Request _) async => admitted,
  );

  test('with maintenance off, a page is the application\'s to answer', () async {
    await settle(<String, Object?>{'maintenanceMode': false});
    expect(await site().respond(_request('GET', '/about')), isNull);
  });

  test('with maintenance on, a visitor is told so, and asked to come back', () async {
    await settle(<String, Object?>{
      'maintenanceMode': true,
      'maintenanceMessage': 'Back at noon.',
    });
    final Response page = (await site().respond(_request('GET', '/about')))!;
    expect(page.status, 503);
    expect(page.headers.get('retry-after'), isNotNull);
    expect(page.headers.get('cache-control'), contains('no-store'));
    final String html = utf8.decode(await page.body!.bytes());
    expect(html, contains('Back at noon.'));
    expect(html, contains('<title>Harbour</title>'));

    // What the framework serves itself goes on: a form, the media, Studio's
    // published pages for the app that is in maintenance with them.
    expect(await site().respond(_request('GET', '/_dartvel/forms/none')), isNot(
        predicate<Response?>((Response? r) => r?.status == 503)));
  });

  test('somebody who may open Studio sees the site as it is', () async {
    await settle(<String, Object?>{'maintenanceMode': true});
    expect(await site(admitted: true).respond(_request('GET', '/about')), isNull);
  });

  test('the maintenance message cannot write markup', () async {
    await settle(<String, Object?>{
      'maintenanceMode': true,
      'maintenanceMessage': '<script>alert(1)</script>',
    });
    final String html = utf8.decode(
        await (await site().respond(_request('GET', '/')))!.body!.bytes());
    expect(html, isNot(contains('<script>alert')));
  });

  test('the default title, description and image are the site\'s', () async {
    await settle(<String, Object?>{
      'defaultSeoTitle': 'Harbour boats',
      'defaultSeoDescription': 'Boats, for hire.',
      'defaultSeoImage': '/_dartvel/media/boat.png',
    });
    final DVStudioSiteDefaults defaults = (await site().siteDefaults())!;
    expect(defaults.name, 'Harbour');
    expect(defaults.title, 'Harbour boats');
    expect(defaults.description, 'Boats, for hire.');
    expect(defaults.image, '/_dartvel/media/boat.png');
  });

  test('a site with no settings saved has no defaults to give', () async {
    expect(await site().siteDefaults(), isNull);
  });
}
