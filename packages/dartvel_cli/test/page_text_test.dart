// The text a page actually contains, taken from its source.
//
// A Flutter web app has an empty body until JavaScript runs, so a crawler, a
// link preview and a reader with scripting off all see nothing. `dartvel
// prerender` can fix that, but it drives a real browser and `dartvel build
// web` does not run it — so every page shipped blank.
//
// The generator already reads the page. The text is right there in the source:
// DVText('...') and Text('...') literals, in the order they are written. No
// browser required.
import 'package:dartvel_cli/src/build/page_text.dart';
import 'package:test/test.dart';

void main() {
  group('finding the text', () {
    test('it reads DVText literals in order', () {
      const String source = '''
Widget _page(BuildContext context) => DVBox.list([
  const DVText('Flutter, all the way down.'),
  const DVText('Write pages and models.'),
]);
''';

      expect(dvPageText(source), <String>[
        'Flutter, all the way down.',
        'Write pages and models.',
      ]);
    });

    test('it reads plain Text too', () {
      // A page mixes them, and a crawler does not care which widget produced
      // a sentence.
      const String source = "Text('A heading'), DVText('A paragraph')";

      expect(dvPageText(source),
          <String>['A heading', 'A paragraph']);
    });

    test('it reads text inside an application own components', () {
      // Matching DVText and Text by name is hardcoding one level down. Real
      // pages wrap text in their own widgets -- Heading, Body, Eyebrow -- and
      // a generator that only knows the framework's names finds nothing on
      // them. The site's own pages returned empty for exactly this reason.
      const String source = '''
Section(children: <Widget>[
  Eyebrow('COMING SOON'),
  Heading('Dartvel Cloud.'),
  Body('Deploy without assembling the runtime around it.'),
]);
''';

      expect(dvPageText(source), <String>[
        'COMING SOON',
        'Dartvel Cloud.',
        'Deploy without assembling the runtime around it.',
      ]);
    });

    test('it reads a list of strings, as a code block holds one', () {
      const String source = '''
CodeBlock(<String>[
  'dartvel build web',
  'dartvel deploy',
]);
''';

      expect(dvPageText(source),
          <String>['dartvel build web', 'dartvel deploy']);
    });

    test('an annotation is not page text', () {
      // @pragma('vm:entry-point') put "vm:entry-point" at the top of every
      // page, and @DVPage(title: ...) repeated the title inside the body it
      // already titles.
      const String source = '''
@DVPage(title: 'Cloud — Dartvel', showAppBar: false)
@pragma('vm:entry-point')
Widget _cloudPage(BuildContext context) => Heading('Dartvel Cloud.');
''';

      expect(dvPageText(source), <String>['Dartvel Cloud.']);
    });

    test('an import or a library name is not page text', () {
      const String source = '''
import 'package:flutter/material.dart';
library some.thing;
Heading('The only real line.');
''';

      expect(dvPageText(source), <String>['The only real line.']);
    });

    test('it reads double-quoted strings', () {
      expect(dvPageText('DVText("Double quoted")'), <String>['Double quoted']);
    });

    test('an interpolated string is skipped rather than shipped raw', () {
      // "Loaded at: \$time" in a body is worse than nothing: it is visibly
      // broken text on a page a crawler is reading.
      const String source = r"DVText('Loaded at: $when'), DVText('Real text')";

      expect(dvPageText(source), <String>['Real text']);
    });

    test('it ignores things that are not prose', () {
      // Route paths, asset names and single words that are plainly
      // identifiers add nothing and dilute the page.
      const String source = """
DVText('/docs'), DVText('assets/logo.png'), DVText('#2F6BFF'),
DVText('A real sentence here.')
""";

      expect(dvPageText(source), <String>['A real sentence here.']);
    });

    test('it keeps a short label that reads like words', () {
      // "Get started" is two words and belongs in the text; discarding
      // everything short would lose every heading and button.
      expect(dvPageText("DVText('Get started')"), <String>['Get started']);
    });

    test('duplicates collapse, order survives', () {
      const String source =
          "DVText('Docs'), DVText('Cloud'), DVText('Docs')";

      expect(dvPageText(source), <String>['Docs', 'Cloud']);
    });

    test('a page with no literals yields nothing rather than failing', () {
      expect(dvPageText('Widget _page(c) => const SizedBox.shrink();'),
          isEmpty);
    });
  });

  group('putting it in the page', () {
    const String shell = '<html><head></head><body></body></html>';

    test('it goes in a noscript block', () {
      // Where a browser with scripting shows nothing and one without shows
      // the page. A hidden div is for crawlers; noscript is for people.
      final html = dvApplyPageText(shell, <String>['A heading', 'A sentence.']);

      expect(html, contains('<noscript>'));
      expect(html, contains('A heading'));
      expect(html, contains('A sentence.'));
    });

    test('the first line is a heading, the rest are paragraphs', () {
      final html = dvApplyPageText(shell, <String>['Title', 'Body text']);

      expect(html, contains('<h1>Title</h1>'));
      expect(html, contains('<p>Body text</p>'));
    });

    test('the text is escaped', () {
      // It comes from source a person wrote, and an ampersand or a bracket
      // would otherwise break the document.
      final html = dvApplyPageText(shell, <String>['Fish & <chips>']);

      expect(html, contains('&amp;'));
      expect(html, contains('&lt;chips&gt;'));
      expect(html, isNot(contains('<chips>')));
    });

    test('applying twice replaces rather than accumulates', () {
      final once = dvApplyPageText(shell, <String>['One']);
      final twice = dvApplyPageText(once, <String>['One']);

      expect(twice, once);
      expect('<noscript>'.allMatches(twice).length, 1);
    });

    test('no text means no empty block', () {
      expect(dvApplyPageText(shell, const <String>[]), shell);
    });

    test('a page with no body is returned unchanged', () {
      expect(dvApplyPageText('<html><head></head></html>', <String>['x']),
          '<html><head></head></html>');
    });
  });

  group('crawler-visible HTML from the semantics tree', () {
    const shell = '<!DOCTYPE html><html><head></head><body>'
        '<script src="flutter_bootstrap.js"></script></body></html>';

    test('the markup is inserted as markup', () {
      // dvApplyPageText escapes what it is given, because it is given plain
      // strings. Semantic HTML has to arrive as HTML or every tag ships as
      // &lt;h2&gt; -- which is worse than the paragraphs it replaces.
      final html = dvApplyPageHtml(shell, '<h1>Docs</h1>\n<a href="/x">X</a>');

      expect(html, contains('<h1>Docs</h1>'));
      expect(html, contains('<a href="/x">X</a>'));
      expect(html, isNot(contains('&lt;h1&gt;')));
    });

    test('it sits inside noscript, where the app is not running', () {
      final html = dvApplyPageHtml(shell, '<h1>Docs</h1>');

      expect(html, contains('<noscript>'));
      expect(html.indexOf('<noscript>'), lessThan(html.indexOf('<h1>Docs')));
      expect(html.indexOf('<h1>Docs'), lessThan(html.indexOf('</noscript>')));
    });

    test('applying it twice does not stack two copies', () {
      // The build runs more than once in a working tree, and a page that
      // accumulated its own content every time would grow without limit.
      final once = dvApplyPageHtml(shell, '<h1>Docs</h1>');

      expect(dvApplyPageHtml(once, '<h1>Docs</h1>'), once);
    });

    test('it replaces what the text extractor wrote', () {
      // Both write into the same marked region, so the better one wins
      // rather than appearing beneath the worse one.
      final flat = dvApplyPageText(shell, <String>['Docs', 'Some prose']);
      final structured = dvApplyPageHtml(flat, '<h1>Docs</h1>');

      expect(structured, contains('<h1>Docs</h1>'));
      expect(structured, isNot(contains('<p>Some prose</p>')));
    });

    test('nothing to say leaves the page alone', () {
      expect(dvApplyPageHtml(shell, '   '), isNot(contains('<noscript>')));
    });
  });
}
