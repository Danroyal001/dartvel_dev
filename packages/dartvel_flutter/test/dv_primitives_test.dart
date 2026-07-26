import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercises the primitives through the public `DV` surface, which is how
/// application code reaches them. The units themselves are covered in
/// dartvel_core; this pins the wiring.
void main() {
  group('DV.lifecycle', () {
    setUp(() => DV.lifecycle.resetForTesting());

    test('is reachable and starts at the documented initial states', () {
      expect(DV.lifecycle.app.value, DVAppLifecycle.uninitialized);
      expect(DV.lifecycle.build.value, DVBuildLifecycle.idle);
    });

    test('observers see framework transitions', () async {
      final seen = <DVAppLifecycle>[];
      final subscription = DV.lifecycle.app.listen(seen.add);

      DV.lifecycle.setApp(DVAppLifecycle.booting);
      DV.lifecycle.setApp(DVAppLifecycle.ready);
      await Future<void>.delayed(Duration.zero);

      expect(seen, <DVAppLifecycle>[
        DVAppLifecycle.booting,
        DVAppLifecycle.ready,
      ]);
      await subscription.cancel();
    });
  });

  group('DV.Modules', () {
    setUp(() => DV.Modules.resetForTesting());

    test('registers and resolves a module', () {
      DV.Modules.register(id: 'store', mountPath: '/store');
      expect(DV.Modules('store').resolve('/cart'), '/store/cart');
      expect(DV.Modules('store').lifecycle.value, DVModuleLifecycle.discovered);
    });

    test('an unregistered module fails loudly', () {
      expect(() => DV.Modules('absent'), throwsA(isA<DVUnknownModuleException>()));
    });
  });

  group('DV.transaction', () {
    test('commits and returns the body result', () async {
      final value = await DV.transaction<String>((_) async => 'ok');
      expect(value, 'ok');
    });

    test('defers afterCommit until the work commits', () async {
      final order = <String>[];
      await DV.transaction<void>((context) async {
        context.afterCommit(() => order.add('notified'));
        order.add('worked');
      });
      expect(order, <String>['worked', 'notified']);
    });

    test('compensates on failure and rethrows', () async {
      var refunded = false;
      await expectLater(
        DV.transaction<void>((context) async {
          context.compensate(() => refunded = true);
          throw StateError('gateway declined');
        }),
        throwsA(isA<StateError>()),
      );
      expect(refunded, isTrue);
    });

    test('exposes the transaction lifecycle on the context', () async {
      await DV.transaction<void>((context) async {
        expect(
          context.lifecycle.transaction.value,
          DVTransactionLifecycle.active,
        );
      });
    });
  });
}
