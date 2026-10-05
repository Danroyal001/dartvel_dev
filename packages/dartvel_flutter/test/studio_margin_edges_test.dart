import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument pageWith(Map<String, Object?> properties) {
  final document = DVPageDocument(route: '/spacing');
  final editor = DVPageDocumentEditor(document);
  var box = DVPageNode.box();
  properties.forEach((name, value) => box = box.withProperty(name, value));
  editor.insert(box, parent: document.root.id);
  editor.insert(DVPageNode.text('inside'), parent: box.id);
  return document;
}

void main() {
  testWidgets('per-side margin survives serialization and affects layout', (
    tester,
  ) async {
    final document = DVPageDocument.fromJson(
      pageWith({'margin': 16, 'marginLeft': 24, 'marginBottom': 0}).toJson(),
    );
    await tester.pumpWidget(
      MaterialApp(home: DVPageDocumentRenderer(document)),
    );
    final insets = tester
        .widgetList<Padding>(
          find.ancestor(
            of: find.text('inside'),
            matching: find.byType(Padding),
          ),
        )
        .map((p) => p.padding);
    expect(
      insets,
      contains(const EdgeInsets.only(left: 24, top: 16, right: 16, bottom: 0)),
    );
  });

  test('export preserves four different edges without replacing them', () {
    final source = pageWith({
      'marginLeft': 24,
      'marginTop': 8,
      'marginRight': 12,
      'marginBottom': 0,
    }).toDartSource();
    expect(
      source,
      contains('.marginOnly(left: 24.0, top: 8.0, right: 12.0, bottom: 0.0)'),
    );
    expect('.marginOnly('.allMatches(source).length, 1);
    expect(source, isNot(contains('.margin(')));
  });

  test('uniform margin remains compatible with existing documents', () {
    expect(pageWith({'margin': 16}).toDartSource(), contains('.margin(16.0)'));
  });

  test('all four edges are reachable in the size and spacing inspector', () {
    final groups = dvStudioInspectorGroupsFor(DVPageNode.box());
    final spacing = groups.firstWhere((g) => g.$1 == 'Size & spacing').$2;
    expect(
      spacing,
      containsAll(['marginTop', 'marginRight', 'marginBottom', 'marginLeft']),
    );
  });
}
