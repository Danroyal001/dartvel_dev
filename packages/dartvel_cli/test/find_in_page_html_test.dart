// The browser's own find reaches the page.
//
// Ctrl+F on a Flutter page finds nothing: the words a reader sees are painted
// into a canvas, and the find bar searches the document. Every page Dartvel
// builds already carries its own text in the document, in the block written
// for crawlers, printers and readers with scripting off -- and that block was
// `display:none`, which is precisely the one thing a browser's find skips.
//
// `hidden="until-found"` is the other kind of hidden: not painted, and still
// searched. The browser finds the text, fires `beforematch` on the element
// holding it, and the runtime scrolls the Flutter page to the paragraph.
// These tests hold the HTML the build writes to that, and hold everything the
// block already did -- crawler text, print, no-script -- to still working.
import 'package:dartvel_cli/src/build/minify.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String _page = '<html><head></head><body></body></html>';

/// Every `<section ...>` opening tag in [html].
List<String> _sections(String html) => RegExp(r'<section\b[^>]*>')
    .allMatches(html)
    .map((RegExpMatch m) => m.group(0)!)
    .toList();

/// The CSS the block ships with, both style elements joined.
String _css(String html) => RegExp(r'<style[^>]*>(.*?)</style>', dotAll: true)
    .allMatches(html)
    .map((RegExpMatch m) => m.group(1)!)
    .join('\n');

void main() {
  group('findable, not visible', () {
    test('each paragraph is its own until-found section with an anchor', () {
      final String out = dvApplyPageHtml(
          _page,
          '<h1>Invoice</h1>\n'
          '<p>Paid in full.</p>\n'
          '<p>Retention is seven years.</p>');

      final List<String> sections = _sections(out);
      expect(sections, hasLength(3),
          reason: 'one section per paragraph, so a match names a paragraph');
      for (final String tag in sections) {
        expect(tag, contains('hidden="until-found"'));
      }
      // Distinct anchors, in document order.
      expect(
          sections
              .map((String t) =>
                  RegExp(r'data-dv-anchor="([^"]*)"').firstMatch(t)!.group(1))
              .toList(),
          <String>['0', '1', '2']);
      // The paragraph is inside its own section, unchanged.
      expect(
          out,
          contains('<section hidden="until-found" data-dv-anchor="2">'
              '<p>Retention is seven years.</p></section>'));
    });

    test('the block is never display:none, which find skips', () {
      final String out = dvApplyPageHtml(_page, '<h1>Invoice</h1>');
      final String css = _css(out);
      expect(css, isNot(contains('.dv-fallback{display:none}')));
      expect(RegExp(r'\.dv-fallback\{[^}]*display:none').hasMatch(css), isFalse);
      expect(RegExp(r'\.dv-fallback\{[^}]*visibility:hidden').hasMatch(css),
          isFalse,
          reason: 'visibility:hidden is not searchable either');
    });

    test('the block takes no room and paints nothing on the screen', () {
      // It is findable, so it has to be laid out; on the screen it is a
      // clipped box of no size, so the browser scrolling to a match moves
      // nothing and shows nothing over the canvas.
      final String css = _css(dvApplyPageHtml(_page, '<h1>Invoice</h1>'));
      final RegExpMatch? screen =
          RegExp(r'@media screen\{\.dv-fallback\{([^}]*)\}').firstMatch(css);
      expect(screen, isNotNull, reason: 'a screen-only rule hides the block');
      expect(screen!.group(1), contains('width:1px'));
      expect(screen.group(1), contains('height:1px'));
      expect(screen.group(1), contains('overflow:hidden'));
      expect(screen.group(1), contains('clip-path:inset(50%)'));
    });

    test('containers are kept and their paragraphs are sections', () {
      // nav, main and footer are structure a crawler reads; the text inside
      // them is what a reader searches for.
      final String out = dvApplyPageHtml(
          _page,
          '<nav>\n<a href="/docs">Docs</a>\n</nav>\n'
          '<main>\n<h2>Install</h2>\n<pre><code>dart pub get\n'
          'dartvel build web</code></pre>\n</main>');

      expect(out, contains('<nav>'));
      expect(out, contains('<main>'));
      expect(
          out,
          contains('<section hidden="until-found" data-dv-anchor="0">'
              '<a href="/docs">Docs</a></section>'));
      expect(
          out,
          contains('<section hidden="until-found" data-dv-anchor="2">'
              '<pre><code>dart pub get\ndartvel build web</code></pre>'
              '</section>'),
          reason: 'a multi-line code block is one section, lines intact');
      expect(_sections(out), hasLength(3));
    });

    test('a list is one section, which keeps it a valid list', () {
      final String out = dvApplyPageHtml(
          _page, '<ul>\n<li>Web</li>\n<li>Android</li>\n</ul>');
      expect(_sections(out), hasLength(1));
      expect(out, contains('<li>Web</li>'));
      expect(out.indexOf('<section'), lessThan(out.indexOf('<ul>')));
    });

    test('the plain-text path is findable too', () {
      // Two entry points write the same block, and one of them not being
      // findable is how find goes missing on whichever pages take the other.
      final String out =
          dvApplyPageText(_page, <String>['Invoice', 'Paid in full.']);
      expect(_sections(out), hasLength(2));
      expect(
          out,
          contains('<section hidden="until-found" data-dv-anchor="1">'
              '<p>Paid in full.</p></section>'));
    });

    test('applying twice still writes one set of sections', () {
      final String once = dvApplyPageHtml(_page, '<h1>x</h1>\n<p>y</p>');
      expect(dvApplyPageHtml(once, '<h1>x</h1>\n<p>y</p>'), once);
    });

    test('text that happens to look like a tag is not a section', () {
      // Escaped by the time it is here; the scanner reads tags, not text.
      final String out =
          dvApplyPageText(_page, <String>['Use <section> for this']);
      expect(_sections(out), hasLength(1));
      expect(out, contains('&lt;section&gt;'));
    });
  });

  group('what the block already did still works', () {
    test('a printer is given every section, not the canvas', () {
      final String css = _css(dvApplyPageHtml(_page, '<h1>Invoice</h1>'));
      final String print = css.substring(css.indexOf('@media print'));
      expect(print, contains('flutter-view'));
      // An until-found section is not painted until something reveals it;
      // print has to reveal every one of them, and a browser that does not
      // know until-found treats the attribute as plain `hidden`.
      expect(print, contains('.dv-fallback [data-dv-anchor]'));
      expect(print, contains('content-visibility:visible!important'));
      expect(print, contains('display:block!important'));
      // And the block is a document again, not a 1px box.
      expect(print, contains('position:static!important'));
      expect(print, contains('clip-path:none!important'));
    });

    test('a reader with scripting off is shown the whole page', () {
      final String out = dvApplyPageHtml(_page, '<h1>Invoice</h1>');
      final RegExpMatch noscript = RegExp(
              r'<noscript class="dv-fallback-style"><style>(.*?)</style></noscript>')
          .firstMatch(out)!;
      final String css = noscript.group(1)!;
      expect(css, contains('.dv-fallback [data-dv-anchor]'));
      expect(css, contains('content-visibility:visible'));
      expect(css, contains('display:block'));
      expect(css, contains('clip-path:none'));
      expect(css, contains('position:static'));
    });

    test('the crawler still reads the words, and the checks still find them',
        () {
      final String out = dvApplyPageHtml(
          _page, '<h1>Invoice</h1>\n<p>Retention is seven years.</p>');
      // tool/ci's checks read the block up to its first </div>; a section is
      // not a div, so they still read all of it.
      final String block = RegExp(r'<div class="dv-fallback"[^>]*>(.*?)</div>',
              dotAll: true)
          .firstMatch(out)!
          .group(1)!;
      expect(block, contains('Retention is seven years.'));
    });

    test('the minifier keeps the attribute and the rules', () {
      final String page = dvMinifyHtml(dvApplyPageHtml(
          _page, '<h1>Invoice</h1>\n<p>Paid.</p>',
          path: '/invoice'));
      expect(page, contains('hidden="until-found"'));
      expect(page, contains('data-dv-anchor="1"'));
      expect(page, contains('clip-path:inset(50%)'));
      expect(page, contains('.dv-fallback [data-dv-anchor]'));
    });
  });
}
