// Connectivity is a signal, and an application reads it rather than asking.
//
// The specification has said `DV.Platform.network.status` and `.since` since
// Offline-First Models was written, and nothing existed: an application that
// wanted to show an offline banner, a queued-writes count or a "last synced"
// line had nothing to read, and the offline store had no way to know when to
// replay. A signal rather than a callback, so a banner is a widget that
// rebuilds and not a listener somebody has to remember to dispose.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/network_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(DVNetworkSource.reset);
  tearDown(DVNetworkSource.reset);

  test('an application that has heard nothing is told so, not told online',
      () {
    // The honest default. Assuming online means the first write on a train
    // goes out, fails, and is reported as an error rather than queued.
    expect(const DVNetwork().status, DVNetworkStatus.unknown);
    expect(const DVNetwork().since, isNull);
  });

  test('what the platform reports is what it reads', () {
    DVNetworkSource.report(DVNetworkStatus.offline);

    expect(const DVNetwork().status, DVNetworkStatus.offline);
    expect(const DVNetwork().since, isNotNull);
  });

  test('since is when it last changed, not when it was last reported', () {
    DVNetworkSource.report(DVNetworkStatus.online);
    final DateTime first = const DVNetwork().since!;

    DVNetworkSource.report(DVNetworkStatus.online);
    expect(const DVNetwork().since, first);

    DVNetworkSource.report(DVNetworkStatus.offline);
    expect(const DVNetwork().since, isNot(first));
  });

  test('a change is on the stream, and an unchanged report is not', () async {
    final List<DVNetworkStatus> seen = <DVNetworkStatus>[];
    final sub = const DVNetwork().changes.listen(seen.add);

    DVNetworkSource.report(DVNetworkStatus.online);
    DVNetworkSource.report(DVNetworkStatus.online);
    DVNetworkSource.report(DVNetworkStatus.metered);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(seen, <DVNetworkStatus>[
      DVNetworkStatus.online,
      DVNetworkStatus.metered,
    ]);
  });

  test('metered is not offline, because they call for different things', () {
    // A sync may proceed on a metered connection; a video prefetch may not.
    DVNetworkSource.report(DVNetworkStatus.metered);

    expect(const DVNetwork().status, DVNetworkStatus.metered);
    expect(const DVNetwork().canReachTheServer, isTrue);

    DVNetworkSource.report(DVNetworkStatus.offline);
    expect(const DVNetwork().canReachTheServer, isFalse);
  });

  test('nothing heard yet is not treated as unreachable either', () {
    // Refusing to try because nothing has reported would strand every
    // platform that has no binding: the write is attempted and its failure
    // is what says the network is gone.
    expect(const DVNetwork().canReachTheServer, isTrue);
  });

  testWidgets('a widget that watches it rebuilds when it changes',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (BuildContext context) =>
            Text(DV.Platform.network.watch(context).name),
      ),
    ));
    expect(find.text('unknown'), findsOneWidget);

    DVNetworkSource.report(DVNetworkStatus.offline);
    await tester.pump();

    expect(find.text('offline'), findsOneWidget);
  });
}
