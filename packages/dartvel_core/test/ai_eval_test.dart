// Evaluating an AI feature against golden transcripts.
//
// Every test here is about an evaluation that passes and has proven nothing.
// One that reads its answers out of the cache the golden was captured into is
// comparing the feature with itself. One scored against version 4 while
// version 5 ships is a pass for a prompt nobody is running. One with no
// transcripts at all passes every threshold. And one whose rubric model is
// allowed to decide has made the build depend on somebody else's model
// version.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class ScriptedAdapter implements DVAIAdapter {
  /// The answer for a ticket, by the body that appears in the prompt.
  final Map<String, String> answers = <String, String>{};
  Exception? fail;
  int calls = 0;

  String _answer(String prompt) {
    calls++;
    if (fail != null) throw fail!;
    for (final MapEntry<String, String> entry in answers.entries) {
      if (prompt.contains(entry.key)) return entry.value;
    }
    return 'no answer';
  }

  @override
  Future<String> chat(String prompt, {String provider = 'gemini'}) async =>
      _answer(prompt);

  @override
  Future<DVJsonObject> structuredOutput(
          String prompt, DVJsonObject schema) async =>
      <String, DVJsonValue>{'summary': DVJsonString(_answer(prompt))};

  @override
  Future<List<double>> embed(String text) => throw UnimplementedError();

  @override
  Future<DVAITranscript> transcribe(List<int> audioBytes,
          {String mimeType = 'audio/wav', String language = 'und'}) =>
      throw UnimplementedError();

  @override
  Future<DVAIAgentResult> runAgent(DVAIAgentRequest request) =>
      throw UnimplementedError();
}

const DVPromptTemplate template = DVPromptTemplate(
  system: 'Summarize the ticket for a support agent.',
  input: <String, Type>{'body': String},
  schema: <String, DVJsonValue>{'summary': DVJsonString('string')},
);

DVGoldenTranscript golden(String name, String body, String summary,
        {int version = 4}) =>
    DVGoldenTranscript(
      name: name,
      feature: 'ticket.summary',
      promptVersion: version,
      input: <String, Object?>{'body': body},
      expected: DVJsonMap(<String, DVJsonValue>{
        'summary': DVJsonString(summary),
      }),
    );

void main() {
  late ScriptedAdapter adapter;
  late DVPrompts prompts;
  late DVMemoryLogSink sink;

  DVAIFeatures features({
    DVCacheAdapter? cache,
    double threshold = 1.0,
    List<DVAIFallback> fallback = const <DVAIFallback>[],
  }) =>
      DVAIFeatures(
        prompts: prompts,
        adapter: adapter,
        model: 'local',
        cache: cache,
        logger: DVLogger(sinks: <DVLogSink>[sink]),
        tracer: DVTracer(),
      )..register(DVAIFeature(
          prompt: 'ticket.summary',
          evalThreshold: threshold,
          fallback: fallback,
        ));

  setUp(() {
    adapter = ScriptedAdapter()
      ..answers.addAll(<String, String>{
        'late delivery': 'Customer reports a late delivery.',
        'refund': 'Customer asks for a refund.',
        'password': 'Customer cannot log in.',
        'invoice': 'Customer disputes an invoice.',
      });
    prompts = DVPrompts(store: DVMemoryPromptStore())
      ..register(const DVPrompt(id: 'ticket.summary', version: 4), template);
    sink = DVMemoryLogSink();
    const DVTestHarness().resetCacheTags();
  });

  tearDown(() => const DVTestHarness().resetCacheTags());

  test('transcripts that match pass the gate', () async {
    final DVAIEvalReport report = await DVAIEval(features()).run(
      'ticket.summary',
      <DVGoldenTranscript>[
        golden('late', 'my late delivery', 'Customer reports a late delivery.'),
        golden('refund', 'I want a refund', 'Customer asks for a refund.'),
      ],
    );
    expect(report.passed, 2);
    expect(report.score, 1.0);
    expect(report.gate.ok, isTrue);
    expect(report.gate.code, isNull);
  });

  test('a transcript that no longer matches fails, with the difference',
      () async {
    adapter.answers['refund'] = 'Customer wants money back.';
    final DVAIEvalReport report = await DVAIEval(features()).run(
      'ticket.summary',
      <DVGoldenTranscript>[
        golden('late', 'my late delivery', 'Customer reports a late delivery.'),
        golden('refund', 'I want a refund', 'Customer asks for a refund.'),
      ],
    );
    expect(report.score, 0.5);
    expect(report.gate.ok, isFalse);
    expect(report.gate.code, 'DV-AIOPS-007');
    final DVAIEvalCase failed =
        report.cases.firstWhere((DVAIEvalCase c) => !c.passed);
    expect(failed.name, 'refund');
    expect(failed.failure, DVAIEvalFailure.mismatch);
    expect(failed.actual, isNotNull);
    final DVLogRecord gate =
        sink.records.firstWhere((DVLogRecord r) => r.code == 'DV-AIOPS-007');
    expect(gate.level, DVLogLevel.error);
  });

  test('the threshold is the declared one', () async {
    adapter.answers['refund'] = 'Customer wants money back.';
    final DVAIEvalReport report =
        await DVAIEval(features(threshold: 0.75)).run(
      'ticket.summary',
      <DVGoldenTranscript>[
        golden('late', 'my late delivery', 'Customer reports a late delivery.'),
        golden('refund', 'I want a refund', 'Customer asks for a refund.'),
        golden('login', 'forgot password', 'Customer cannot log in.'),
        golden('invoice', 'wrong invoice', 'Customer disputes an invoice.'),
      ],
    );
    expect(report.score, 0.75);
    expect(report.threshold, 0.75);
    expect(report.gate.ok, isTrue);
  });

  test('no transcripts is refused, not a vacuous pass', () async {
    final DVAIEvalReport report = await DVAIEval(features(threshold: 0))
        .run('ticket.summary', const <DVGoldenTranscript>[]);
    expect(report.gate.ok, isFalse);
    expect(report.gate.code, 'DV-AIOPS-007');
  });

  test('a transcript from another prompt version is stale, not a pass',
      () async {
    final DVAIEvalReport report = await DVAIEval(features()).run(
      'ticket.summary',
      <DVGoldenTranscript>[
        // The output still matches: the wording change did not move this one.
        // It is still not evidence about version 4.
        golden('late', 'my late delivery', 'Customer reports a late delivery.',
            version: 3),
      ],
    );
    expect(report.cases.single.passed, isFalse);
    expect(report.cases.single.failure, DVAIEvalFailure.staleVersion);
    expect(report.gate.ok, isFalse);
  });

  test('a transcript for another feature is refused', () async {
    await expectLater(
      DVAIEval(features()).run('ticket.summary', <DVGoldenTranscript>[
        const DVGoldenTranscript(
          name: 'x',
          feature: 'ticket.reply',
          promptVersion: 4,
          input: <String, Object?>{'body': 'refund'},
          expected: DVJsonNull(),
        ),
      ]),
      throwsArgumentError,
    );
  });

  test('the evaluation never answers from the cache', () async {
    // Capture primes the cache with today's answer; then the feature
    // regresses. An eval that read the cache would compare the golden with
    // the answer it was captured from and pass.
    final DVCacheAdapter cache = DVMemoryCacheAdapter();
    final DVAIFeatures f = features(cache: cache);
    final DVGoldenTranscript captured = await DVAIEval(f).capture(
      'ticket.summary',
      name: 'refund',
      input: const <String, Object?>{'body': 'I want a refund'},
    );
    await f.run('ticket.summary',
        input: const <String, Object?>{'body': 'I want a refund'});
    adapter.answers['refund'] = 'Customer wants money back.';

    final DVAIEvalReport report =
        await DVAIEval(f).run('ticket.summary', <DVGoldenTranscript>[captured]);
    expect(report.cases.single.passed, isFalse);
    expect(report.cases.single.failure, DVAIEvalFailure.mismatch);
  });

  test('a degraded or unavailable answer is a failure', () async {
    adapter.fail = const DVAIProviderException('local', 'down');
    final DVAIEvalReport report =
        await DVAIEval(features(fallback: <DVAIFallback>[DVAIFallback.degrade]))
            .run('ticket.summary', <DVGoldenTranscript>[
      golden('refund', 'I want a refund', 'Customer asks for a refund.'),
    ]);
    expect(report.cases.single.passed, isFalse);
    expect(report.cases.single.failure, DVAIEvalFailure.notAnswered);
  });

  test('a rubric score is recorded and never decides', () async {
    adapter.answers['refund'] = 'Customer wants money back.';
    final DVAIEvalReport report = await DVAIEval(
      features(),
      // A generous rubric that loves everything, and a harsh one that hates
      // everything: neither may move the gate.
      rubric: (DVGoldenTranscript t, DVJsonValue actual) =>
          t.name == 'refund' ? 1.0 : 0.0,
    ).run('ticket.summary', <DVGoldenTranscript>[
      golden('late', 'my late delivery', 'Customer reports a late delivery.'),
      golden('refund', 'I want a refund', 'Customer asks for a refund.'),
    ]);
    final DVAIEvalCase late =
        report.cases.firstWhere((DVAIEvalCase c) => c.name == 'late');
    final DVAIEvalCase refund =
        report.cases.firstWhere((DVAIEvalCase c) => c.name == 'refund');
    expect(late.passed, isTrue);
    expect(late.rubricScore, 0.0);
    expect(refund.passed, isFalse);
    expect(refund.rubricScore, 1.0);
    expect(report.score, 0.5);
  });

  test('a report names the prompt version and model it scored', () async {
    final DVAIEvalReport report = await DVAIEval(features()).run(
      'ticket.summary',
      <DVGoldenTranscript>[
        golden('late', 'my late delivery', 'Customer reports a late delivery.'),
      ],
    );
    expect(report.promptVersion, 4);
    expect(report.promptFingerprint,
        DVPromptVersion.compiled(
                const DVPrompt(id: 'ticket.summary', version: 4), template)
            .fingerprint);
    expect(report.cases.single.model, 'local');
  });

  test('transcripts round-trip through their file', () {
    final List<DVGoldenTranscript> transcripts = <DVGoldenTranscript>[
      golden('late', 'my late delivery', 'Customer reports a late delivery.'),
    ];
    final List<DVGoldenTranscript> read =
        DVGoldenTranscript.decodeFile(DVGoldenTranscript.encodeFile(transcripts));
    expect(read.single.name, 'late');
    expect(read.single.promptVersion, 4);
    expect(read.single.input, <String, Object?>{'body': 'my late delivery'});
    expect(DVJsonCodec.toJson(read.single.expected),
        <String, Object?>{'summary': 'Customer reports a late delivery.'});
  });
}
