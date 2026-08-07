// The Studio admin surface, driven the way a person drives it.
//
// The palette, canvas and inspector are each tested on their own; what this
// covers is the part that makes them usable from a running app — choosing a
// page, creating one, publishing it, and reverting a route to its compiled
// page.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument documentFor(String route, String text) {
  final document = DVPageDocument(route: route, title: route);
  DVPageDocumentEditor(document)
      .insert(DVPageNode.text(text), parent: document.root.id);
  return document;
}

Widget host() => const MaterialApp(home: Material(child: DVStudioScreen()));

void main() {
  late SqliteDVDatabaseAdapter database;

  setUp(() {
    database = SqliteDVDatabaseAdapter.memory();
    DV.Database.configure(database);
    DVPageStore.resetCache();
  });

  tearDown(() {
    database.close();
    DVPageStore.resetCache();
  });

  testWidgets('stored pages are listed', (WidgetTester tester) async {
    await const DVPageStore().save(documentFor('/pricing', 'Plans'));
    await const DVPageStore().save(documentFor('/about', 'About us'));

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('/pricing'), findsOneWidget);
    expect(find.text('/about'), findsOneWidget);
    expect(find.text('Select or create a page to edit.'), findsOneWidget);
  });

  testWidgets('an empty store says so rather than looking broken',
      (WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('No stored pages yet.'), findsOneWidget);
  });

  testWidgets('opening a page shows the builder over its real widgets',
      (WidgetTester tester) async {
    await const DVPageStore().save(documentFor('/pricing', 'Plans'));

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('dv-studio-route-/pricing')));
    await tester.pumpAndSettle();

    // The canvas renders the document's actual DVText, not a preview of it.
    expect(find.text('Plans'), findsOneWidget);
    // And the palette and inspector came with it.
    expect(find.text('Column'), findsOneWidget);
    expect(find.text('Nothing selected'), findsOneWidget);
  });

  testWidgets('creating a page opens a blank document for a new route',
      (WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(EditableText).first, '/new');
    await tester.tap(find.byKey(const ValueKey<String>('dv-studio-create')));
    await tester.pumpAndSettle();

    expect(find.text('/new'), findsWidgets);
    // Not yet published: creating is not saving.
    expect(await const DVPageStore().routes(), isEmpty);
  });

  testWidgets('creating a route that already exists opens it instead of '
      'blanking it', (WidgetTester tester) async {
    await const DVPageStore().save(documentFor('/pricing', 'Plans'));

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, '/pricing');
    await tester.tap(find.byKey(const ValueKey<String>('dv-studio-create')));
    await tester.pumpAndSettle();

    // Starting blank here would overwrite the page on the first publish.
    expect(find.text('Plans'), findsOneWidget);
  });

  testWidgets('publishing writes the document to the store',
      (WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, '/new');
    await tester.tap(find.byKey(const ValueKey<String>('dv-studio-create')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('dv-studio-publish')));
    await tester.pumpAndSettle();

    expect(await const DVPageStore().routes(), <String>['/new']);
    // The list reflects it without a reload, because saving publishes.
    expect(find.byKey(const ValueKey<String>('dv-studio-route-/new')),
        findsOneWidget);
  });

  testWidgets('reverting deletes the document so the compiled page returns',
      (WidgetTester tester) async {
    await const DVPageStore().save(documentFor('/pricing', 'Plans'));

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey<String>('dv-studio-route-/pricing')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('dv-studio-revert')));
    await tester.pumpAndSettle();

    expect(await const DVPageStore().routes(), isEmpty);
    expect(find.text('Select or create a page to edit.'), findsOneWidget);
  });

  testWidgets('view code shows the page as exportable Dart source',
      (WidgetTester tester) async {
    await const DVPageStore().save(documentFor('/pricing', 'Plans'));

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey<String>('dv-studio-route-/pricing')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey<String>('dv-studio-view-code')));
    await tester.pumpAndSettle();

    // The exported source, not a summary of it: the annotation, the
    // route-derived page function, and the page's own widgets.
    expect(find.textContaining('@DVPage'), findsOneWidget);
    expect(find.textContaining('Widget _pricingPage(BuildContext context)'),
        findsOneWidget);
    expect(find.textContaining("const DVText('Plans')"), findsOneWidget);
    // The design surface is gone while the code is shown, so the two views
    // cannot disagree about what is being edited.
    expect(find.text('Nothing selected'), findsNothing);
  });

  testWidgets('undo is offered only once there is something to undo',
      (WidgetTester tester) async {
    await const DVPageStore().save(documentFor('/pricing', 'Plans'));

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey<String>('dv-studio-route-/pricing')));
    await tester.pumpAndSettle();

    GestureDetector undo() => tester.widget<GestureDetector>(
        find.byKey(const ValueKey<String>('dv-studio-undo')));
    expect(undo().onTap, isNull);

    // Select the text node and change it through the inspector.
    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, '/x');
    await tester.pumpAndSettle();

    expect(undo().onTap, isNotNull);
  });

  group('workflows', () {
    Future<void> openWorkflows(WidgetTester tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.tap(
          find.byKey(const ValueKey<String>('dv-studio-section-workflows')));
      await tester.pumpAndSettle();
    }

    testWidgets('stored workflows are listed', (WidgetTester tester) async {
      await const DVWorkflowStore().save(DVWorkflowDocument(name: 'sendMail'));

      await openWorkflows(tester);

      expect(find.text('sendMail'), findsOneWidget);
      expect(
          find.text('Select or create a workflow to edit.'), findsOneWidget);
    });

    testWidgets('an empty store says so rather than looking broken',
        (WidgetTester tester) async {
      await openWorkflows(tester);

      expect(find.text('No stored workflows yet.'), findsOneWidget);
    });

    testWidgets('creating a workflow opens the step builder',
        (WidgetTester tester) async {
      await openWorkflows(tester);

      await tester.enterText(find.byType(EditableText).first, 'charge');
      await tester.tap(find
          .byKey(const ValueKey<String>('dv-studio-workflow-create')));
      await tester.pumpAndSettle();

      // The step palette, not a page palette: switching sections switches
      // what is being built.
      expect(find.text('Condition'), findsOneWidget);
      expect(find.text('No step selected'), findsOneWidget);
      expect(find.text('Column'), findsNothing);
      // Not yet published: creating is not saving.
      expect(await const DVWorkflowStore().names(), isEmpty);
    });

    testWidgets('publishing writes the workflow to the store',
        (WidgetTester tester) async {
      await openWorkflows(tester);
      await tester.enterText(find.byType(EditableText).first, 'charge');
      await tester.tap(find
          .byKey(const ValueKey<String>('dv-studio-workflow-create')));
      await tester.pumpAndSettle();

      await tester.tap(find
          .byKey(const ValueKey<String>('dv-studio-workflow-publish')));
      await tester.pumpAndSettle();

      expect(await const DVWorkflowStore().names(), <String>['charge']);
      expect(find.byKey(const ValueKey<String>('dv-studio-workflow-charge')),
          findsOneWidget);
    });

    testWidgets('creating a name that already exists opens it instead of '
        'blanking it', (WidgetTester tester) async {
      final stored = DVWorkflowDocument(name: 'charge');
      DVWorkflowDocumentEditor(stored)
          .insert(DVWorkflowStep.call('capturePayment'),
              parent: DVWorkflowDocumentEditor.rootParent);
      await const DVWorkflowStore().save(stored);

      await openWorkflows(tester);
      await tester.enterText(find.byType(EditableText).first, 'charge');
      await tester.tap(find
          .byKey(const ValueKey<String>('dv-studio-workflow-create')));
      await tester.pumpAndSettle();

      // Starting blank here would drop the steps on the first publish.
      expect(find.text('call capturePayment'), findsOneWidget);
    });

    testWidgets('deleting removes the workflow', (WidgetTester tester) async {
      await const DVWorkflowStore().save(DVWorkflowDocument(name: 'charge'));

      await openWorkflows(tester);
      await tester
          .tap(find.byKey(const ValueKey<String>('dv-studio-workflow-charge')));
      await tester.pumpAndSettle();
      await tester.tap(
          find.byKey(const ValueKey<String>('dv-studio-workflow-delete')));
      await tester.pumpAndSettle();

      expect(await const DVWorkflowStore().names(), isEmpty);
      expect(
          find.text('Select or create a workflow to edit.'), findsOneWidget);
    });

    testWidgets('view code shows the workflow as a backend function',
        (WidgetTester tester) async {
      await const DVWorkflowStore().save(DVWorkflowDocument(name: 'charge'));

      await openWorkflows(tester);
      await tester
          .tap(find.byKey(const ValueKey<String>('dv-studio-workflow-charge')));
      await tester.pumpAndSettle();
      await tester.tap(
          find.byKey(const ValueKey<String>('dv-studio-workflow-view-code')));
      await tester.pumpAndSettle();

      expect(find.textContaining('@DVBackendFunction'), findsOneWidget);
      expect(find.textContaining('charge'), findsWidgets);
    });

    testWidgets('switching back to pages leaves the workflow edit behind',
        (WidgetTester tester) async {
      await const DVPageStore().save(documentFor('/pricing', 'Plans'));
      await openWorkflows(tester);
      await tester.enterText(find.byType(EditableText).first, 'charge');
      await tester.tap(find
          .byKey(const ValueKey<String>('dv-studio-workflow-create')));
      await tester.pumpAndSettle();

      await tester.tap(
          find.byKey(const ValueKey<String>('dv-studio-section-pages')));
      await tester.pumpAndSettle();

      // An unpublished workflow must not linger under the page builder.
      expect(find.text('No step selected'), findsNothing);
      expect(find.text('/pricing'), findsOneWidget);
    });
  });
}
