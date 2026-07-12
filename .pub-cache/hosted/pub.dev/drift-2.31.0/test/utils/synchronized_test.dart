import 'dart:async';

import 'package:drift/src/utils/synchronized.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  test('synchronized runs code in sequence', () async {
    final lock = Lock();
    var i = 0;
    var inSynchronizedBlock = 0;
    final completionOrder = <int>[];
    final futures = List.generate(
        100,
        (index) => lock.synchronized(() async {
              expect(inSynchronizedBlock, 0);
              inSynchronizedBlock = 1;
              await pumpEventQueue();
              inSynchronizedBlock--;
              return i++;
            })
              ..whenComplete(() => completionOrder.add(index)));
    final results = await Future.wait(futures);

    expect(results, List.generate(100, (index) => index));
    expect(completionOrder, List.generate(100, (index) => index));
  });

  test('can wait on lock used in fakeAsync zone', () async {
    final lock = Lock();
    final completer = Completer<void>();

    fakeAsync((async) {
      lock
          .synchronized(expectAsync0(() async {}))
          .then((_) => completer.complete());
      async.flushTimers();
    });

    await completer.future;
    await lock.synchronized(() async {});
  });
}
