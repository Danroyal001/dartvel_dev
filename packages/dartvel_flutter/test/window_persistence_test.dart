// Spilling and workspace persistence.
//
// Both are about what survives: a value too big for a preference store, and a
// layout that has to come back after a relaunch. The tests assert the parts
// that would otherwise be assumed — that a spilled value really left the
// preference store, and that a restored workspace is the same workspace.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'window_shared_store_helpers.dart';

const orders = DVRouteTarget('/orders');
const customers = DVRouteTarget('/customers');

String big(int bytes) => 'x' * bytes;

void main() {
  group('spilling', () {
    late NotifyingBackend backend;
    late DVMemoryFileStorageAdapter files;
    late DVWindowSharedStore store;

    setUp(() {
      backend = NotifyingBackend();
      files = DVMemoryFileStorageAdapter();
      store = DVWindowSharedStore(
        backend: backend,
        spillStorage: files,
        spillThresholdBytes: 64,
        debounce: Duration.zero,
      );
    });
    tearDown(() => store.dispose());

    test('a small value stays in the preference store', () async {
      await store.set('small', const DVJsonString('tab-1'));

      expect(backend.values['small'], contains('tab-1'));
    });

    test('a large value leaves a pointer, not the bytes', () async {
      await store.set('draft', DVJsonString(big(500)));

      final stored = backend.values['draft']!;
      expect(stored, startsWith('dv-spill:'),
          reason: 'the preference store holds a pointer');
      expect(stored.length, lessThan(200),
          reason: 'the bytes must not be what was written here');
    });

    test('and reading follows the pointer', () async {
      await store.set('draft', DVJsonString(big(500)));
      store.evictCache();

      final value = await store.get('draft');

      expect((value! as DVJsonString).value.length, 500);
    });

    test('a rewrite replaces the object rather than accumulating', () async {
      await store.set('draft', DVJsonString(big(500)));
      await store.set('draft', DVJsonString(big(600)));
      store.evictCache();

      expect(((await store.get('draft'))! as DVJsonString).value.length, 600);
    });

    test('a pointer whose object is gone reads as unreadable, not a crash',
        () async {
      await store.set('draft', DVJsonString(big(500)));
      await files.delete('dartvel/window-shared/draft');
      store.evictCache();

      expect(await store.get('draft'), isNull);
    });

    test('with no spill storage a large value is stored inline', () async {
      final inline = DVWindowSharedStore(
        backend: NotifyingBackend(),
        spillThresholdBytes: 64,
        debounce: Duration.zero,
      );
      addTearDown(inline.dispose);

      await inline.set('draft', DVJsonString(big(500)));
      inline.evictCache();

      expect(((await inline.get('draft'))! as DVJsonString).value.length, 500,
          reason: 'spilling is an optimisation, not a requirement');
    });
  });

  group('workspace persistence', () {
    tearDown(DVWindowManager.reset);

    test('restores tab order and the active tab', () async {
      final manager = DV.Platform.Window;
      final workspace = DVTabWorkspaceController(
        tabs: const <DVTab>[DVTab(orders), DVTab(customers)],
      )..activate(1);

      await manager.persistWorkspace('main',
          workspaces: <DVTabWorkspaceController>[workspace]);
      final restored = await manager.restoreWorkspace('main');

      expect(restored, hasLength(1));
      expect(restored.single.tabs.map((DVTab t) => t.route.path),
          <String>['/orders', '/customers']);
      expect(restored.single.active, const DVTab(customers),
          reason: 'the layout is not restored if the selection is lost');
    });

    test('several workspaces round-trip', () async {
      final manager = DV.Platform.Window;

      await manager.persistWorkspace('main',
          workspaces: <DVTabWorkspaceController>[
            DVTabWorkspaceController(tabs: const <DVTab>[DVTab(orders)]),
            DVTabWorkspaceController(tabs: const <DVTab>[DVTab(customers)]),
          ]);

      expect(await manager.restoreWorkspace('main'), hasLength(2));
    });

    test('a first launch restores nothing rather than failing', () async {
      expect(await DV.Platform.Window.restoreWorkspace('never-saved'), isEmpty);
    });

    test('workspaces are stored under their own name', () async {
      final manager = DV.Platform.Window;
      await manager.persistWorkspace('left',
          workspaces: <DVTabWorkspaceController>[
            DVTabWorkspaceController(tabs: const <DVTab>[DVTab(orders)]),
          ]);

      expect(await manager.restoreWorkspace('right'), isEmpty);
      expect(await manager.restoreWorkspace('left'), hasLength(1));
    });

    test('an empty workspace persists as empty rather than vanishing',
        () async {
      final manager = DV.Platform.Window;

      await manager.persistWorkspace('main',
          workspaces: <DVTabWorkspaceController>[DVTabWorkspaceController()]);
      final restored = await manager.restoreWorkspace('main');

      expect(restored, hasLength(1));
      expect(restored.single.isEmpty, isTrue);
    });
  });
}
