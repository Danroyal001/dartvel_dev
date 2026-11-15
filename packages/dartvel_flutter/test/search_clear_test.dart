// Every search box in every Dartvel app has an "x" that empties it.
//
// Each search box Dartvel drew -- a `.input()` field used for search, Studio's
// record and element searches, Studio's command palette -- made the reader
// select what they had typed and delete it to start again, where every
// platform's own search box has an "x" for that. Now a search field has one by
// default: shown only while there is text, it empties the field, keeps the
// focus in it, tells the field's change callback, and is a named, keyboard
// reachable button. Escape does the same while there is text to clear.
//
// These drive the field as a person does: by typing, tapping, Tab and Escape,
// and by what a screen reader is told.
import 'dart:ui' show SemanticsInputType;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/studio/studio_command_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

final Finder _clear = find.byTooltip('Clear search');

EditableText _editable(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText));

void main() {
  group('a search field made with .input(search: true)', () {
    late List<String> changes;
    late int cleared;

    Widget field({DVClearButton? clearButton}) => DVText('').modifier(
          DVModifier().input(
            label: 'Search',
            search: true,
            clearButton: clearButton,
            onChanged: changes.add,
            onCleared: () => cleared++,
          ),
        );

    setUp(() {
      changes = <String>[];
      cleared = 0;
    });

    testWidgets('has no "x" while it is empty', (WidgetTester tester) async {
      await _pump(tester, field());
      expect(_clear, findsNothing);
    });

    testWidgets('shows the "x" once there is text, and hides it again when '
        'the text is deleted', (WidgetTester tester) async {
      await _pump(tester, field());
      await tester.enterText(find.byType(TextField), 'cache');
      await tester.pump();
      expect(_clear, findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(_clear, findsNothing);
    });

    testWidgets('pressing the "x" empties the field, keeps the focus in it, '
        'and tells onChanged and onCleared', (WidgetTester tester) async {
      await _pump(tester, field());
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'cache');
      await tester.pump();
      changes.clear();

      await tester.tap(_clear);
      await tester.pump();

      expect(_editable(tester).controller.text, isEmpty);
      expect(_editable(tester).focusNode.hasFocus, isTrue,
          reason: 'the next search is typed straight away');
      expect(changes, <String>['']);
      expect(cleared, 1);
      expect(_clear, findsNothing);
    });

    testWidgets('Escape in the field clears it and keeps the focus',
        (WidgetTester tester) async {
      await _pump(tester, field());
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'cache');
      await tester.pump();
      changes.clear();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(_editable(tester).controller.text, isEmpty);
      expect(_editable(tester).focusNode.hasFocus, isTrue);
      expect(changes, <String>['']);
      expect(cleared, 1);
    });

    testWidgets('Escape in an empty field is left for the page or dialog',
        (WidgetTester tester) async {
      int dismissed = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Actions(
            actions: <Type, Action<Intent>>{
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (_) => dismissed++,
              ),
            },
            child: field(),
          ),
        ),
      ));
      await tester.tap(find.byType(TextField));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(cleared, 0);
      expect(dismissed, 1, reason: 'Escape still closes what the field is in');
    });

    testWidgets('the "x" is a named button with its tooltip, and Tab reaches '
        'it from the field', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pump(tester, field());
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'cache');
      await tester.pump();

      expect(
        tester.getSemantics(_clear),
        matchesSemantics(
          label: 'Clear search',
          isButton: true,
          hasTapAction: true,
          isFocusable: true,
          hasFocusAction: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final FocusNode? focused = FocusManager.instance.primaryFocus;
      expect(focused?.context, isNotNull);
      expect(
        find.ancestor(
          of: find.byWidgetPredicate(
              (Widget w) => identical(w, focused!.context!.widget)),
          matching: _clear,
        ),
        findsOneWidget,
        reason: 'Tab from the field lands on the "x"',
      );

      // And Enter on it clears, as a click does.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(_editable(tester).controller.text, isEmpty);
      expect(_editable(tester).focusNode.hasFocus, isTrue);
      handle.dispose();
    });

    testWidgets('is announced as a search box, which the web draws as '
        '<input type="search">', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pump(tester, field());
      final SemanticsData data =
          tester.getSemantics(find.byType(TextField)).getSemanticsData();
      expect(data.flagsCollection.isTextField, isTrue);
      expect(data.inputType, SemanticsInputType.search);
      handle.dispose();
    });

    testWidgets('clearButton: DVClearButton.none turns the "x" and Escape off',
        (WidgetTester tester) async {
      await _pump(tester, field(clearButton: DVClearButton.none));
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'cache');
      await tester.pump();
      expect(_clear, findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(_editable(tester).controller.text, 'cache');
      expect(cleared, 0);
    });

    testWidgets('DVClearButton.custom draws the application\'s own control, '
        'which clears the same way', (WidgetTester tester) async {
      await _pump(
        tester,
        field(
          clearButton: DVClearButton.custom(
            (BuildContext context, VoidCallback clear) => TextButton(
              onPressed: clear,
              child: const Text('Reset'),
            ),
          ),
        ),
      );
      expect(find.text('Reset'), findsNothing);
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'cache');
      await tester.pump();
      expect(_clear, findsNothing);

      await tester.tap(find.text('Reset'));
      await tester.pump();
      expect(_editable(tester).controller.text, isEmpty);
      expect(_editable(tester).focusNode.hasFocus, isTrue);
      expect(cleared, 1);
    });

    testWidgets('keeps its "x" when it is also given a semantic label',
        (WidgetTester tester) async {
      await _pump(
        tester,
        DVText('').modifier(DVModifier()
            .input(hint: 'Search', search: true, onChanged: changes.add)
            .semanticLabel('Search the tools')),
      );
      await tester.enterText(find.byType(TextField), 'margin');
      await tester.pump();
      expect(_clear, findsOneWidget);
    });
  });

  testWidgets('a field that is not a search field has no "x"',
      (WidgetTester tester) async {
    await _pump(
      tester,
      DVText('').modifier(DVModifier().input(label: 'Name', onChanged: (_) {})),
    );
    await tester.enterText(find.byType(TextField), 'Ada');
    await tester.pump();
    expect(_clear, findsNothing);
  });

  group('Studio', () {
    testWidgets('a Studio search input has the "x", which clears and keeps '
        'the focus', (WidgetTester tester) async {
      String query = 'x';
      await _pump(
        tester,
        DVStudioTextInput(
          search: true,
          placeholder: 'Search elements',
          onChanged: (String value) => query = value,
        ),
      );
      expect(_clear, findsNothing);
      await tester.tap(find.byType(EditableText));
      await tester.enterText(find.byType(EditableText), 'col');
      await tester.pump();
      expect(_clear, findsOneWidget);

      await tester.tap(_clear);
      await tester.pump();
      expect(_editable(tester).controller.text, isEmpty);
      expect(_editable(tester).focusNode.hasFocus, isTrue);
      expect(query, isEmpty);
    });

    testWidgets('the command palette\'s search has the "x"',
        (WidgetTester tester) async {
      await _pump(
        tester,
        const DVStudioCommandPalette(commands: <DVStudioCommand>[]),
      );
      await tester.enterText(
          find.byKey(DVStudioCommandPalette.searchKey), 'pages');
      await tester.pump();
      expect(_clear, findsOneWidget);

      await tester.tap(_clear);
      await tester.pump();
      expect(_editable(tester).controller.text, isEmpty);
      expect(_editable(tester).focusNode.hasFocus, isTrue);
    });
  });
}
