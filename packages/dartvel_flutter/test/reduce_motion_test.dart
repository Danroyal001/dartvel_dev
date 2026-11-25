// Reduce Motion, as Flutter 3.50 reports it.
//
// Flutter has two settings, and Dartvel only read one. `disableAnimations` is
// Android's "Remove animations" (and the web's prefers-reduced-motion); iOS
// "Reduce Motion" arrives separately, as `MediaQueryData.reduceMotion`, and
// Flutter's own animations do not react to it. So on an iPhone with Reduce
// Motion on, every page transition, every animated box, the back-to-top
// scroll and the keyboard scroll all still moved. Every animation Dartvel
// runs itself now jumps to its end state when either setting is on.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/find/find_in_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// [home] in an app whose every route sees Reduce Motion as [reduce].
Widget app(Widget home, {bool reduce = true}) => MaterialApp(
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(reduceMotion: reduce),
        child: child!,
      ),
      home: home,
    );

class _Page extends DVClassWidget {
  const _Page() : super(pageScrollToTop: true);
  @override
  Widget build(BuildContext context) =>
      const SingleChildScrollView(child: SizedBox(height: 5000, child: Text('page')));
}

void main() {
  tearDown(() => const DVAccessibility().clearReducedMotion());

  group('the setting itself', () {
    testWidgets('context.screen reports Reduce Motion, not only Remove animations',
        (WidgetTester tester) async {
      late bool reduced;
      await tester.pumpWidget(app(Builder(builder: (BuildContext context) {
        reduced = context.screen.reducedMotion;
        return const SizedBox();
      })));
      expect(reduced, isTrue);
    });

    testWidgets('and is off when neither setting is on', (WidgetTester tester) async {
      late bool reduced;
      await tester.pumpWidget(app(reduce: false, Builder(builder: (BuildContext context) {
        reduced = context.screen.reducedMotion;
        return const SizedBox();
      })));
      expect(reduced, isFalse);
    });

    testWidgets('DV.Accessibility follows the platform Reduce Motion feature',
        (WidgetTester tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(reduceMotion: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      expect(DV.Accessibility.reducedMotion, isTrue);
    });
  });

  group('an animated box', () {
    Widget box(double width) => Align(
          alignment: .topLeft,
          child: DVBox(
            const SizedBox(height: 10),
            DVModifier().width(width).animate(const Duration(milliseconds: 300)),
          ),
        );

    testWidgets('takes its new size at once with Reduce Motion on',
        (WidgetTester tester) async {
      await tester.pumpWidget(app(box(100)));
      await tester.pumpWidget(app(box(200)));
      expect(tester.getSize(find.byType(DVBox)).width, 200);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('and still animates without it', (WidgetTester tester) async {
      await tester.pumpWidget(app(reduce: false, box(100)));
      await tester.pumpWidget(app(reduce: false, box(200)));
      await tester.pump(const Duration(milliseconds: 100));
      final double width = tester.getSize(find.byType(DVBox)).width;
      expect(width, greaterThan(100));
      expect(width, lessThan(200));
      await tester.pumpAndSettle();
    });
  });

  group('page transitions', () {
    Widget routed({required bool reduce}) {
      final GoRouter router = GoRouter(routes: <RouteBase>[
        for (final String path in <String>['/', '/next'])
          GoRoute(
            path: path,
            pageBuilder: (BuildContext context, GoRouterState state) => dvTransitionPage<void>(
              key: state.pageKey,
              spec: const PageTransitionSpec(
                type: DvTransition.slideLeft,
                duration: Duration(milliseconds: 300),
              ),
              child: Text('page $path'),
            ),
          ),
      ]);
      return MaterialApp.router(
        routerConfig: router,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(reduceMotion: reduce),
          child: child!,
        ),
      );
    }

    testWidgets('a pushed page is there on the next frame with Reduce Motion on',
        (WidgetTester tester) async {
      await tester.pumpWidget(routed(reduce: true));
      GoRouter.of(tester.element(find.text('page /'))).push('/next');
      await tester.pump();
      await tester.pump();
      expect(find.text('page /next'), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'no transition frames follow');
    });

    testWidgets('and slides in without it', (WidgetTester tester) async {
      await tester.pumpWidget(routed(reduce: false));
      GoRouter.of(tester.element(find.text('page /'))).push('/next');
      await tester.pump();
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpAndSettle();
    });
  });

  testWidgets('back to top jumps instead of scrolling with Reduce Motion on',
      (WidgetTester tester) async {
    await tester.pumpWidget(app(const Scaffold(body: _Page())));
    await tester.pump();
    await tester.tap(find.byTooltip('To the bottom'));
    await tester.pump();
    final ScrollPosition position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(position.pixels, position.maxScrollExtent);
  });

  testWidgets('the End key jumps instead of scrolling with Reduce Motion on',
      (WidgetTester tester) async {
    final ScrollController controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(DVPageShell(
      spec: const DVPageScaffoldSpec(title: 'Long'),
      child: SingleChildScrollView(
        controller: controller,
        child: const SizedBox(height: 4000, width: 100),
      ),
    )));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(controller.offset, controller.position.maxScrollExtent);
  });

  testWidgets('the loading bar stands still with Reduce Motion on',
      (WidgetTester tester) async {
    await tester.pumpWidget(app(const DVPageShell(
      spec: DVPageScaffoldSpec(title: 't'),
      child: DvDefaultLoading(),
    )));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
  });

  testWidgets('a find match is scrolled to at once with Reduce Motion on',
      (WidgetTester tester) async {
    final ScrollController controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(DVPageShell(
      spec: const DVPageScaffoldSpec(title: 'Policy'),
      child: SingleChildScrollView(
        controller: controller,
        child: Column(children: <Widget>[
          for (int i = 0; i < 60; i++)
            Padding(padding: const .all(8), child: Text('Paragraph $i.')),
          const Text('The last line.'),
        ]),
      ),
    )));
    final Future<bool> revealed = DVFindInPage.reveal('The last line.');
    await tester.pump();
    await tester.pump();
    final ScrollPosition position = controller.position;
    expect(position.pixels, greaterThan(0), reason: 'already there, not on its way');
    final double landed = position.pixels;
    await tester.pumpAndSettle();
    expect(position.pixels, landed);
    expect(await revealed, isTrue);
  });
}
