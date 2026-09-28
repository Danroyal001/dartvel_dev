// A thin bar across the top while something loads, on every platform.
//
// The web page has one in its HTML until Flutter's first frame. After that,
// and on every other platform from the start, the loads a person waits on are
// a deferred page arriving and a page's data -- both shown with
// DvDefaultLoading -- and whatever an application tracks through DV.progress.
// Each shows the same bar: themed, still under reduced motion, and a
// progress indicator to assistive technology.
import 'dart:async';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _shell(Widget child, {bool reduced = false}) => MaterialApp(
      theme: ThemeData(colorScheme: const ColorScheme.light(primary: Color(0xFF123456))),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: DVPageShell(
          spec: const DVPageScaffoldSpec(title: 't'),
          child: child,
        ),
      ),
    );

void main() {
  tearDown(() {
    DV.progress.enabled = true;
    DV.progress.color = null;
  });

  testWidgets('a page that is loading shows the bar at the top, not a spinner '
      'in the middle', (WidgetTester tester) async {
    await tester.pumpWidget(_shell(const DvDefaultLoading()));
    final Finder bar = find.byType(DVTopProgressBar);
    expect(bar, findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.getTopLeft(bar).dy, lessThan(80));
    expect(tester.getSize(bar).height, lessThanOrEqualTo(4));
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
  });

  testWidgets('what an application tracks shows until it is done',
      (WidgetTester tester) async {
    final Completer<void> saving = Completer<void>();
    await tester.pumpWidget(_shell(const Text('page')));
    expect(find.byType(DVTopProgressBar), findsNothing);

    final Future<void> tracked = DV.progress.track(saving.future);
    await tester.pump();
    expect(find.byType(DVTopProgressBar), findsOneWidget);

    saving.complete();
    await tracked;
    await tester.pump();
    expect(find.byType(DVTopProgressBar), findsNothing);
  });

  testWidgets('start returns the one call that ends it, once',
      (WidgetTester tester) async {
    await tester.pumpWidget(_shell(const Text('page')));
    final VoidCallback a = DV.progress.start();
    final VoidCallback b = DV.progress.start();
    await tester.pump();
    a();
    a(); // a second end of the same load does not end the other one
    await tester.pump();
    expect(find.byType(DVTopProgressBar), findsOneWidget);
    b();
    await tester.pump();
    expect(find.byType(DVTopProgressBar), findsNothing);
  });

  testWidgets('it takes the theme colour, or the one the app gives it',
      (WidgetTester tester) async {
    await tester.pumpWidget(_shell(const DvDefaultLoading()));
    expect(tester.widget<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator)).color,
        const Color(0xFF123456));
    DV.progress.color = const Color(0xFF00FF00);
    await tester.pumpWidget(_shell(const DvDefaultLoading(key: ValueKey<int>(2))));
    expect(tester.widget<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator)).color,
        const Color(0xFF00FF00));
  });

  testWidgets('with reduced motion it stands still, and still says loading',
      (WidgetTester tester) async {
    await tester.pumpWidget(_shell(const DvDefaultLoading(), reduced: true));
    expect(find.byType(DVTopProgressBar), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    // Nothing is animating, so the frame settles.
    await tester.pumpAndSettle();
  });

  testWidgets('an application can turn the tracked bar off',
      (WidgetTester tester) async {
    DV.progress.enabled = false;
    await tester.pumpWidget(_shell(const Text('page')));
    final VoidCallback end = DV.progress.start();
    await tester.pump();
    expect(find.byType(DVTopProgressBar), findsNothing);
    end();
  });
}
