/// Ranking configuration: synonyms, typo tolerance and highlight markers.
///
/// The spec configures these in `pubspec.yaml`, so they arrive as data rather
/// than as code a provider hard-codes. Keeping the rules here means the local
/// provider and any hosted adapter that has to post-process agree on what a
/// match is.
class DVSearchTuning {
  const DVSearchTuning({
    this.synonyms = const <String, List<String>>{},
    this.typoTolerance = true,
    this.highlightPre = '<mark>',
    this.highlightPost = '</mark>',
  });

  /// Terms that should find each other.
  ///
  /// The table is read in both directions: declaring `ada -> augusta` and then
  /// failing to match "ada" when someone searches "augusta" is the surprising
  /// half of a one-way mapping.
  final Map<String, List<String>> synonyms;

  /// Whether a near-miss counts as a match. See [dvTypoMatches] for the budget.
  final bool typoTolerance;

  /// Wrapped around a match by [dvHighlight].
  final String highlightPre;
  final String highlightPost;

  /// Splits [query] into terms and adds every synonym of each.
  ///
  /// Sorted and de-duplicated, so a term reachable two ways is not weighted
  /// twice and two runs produce the same list.
  List<String> expand(String query) {
    final Set<String> out = <String>{};
    for (final String term in query.toLowerCase().split(RegExp(r'\s+'))) {
      if (term.isEmpty) continue;
      out.add(term);
      out.addAll(_synonymsOf(term));
    }
    return out.toList()..sort();
  }

  Iterable<String> _synonymsOf(String term) sync* {
    for (final MapEntry<String, List<String>> entry in synonyms.entries) {
      final String key = entry.key.toLowerCase();
      final List<String> values =
          entry.value.map((String v) => v.toLowerCase()).toList();
      if (key == term) {
        yield* values;
      } else if (values.contains(term)) {
        // The reverse direction, so the table means "these are the same".
        yield key;
        yield* values.where((String v) => v != term);
      }
    }
  }
}

/// Whether [candidate] is [term] allowing for a typo.
///
/// The budget scales with length rather than being flat, because a flat
/// distance of two makes "ada" match "eve" -- an unrelated word of the same
/// length, returned with full confidence. Under five characters nothing is
/// tolerated; up to eight, one edit; beyond that, two.
///
/// A transposition of adjacent characters costs one edit rather than two: it is
/// the most common typo there is, and counting it as two puts "recieve" outside
/// the budget of the word it obviously means.
bool dvTypoMatches(
  String term,
  String candidate, {
  bool enabled = true,
}) {
  final String a = term.toLowerCase();
  final String b = candidate.toLowerCase();
  if (a == b) return true;
  if (!enabled) return false;

  final int budget = a.length < 5 ? 0 : (a.length <= 8 ? 1 : 2);
  if (budget == 0) return false;
  // A length gap wider than the budget cannot be closed; skipping the matrix
  // here also keeps a long candidate from being compared against a short term.
  if ((a.length - b.length).abs() > budget) return false;

  return _damerauLevenshtein(a, b, budget) <= budget;
}

/// Optimal string alignment distance, stopping once [budget] is exceeded.
int _damerauLevenshtein(String a, String b, int budget) {
  final List<List<int>> d = List<List<int>>.generate(
    a.length + 1,
    (int _) => List<int>.filled(b.length + 1, 0),
  );
  for (int i = 0; i <= a.length; i += 1) {
    d[i][0] = i;
  }
  for (int j = 0; j <= b.length; j += 1) {
    d[0][j] = j;
  }

  for (int i = 1; i <= a.length; i += 1) {
    int rowBest = budget + 1;
    for (int j = 1; j <= b.length; j += 1) {
      final int cost = a[i - 1] == b[j - 1] ? 0 : 1;
      int value = <int>[
        d[i - 1][j] + 1,
        d[i][j - 1] + 1,
        d[i - 1][j - 1] + cost,
      ].reduce((int x, int y) => x < y ? x : y);
      if (i > 1 &&
          j > 1 &&
          a[i - 1] == b[j - 2] &&
          a[i - 2] == b[j - 1]) {
        final int transposed = d[i - 2][j - 2] + 1;
        if (transposed < value) value = transposed;
      }
      d[i][j] = value;
      if (value < rowBest) rowBest = value;
    }
    // Every alignment through this row already costs more than allowed.
    if (rowBest > budget) return budget + 1;
  }
  return d[a.length][b.length];
}

/// Wraps each occurrence of any of [terms] in [text] with [pre] and [post].
///
/// Matching is case-insensitive and the original casing is preserved, so a
/// highlighted result still reads as what was stored.
///
/// Spans are collected and merged before anything is inserted. Replacing terms
/// one after another would wrap the markers of an earlier pass -- 'love' and
/// 'lovelace' both match "Lovelace" -- and the corrupted output still looks
/// like text.
String dvHighlight(
  String text,
  Iterable<String> terms, {
  String pre = '<mark>',
  String post = '</mark>',
}) {
  final String haystack = text.toLowerCase();
  final List<List<int>> spans = <List<int>>[];

  for (final String term in terms) {
    if (term.isEmpty) continue;
    final String needle = term.toLowerCase();
    int at = haystack.indexOf(needle);
    while (at != -1) {
      spans.add(<int>[at, at + needle.length]);
      at = haystack.indexOf(needle, at + 1);
    }
  }
  if (spans.isEmpty) return text;

  spans.sort((List<int> x, List<int> y) => x[0].compareTo(y[0]));
  final List<List<int>> merged = <List<int>>[spans.first];
  for (final List<int> span in spans.skip(1)) {
    final List<int> last = merged.last;
    if (span[0] <= last[1]) {
      if (span[1] > last[1]) last[1] = span[1];
    } else {
      merged.add(span);
    }
  }

  final StringBuffer out = StringBuffer();
  int cursor = 0;
  for (final List<int> span in merged) {
    out
      ..write(text.substring(cursor, span[0]))
      ..write(pre)
      ..write(text.substring(span[0], span[1]))
      ..write(post);
    cursor = span[1];
  }
  out.write(text.substring(cursor));
  return out.toString();
}
