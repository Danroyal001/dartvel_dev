// What a version changes, as a person reviewing it reads it.
//
// The workflow's own diff compares top-level fields, and for a page document
// that is `title` and `root`: every edit anywhere on the page is "root
// changed", which tells a reviewer nothing. This is the node-level diff the
// History panel shows. The quiet failures: a node that moved reported as a
// removal and an addition (so a reviewer thinks content was deleted), every
// descendant of a removed container listed one by one (so one deletion reads
// as fifty), and a change inside a breakpoint override not reported at all.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument page() {
  return DVPageDocument(
    route: '/p',
    title: 'Pricing',
    root: DVPageNode(
      id: 'root',
      type: 'box',
      children: <DVPageNode>[
        DVPageNode(
          id: 'hero',
          type: 'box',
          layout: 'row',
          children: <DVPageNode>[
            DVPageNode(
              id: 'heading',
              type: 'text',
              properties: <String, Object?>{'text': 'Plans', 'fontSize': 24},
            ),
            DVPageNode(
              id: 'lede',
              type: 'text',
              properties: <String, Object?>{'text': 'Pick one'},
            ),
          ],
        ),
        DVPageNode(
          id: 'footer',
          type: 'box',
          children: <DVPageNode>[
            DVPageNode(
              id: 'legal',
              type: 'text',
              properties: <String, Object?>{'text': '© Acme'},
            ),
          ],
        ),
      ],
    ),
  );
}

DVPageDocument copy(DVPageDocument document) =>
    DVPageDocument.fromJson(document.toJson());

void main() {
  test('an identical document has no changes', () {
    final DVPageDocumentDiff diff = DVPageDocumentDiff.between(page(), page());
    expect(diff.isEmpty, isTrue);
    expect(diff.nodes, isEmpty);
    expect(diff.title, isNull);
  });

  test('a changed property names the node, the property and both values', () {
    final DVPageDocument after = copy(page());
    DVPageDocumentEditor(after).update(
      'heading',
      (DVPageNode node) =>
          node.withProperty('fontSize', 32).withProperty('text', 'Our plans'),
    );

    final DVPageDocumentDiff diff = DVPageDocumentDiff.between(page(), after);

    final DVPageNodeChange change = diff.nodes.single;
    expect(change.kind, DVPageChangeKind.changed);
    expect(change.nodeId, 'heading');
    expect(change.label, 'Text');
    expect(change.summary, 'Our plans');
    expect(
      <String, (String, String)>{
        for (final DVPagePropertyChange p in change.properties)
          p.name: (p.fromText, p.toText),
      },
      <String, (String, String)>{
        'fontSize': ('24', '32'),
        'text': ('"Plans"', '"Our plans"'),
      },
    );
  });

  test('an added container is one change, counting what it holds', () {
    final DVPageDocument after = copy(page());
    final DVPageNode card = DVPageNode(id: 'card', type: 'box');
    DVPageDocumentEditor(after)
      ..insert(card, parent: 'root')
      ..insert(
        DVPageNode(
          id: 'c1',
          type: 'text',
          properties: <String, Object?>{'text': 'Pro'},
        ),
        parent: 'card',
      )
      ..insert(
        DVPageNode(
          id: 'c2',
          type: 'text',
          properties: <String, Object?>{'text': r'$29'},
        ),
        parent: 'card',
      );

    final DVPageDocumentDiff diff = DVPageDocumentDiff.between(page(), after);

    final DVPageNodeChange added = diff.nodes.single;
    expect(added.kind, DVPageChangeKind.added);
    expect(added.nodeId, 'card');
    expect(added.descendants, 2);
    expect(diff.added, 1);
  });

  test('a removed container is one change, not one per descendant', () {
    final DVPageDocument after = copy(page());
    DVPageDocumentEditor(after).remove('hero');

    final DVPageDocumentDiff diff = DVPageDocumentDiff.between(page(), after);

    final DVPageNodeChange removed = diff.nodes.single;
    expect(removed.kind, DVPageChangeKind.removed);
    expect(removed.nodeId, 'hero');
    expect(removed.label, 'Row');
    expect(removed.descendants, 2);
    expect(diff.removed, 1);
  });

  test('a node moved to another container is a move, not a removal and an '
      'addition', () {
    final DVPageDocument after = copy(page());
    DVPageDocumentEditor(after).move('legal', parent: 'hero');

    final DVPageDocumentDiff diff = DVPageDocumentDiff.between(page(), after);

    final DVPageNodeChange moved = diff.nodes.single;
    expect(moved.kind, DVPageChangeKind.moved);
    expect(moved.nodeId, 'legal');
    expect(moved.fromParent, 'Column');
    expect(moved.toParent, 'Row');
    expect(diff.removed, 0);
    expect(diff.added, 0);
  });

  test('a node inserted before its siblings does not mark them moved', () {
    final DVPageDocument after = copy(page());
    DVPageDocumentEditor(after).insert(
      DVPageNode(
        id: 'banner',
        type: 'text',
        properties: <String, Object?>{'text': 'Sale'},
      ),
      parent: 'root',
      index: 0,
    );

    final DVPageDocumentDiff diff = DVPageDocumentDiff.between(page(), after);

    expect(
      diff.nodes.map((DVPageNodeChange c) => (c.kind, c.nodeId)).toList(),
      <(DVPageChangeKind, String)>[(DVPageChangeKind.added, 'banner')],
    );
  });

  test('a changed title, layout, action and breakpoint override are all '
      'reported', () {
    final DVPageDocument after = copy(page())..title = 'Plans & pricing';
    final DVPageDocumentEditor editor = DVPageDocumentEditor(after);
    editor.update(
      'hero',
      (DVPageNode node) => DVPageNode(
        id: node.id,
        type: node.type,
        layout: 'list',
        properties: node.properties,
        children: node.children,
      ),
    );
    editor.update(
      'lede',
      (DVPageNode node) => node
          .withAction(<String, Object?>{'type': 'navigate', 'to': '/signup'})
          .withBreakpointProperty(DVBreakpoint.tablet, 'fontSize', 18),
    );

    final DVPageDocumentDiff diff = DVPageDocumentDiff.between(page(), after);

    expect(diff.title!.fromText, '"Pricing"');
    expect(diff.title!.toText, '"Plans & pricing"');
    final Map<String, List<String>> byNode = <String, List<String>>{
      for (final DVPageNodeChange c in diff.nodes)
        c.nodeId: <String>[
          for (final DVPagePropertyChange p in c.properties) p.name,
        ],
    };
    expect(byNode, <String, List<String>>{
      'hero': <String>['layout'],
      'lede': <String>['action', 'fontSize (tablet)'],
    });
    final DVPagePropertyChange action = diff.nodes.last.properties.first;
    expect(action.fromText, '—');
    expect(action.toText, 'type: navigate, to: /signup');
  });

  test('against nothing, every top-level node is an addition', () {
    final DVPageDocumentDiff diff = DVPageDocumentDiff.between(null, page());
    expect(diff.nodes.map((DVPageNodeChange c) => c.nodeId).toList(), <String>[
      'hero',
      'footer',
    ]);
    expect(
      diff.title,
      isNull,
      reason: 'a new page has a title, it did not change one',
    );
  });
}
