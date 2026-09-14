// A transaction belongs to the flow that opened it.
//
// Two backend requests served by one isolate interleave at every await. The
// transaction a request opened must stay that request's: the other request's
// DV.transaction must not join it, its failure must not undo the other's
// work, and callbacks registered in one must not fire on the other's commit.
// Nesting inside one flow still joins, and work the body schedules -- a timer,
// a microtask -- is still part of the body's flow.
//
// Every interleaving here is forced with Completers rather than delays, so
// the order the flows reach each point is the same on every run.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  late DVTransactionRunner transaction;

  setUp(() => transaction = DVTransactionRunner());

  test('a transaction opened while another flow is mid-transaction is its own',
      () async {
    final Completer<void> aOpened = Completer<void>();
    final Completer<void> releaseA = Completer<void>();
    late String aId;
    late bool bNested;
    late String bId;
    late String bInnerId;

    final Future<void> a = transaction<void>((DVContext context) async {
      aId = context.transactionId;
      aOpened.complete();
      await releaseA.future;
    });

    await aOpened.future;
    final Future<void> b = transaction<void>((DVContext context) async {
      bNested = context.isNested;
      bId = context.transactionId;
      await transaction<void>((DVContext inner) {
        bInnerId = inner.transactionId;
      });
    });

    await b;
    releaseA.complete();
    await a;

    expect(bNested, isFalse,
        reason: 'request B opened its own transaction; it did not join A');
    expect(bId, isNot(aId));
    expect(bInnerId, bId,
        reason: 'a nested call in B joins B, not the other request\'s A');
  });

  test('one flow failing does not roll back or compensate another flow',
      () async {
    final Completer<void> aOpened = Completer<void>();
    final Completer<void> bRegistered = Completer<void>();
    final Completer<void> releaseB = Completer<void>();
    final List<String> undone = <String>[];

    final Future<void> a = transaction<void>((DVContext context) async {
      context.compensate(() => undone.add('a'));
      aOpened.complete();
      await bRegistered.future;
      throw StateError('request A failed');
    });

    await aOpened.future;
    final Future<void> b = transaction<void>((DVContext context) async {
      context.compensate(() => undone.add('b'));
      await transaction<void>((DVContext inner) {
        inner.compensate(() => undone.add('b-inner'));
      });
      bRegistered.complete();
      await releaseB.future;
    });

    await expectLater(a, throwsA(isA<StateError>()));
    releaseB.complete();
    await b;

    expect(undone, <String>['a'],
        reason: 'only A\'s own compensation runs when A rolls back');
  });

  test('afterCommit registered in one flow runs when that flow commits',
      () async {
    final Completer<void> aOpened = Completer<void>();
    final Completer<void> releaseA = Completer<void>();
    final List<String> order = <String>[];

    final Future<void> a = transaction<void>((DVContext context) async {
      aOpened.complete();
      await releaseA.future;
      order.add('a-body-done');
    });

    await aOpened.future;
    await transaction<void>((DVContext context) async {
      context.afterCommit(() => order.add('b-after-commit'));
      order.add('b-body-done');
    });
    order.add('b-returned');

    releaseA.complete();
    await a;

    expect(order, <String>[
      'b-body-done',
      'b-after-commit',
      'b-returned',
      'a-body-done',
    ]);
  });

  test('afterCommit does not fire when an unrelated flow commits', () async {
    final Completer<void> aOpened = Completer<void>();
    final Completer<void> releaseA = Completer<void>();
    var bAfterCommitRan = false;

    final Future<void> a = transaction<void>((DVContext context) async {
      aOpened.complete();
      await releaseA.future;
    });

    await aOpened.future;
    await expectLater(
      transaction<void>((DVContext context) async {
        context.afterCommit(() => bAfterCommitRan = true);
        throw StateError('request B failed');
      }),
      throwsA(isA<StateError>()),
    );

    releaseA.complete();
    await a;

    expect(bAfterCommitRan, isFalse,
        reason: 'B never committed, so A committing must not send B\'s effects');
  });

  test('nesting within one flow still joins while another flow is open',
      () async {
    final Completer<void> aOpened = Completer<void>();
    final Completer<void> bOpened = Completer<void>();
    final Completer<void> releaseB = Completer<void>();
    late String aId;
    late String aInnerId;
    late bool aInnerNested;
    late String bId;

    final Future<void> a = transaction<void>((DVContext context) async {
      aId = context.transactionId;
      aOpened.complete();
      await bOpened.future;
      await transaction<void>((DVContext inner) {
        aInnerNested = inner.isNested;
        aInnerId = inner.transactionId;
      });
    });

    await aOpened.future;
    final Future<void> b = transaction<void>((DVContext context) async {
      bId = context.transactionId;
      bOpened.complete();
      await releaseB.future;
    }, isolated: true);

    await a;
    releaseB.complete();
    await b;

    expect(aInnerNested, isTrue);
    expect(aInnerId, aId,
        reason: 'the nested call joins A even though B opened after it');
    expect(bId, isNot(aId));
  });

  test('a timer and a microtask the body schedules see the body\'s transaction',
      () async {
    final Completer<void> aOpened = Completer<void>();
    final Completer<void> bOpened = Completer<void>();
    final Completer<void> releaseB = Completer<void>();
    late DVContext aContext;
    late DVContext bContext;
    DVContext? seenByTimer;
    DVContext? seenByMicrotask;

    final Future<void> a = transaction<void>((DVContext context) async {
      aContext = context;
      aOpened.complete();
      await bOpened.future;

      final Completer<void> timerFired = Completer<void>();
      Timer(Duration.zero, () {
        seenByTimer = DVTransactionRunner.activeContext;
        timerFired.complete();
      });
      final Completer<void> microtaskRan = Completer<void>();
      scheduleMicrotask(() {
        seenByMicrotask = DVTransactionRunner.activeContext;
        microtaskRan.complete();
      });
      await Future.wait(<Future<void>>[timerFired.future, microtaskRan.future]);
    });

    await aOpened.future;
    final Future<void> b = transaction<void>((DVContext context) async {
      bContext = context;
      bOpened.complete();
      await releaseB.future;
    }, isolated: true);

    await a;
    releaseB.complete();
    await b;

    expect(bContext, isNot(same(aContext)));
    expect(seenByTimer, same(aContext));
    expect(seenByMicrotask, same(aContext));
  });

  test('outside any transaction a concurrent flow sees none', () async {
    final Completer<void> aOpened = Completer<void>();
    final Completer<void> releaseA = Completer<void>();

    final Future<void> a = transaction<void>((DVContext context) async {
      aOpened.complete();
      await releaseA.future;
    });

    await aOpened.future;
    final DVContext? seen = DVTransactionRunner.activeContext;
    releaseA.complete();
    await a;

    expect(seen, isNull,
        reason: 'the test body never opened a transaction; A is not its');
  });

  test('work that outlives the body does not join the finished transaction',
      () async {
    final Completer<DVContext?> escaped = Completer<DVContext?>();
    final Completer<void> committed = Completer<void>();

    await transaction<void>((DVContext context) {
      // Deliberately unawaited: it runs after the transaction is over.
      unawaited(committed.future.then(
          (_) => escaped.complete(DVTransactionRunner.activeContext)));
    });
    committed.complete();

    expect(await escaped.future, isNull);
  });

  test('a transaction opened by an afterCommit callback is its own', () async {
    late String outerId;
    bool? callbackNested;
    String? callbackId;
    var callbackAfterCommitRan = false;

    await transaction<void>((DVContext context) {
      outerId = context.transactionId;
      context.afterCommit(() async {
        await transaction<void>((DVContext next) {
          callbackNested = next.isNested;
          callbackId = next.transactionId;
          next.afterCommit(() => callbackAfterCommitRan = true);
        });
      });
    });

    expect(callbackNested, isFalse,
        reason: 'the outer transaction has committed; there is nothing to join');
    expect(callbackId, isNot(outerId));
    expect(callbackAfterCommitRan, isTrue,
        reason: 'joining a committed transaction would drop this silently');
  });
}
