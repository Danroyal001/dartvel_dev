import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  late DVTransactionRunner transaction;

  setUp(() => transaction = DVTransactionRunner());

  group('committing', () {
    test('returns the body result', () async {
      final result = await transaction<int>((_) async => 42);
      expect(result, 42);
    });

    test('runs afterCommit callbacks in registration order', () async {
      final order = <String>[];
      await transaction<void>((context) async {
        context.afterCommit(() => order.add('first'));
        context.afterCommit(() => order.add('second'));
        order.add('body');
      });
      expect(order, <String>['body', 'first', 'second']);
    });

    test('does not run compensations on success', () async {
      var compensated = false;
      await transaction<void>((context) {
        context.compensate(() => compensated = true);
      });
      expect(compensated, isFalse);
    });

    test('walks the full committed lifecycle', () async {
      final seen = <DVTransactionLifecycle>[];
      await transaction<void>((context) async {
        context.lifecycle.transaction.listen(seen.add);
        await Future<void>.delayed(Duration.zero);
      });
      await Future<void>.delayed(Duration.zero);

      expect(seen, containsAllInOrder(<DVTransactionLifecycle>[
        DVTransactionLifecycle.preparing,
        DVTransactionLifecycle.committing,
        DVTransactionLifecycle.committed,
      ]));
    });
  });

  group('failing', () {
    test('rethrows the original error', () async {
      expect(
        () => transaction<void>((_) => throw StateError('boom')),
        throwsA(isA<StateError>()),
      );
    });

    test('does not run afterCommit callbacks', () async {
      // Irreversible effects must not fire when the work did not commit.
      var sent = false;
      await expectLater(
        transaction<void>((context) {
          context.afterCommit(() => sent = true);
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()),
      );
      expect(sent, isFalse);
    });

    test('runs compensations in reverse registration order', () async {
      // Each compensation undoes its effect while what it depended on still
      // stands, so the order must be the inverse of registration.
      final undone = <String>[];
      await expectLater(
        transaction<void>((context) {
          context.compensate(() => undone.add('charge'));
          context.compensate(() => undone.add('reservation'));
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()),
      );
      expect(undone, <String>['reservation', 'charge']);
    });

    test('reports compensation failures without losing the original cause',
        () async {
      try {
        await transaction<void>((context) {
          context.compensate(() => throw StateError('refund failed'));
          throw ArgumentError('original cause');
        });
        fail('expected DVCompensationException');
      } on DVCompensationException catch (error) {
        expect(error.cause, isA<ArgumentError>());
        expect(error.compensationErrors, hasLength(1));
        expect(error.toString(), contains('original cause'));
        expect(error.toString(), contains('refund failed'));
      }
    });

    test('a failing compensation does not stop the remaining ones', () async {
      final undone = <String>[];
      await expectLater(
        transaction<void>((context) {
          context.compensate(() => undone.add('outer'));
          context.compensate(() => throw StateError('middle failed'));
          context.compensate(() => undone.add('inner'));
          throw StateError('boom');
        }),
        throwsA(isA<DVCompensationException>()),
      );
      expect(undone, <String>['inner', 'outer']);
    });

    test('reaches rolledBack when there is nothing to compensate', () async {
      final seen = <DVTransactionLifecycle>[];
      await expectLater(
        transaction<void>((context) {
          context.lifecycle.transaction.listen(seen.add);
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(seen, contains(DVTransactionLifecycle.rolledBack));
    });

    test('reaches compensated when compensations ran', () async {
      final seen = <DVTransactionLifecycle>[];
      await expectLater(
        transaction<void>((context) {
          context.lifecycle.transaction.listen(seen.add);
          context.compensate(() {});
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(seen, contains(DVTransactionLifecycle.compensating));
      expect(seen, contains(DVTransactionLifecycle.compensated));
    });
  });

  group('nesting', () {
    test('a nested transaction joins the active one', () async {
      await transaction<void>((outer) async {
        expect(outer.isNested, isFalse);
        await transaction<void>((inner) async {
          expect(inner.isNested, isTrue);
        });
      });
    });

    test('nested afterCommit fires once, after the outer commit', () async {
      final order = <String>[];
      await transaction<void>((outer) async {
        await transaction<void>((inner) async {
          inner.afterCommit(() => order.add('inner-after-commit'));
          order.add('inner-body');
        });
        order.add('outer-body');
      });

      expect(order, <String>['inner-body', 'outer-body', 'inner-after-commit']);
    });

    test('a nested failure rolls back the outer transaction', () async {
      final undone = <String>[];
      await expectLater(
        transaction<void>((outer) async {
          outer.compensate(() => undone.add('outer'));
          await transaction<void>((inner) async {
            inner.compensate(() => undone.add('inner'));
            throw StateError('inner blew up');
          });
        }),
        throwsA(isA<StateError>()),
      );
      expect(undone, <String>['inner', 'outer']);
    });

    test('an isolated transaction does not join the active one', () async {
      await transaction<void>((outer) async {
        await transaction<void>((inner) async {
          expect(inner.isNested, isFalse);
        }, isolated: true);
      });
    });

    test('an isolated inner failure does not roll back the outer', () async {
      var outerCompensated = false;
      var innerCompensated = false;

      await transaction<void>((outer) async {
        outer.compensate(() => outerCompensated = true);
        try {
          await transaction<void>((inner) async {
            inner.compensate(() => innerCompensated = true);
            throw StateError('isolated failure');
          }, isolated: true);
        } catch (_) {
          // Deliberately contained: the outer transaction still commits.
        }
      });

      expect(innerCompensated, isTrue);
      expect(outerCompensated, isFalse);
    });
  });

  group('context lifecycle scoping', () {
    test('request and page signals are unavailable in a transaction',
        () async {
      await transaction<void>((context) {
        expect(() => context.lifecycle.request, throwsStateError);
        expect(() => context.lifecycle.page, throwsStateError);
        expect(context.lifecycle.transaction, isNotNull);
      });
    });

    test('transaction signal is unavailable outside a transaction', () {
      final context = DVContext();
      expect(() => context.lifecycle.transaction, throwsStateError);
    });
  });

  group('active context', () {
    test('is exposed while running and cleared afterwards', () async {
      expect(DVTransactionRunner.activeContext, isNull);
      await transaction<void>((context) async {
        expect(DVTransactionRunner.activeContext, same(context));
      });
      expect(DVTransactionRunner.activeContext, isNull);
    });

    test('is cleared even when the body throws', () async {
      await expectLater(
        transaction<void>((_) => throw StateError('boom')),
        throwsA(isA<StateError>()),
      );
      expect(DVTransactionRunner.activeContext, isNull);
    });
  });
}
