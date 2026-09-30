// An embedder that needs no network, no key and no model download.
//
// Every embedder Dartvel shipped before this one either called a paid
// provider or was LocalDVAIAdapter's character buckets, which put "refund"
// and "funder" next to each other and "refund" and "money back" nowhere near.
// A search built on that returns something for every query, ranked with
// confidence, and none of it is by meaning. These tests hold the fitted
// embedder to the one thing that makes it semantic: two words that never
// appear together are near when they appear in the same company.
import 'dart:math' as math;

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/framework.dart';
import 'package:test/test.dart';

double cosine(List<double> a, List<double> b) {
  double dot = 0, na = 0, nb = 0;
  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na == 0 || nb == 0) return 0;
  return dot / (math.sqrt(na) * math.sqrt(nb));
}

/// Two topics. "car" and "automobile" never share a document; they share
/// "engine", "wheels" and "road". Nothing about fruit mentions any of them.
const List<String> corpus = <String>[
  'The car needs a new engine and four wheels for the road.',
  'An automobile engine turns the wheels on the road.',
  'Drive the car down the road; the engine is loud.',
  'Service the automobile: check the engine and the wheels.',
  'A banana is a fruit, and so is an apple.',
  'Apple and banana fruit salad with fresh orange.',
  'Orange juice is squeezed from fresh fruit.',
  'Peel the banana and slice the apple into the fruit bowl.',
];

void main() {
  group('fitting', () {
    test('words that share company are near even when they never co-occur',
        () async {
      final DVLatentSemanticEmbedder embedder =
          DVLatentSemanticEmbedder.fit(corpus, dimensions: 2);

      final List<double> car = await embedder.embed('car');
      final List<double> automobile = await embedder.embed('automobile');
      final List<double> banana = await embedder.embed('banana');

      // A word embedder would score car/automobile 0: no shared letters that
      // matter and no document that holds both.
      expect(cosine(car, automobile), greaterThan(0.9));
      expect(cosine(car, banana), lessThan(0.3));
    });

    test('the same corpus fits to the same model, byte for byte', () async {
      final DVLatentSemanticEmbedder a =
          DVLatentSemanticEmbedder.fit(corpus, dimensions: 4);
      final DVLatentSemanticEmbedder b =
          DVLatentSemanticEmbedder.fit(corpus, dimensions: 4);

      expect(a.id, b.id);
      expect(await a.embed('engine wheels'), await b.embed('engine wheels'));
    });

    test('a different corpus is a different model, and says so in its id',
        () {
      final DVLatentSemanticEmbedder a =
          DVLatentSemanticEmbedder.fit(corpus, dimensions: 4);
      final DVLatentSemanticEmbedder b = DVLatentSemanticEmbedder.fit(
          <String>[...corpus, 'Trains run on rails, not on the road.'],
          dimensions: 4);

      // Vectors from two fits are not comparable, and the semantic index
      // tells generations apart by the embedder's id. Two fits under one id
      // would be the silent corruption the generation rule exists to stop.
      expect(a.id, isNot(b.id));
      expect(a.id, startsWith('dartvel/lsa-'));
    });

    test('every vector is as long as the declared dimensions', () async {
      final DVLatentSemanticEmbedder embedder =
          DVLatentSemanticEmbedder.fit(corpus, dimensions: 3);

      expect(embedder.dimensions, 3);
      expect(await embedder.embed('car'), hasLength(3));
      expect(await embedder.embed(''), hasLength(3));
      expect(await embedder.embed('zebra quantum'), hasLength(3));
    });

    test('more dimensions than the corpus can carry are capped, not padded',
        () {
      // Eight documents span at most eight directions. A ninth dimension
      // would be noise with a vector length to match.
      final DVLatentSemanticEmbedder embedder =
          DVLatentSemanticEmbedder.fit(corpus, dimensions: 256);
      expect(embedder.dimensions, lessThanOrEqualTo(corpus.length));
    });

    test('text with no word the model knows embeds to the zero vector',
        () async {
      final DVLatentSemanticEmbedder embedder =
          DVLatentSemanticEmbedder.fit(corpus, dimensions: 2);

      // Not a small random vector: that would be near something, and a
      // search for gibberish would return a confident first result.
      expect(await embedder.embed('zebra quantum xylophone'),
          everyElement(0.0));
    });

    test('an empty corpus or no dimensions is refused', () {
      expect(() => DVLatentSemanticEmbedder.fit(const <String>[]),
          throwsArgumentError);
      expect(() => DVLatentSemanticEmbedder.fit(corpus, dimensions: 0),
          throwsArgumentError);
    });
  });

  group('behind a semantic index', () {
    setUp(() {
      const DVQueues().useAdapter(DVInMemoryQueueAdapter());
      DVSemanticIndex.resetRegistry();
    });

    test('a paraphrase finds the record that shares none of its words',
        () async {
      final Map<String, String> store = <String, String>{
        for (int i = 0; i < corpus.length; i++) 'doc$i': corpus[i],
      };
      final DVSemanticIndex<String> index = DVSemanticIndex<String>(
        name: 'notes',
        embedder: DVLatentSemanticEmbedder.fit(corpus, dimensions: 2),
        vectors: DVInMemoryVectorAdapter(),
        idOf: (String text) =>
            store.entries.firstWhere((MapEntry<String, String> e) => e.value == text).key,
        fields: <String, String Function(String)>{'body': (String t) => t},
        load: (String id) async => store[id],
      );
      await index.backfill(store.values, complete: true);

      final DVSemanticPage<String> page =
          await index.query('automobile', mode: DVSearchMode.semantic, limit: 4);

      // doc0 and doc2 say "car" and never "automobile".
      expect(page.items.take(4), containsAll(<String>[corpus[0], corpus[2]]));
      expect(page.items.take(4), everyElement(isNot(contains('fruit'))));
    });
  });
}
