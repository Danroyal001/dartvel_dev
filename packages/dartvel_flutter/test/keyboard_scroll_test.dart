// A page you cannot scroll from the keyboard.
//
// The arrow keys, Page Up, Page Down, Home, End and the space bar scroll a
// document in every browser and every document reader, and on a Dartvel page
// they did nothing: Flutter's scrollables answer a key only while they
// themselves hold focus, and on a freshly opened page nothing does. Found on
// dartvel.dev, where no key scrolled the home page at all.
//
// It is not a web question. A Bluetooth keyboard on Android, a presenter
// clicker paired to an iPhone -- which sends Page Up and Page Down -- and a
// TV remote all produce these keys, so the page has to answer them wherever
// a keyboard can reach it.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A page taller than the viewport, wrapped the way a generated page is.
Widget page({Axis axis = Axis.vertical, ScrollController? controller}) =>
    MaterialApp(
      home: DVPageShell(
        spec: const DVPageScaffoldSpec(title: 'Long'),
        child: SingleChildScrollView(
          controller: controller,
          scrollDirection: axis,
          child: SizedBox(
            height: axis == Axis.vertical ? 4000 : 100,
            width: axis == Axis.horizontal ? 4000 : 100,
          ),
        ),
      ),
    );

void main() {
  late ScrollController controller;

  setUp(() => controller = ScrollController());
  tearDown(() => controller.dispose());

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  testWidgets('the arrow keys scroll a page nobody has clicked on',
      (WidgetTester tester) async {
    await tester.pumpWidget(page(controller: controller));
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.arrowDown);

    expect(controller.offset, greaterThan(0));
  });

  testWidgets('Page Down moves about a screen, Page Up comes back',
      (WidgetTester tester) async {
    await tester.pumpWidget(page(controller: controller));
    await tester.pumpAndSettle();
    final double viewport = tester.getSize(find.byType(Scaffold)).height;

    await press(tester, LogicalKeyboardKey.pageDown);
    final double down = controller.offset;
    await press(tester, LogicalKeyboardKey.pageUp);

    // A screen less an overlap, which is what every reader does: a page turn
    // that shows no line twice loses the reader's place.
    expect(down, greaterThan(viewport * 0.5));
    expect(down, lessThanOrEqualTo(viewport));
    expect(controller.offset, 0);
  });

  testWidgets('Home and End go to the ends', (WidgetTester tester) async {
    await tester.pumpWidget(page(controller: controller));
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.end);
    expect(controller.offset, controller.position.maxScrollExtent);

    await press(tester, LogicalKeyboardKey.home);
    expect(controller.offset, 0);
  });

  testWidgets('a horizontal page answers the left and right arrows',
      (WidgetTester tester) async {
    await tester.pumpWidget(
        page(axis: Axis.horizontal, controller: controller));
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.arrowRight);

    expect(controller.offset, greaterThan(0));
  });

  testWidgets('a text field keeps its own arrow keys',
      (WidgetTester tester) async {
    final TextEditingController text = TextEditingController(text: 'abc');
    addTearDown(text.dispose);
    await tester.pumpWidget(MaterialApp(
      home: DVPageShell(
        spec: const DVPageScaffoldSpec(title: 'Form'),
        child: SingleChildScrollView(
          controller: controller,
          child: Column(
            children: <Widget>[
              TextField(controller: text),
              const SizedBox(height: 4000),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.arrowLeft);

    expect(controller.offset, 0,
        reason: 'the caret moved; the page must not have');
  });
}
