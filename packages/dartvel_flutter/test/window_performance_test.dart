// The Multi-Window performance contract.
//
// The specification names what is measured -- open() to ready, real and
// virtual; tear-out handover; shared-store write rate and coalescing ratio;
// store size and spill count; restore-on-launch duration -- and four
// diagnostics: a call site that always degrades, a shared key written more
// than once per frame before coalescing, a workspace whose restore exceeds
// the startup budget, and owned windows outliving the frame budget on close.
// None of it was measured. A contract nothing reads is a paragraph.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'window_shared_store_helpers.dart';

/// A clock that moves by [tick] every time it is read, so a duration between
/// two reads is known rather than whatever the runner's scheduler allowed.
class SteppingClock {
  SteppingClock(this.tick);
  final Duration tick;
  int _now = 0;
  int read() => _now += tick.inMicroseconds;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SteppingClock clock;
  late DVWindowPerformance perf;

  DVWindowPerformance install(Duration tick) {
    clock = SteppingClock(tick);
    perf = DVWindowPerformance(nowMicros: clock.read);
    DVWindowManager.performance = perf;
    return perf;
  }

  setUp(() {
    DVWindowManager.reset();
    install(const Duration(milliseconds: 1));
    DVNativeBridge.register('window.open', (Object? _) => 'native');
    DVNativeBridge.register('window.close', (Object? _) => true);
  });

  tearDown(() {
    DVNativeBridge.unregister('window.open');
    DVNativeBridge.unregister('window.close');
    DVWindowManager.reset();
  });

  Future<DVWindow> open(String path, {DVWindowOptions? options}) =>
      DV.Platform.Window.open(DVRouteTarget(path),
          options: options ?? const DVWindowOptions());

  group('open() to ready', () {
    test('a real window is measured and says it was real', () async {
      DV.Test.fakeWindowing(DVWindowingCapability.desktop());
      await open('/orders');

      expect(perf.opens, hasLength(1));
      final DVWindowOpenSample sample = perf.opens.single;
      expect(sample.route, '/orders');
      expect(sample.virtual, isFalse);
      expect(sample.elapsed, greaterThan(Duration.zero));
      expect(sample.code, isNull);
    });

    test('a virtual window is measured too, with its degradation', () async {
      DV.Test.fakeWindowing(const DVWindowingCapability());
      await open('/orders');

      final DVWindowOpenSample sample = perf.opens.single;
      expect(sample.virtual, isTrue);
      expect(sample.code, 'DV-WINDOW-001');
    });

    test('focusing a window already open is not an open', () async {
      DV.Test.fakeWindowing(DVWindowingCapability.desktop());
      await open('/orders');
      await open('/orders');

      expect(perf.opens, hasLength(1));
    });

    test('reset installs a fresh recorder', () async {
      DV.Test.fakeWindowing(DVWindowingCapability.desktop());
      await open('/orders');
      DVWindowManager.reset();

      expect(DVWindowManager.performance, isNot(same(perf)));
      expect(DVWindowManager.performance.opens, isEmpty);
    });
  });

  group('a call site that always degrades', () {
    test('is one finding after enough samples, not one per open', () async {
      DV.Test.fakeWindowing(const DVWindowingCapability());
      for (var i = 0; i < 3; i++) {
        await open('/orders', options: const DVWindowOptions(duplicate: true));
      }

      final finding = perf.findings.singleWhere(
          (DVWindowPerformanceFinding f) => f.kind == DVWindowPerformanceIssue.alwaysDegrades);
      expect(finding.subject, '/orders');
      expect(finding.count, 3);
      expect(finding.message, contains('DV-WINDOW-001'));
    });

    test('is not raised before the minimum, nor for a site that sometimes succeeds', () async {
      DV.Test.fakeWindowing(const DVWindowingCapability());
      await open('/orders', options: const DVWindowOptions(duplicate: true));
      await open('/orders', options: const DVWindowOptions(duplicate: true));
      expect(perf.findings, isEmpty);

      DV.Test.fakeWindowing(DVWindowingCapability.desktop());
      await open('/orders', options: const DVWindowOptions(duplicate: true));
      expect(perf.findings, isEmpty);
      expect(perf.degradationsByRoute['/orders']!.opens, 3);
      expect(perf.degradationsByRoute['/orders']!.degraded, 2);
    });
  });

  group('shared store', () {
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
        debounce: const Duration(milliseconds: 5),
      );
      DVWindowManager.useSharedStore(store);
    });
    tearDown(() => store.dispose());

    test('write rate and coalescing ratio: five writes, one flush', () async {
      for (var i = 0; i < 5; i++) {
        // ignore: unawaited_futures
        store.set('draft', DVJsonString('v$i'));
      }
      await store.flush('draft');

      expect(perf.storeWrites, 5);
      expect(perf.storeFlushes, 1);
      expect(perf.coalescingRatio, closeTo(0.8, 0.001));
    });

    test('store size follows what is stored, and spills are counted', () async {
      await store.set('small', const DVJsonString('tab-1'));
      final int small = perf.storeSizeBytes;
      expect(small, greaterThan(0));

      await store.set('draft', DVJsonString('x' * 500));
      expect(perf.spillCount, 1);
      expect(perf.storeSizeBytes, greaterThan(small + 500));

      await store.set('draft', null);
      expect(perf.storeSizeBytes, small);
    });

    test('a key written twice within a frame is a finding; once a frame is not', () async {
      // The clock steps 1ms per read, well inside the 16ms frame budget.
      // ignore: unawaited_futures
      store.set('cursor', const DVJsonNumber(1));
      // ignore: unawaited_futures
      store.set('cursor', const DVJsonNumber(2));
      await store.flush('cursor');

      final finding = perf.findings.singleWhere(
          (DVWindowPerformanceFinding f) => f.kind == DVWindowPerformanceIssue.writtenWithinFrame);
      expect(finding.subject, 'cursor');
      expect(finding.count, 1);

      install(const Duration(milliseconds: 20));
      await store.set('slow', const DVJsonNumber(1));
      await store.set('slow', const DVJsonNumber(2));
      expect(perf.findings, isEmpty);
    });
  });

  group('restore on launch', () {
    test('is measured, and a restore over the startup budget is a finding', () async {
      DV.Test.fakeWindowing(DVWindowingCapability.desktop());
      final store = DVWindowSharedStore(debounce: Duration.zero);
      addTearDown(store.dispose);
      DVWindowManager.useSharedStore(store);
      final workspace = DVTabWorkspaceController(
          tabs: const <DVTab>[DVTab(DVRouteTarget('/a')), DVTab(DVRouteTarget('/b'))]);
      await DV.Platform.Window.persistWorkspace('main', workspaces: <DVTabWorkspaceController>[workspace]);

      await DV.Platform.Window.restoreWorkspace('main');
      expect(perf.restores.single.name, 'main');
      expect(perf.restores.single.tabs, 2);
      expect(perf.findings, isEmpty);

      final slow = install(const Duration(milliseconds: 600));
      await DV.Platform.Window.restoreWorkspace('main');
      final finding = slow.findings.singleWhere(
          (DVWindowPerformanceFinding f) => f.kind == DVWindowPerformanceIssue.restoreOverBudget);
      expect(finding.subject, 'main');
      expect(finding.message, contains('500ms'));
    });
  });

  group('owned windows on close', () {
    test('closing within the frame budget is a sample and no finding', () async {
      DV.Test.fakeWindowing(DVWindowingCapability.desktop());
      final DVWindow owner = await open('/a');
      await open('/confirm',
          options: DVWindowOptions(kind: DVWindowKind.dialog, owner: owner, duplicate: true));
      await owner.close();

      expect(perf.ownedCloses.single.owner, '/a');
      expect(perf.ownedCloses.single.owned, 1);
      expect(perf.findings, isEmpty);
    });

    test('owned windows outliving the frame budget are a finding', () async {
      DV.Test.fakeWindowing(DVWindowingCapability.desktop());
      final DVWindow owner = await open('/a');
      await open('/confirm',
          options: DVWindowOptions(kind: DVWindowKind.dialog, owner: owner, duplicate: true));
      final slow = install(const Duration(milliseconds: 20));
      await owner.close();

      final finding = slow.findings.singleWhere(
          (DVWindowPerformanceFinding f) => f.kind == DVWindowPerformanceIssue.ownedOutliveFrame);
      expect(finding.subject, '/a');
    });

    test('a window owning nothing records no owned close', () async {
      DV.Test.fakeWindowing(DVWindowingCapability.desktop());
      final DVWindow w = await open('/a');
      await w.close();
      expect(perf.ownedCloses, isEmpty);
    });
  });

  group('tear-out handover', () {
    test('is measured from the gesture to the new window being ready', () async {
      DV.Test.fakeWindowing(DVWindowingCapability.desktop());
      final store = DVWindowSharedStore(debounce: Duration.zero);
      addTearDown(store.dispose);
      DVWindowManager.useSharedStore(store);
      final controller = DVTabWorkspaceController(
          tabs: const <DVTab>[DVTab(DVRouteTarget('/a')), DVTab(DVRouteTarget('/b'))]);

      await controller.tearOut(1);

      expect(perf.tearOuts.single.route, '/b');
      expect(perf.tearOuts.single.elapsed, greaterThan(Duration.zero));
    });
  });

  group('the report', () {
    test('serialises every measurement and the findings', () async {
      DV.Test.fakeWindowing(const DVWindowingCapability());
      for (var i = 0; i < 3; i++) {
        await open('/orders', options: const DVWindowOptions(duplicate: true));
      }
      final Map<String, Object?> json = perf.toJson();

      expect(json['opens'], isA<List<Object?>>());
      expect((json['degradations'] as Map)['/orders'], <String, Object?>{
        'opens': 3,
        'degraded': 3,
        'codes': <String, Object?>{'DV-WINDOW-001': 3},
      });
      expect(json['store'], containsPair('writes', 0));
      final List<Object?> findings = json['findings']! as List<Object?>;
      expect((findings.single as Map)['kind'], 'alwaysDegrades');
      expect((findings.single as Map)['subject'], '/orders');
    });
  });
}
