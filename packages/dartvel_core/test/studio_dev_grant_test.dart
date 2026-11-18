// Studio in development: `dartvel dev` and `dartvel dev --release`.
//
// A deployment opens Studio to accounts granted Studio.access. A development
// server has no accounts to speak of, and serving Studio -- records, grants,
// the page builder -- to anybody who can reach a port bound to 0.0.0.0 would
// hand a laptop's data to the coffee shop. So development prints a link with
// a grant token, the way a notebook server does: opening it sets a cookie for
// the mount, and the mount serves only a browser holding that cookie.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const DVAdminMount _mount = DVAdminMount(
  path: '/__studio',
  enabled: true,
  requiresAuth: true,
);

Request _request(String path, {String? cookie}) => Request(
      method: 'GET',
      url: Uri.parse('http://localhost:3000$path'),
      headers: Headers(<String, String>{'cookie': ?cookie}),
      bodyStream: const Stream<List<int>>.empty(),
    );

void main() {
  late Directory root;
  late MemoryDVDatabaseAdapter database;
  late DVAdminServer server;
  const DVStudioDevGrant grant = DVStudioDevGrant('0123456789abcdef0123456789abcdef');

  setUp(() {
    root = Directory.systemTemp.createTempSync('dartvel_studio_dev_');
    File('${root.path}/index.html').writeAsStringSync('<title>Studio</title>');
    addTearDown(() => root.deleteSync(recursive: true));
    server = DVAdminServer(
      mount: _mount,
      root: root.path,
      // The application's shell, which Studio's pages are rendered from.
      webRoot: root.path,
      devGrant: grant,
      database: database = MemoryDVDatabaseAdapter(),
    );
  });

  test('the link sets the grant cookie for the mount and drops the token '
      'from the address', () async {
    final Response? response = await server.respond(
      _request('/__studio/?dev_grant=${grant.token}'),
    );

    expect(response?.status, 303);
    expect(response!.headers.get('location'), '/__studio/');
    final String cookie = response.headers.get('set-cookie')!;
    expect(cookie, contains('${DVStudioDevGrant.cookieName}=${grant.token}'));
    expect(cookie, contains('HttpOnly'));
    expect(cookie, contains('SameSite=Strict'));
    // The whole site, not only the mount: Studio's code is the application's
    // deferred library, loaded from the site root, and a browser only sends
    // the cookie to a path under the one it was set for.
    expect(cookie, contains('Path=/;'));
  });

  test('a browser holding the cookie gets Studio and its data', () async {
    final String cookie = '${DVStudioDevGrant.cookieName}=${grant.token}';

    final Response? shell =
        await server.respond(_request('/__studio/', cookie: cookie));
    final Response? models =
        await server.respond(_request('/__studio/api/models', cookie: cookie));

    expect(shell?.status, 200);
    expect(models?.status, 200);
    expect(
      jsonDecode(utf8.decode(await models!.body!.bytes())),
      containsPair('models', <Object?>[]),
    );
  });

  test('the Studio app is told the browser holding the cookie is granted', () async {
    // The app's own guard asks api/access before it shows any screen; left
    // unanswered, every Studio page of `dartvel dev --release` sent the
    // browser holding the grant to the sign-in.
    final String cookie = '${DVStudioDevGrant.cookieName}=${grant.token}';
    final Response? access =
        await server.respond(_request('/__studio/api/access', cookie: cookie));
    expect(access?.status, 200);
    expect(jsonDecode(utf8.decode(await access!.body!.bytes())), containsPair('granted', true));
  });

  test("the Web screen's document lists the snippets the build used, then a change saved in Studio", () async {
    // A shell with a body, so the screen's document has somewhere to go.
    File('${root.path}/index.html')
        .writeAsStringSync('<!DOCTYPE html><html><head><title>Studio</title></head><body></body></html>');
    File('${root.path}/graph.json').writeAsStringSync(jsonEncode(<String, Object?>{
      'platforms': <String, Object?>{
        'web': <String, Object?>{
          'document': <String, Object?>{
            'head': <Object?>[<String, Object?>{'html': '<meta name="built" content="1">'}],
          },
        },
      },
    }));
    final String cookie = '${DVStudioDevGrant.cookieName}=${grant.token}';
    Future<String> document() async =>
        utf8.decode(await (await server.respond(_request('/__studio/platforms/web', cookie: cookie)))!.body!.bytes());
    expect(await document(), contains('&lt;meta name="built" content="1"&gt;'));

    await dvStudioSavePendingPlatforms(database, <String, Object?>{
      'bodyEnd': <Object?>[<String, Object?>{'html': '<script>saved()</script>'}],
    });
    final String after = await document();
    expect(after, contains('&lt;script&gt;saved()&lt;/script&gt;'));
    expect(after, isNot(contains('name="built"')));
  });

  test('anybody else gets what a missing route gets', () async {
    for (final Request request in <Request>[
      _request('/__studio/'),
      _request('/__studio/api/models'),
      _request('/__studio/api/models',
          cookie: '${DVStudioDevGrant.cookieName}=wrong'),
      _request('/__studio/?dev_grant=wrong'),
    ]) {
      expect(await server.respond(request), isNull,
          reason: '${request.url} ${request.headers.get('cookie')}');
    }
  });

  test('a fresh grant is a long random token', () {
    final DVStudioDevGrant a = DVStudioDevGrant.generate();
    final DVStudioDevGrant b = DVStudioDevGrant.generate();

    expect(a.token.length, greaterThanOrEqualTo(32));
    expect(a.token, isNot(b.token));
    expect(a.link('http://localhost:3000', _mount),
        'http://localhost:3000/__studio/?dev_grant=${a.token}');
  });
}
