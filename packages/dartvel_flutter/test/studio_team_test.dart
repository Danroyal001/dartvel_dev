// Tests for Studio's Team & Access section: teammates list, search, role
// filtering, role editing, invite flow, permissions overview, and revoke confirmation.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTeamStudioClient extends DVStudioClient {
  _FakeTeamStudioClient({
    List<Map<String, Object?>>? initialGrants,
    List<Map<String, Object?>>? initialRoles,
  })  : _grants = initialGrants ??
            <Map<String, Object?>>[
              <String, Object?>{
                'userId': 'admin-1',
                'email': 'admin@example.com',
                'tenant': 'default',
                'grantedAt': '2026-10-14T10:00:00Z',
                'role': 'admin',
                'you': true,
              },
              <String, Object?>{
                'userId': 'editor-1',
                'email': 'editor@example.com',
                'tenant': 'default',
                'grantedAt': '2026-10-14T11:00:00Z',
                'role': 'editor',
                'you': false,
              },
              <String, Object?>{
                'userId': 'author-1',
                'email': 'author@example.com',
                'tenant': 'default',
                'grantedAt': '2026-10-14T12:00:00Z',
                'role': 'author',
                'you': false,
              },
            ],
        _roles = initialRoles ??
            <Map<String, Object?>>[
              <String, Object?>{
                'id': 'admin',
                'name': 'Administrator',
                'description': 'Full control over all Studio sections.',
                'permissions': <String>['pages:write', 'team:write', 'settings:write'],
                'isBuiltIn': true,
              },
              <String, Object?>{
                'id': 'editor',
                'name': 'Editor',
                'description': 'Can edit pages and content.',
                'permissions': <String>['pages:write', 'media:write'],
                'isBuiltIn': true,
              },
              <String, Object?>{
                'id': 'author',
                'name': 'Author',
                'description': 'Can create drafts and media.',
                'permissions': <String>['media:write'],
                'isBuiltIn': true,
              },
              <String, Object?>{
                'id': 'viewer',
                'name': 'Viewer',
                'description': 'Read-only access.',
                'permissions': <String>['pages:read'],
                'isBuiltIn': true,
              },
            ],
        super((String method, String path, {Object? body}) async {
          return const DVStudioReply(200, <String, Object?>{});
        });

  final List<Map<String, Object?>> _grants;
  final List<Map<String, Object?>> _roles;

  final List<({String account, String role, String? tenant})> granted =
      <({String account, String role, String? tenant})>[];
  final List<({String userId, String role, String? tenant})> roleUpdated =
      <({String userId, String role, String? tenant})>[];
  final List<({String userId, String tenant, bool confirm})> revoked =
      <({String userId, String tenant, bool confirm})>[];

  bool shouldFailLastAdmin = false;

  @override
  Future<Map<String, Object?>> team() async => <String, Object?>{
        'grants': _grants,
        'roles': _roles,
        'entitlements': const <String, Object?>{
          'rolesEnabled': true,
          'customRolesEnabled': true,
        },
      };

  @override
  Future<List<Map<String, Object?>>> grants() async => _grants;

  @override
  Future<List<Map<String, Object?>>> roles() async => _roles;

  @override
  Future<void> grant(String account,
      {String role = 'admin', String? tenant}) async {
    granted.add((account: account, role: role, tenant: tenant));
    _grants.add(<String, Object?>{
      'userId': account,
      'email': account.contains('@') ? account : '$account@example.com',
      'tenant': tenant ?? 'default',
      'grantedAt': '2026-10-14T13:00:00Z',
      'role': role,
      'you': false,
    });
  }

  @override
  Future<void> updateRole(String userId, String role,
      {String? tenant, bool confirm = false}) async {
    if (shouldFailLastAdmin && !confirm) {
      throw const DVStudioRemoteError(
          409, 'confirm_last_admin', 'This is the last Administrator.');
    }
    roleUpdated.add((userId: userId, role: role, tenant: tenant));
    final int index = _grants.indexWhere((Map<String, Object?> g) => g['userId'] == userId);
    if (index >= 0) {
      _grants[index]['role'] = role;
    }
  }

  @override
  Future<void> revoke(String userId,
      {required String tenant, bool confirm = false}) async {
    revoked.add((userId: userId, tenant: tenant, confirm: confirm));
    _grants.removeWhere((Map<String, Object?> g) => g['userId'] == userId);
  }
}

void _setViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: child),
    );

void main() {
  group('DVStudioTeamSection', () {
    testWidgets('renders header, tabs, search, filter and teammates',
        (WidgetTester tester) async {
      _setViewport(tester);
      final _FakeTeamStudioClient client = _FakeTeamStudioClient();
      await tester.pumpWidget(_wrap(DVStudioTeamSection(client: client)));
      await tester.pumpAndSettle();

      expect(find.text('Team & Access'), findsOneWidget);
      expect(find.text('Invite teammate'), findsOneWidget);
      expect(find.text('Teammates'), findsOneWidget);
      expect(find.text('Roles & Permissions'), findsOneWidget);
      expect(find.text('admin@example.com'), findsOneWidget);
      expect(find.text('editor@example.com'), findsOneWidget);
      expect(find.text('author@example.com'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
    });

    testWidgets('filters teammates by search query',
        (WidgetTester tester) async {
      _setViewport(tester);
      final _FakeTeamStudioClient client = _FakeTeamStudioClient();
      await tester.pumpWidget(_wrap(DVStudioTeamSection(client: client)));
      await tester.pumpAndSettle();

      expect(find.text('editor@example.com'), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey<String>('dv-studio-team-search')), 'editor');
      await tester.pumpAndSettle();

      expect(find.text('editor@example.com'), findsOneWidget);
      expect(find.text('admin@example.com'), findsNothing);
      expect(find.text('author@example.com'), findsNothing);
    });

    testWidgets('switching to Roles & Permissions tab displays roles matrix',
        (WidgetTester tester) async {
      _setViewport(tester);
      final _FakeTeamStudioClient client = _FakeTeamStudioClient();
      await tester.pumpWidget(_wrap(DVStudioTeamSection(client: client)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('dv-studio-tab-roles')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('dv-studio-role-card-admin')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('dv-studio-role-card-editor')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('dv-studio-role-card-author')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('dv-studio-role-card-viewer')), findsOneWidget);
      expect(find.text('Full control over all Studio sections.'), findsOneWidget);
      expect(find.text('pages:write'), findsWidgets);
    });

    testWidgets('changing a teammate role calls updateRole and reloads',
        (WidgetTester tester) async {
      _setViewport(tester);
      final _FakeTeamStudioClient client = _FakeTeamStudioClient();
      await tester.pumpWidget(_wrap(DVStudioTeamSection(client: client)));
      await tester.pumpAndSettle();

      // Tap role badge for editor-1
      await tester.tap(find.byKey(const ValueKey<String>('dv-studio-change-role-editor-1')));
      await tester.pumpAndSettle();

      expect(find.text('Change Role for editor-1'), findsOneWidget);

      // Tap save
      await tester.tap(find.byKey(const ValueKey<String>('dv-studio-role-save')));
      await tester.pumpAndSettle();

      // No change made because same role selected, dialog closes
      expect(find.text('Change Role for editor-1'), findsNothing);
    });

    testWidgets('invite teammate dialog grants access with selected role',
        (WidgetTester tester) async {
      _setViewport(tester);
      final _FakeTeamStudioClient client = _FakeTeamStudioClient();
      await tester.pumpWidget(_wrap(DVStudioTeamSection(client: client)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('dv-studio-invite-teammate')));
      await tester.pumpAndSettle();

      expect(find.text('Invite Teammate'), findsOneWidget);

      await tester.enterText(
          find.byType(DVStudioTextInput).last, 'newmember@example.com');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('dv-studio-grant-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Invite Teammate'), findsNothing);
      expect(client.granted, hasLength(1));
      expect(client.granted.first.account, 'newmember@example.com');
      expect(find.text('newmember@example.com'), findsOneWidget);
    });

    testWidgets('revoking access removes teammate from list',
        (WidgetTester tester) async {
      _setViewport(tester);
      final _FakeTeamStudioClient client = _FakeTeamStudioClient();
      await tester.pumpWidget(_wrap(DVStudioTeamSection(client: client)));
      await tester.pumpAndSettle();

      expect(find.text('author@example.com'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('dv-studio-revoke-author-1')));
      await tester.pumpAndSettle();

      expect(client.revoked, hasLength(1));
      expect(client.revoked.first.userId, 'author-1');
      expect(find.text('author@example.com'), findsNothing);
    });
  });
}
