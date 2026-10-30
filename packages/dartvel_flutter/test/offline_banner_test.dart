// Every page says when the device is offline, without asking.
//
// Error, Empty, and Loading States: an offline banner is driven by the
// connectivity signal, and it is the rendering of state the framework already
// has. DV.Platform.network existed and nothing showed it, so a reader on a
// train saw a page that looked live and wrote into a void. A banner an
// application has to remember to add is missing on the days it forgets, so
// the page shell carries it.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/network_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _page() => const MaterialApp(
      home: DVPageShell(
        spec: DVPageScaffoldSpec(title: 'Orders'),
        child: Text('the page'),
      ),
    );

void main() {
  setUp(DVNetworkSource.reset);
  tearDown(() {
    DVNetworkSource.reset();
    DV.I18n.reset();
  });

  testWidgets('an offline device is told so on a page nobody wrapped',
      (WidgetTester tester) async {
    DVNetworkSource.report(DVNetworkStatus.offline);

    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    expect(find.text("You're offline"), findsOneWidget);
    expect(find.text('the page'), findsOneWidget);
  });

  testWidgets('the banner comes and goes with the signal',
      (WidgetTester tester) async {
    DVNetworkSource.report(DVNetworkStatus.online);
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();
    expect(find.text("You're offline"), findsNothing);

    DVNetworkSource.report(DVNetworkStatus.offline);
    await tester.pumpAndSettle();
    expect(find.text("You're offline"), findsOneWidget);

    DVNetworkSource.report(DVNetworkStatus.online);
    await tester.pumpAndSettle();
    expect(find.text("You're offline"), findsNothing);
  });

  testWidgets('unknown and metered are not offline', (WidgetTester tester) async {
    // Unknown is a target with no binding: claiming offline there would put
    // a banner on every page of every app on that target, for ever.
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();
    expect(find.text("You're offline"), findsNothing);

    DVNetworkSource.report(DVNetworkStatus.metered);
    await tester.pumpAndSettle();
    expect(find.text("You're offline"), findsNothing);
  });

  testWidgets('the page keeps its state when the banner appears',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: DVPageShell(
        spec: const DVPageScaffoldSpec(title: 'Draft'),
        child: _Counter(),
      ),
    ));
    await tester.tap(find.text('count 0'));
    await tester.pumpAndSettle();
    expect(find.text('count 1'), findsOneWidget);

    DVNetworkSource.report(DVNetworkStatus.offline);
    await tester.pumpAndSettle();

    expect(find.text('count 1'), findsOneWidget,
        reason: 'going offline must not rebuild the page from scratch');
  });

  testWidgets('a screen reader hears it once, as a live region',
      (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    DVNetworkSource.report(DVNetworkStatus.offline);

    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.bySemanticsLabel("You're offline")),
      matchesSemantics(label: "You're offline", isLiveRegion: true),
    );
    semantics.dispose();
  });

  testWidgets('the words are a framework string the catalogue replaces',
      (WidgetTester tester) async {
    DV.I18n.load(const DVTranslationCatalog(
      locale: LocaleTag.frFR,
      messages: <DVTranslationKey, String>{
        DVFrameworkStrings.offline: 'Vous êtes hors ligne',
      },
    ));
    DV.I18n.useLocale(LocaleTag.frFR);
    DVNetworkSource.report(DVNetworkStatus.offline);

    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    expect(find.text('Vous êtes hors ligne'), findsOneWidget);
  });
}

class _Counter extends StatefulWidget {
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => setState(() => count += 1),
        child: Text('count $count'),
      );
}
