// Rotation hooks, and supplying secrets to a test.
//
// A long-lived client holding a connection built from a secret -- a payment
// gateway, a message broker -- has to rebuild it when the secret rotates,
// without a restart. The specification's shape is DV.Secrets.onRotate; a
// secret with no hook is simply re-read on next access. Neither existed, so
// every rotation was a restart.
//
// DV.Test.withSecrets is the other half: values for the duration of a test,
// restored after, so a suite never depends on the developer's environment and
// a forgotten override cannot leak into the next test.

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  const DVSecrets secrets = DVSecrets();

  setUp(DVSecrets.reset);
  tearDown(DVSecrets.reset);

  group('onRotate', () {
    test('a hook fires with the new value when the secret rotates', () async {
      DVSecrets.configure(<String, String>{'GATEWAY': 'old'});
      final List<String> seen = <String>[];
      secrets.onRotate('GATEWAY', (String value) async => seen.add(value));

      await secrets.rotate('GATEWAY', 'new');

      expect(seen, <String>['new']);
      expect(secrets.get('GATEWAY'), 'new');
    });

    test('hooks fire in registration order', () async {
      final List<String> order = <String>[];
      secrets.onRotate('K', (String v) async => order.add('first'));
      secrets.onRotate('K', (String v) async => order.add('second'));

      await secrets.rotate('K', 'v');

      expect(order, <String>['first', 'second']);
    });

    test('an unchanged value fires nothing', () async {
      // Re-reporting the same value must not rebuild every connection.
      DVSecrets.configure(<String, String>{'K': 'same'});
      var fired = 0;
      secrets.onRotate('K', (String v) async => fired++);

      await secrets.rotate('K', 'same');

      expect(fired, 0);
    });

    test('a hook for another key is left alone', () async {
      var fired = 0;
      secrets.onRotate('OTHER', (String v) async => fired++);

      await secrets.rotate('K', 'v');

      expect(fired, 0);
    });

    test('the returned function removes the hook', () async {
      var fired = 0;
      final void Function() off =
          secrets.onRotate('K', (String v) async => fired++);
      off();

      await secrets.rotate('K', 'v');

      expect(fired, 0);
    });

    test('a secret with no hook is simply re-read', () async {
      DVSecrets.configure(<String, String>{'K': 'one'});
      await secrets.rotate('K', 'two');
      expect(secrets.get('K'), 'two');
    });

    test('a hook that throws does not stop the others, and is reported',
        () async {
      // One connection failing to rebuild must not leave the rest on the old
      // secret, which would be worse than either outcome alone.
      final List<String> ran = <String>[];
      secrets.onRotate('K', (String v) async => throw StateError('boom'));
      secrets.onRotate('K', (String v) async => ran.add('second'));

      await expectLater(secrets.rotate('K', 'v'), throwsA(isA<StateError>()));
      expect(ran, <String>['second']);
      expect(secrets.get('K'), 'v', reason: 'the value rotated regardless');
    });

    test('reset drops hooks, so one test cannot fire another\'s', () async {
      var fired = 0;
      secrets.onRotate('K', (String v) async => fired++);
      DVSecrets.reset();

      await secrets.rotate('K', 'v');

      expect(fired, 0);
    });
  });

  group('DV.Test.withSecrets', () {
    const DVTestHarness harness = DVTestHarness();

    test('values are visible inside and gone after', () async {
      await harness.withSecrets(<String, String>{'K': 'inside'}, () async {
        expect(secrets.get('K'), 'inside');
      });
      expect(secrets.maybeGet('K'), isNull);
    });

    test('a previous value is put back, not merely removed', () async {
      DVSecrets.configure(<String, String>{'K': 'before'});
      await harness.withSecrets(<String, String>{'K': 'during'}, () async {
        expect(secrets.get('K'), 'during');
      });
      expect(secrets.get('K'), 'before');
    });

    test('restored even when the body throws', () async {
      await expectLater(
        harness.withSecrets(<String, String>{'K': 'x'}, () async {
          throw StateError('body failed');
        }),
        throwsA(isA<StateError>()),
      );
      expect(secrets.maybeGet('K'), isNull);
    });

    test('the body\'s result comes back', () async {
      final int n = await harness.withSecrets(
          <String, String>{'K': '3'}, () async => int.parse(secrets.get('K')));
      expect(n, 3);
    });

    test('rotation hooks registered inside are gone after', () async {
      // A hook is state too; leaving it behind is the leak this exists to
      // prevent.
      var fired = 0;
      await harness.withSecrets(<String, String>{'K': 'x'}, () async {
        secrets.onRotate('K', (String v) async => fired++);
      });
      await secrets.rotate('K', 'y');
      expect(fired, 0);
    });
  });
}
