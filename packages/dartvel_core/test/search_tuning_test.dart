// Ranking helpers: synonyms, typo tolerance and highlighting.
//
// Each of these fails silently when it is wrong -- a too-permissive typo
// distance returns confident nonsense, and a highlighter that mangles offsets
// returns text that still reads as text -- so the tests here are mostly about
// the boundaries rather than the happy path.
import 'package:dartvel_core/src/search/search_tuning.dart';
import 'package:test/test.dart';

void main() {
  group('synonyms', () {
    const DVSearchTuning tuning = DVSearchTuning(
      synonyms: <String, List<String>>{
        'ada': <String>['augusta'],
        'admin': <String>['administrator', 'superuser'],
      },
    );

    test('a term expands to its synonyms and keeps itself', () {
      expect(tuning.expand('ada'), <String>['ada', 'augusta']);
    });

    test('expansion is per term, not per query string', () {
      expect(tuning.expand('ada admin'),
          <String>['ada', 'admin', 'administrator', 'augusta', 'superuser']);
    });

    test('a term with no synonyms is left as it is', () {
      expect(tuning.expand('lovelace'), <String>['lovelace']);
    });

    test('expansion is symmetric, so searching the synonym finds the term', () {
      // Declaring `ada -> augusta` and then failing to match "ada" when the
      // user types "augusta" is the surprising half of a one-way table.
      expect(tuning.expand('augusta'), contains('ada'));
    });

    test('duplicates collapse, so a term is not weighted twice', () {
      const DVSearchTuning overlapping = DVSearchTuning(
        synonyms: <String, List<String>>{
          'a': <String>['b'],
          'b': <String>['a'],
        },
      );
      expect(overlapping.expand('a b'), <String>['a', 'b']);
    });
  });

  group('typo tolerance', () {
    test('an exact term matches at any length', () {
      expect(dvTypoMatches('ada', 'ada'), isTrue);
    });

    test('a short term tolerates nothing', () {
      // With a flat distance of 2, "ada" would match "eve". A three-letter
      // query matching an unrelated three-letter word is worse than no typo
      // tolerance at all.
      expect(dvTypoMatches('ada', 'eve'), isFalse);
      expect(dvTypoMatches('ada', 'ade'), isFalse);
    });

    test('a medium term tolerates one edit', () {
      expect(dvTypoMatches('lovelace', 'lovelice'), isTrue);
      expect(dvTypoMatches('lovelace', 'lovel'), isFalse);
    });

    test('a long term tolerates two', () {
      expect(dvTypoMatches('understanding', 'understandnig'), isTrue);
      expect(dvTypoMatches('understanding', 'unrelatedword'), isFalse);
    });

    test('a transposition costs one edit, not two', () {
      // Swapped adjacent letters are the most common typo there is; counting
      // them as two edits puts them outside a five-letter word's budget.
      expect(dvTypoMatches('teh', 'the'), isFalse); // still too short to allow
      expect(dvTypoMatches('recieve', 'receive'), isTrue);
    });

    test('tolerance can be switched off', () {
      expect(dvTypoMatches('lovelace', 'lovelice', enabled: false), isFalse);
      expect(dvTypoMatches('lovelace', 'lovelace', enabled: false), isTrue);
    });
  });

  group('highlighting', () {
    test('a match is wrapped and the original case is kept', () {
      expect(
        dvHighlight('Ada Lovelace', <String>['ada']),
        '<mark>Ada</mark> Lovelace',
      );
    });

    test('every occurrence is wrapped', () {
      expect(
        dvHighlight('ada and ada', <String>['ada']),
        '<mark>ada</mark> and <mark>ada</mark>',
      );
    });

    test('overlapping terms do not nest or corrupt the text', () {
      // 'love' and 'lovelace' both match; naive successive replacement would
      // wrap the marker it just inserted.
      final String out = dvHighlight('Lovelace', <String>['love', 'lovelace']);
      expect(out, '<mark>Lovelace</mark>');
      expect(out, isNot(contains('<mark><mark>')));
    });

    test('markers are configurable', () {
      expect(
        dvHighlight('Ada', <String>['ada'], pre: '[', post: ']'),
        '[Ada]',
      );
    });

    test('text with no match comes back unchanged', () {
      expect(dvHighlight('Ada', <String>['zzz']), 'Ada');
    });

    test('a regex metacharacter in a term is matched literally', () {
      // A term is user input. Treating '.' as "any character" would highlight
      // the wrong span, and an unbalanced '(' would throw.
      expect(dvHighlight('a.b', <String>['.']), 'a<mark>.</mark>b');
      expect(dvHighlight('a(b', <String>['(']), 'a<mark>(</mark>b');
    });

    test('an empty term is ignored rather than wrapping every gap', () {
      expect(dvHighlight('Ada', <String>['']), 'Ada');
    });
  });
}
