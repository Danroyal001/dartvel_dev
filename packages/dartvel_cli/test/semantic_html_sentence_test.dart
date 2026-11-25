// A sentence with links in it is one paragraph in the document, and a piece
// that starts with closing punctuation follows the piece before it directly.
//
// A paragraph whose links are placed with DVWidgetSpan reaches the build as a
// node whose children are its runs of text and its links, in reading order.
// Each piece went out as an element of its own -- a <p> per run, an <a> per
// link -- so the server-rendered page read "Get a free quote . Our privacy
// policy , terms and refund policy explain..." (sigmadev.digital/about,
// Dartvel main after #309): the browser's find could not match "free quote.",
// a selection came out a line per piece, and a screen reader paused at every
// one.
import 'package:dartvel_cli/src/build/semantic_html.dart';
import 'package:test/test.dart';

DVSemanticNode text(String label) => DVSemanticNode(label: label);

DVSemanticNode link(String label, String href) =>
    DVSemanticNode(role: 'link', label: label, href: href, inSentence: true);

String anchor(String label, String href) =>
    '<a href="$href" title="$label" aria-label="$label">$label</a>';

void main() {
  test('the pieces of a sentence are one paragraph, read with its links in place', () {
    final String html = dvSemanticHtml(<DVSemanticNode>[
      DVSemanticNode(children: <DVSemanticNode>[
        text('Questions, or a project in mind?'),
        link('Get a free quote', '/contact'),
        text('. Our'),
        link('privacy policy', '/privacy'),
        text(','),
        link('terms', '/terms'),
        text('and'),
        link('refund policy', '/refund-policy'),
        text('explain how we handle your data and your payments.'),
      ]),
    ]);
    expect(
      html,
      '<p>Questions, or a project in mind? ${anchor('Get a free quote', '/contact')}. Our '
      '${anchor('privacy policy', '/privacy')}, ${anchor('terms', '/terms')} and '
      '${anchor('refund policy', '/refund-policy')} explain how we handle your data and your payments.</p>',
    );
    // What a reader, find and a crawler get once the tags are gone.
    final String words = html.replaceAll(RegExp('<[^>]+>'), '');
    expect(words, contains('Get a free quote. Our privacy policy, terms and refund policy explain'));
    expect(words, isNot(contains(' .')));
    expect(words, isNot(contains(' ,')));
  });

  test('words on either side of a link stay apart', () {
    final String html = dvSemanticHtml(<DVSemanticNode>[
      DVSemanticNode(children: <DVSemanticNode>[
        text('Read our'),
        link('terms', '/terms'),
        text('before you start'),
      ]),
    ]);
    expect(html, '<p>Read our ${anchor('terms', '/terms')} before you start</p>');
  });

  test('every closing mark follows directly; an opening one is followed directly', () {
    for (final String mark in <String>['.', ',', ';', ':', '!', '?', ')', ']', '}', '…', '%', '”', '’', '»']) {
      final String html = dvSemanticHtml(<DVSemanticNode>[
        DVSemanticNode(children: <DVSemanticNode>[text('See'), link('this', '/this'), text('$mark next')]),
      ]);
      expect(html, '<p>See ${anchor('this', '/this')}$mark next</p>', reason: mark);
    }
    for (final String mark in <String>['(', '[', '{', '“', '‘', '«']) {
      final String html = dvSemanticHtml(<DVSemanticNode>[
        DVSemanticNode(children: <DVSemanticNode>[text('See $mark'), link('this', '/this'), text(')')]),
      ]);
      expect(html, '<p>See $mark${anchor('this', '/this')})</p>', reason: mark);
    }
  });

  test('a link that starts a sentence and one that ends it', () {
    final String html = dvSemanticHtml(<DVSemanticNode>[
      DVSemanticNode(children: <DVSemanticNode>[
        link('Pricing', '/pricing'),
        text('is on its own page, next to'),
        link('Docs', '/docs'),
      ]),
    ]);
    expect(html, '<p>${anchor('Pricing', '/pricing')} is on its own page, next to ${anchor('Docs', '/docs')}</p>');
  });

  test('paragraphs and links that are not one sentence stay elements of their own', () {
    // A column of a paragraph, a link and a paragraph: nothing in it was
    // placed in a sentence, so nothing is joined.
    final String html = dvSemanticHtml(<DVSemanticNode>[
      DVSemanticNode(children: <DVSemanticNode>[
        text('Before'),
        const DVSemanticNode(role: 'link', label: 'Our work', href: '/past-work'),
        text('After'),
      ]),
    ]);
    expect(html, '<p>Before</p>\n${anchor('Our work', '/past-work')}\n<p>After</p>');
  });

  test('a link wrapping a sentence is named without a space before its punctuation', () {
    final String html = dvSemanticHtml(<DVSemanticNode>[
      DVSemanticNode(href: '/contact', children: <DVSemanticNode>[text('Get a free quote'), text('.')]),
    ]);
    expect(html, anchor('Get a free quote.', '/contact'));
  });
}
