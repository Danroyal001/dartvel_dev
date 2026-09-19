// The Studio Workflows section, exercised through the real screen.
//
// These lived in dartvel_flutter/test/studio_screen_test.dart, where they
// passed against a Studio that had the workflow builder compiled in. The
// builder is Pro and now attaches through DVStudioSection, so the tests move
// with it — and the free suite gained one asserting the tab is absent, which
// is the other half of the same claim.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host() => MaterialApp(
      home: Material(
        child: DVStudioScreen(
          sections: <DVStudioSection>[dvWorkflowStudioSection()],
        ),
      ),
    );

DVPageDocument documentFor(String route, String text) {
  final document = DVPageDocument(route: route, title: route);
  DVPageDocumentEditor(document)
      .insert(DVPageNode.text(text), parent: document.root.id);
  return document;
}

void main() {
  // The store is a real database, so the suite needs an adapter. This lived in
  // the setUp of the free Studio's suite and did not travel with the tests.
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

  group('workflows', () {
    Future<void> openWorkflows(WidgetTester tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.tap(
          find.byKey(const ValueKey<String>('dv-studio-section-functions')));
      await tester.pumpAndSettle();
    }

    testWidgets('stored workflows are listed', (WidgetTester tester) async {
      await const DVWorkflowStore().save(DVWorkflowDocument(name: 'sendMail'));

      await openWorkflows(tester);

      expect(find.text('sendMail'), findsOneWidget);
      expect(
          find.text('Select or create a function to edit.'), findsOneWidget);
    });

    testWidgets('an empty store says so rather than looking broken',
        (WidgetTester tester) async {
      await openWorkflows(tester);

      expect(find.text('No backend functions yet.'), findsOneWidget);
    });

    testWidgets('creating a workflow opens the step builder',
        (WidgetTester tester) async {
      await openWorkflows(tester);

      await tester.enterText(find.byType(EditableText).first, 'charge');
      await tester.tap(find
          .byKey(const ValueKey<String>('dv-studio-function-create')));
      await tester.pumpAndSettle();

      // The step palette, not a page palette: switching sections switches
      // what is being built.
      expect(find.text('Condition'), findsOneWidget);
      // With nothing selected the inspector shows the function's inputs.
      expect(find.text('INPUTS'), findsOneWidget);
      expect(find.text('Column'), findsNothing);
      // Not yet published: creating is not saving.
      expect(await const DVWorkflowStore().names(), isEmpty);
    });

    testWidgets('a workflow with an untyped input is not deployed',
        (WidgetTester tester) async {
      // Saved before inputs had types: deployed, it would become a backend
      // function that takes anything.
      await const DVWorkflowStore().save(DVWorkflowDocument.fromJson(
          <String, Object?>{'name': 'legacy', 'parameters': <Object?>['email']}));
      await openWorkflows(tester);
      await tester
          .tap(find.byKey(const ValueKey<String>('dv-studio-function-legacy')));
      await tester.pumpAndSettle();

      await tester.tap(
          find.byKey(const ValueKey<String>('dv-studio-function-deploy')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Give email a type'), findsOneWidget);
    });

    testWidgets('publishing writes the workflow to the store',
        (WidgetTester tester) async {
      await openWorkflows(tester);
      await tester.enterText(find.byType(EditableText).first, 'charge');
      await tester.tap(find
          .byKey(const ValueKey<String>('dv-studio-function-create')));
      await tester.pumpAndSettle();

      // Deploy, the word the page builder and dartvel deploy use.
      expect(
          find.descendant(
              of: find.byKey(
                  const ValueKey<String>('dv-studio-function-deploy')),
              matching: find.text('Deploy')),
          findsOneWidget);

      await tester.tap(find
          .byKey(const ValueKey<String>('dv-studio-function-deploy')));
      await tester.pumpAndSettle();

      expect(await const DVWorkflowStore().names(), <String>['charge']);
      expect(find.byKey(const ValueKey<String>('dv-studio-function-charge')),
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
          .byKey(const ValueKey<String>('dv-studio-function-create')));
      await tester.pumpAndSettle();

      // Starting blank here would drop the steps on the first publish.
      expect(find.text('call capturePayment'), findsOneWidget);
    });

    testWidgets('deleting removes the workflow', (WidgetTester tester) async {
      await const DVWorkflowStore().save(DVWorkflowDocument(name: 'charge'));

      await openWorkflows(tester);
      await tester
          .tap(find.byKey(const ValueKey<String>('dv-studio-function-charge')));
      await tester.pumpAndSettle();
      await tester.tap(
          find.byKey(const ValueKey<String>('dv-studio-function-delete')));
      await tester.pumpAndSettle();

      expect(await const DVWorkflowStore().names(), isEmpty);
      expect(
          find.text('Select or create a function to edit.'), findsOneWidget);
    });

    testWidgets('view code shows the workflow as a backend function',
        (WidgetTester tester) async {
      await const DVWorkflowStore().save(DVWorkflowDocument(name: 'charge'));

      await openWorkflows(tester);
      await tester
          .tap(find.byKey(const ValueKey<String>('dv-studio-function-charge')));
      await tester.pumpAndSettle();
      await tester.tap(
          find.byKey(const ValueKey<String>('dv-studio-function-view-code')));
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
          .byKey(const ValueKey<String>('dv-studio-function-create')));
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
