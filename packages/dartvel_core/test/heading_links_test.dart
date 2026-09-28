// A link to a heading: `/docs/ui#layouts` opens the page at that heading.
//
// Flutter has no fragments. Every heading a page draws gets an id derived
// from its words: the runtime writes it on the heading in the document copy
// of the page, and scrolls the Flutter page to the heading a link names.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('the id a heading gets', () {
    test('is its words, lower case, joined by hyphens', () {
      expect(dvHeadingSlug('Lay out children in a list'),
          'lay-out-children-in-a-list');
    });

    test('drops punctuation a URL would have to escape', () {
      expect(dvHeadingSlug('Find text with Ctrl+F (on the web)!'),
          'find-text-with-ctrlf-on-the-web');
      expect(dvHeadingSlug('  What -- is --  left?  '), 'what-is-left');
    });

    test('keeps letters that are not ASCII', () {
      expect(dvHeadingSlug('Données et réglages'), 'données-et-réglages');
    });

    test('is never empty', () {
      expect(dvHeadingSlug('?!'), 'section');
    });
  });

  group('the ids of a page', () {
    test('only headings get one, and a repeat is numbered', () {
      final List<String?> ids = dvHeadingIds(const <DVFindBlock>[
        DVFindBlock('Setup', headingLevel: 2),
        DVFindBlock('Run the installer.'),
        DVFindBlock('Setup', headingLevel: 3),
        DVFindBlock('Setup', headingLevel: 3),
      ]);
      expect(ids, <String?>['setup', null, 'setup-2', 'setup-3']);
    });
  });
}
