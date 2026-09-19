// Frontend and backend functions, each with the builder.
//
// Studio had one Workflows section, and everything built in it became a
// backend function. Logic that belongs in the app -- what a button does, which
// backend function to call and what to do with the answer -- had nowhere to
// be built. A workflow now runs on a side: a backend function exports as the
// @DVBackendFunction it always did, and a frontend function exports as a plain
// function in the app, whose Call steps are calls through the generated client
// -- so a frontend function calls a backend one by name, as hand-written app
// code does.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVWorkflowDocument signUp({DVWorkflowSide side = DVWorkflowSide.frontend}) =>
    DVWorkflowDocument(
      name: 'signUp',
      side: side,
      parameters: const <DVWorkflowParameter>[
        DVWorkflowParameter('email', DVWorkflowType.text),
      ],
      returns: DVWorkflowType.text,
      steps: <DVWorkflowStep>[
        DVWorkflowStep.call(
          'sendWelcome',
          arguments: const <String, DVWorkflowValue>{
            'to': DVWorkflowValue.reference('email'),
          },
          assignTo: 'receipt',
        ),
        DVWorkflowStep.returns(const DVWorkflowValue.reference('receipt')),
      ],
    );

Widget host() => MaterialApp(
      home: Material(
        child: DVStudioScreen(sections: dvFunctionStudioSections()),
      ),
    );

void main() {
  late SqliteDVDatabaseAdapter database;

  setUp(() {
    database = SqliteDVDatabaseAdapter.memory();
    DV.Database.configure(database);
  });

  tearDown(() {
    database.close();
    DVWorkflows.reset();
  });

  group('the document', () {
    test('keeps its side', () {
      final DVWorkflowDocument back =
          DVWorkflowDocument.fromJson(signUp().toJson());

      expect(back.side, DVWorkflowSide.frontend);
    });

    // The editor rebuilds the document on every input and result change; one
    // that dropped the side turned a frontend function into a backend one.
    test('stays on its side through the builder\'s edits', () {
      final DVWorkflowEditorController controller =
          DVWorkflowEditorController(signUp());
      addTearDown(controller.dispose);

      controller.addInput();
      controller.setReturns(null);

      expect(controller.document.side, DVWorkflowSide.frontend);
    });

    test('saved before sides existed is a backend function', () {
      final DVWorkflowDocument old = DVWorkflowDocument.fromJson(
          <String, Object?>{'name': 'old', 'steps': <Object?>[]});

      expect(old.side, DVWorkflowSide.backend);
    });
  });

  group('a frontend function\'s export', () {
    test('is a plain function in the app, not a backend function', () {
      final String source = signUp().toDartSource();

      expect(source, isNot(contains('@DVBackendFunction')));
      expect(source,
          contains("import '../dartvel_client/dartvel_client.dart';"));
      expect(source,
          contains('Future<String> signUp(String email) async {'));
    });

    test('calls a backend function through the generated client', () {
      expect(signUp().toDartSource(),
          contains('final receipt = await sendWelcome(to: email);'));
    });

    test('a backend function still exports as one', () {
      expect(signUp(side: DVWorkflowSide.backend).toDartSource(),
          contains('@DVBackendFunction()'));
    });
  });

  group('a frontend function run in Studio', () {
    test('calls the backend function it names', () async {
      DVWorkflows.registerAction('sendWelcome',
          (Map<String, Object?> arguments) async => 'sent to ${arguments['to']}');

      expect(
        await DVWorkflows.run(signUp(),
            input: <String, Object?>{'email': 'a@b.co'}),
        'sent to a@b.co',
      );
    });
  });

  group('the store', () {
    test('lists each side\'s functions apart', () async {
      const DVWorkflowStore store = DVWorkflowStore();
      await store.save(signUp());
      await store.save(DVWorkflowDocument(name: 'sendWelcome'));

      expect(await store.names(side: DVWorkflowSide.frontend),
          <String>['signUp']);
      expect(await store.names(side: DVWorkflowSide.backend),
          <String>['sendWelcome']);
      expect(await store.names(), <String>['sendWelcome', 'signUp']);
    });
  });

  group('Studio', () {
    Future<void> open(WidgetTester tester, String id) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey<String>('dv-studio-section-$id')));
      await tester.pumpAndSettle();
    }

    testWidgets('has a Frontend and a Backend section',
        (WidgetTester tester) async {
      await open(tester, 'frontend');

      expect(find.text('Frontend'), findsWidgets);
      expect(find.text('Backend'), findsWidgets);
      expect(find.text('Frontend functions'), findsOneWidget);
    });

    testWidgets('each lists only its own side\'s functions',
        (WidgetTester tester) async {
      await const DVWorkflowStore().save(signUp());
      await const DVWorkflowStore()
          .save(DVWorkflowDocument(name: 'sendWelcome'));

      await open(tester, 'frontend');
      expect(find.text('signUp'), findsOneWidget);
      expect(find.text('sendWelcome'), findsNothing);

      await tester.tap(
          find.byKey(const ValueKey<String>('dv-studio-section-functions')));
      await tester.pumpAndSettle();
      expect(find.text('Backend functions'), findsOneWidget);
      expect(find.text('sendWelcome'), findsOneWidget);
      expect(find.text('signUp'), findsNothing);
    });

    testWidgets('a function made in Frontend is a frontend function',
        (WidgetTester tester) async {
      await open(tester, 'frontend');

      await tester.enterText(find.byType(EditableText).first, 'checkout');
      await tester
          .tap(find.byKey(const ValueKey<String>('dv-studio-function-create')));
      await tester.pumpAndSettle();
      await tester.tap(
          find.byKey(const ValueKey<String>('dv-studio-function-deploy')));
      await tester.pumpAndSettle();

      final DVWorkflowDocument? saved =
          await const DVWorkflowStore().load('checkout');
      expect(saved?.side, DVWorkflowSide.frontend);
    });
  });
}
