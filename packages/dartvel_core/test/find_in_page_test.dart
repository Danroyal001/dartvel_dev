// Which rendered paragraph a browser's match means, and what the runtime
// mirror is written from.
//
// `beforematch` names an element and nothing else: not the query, not the
// offset. The runtime has the element's text and the paragraphs the page has
// drawn, and has to pick the one to scroll to. Scrolling to the wrong one is
// the silent failure here -- the page moves, somewhere plausible, and the
// reader concludes the words are not on it -- so most of these tests are about
// what must not match.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('which paragraph a match means', () {
    const List<String> page = <String>[
      'Retention',
      'Records are kept for seven years.',
      'Deleting an account removes its records within thirty days.',
      'Contact',
    ];

    test('the paragraph with the same text', () {
      expect(dvFindMatch('Records are kept for seven years.', page), 1);
    });

    test('whitespace and case are what the reader cannot see', () {
      // A mirror writes the text as the page wrapped it; find ignores case.
      expect(dvFindMatch('  records ARE kept\nfor seven   years. ', page), 1);
    });

    test('a sentence the build wrote out of a longer rendered paragraph', () {
      expect(dvFindMatch('removes its records within thirty days', page), 2);
    });

    test('a list the build wrote whole, drawn an item at a time', () {
      expect(
          dvFindMatch(
              'Web Android iOS',
              const <String>['Targets', 'Web', 'Android', 'iOS', 'Linux']),
          isNotNull);
      // A section holding two long paragraphs lands on one of them.
      expect(
          dvFindMatch(
              'Records are kept for seven years. Deleting an account '
              'removes its records within thirty days.',
              page),
          anyOf(1, 2));
    });

    test('a short label inside a long section is not a match for it', () {
      // "Contact" is in every footer; a section that merely mentions it
      // must not scroll there.
      expect(
          dvFindMatch(
              'Contact the team about retention for anything else at all',
              const <String>['Contact', 'Pricing']),
          isNull);
    });

    test('nothing close means nowhere, not the nearest guess', () {
      expect(dvFindMatch('Quarterly revenue by region', page), isNull);
      expect(dvFindMatch('', page), isNull);
      expect(dvFindMatch('anything', const <String>[]), isNull);
    });

    test('text that changed a little still finds its paragraph', () {
      expect(
          dvFindMatch('Records are kept for seven years now.', page), 1);
    });

    test('the same words twice: the hint picks which', () {
      const List<String> repeated = <String>[
        'Read more',
        'First article',
        'Read more',
        'Second article',
        'Read more',
      ];
      expect(dvFindMatch('Read more', repeated, hint: 4), 4);
      expect(dvFindMatch('Read more', repeated, hint: 2), 2);
      expect(dvFindMatch('Read more', repeated), 0);
    });

    test('a hint never outranks the text', () {
      // The page changed since the mirror was written: index 0 is now
      // somebody else's paragraph.
      expect(dvFindMatch('Contact', page, hint: 0), 3);
    });
  });

  group('the runtime anchor', () {
    test('a runtime anchor carries the index it was written at', () {
      expect(dvFindRuntimeAnchor('r12'), 12);
    });

    test("the build's anchors count something else, so are no hint", () {
      expect(dvFindRuntimeAnchor('12'), isNull);
      expect(dvFindRuntimeAnchor(null), isNull);
      expect(dvFindRuntimeAnchor('rx'), isNull);
    });
  });

  group('what the mirror is written from', () {
    test('whitespace collapsed, empty paragraphs dropped, repeats kept', () {
      expect(
          dvFindMirrorBlocks(const <DVFindBlock>[
            DVFindBlock('Pricing', headingLevel: 1),
            DVFindBlock('   '),
            DVFindBlock('Pay\n  monthly'),
            DVFindBlock('Pay monthly'),
          ]),
          const <DVFindBlock>[
            DVFindBlock('Pricing', headingLevel: 1),
            DVFindBlock('Pay monthly'),
            DVFindBlock('Pay monthly'),
          ]);
    });

    test('a heading is written as its level, everything else a paragraph',
        () {
      expect(const DVFindBlock('x', headingLevel: 2).tag, 'h2');
      expect(const DVFindBlock('x').tag, 'p');
      expect(const DVFindBlock('x', headingLevel: 9).tag, 'p');
    });

    test('the mirror stops at its cap rather than copying a novel', () {
      final List<DVFindBlock> blocks = dvFindMirrorBlocks(
        List<DVFindBlock>.generate(10, (int i) => DVFindBlock('x' * 100)),
        maxChars: 450,
      );
      expect(blocks, hasLength(4));
    });

    test('beside a build-written block, only what it does not already say',
        () {
      // The build's block keeps its links and landmarks; what the page drew
      // since -- a row a list built on scrolling -- goes beside it.
      const String built = 'Invoices Invoice 1 paid in full. Invoice 2 due.';
      expect(
          dvFindMissing(built, const <DVFindBlock>[
            DVFindBlock('Invoices', headingLevel: 1),
            DVFindBlock('Invoice 2   due.'),
            DVFindBlock('Invoice 3 overdue.'),
          ]),
          const <DVFindBlock>[DVFindBlock('Invoice 3 overdue.')]);
    });
  });
}
