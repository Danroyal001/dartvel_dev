// A prompt is a versioned asset.
//
// Every test here is about a prompt that looks like the one an evaluation was
// scored against and is not. Text edited under an unchanged version number is
// indistinguishable from the original in every output record it produces. A
// stored version that nobody exported back to source disappears on the next
// deploy with nothing to say it existed. A rollback that writes a fresh
// version "undoing" the change carries a number no evaluation has ever seen.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const DVPrompt summaryV4 = DVPrompt(id: 'ticket.summary', version: 4);

const DVPromptTemplate summaryTemplate = DVPromptTemplate(
  system: 'Summarize the ticket for a support agent.',
  input: <String, Type>{'body': String, 'status': String},
  schema: <String, DVJsonValue>{'summary': DVJsonString('string')},
);

DVPromptVersion stored(int version, String system,
        {Map<String, String>? input}) =>
    DVPromptVersion(
      id: 'ticket.summary',
      version: version,
      system: system,
      input: input ?? const <String, String>{'body': 'String', 'status': 'String'},
      schema: const <String, DVJsonValue>{'summary': DVJsonString('string')},
    );

void main() {
  group('the fingerprint', () {
    test('moves when the wording moves', () {
      final DVPromptVersion a =
          DVPromptVersion.compiled(summaryV4, summaryTemplate);
      final DVPromptVersion b = DVPromptVersion.compiled(
        summaryV4,
        const DVPromptTemplate(
          system: 'Summarise the ticket for a support agent.',
          input: <String, Type>{'body': String, 'status': String},
          schema: <String, DVJsonValue>{'summary': DVJsonString('string')},
        ),
      );
      expect(a.fingerprint, isNot(b.fingerprint));
    });

    test('does not move when only declaration order does', () {
      final DVPromptVersion a =
          DVPromptVersion.compiled(summaryV4, summaryTemplate);
      final DVPromptVersion b = DVPromptVersion.compiled(
        summaryV4,
        const DVPromptTemplate(
          system: 'Summarize the ticket for a support agent.',
          input: <String, Type>{'status': String, 'body': String},
          schema: <String, DVJsonValue>{'summary': DVJsonString('string')},
        ),
      );
      expect(a.fingerprint, b.fingerprint);
    });

    test('moves when the input types move', () {
      final DVPromptVersion a =
          DVPromptVersion.compiled(summaryV4, summaryTemplate);
      final DVPromptVersion b = DVPromptVersion.compiled(
        summaryV4,
        const DVPromptTemplate(
          system: 'Summarize the ticket for a support agent.',
          input: <String, Type>{'body': String, 'status': int},
          schema: <String, DVJsonValue>{'summary': DVJsonString('string')},
        ),
      );
      expect(a.fingerprint, isNot(b.fingerprint));
      expect(a.shape, isNot(b.shape));
    });
  });

  group('the prompt lockfile (DV-AIOPS-006)', () {
    DVPromptVersion compiled(int version, String system) =>
        DVPromptVersion.compiled(
          DVPrompt(id: 'ticket.summary', version: version),
          DVPromptTemplate(
            system: system,
            input: const <String, Type>{'body': String, 'status': String},
            schema: const <String, DVJsonValue>{
              'summary': DVJsonString('string'),
            },
          ),
        );

    test('an edit without a version bump is refused', () {
      final DVPromptLock lock =
          const DVPromptLock.empty().record(<DVPromptVersion>[compiled(4, 'A')]);
      final List<DVPromptLockProblem> problems =
          lock.check(<DVPromptVersion>[compiled(4, 'A, reworded')]);
      expect(problems, hasLength(1));
      expect(problems.single.code, 'DV-AIOPS-006');
      expect(problems.single.promptId, 'ticket.summary');
    });

    test('an edit with a version bump passes and is recorded', () {
      final DVPromptLock lock =
          const DVPromptLock.empty().record(<DVPromptVersion>[compiled(4, 'A')]);
      final DVPromptVersion next = compiled(5, 'A, reworded');
      expect(lock.check(<DVPromptVersion>[next]), isEmpty);
      final DVPromptLock recorded = lock.record(<DVPromptVersion>[next]);
      expect(recorded.contains(next), isTrue);
      // The history stays: version 4 is still a counterpart for anything
      // stored or evaluated against it.
      expect(recorded.contains(compiled(4, 'A')), isTrue);
    });

    test('an unchanged prompt passes', () {
      final DVPromptLock lock =
          const DVPromptLock.empty().record(<DVPromptVersion>[compiled(4, 'A')]);
      expect(lock.check(<DVPromptVersion>[compiled(4, 'A')]), isEmpty);
    });

    test('a version that goes backwards is refused', () {
      final DVPromptLock lock = const DVPromptLock.empty()
          .record(<DVPromptVersion>[compiled(4, 'A')])
          .record(<DVPromptVersion>[compiled(5, 'B')]);
      final List<DVPromptLockProblem> problems =
          lock.check(<DVPromptVersion>[compiled(4, 'A')]);
      expect(problems.single.code, 'DV-AIOPS-006');
    });

    test('recording refuses a lock whose check fails', () {
      final DVPromptLock lock =
          const DVPromptLock.empty().record(<DVPromptVersion>[compiled(4, 'A')]);
      expect(
        () => lock.record(<DVPromptVersion>[compiled(4, 'changed')]),
        throwsA(isA<DVAIOpsError>()
            .having((DVAIOpsError e) => e.code, 'code', 'DV-AIOPS-006')),
      );
    });

    test('round-trips through its file', () {
      final DVPromptLock lock = const DVPromptLock.empty()
          .record(<DVPromptVersion>[compiled(4, 'A')])
          .record(<DVPromptVersion>[compiled(5, 'B')]);
      final DVPromptLock read = DVPromptLock.decode(lock.encode());
      expect(read.contains(compiled(4, 'A')), isTrue);
      expect(read.contains(compiled(5, 'B')), isTrue);
      expect(read.contains(compiled(5, 'C')), isFalse);
      expect(DVPromptLock.fileName, 'dartvel.prompts.lock');
    });

    test('a hand-edited file with versions out of order is refused', () {
      const String source = '{"format": 1, "prompts": {"ticket.summary": ['
          '{"version": 5, "fingerprint": "b"}, '
          '{"version": 4, "fingerprint": "a"}]}}';
      expect(() => DVPromptLock.decode(source), throwsFormatException);
    });

    test('a file in another format is refused rather than guessed', () {
      expect(() => DVPromptLock.decode('{"format": 2, "prompts": {}}'),
          throwsFormatException);
    });
  });

  group('stored versions', () {
    late DVPrompts prompts;
    late DVMemoryLogSink sink;

    setUp(() {
      sink = DVMemoryLogSink();
      prompts = DVPrompts(
        store: DVMemoryPromptStore(),
        logger: DVLogger(sinks: <DVLogSink>[sink]),
      )..register(summaryV4, summaryTemplate);
    });

    test('with nothing stored, the compiled version answers', () async {
      final DVResolvedPrompt resolved = await prompts.resolve('ticket.summary');
      expect(resolved.version.version, 4);
      expect(resolved.source, DVPromptSource.compiled);
    });

    test('a stored version overrides the compiled one', () async {
      await prompts.ship(stored(5, 'Summarize the ticket in one line.'));
      final DVResolvedPrompt resolved = await prompts.resolve('ticket.summary');
      expect(resolved.version.version, 5);
      expect(resolved.version.system, 'Summarize the ticket in one line.');
      expect(resolved.source, DVPromptSource.stored);
    });

    test('deleting the stored version restores the compiled one', () async {
      await prompts.ship(stored(5, 'Summarize the ticket in one line.'));
      await prompts.unship('ticket.summary', 5);
      final DVResolvedPrompt resolved = await prompts.resolve('ticket.summary');
      expect(resolved.version.version, 4);
      expect(resolved.source, DVPromptSource.compiled);
    });

    test('a stored version cannot change the typed shape', () async {
      // The call site was compiled against body and status. A stored version
      // that expects something else is a store release breaking a build.
      expect(
        () => prompts.ship(stored(5, 'Summarize.',
            input: const <String, String>{'body': 'String'})),
        throwsArgumentError,
      );
    });

    test('a stored version reusing a number with other text is refused',
        () async {
      await expectLater(
        prompts.ship(stored(4, 'Different text under the compiled number.')),
        throwsA(isA<DVAIOpsError>()
            .having((DVAIOpsError e) => e.code, 'code', 'DV-AIOPS-006')),
      );
    });

    test('a stored version reusing a stored number with other text is refused',
        () async {
      await prompts.ship(stored(5, 'One line.'));
      await expectLater(
        prompts.ship(stored(5, 'Two lines.')),
        throwsA(isA<DVAIOpsError>()
            .having((DVAIOpsError e) => e.code, 'code', 'DV-AIOPS-006')),
      );
    });

    test('a prompt nobody compiled cannot be stored', () async {
      await expectLater(
        prompts.ship(DVPromptVersion(
            id: 'invented', version: 1, system: 'x')),
        throwsArgumentError,
      );
    });

    test('a rollback ships the previous version, not an inverse', () async {
      await prompts.ship(stored(5, 'One line.'));
      final String five =
          (await prompts.resolve('ticket.summary')).version.fingerprint;
      await prompts.ship(stored(6, 'One line, politely.'));

      final DVResolvedPrompt back = await prompts.rollback('ticket.summary');
      expect(back.version.version, 5);
      expect(back.version.fingerprint, five);
      expect((await prompts.resolve('ticket.summary')).version.version, 5);

      final DVResolvedPrompt compiled = await prompts.rollback('ticket.summary');
      expect(compiled.version.version, 4);
      expect(compiled.source, DVPromptSource.compiled);
    });

    test('rolling back with nothing stored is refused', () async {
      await expectLater(
          prompts.rollback('ticket.summary'), throwsStateError);
    });
  });

  group('a stored version with no counterpart (DV-AIOPS-001)', () {
    test('is reported by the audit, and stops once the lock records it',
        () async {
      final DVMemoryPromptStore store = DVMemoryPromptStore();
      final DVPromptLock lock = const DVPromptLock.empty().record(
          <DVPromptVersion>[DVPromptVersion.compiled(summaryV4, summaryTemplate)]);
      final DVPrompts prompts = DVPrompts(store: store, lock: lock)
        ..register(summaryV4, summaryTemplate);

      await prompts.ship(stored(5, 'One line.'));
      final List<DVPromptLockProblem> problems = await prompts.audit();
      expect(problems.single.code, 'DV-AIOPS-001');
      expect(problems.single.version, 5);

      // Exported back to source, bumped and recorded: now it has one.
      final DVPrompts exported = DVPrompts(
        store: store,
        lock: lock.record(<DVPromptVersion>[stored(5, 'One line.')]),
      )..register(const DVPrompt(id: 'ticket.summary', version: 5),
          const DVPromptTemplate(
            system: 'One line.',
            input: <String, Type>{'body': String, 'status': String},
            schema: <String, DVJsonValue>{'summary': DVJsonString('string')},
          ));
      expect(await exported.audit(), isEmpty);
    });

    test('a stored version the lock knows under other text is not a counterpart',
        () async {
      final DVPromptLock lock = const DVPromptLock.empty()
          .record(<DVPromptVersion>[DVPromptVersion.compiled(summaryV4, summaryTemplate)])
          .record(<DVPromptVersion>[stored(5, 'The text version 5 had.')]);
      final DVPrompts prompts = DVPrompts(store: DVMemoryPromptStore(), lock: lock)
        ..register(summaryV4, summaryTemplate);
      await expectLater(
        prompts.ship(stored(5, 'Some other text.')),
        throwsA(isA<DVAIOpsError>()
            .having((DVAIOpsError e) => e.code, 'code', 'DV-AIOPS-006')),
      );
    });

    test('is logged when it answers, once', () async {
      final DVMemoryLogSink sink = DVMemoryLogSink();
      final DVPrompts prompts = DVPrompts(
        store: DVMemoryPromptStore(),
        lock: const DVPromptLock.empty().record(<DVPromptVersion>[
          DVPromptVersion.compiled(summaryV4, summaryTemplate),
        ]),
        logger: DVLogger(sinks: <DVLogSink>[sink]),
      )..register(summaryV4, summaryTemplate);
      await prompts.ship(stored(5, 'One line.'));
      await prompts.resolve('ticket.summary');
      await prompts.resolve('ticket.summary');
      final List<DVLogRecord> reported = <DVLogRecord>[
        for (final DVLogRecord r in sink.records)
          if (r.code == 'DV-AIOPS-001') r,
      ];
      expect(reported, hasLength(1));
      expect(reported.single.level, DVLogLevel.warn);
    });
  });
}
