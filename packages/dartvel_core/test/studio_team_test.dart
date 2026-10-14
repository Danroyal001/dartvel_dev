// Tests for Studio's users and roles: roles, permissions, team directory,
// configurable entitlement gate, role editing, and server documents.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Request _request(
  String method,
  String path, {
  Object? json,
  Map<String, String>? headers,
}) =>
    Request(
      method: method,
      url: Uri.parse(
          'http://localhost:8080${path.startsWith('/') ? '' : '/'}$path'),
      headers: Headers(<String, String>{
        if (json != null) 'content-type': 'application/json',
        'x-dartvel-csrf-token': 'abcdefghijklmnopqrstuvwxyz012345',
        ...?headers,
      }),
      bodyStream: json == null
          ? const Stream<List<int>>.empty()
          : Stream<List<int>>.value(utf8.encode(jsonEncode(json))),
    );

Future<String> _text(Response response) async =>
    utf8.decode(await response.body!.bytes());

Future<Map<String, Object?>> _json(Response response) async =>
    (jsonDecode(await _text(response)) as Map).cast<String, Object?>();

void main() {
  group('DVStudioRole and entitlements', () {
    test('default roles carry appropriate permissions', () {
      expect(DVStudioRole.admin.permissions, contains('settings:write'));
      expect(DVStudioRole.admin.permissions, contains('team:write'));
      expect(DVStudioRole.editor.permissions, contains('pages:write'));
      expect(DVStudioRole.editor.permissions, isNot(contains('settings:write')));
      expect(DVStudioRole.author.permissions, contains('media:write'));
      expect(DVStudioRole.author.permissions, isNot(contains('routes:write')));
      expect(DVStudioRole.viewer.permissions, contains('pages:read'));
      expect(DVStudioRole.viewer.permissions, isNot(contains('pages:write')));
    });

    test('DVStudioRole serializes and deserializes cleanly', () {
      const DVStudioRole role = DVStudioRole(
        id: 'reviewer',
        name: 'Reviewer',
        description: 'Can review content drafts',
        permissions: <String>{'pages:read', 'pages:review'},
        isBuiltIn: false,
      );
      final Map<String, Object?> json = role.toJson();
      expect(json['id'], 'reviewer');
      expect(json['name'], 'Reviewer');
      final DVStudioRole restored = DVStudioRole.fromJson(json);
      expect(restored.id, 'reviewer');
      expect(restored.permissions, contains('pages:review'));
      expect(restored.isBuiltIn, isFalse);
    });

    test('DVStudioEntitlements provides single configurable gate', () {
      expect(DVStudioEntitlements.current.rolesEnabled, isTrue);
      expect(DVStudioEntitlements.current.customRolesEnabled, isTrue);
    });
  });

  group('DVStudioGrants roles and permissions', () {
    late SqliteDVDatabaseAdapter database;
    late DVStudioGrants grants;

    setUp(() {
      database = SqliteDVDatabaseAdapter.memory();
      grants = DVStudioGrants(database);
    });

    test('grant assigns role and stores it', () async {
      await grants.grant('user-1', role: 'editor');
      expect(await grants.isGranted('user-1'), isTrue);
      expect(await grants.roleOf('user-1'), 'editor');

      final List<DVStudioGrant> all = await grants.list();
      expect(all, hasLength(1));
      expect(all.first.role, 'editor');
    });

    test('updateRole changes user role', () async {
      await grants.grant('user-1', role: 'viewer');
      expect(await grants.roleOf('user-1'), 'viewer');

      final bool updated = await grants.updateRole('user-1', 'admin');
      expect(updated, isTrue);
      expect(await grants.roleOf('user-1'), 'admin');
    });

    test('isGranted checks required permission based on role', () async {
      await grants.grant('viewer-1', role: 'viewer');
      await grants.grant('editor-1', role: 'editor');

      expect(await grants.isGranted('viewer-1', requiredPermission: 'pages:read'), isTrue);
      expect(await grants.isGranted('viewer-1', requiredPermission: 'pages:write'), isFalse);
      expect(await grants.isGranted('editor-1', requiredPermission: 'pages:write'), isTrue);
    });

    test('custom roles can be saved, listed and deleted', () async {
      final List<DVStudioRole> initial = await grants.listRoles();
      expect(initial, hasLength(4));

      const DVStudioRole custom = DVStudioRole(
        id: 'moderator',
        name: 'Moderator',
        description: 'Can manage comments and media',
        permissions: <String>{'media:write'},
        isBuiltIn: false,
      );
      await grants.saveRole(custom);

      final List<DVStudioRole> afterSave = await grants.listRoles();
      expect(afterSave, hasLength(5));
      expect(afterSave.any((DVStudioRole r) => r.id == 'moderator'), isTrue);

      final bool deleted = await grants.deleteRole('moderator');
      expect(deleted, isTrue);
      expect((await grants.listRoles()).any((DVStudioRole r) => r.id == 'moderator'), isFalse);
    });

    test('built-in roles cannot be deleted', () async {
      expect(() => grants.deleteRole('admin'), throwsArgumentError);
    });
  });

  group('Studio team API endpoints', () {
    late SqliteDVDatabaseAdapter database;
    late DVStudioApi api;

    setUp(() {
      database = SqliteDVDatabaseAdapter.memory();
      api = DVStudioApi(database: database);
    });

    test('GET api/grants and api/team return grants, roles and entitlements', () async {
      await DVStudioGrants(database).grant('admin-1', role: 'admin');

      final Response res1 = await api.respond(_request('GET', 'api/grants'), 'grants');
      expect(res1.status, 200);
      final Map<String, Object?> body1 = await _json(res1);
      final List<Object?> grantsList = body1['grants']! as List<Object?>;
      expect(grantsList, hasLength(1));
      final Map<String, Object?> grant = grantsList.first! as Map<String, Object?>;
      expect(grant['userId'], 'admin-1');
      expect(grant['role'], 'admin');

      final List<Object?> rolesList = body1['roles']! as List<Object?>;
      expect(rolesList, isNotEmpty);
      expect(body1['entitlements'], isA<Map>());

      final Response res2 = await api.respond(_request('GET', 'api/team'), 'team');
      expect(res2.status, 200);
    });

    test('POST api/team creates grant with role', () async {
      final Response res = await api.respond(
        _request(
          'POST',
          'api/team',
          json: <String, Object?>{
            'account': 'teammate-1',
            'role': 'editor',
          },
        ),
        'team',
      );
      expect(res.status, 201);
      final Map<String, Object?> body = await _json(res);
      expect(body['userId'], 'teammate-1');
      expect(body['role'], 'editor');

      expect(await DVStudioGrants(database).roleOf('teammate-1'), 'editor');
    });

    test('PATCH api/team updates user role', () async {
      await DVStudioGrants(database).grant('admin-1', role: 'admin');
      await DVStudioGrants(database).grant('user-2', role: 'viewer');

      final Response res = await api.respond(
        _request(
          'PATCH',
          'api/team',
          json: <String, Object?>{
            'userId': 'user-2',
            'role': 'editor',
          },
        ),
        'team',
      );
      expect(res.status, 200);
      final Map<String, Object?> body = await _json(res);
      expect(body['userId'], 'user-2');
      expect(body['role'], 'editor');

      expect(await DVStudioGrants(database).roleOf('user-2'), 'editor');
    });

    test('PATCH api/team prevents demoting last admin without confirmation', () async {
      await DVStudioGrants(database).grant('only-admin', role: 'admin');

      final Response res1 = await api.respond(
        _request(
          'PATCH',
          'api/team',
          json: <String, Object?>{
            'userId': 'only-admin',
            'role': 'editor',
          },
        ),
        'team',
      );
      expect(res1.status, 409);
      final Map<String, Object?> body1 = await _json(res1);
      expect(body1['code'], 'confirm_last_admin');

      // With confirmation:
      final Response res2 = await api.respond(
        _request(
          'PATCH',
          'api/team',
          json: <String, Object?>{
            'userId': 'only-admin',
            'role': 'editor',
            'confirm': true,
          },
        ),
        'team',
      );
      expect(res2.status, 200);
      expect(await DVStudioGrants(database).roleOf('only-admin'), 'editor');
    });

    test('custom roles endpoint GET and POST api/team/roles', () async {
      final Response getRes =
          await api.respond(_request('GET', 'api/team/roles'), 'team/roles');
      expect(getRes.status, 200);
      final Map<String, Object?> getBody = await _json(getRes);
      expect((getBody['roles'] as List).length, greaterThanOrEqualTo(4));

      final Response postRes = await api.respond(
        _request(
          'POST',
          'api/team/roles',
          json: <String, Object?>{
            'id': 'support',
            'name': 'Customer Support',
            'description': 'Can view records and users',
            'permissions': <String>['models:read', 'team:read'],
          },
        ),
        'team/roles',
      );
      expect(postRes.status, 201);
      final Map<String, Object?> postBody = await _json(postRes);
      expect(postBody['id'], 'support');

      final List<DVStudioRole> roles =
          await DVStudioGrants(database).listRoles();
      expect(roles.any((DVStudioRole r) => r.id == 'support'), isTrue);
    });
  });

  group('Studio team documents and aliases', () {
    test('dvStudioScreenAliases resolves team, users, and roles to access', () {
      expect(dvStudioScreenFor('team')?.id, 'access');
      expect(dvStudioScreenFor('users')?.id, 'access');
      expect(dvStudioScreenFor('roles')?.id, 'access');
    });

    test('access screen document renders heading and summary', () {
      final DVStudioScreenSpec? spec = dvStudioScreenFor('access');
      expect(spec, isNotNull);
      final DVStudioDocument doc = dvStudioDocumentFor(
        DVStudioTarget(screen: spec!),
        mount: '/__studio',
        data: const DVStudioProjectData(),
      );
      expect(doc.heading, 'Team');
      expect(doc.html, contains('Manage teammates, roles and permissions'));
    });

    test('access target document renders sub-object document', () {
      final DVStudioScreenSpec? spec = dvStudioScreenFor('access');
      final DVStudioDocument doc = dvStudioDocumentFor(
        DVStudioTarget(screen: spec!, object: const <String>['roles']),
        mount: '/__studio',
        data: const DVStudioProjectData(),
      );
      expect(doc.heading, 'Roles & Permissions');
      expect(doc.html, contains('Team and access management'));
    });
  });
}
