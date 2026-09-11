// Work that belongs to a running application starts with its first page on
// screen and stops with its last.
//
// The client schedules used to start a periodic timer when the router was
// created. Nothing owned it: nothing ever cancelled it, a second router
// started a second one beside it -- so every schedule fired twice -- and
// every widget test that built the router failed with "A Timer is still
// pending even after the widget tree was disposed", because it was.
//
// Every route puts its page in a DVPageLifecycleHost, so "a page is on
// screen" is something the framework already knows.
import 'dart:async';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget pages(int count) => Directionality(
      textDirection: TextDirection.ltr,
      child: Column(children: <Widget>[
        for (int i = 0; i < count; i++)
          DVPageLifecycleHost(key: ValueKey<int>(i), child: const SizedBox()),
      ]),
    );

void main() {
  setUp(DVShowingPages.reset);
  tearDown(DVShowingPages.reset);

  testWidgets('nothing runs before a page is on screen',
      (WidgetTester tester) async {
    var starts = 0;
    DVShowingPages.run('job', start: () => starts++, stop: () {});

    expect(starts, 0, reason: 'registered is not running');
    await tester.pumpWidget(pages(1));
    expect(starts, 1);
  });

  testWidgets('it stops with the last page, not the first',
      (WidgetTester tester) async {
    var starts = 0;
    var stops = 0;
    DVShowingPages.run('job', start: () => starts++, stop: () => stops++);

    // Two at once is ordinary: the page leaving and the page arriving are
    // both mounted for the length of the transition.
    await tester.pumpWidget(pages(2));
    expect(starts, 1, reason: 'the second page is not a second start');
    await tester.pumpWidget(pages(1));
    expect(stops, 0, reason: 'a page is still on screen');
    await tester.pumpWidget(const SizedBox());
    expect(stops, 1);
  });

  testWidgets('it starts again when a page comes back',
      (WidgetTester tester) async {
    var starts = 0;
    DVShowingPages.run('job', start: () => starts++, stop: () {});

    await tester.pumpWidget(pages(1));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(pages(1));

    expect(starts, 2);
  });

  testWidgets('a job registered while a page is showing starts at once',
      (WidgetTester tester) async {
    await tester.pumpWidget(pages(1));
    var starts = 0;

    DVShowingPages.run('job', start: () => starts++, stop: () {});

    expect(starts, 1);
  });

  testWidgets('registering the same job again replaces it',
      (WidgetTester tester) async {
    // A second router is a second registration. It used to be a second
    // timer, and every schedule then ran twice.
    final List<String> log = <String>[];
    await tester.pumpWidget(pages(1));

    DVShowingPages.run('job',
        start: () => log.add('start 1'), stop: () => log.add('stop 1'));
    DVShowingPages.run('job',
        start: () => log.add('start 2'), stop: () => log.add('stop 2'));
    await tester.pumpWidget(const SizedBox());

    expect(log, <String>['start 1', 'stop 1', 'start 2', 'stop 2']);
  });

  testWidgets('a cancelled job is stopped and not started again',
      (WidgetTester tester) async {
    final List<String> log = <String>[];
    DVShowingPages.run('job',
        start: () => log.add('start'), stop: () => log.add('stop'));
    await tester.pumpWidget(pages(1));

    DVShowingPages.cancel('job');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(pages(1));

    expect(log, <String>['start', 'stop']);
  });

  testWidgets('a timer owned this way goes with the tree',
      (WidgetTester tester) async {
    // The assertion is the test framework's own: a periodic timer still
    // running when the tree has been disposed fails the test. That is the
    // failure the client schedules produced in every test that built a
    // router.
    Timer? timer;
    DVShowingPages.run(
      'ticker',
      start: () => timer ??=
          Timer.periodic(const Duration(seconds: 20), (Timer _) {}),
      stop: () {
        timer?.cancel();
        timer = null;
      },
    );

    await tester.pumpWidget(pages(1));
    expect(timer?.isActive, isTrue);
  });
}
