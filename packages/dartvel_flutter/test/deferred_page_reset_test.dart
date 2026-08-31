// A generated page caches its deferred library future, and a widget test
// creates each test in its own FakeAsync zone.
//
// The combination is a trap. The first test's loadLibrary() is cached in a
// static; every later test subscribes to that same future, whose completion
// callbacks are scheduled in the first test's zone -- which is gone. The
// future never delivers, the page's FutureBuilder sits on its loading state,
// and the test reports that the page renders nothing.
//
// The first test passes and every one after it fails, which reads like test
// pollution in the application rather than the framework.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a page registers a reset for its cached library', () {
    // The registry is what makes a central reset possible: a test cannot
    // reach a private static on each generated class.
    int calls = 0;
    final void Function() unregister =
        dvRegisterDeferredPageReset(() => calls += 1);
    addTearDown(unregister);

    dvResetDeferredPages();
    expect(calls, 1);

    dvResetDeferredPages();
    expect(calls, 2);
  });

  test('resetting clears every registered page', () {
    final List<String> reset = <String>[];
    final void Function() a = dvRegisterDeferredPageReset(() => reset.add('a'));
    final void Function() b = dvRegisterDeferredPageReset(() => reset.add('b'));
    addTearDown(a);
    addTearDown(b);

    dvResetDeferredPages();
    expect(reset, <String>['a', 'b']);
  });

  test('an unregistered page is not reset again', () {
    // A page whose test file has finished must not be called back into: the
    // closure holds its class, and calling it after teardown is how a reset
    // becomes its own source of cross-test state.
    final List<String> reset = <String>[];
    final void Function() a = dvRegisterDeferredPageReset(() => reset.add('a'));
    dvRegisterDeferredPageReset(() => reset.add('b'));
    a();

    dvResetDeferredPages();
    expect(reset, <String>['b']);
  });
}
