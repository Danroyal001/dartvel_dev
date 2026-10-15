// A Studio role is what its holder may do, checked by the server on every
// write -- as wp-admin checks a capability on every action rather than only
// hiding the button. A role nobody checks is a label.
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
  late DVStudioGrants grants;
  late String caller;
  late DVAdminServer server;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('dartvel_studio_roles_');
    addTearDown(() => root.deleteSync(recursive: true));
    database = MemoryDVDatabaseAdapter();
    grants = DVStudioGrants(database);
    await grants.grant('ada', role: 'admin');
    await grants.grant('eve', role: 'editor');
    await grants.grant('abe', role: 'author');
    await grants.grant('vic', role: 'viewer');
    server = DVAdminServer(
      mount: const DVAdminMount(
        path: '/__studio',
        enabled: true,
        requiresAuth: false,
      ),
      root: root.path,
      database: database,
      caller: (Request _) async => caller,
    );
  });

  Future<int> status(String who, String method, String path, {Object? json}) async {
    caller = who;
    final Response response = (await server.respond(
      _request(method, '/__studio/api/$path', json: json),
    ))!;
    return response.status;
  }

  final Map<String, Object?> page = <String, Object?>{
    'document': <String, Object?>{'route': '/about', 'title': 'About'},
  };

  test('a viewer reads and changes nothing', () async {
    expect(await status('vic', 'GET', 'pages'), 200);
    expect(await status('vic', 'PUT', 'pages', json: page), 403);
    expect(await status('vic', 'PUT', 'pages/draft', json: page), 403);
    expect(
      await status('vic', 'PUT', 'settings', json: <String, Object?>{
        'siteTitle': 'Mine now',
      }),
      403,
    );
  });

  test('nobody but an administrator changes who may open Studio', () async {
    for (final String who in <String>['eve', 'abe', 'vic']) {
      expect(
        await status(who, 'POST', 'grants', json: <String, Object?>{
          'account': 'mallory',
          'role': 'admin',
        }),
        403,
        reason: '$who granted access',
      );
      expect(
        await status(who, 'PATCH', 'grants', json: <String, Object?>{
          'userId': who,
          'role': 'admin',
        }),
        403,
        reason: '$who promoted themselves',
      );
    }
    expect(await grants.roleOf('vic'), 'viewer');
    expect(
      await status('ada', 'PATCH', 'grants', json: <String, Object?>{
        'userId': 'vic',
        'role': 'editor',
      }),
      200,
    );
  });

  test('an author writes drafts; publishing is an editor\'s', () async {
    expect(await status('abe', 'PUT', 'pages/draft', json: page), 200);
    expect(
      await status('abe', 'POST', 'pages/publish', json: <String, Object?>{
        'route': '/about',
      }),
      403,
    );
    expect(await status('abe', 'PUT', 'pages', json: page), 403);
    expect(
      await status('eve', 'POST', 'pages/publish', json: <String, Object?>{
        'route': '/about',
      }),
      200,
    );
  });

  test('the team and settings are not read by a role without them', () async {
    expect(await status('abe', 'GET', 'grants'), 403);
    expect(await status('abe', 'GET', 'settings'), 403);
    expect(await status('vic', 'GET', 'grants'), 200);
  });

  test('a role that does not exist is not granted', () async {
    expect(
      await status('ada', 'POST', 'grants', json: <String, Object?>{
        'account': 'mallory',
        'role': 'superuser',
      }),
      400,
    );
  });

  test('the last administrator is not revoked without saying so', () async {
    // Other grants remain on the tenant, so the last-grant check does not
    // catch it; ada is still the only one who can manage the team.
    expect(await status('owner', 'DELETE', 'grants?userId=ada'), 409);
    expect(await grants.roleOf('ada'), 'admin');
    expect(await status('owner', 'DELETE', 'grants?userId=ada&confirm=true'), 200);
  });

  test('a caller the application admitted itself keeps full access', () async {
    // No grant row: the application registered its own Studio.access answer,
    // or this is a development server's grant.
    expect(await status('owner', 'PUT', 'pages', json: page), 200);
  });
}
