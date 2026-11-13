// Links that come on screen while the page is scrolling wait for it to stop.
//
// tools.sigmadev.digital lists 178 tools, each its own page and so its own
// code module. A fast scroll down that list left card after card on screen
// for the 300 ms that makes a link "read", and each one started fetching and
// instantiating its page's code there and then: about 150 modules arrived
// mid-scroll on a cold visit, with one 833 ms freeze and 2 s of frames over
// 100 ms on a throttled connection (13 Nov 2026). A visitor who is still
// scrolling has not chosen anything yet; the page they stop on has their next
// tap. So visible preloads queue until the page has stopped scrolling for
// [dvLinkScrollSettle], then run one at a time, each link checked again on
// the way out of the queue.
import 'dart:async';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

GoRouter routerWith(Widget subject) => GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (BuildContext context, GoRouterState state) => Scaffold(body: subject)),
        GoRoute(path: '/tool/:id', builder: (BuildContext context, GoRouterState state) => const Scaffold(body: Text('tool'))),
      ],
    );

Future<void> pump(WidgetTester tester, Widget subject) async {
  final router = routerWith(subject);
  DVNavigation.attach(router);
  addTearDown(DVNavigation.detach);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump();
}

/// A long list of tool links, 100 points apart, each reporting its preload.
Widget toolList(ScrollController controller, Future<void> Function(int index) onLoad) => ListView.builder(
      controller: controller,
      itemCount: 200,
      itemExtent: 100,
      itemBuilder: (BuildContext context, int index) => DVNavLink(
        to: DVRouteTarget('/tool/$index'),
        preload: DVLinkPreload.visible,
        onPreload: () => onLoad(index),
        child: DVText('Tool $index'),
      ),
    );

void main() {
  testWidgets('nothing is fetched while the page keeps scrolling, however long a link stays on screen',
      (WidgetTester tester) async {
    final List<int> loaded = <int>[];
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pump(tester, toolList(controller, (int index) async => loaded.add(index)));
    // Wait out the links on screen at the start, so only scrolling is measured.
    await tester.pump(const Duration(seconds: 5));
    for (int i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    loaded.clear();

    // A slow, steady scroll: 20 points every 50 ms for 3 s. Every link that
    // comes on screen stays there well past the 300 ms delay.
    for (int step = 0; step < 60; step++) {
      controller.jumpTo(controller.offset + 20);
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(loaded, isEmpty, reason: 'still scrolling: nothing has been chosen yet');

    // Stopped: the links on screen now are fetched.
    await tester.pump(dvLinkScrollSettle + dvLinkVisibleDelay);
    for (int i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    final int firstOnScreen = (controller.offset / 100).floor();
    expect(loaded, isNotEmpty);
    expect(loaded.every((int index) => index >= firstOnScreen && index <= firstOnScreen + 6), isTrue,
        reason: 'only links on screen where the page stopped; got $loaded from $firstOnScreen');
  });

  testWidgets('one at a time: the next starts when the one before has finished', (WidgetTester tester) async {
    final Map<int, Completer<void>> pending = <int, Completer<void>>{};
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pump(tester, toolList(controller, (int index) => (pending[index] = Completer<void>()).future));

    await tester.pump(dvLinkVisibleDelay + dvLinkScrollSettle);
    await tester.pump(const Duration(milliseconds: 100));
    expect(pending.length, 1, reason: 'six links on screen, but one fetch at a time');

    pending.values.first.complete();
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(pending.length, 2);
    for (final Completer<void> completer in pending.values) {
      if (!completer.isCompleted) completer.complete();
    }
    for (int i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      for (final Completer<void> completer in pending.values) {
        if (!completer.isCompleted) completer.complete();
      }
    }
  });

  testWidgets('a link that has left the screen by its turn in the queue is not fetched', (WidgetTester tester) async {
    final Map<int, Completer<void>> pending = <int, Completer<void>>{};
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pump(tester, toolList(controller, (int index) => (pending[index] = Completer<void>()).future));

    await tester.pump(dvLinkVisibleDelay + dvLinkScrollSettle);
    await tester.pump(const Duration(milliseconds: 100));
    expect(pending.keys, <int>[0]);

    // The visitor scrolls far away while the first fetch is still running.
    controller.jumpTo(10000);
    await tester.pump();
    pending[0]!.complete();
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(pending.keys.where((int index) => index < 20), <int>[0],
        reason: 'links 1 to 5 were queued at the top of the page, which is gone');
    for (int i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      for (final Completer<void> completer in pending.values) {
        if (!completer.isCompleted) completer.complete();
      }
    }
  });

  testWidgets('nothing of the queue outlives the page: no timer is left when the last link goes', (WidgetTester tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pump(tester, toolList(controller, (int index) async {}));
    await tester.pump(dvLinkVisibleDelay + dvLinkScrollSettle);
    // A scroll, then the page goes at once: the settle wait it started must
    // go with it, or a test of any app with links fails on a pending timer.
    controller.jumpTo(500);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.transientCallbackCount, 0);
  });
}
