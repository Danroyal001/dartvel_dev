// A persisted workspace belongs to the tenant and the user who saved it.
//
// The spec: layout, tab order and active tab persist under the workspace
// name, tenant- and user-scoped. Without the scope, one person's open tabs
// come back for the next person at the same desk, or for the same person
// in another tenant -- a layout is a small thing to leak, and the routes in
// it are not.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DVWindowManager.reset();
    const DVTenants().currentTenant = 'acme';
  });
  tearDown(() {
    DVWindowManager.reset();
    const DVTenants().currentTenant = 'default';
    DV.Test.resetAuth();
  });

  Future<void> save(List<String> routes) => DV.Platform.Window.persistWorkspace(
        'main',
        workspaces: <DVTabWorkspaceController>[
          DVTabWorkspaceController(
            tabs: <DVTab>[for (final String r in routes) DVTab(DVRouteTarget(r))],
          ),
        ],
      );

  Future<List<String>> restored() async {
    final List<DVTabWorkspaceController> w = await DV.Platform.Window.restoreWorkspace('main');
    return <String>[for (final DVTabWorkspaceController c in w) for (final DVTab t in c.tabs) t.route.path];
  }

  final DVAuthUser ada = DVAuthUser(id: 'u-ada', provider: 'test', createdAt: DateTime(2026));
  final DVAuthUser grace = DVAuthUser(id: 'u-grace', provider: 'test', createdAt: DateTime(2026));

  test('the same tenant and user get their layout back', () async {
    await DV.Test.asUser(ada, () => save(<String>['/orders', '/stock']));
    expect(await DV.Test.asUser(ada, restored), <String>['/orders', '/stock']);
  });

  test('another user at the same desk does not', () async {
    await DV.Test.asUser(ada, () => save(<String>['/orders', '/stock']));
    expect(await DV.Test.asUser(grace, restored), isEmpty);
    expect(await restored(), isEmpty, reason: 'nor nobody signed in');
  });

  test('the same user in another tenant does not', () async {
    await DV.Test.asUser(ada, () => save(<String>['/orders']));
    const DVTenants().currentTenant = 'globex';
    expect(await DV.Test.asUser(ada, restored), isEmpty);
    const DVTenants().currentTenant = 'acme';
    expect(await DV.Test.asUser(ada, restored), <String>['/orders']);
  });

  test('two users keep two layouts under one name', () async {
    await DV.Test.asUser(ada, () => save(<String>['/orders']));
    await DV.Test.asUser(grace, () => save(<String>['/stock']));
    expect(await DV.Test.asUser(ada, restored), <String>['/orders']);
    expect(await DV.Test.asUser(grace, restored), <String>['/stock']);
  });
}
