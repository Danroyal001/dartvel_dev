// Semantic search over the application's own records.
//
// Every test here is about a result that looks like a result and is not. A
// vector query returns the k nearest, so a tenant filter applied afterwards
// does not narrow a page, it empties or leaks one. Two embedders' vectors in
// one index are not a worse index, they are noise with scores attached. A
// rebuild that answers from half-written vectors returns confident nonsense
// for hours. An embedding job that failed quietly leaves a record that is
// simply never found, and nobody can report what they never see.
import 'dart:async';
import 'dart:math' as math;

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class Ticket {
  Ticket(this.id, this.body, {this.tenant = 'acme', this.status = 'open',
      this.secret = ''});

  final String id;
  final String body;
  final String tenant;
  final String status;
  final String secret;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'body': body,
        'tenant': tenant,
        'status': status,
        'secret': secret,
      };
}

/// A deterministic embedder over a fixed vocabulary.
///
/// [rotate] permutes which dimension each word lands in, so two instances
/// with different rotations are two different "models": a query embedded by
/// one and compared against vectors written by the other scores at random,
/// which is exactly the corruption the generation rule exists to prevent.
class WordEmbedder implements DVEmbedder {
  WordEmbedder(this.id, {this.rotate = 0, this.failOn});

  static const List<String> vocabulary = <String>[
    'late', 'delivery', 'unhappy', 'refund', 'happy', 'invoice', 'password',
    'login', 'shipping', 'broken', 'thanks', 'price',
  ];

  @override
  final String id;

  @override
  int get dimensions => vocabulary.length;

  final int rotate;

  /// Text containing this word makes [embed] throw.
  final String? failOn;

  int calls = 0;

  @override
  Future<List<double>> embed(String text) async {
    calls++;
    final String lower = text.toLowerCase();
    if (failOn != null && lower.contains(failOn!)) {
      throw StateError('embedder refused "$failOn"');
    }
    final List<double> v = List<double>.filled(dimensions, 0);
    for (int i = 0; i < vocabulary.length; i++) {
      if (lower.contains(vocabulary[i])) {
        v[(i + rotate) % dimensions] += 1;
      }
    }
    return v;
  }
}

/// An adapter that claims to filter and does not: the failure mode a
/// defence-in-depth check exists for.
class LeakyVectorAdapter extends DVInMemoryVectorAdapter {
  @override
  Future<List<DVVectorMatch>> nearest(String index, List<double> vector,
          {required int k, DVVectorFilter? filter}) =>
      super.nearest(index, vector, k: k);
}

void main() {
  late Map<String, Ticket> store;
  late DVInMemoryVectorAdapter vectors;
  late WordEmbedder embedder;
  const DVQueues queues = DVQueues();

  DVSemanticIndex<Ticket> index({
    DVEmbedder? using,
    DVVectorAdapter? adapter,
    bool scoped = true,
    FutureOr<bool> Function(Ticket)? canSee,
    DVSearchProvider<Ticket, Object?>? keyword,
    List<DVEmbedder> previous = const <DVEmbedder>[],
    DVChunking chunking = const DVChunking(maxCharacters: 60, overlap: 0),
    Set<String> sensitive = const <String>{'secret'},
    int refillMultiple = 4,
    DVSemanticMetering? metering,
    bool noEmbedder = false,
  }) =>
      DVSemanticIndex<Ticket>(
        name: 'tickets',
        embedder: noEmbedder ? null : (using ?? embedder),
        vectors: adapter ?? vectors,
        idOf: (Ticket t) => t.id,
        fields: <String, String Function(Ticket)>{
          'body': (Ticket t) => t.body,
        },
        load: (String id) async => store[id],
        tenantOf: scoped ? (Ticket t) => t.tenant : null,
        attributesOf: (Ticket t) => <String, String>{'status': t.status},
        canSee: canSee,
        keyword: keyword,
        previousEmbedders: previous,
        chunking: chunking,
        sensitiveFields: sensitive,
        toJson: (Ticket t) => t.toJson(),
        refillMultiple: refillMultiple,
        metering: metering,
      );

  Future<void> save(DVSemanticIndex<Ticket> idx, Ticket t) async {
    store[t.id] = t;
    await idx.indexed(t);
  }

  Future<void> drain() async {
    while (await queues.work(queue: 'semantic', maxJobs: 50) > 0) {}
  }

  setUp(() {
    store = <String, Ticket>{};
    vectors = DVInMemoryVectorAdapter();
    embedder = WordEmbedder('test/words-v1');
    queues.useAdapter(DVInMemoryQueueAdapter());
    DVSemanticIndex.resetRegistry();
    // The helper's index is tenant-scoped and every ticket defaults to acme.
    const DVTenants().currentTenant = 'acme';
    DVObservability.resetLogging();
  });

  tearDown(() {
    DVTenants.reset();
    DVObservability.resetLogging();
  });

  List<String> loggedCodes() => <String>[
        for (final DVLogRecord r in DVObservability.recentLogs)
          if (r.code != null) r.code!,
      ];

  group('declaration', () {
    test('semantic search with no embedder is refused, not defaulted', () {
      expect(
        () => index(noEmbedder: true),
        throwsA(isA<DVSemanticConfigError>()
            .having((DVSemanticConfigError e) => e.code, 'code',
                'DV-SEMANTIC-001')),
      );
    });

    test('a scoped model on an adapter that cannot filter is refused', () {
      expect(
        () => index(adapter: DVInMemoryVectorAdapter(canFilter: false)),
        throwsA(isA<DVSemanticConfigError>()
            .having((DVSemanticConfigError e) => e.code, 'code',
                'DV-SEMANTIC-002')),
      );
    });

    test('a policy-scoped model on an adapter that cannot filter is refused',
        () {
      expect(
        () => index(
            scoped: false,
            canSee: (Ticket t) => t.status == 'open',
            adapter: DVInMemoryVectorAdapter(canFilter: false)),
        throwsA(isA<DVSemanticConfigError>()
            .having((DVSemanticConfigError e) => e.code, 'code',
                'DV-SEMANTIC-002')),
      );
    });

    test('an unscoped model may use an adapter that cannot filter', () {
      expect(
        () => index(
            scoped: false,
            adapter: DVInMemoryVectorAdapter(canFilter: false)),
        returnsNormally,
      );
    });

    test('a sensitive field cannot be a semantic field', () {
      expect(
        () => index(sensitive: const <String>{'body'}),
        throwsArgumentError,
      );
    });
  });

  group('the write path', () {
    test('a write enqueues a job and embeds nothing inline', () async {
      final DVSemanticIndex<Ticket> idx = index();
      await save(idx, Ticket('t1', 'late delivery, customer unhappy'));

      expect(embedder.calls, 0,
          reason: 'a model save that waits on an embedder is a timeout '
              'during somebody else\'s outage');
      expect(await queues.pending('semantic'), hasLength(1));

      await drain();
      final DVSemanticPage<Ticket> page =
          await idx.query('unhappy delivery', mode: DVSearchMode.semantic);
      expect(page.items.map((Ticket t) => t.id), <String>['t1']);
    });

    test('a record whose embedding job dead-letters is reported absent',
        () async {
      final DVSemanticIndex<Ticket> idx =
          index(using: WordEmbedder('test/words-v1', failOn: 'broken'));
      await save(idx, Ticket('bad', 'broken login'));
      await save(idx, Ticket('good', 'late delivery'));
      await drain();

      final List<String> absent = await idx.absentRecords();
      expect(absent, <String>['bad'],
          reason: 'a record never embedded is never found, and nobody can '
              'report a search result they never saw');
      expect(loggedCodes(), contains('DV-SEMANTIC-004'));
    });

    test('a removed record leaves the index', () async {
      final DVSemanticIndex<Ticket> idx = index();
      await save(idx, Ticket('t1', 'late delivery'));
      await drain();
      store.remove('t1');
      await idx.removed('t1');
      await drain();

      final DVSemanticPage<Ticket> page =
          await idx.query('late delivery', mode: DVSearchMode.semantic);
      expect(page.items, isEmpty);
    });
  });

  group('chunking', () {
    test('a match in a later chunk returns the record once, with that chunk',
        () async {
      final DVSemanticIndex<Ticket> idx = index();
      // 99 characters: [0,56) is filler, [56,99) holds both query words.
      final String body = '${'thanks happy price ' * 4}then refund invoice';
      await save(idx, Ticket('long', body));
      await drain();

      final DVSemanticPage<Ticket> page =
          await idx.query('refund invoice', mode: DVSearchMode.semantic);
      expect(page.hits, hasLength(1),
          reason: 'a search that returns the same ticket once per chunk is '
              'a search nobody uses twice');
      final DVSemanticHit<Ticket> hit = page.hits.single;
      expect(hit.chunk, isNotNull);
      expect(hit.chunk!.offset, greaterThan(0));
      expect(hit.chunk!.text, contains('refund'));
      expect(hit.field, 'body');
    });
  });

  group('tenant scope', () {
    test('a semantic result never comes from another tenant', () async {
      final DVSemanticIndex<Ticket> idx = index();
      await save(idx, Ticket('acme-1', 'late delivery', tenant: 'acme'));
      await save(idx, Ticket('globex-1', 'late delivery unhappy',
          tenant: 'globex'));
      await drain();

      final DVSemanticPage<Ticket> page = await const DVTenants().withTenant(
          'acme',
          () => idx.query('late delivery unhappy',
              mode: DVSearchMode.semantic));
      expect(page.items.map((Ticket t) => t.id), <String>['acme-1']);
    });

    test('an adapter that ignores the filter still cannot leak a tenant',
        () async {
      final LeakyVectorAdapter leaky = LeakyVectorAdapter();
      final DVSemanticIndex<Ticket> idx = index(adapter: leaky);
      await save(idx, Ticket('acme-1', 'price', tenant: 'acme'));
      await save(idx, Ticket('globex-1', 'late delivery unhappy',
          tenant: 'globex'));
      await drain();

      final DVSemanticPage<Ticket> page = await const DVTenants().withTenant(
          'acme',
          () => idx.query('late delivery unhappy',
              mode: DVSearchMode.semantic));
      expect(page.items.map((Ticket t) => t.id), isNot(contains('globex-1')),
          reason: 'the same rule decides every row, whatever the adapter '
              'claimed to push down');
    });
  });

  group('post-filtering with refill', () {
    test('a policy that hides the nearest rows still fills the page',
        () async {
      final DVSemanticIndex<Ticket> idx =
          index(canSee: (Ticket t) => !t.id.startsWith('hidden'));
      for (int i = 0; i < 6; i++) {
        await save(idx, Ticket('hidden-$i', 'late delivery unhappy refund'));
      }
      for (int i = 0; i < 3; i++) {
        await save(idx, Ticket('visible-$i', 'late delivery'));
      }
      await drain();

      final DVSemanticPage<Ticket> page = await idx.query(
          'late delivery unhappy refund',
          mode: DVSearchMode.semantic,
          limit: 3);
      expect(page.items.map((Ticket t) => t.id),
          unorderedEquals(<String>['visible-0', 'visible-1', 'visible-2']),
          reason: 'ask for three, have the nearest six hidden, and a filter '
              'applied once shows nothing while the data is there');
      expect(page.bounded, isFalse);
    });

    test('hitting the refill bound says so rather than looking complete',
        () async {
      final DVSemanticIndex<Ticket> idx = index(
          canSee: (Ticket t) => !t.id.startsWith('hidden'), refillMultiple: 2);
      for (int i = 0; i < 12; i++) {
        await save(idx, Ticket('hidden-$i', 'late delivery unhappy refund'));
      }
      await save(idx, Ticket('visible-0', 'late delivery'));
      await drain();

      final DVSemanticPage<Ticket> page = await idx.query(
          'late delivery unhappy refund',
          mode: DVSearchMode.semantic,
          limit: 3);
      expect(page.items.length, lessThan(3));
      expect(page.bounded, isTrue);
      expect(loggedCodes(), contains('DV-SEMANTIC-005'));
    });

    test('an exhausted index with fewer rows is not reported as bounded',
        () async {
      final DVSemanticIndex<Ticket> idx = index();
      await save(idx, Ticket('only', 'late delivery'));
      await drain();

      final DVSemanticPage<Ticket> page = await idx.query('late delivery',
          mode: DVSearchMode.semantic, limit: 5);
      expect(page.items, hasLength(1));
      expect(page.bounded, isFalse);
    });

    test('an expressible predicate is pushed into the query', () async {
      final DVSemanticIndex<Ticket> idx = index();
      for (int i = 0; i < 8; i++) {
        await save(idx, Ticket('closed-$i', 'late delivery unhappy',
            status: 'closed'));
      }
      await save(idx, Ticket('open-0', 'late delivery', status: 'open'));
      await drain();

      final DVSemanticPage<Ticket> page = await idx.query(
          'late delivery unhappy',
          mode: DVSearchMode.semantic,
          limit: 1,
          where: const <String, String>{'status': 'open'});
      expect(page.items.map((Ticket t) => t.id), <String>['open-0']);
      expect(page.bounded, isFalse);
    });
  });

  group('the embedder is pinned', () {
    test('a new embedder builds a second index and queries keep the old one',
        () async {
      final WordEmbedder v1 = WordEmbedder('test/words-v1');
      final DVSemanticIndex<Ticket> first = index(using: v1);
      await save(first, Ticket('t1', 'late delivery'));
      await save(first, Ticket('t2', 'password login'));
      await drain();

      // A different model: same dimensions, different meaning per dimension.
      DVSemanticIndex.resetRegistry();
      final WordEmbedder v2 = WordEmbedder('test/words-v2', rotate: 5);
      final DVSemanticIndex<Ticket> second =
          index(using: v2, previous: <DVEmbedder>[v1]);

      // Half a backfill: only t2 in the new generation.
      await second.backfill(<Ticket>[store['t2']!]);
      expect(loggedCodes(), contains('DV-SEMANTIC-003'));

      final DVSemanticPage<Ticket> mid =
          await second.query('late delivery', mode: DVSearchMode.semantic);
      expect(mid.items.map((Ticket t) => t.id).first, 't1',
          reason: 'mid-rebuild answers come from the complete old index, '
              'embedded with the old model');
      expect(mid.generation, contains('test/words-v1'));

      await second.backfill(<Ticket>[store['t1']!, store['t2']!],
          complete: true);
      final DVSemanticPage<Ticket> after =
          await second.query('late delivery', mode: DVSearchMode.semantic);
      expect(after.generation, contains('test/words-v2'));
      expect(after.items.map((Ticket t) => t.id).first, 't1');
    });

    test('a record edited mid-rebuild is not stale in the new index',
        () async {
      final WordEmbedder v1 = WordEmbedder('test/words-v1');
      final DVSemanticIndex<Ticket> first = index(using: v1);
      await save(first, Ticket('t1', 'late delivery'));
      await save(first, Ticket('t2', 'password login'));
      await drain();

      DVSemanticIndex.resetRegistry();
      final DVSemanticIndex<Ticket> second = index(
          using: WordEmbedder('test/words-v2', rotate: 5),
          previous: <DVEmbedder>[v1]);
      // The backfill reaches t1 before it is edited, and will skip it later.
      await second.backfill(<Ticket>[store['t1']!]);
      await save(second, Ticket('t1', 'refund invoice'));
      await drain();

      final DVSemanticPage<Ticket> mid =
          await second.query('refund invoice', mode: DVSearchMode.semantic);
      expect(mid.hits.first.chunk!.text, contains('refund'),
          reason: 'the index still answering sees the edit');

      await second.backfill(<Ticket>[store['t1']!, store['t2']!],
          complete: true);
      final DVSemanticPage<Ticket> after =
          await second.query('refund invoice', mode: DVSearchMode.semantic);
      expect(after.generation, contains('test/words-v2'));
      expect(after.hits.first.record.id, 't1');
      expect(after.hits.first.chunk!.text, contains('refund'),
          reason: 'a write during the rebuild lands in the index being '
              'built, or the switch-over serves the vector from before it');
    });

    test('a rebuild with no way to embed for the old index refuses to query',
        () async {
      final DVSemanticIndex<Ticket> first =
          index(using: WordEmbedder('test/words-v1'));
      await save(first, Ticket('t1', 'late delivery'));
      await drain();

      DVSemanticIndex.resetRegistry();
      final DVSemanticIndex<Ticket> second =
          index(using: WordEmbedder('test/words-v2', rotate: 5));
      expect(
        () => second.query('late delivery', mode: DVSearchMode.semantic),
        throwsA(isA<DVSemanticRebuildError>()),
        reason: 'embedding the query with the new model and comparing it '
            'with the old vectors returns noise with scores',
      );
    });

    test('an index refuses vectors of a different length', () async {
      await vectors.upsert('x', <DVVectorEntry>[
        const DVVectorEntry(recordId: 'a', chunk: 0, offset: 0, text: 'a',
            vector: <double>[1, 0, 0]),
      ]);
      expect(
        () => vectors.upsert('x', <DVVectorEntry>[
          const DVVectorEntry(recordId: 'b', chunk: 0, offset: 0, text: 'b',
              vector: <double>[1, 0]),
        ]),
        throwsArgumentError,
      );
    });

    test('an AI adapter embedder checks the dimensions it was declared with',
        () async {
      final DVAIEmbedder wrapped = DVAIEmbedder(const LocalDVAIAdapter(),
          id: 'local/buckets', dimensions: 1536);
      expect(() => wrapped.embed('hello'),
          throwsA(isA<DVSemanticDimensionError>()));
      final DVAIEmbedder right = DVAIEmbedder(const LocalDVAIAdapter(),
          id: 'local/buckets', dimensions: 16);
      expect(await right.embed('hello'), hasLength(16));
    });

    test('a backfill that fails resumes where it stopped', () async {
      final WordEmbedder v1 = WordEmbedder('test/words-v1');
      final DVSemanticIndex<Ticket> first = index(using: v1);
      await save(first, Ticket('seed', 'thanks'));
      await drain();

      DVSemanticIndex.resetRegistry();
      final WordEmbedder flaky =
          WordEmbedder('test/words-v2', rotate: 3, failOn: 'broken');
      final DVSemanticIndex<Ticket> second =
          index(using: flaky, previous: <DVEmbedder>[v1]);
      final List<Ticket> corpus = <Ticket>[
        Ticket('a', 'late delivery'),
        Ticket('b', 'refund invoice'),
        Ticket('c', 'broken login'),
        Ticket('d', 'price'),
      ];
      for (final Ticket t in corpus) {
        store[t.id] = t;
      }
      await expectLater(second.backfill(corpus), throwsStateError);
      final int callsBefore = flaky.calls;

      final WordEmbedder fixed = WordEmbedder('test/words-v2', rotate: 3);
      DVSemanticIndex.resetRegistry();
      final DVSemanticIndex<Ticket> third =
          index(using: fixed, previous: <DVEmbedder>[v1]);
      final DVSemanticBackfill result =
          await third.backfill(corpus, complete: true);
      expect(result.processed, corpus.length);
      expect(fixed.calls, 2,
          reason: 'records already embedded before the failure are not '
              'embedded (and paid for) again');
      expect(callsBefore, 3);
    });
  });

  group('modes', () {
    DVInMemorySearchProvider<Ticket, Object?> keywordOver(
            Iterable<Ticket> tickets) =>
        DVInMemorySearchProvider<Ticket, Object?>(
          records: tickets.toList(),
          document: (Ticket t) => t.body,
        );

    test('keyword stays the default and embeds nothing', () async {
      final Ticket t = Ticket('k1', 'invoice price');
      final DVSemanticIndex<Ticket> idx =
          index(keyword: keywordOver(<Ticket>[t]));
      await save(idx, t);
      await drain();
      final int before = embedder.calls;

      final DVSemanticPage<Ticket> page = await idx.query('invoice');
      expect(page.items.map((Ticket x) => x.id), <String>['k1']);
      expect(embedder.calls, before,
          reason: 'an existing call must not change meaning or cost');
    });

    test('hybrid ranks a record both rankings found above either alone',
        () async {
      final List<Ticket> tickets = <Ticket>[
        Ticket('both', 'refund invoice late'),
        Ticket('semantic-only', 'unhappy refund delivery late'),
        Ticket('keyword-only', 'invoice number'),
      ];
      final DVSemanticIndex<Ticket> idx = index(keyword: keywordOver(tickets));
      for (final Ticket t in tickets) {
        await save(idx, t);
      }
      await drain();

      final DVSemanticPage<Ticket> page = await idx.query('refund invoice late',
          mode: DVSearchMode.hybrid, limit: 3);
      expect(page.hits.first.record.id, 'both');
      expect(page.hits.first.matchedBy,
          <DVSearchMode>{DVSearchMode.keyword, DVSearchMode.semantic});
    });

    test('keyword results pass the same tenant and policy checks', () async {
      final List<Ticket> tickets = <Ticket>[
        Ticket('mine', 'invoice', tenant: 'acme'),
        Ticket('theirs', 'invoice', tenant: 'globex'),
      ];
      final DVSemanticIndex<Ticket> idx = index(keyword: keywordOver(tickets));
      for (final Ticket t in tickets) {
        store[t.id] = t;
      }
      final DVSemanticPage<Ticket> page = await const DVTenants()
          .withTenant('acme', () => idx.query('invoice'));
      expect(page.items.map((Ticket t) => t.id), <String>['mine']);
    });
  });

  group('retrieval for AI features', () {
    test('retrieve returns rows without sensitive fields', () async {
      final DVSemanticIndex<Ticket> idx = index();
      await save(idx, Ticket('t1', 'late delivery', secret: 'card 4242'));
      await drain();

      final DVSemanticRetrieval<Ticket> context =
          await idx.retrieve('late delivery', limit: 2);
      expect(context.rows, hasLength(1));
      expect(context.rows.single.containsKey('secret'), isFalse,
          reason: 'what reaches a prompt must not carry a sensitive field');
      expect(context.rows.single['body'], 'late delivery');
      expect(context.hits.single.chunk, isNotNull);
    });
  });

  test('cosine similarity is the ranking', () async {
    // A sanity check on the reference adapter the other tests rely on.
    await vectors.upsert('s', <DVVectorEntry>[
      const DVVectorEntry(recordId: 'near', chunk: 0, offset: 0, text: 'n',
          vector: <double>[1, 1, 0]),
      const DVVectorEntry(recordId: 'far', chunk: 0, offset: 0, text: 'f',
          vector: <double>[0, 0, 1]),
    ]);
    final List<DVVectorMatch> matches =
        await vectors.nearest('s', const <double>[1, 0.9, 0], k: 2);
    expect(matches.first.entry.recordId, 'near');
    expect(matches.first.score, closeTo(math.cos(0.05), 0.01));
  });

  group('costs', () {
    test('a tenant over its embedding budget is refused, not degraded',
        () async {
      final DVMeters meters =
          DVMeters(store: DVMemoryMeterStore(), clock: () => DateTime.utc(2026, 9, 15));
      final DVMeterDefinition tokens = DVMeterDefinition(
        'embedding_tokens',
        unit: 'token',
        kind: DVMeterKind.counter,
        limit: const DVLimit.fixed(30),
        atLimit: DVQuota.block,
      );
      final DVSemanticIndex<Ticket> idx = index(
          metering: DVSemanticMetering(meters: meters, tokens: tokens));
      await save(idx, Ticket('t1', 'late delivery'));
      await drain();
      final int before = embedder.calls;

      // Each query costs tokens; the budget runs out.
      Object? refusal;
      for (int i = 0; i < 20 && refusal == null; i++) {
        try {
          await idx.query('late delivery unhappy refund invoice',
              mode: DVSearchMode.semantic);
        } on DVSemanticBudgetExceeded catch (e) {
          refusal = e;
        }
      }
      expect(refusal, isA<DVSemanticBudgetExceeded>(),
          reason: 'a search over budget says it cannot run; it does not '
              'quietly fall back to keyword and return something different');
      expect((refusal! as DVSemanticBudgetExceeded).code, 'DV-SEMANTIC-007');
      final int calls = embedder.calls;
      expect(() => idx.query('late delivery unhappy refund invoice',
              mode: DVSearchMode.semantic),
          throwsA(isA<DVSemanticBudgetExceeded>()));
      expect(embedder.calls, calls,
          reason: 'a refused query is not embedded, and not paid for');
      expect(calls, greaterThan(before));
    });
  });
}
