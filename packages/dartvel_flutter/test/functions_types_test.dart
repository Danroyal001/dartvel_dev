// A workflow's inputs and result have types, and they are checked.
//
// A workflow exported as `Future<Object?> _welcome(Object? email)` is a
// backend function that validates nothing: the generated client sends
// anything, the server decodes nothing, and a wrong input fails inside a step
// instead of at the door. Each parameter now has a type a site owner picks by
// name -- Text, Whole number, Number, Yes or no -- the export is typed Dart,
// and a run refuses input of the wrong type before any step runs.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

DVWorkflowDocument welcome({
  List<DVWorkflowParameter>? parameters,
  DVWorkflowType? returns = DVWorkflowType.text,
}) =>
    DVWorkflowDocument(
      name: 'welcome',
      parameters: parameters ??
          const <DVWorkflowParameter>[
            DVWorkflowParameter('email', DVWorkflowType.text),
            DVWorkflowParameter('wantsNews', DVWorkflowType.yesNo),
            DVWorkflowParameter('age', DVWorkflowType.wholeNumber,
                optional: true),
          ],
      returns: returns,
      steps: <DVWorkflowStep>[
        DVWorkflowStep.returns(const DVWorkflowValue.reference('email')),
      ],
    );

void main() {
  tearDown(DVWorkflows.reset);

  group('the document', () {
    test('keeps each parameter\'s type and the result\'s', () {
      final DVWorkflowDocument back =
          DVWorkflowDocument.fromJson(welcome().toJson());

      expect(back.parameters, welcome().parameters);
      expect(back.returns, DVWorkflowType.text);
    });

    test('reads a parameter saved before types as one with no type', () {
      final DVWorkflowDocument old = DVWorkflowDocument.fromJson(
          <String, Object?>{'name': 'old', 'parameters': <Object?>['email']});

      expect(old.parameters.single.name, 'email');
      expect(old.parameters.single.type, isNull);
      expect(old.untyped, <String>['email']);
    });

    test('names each type the way a site owner would', () {
      expect(<String>[for (final t in DVWorkflowType.values) t.label],
          <String>['Text', 'Whole number', 'Number', 'Yes or no']);
    });
  });

  group('the export', () {
    test('is typed Dart', () {
      final String source = welcome().toDartSource();

      expect(
          source,
          contains('Future<String> _welcome(String email, bool wantsNews, '
              'int? age) => welcomeBody(email, wantsNews, age);'));
      expect(
          source,
          contains('Future<String> welcomeBody(String email, bool wantsNews, '
              'int? age) async {'));
      expect(source, isNot(contains('Object?')));
    });

    test('with no result type returns nothing', () {
      final DVWorkflowDocument silent = DVWorkflowDocument(
        name: 'ping',
        parameters: const <DVWorkflowParameter>[
          DVWorkflowParameter('host', DVWorkflowType.text),
        ],
      );

      expect(silent.toDartSource(),
          contains('Future<void> _ping(String host) => pingBody(host);'));
    });

    test('refuses a parameter with no type', () {
      final DVWorkflowDocument old = DVWorkflowDocument.fromJson(
          <String, Object?>{'name': 'old', 'parameters': <Object?>['email']});

      expect(
        old.toDartSource,
        throwsA(isA<DVWorkflowException>().having((DVWorkflowException e) =>
            e.message, 'message', contains('email'))),
      );
    });
  });

  group('a run', () {
    test('takes input of the declared types', () async {
      expect(
        await DVWorkflows.run(welcome(),
            input: <String, Object?>{'email': 'a@b.co', 'wantsNews': true}),
        'a@b.co',
      );
    });

    test('refuses input of the wrong type before any step runs', () async {
      await expectLater(
        DVWorkflows.run(welcome(),
            input: <String, Object?>{'email': 'a@b.co', 'wantsNews': 'yes'}),
        throwsA(isA<DVWorkflowException>().having(
            (DVWorkflowException e) => e.message,
            'message',
            allOf(contains('wantsNews'), contains('Yes or no')))),
      );
    });

    test('takes a whole number where a number is asked for', () async {
      final DVWorkflowDocument half = DVWorkflowDocument(
        name: 'half',
        parameters: const <DVWorkflowParameter>[
          DVWorkflowParameter('n', DVWorkflowType.number),
        ],
        returns: DVWorkflowType.number,
        steps: <DVWorkflowStep>[
          DVWorkflowStep.returns(const DVWorkflowValue.reference('n')),
        ],
      );

      expect(await DVWorkflows.run(half, input: <String, Object?>{'n': 2}), 2.0);
    });

    test('refuses a missing input unless it is optional', () async {
      await expectLater(
        DVWorkflows.run(welcome(), input: <String, Object?>{'email': 'a@b.co'}),
        throwsA(isA<DVWorkflowException>()),
      );
    });

    test('refuses a workflow with an untyped parameter', () async {
      final DVWorkflowDocument old = DVWorkflowDocument.fromJson(
          <String, Object?>{'name': 'old', 'parameters': <Object?>['email']});

      await expectLater(
        DVWorkflows.run(old, input: <String, Object?>{'email': 'a@b.co'}),
        throwsA(isA<DVWorkflowException>()),
      );
    });

    test('refuses a result of the wrong type', () async {
      final DVWorkflowDocument wrong = welcome(returns: DVWorkflowType.wholeNumber);

      await expectLater(
        DVWorkflows.run(wrong,
            input: <String, Object?>{'email': 'a@b.co', 'wantsNews': false}),
        throwsA(isA<DVWorkflowException>().having(
            (DVWorkflowException e) => e.message,
            'message',
            contains('Whole number'))),
      );
    });
  });
}
