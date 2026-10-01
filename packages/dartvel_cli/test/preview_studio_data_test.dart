// Studio's data on `dartvel dev --release`.
//
// Preview served Studio's files and not its API, so every section opened on
// "The server did not answer". Given an admin server, the preview handler
// answers the mount through it: the same DVAdminServer the web-server binary
// uses, over the project's database, open to the browser holding the
// development grant and to nobody else.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/web_server.dart';
import 'package:dartvel_core/dartvel.dart'
    show
        DVAdminMount,
        DVAdminServer,
        DVPublishedPages,
        DVStudioDevGrant,
        DVStudioFieldSpec,
        DVStudioModelSpec,
        MemoryDVDatabaseAdapter;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Handler handler;
  const DVStudioDevGrant grant =
      DVStudioDevGrant('0123456789abcdef0123456789abcdef');
  const DVAdminMount mount =
      DVAdminMount(path: '/__studio', enabled: true, requiresAuth: true);

  setUp(() {
    root = Directory.systemTemp.createTempSync('dartvel_preview_studio_');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/index.html').writeAsStringSync(
        '<html><head><title>Site</title></head><body></body></html>');
    handler = dvWebServerHandler(
      webRoot: root.path,
      admin: mount,
      publishedPages: DVPublishedPages(database: () => null),
      adminServer: DVAdminServer(
        mount: mount,
        root: '${root.path}/studio-data',
        webRoot: root.path,
        title: 'Studio · shop',
        devGrant: grant,
        database: MemoryDVDatabaseAdapter(),
        models: const <DVStudioModelSpec>[
          DVStudioModelSpec(
            model: 'Note',
            table: 'notes',
            key: 'id',
            fields: <DVStudioFieldSpec>[
              DVStudioFieldSpec(name: 'id', type: 'String'),
            ],
          ),
        ],
      ),
    );
  });

  Future<Response> get(String path, {String? cookie}) async => await handler(
        Request('GET', Uri.parse('http://localhost:8080$path'),
            headers: <String, String>{'cookie': ?cookie}),
      );

  test('the grant link sets the cookie, and the API answers with it',
      () async {
    final Response claimed = await get('/__studio/?dev_grant=${grant.token}');
    expect(claimed.statusCode, 303);
    expect(claimed.headers['set-cookie'], contains(grant.token));

    final Response models = await get(
      '/__studio/api/models',
      cookie: '${DVStudioDevGrant.cookieName}=${grant.token}',
    );
    expect(models.statusCode, 200);
    final Map<String, Object?> body =
        jsonDecode(await models.readAsString()) as Map<String, Object?>;
    expect((body['models']! as List<Object?>), hasLength(1));

    // And Studio itself: a page of the application, rendered from its shell.
    final Response page = await get(
      '/__studio/',
      cookie: '${DVStudioDevGrant.cookieName}=${grant.token}',
    );
    expect(page.statusCode, 200);
    expect(await page.readAsString(), contains('<title>Studio · shop</title>'));
  });

  test('without the grant the mount is a missing route', () async {
    final Response models = await get('/__studio/api/models');
    final Response shell = await get('/__studio/');

    expect(models.statusCode, 404);
    expect(await models.readAsString(), isEmpty);
    expect(shell.statusCode, 404);
  });

  test('the pages Studio published are served to the app', () async {
    final Response pages = await get('/_dartvel/pages');

    expect(pages.statusCode, 200);
    expect(jsonDecode(await pages.readAsString()),
        <String, Object?>{'pages': <Object?>[]});
  });
}
