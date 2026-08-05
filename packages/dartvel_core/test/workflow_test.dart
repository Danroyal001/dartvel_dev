// Visual backend workflows: the runner executes real registered actions, and
// the exporter emits an ordinary @DVBackendFunction. Same bargain as the page
// builder — data so saving publishes, code so the builder can be dropped.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  final calls = <String, List<Map<String, Object?>>>{};

  setUp(() {
    calls.clear();
    DVWorkflows.reset();
    DVWorkflows.registerAction('sendMail', (Map<String, Object?> args) async {
      calls.putIfAbsent('sendMail', () => []).add(args);
      return 'sent:${args['to']}';
    });
    DVWorkflows.registerAction('audit', (Map<String, Object?> args) async {
      calls.putIfAbsent('audit', () => []).add(args);
      return null;
    });
  });

  group('running', () {
    test('calls a registered action with resolved arguments', () async {
      final workflow = DVWorkflowDocument(
        name: 'welcome',
        parameters: <String>['email'],
        steps: <DVWorkflowStep>[
          DVWorkflowStep.call(
            'sendMail',
            arguments: <String, DVWorkflowValue>{
              'to': const DVWorkflowValue.reference('email'),
              'subject': const DVWorkflowValue.literal('Welcome'),
            },
            assignTo: 'receipt',
          ),
          DVWorkflowStep.returns(const DVWorkflowValue.reference('receipt')),
        ],
      );

      final result = await DVWorkflows.run(
        workflow,
        input: <String, Object?>{'email': 'ada@example.com'},
      );

      expect(result, 'sent:ada@example.com');
      expect(calls['sendMail']!.single, <String, Object?>{
        'to': 'ada@example.com',
        'subject': 'Welcome',
      });
    });

    test('a condition takes the branch its value selects', () async {
      DVWorkflowDocument workflow(bool premium) => DVWorkflowDocument(
            name: 'greet',
            parameters: <String>['isPremium'],
            steps: <DVWorkflowStep>[
              DVWorkflowStep.condition(
                const DVWorkflowValue.reference('isPremium'),
                then: <DVWorkflowStep>[
                  DVWorkflowStep.returns(
                    const DVWorkflowValue.literal('premium'),
                  ),
                ],
                otherwise: <DVWorkflowStep>[
                  DVWorkflowStep.returns(
                    const DVWorkflowValue.literal('standard'),
                  ),
                ],
              ),
            ],
          );

      expect(
        await DVWorkflows.run(
          workflow(true),
          input: <String, Object?>{'isPremium': true},
        ),
        'premium',
      );
      expect(
        await DVWorkflows.run(
          workflow(false),
          input: <String, Object?>{'isPremium': false},
        ),
        'standard',
      );
    });

    test('a return inside a branch ends the whole workflow', () async {
      final workflow = DVWorkflowDocument(
        name: 'guard',
        parameters: <String>['blocked'],
        steps: <DVWorkflowStep>[
          DVWorkflowStep.condition(
            const DVWorkflowValue.reference('blocked'),
            then: <DVWorkflowStep>[
              DVWorkflowStep.returns(const DVWorkflowValue.literal('stopped')),
            ],
          ),
          // Must not run when the branch returned.
          DVWorkflowStep.call('audit'),
          DVWorkflowStep.returns(const DVWorkflowValue.literal('continued')),
        ],
      );

      expect(
        await DVWorkflows.run(
          workflow,
          input: <String, Object?>{'blocked': true},
        ),
        'stopped',
      );
      expect(calls['audit'], isNull);

      expect(
        await DVWorkflows.run(
          workflow,
          input: <String, Object?>{'blocked': false},
        ),
        'continued',
      );
      expect(calls['audit'], hasLength(1));
    });

    test('set introduces a variable later steps can read', () async {
      final workflow = DVWorkflowDocument(
        name: 'compose',
        steps: <DVWorkflowStep>[
          DVWorkflowStep.set(
            'subject',
            const DVWorkflowValue.literal('Hello'),
          ),
          DVWorkflowStep.returns(const DVWorkflowValue.reference('subject')),
        ],
      );

      expect(await DVWorkflows.run(workflow), 'Hello');
    });

    test('a workflow with no return yields null rather than a stale value',
        () async {
      final workflow = DVWorkflowDocument(
        name: 'fireAndForget',
        steps: <DVWorkflowStep>[DVWorkflowStep.call('audit')],
      );

      expect(await DVWorkflows.run(workflow), isNull);
      expect(calls['audit'], hasLength(1));
    });
  });

  group('failing loudly', () {
    test('an unknown action names what is registered', () async {
      final workflow = DVWorkflowDocument(
        name: 'typo',
        steps: <DVWorkflowStep>[DVWorkflowStep.call('sendMial')],
      );

      await expectLater(
        DVWorkflows.run(workflow),
        throwsA(
          isA<DVWorkflowException>().having(
            (DVWorkflowException e) => e.toString(),
            'message',
            allOf(contains('sendMial'), contains('sendMail')),
          ),
        ),
      );
    });

    test('an unknown variable is an error, not a null', () async {
      // Silently yielding null here would send mail to nobody and report
      // success.
      final workflow = DVWorkflowDocument(
        name: 'oops',
        steps: <DVWorkflowStep>[
          DVWorkflowStep.call(
            'sendMail',
            arguments: <String, DVWorkflowValue>{
              'to': const DVWorkflowValue.reference('missing'),
            },
          ),
        ],
      );

      await expectLater(
        DVWorkflows.run(workflow),
        throwsA(isA<DVWorkflowException>()),
      );
      expect(calls['sendMail'], isNull);
    });

    test('missing input names the parameters the workflow declares', () async {
      final workflow = DVWorkflowDocument(
        name: 'needsInput',
        parameters: <String>['email'],
        steps: <DVWorkflowStep>[],
      );

      await expectLater(
        DVWorkflows.run(workflow),
        throwsA(
          isA<DVWorkflowException>().having(
            (DVWorkflowException e) => e.message,
            'message',
            contains('email'),
          ),
        ),
      );
    });

    test('the failing step is identified', () async {
      final step = DVWorkflowStep.call('nope');
      final workflow =
          DVWorkflowDocument(name: 'w', steps: <DVWorkflowStep>[step]);

      await expectLater(
        DVWorkflows.run(workflow),
        throwsA(
          isA<DVWorkflowException>().having(
            (DVWorkflowException e) => e.stepId,
            'stepId',
            step.id,
          ),
        ),
      );
    });
  });

  group('serialization', () {
    test('a workflow round-trips, branches and references included', () {
      final workflow = DVWorkflowDocument(
        name: 'welcome',
        parameters: <String>['email'],
        steps: <DVWorkflowStep>[
          DVWorkflowStep.set('greeting', const DVWorkflowValue.literal('Hi')),
          DVWorkflowStep.condition(
            const DVWorkflowValue.reference('email'),
            then: <DVWorkflowStep>[
              DVWorkflowStep.call(
                'sendMail',
                arguments: <String, DVWorkflowValue>{
                  'to': const DVWorkflowValue.reference('email'),
                },
              ),
            ],
          ),
        ],
      );

      final restored = DVWorkflowDocument.fromJson(workflow.toJson());

      expect(restored.toJson(), workflow.toJson());
      expect(restored.steps[1].branches['then']!.single.name, 'sendMail');
    });

    test('a literal that looks like a reference stays a literal', () {
      // Only the {'$var': name} shape is a reference; keeping that explicit
      // means data is never mistaken for a variable name.
      final value = DVWorkflowValue.fromJson(<String, Object?>{
        r'$var': 'user',
        'extra': 1,
      });

      expect(value.variable, isNull);
      expect(value.literal, isA<Map<Object?, Object?>>());
    });

    test('a workflow without a name is rejected', () {
      expect(
        () => DVWorkflowDocument.fromJson(<String, Object?>{'steps': <Object?>[]}),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('code export', () {
    test('emits an ordinary private @DVBackendFunction', () {
      final workflow = DVWorkflowDocument(
        name: 'welcome',
        parameters: <String>['email'],
        steps: <DVWorkflowStep>[
          DVWorkflowStep.set(
            'subject',
            const DVWorkflowValue.literal("Ada's welcome"),
          ),
          DVWorkflowStep.call(
            'sendMail',
            arguments: <String, DVWorkflowValue>{
              'to': const DVWorkflowValue.reference('email'),
              'subject': const DVWorkflowValue.reference('subject'),
            },
            assignTo: 'receipt',
          ),
          DVWorkflowStep.returns(const DVWorkflowValue.reference('receipt')),
        ],
      );

      final source = workflow.toDartSource();

      expect(source, contains('@DVBackendFunction()'));
      // Private inputs must be expression-bodied until body lowering
      // exists, so the steps live in a public helper.
      expect(
        source,
        contains('Future<Object?> _welcome(Object? email) => '
            'welcomeBody(email);'),
      );
      expect(
        source,
        contains('Future<Object?> welcomeBody(Object? email) async {'),
      );
      // A quote in a literal must not break the emitted source.
      expect(source, contains(r"final subject = 'Ada\'s welcome';"));
      expect(
        source,
        contains('final receipt = await sendMail(to: email, subject: subject);'),
      );
      expect(source, contains('return receipt;'));
      // Nothing of the builder survives the export.
      expect(source, isNot(contains('DVWorkflow')));
    });

    test('a condition exports as an if/else', () {
      final workflow = DVWorkflowDocument(
        name: 'guard',
        parameters: <String>['blocked'],
        steps: <DVWorkflowStep>[
          DVWorkflowStep.condition(
            const DVWorkflowValue.reference('blocked'),
            then: <DVWorkflowStep>[
              DVWorkflowStep.returns(const DVWorkflowValue.literal('stopped')),
            ],
            otherwise: <DVWorkflowStep>[
              DVWorkflowStep.call('audit'),
            ],
          ),
        ],
      );

      final source = workflow.toDartSource();

      expect(source, contains('if (blocked == true) {'));
      expect(source, contains("return 'stopped';"));
      expect(source, contains('} else {'));
      expect(source, contains('await audit();'));
    });
  });

  group('store', () {
    late SqliteDVDatabaseAdapter database;

    setUp(() {
      database = SqliteDVDatabaseAdapter.memory();
      const DVDatabase().configure(database);
    });

    tearDown(() => database.close());

    test('saving publishes and re-saving replaces', () async {
      const store = DVWorkflowStore();
      final changed = <String>[];
      final subscription = DVWorkflowStore.changes.listen(changed.add);

      await store.save(DVWorkflowDocument(name: 'welcome'));
      expect(await store.names(), <String>['welcome']);

      await store.save(
        DVWorkflowDocument(
          name: 'welcome',
          steps: <DVWorkflowStep>[DVWorkflowStep.call('audit')],
        ),
      );
      expect(await store.names(), <String>['welcome']);
      expect((await store.load('welcome'))!.steps, hasLength(1));

      await store.delete('welcome');
      expect(await store.load('welcome'), isNull);

      await Future<void>.delayed(Duration.zero);
      expect(changed, <String>['welcome', 'welcome', 'welcome']);
      await subscription.cancel();
    });

    test('a stored workflow runs after a round trip', () async {
      const store = DVWorkflowStore();
      await store.save(
        DVWorkflowDocument(
          name: 'welcome',
          parameters: <String>['email'],
          steps: <DVWorkflowStep>[
            DVWorkflowStep.call(
              'sendMail',
              arguments: <String, DVWorkflowValue>{
                'to': const DVWorkflowValue.reference('email'),
              },
              assignTo: 'receipt',
            ),
            DVWorkflowStep.returns(const DVWorkflowValue.reference('receipt')),
          ],
        ),
      );

      final loaded = await store.load('welcome');
      final result = await DVWorkflows.run(
        loaded!,
        input: <String, Object?>{'email': 'grace@example.com'},
      );

      expect(result, 'sent:grace@example.com');
    });
  });
}
