// The editor's edits as data: every mutation the controller performs is also
// published as a serialisable edit, and an edit can be applied to another
// controller. This is the seam multi-user editing attaches through -- a
// collaborator's controller applies what this one published -- and it is
// free, because the seam is not the feature.
//
// What the tests hold to: an edit round-trips JSON; applying the published
// edits to a second controller on the same starting document yields the same
// document; applying does not itself publish, or two collaborators would
// echo each other forever; and an applied edit does not enter local undo.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument seed() => DVPageDocument(
      route: '/p',
      root: DVPageNode(
        id: 'root',
        type: 'box',
        children: <DVPageNode>[
          DVPageNode(id: 'a', type: 'text', properties: <String, Object?>{'text': 'A'}),
          DVPageNode(id: 'b', type: 'box', layout: 'row'),
        ],
      ),
    );

void main() {
  test('each mutation is published as an edit that survives JSON', () {
    final DVStudioEditorController c = DVStudioEditorController(seed());
    final List<DVStudioEdit> seen = <DVStudioEdit>[];
    c.edits.listen(seen.add);

    c.insert(DVPageNode(id: 'c', type: 'text'), parent: 'b');
    c.setProperty('a', 'text', 'Changed');
    c.move('a', parent: 'b', index: 0);
    c.remove('c');

    return Future<void>.delayed(Duration.zero).then((_) {
      expect(seen.map((DVStudioEdit e) => e.kind), <String>['insert', 'update', 'move', 'remove']);
      for (final DVStudioEdit e in seen) {
        expect(DVStudioEdit.fromJson(e.toJson()).toJson(), e.toJson());
      }
    });
  });

  test('applying the published edits reproduces the document elsewhere', () async {
    final DVStudioEditorController here = DVStudioEditorController(seed());
    final DVStudioEditorController there = DVStudioEditorController(seed());
    here.edits.listen((DVStudioEdit e) => there.apply(DVStudioEdit.fromJson(e.toJson())));

    here.insert(DVPageNode(id: 'c', type: 'text', properties: <String, Object?>{'text': 'C'}), parent: 'b');
    here.setProperty('a', 'text', 'Changed');
    here.move('a', parent: 'b', index: 0);
    here.remove('c');
    here.undo();
    await Future<void>.delayed(Duration.zero);

    expect(there.document.toJson(), here.document.toJson());
    expect(DVPageDocumentEditor(there.document).find('c'), isNotNull,
        reason: 'undo is an edit too: the whole document, replaced');
  });

  test('applying does not publish, and does not enter local undo', () async {
    final DVStudioEditorController c = DVStudioEditorController(seed());
    final List<DVStudioEdit> seen = <DVStudioEdit>[];
    c.edits.listen(seen.add);

    c.apply(DVStudioEdit.update('a', DVPageNode(id: 'a', type: 'text', properties: <String, Object?>{'text': 'Remote'})));
    await Future<void>.delayed(Duration.zero);

    expect(seen, isEmpty);
    expect(c.canUndo, isFalse);
    expect(DVPageDocumentEditor(c.document).find('a')!.properties['text'], 'Remote');
  });

  test('an edit that cannot apply is refused without touching the document', () {
    final DVStudioEditorController c = DVStudioEditorController(seed());
    final Map<String, Object?> before = c.document.toJson();
    expect(() => c.apply(DVStudioEdit.remove('nope')), throwsArgumentError);
    expect(c.document.toJson(), before);
  });

  test('a read-only controller refuses local mutations but still applies edits', () {
    // A viewer's screen follows the editors; it does not get to type.
    final DVStudioEditorController c = DVStudioEditorController(seed(), readOnly: true);
    expect(() => c.setProperty('a', 'text', 'x'), throwsStateError);
    c.apply(DVStudioEdit.remove('a'));
    expect(DVPageDocumentEditor(c.document).find('a'), isNull);

    // Settable after the fact: the screen creates the controller, and who is
    // allowed to edit is decided by whatever attaches to it.
    final DVStudioEditorController later = DVStudioEditorController(seed());
    later.readOnly = true;
    expect(() => later.remove('a'), throwsStateError);
    later.readOnly = false;
    later.remove('a');
    expect(DVPageDocumentEditor(later.document).find('a'), isNull);
  });

  testWidgets('DVStudioScreen hands the editor it opens to every hook', (WidgetTester tester) async {
    final SqliteDVDatabaseAdapter database = SqliteDVDatabaseAdapter.memory();
    DV.Database.configure(database);
    DVPageStore.resetCache();
    addTearDown(() {
      database.close();
      DVPageStore.resetCache();
    });
    await const DVPageStore().save(seed());

    final List<String> opened = <String>[];
    int detached = 0;
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: DVStudioScreen(
          editorHooks: <DVStudioEditorHook>[
            (DVStudioEditorController controller) {
              opened.add(controller.document.route);
              return () => detached++;
            },
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('dv-studio-route-/p')));
    await tester.pumpAndSettle();

    expect(opened, <String>['/p']);
    await tester.pumpWidget(const SizedBox());
    expect(detached, 1, reason: 'a hook is detached when its editor goes');
  });
}
