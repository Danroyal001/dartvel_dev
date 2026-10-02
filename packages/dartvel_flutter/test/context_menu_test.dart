// One context menu, opened the way each platform opens one: a right-click
// (mouse, trackpad), a long-press (touch), the menu key or Shift+F10
// (keyboard), and the screen reader's actions.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const List<DVMenuItem> items = <DVMenuItem>[
    DVMenuItem(id: 'open', label: 'Open'),
    DVMenuItem(id: 'rename', label: 'Rename', shortcut: 'mod+r'),
    DVMenuItem(id: 'delete', label: 'Delete', enabled: false),
    DVMenuItem(id: 'share', label: 'Share', children: <DVMenuItem>[
      DVMenuItem(id: 'share.link', label: 'Copy link'),
    ]),
  ];

  Future<List<String>> pump(WidgetTester tester, {TargetPlatform platform = TargetPlatform.android}) async {
    final List<String> chosen = <String>[];
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: platform),
      home: Scaffold(
        body: Center(
          child: DVContextMenu(
            items: items,
            onSelected: chosen.add,
            child: const SizedBox(width: 200, height: 100, child: Text('Report.pdf')),
          ),
        ),
      ),
    ));
    return chosen;
  }

  testWidgets('a right-click opens it, and an item runs once', (WidgetTester tester) async {
    final List<String> chosen = await pump(tester, platform: TargetPlatform.windows);
    expect(find.text('Open'), findsNothing);
    await tester.tap(find.text('Report.pdf'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(chosen, <String>['open']);
    expect(find.text('Open'), findsNothing, reason: 'choosing closes the menu');
  });

  testWidgets('a long-press opens it on touch', (WidgetTester tester) async {
    final List<String> chosen = await pump(tester);
    await tester.longPress(find.text('Report.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(chosen, <String>['rename']);
  });

  testWidgets('the menu key and Shift+F10 open it from the keyboard', (WidgetTester tester) async {
    await pump(tester, platform: TargetPlatform.linux);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('a disabled item does nothing; a shortcut is shown for the platform', (WidgetTester tester) async {
    final List<String> chosen = await pump(tester, platform: TargetPlatform.macOS);
    await tester.tap(find.text('Report.pdf'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('⌘R'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(chosen, isEmpty);
  });

  testWidgets('a nested item is reached through its submenu', (WidgetTester tester) async {
    final List<String> chosen = await pump(tester, platform: TargetPlatform.windows);
    await tester.tap(find.text('Report.pdf'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();
    expect(chosen, <String>['share.link']);
  });

  testWidgets('a screen reader gets each enabled item as an action', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    final List<String> chosen = await pump(tester);
    final SemanticsNode node = tester.getSemantics(find.text('Report.pdf'));
    final List<String> labels = <String>[
      for (final int id in node.getSemanticsData().customSemanticsActionIds ?? const <int>[])
        CustomSemanticsAction.getAction(id)!.label!,
    ];
    expect(labels, <String>['Open', 'Rename', 'Copy link']);
    final int copy = node.getSemanticsData().customSemanticsActionIds!
        .firstWhere((int id) => CustomSemanticsAction.getAction(id)!.label == 'Copy link');
    node.owner!
        .performAction(node.id, SemanticsAction.customAction, copy);
    await tester.pump();
    expect(chosen, <String>['share.link']);
    handle.dispose();
  });
}
