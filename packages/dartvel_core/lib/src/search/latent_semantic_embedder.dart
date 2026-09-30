/// An embedder fitted to the application's own text, with no network, no key
/// and no model to download.
///
/// Latent semantic analysis: the text is a matrix of weighted word counts, and
/// its strongest directions are the topics the corpus is about. A word is
/// placed by the company it keeps, so "car" and "automobile" land together
/// when both sit next to "engine" and "wheels", although no document says
/// both. That is meaning in the sense semantic search needs, learned from the
/// corpus rather than from the internet.
///
/// What it is not: a language model. It knows the words its corpus contains
/// and nothing else, so a question in words the corpus never uses embeds to
/// the zero vector and finds nothing, which is the honest answer. For a
/// documentation site, a product catalogue or a help centre, whose vocabulary
/// is its own, it is often enough. For open-ended questions, use a provider's
/// embedding model through [DVAIEmbedder].
///
/// The fit is part of the model. Two fits of different text are two models,
/// and [id] carries a fingerprint of the fit so the semantic index builds a
/// new generation rather than comparing vectors from both.
library dartvel_core.search.latent_semantic_embedder;

import 'dart:math' as math;
import 'dart:typed_data';

import 'semantic_search.dart' show DVEmbedder;

/// Words too common to say what a text is about.
const Set<String> dvLatentSemanticStopWords = <String>{
  'a', 'about', 'after', 'all', 'also', 'an', 'and', 'any', 'are', 'as', 'at',
  'be', 'been', 'before', 'but', 'by', 'can', 'could', 'did', 'do', 'does',
  'each', 'for', 'from', 'get', 'had', 'has', 'have', 'how', 'i', 'if', 'in',
  'into', 'is', 'it', 'its', 'just', 'me', 'more', 'most', 'my', 'no', 'not',
  'of', 'on', 'one', 'only', 'or', 'other', 'our', 'out', 'so', 'some',
  'such', 'than', 'that', 'the', 'their', 'them', 'then', 'there', 'these',
  'they', 'this', 'those', 'to', 'up', 'us', 'was', 'we', 'were', 'what',
  'when', 'where', 'which', 'while', 'who', 'why', 'will', 'with', 'would',
  'you', 'your',
};

/// The words of [text], lower-cased, without stop words, with the common
/// English endings taken off so "deploying" and "deploys" are one word.
List<String> dvLatentSemanticTokens(
  String text, {
  Set<String> stopWords = dvLatentSemanticStopWords,
}) {
  final List<String> out = <String>[];
  for (final RegExpMatch match
      in RegExp(r'[a-z0-9]+').allMatches(text.toLowerCase())) {
    final String word = match.group(0)!;
    if (word.length < 2 || stopWords.contains(word)) continue;
    out.add(_stem(word));
  }
  return out;
}

String _stem(String word) {
  // Longest first, and only where enough of the word is left to still be
  // one: "is" is not "i" plus a plural.
  const List<String> endings = <String>[
    'ations', 'ation', 'ings', 'ing', 'ies', 'es', 's', 'ed',
  ];
  for (final String ending in endings) {
    if (word.length > ending.length + 3 && word.endsWith(ending)) {
      final String root = word.substring(0, word.length - ending.length);
      return ending == 'ies' ? '${root}y' : root;
    }
  }
  return word;
}

/// Latent semantic analysis over a corpus the application hands it.
class DVLatentSemanticEmbedder implements DVEmbedder {
  DVLatentSemanticEmbedder._({
    required Map<String, int> terms,
    required Float64List idf,
    required List<Float64List> basis,
    required this.stopWords,
    required this.id,
  })  : _terms = terms,
        _idf = idf,
        _basis = basis;

  /// Fits the embedder to [documents].
  ///
  /// [dimensions] is how many topics are kept. More keeps finer distinctions
  /// and more noise; it is capped at the number of documents and of distinct
  /// words, which is all the directions the corpus has. The fit is
  /// deterministic: the same documents give the same model and the same
  /// [id] on every machine.
  factory DVLatentSemanticEmbedder.fit(
    Iterable<String> documents, {
    int dimensions = 128,
    int iterations = 8,
    Set<String> stopWords = dvLatentSemanticStopWords,
  }) {
    if (dimensions < 1) {
      throw ArgumentError.value(dimensions, 'dimensions', 'must be positive');
    }
    if (iterations < 1) {
      throw ArgumentError.value(iterations, 'iterations', 'must be positive');
    }
    final List<List<String>> tokenized = <List<String>>[
      for (final String document in documents)
        dvLatentSemanticTokens(document, stopWords: stopWords),
    ]..removeWhere((List<String> words) => words.isEmpty);
    if (tokenized.isEmpty) {
      throw ArgumentError.value(documents, 'documents',
          'hold no words to learn from; a model fitted to nothing is noise');
    }

    // Terms in a fixed order, so the same corpus is the same matrix.
    final Map<String, int> frequency = <String, int>{};
    for (final List<String> words in tokenized) {
      for (final String word in words.toSet()) {
        frequency[word] = (frequency[word] ?? 0) + 1;
      }
    }
    final List<String> vocabulary = frequency.keys.toList()..sort();
    final Map<String, int> terms = <String, int>{
      for (int i = 0; i < vocabulary.length; i++) vocabulary[i]: i,
    };
    final Float64List idf = Float64List(vocabulary.length);
    for (int i = 0; i < vocabulary.length; i++) {
      idf[i] = math.log(tokenized.length / frequency[vocabulary[i]]!) + 1;
    }

    final List<_Sparse> rows = <_Sparse>[
      for (final List<String> words in tokenized) _weigh(words, terms, idf),
    ];
    final int k = math.min(dimensions, math.min(rows.length, vocabulary.length));
    final List<Float64List> basis =
        _topDirections(rows, vocabulary.length, k, iterations);

    return DVLatentSemanticEmbedder._(
      terms: terms,
      idf: idf,
      basis: basis,
      stopWords: stopWords,
      id: 'dartvel/lsa-${_fingerprint(vocabulary, idf, basis)}',
    );
  }

  final Map<String, int> _terms;
  final Float64List _idf;
  final List<Float64List> _basis;
  final Set<String> stopWords;

  /// `dartvel/lsa-` and a fingerprint of the fit.
  @override
  final String id;

  @override
  int get dimensions => _basis.length;

  /// How many distinct words the fit learned.
  int get vocabularySize => _terms.length;

  @override
  Future<List<double>> embed(String text) async {
    final _Sparse row = _weigh(
        dvLatentSemanticTokens(text, stopWords: stopWords), _terms, _idf);
    return <double>[
      for (final Float64List direction in _basis) row.dot(direction),
    ];
  }

  /// Log-scaled counts times inverse document frequency, unit length. Words
  /// the fit never saw carry no weight: there is no direction to put them in.
  static _Sparse _weigh(
      List<String> words, Map<String, int> terms, Float64List idf) {
    final Map<int, double> counts = <int, double>{};
    for (final String word in words) {
      final int? index = terms[word];
      if (index == null) continue;
      counts[index] = (counts[index] ?? 0) + 1;
    }
    final List<int> indexes = counts.keys.toList()..sort();
    final Float64List values = Float64List(indexes.length);
    double norm = 0;
    for (int i = 0; i < indexes.length; i++) {
      final double weight =
          (1 + math.log(counts[indexes[i]]!)) * idf[indexes[i]];
      values[i] = weight;
      norm += weight * weight;
    }
    if (norm > 0) {
      final double length = math.sqrt(norm);
      for (int i = 0; i < values.length; i++) {
        values[i] /= length;
      }
    }
    return _Sparse(Int32List.fromList(indexes), values);
  }

  /// The [k] strongest directions of the term space: the top right singular
  /// vectors of the document matrix, by subspace iteration from a seeded
  /// start so the result does not depend on the run.
  static List<Float64List> _topDirections(
      List<_Sparse> rows, int width, int k, int iterations) {
    final math.Random random = math.Random(0x5eed);
    List<Float64List> q = <Float64List>[
      for (int j = 0; j < k; j++)
        Float64List.fromList(<double>[
          for (int i = 0; i < width; i++) random.nextDouble() - 0.5,
        ]),
    ];
    q = _orthonormal(q);
    for (int step = 0; step < iterations; step++) {
      // (XᵀX)q, as Xᵀ(Xq): the matrix is sparse and XᵀX is not.
      final List<Float64List> next = <Float64List>[
        for (int j = 0; j < k; j++) Float64List(width),
      ];
      for (final _Sparse row in rows) {
        for (int j = 0; j < k; j++) {
          final double along = row.dot(q[j]);
          if (along == 0) continue;
          row.addScaledTo(next[j], along);
        }
      }
      q = _orthonormal(next);
    }
    return q;
  }

  /// Gram-Schmidt, twice over, which is what keeps it orthogonal in floating
  /// point. A direction that collapses to nothing stays zero and embeds
  /// every text to 0 along it, rather than dividing by zero.
  static List<Float64List> _orthonormal(List<Float64List> vectors) {
    final List<Float64List> out = <Float64List>[];
    for (final Float64List vector in vectors) {
      final Float64List v = Float64List.fromList(vector);
      for (int pass = 0; pass < 2; pass++) {
        for (final Float64List u in out) {
          double dot = 0;
          for (int i = 0; i < v.length; i++) {
            dot += v[i] * u[i];
          }
          for (int i = 0; i < v.length; i++) {
            v[i] -= dot * u[i];
          }
        }
      }
      double norm = 0;
      for (int i = 0; i < v.length; i++) {
        norm += v[i] * v[i];
      }
      norm = math.sqrt(norm);
      if (norm > 1e-12) {
        for (int i = 0; i < v.length; i++) {
          v[i] /= norm;
        }
      } else {
        v.fillRange(0, v.length, 0);
      }
      out.add(v);
    }
    return out;
  }

  /// Sixteen hex digits over the vocabulary, the weights and the directions.
  /// Two 32-bit FNV-1a hashes rather than one 64-bit one, because a web build
  /// has no 64-bit integers to multiply in.
  static String _fingerprint(
      List<String> vocabulary, Float64List idf, List<Float64List> basis) {
    int a = 0x811c9dc5;
    int b = 0x01000193 ^ 0x5bd1e995;
    void byte(int value) {
      a = ((a ^ value) * 0x01000193) & 0xffffffff;
      b = ((b ^ value) * 0x01000193) & 0xffffffff;
      b = ((b << 5) | (b >> 27)) & 0xffffffff;
    }

    for (final String word in vocabulary) {
      for (final int unit in word.codeUnits) {
        byte(unit & 0xff);
        byte(unit >> 8);
      }
      byte(0);
    }
    final ByteData scratch = ByteData(8);
    void real(double value) {
      scratch.setFloat64(0, value);
      for (int i = 0; i < 8; i++) {
        byte(scratch.getUint8(i));
      }
    }

    idf.forEach(real);
    for (final Float64List direction in basis) {
      direction.forEach(real);
    }
    return a.toRadixString(16).padLeft(8, '0') +
        b.toRadixString(16).padLeft(8, '0');
  }
}

/// A row with most of its entries zero.
class _Sparse {
  const _Sparse(this.indexes, this.values);

  final Int32List indexes;
  final Float64List values;

  double dot(Float64List dense) {
    double sum = 0;
    for (int i = 0; i < indexes.length; i++) {
      sum += values[i] * dense[indexes[i]];
    }
    return sum;
  }

  void addScaledTo(Float64List dense, double scale) {
    for (int i = 0; i < indexes.length; i++) {
      dense[indexes[i]] += values[i] * scale;
    }
  }
}
