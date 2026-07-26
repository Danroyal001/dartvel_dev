import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('DVMutableLifecycleSignal', () {
    test('starts at the initial state', () {
      final signal =
          DVMutableLifecycleSignal<DVAppLifecycle>(DVAppLifecycle.uninitialized);
      expect(signal.value, DVAppLifecycle.uninitialized);
      expect(signal.read(), DVAppLifecycle.uninitialized);
    });

    test('emits each transition to observers', () async {
      final signal =
          DVMutableLifecycleSignal<DVAppLifecycle>(DVAppLifecycle.uninitialized);
      final seen = <DVAppLifecycle>[];
      signal.listen(seen.add);

      signal.set(DVAppLifecycle.initializing);
      signal.set(DVAppLifecycle.booting);
      signal.set(DVAppLifecycle.ready);
      await Future<void>.delayed(Duration.zero);

      expect(seen, <DVAppLifecycle>[
        DVAppLifecycle.initializing,
        DVAppLifecycle.booting,
        DVAppLifecycle.ready,
      ]);
      expect(signal.value, DVAppLifecycle.ready);
    });

    test('does not re-emit the same state', () async {
      // Observers should see genuine transitions, not repeated assignments.
      final signal =
          DVMutableLifecycleSignal<DVAppLifecycle>(DVAppLifecycle.ready);
      final seen = <DVAppLifecycle>[];
      signal.listen(seen.add);

      signal.set(DVAppLifecycle.ready);
      signal.set(DVAppLifecycle.ready);
      await Future<void>.delayed(Duration.zero);

      expect(seen, isEmpty);
    });

    test('a failing observer cannot break the transition for others',
        () async {
      final signal =
          DVMutableLifecycleSignal<DVAppLifecycle>(DVAppLifecycle.uninitialized);
      final seen = <DVAppLifecycle>[];
      signal.listen((_) => throw StateError('observer blew up'));
      signal.listen(seen.add);

      signal.set(DVAppLifecycle.ready);
      await Future<void>.delayed(Duration.zero);

      expect(seen, <DVAppLifecycle>[DVAppLifecycle.ready]);
      expect(signal.value, DVAppLifecycle.ready);
    });

    test('supports async observers', () async {
      final signal =
          DVMutableLifecycleSignal<DVAppLifecycle>(DVAppLifecycle.uninitialized);
      var ran = false;
      signal.listen((_) async {
        await Future<void>.delayed(Duration.zero);
        ran = true;
      });

      signal.set(DVAppLifecycle.booting);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(ran, isTrue);
    });
  });

  group('DVLifecycleRegistry', () {
    test('exposes app and build signals at their initial states', () {
      final registry = DVLifecycleRegistry();
      expect(registry.app.value, DVAppLifecycle.uninitialized);
      expect(registry.build.value, DVBuildLifecycle.idle);
    });

    test('resetForTesting returns both signals to their initial states', () {
      final registry = DVLifecycleRegistry();
      registry.setApp(DVAppLifecycle.ready);
      registry.setBuild(DVBuildLifecycle.compiling);

      registry.resetForTesting();

      expect(registry.app.value, DVAppLifecycle.uninitialized);
      expect(registry.build.value, DVBuildLifecycle.idle);
    });

    test('framework transitions are visible through the read-only view',
        () async {
      final registry = DVLifecycleRegistry();
      final seen = <DVAppLifecycle>[];
      registry.app.listen(seen.add);

      registry.setApp(DVAppLifecycle.booting);
      registry.setApp(DVAppLifecycle.ready);
      await Future<void>.delayed(Duration.zero);

      expect(seen, <DVAppLifecycle>[
        DVAppLifecycle.booting,
        DVAppLifecycle.ready,
      ]);
    });

    test('build lifecycle advances independently of app lifecycle', () {
      final registry = DVLifecycleRegistry();
      registry.setBuild(DVBuildLifecycle.generating);
      expect(registry.build.value, DVBuildLifecycle.generating);
      expect(registry.app.value, DVAppLifecycle.uninitialized);
    });
  });

  group('lifecycle enums', () {
    test('cover the states named in the spec', () {
      expect(DVAppLifecycle.values, hasLength(10));
      expect(DVPageLifecycle.values, hasLength(11));
      expect(DVModuleLifecycle.values, hasLength(12));
      expect(DVRequestLifecycle.values, hasLength(20));
      expect(DVTransactionLifecycle.values, hasLength(11));
      expect(DVBuildLifecycle.values, hasLength(9));
    });
  });
}
