// A forwarding signal is what a `DVBox.video(source).controller` handle reads
// through. A box rebuilt by its parent makes a new handle every build, so a
// handle that subscribed to the player on construction would leave one more
// subscription on the player per rebuild for as long as the player lived.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  test('holds no subscription on its target until something listens', () async {
    final DVMutableMediaSignal<int> target = DVMutableMediaSignal<int>(1);
    final DVForwardingMediaSignal<int> forwarding =
        DVForwardingMediaSignal<int>(target);
    expect(target.hasListener, isFalse);
    expect(forwarding.value, 1);

    final List<int> seen = <int>[];
    final StreamSubscription<int> sub = forwarding.listen(seen.add);
    expect(target.hasListener, isTrue);
    target.set(2);
    await pump();
    expect(seen, <int>[2]);

    await sub.cancel();
    expect(target.hasListener, isFalse);
  });

  test('moves its subscription, and its listeners, when retargeted', () async {
    final DVMutableMediaSignal<int> first = DVMutableMediaSignal<int>(1);
    final DVMutableMediaSignal<int> second = DVMutableMediaSignal<int>(5);
    final DVForwardingMediaSignal<int> forwarding =
        DVForwardingMediaSignal<int>(first);
    final List<int> seen = <int>[];
    forwarding.listen(seen.add);

    forwarding.retarget(second);
    expect(first.hasListener, isFalse);
    expect(second.hasListener, isTrue);
    await pump();
    expect(seen, <int>[5]);

    first.set(9);
    second.set(6);
    await pump();
    expect(seen, <int>[5, 6]);
  });

  test('retargeting with nobody listening subscribes to nothing', () {
    final DVMutableMediaSignal<int> first = DVMutableMediaSignal<int>(1);
    final DVMutableMediaSignal<int> second = DVMutableMediaSignal<int>(2);
    DVForwardingMediaSignal<int>(first).retarget(second);
    expect(first.hasListener, isFalse);
    expect(second.hasListener, isFalse);
  });
}
