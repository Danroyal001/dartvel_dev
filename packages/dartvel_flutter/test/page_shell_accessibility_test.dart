// Every page is drivable by every input method, without asking.
//
// The accessibility docs told a reader to wrap their page in DVSwitchControl
// and DVHardwareKeys. A page somebody has to remember to make reachable is a
// page that is unreachable on the days they forget, and non-coders building
// in Studio will never wrap anything. The shell already gives every page the
// arrow keys on the same argument; switches and a D-pad are the same
// argument.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget page(List<FocusNode> nodes) => MaterialApp(
      home: DVPageShell(
        spec: const DVPageScaffoldSpec(title: 'Reachable'),
        child: Column(
          children: <Widget>[
            for (final FocusNode node in nodes)
              TextButton(focusNode: node, onPressed: () {}, child: const Text('x')),
          ],
        ),
      ),
    );

void main() {
  switchSettingsTests();

  testWidgets('a D-pad moves focus through a page nobody wrapped',
      (WidgetTester tester) async {
    final List<FocusNode> nodes = <FocusNode>[FocusNode(), FocusNode()];
    addTearDown(() {
      for (final FocusNode node in nodes) {
        node.dispose();
      }
    });

    await tester.pumpWidget(page(nodes));
    await tester.pumpAndSettle();
    nodes.first.requestFocus();
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(nodes[1].hasPrimaryFocus, isTrue,
        reason: 'the remote moved to the next control with nothing wrapped');
  });

  testWidgets('switch control steps a page nobody wrapped',
      (WidgetTester tester) async {
    final List<FocusNode> nodes = <FocusNode>[FocusNode(), FocusNode()];
    addTearDown(() {
      DVAccessibilitySwitchControl.state.enabled = false;
      for (final FocusNode node in nodes) {
        node.dispose();
      }
    });

    await tester.pumpWidget(page(nodes));
    await tester.pumpAndSettle();
    DVAccessibilitySwitchControl.state.enabled = true;
    await tester.pumpAndSettle();
    nodes.first.requestFocus();
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(nodes[1].hasPrimaryFocus, isTrue,
        reason: 'space steps focus while switch control is on');
  });
}

// The switches a reader actually has.
//
// Space and Enter are the common pair, and they are not everyone's. The keys
// and the auto-scan interval used to be arguments on the DVSwitchControl a
// page wrapped itself in; now that every page has one and no page wraps
// anything, they belong beside the on switch, where an application can still
// reach them.
void switchSettingsTests() {
  tearDown(() {
    DVAccessibilitySwitchControl.state
      ..reset()
      ..settings = const DVSwitchControlSettings()
      ..autoScan = null;
  });

  testWidgets('a reader whose switch is not Space says so', (WidgetTester tester) async {
    final List<FocusNode> nodes = <FocusNode>[FocusNode(), FocusNode()];
    addTearDown(() {
      for (final FocusNode node in nodes) {
        node.dispose();
      }
    });

    await tester.pumpWidget(page(nodes));
    await tester.pumpAndSettle();
    DVAccessibilitySwitchControl.state
      ..settings = const DVSwitchControlSettings(next: LogicalKeyboardKey.f7)
      ..enabled = true;
    await tester.pumpAndSettle();
    nodes.first.requestFocus();
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.f7);
    await tester.pumpAndSettle();

    expect(nodes[1].hasPrimaryFocus, isTrue,
        reason: 'the key the reader named steps focus');
  });

  testWidgets('auto-scan steps for a reader with one switch',
      (WidgetTester tester) async {
    final List<FocusNode> nodes = <FocusNode>[FocusNode(), FocusNode()];
    addTearDown(() {
      for (final FocusNode node in nodes) {
        node.dispose();
      }
    });

    await tester.pumpWidget(page(nodes));
    await tester.pumpAndSettle();
    DVAccessibilitySwitchControl.state
      ..autoScan = const Duration(milliseconds: 100)
      ..enabled = true;
    await tester.pumpAndSettle();
    nodes.first.requestFocus();
    await tester.pumpAndSettle();

    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    expect(nodes[1].hasPrimaryFocus, isTrue,
        reason: 'focus stepped on its own, so one switch is enough');
  });
}
