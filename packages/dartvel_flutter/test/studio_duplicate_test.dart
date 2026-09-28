// Duplicate an element, as every page builder does with Ctrl+D (Cmd+D):
// the copy is placed right after the original, in the same container, with
// fresh ids all the way down so the two never answer to one selection, and
// it is one undoable edit that collaborators receive.
import 'package:dartvel_flutter/src/studio/page_document.dart';
import 'package:dartvel_flutter/src/studio/studio_edit.dart';
import 'package:dartvel_flutter/src/studio/studio_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Set<String> ids(DVPageNode n) => <String>{n.id, for (final DVPageNode c in n.children) ...ids(c)};

void main() {
  test('a card is copied after itself, with new ids throughout', () {
    final DVPageNode card = DVPageNode(type: 'box', children: <DVPageNode>[
      DVPageNode.text('Title'),
      DVPageNode.text('Body'),
    ]);
    final DVPageNode footer = DVPageNode.text('Footer');
    final DVStudioEditorController c = DVStudioEditorController(DVPageDocument(
        route: '/', root: DVPageNode(type: 'box', children: <DVPageNode>[card, footer])));
    final List<DVStudioEdit> sent = <DVStudioEdit>[];
    c.edits.listen(sent.add);

    c.select(card.id);
    c.duplicate(card.id);

    final List<DVPageNode> top = c.document.root.children;
    expect(top.length, 3);
    expect(top[0].id, card.id);
    expect(top[2].id, footer.id);
    final DVPageNode copy = top[1];
    expect(copy.children.map((DVPageNode n) => n.properties['text']),
        <Object?>['Title', 'Body']);
    expect(ids(copy).intersection(ids(card)), isEmpty);
    expect(c.selectedId, copy.id);

    c.undo();
    expect(c.document.root.children.length, 2);
  });

  test('the page itself is not duplicated', () {
    final DVStudioEditorController c =
        DVStudioEditorController(DVPageDocument(route: '/'));
    expect(() => c.duplicate(c.document.root.id), throwsArgumentError);
    expect(c.canUndo, isFalse);
  });
  testWidgets('Ctrl+D on the canvas duplicates the selected element',
      (WidgetTester tester) async {
    final DVPageNode title = DVPageNode.text('Title');
    final DVStudioEditorController c = DVStudioEditorController(DVPageDocument(
        route: '/', root: DVPageNode(type: 'box', children: <DVPageNode>[title])));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DVStudioCanvas(controller: c, viewportWidth: 400)),
    ));
    await tester.tap(find.text('Title'));
    await tester.pump();
    expect(c.selectedId, title.id);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(c.document.root.children.length, 2);
    expect(find.text('Title'), findsNWidgets(2));
  });
}
