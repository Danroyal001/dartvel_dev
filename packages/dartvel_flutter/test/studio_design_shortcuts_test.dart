// The shortcuts somebody who has used Figma, Bubble or Power Apps already
// has in their fingers, doing the same thing on Studio's canvas.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/studio/studio_command_palette.dart'
    show dvStudioShortcuts;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument _page() => DVPageDocument(
      route: '/menu',
      root: DVPageNode(id: 'page', type: 'box', children: <DVPageNode>[
        DVPageNode(id: 'a', type: 'text', properties: <String, Object?>{'text': 'Espresso'}),
        DVPageNode(id: 'b', type: 'text', properties: <String, Object?>{'text': 'Latte'}),
        DVPageNode(id: 'c', type: 'text', properties: <String, Object?>{'text': 'Mocha'}),
      ]),
    );

List<String> _texts(DVPageNode node) => <String>[
      if (node.properties['text'] case final String text) text,
      for (final DVPageNode child in node.children) ..._texts(child),
    ];

Future<DVStudioEditorController> _canvas(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final DVStudioEditorController controller = DVStudioEditorController(_page());
  addTearDown(controller.dispose);
  await tester.pumpWidget(MaterialApp(
    home: Material(child: DVStudioCanvas(controller: controller)),
  ));
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _press(WidgetTester tester, List<LogicalKeyboardKey> keys) async {
  for (final LogicalKeyboardKey key in keys.take(keys.length - 1)) {
    await tester.sendKeyDownEvent(key);
  }
  await tester.sendKeyEvent(keys.last);
  for (final LogicalKeyboardKey key in keys.take(keys.length - 1).toList().reversed) {
    await tester.sendKeyUpEvent(key);
  }
  await tester.pumpAndSettle();
}

const LogicalKeyboardKey _ctrl = LogicalKeyboardKey.controlLeft;
const LogicalKeyboardKey _shift = LogicalKeyboardKey.shiftLeft;

void main() {
  testWidgets('Ctrl+C then Ctrl+V pastes a copy after the selection; Ctrl+X '
      'cuts', (WidgetTester tester) async {
    final DVStudioEditorController controller = await _canvas(tester);
    await tester.tap(find.text('Espresso'));
    await tester.pumpAndSettle();
    await _press(tester, <LogicalKeyboardKey>[_ctrl, LogicalKeyboardKey.keyC]);
    await tester.tap(find.text('Mocha'));
    await tester.pumpAndSettle();
    await _press(tester, <LogicalKeyboardKey>[_ctrl, LogicalKeyboardKey.keyV]);
    expect(_texts(controller.document.root),
        <String>['Espresso', 'Latte', 'Mocha', 'Espresso']);
    expect(controller.selectedNode!.id, isNot('a'), reason: 'a copy, with its own id');

    await tester.tap(find.text('Latte'));
    await tester.pumpAndSettle();
    await _press(tester, <LogicalKeyboardKey>[_ctrl, LogicalKeyboardKey.keyX]);
    expect(_texts(controller.document.root), <String>['Espresso', 'Mocha', 'Espresso']);
  });

  testWidgets('Ctrl+G puts the selection in a group, Ctrl+Shift+G takes it '
      'out again', (WidgetTester tester) async {
    final DVStudioEditorController controller = await _canvas(tester);
    await tester.tap(find.text('Latte'));
    await tester.pumpAndSettle();
    await _press(tester, <LogicalKeyboardKey>[_ctrl, LogicalKeyboardKey.keyG]);
    final DVPageNode group = controller.document.root.children[1];
    expect(group.type, 'box');
    expect(_texts(group), <String>['Latte']);
    expect(controller.selectedId, group.id);

    await _press(tester, <LogicalKeyboardKey>[_ctrl, _shift, LogicalKeyboardKey.keyG]);
    expect(controller.document.root.children.map((DVPageNode n) => n.id),
        <String>['a', 'b', 'c']);
  });

  testWidgets('Ctrl+] and Ctrl+[ move the selection later and earlier',
      (WidgetTester tester) async {
    final DVStudioEditorController controller = await _canvas(tester);
    await tester.tap(find.text('Espresso'));
    await tester.pumpAndSettle();
    await _press(tester, <LogicalKeyboardKey>[_ctrl, LogicalKeyboardKey.bracketRight]);
    expect(_texts(controller.document.root), <String>['Latte', 'Espresso', 'Mocha']);
    await _press(tester, <LogicalKeyboardKey>[_ctrl, LogicalKeyboardKey.bracketLeft]);
    expect(_texts(controller.document.root), <String>['Espresso', 'Latte', 'Mocha']);
  });

  testWidgets('Tab and Shift+Tab walk to the next and previous element, '
      'Shift+Enter selects what the selection is in, Enter what is in it',
      (WidgetTester tester) async {
    final DVStudioEditorController controller = await _canvas(tester);
    await tester.tap(find.text('Espresso'));
    await tester.pumpAndSettle();
    await _press(tester, <LogicalKeyboardKey>[LogicalKeyboardKey.tab]);
    expect(controller.selectedId, 'b');
    await _press(tester, <LogicalKeyboardKey>[_shift, LogicalKeyboardKey.tab]);
    expect(controller.selectedId, 'a');
    await _press(tester, <LogicalKeyboardKey>[_shift, LogicalKeyboardKey.enter]);
    expect(controller.selectedId, 'page');
    await _press(tester, <LogicalKeyboardKey>[LogicalKeyboardKey.enter]);
    expect(controller.selectedId, 'a');
  });

  testWidgets('Ctrl+Y redoes, as it does in Power Apps and Bubble',
      (WidgetTester tester) async {
    final DVStudioEditorController controller = await _canvas(tester);
    await tester.tap(find.text('Latte'));
    await tester.pumpAndSettle();
    await _press(tester, <LogicalKeyboardKey>[LogicalKeyboardKey.delete]);
    await _press(tester, <LogicalKeyboardKey>[_ctrl, LogicalKeyboardKey.keyZ]);
    expect(_texts(controller.document.root), contains('Latte'));
    await _press(tester, <LogicalKeyboardKey>[_ctrl, LogicalKeyboardKey.keyY]);
    expect(_texts(controller.document.root), isNot(contains('Latte')));
  });

  testWidgets('in the page editor, Shift+0 is 100%, Shift+1 fits the page, and '
      'Ctrl+S deploys it', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final SqliteDVDatabaseAdapter database = SqliteDVDatabaseAdapter.memory();
    DV.Database.configure(database);
    DVPageStore.resetCache();
    addTearDown(() {
      database.close();
      DVPageStore.resetCache();
    });
    await const DVPageStore().save(_page());
    await tester.pumpWidget(const MaterialApp(home: Material(child: DVStudioScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('dv-studio-route-/menu')));
    await tester.pumpAndSettle();
    final double fitted = tester.getRect(find.byKey(const ValueKey<String>('dv-studio-artboard'))).width;
    expect(fitted, lessThan(1280), reason: 'the canvas is narrower than the page');

    await _press(tester, <LogicalKeyboardKey>[_shift, LogicalKeyboardKey.digit0]);
    expect(tester.getRect(find.byKey(const ValueKey<String>('dv-studio-artboard'))).width, 1280);
    await _press(tester, <LogicalKeyboardKey>[_shift, LogicalKeyboardKey.digit1]);
    expect(tester.getRect(find.byKey(const ValueKey<String>('dv-studio-artboard'))).width, fitted);

    await tester.tap(find.text('Latte'));
    await tester.pumpAndSettle();
    await _press(tester, <LogicalKeyboardKey>[LogicalKeyboardKey.delete]);
    await _press(tester, <LogicalKeyboardKey>[_ctrl, LogicalKeyboardKey.keyS]);
    expect(_texts((await const DVPageStore().load('/menu'))!.root),
        <String>['Espresso', 'Mocha']);
  });

  test('every shortcut on the sheet names what it does', () {
    final Map<String, String> sheet = <String, String>{
      for (final (String keys, String what) in dvStudioShortcuts) keys: what,
    };
    for (final String keys in <String>[
      'Ctrl+C', 'Ctrl+V', 'Ctrl+X', 'Ctrl+G', 'Ctrl+Shift+G', 'Ctrl+]',
      'Ctrl+[', 'Tab', 'Shift+Enter', 'Enter', 'Ctrl+Y', 'Shift+0', 'Shift+1',
      'Ctrl+S',
    ]) {
      expect(sheet[keys], isNotNull, reason: '$keys is not on the sheet');
    }
  });
}
