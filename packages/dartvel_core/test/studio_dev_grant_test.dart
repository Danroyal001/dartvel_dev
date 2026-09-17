// Studio in development: `dartvel dev` and `dartvel preview`.
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
  late DVAdminServer server;
  const DVStudioDevGrant grant = DVStudioDevGrant('0123456789abcdef0123456789abcdef');

  setUp(() {
    root = Directory.systemTemp.createTempSync('dartvel_studio_dev_');
    File('${root.path}/index.html').writeAsStringSync('<title>Studio</title>');
    addTearDown(() => root.deleteSync(recursive: true));
    server = DVAdminServer(
      mount: _mount,
      root: root.path,
      devGrant: grant,
      database: MemoryDVDatabaseAdapter(),
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
    expect(cookie, contains('Path=/__studio'));
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
      <String, Object?>{'models': <Object?>[]},
    );
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
