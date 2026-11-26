// DARTVEL_OFF=page-scroll-button: the server says so in every document it
// serves (`<meta name="dartvel-off">`), the app reads it once at start
// (DVOffSwitches.current), and no page builds the button or its tap target.
// On sigmadev.digital the button's tap area covered the page, and turning it
// off took a 25-minute rebuild.
import 'package:dartvel_core/dartvel.dart' show DVOffSwitches;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Page extends DVClassWidget {
  const _Page() : super(pageScrollToTop: true);
  @override
  Widget build(BuildContext context) => SingleChildScrollView(child: Column(children: <Widget>[
        for (int row = 0; row < 100; row++) SizedBox(height: 50, child: Text('Row $row')),
      ]));
}

Widget _longColumn() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[for (int row = 0; row < 40; row++) SizedBox(height: 50, child: Text('Row $row'))],
    );

void main() {
  tearDown(() => DVOffSwitches.current = DVOffSwitches.none);

  testWidgets('switched off: no button on a page that asked for one, and it still scrolls', (WidgetTester tester) async {
    DVOffSwitches.current = DVOffSwitches.parse('page-scroll-button');
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: _Page())));
    await tester.pump();
    expect(find.byTooltip('To the bottom'), findsNothing);
    expect(find.byKey(const ValueKey<String>('dv-page-scroll')), findsNothing);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels, greaterThan(0));
  });

  testWidgets('switched off: none in a page shell either', (WidgetTester tester) async {
    DVOffSwitches.current = DVOffSwitches.parse('page-scroll-button');
    await tester.pumpWidget(MaterialApp(
        home: DVPageShell(spec: const DVPageScaffoldSpec(title: 'Long'), child: DVPageScrollFrame(child: _longColumn()))));
    await tester.pumpAndSettle();
    expect(find.byTooltip('To the bottom'), findsNothing);
    expect(find.byKey(const ValueKey<String>('dv-page-scroll')), findsNothing);
  });

  testWidgets('another switch leaves the button alone', (WidgetTester tester) async {
    DVOffSwitches.current = DVOffSwitches.parse('analytics ssr-first');
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: _Page())));
    await tester.pump();
    expect(find.byTooltip('To the bottom'), findsOneWidget);
  });
}
