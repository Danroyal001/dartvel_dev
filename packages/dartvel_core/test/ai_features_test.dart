// An AI feature after it ships: budgets, fallbacks, caching, and what it may
// see.
//
// Every test here is about a feature that looks like it is working and is
// not. A budget checked after the call has already spent what it was meant to
// protect. A fallback nobody reported is an application that got worse on a
// Tuesday with no way to say when. A cached answer keyed without the prompt
// version serves last week's wording after this week's shipped. A sensitive
// field that reaches a prompt has left the building, whatever the logs say.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class Ticket {}

class Customer {}

class Invoice {}

class FakeAdapter implements DVAIAdapter {
  FakeAdapter(this.name, {this.fail, this.error});

  final String name;

  /// Thrown from every call: a provider outage or refusal.
  Exception? fail;

  /// Thrown from every call: a programming error, not an outage.
  Error? error;

  final List<String> prompts = <String>[];

  String answer = '';

  Future<void> _call(String prompt) async {
    prompts.add(prompt);
    if (fail != null) throw fail!;
    if (error != null) throw error!;
  }

  @override
  Future<String> chat(String prompt, {String provider = 'gemini'}) async {
    await _call(prompt);
    return answer.isEmpty ? 'summary by $name' : answer;
  }

  @override
  Future<DVJsonObject> structuredOutput(
      String prompt, DVJsonObject schema) async {
    await _call(prompt);
    return <String, DVJsonValue>{
      'summary': DVJsonString(answer.isEmpty ? 'summary by $name' : answer),
    };
  }

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

const DVPrompt summaryPrompt = DVPrompt(id: 'ticket.summary', version: 4);

const DVPromptTemplate summaryTemplate = DVPromptTemplate(
  system: 'Summarize the ticket for a support agent.',
  input: <String, Type>{'id': String, 'body': String, 'status': String},
  schema: <String, DVJsonValue>{'summary': DVJsonString('string')},
);

const Map<String, Object?> ticket42 = <String, Object?>{
  'id': '42',
  'body': 'The delivery is late again.',
  'status': 'open',
};

void main() {
  late FakeAdapter sonnet;
  late FakeAdapter haiku;
  late DVPrompts prompts;
  late DVMemoryLogSink sink;
  late DVMemoryTraceExporter spans;
  late DVAIRunLog runs;
  late DateTime now;

  DVMeterDefinition tokens({num limit = 100000, DVQuota atLimit = DVQuota.block}) =>
      DVMeterDefinition('aiTokens',
          unit: 'token', limit: DVLimit.fixed(limit), atLimit: atLimit);

  DVAIFeatures features({
    DVMeters? meters,
    DVMeterDefinition? meter,
    DVCacheAdapter? cache,
    DVAIContextPolicy policy = const DVAIContextPolicy(),
  }) =>
      DVAIFeatures(
        prompts: prompts,
        adapter: sonnet,
        model: 'sonnet',
        models: <String, DVAIAdapter>{'haiku': haiku},
        meters: meters,
        meterDefinitions: <String, DVMeterDefinition>{
          if (meter != null) meter.name: meter,
        },
        cache: cache,
        contextModels: const <DVAIContextModel>[
          DVAIContextModel(Ticket,
              name: 'Ticket', fields: <String>{'id', 'body', 'status'}),
          DVAIContextModel(Customer,
              name: 'Customer',
              fields: <String>{'name', 'email', 'ssn'},
              sensitive: <String>{'ssn'}),
          DVAIContextModel(Invoice,
              name: 'Invoice', fields: <String>{'total'}),
        ],
        policy: policy,
        runs: runs,
        logger: DVLogger(minimumLevel: DVLogLevel.trace, sinks: <DVLogSink>[sink]),
        tracer: DVTracer(exporter: spans),
        clock: () => now,
      );

  List<String> codes() => <String>[
        for (final DVLogRecord r in sink.records)
          if (r.code != null) r.code!,
      ];

  setUp(() {
    now = DateTime.utc(2026, 9, 14, 12);
    sonnet = FakeAdapter('sonnet');
    haiku = FakeAdapter('haiku');
    prompts = DVPrompts(store: DVMemoryPromptStore())
      ..register(summaryPrompt, summaryTemplate);
    sink = DVMemoryLogSink();
    spans = DVMemoryTraceExporter();
    runs = DVAIRunLog();
    const DVTestHarness().resetCacheTags();
  });

  tearDown(() {
    DVTenants.reset();
    DVSecrets.reset();
    const DVTestHarness().resetCacheTags();
  });

  group('declaring a feature', () {
    test('a feature over a prompt nobody registered is refused', () {
      expect(
        () => features().register(const DVAIFeature(prompt: 'nope')),
        throwsArgumentError,
      );
    });

    test('a budget naming an unknown meter is refused', () {
      expect(
        () => features().register(const DVAIFeature(
            prompt: 'ticket.summary', budget: DVMeterRef.tenant('aiTokens'))),
        throwsArgumentError,
      );
    });

    test('a fallback model with no adapter is refused', () {
      expect(
        () => features().register(const DVAIFeature(
            prompt: 'ticket.summary',
            fallback: <DVAIFallback>[DVAIFallback.model('opus')])),
        throwsArgumentError,
      );
    });

    test('a cache tag naming an input the prompt does not declare is refused',
        () {
      expect(
        () => features().register(const DVAIFeature(
            prompt: 'ticket.summary', cacheTags: <String>['customer:{customer}'])),
        throwsArgumentError,
      );
    });

    test('a manifest naming a model the policy forbids is DV-AIOPS-005', () {
      expect(
        () => features(
                policy: const DVAIContextPolicy(
                    forbiddenModels: <Type>{Invoice}))
            .register(const DVAIFeature(
                prompt: 'ticket.summary', context: <Type>[Ticket, Invoice])),
        throwsA(isA<DVAIOpsError>()
            .having((DVAIOpsError e) => e.code, 'code', 'DV-AIOPS-005')),
      );
    });

    test('a manifest reading a field the policy forbids is DV-AIOPS-005', () {
      expect(
        () => features(
                policy: const DVAIContextPolicy(forbiddenFields: <Type, Set<String>>{
          Customer: <String>{'email'},
        })).register(const DVAIFeature(
            prompt: 'ticket.summary', context: <Type>[Customer])),
        throwsA(isA<DVAIOpsError>()
            .having((DVAIOpsError e) => e.code, 'code', 'DV-AIOPS-005')),
      );
    });

    test('narrowing the manifest past a forbidden field is allowed', () {
      features(
              policy: const DVAIContextPolicy(forbiddenFields: <Type, Set<String>>{
        Customer: <String>{'email'},
      })).register(const DVAIFeature(
          prompt: 'ticket.summary',
          context: <Type>[Customer],
          contextFields: <Type, List<String>>{
            Customer: <String>['name'],
          }));
    });

    test('a manifest naming a sensitive field explicitly is DV-AIOPS-005', () {
      expect(
        () => features().register(const DVAIFeature(
            prompt: 'ticket.summary',
            context: <Type>[Customer],
            contextFields: <Type, List<String>>{
              Customer: <String>['name', 'ssn'],
            })),
        throwsA(isA<DVAIOpsError>()
            .having((DVAIOpsError e) => e.code, 'code', 'DV-AIOPS-005')),
      );
    });
  });

  group('the input is typed', () {
    test('a missing declared input is refused before any call', () async {
      final DVAIFeatures f = features()
        ..register(const DVAIFeature(prompt: 'ticket.summary'));
      await expectLater(
        f.run('ticket.summary',
            input: const <String, Object?>{'id': '42', 'body': 'x'}),
        throwsArgumentError,
      );
      expect(sonnet.prompts, isEmpty);
    });

    test('an undeclared input is refused', () async {
      final DVAIFeatures f = features()
        ..register(const DVAIFeature(prompt: 'ticket.summary'));
      await expectLater(
        f.run('ticket.summary',
            input: <String, Object?>{...ticket42, 'password': 'x'}),
        throwsArgumentError,
      );
      expect(sonnet.prompts, isEmpty);
    });

    test('an input of the wrong type is refused', () async {
      final DVAIFeatures f = features()
        ..register(const DVAIFeature(prompt: 'ticket.summary'));
      await expectLater(
        f.run('ticket.summary',
            input: <String, Object?>{...ticket42, 'status': 3}),
        throwsArgumentError,
      );
    });
  });

  group('budgets', () {
    late DVMeters meters;

    setUp(() {
      meters = DVMeters(store: DVMemoryMeterStore(), clock: () => now);
    });

    test('the budget is checked before the provider is called', () async {
      final DVMeterDefinition meter = tokens(limit: 1000);
      await const DVTenants().withTenant('acme', () async {
        await meters.record(meter, 990, idempotencyKey: 'earlier');
        final DVAIFeatures f = features(meters: meters, meter: meter)
          ..register(const DVAIFeature(
              prompt: 'ticket.summary',
              budget: DVMeterRef.tenant('aiTokens'),
              maxOutputTokens: 50));
        final DVAIFeatureResult result = await f.run('ticket.summary',
            input: ticket42, idempotencyKey: 'req-1');

        expect(result, isA<DVAIRefused>());
        expect((result as DVAIRefused).meter, 'aiTokens');
        expect(sonnet.prompts, isEmpty,
            reason: 'a refused budget must not have spent anything');
        expect(await meters.usage(meter, tenant: 'acme'), 990);
      });
      expect(codes(), contains('DV-AIOPS-002'));
    });

    test('the default at exhaustion is to refuse, not a cheaper model',
        () async {
      final DVMeterDefinition meter = tokens(limit: 10);
      await const DVTenants().withTenant('acme', () async {
        final DVAIFeatures f = features(meters: meters, meter: meter)
          ..register(const DVAIFeature(
              prompt: 'ticket.summary', budget: DVMeterRef.tenant('aiTokens')));
        final DVAIFeatureResult result = await f.run('ticket.summary',
            input: ticket42, idempotencyKey: 'req-1');
        expect(result, isA<DVAIRefused>());
      });
      expect(sonnet.prompts, isEmpty);
      expect(haiku.prompts, isEmpty);
    });

    test('a fallback model cannot escape the budget it shares', () async {
      final DVMeterDefinition meter = tokens(limit: 10);
      await const DVTenants().withTenant('acme', () async {
        final DVAIFeatures f = features(meters: meters, meter: meter)
          ..register(const DVAIFeature(
              prompt: 'ticket.summary',
              budget: DVMeterRef.tenant('aiTokens'),
              fallback: <DVAIFallback>[DVAIFallback.model('haiku')]));
        final DVAIFeatureResult result = await f.run('ticket.summary',
            input: ticket42, idempotencyKey: 'req-1');
        expect(result, isA<DVAIRefused>());
        expect(result.steps.map((DVAIFallbackStep s) => s.to), <String>['haiku']);
      });
      expect(sonnet.prompts, isEmpty);
      expect(haiku.prompts, isEmpty);
    });

    test('a degrade step at exhaustion is a typed state, and reported',
        () async {
      final DVMeterDefinition meter = tokens(limit: 10);
      await const DVTenants().withTenant('acme', () async {
        final DVAIFeatures f = features(meters: meters, meter: meter)
          ..register(const DVAIFeature(
              prompt: 'ticket.summary',
              budget: DVMeterRef.tenant('aiTokens'),
              fallback: <DVAIFallback>[DVAIFallback.degrade]));
        final DVAIFeatureResult result = await f.run('ticket.summary',
            input: ticket42, idempotencyKey: 'req-1');
        expect(result, isA<DVAIDegraded>());
        expect((result as DVAIDegraded).reason, DVAIFallbackReason.budget);
      });
      expect(sonnet.prompts, isEmpty);
      expect(codes(), containsAll(<String>['DV-AIOPS-002', 'DV-AIOPS-003']));
    });

    test('usage is recorded after the call, once per idempotency key',
        () async {
      final DVMeterDefinition meter = tokens();
      await const DVTenants().withTenant('acme', () async {
        final DVAIFeatures f = features(meters: meters, meter: meter)
          ..register(const DVAIFeature(
              prompt: 'ticket.summary', budget: DVMeterRef.tenant('aiTokens')));
        final DVAIAnswered first = await f.run('ticket.summary',
            input: ticket42, idempotencyKey: 'req-1') as DVAIAnswered;
        final num used = await meters.usage(meter, tenant: 'acme');
        expect(
          used,
          DVAIFeatures.estimateTokens(sonnet.prompts.single) +
              DVAIFeatures.estimateTokens(
                  jsonEncode(DVJsonCodec.toJson(first.output))),
        );

        // The same request retried: the provider runs again (nothing is
        // cached here), and the meter still counts it once.
        await f.run('ticket.summary',
            input: ticket42, idempotencyKey: 'req-1', bypassCache: true);
        expect(sonnet.prompts, hasLength(2));
        expect(await meters.usage(meter, tenant: 'acme'), used);
      });
    });

    test('a budgeted feature with no idempotency key is refused before the call',
        () async {
      final DVMeterDefinition meter = tokens();
      final DVAIFeatures f = features(meters: meters, meter: meter)
        ..register(const DVAIFeature(
            prompt: 'ticket.summary', budget: DVMeterRef.tenant('aiTokens')));
      await expectLater(
          f.run('ticket.summary', input: ticket42), throwsStateError);
      expect(sonnet.prompts, isEmpty);
    });

    test('a budget over its limit under throttle proceeds and says so',
        () async {
      final DVMeterDefinition meter = tokens(limit: 10, atLimit: DVQuota.throttle);
      await const DVTenants().withTenant('acme', () async {
        final DVAIFeatures f = features(meters: meters, meter: meter)
          ..register(const DVAIFeature(
              prompt: 'ticket.summary', budget: DVMeterRef.tenant('aiTokens')));
        final DVAIFeatureResult result = await f.run('ticket.summary',
            input: ticket42, idempotencyKey: 'req-1');
        expect(result, isA<DVAIAnswered>());
      });
      final DVLogRecord over =
          sink.records.firstWhere((DVLogRecord r) => r.code == 'DV-AIOPS-002');
      expect(over.context['behaviour'], 'throttle');
    });
  });

  group('fallback on provider failure', () {
    test('a declared model step answers, and the step is reported', () async {
      sonnet.fail = const DVAIProviderException('anthropic', 'overloaded',
          statusCode: 529);
      final DVAIFeatures f = features()
        ..register(const DVAIFeature(
            prompt: 'ticket.summary',
            fallback: <DVAIFallback>[DVAIFallback.model('haiku')]));
      final DVAIFeatureResult result =
          await f.run('ticket.summary', input: ticket42);

      expect(result, isA<DVAIAnswered>());
      final DVAIAnswered answered = result as DVAIAnswered;
      expect(answered.run.model, 'haiku');
      expect(answered.steps.single.from, 'sonnet');
      expect(answered.steps.single.to, 'haiku');
      expect(answered.steps.single.reason, DVAIFallbackReason.providerFailure);
      expect(answered.run.steps, hasLength(1),
          reason: 'the run record must carry that it was not the primary');
      final DVLogRecord step =
          sink.records.firstWhere((DVLogRecord r) => r.code == 'DV-AIOPS-003');
      expect(step.level, DVLogLevel.info);
    });

    test('with no fallback declared the feature is unavailable, DV-AIOPS-004',
        () async {
      sonnet.fail = const DVAIProviderException('anthropic', 'overloaded');
      final DVAIFeatures f = features()
        ..register(const DVAIFeature(prompt: 'ticket.summary'));
      final DVAIFeatureResult result =
          await f.run('ticket.summary', input: ticket42);
      expect(result, isA<DVAIUnavailable>());
      final DVLogRecord down =
          sink.records.firstWhere((DVLogRecord r) => r.code == 'DV-AIOPS-004');
      expect(down.level, DVLogLevel.error);
      expect(codes(), isNot(contains('DV-AIOPS-003')));
    });

    test('a chain whose every model fails is unavailable too', () async {
      sonnet.fail = const DVAIProviderException('anthropic', 'overloaded');
      haiku.fail = const DVAIProviderException('anthropic', 'overloaded');
      final DVAIFeatures f = features()
        ..register(const DVAIFeature(
            prompt: 'ticket.summary',
            fallback: <DVAIFallback>[DVAIFallback.model('haiku')]));
      final DVAIFeatureResult result =
          await f.run('ticket.summary', input: ticket42);
      expect(result, isA<DVAIUnavailable>());
      expect(codes(), containsAll(<String>['DV-AIOPS-003', 'DV-AIOPS-004']));
    });

    test('a programming error is not an outage and is not fallen back from',
        () async {
      sonnet.error = StateError('adapter misconfigured');
      final DVAIFeatures f = features()
        ..register(const DVAIFeature(
            prompt: 'ticket.summary',
            fallback: <DVAIFallback>[DVAIFallback.model('haiku')]));
      await expectLater(
          f.run('ticket.summary', input: ticket42), throwsStateError);
      expect(haiku.prompts, isEmpty);
    });
  });

  group('caching', () {
    test('the same resolved input is answered once', () async {
      final DVAIFeatures f = features(cache: DVMemoryCacheAdapter())
        ..register(const DVAIFeature(
            prompt: 'ticket.summary', cacheTags: <String>['ticket:{id}']));
      await f.run('ticket.summary', input: ticket42);
      final DVAIAnswered second =
          await f.run('ticket.summary', input: ticket42) as DVAIAnswered;
      expect(sonnet.prompts, hasLength(1));
      expect(second.run.fromCache, isTrue);
      expect(second.run.promptVersion, 4);
    });

    test('shipping a new prompt version does not serve the old answers',
        () async {
      final DVAIFeatures f = features(cache: DVMemoryCacheAdapter())
        ..register(const DVAIFeature(prompt: 'ticket.summary'));
      await f.run('ticket.summary', input: ticket42);
      await prompts.ship(DVPromptVersion(
        id: 'ticket.summary',
        version: 5,
        system: 'Summarize the ticket in one line.',
        input: const <String, String>{
          'id': 'String',
          'body': 'String',
          'status': 'String',
        },
        schema: const <String, DVJsonValue>{'summary': DVJsonString('string')},
      ));
      final DVAIAnswered after =
          await f.run('ticket.summary', input: ticket42) as DVAIAnswered;
      expect(after.run.fromCache, isFalse);
      expect(after.run.promptVersion, 5);
      expect(after.run.promptSource, DVPromptSource.stored);
      expect(sonnet.prompts, hasLength(2));
      expect(sonnet.prompts.last, contains('in one line'));
    });

    test('a new version with the same wording still does not serve the old '
        'version\'s answers', () async {
      // Nothing in the prompt text moved, so a key built from the text alone
      // would hit. The answer would then be recorded against version 5 while
      // version 4 produced it.
      final DVAIFeatures f = features(cache: DVMemoryCacheAdapter())
        ..register(const DVAIFeature(prompt: 'ticket.summary'));
      await f.run('ticket.summary', input: ticket42);
      await prompts.ship(DVPromptVersion(
        id: 'ticket.summary',
        version: 5,
        system: summaryTemplate.system,
        input: const <String, String>{
          'id': 'String',
          'body': 'String',
          'status': 'String',
        },
        schema: const <String, DVJsonValue>{'summary': DVJsonString('string')},
      ));
      final DVAIAnswered after =
          await f.run('ticket.summary', input: ticket42) as DVAIAnswered;
      expect(after.run.promptVersion, 5);
      expect(after.run.fromCache, isFalse);
      expect(sonnet.prompts, hasLength(2));
    });

    test('revalidating a tag drops what it made stale', () async {
      final DVAIFeatures f = features(cache: DVMemoryCacheAdapter())
        ..register(const DVAIFeature(
            prompt: 'ticket.summary', cacheTags: <String>['ticket:{id}']));
      await f.run('ticket.summary', input: ticket42);
      const DVCacheTags().revalidateTag('ticket:42');
      final DVAIAnswered after =
          await f.run('ticket.summary', input: ticket42) as DVAIAnswered;
      expect(after.run.fromCache, isFalse);
      expect(sonnet.prompts, hasLength(2));
    });

    test('another ticket\'s tag leaves this answer cached', () async {
      final DVAIFeatures f = features(cache: DVMemoryCacheAdapter())
        ..register(const DVAIFeature(
            prompt: 'ticket.summary', cacheTags: <String>['ticket:{id}']));
      await f.run('ticket.summary', input: ticket42);
      const DVCacheTags().revalidateTag('ticket:43');
      await f.run('ticket.summary', input: ticket42);
      expect(sonnet.prompts, hasLength(1));
    });

    test('one tenant is never answered from another tenant\'s cache',
        () async {
      final DVAIFeatures f = features(cache: DVMemoryCacheAdapter())
        ..register(const DVAIFeature(prompt: 'ticket.summary'));
      await const DVTenants()
          .withTenant('acme', () => f.run('ticket.summary', input: ticket42));
      await const DVTenants()
          .withTenant('globex', () => f.run('ticket.summary', input: ticket42));
      expect(sonnet.prompts, hasLength(2));
    });

    test('a fallback model\'s cached answer is not served as the primary\'s',
        () async {
      final DVAIFeatures f = features(cache: DVMemoryCacheAdapter())
        ..register(const DVAIFeature(
            prompt: 'ticket.summary',
            fallback: <DVAIFallback>[DVAIFallback.model('haiku')]));
      sonnet.fail = const DVAIProviderException('anthropic', 'overloaded');
      await f.run('ticket.summary', input: ticket42);
      sonnet.fail = null;
      final DVAIAnswered recovered =
          await f.run('ticket.summary', input: ticket42) as DVAIAnswered;
      expect(recovered.run.model, 'sonnet');
      expect(recovered.run.fromCache, isFalse);
    });
  });

  group('what a feature is allowed to see', () {
    test('a model outside the manifest cannot be added', () {
      final DVAIFeatures f = features()
        ..register(const DVAIFeature(
            prompt: 'ticket.summary', context: <Type>[Ticket]));
      expect(
        () => f.contextFor('ticket.summary').add(Customer,
            const <String, Object?>{'name': 'Ada'}),
        throwsA(isA<DVAIOpsError>()
            .having((DVAIOpsError e) => e.code, 'code', 'DV-AIOPS-005')),
      );
    });

    test('a context built for one feature cannot be used by another', () async {
      prompts.register(
          const DVPrompt(id: 'ticket.reply', version: 1), summaryTemplate);
      final DVAIFeatures f = features()
        ..register(const DVAIFeature(
            prompt: 'ticket.summary', context: <Type>[Customer]))
        ..register(const DVAIFeature(prompt: 'ticket.reply'));
      final DVAIContext wide = f.contextFor('ticket.summary')
        ..add(Customer, const <String, Object?>{'name': 'Ada'});
      await expectLater(
        f.run('ticket.reply', input: ticket42, context: wide),
        throwsA(isA<DVAIOpsError>()
            .having((DVAIOpsError e) => e.code, 'code', 'DV-AIOPS-005')),
      );
      expect(sonnet.prompts, isEmpty);
    });

    test('a sensitive field is described, never valued', () async {
      final DVAIFeatures f = features()
        ..register(const DVAIFeature(
            prompt: 'ticket.summary', context: <Type>[Ticket, Customer]));
      final DVAIContext context = f.contextFor('ticket.summary')
        ..add(Customer, const <String, Object?>{
          'name': 'Ada Lovelace',
          'email': 'ada@example.com',
          'ssn': '078-05-1120',
          'internalNote': 'owes us money',
        });
      await f.run('ticket.summary', input: ticket42, context: context);

      final String prompt = sonnet.prompts.single;
      expect(prompt, contains('Ada Lovelace'));
      expect(prompt, isNot(contains('078-05-1120')));
      expect(prompt, contains('ssn'),
          reason: 'the field is described, so the model knows it exists');
      expect(prompt, isNot(contains('owes us money')),
          reason: 'a field the model descriptor does not declare is not read');
    });

    test('a narrowed manifest reads only the fields it names', () async {
      final DVAIFeatures f = features()
        ..register(const DVAIFeature(
            prompt: 'ticket.summary',
            context: <Type>[Customer],
            contextFields: <Type, List<String>>{
              Customer: <String>['name'],
            }));
      final DVAIContext context = f.contextFor('ticket.summary')
        ..add(Customer, const <String, Object?>{
          'name': 'Ada Lovelace',
          'email': 'ada@example.com',
        });
      await f.run('ticket.summary', input: ticket42, context: context);
      expect(sonnet.prompts.single, isNot(contains('ada@example.com')));
    });

    test('retrieved rows pass the same exclusion', () async {
      final DVAIFeatures f = features()
        ..register(const DVAIFeature(
            prompt: 'ticket.summary', context: <Type>[Customer]));
      // An index that did not know ssn was sensitive handed it over.
      const DVSemanticRetrieval<Object?> retrieval = DVSemanticRetrieval<Object?>(
        hits: <DVSemanticHit<Object?>>[],
        rows: <Map<String, Object?>>[
          <String, Object?>{'name': 'Grace Hopper', 'ssn': '219-09-9999'},
        ],
      );
      final DVAIContext context = f.contextFor('ticket.summary')
        ..addRetrieval(Customer, retrieval);
      await f.run('ticket.summary', input: ticket42, context: context);
      expect(sonnet.prompts.single, contains('Grace Hopper'));
      expect(sonnet.prompts.single, isNot(contains('219-09-9999')));
    });

    test('a resolved secret in an input never reaches the provider', () async {
      DVSecrets.configure(<String, String>{'STRIPE_KEY': 'sk_live_4eC39HqLyjW'});
      const DVSecrets().get('STRIPE_KEY');
      final DVAIFeatures f = features()
        ..register(const DVAIFeature(prompt: 'ticket.summary'));
      await f.run('ticket.summary', input: <String, Object?>{
        ...ticket42,
        'body': 'I pasted my key sk_live_4eC39HqLyjW, is that bad?',
      });
      expect(sonnet.prompts.single, isNot(contains('sk_live_4eC39HqLyjW')));
    });

    test('neither a trace nor a log carries a sensitive value or the prompt',
        () async {
      sonnet.fail = const DVAIProviderException('anthropic', 'rejected',
          responseBody: 'echo: 078-05-1120');
      final DVAIFeatures f = features()
        ..register(const DVAIFeature(
            prompt: 'ticket.summary',
            context: <Type>[Customer],
            fallback: <DVAIFallback>[DVAIFallback.model('haiku')]));
      final DVAIContext context = f.contextFor('ticket.summary')
        ..add(Customer, const <String, Object?>{
          'name': 'Ada Lovelace',
          'ssn': '078-05-1120',
        });
      await f.run('ticket.summary', input: ticket42, context: context);

      expect(spans.spans, isNotEmpty);
      final String traced = jsonEncode(<Object?>[
        for (final DVSpan span in spans.spans) span.toJson(),
      ]);
      expect(traced, contains('ticket.summary'));
      expect(traced, isNot(contains('078-05-1120')));
      expect(traced, isNot(contains('Ada Lovelace')));
      expect(traced, isNot(contains('The delivery is late again.')));

      final String logged = sink.records
          .map((DVLogRecord r) => r.toJsonLine())
          .join('\n');
      expect(logged, isNot(contains('078-05-1120')));
      expect(logged, isNot(contains('Ada Lovelace')));
    });
  });

  group('an outage report', () {
    test('carries the error type and status, never the provider\'s body',
        () async {
      // Providers quote the request back in their error bodies.
      sonnet.fail = const DVAIProviderException('anthropic', 'rejected',
          statusCode: 400,
          responseBody: 'bad request: The delivery is late again. 078-05-1120');
      final DVAIFeatures f = features()
        ..register(const DVAIFeature(
            prompt: 'ticket.summary', context: <Type>[Customer]));
      final DVAIContext context = f.contextFor('ticket.summary')
        ..add(Customer, const <String, Object?>{'name': 'Ada Lovelace'});
      final DVAIFeatureResult result =
          await f.run('ticket.summary', input: ticket42, context: context);
      expect(result, isA<DVAIUnavailable>());

      final DVLogRecord down =
          sink.records.firstWhere((DVLogRecord r) => r.code == 'DV-AIOPS-004');
      expect(down.context['errorType'], 'DVAIProviderException');
      expect(down.context['status'], 400);
      final String logged =
          sink.records.map((DVLogRecord r) => r.toJsonLine()).join('\n');
      expect(logged, isNot(contains('The delivery is late again.')));
      expect(logged, isNot(contains('078-05-1120')));

      final String traced = jsonEncode(<Object?>[
        for (final DVSpan span in spans.spans) span.toJson(),
      ]);
      expect(traced, contains('DVAIProviderException'));
      expect(traced, isNot(contains('The delivery is late again.')));
    });
  });

  group('outputs are recorded against what produced them', () {
    test('an answer carries the prompt version, fingerprint and model',
        () async {
      final DVAIFeatures f = features()
        ..register(const DVAIFeature(prompt: 'ticket.summary'));
      final DVAIAnswered answered =
          await f.run('ticket.summary', input: ticket42) as DVAIAnswered;
      final DVPromptVersion compiled =
          DVPromptVersion.compiled(summaryPrompt, summaryTemplate);

      expect(answered.run.feature, 'ticket.summary');
      expect(answered.run.promptVersion, 4);
      expect(answered.run.promptFingerprint, compiled.fingerprint);
      expect(answered.run.promptSource, DVPromptSource.compiled);
      expect(answered.run.model, 'sonnet');
      expect(answered.run.at, now);
      expect(runs.records.single.inputHash, answered.run.inputHash);
      expect(answered.run.outputHash, isNotEmpty);
    });

    test('the span names the version that answered', () async {
      final DVAIFeatures f = features()
        ..register(const DVAIFeature(prompt: 'ticket.summary'));
      await f.run('ticket.summary', input: ticket42);
      final DVSpan span = spans.spans.single;
      expect(span.attributes['ai.feature'], 'ticket.summary');
      expect(span.attributes['ai.prompt.version'], '4');
      expect(span.attributes['ai.model'], 'sonnet');
    });

    test('every refusal, degrade and outage is recorded too', () async {
      sonnet.fail = const DVAIProviderException('anthropic', 'overloaded');
      final DVAIFeatures f = features()
        ..register(const DVAIFeature(
            prompt: 'ticket.summary',
            fallback: <DVAIFallback>[DVAIFallback.degrade]));
      await f.run('ticket.summary', input: ticket42);
      expect(runs.records.single.outcome, 'degraded');
      expect(runs.records.single.promptVersion, 4);
    });
  });
}
