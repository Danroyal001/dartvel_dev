// Esc on a page belongs to whatever the page has open, and otherwise to the
// browser.
//
// The selection area every page is wrapped in answers Esc by hiding its menu
// -- and, with no menu showing, still reported the key handled. On the web a
// handled key is a key the page called preventDefault on, so the browser
// never saw it: Esc from the page stopped closing the browser's find bar,
// which is what a reader presses after Ctrl+F. A key the page has no use for
// is reported unhandled; a key that closes something is handled, as before.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget longPage({Widget Function(Widget page)? around, Widget? extra}) {
  final Widget page = DVPageShell(
    spec: const DVPageScaffoldSpec(title: 'Policy'),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          if (extra != null) extra,
          for (int i = 0; i < 60; i++)
            Padding(
              padding: const .all(8),
              child: Text('Paragraph $i says something about records.'),
            ),
        ],
      ),
    ),
  );
  return MaterialApp(home: around == null ? page : around(page));
}

Future<void> clickOn(WidgetTester tester, Finder target) async {
  final TestGesture mouse = await tester.startGesture(
    tester.getCenter(target),
    kind: PointerDeviceKind.mouse,
  );
  await mouse.up();
  await tester.pumpAndSettle();
}

Future<void> rightClickOn(WidgetTester tester, Finder target) async {
  final TestGesture mouse = await tester.startGesture(
    tester.getCenter(target),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await mouse.up();
  await tester.pumpAndSettle();
}

double scrollOffset(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).last).position.pixels;

void main() {
  testWidgets('Esc on a page with nothing open is left to the browser', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(longPage());
    await tester.pumpAndSettle();

    expect(
      await tester.sendKeyEvent(LogicalKeyboardKey.escape),
      isFalse,
      reason:
          'a handled key is preventDefault-ed on the web, and the '
          "browser's find bar never hears the Esc",
    );
  });

  testWidgets('and after the reader clicked into the text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(longPage());
    await tester.pumpAndSettle();
    await clickOn(
      tester,
      find.text('Paragraph 2 says something about records.'),
    );

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.escape), isFalse);
  });

  testWidgets('a click into the text leaves the page keys working', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(longPage());
    await tester.pumpAndSettle();
    await clickOn(
      tester,
      find.text('Paragraph 2 says something about records.'),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(
      scrollOffset(tester),
      greaterThan(0),
      reason: 'the page answers Page Down after a click as before one',
    );
  });

  testWidgets(
    'a selection survives, and copies, after the click that made it',
    (WidgetTester tester) async {
      final List<String> clipboard = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(longPage());
      await tester.pumpAndSettle();
      final Rect box = tester.getRect(
        find.text('Paragraph 1 says something about records.'),
      );
      final TestGesture mouse = await tester.startGesture(
        box.centerLeft + const Offset(1, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await mouse.moveTo(box.centerRight - const Offset(1, 0));
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(clipboard, isNotEmpty);
      expect(clipboard.last, contains('says something about records'));
    },
  );

  testWidgets('Esc closes the selection menu, and is handled', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(longPage());
    await tester.pumpAndSettle();
    await rightClickOn(
      tester,
      find.text('Paragraph 2 says something about records.'),
    );
    expect(find.text('Select all'), findsOneWidget);

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.escape), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Select all'), findsNothing);

    expect(
      await tester.sendKeyEvent(LogicalKeyboardKey.escape),
      isFalse,
      reason: 'with the menu gone there is nothing left on the page',
    );
  });

  testWidgets('Esc still closes a dialog opened from the page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      longPage(
        extra: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const AlertDialog(content: Text('Delete it?')),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Delete it?'), findsOneWidget);

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.escape), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Delete it?'), findsNothing);
  });

  testWidgets('Esc still closes a menu open on the page', (
    WidgetTester tester,
  ) async {
    final MenuController menu = MenuController();
    final FocusNode button = FocusNode();
    addTearDown(button.dispose);
    await tester.pumpWidget(
      longPage(
        extra: MenuAnchor(
          controller: menu,
          menuChildren: <Widget>[
            MenuItemButton(onPressed: () {}, child: const Text('Rename')),
          ],
          child: TextButton(
            focusNode: button,
            onPressed: menu.open,
            child: const Text('Actions'),
          ),
        ),
      ),
    );
    // Opened from the keyboard: Esc closes a menu that focus is in.
    button.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.escape), isTrue);
    await tester.pumpAndSettle();
    expect(menu.isOpen, isFalse);
  });

  testWidgets("Esc still reaches the application's own dismiss action", (
    WidgetTester tester,
  ) async {
    int dismissed = 0;
    await tester.pumpWidget(
      longPage(
        around: (Widget page) => Actions(
          actions: <Type, Action<Intent>>{
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) => dismissed++,
            ),
          },
          child: page,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await clickOn(
      tester,
      find.text('Paragraph 2 says something about records.'),
    );

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.escape), isTrue);
    expect(dismissed, 1);
  });

  testWidgets('Esc during composition is left to the input method', (
    WidgetTester tester,
  ) async {
    // Flutter's own text field reports Esc handled whatever the page does;
    // what the page decides is whether the Esc goes on to close something.
    // During a composition it must not: the input method's Esc cancels the
    // composition, and closing the page's sheet with it loses the text.
    int dismissed = 0;
    final TextEditingController text = TextEditingController();
    addTearDown(text.dispose);
    await tester.pumpWidget(
      longPage(
        extra: TextField(controller: text),
        around: (Widget page) => Actions(
          actions: <Type, Action<Intent>>{
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) => dismissed++,
            ),
          },
          child: page,
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    text.value = const TextEditingValue(
      text: 'にほ',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(dismissed, 0, reason: 'the composition, not the page, takes Esc');
    expect(text.text, 'にほ');

    text.value = const TextEditingValue(
      text: '日本',
      selection: TextSelection.collapsed(offset: 2),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(dismissed, 1, reason: 'with the composition done, Esc goes on');
  });
}
