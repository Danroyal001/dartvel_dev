// Ctrl+K (Cmd+K on a Mac) opens a command palette over Studio: every
// section, every page, every element on the page being edited and what can
// be done to it, found by typing a few letters of it.
import 'dart:async';

import 'package:dartvel_flutter/src/studio/studio_command_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ranking', () {
    final List<DVStudioCommand> commands = <DVStudioCommand>[
      DVStudioCommand(id: 'flags', title: 'Go to Flags', run: () {}),
      DVStudioCommand(id: 'pages', title: 'Go to Pages', run: () {}),
      DVStudioCommand(
          id: 'pricing', title: 'Open page /pricing', keywords: <String>['plans'], run: () {}),
      DVStudioCommand(id: 'undo', title: 'Undo', shortcut: 'Ctrl+Z', run: () {}),
    ];

    test('letters in order find a command, the tighter match first', () {
      expect(dvRankCommands('gtp', commands).map((DVStudioCommand c) => c.id).first,
          'pages');
      expect(dvRankCommands('undo', commands).first.id, 'undo');
      expect(dvRankCommands('zzz', commands), isEmpty);
    });

    test('keywords count as well as titles', () {
      expect(dvRankCommands('plans', commands).single.id, 'pricing');
    });

    test('an empty query lists everything as given', () {
      expect(dvRankCommands('', commands).map((DVStudioCommand c) => c.id),
          <String>['flags', 'pages', 'pricing', 'undo']);
    });
  });

  testWidgets('Ctrl+K opens it, typing narrows it, Enter runs the top one',
      (WidgetTester tester) async {
    final List<String> ran = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: DVStudioCommandScope(
        child: Builder(builder: (BuildContext context) {
          DVStudioCommandScope.provide(context, 'test', () => <DVStudioCommand>[
                DVStudioCommand(id: 'flags', title: 'Go to Flags', run: () => ran.add('flags')),
                DVStudioCommand(id: 'pages', title: 'Go to Pages', run: () => ran.add('pages')),
              ]);
          return const Scaffold(body: Focus(autofocus: true, child: Text('studio')));
        }),
      ),
    ));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(DVStudioCommandPalette.searchKey), findsOneWidget);
    expect(find.text('Go to Flags'), findsOneWidget);

    await tester.enterText(find.byKey(DVStudioCommandPalette.searchKey), 'pag');
    await tester.pump();
    expect(find.text('Go to Flags'), findsNothing);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(ran, <String>['pages']);
    expect(find.byKey(DVStudioCommandPalette.searchKey), findsNothing);
  });

  testWidgets('arrows move the choice and Esc closes without running anything',
      (WidgetTester tester) async {
    final List<String> ran = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: DVStudioCommandScope(
        child: Builder(builder: (BuildContext context) {
          DVStudioCommandScope.provide(context, 'test', () => <DVStudioCommand>[
                DVStudioCommand(id: 'a', title: 'Alpha', run: () => ran.add('a')),
                DVStudioCommand(id: 'b', title: 'Beta', run: () => ran.add('b')),
              ]);
          return const Scaffold(body: Focus(autofocus: true, child: Text('studio')));
        }),
      ),
    ));
    await tester.pump();
    unawaited(DVStudioCommandScope.open(tester.element(find.text('studio'))));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(ran, <String>['b']);

    unawaited(DVStudioCommandScope.open(tester.element(find.text('studio'))));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(DVStudioCommandPalette.searchKey), findsNothing);
    expect(ran, <String>['b']);
  });
}
