// Restoring a workspace whose routes have moved on.
//
// A workspace layout is written to disk and read back a release later. In
// between, pages get renamed and deleted, so some stored routes no longer
// resolve. Restore kept them: it only checked that a stored entry was a string,
// so a tab pointing at a page that no longer exists came back as a tab, and the
// failure arrived when someone clicked it.
//
// The specification reserves DV-WINDOW-009 for "restored route missing,
// unauthorized, or unresolvable" and nothing emitted it. `info`, not a warning:
// a page being removed between releases is normal, and the workspace should
// come back without it rather than not come back.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(DVWindowManager.reset);
  tearDown(DVWindowManager.reset);

  Future<void> save(List<String> routes) =>
      DV.Platform.Window.persistWorkspace(
        'main',
        workspaces: <DVTabWorkspaceController>[
          DVTabWorkspaceController(
            tabs: <DVTab>[for (final String r in routes) DVTab(DVRouteTarget(r))],
          ),
        ],
      );

  group('with no known route set', () {
    test('everything stored comes back', () async {
      // Nothing has told the runtime which routes exist, so it cannot judge.
      // Dropping tabs on a guess would lose a workspace.
      await save(<String>['/a', '/b']);

      final List<DVTabWorkspaceController> restored =
          await DV.Platform.Window.restoreWorkspace('main');

      expect(restored.single.tabs.map((DVTab t) => t.route.path),
          <String>['/a', '/b']);
    });
  });

  group('with a known route set', () {
    setUp(() => DVWindowManager.knownRoutes = <String>{'/a', '/b'});

    test('routes that still exist come back', () async {
      await save(<String>['/a', '/b']);

      final List<DVTabWorkspaceController> restored =
          await DV.Platform.Window.restoreWorkspace('main');

      expect(restored.single.tabs, hasLength(2));
    });

    test('a route that no longer exists is dropped', () async {
      await save(<String>['/a', '/gone', '/b']);

      final List<DVTabWorkspaceController> restored =
          await DV.Platform.Window.restoreWorkspace('main');

      expect(restored.single.tabs.map((DVTab t) => t.route.path),
          <String>['/a', '/b']);
    });

    test('a workspace whose every route is gone is not restored empty',
        () async {
      // An empty workspace is a worse answer than no workspace: it looks like
      // the user closed everything.
      await save(<String>['/gone', '/also-gone']);

      expect(await DV.Platform.Window.restoreWorkspace('main'), isEmpty);
    });

    test('the active index survives an earlier tab being dropped', () async {
      // The stored index counts the tabs that were saved. Dropping one before
      // it and keeping the number selects the wrong tab -- silently, because
      // it is still a valid index.
      await DV.Platform.Window.persistWorkspace(
        'main',
        workspaces: <DVTabWorkspaceController>[
          DVTabWorkspaceController(
            tabs: <DVTab>[
              const DVTab(DVRouteTarget('/gone')),
              const DVTab(DVRouteTarget('/a')),
              const DVTab(DVRouteTarget('/b')),
            ],
          )..activate(2),
        ],
      );

      final List<DVTabWorkspaceController> restored =
          await DV.Platform.Window.restoreWorkspace('main');

      expect(restored.single.tabs.map((DVTab t) => t.route.path),
          <String>['/a', '/b']);
      expect(restored.single.tabs[restored.single.activeIndex].route.path, '/b',
          reason: 'the same tab as before, at its new position');
    });

    test('an active index pointing at a dropped tab lands somewhere real',
        () async {
      await DV.Platform.Window.persistWorkspace(
        'main',
        workspaces: <DVTabWorkspaceController>[
          DVTabWorkspaceController(
            tabs: <DVTab>[
              const DVTab(DVRouteTarget('/a')),
              const DVTab(DVRouteTarget('/gone')),
            ],
          )..activate(1),
        ],
      );

      final List<DVTabWorkspaceController> restored =
          await DV.Platform.Window.restoreWorkspace('main');

      expect(restored.single.activeIndex, 0);
    });

    test('reset clears the known routes, so one test cannot set another\'s',
        () {
      DVWindowManager.reset();
      expect(DVWindowManager.knownRoutes, isEmpty);
    });
  });

  group('the diagnostic', () {
    test('DV-WINDOW-009 is what an unresolvable restored route reports', () {
      expect(DVWindowDegradation.restoredRouteUnresolvable.code,
          'DV-WINDOW-009');
      expect(DVWindowDegradation.restoredRouteUnresolvable.level, 'info',
          reason: 'a page removed between releases is normal');
    });
  });
}
