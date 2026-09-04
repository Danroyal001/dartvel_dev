// The Studio page-document pipeline, end to end: editor operations build the
// tree drag-and-drop would, the renderer instantiates real widgets, actions
// navigate through a real router, the store persists through real SQLite, and
// the exporter emits ordinary @DVPage source.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument pricingPage() {
  final document = DVPageDocument(route: '/pricing', title: 'Pricing');
  final editor = DVPageDocumentEditor(document);
  final heading = DVPageNode.text('Plans').withProperty('fontSize', 24);
  editor.insert(heading, parent: document.root.id);
  final row = DVPageNode.box(layout: 'row');
  editor.insert(row, parent: document.root.id);
  editor.insert(DVPageNode.text('Free'), parent: row.id);
  editor.insert(
    DVPageNode.text('Pro').withAction(
      <String, Object?>{'type': 'navigate', 'to': '/checkout'},
    ),
    parent: row.id,
  );
  return document;
}

void main() {
  tearDown(DVNavigation.detach);

  test('a document round-trips through JSON without loss', () {
    final document = pricingPage();

    final restored = DVPageDocument.fromJson(document.toJson());

    expect(restored.toJson(), document.toJson());
    expect(restored.title, 'Pricing');
  });

  test('editor operations behave like the gestures they back', () {
    final document = pricingPage();
    final editor = DVPageDocumentEditor(document);
    final row = document.root.children[1];

    // Move: drag the heading into the row.
    final heading = document.root.children.first;
    editor.move(heading.id, parent: row.id, index: 0);
    expect(document.root.children, hasLength(1));
    expect(row.children.first.id, heading.id);

    // Update: the inspector changes a property in place.
    editor.update(heading.id, (node) => node.withProperty('fontSize', 32));
    expect(editor.find(heading.id)!.properties['fontSize'], 32);

    // Remove: delete a child.
    editor.remove(heading.id);
    expect(editor.find(heading.id), isNull);

    // A container cannot be dropped into its own subtree.
    expect(
      () => editor.move(document.root.children.first.id,
          parent: row.children.first.id),
      throwsArgumentError,
    );
  });

  testWidgets('the renderer instantiates real widgets, not a facsimile',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: DVPageDocumentRenderer(pricingPage())),
    );

    // The actual primitives, findable by type — no CustomPaint standing in.
    expect(find.text('Plans'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
    expect(find.text('Pro'), findsOneWidget);
    expect(find.byType(DVText), findsNWidgets(3));
  });

  testWidgets('a bound navigate action drives the real router',
      (WidgetTester tester) async {
    final router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) =>
              DVPageDocumentRenderer(pricingPage()),
        ),
        GoRoute(
          path: '/checkout',
          builder: (BuildContext context, GoRouterState state) =>
              const Text('checkout page'),
        ),
      ],
    );
    addTearDown(router.dispose);
    DVNavigation.attach(router);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    await tester.tap(find.text('Pro'));
    await tester.pumpAndSettle();

    expect(find.text('checkout page'), findsOneWidget);
  });

  test('saving publishes: store round-trips through real SQLite', () async {
    final database = SqliteDVDatabaseAdapter.memory();
    addTearDown(database.close);
    DV.Database.configure(database);
    const store = DVPageStore();

    await store.save(pricingPage());
    expect(await store.routes(), <String>['/pricing']);

    final loaded = await store.load('/pricing');
    expect(loaded, isNotNull);
    expect(loaded!.title, 'Pricing');
    expect(loaded.root.children[1].children, hasLength(2));

    // Re-saving the same route replaces it — an edit, not a duplicate.
    loaded.title = 'Pricing v2';
    await store.save(loaded);
    expect(await store.routes(), <String>['/pricing']);
    expect((await store.load('/pricing'))!.title, 'Pricing v2');

    await store.delete('/pricing');
    expect(await store.load('/pricing'), isNull);
  });

  test('code export emits ordinary @DVPage source', () {
    final source = pricingPage().toDartSource();

    // The same shape a hand-written page uses: private, expression-bodied.
    expect(source, contains("@DVPage(title: 'Pricing')"));
    expect(source, contains('Widget _pricingPage(BuildContext context) =>'));
    expect(source, contains("const DVText('Plans').modifier(const DVModifier().fontSize(24.0))"));
    expect(source, contains('DVBox.row('));
    expect(
      source,
      contains(
        "const DVText('Pro').modifier(const DVModifier()"
        ".onPressed(DV.Navigation.to(const DVRouteTarget('/checkout'))))",
      ),
    );
    // Nothing of the builder survives into the export.
    expect(source, isNot(contains('DVPageNode')));
    expect(source, isNot(contains('DVPageDocument')));
  });

  test('a document read back from its own JSON shares nothing with it', () {
    // The obvious way to copy a document in memory, and it was not a copy:
    // toJson handed over the same property map and fromJson cast it, which
    // is a view. Rewriting an image's source on the copy -- what exporting a
    // project does -- changed the document the running application was still
    // serving.
    final DVPageDocument original = DVPageDocument(route: '/copied');
    final DVPageDocumentEditor editor = DVPageDocumentEditor(original);
    final DVPageNode node = DVPageNode.image('figma/abc.png')
        .withProperty('source', 'stored');
    editor.insert(node, parent: original.root.id);

    final DVPageDocument copy = DVPageDocument.fromJson(original.toJson());
    copy.root.children.single.properties['source'] = 'asset';

    expect(original.root.children.single.properties['source'], 'stored');
  });

  test('and its breakpoint overrides are its own too', () {
    final DVPageDocument original = DVPageDocument(route: '/copied');
    final DVPageDocumentEditor editor = DVPageDocumentEditor(original);
    editor.insert(
      DVPageNode.text('hello')
          .withBreakpointProperty(DVBreakpoint.tablet, 'fontSize', 24),
      parent: original.root.id,
    );

    final DVPageDocument copy = DVPageDocument.fromJson(original.toJson());
    copy.root.children.single.breakpoints['tablet']!['fontSize'] = 48;

    expect(
        original.root.children.single.breakpoints['tablet']!['fontSize'], 24);
  });
}
