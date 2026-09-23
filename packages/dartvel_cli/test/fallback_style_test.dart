// The no-script fallback needs a stylesheet, or it is a wall of text.
//
// The crawler-visible block is real semantic HTML -- headings, links, code
// blocks -- and it shipped with no CSS at all. Viewed with scripting off, or
// by anything that does not run the app, every line ran the full width of the
// window in the browser's default serif at whatever size it defaults to.
//
// It costs a few hundred bytes inline. There is no case where a page wants
// its fallback unreadable.
import 'package:dartvel_cli/src/build/page_text.dart';
import 'package:test/test.dart';

const String _page = '<html><head></head><body></body></html>';

void main() {
  test('the fallback carries a stylesheet', () {
    final String out = dvApplyPageHtml(_page, '<h1>Hello</h1>');
    expect(out, contains('<style'));
    // The one thing that decides whether it is readable.
    expect(out, contains('max-width'));
  });

  test('no rule in it can reach the running application', () {
    // It used to be kept inside the noscript block for this, and cannot be
    // any more: content a printer must reach has to be in the document. What
    // kept the application safe was never the noscript wrapper but the
    // scope -- a bare `max-width` on `body` would break every Dartvel app's
    // own layout, and nothing here sets one.
    final String out = dvApplyPageHtml(_page, '<h1>Hello</h1>');
    final int opens = out.indexOf('<style class="dv-fallback-style">');
    final String css = out.substring(
        out.indexOf('>', opens) + 1, out.indexOf('</style>', opens));

    for (final String rule in css.split('}')) {
      final int brace = rule.indexOf('{');
      if (brace < 0) continue;
      final String selectors = rule.substring(0, brace).trim();
      if (selectors.startsWith('@') || selectors.isEmpty) continue;
      for (final String selector in selectors.split(',')) {
        expect(selector.trim(), anyOf(startsWith('.dv-fallback'), startsWith('flutter-view'), startsWith('flt-'), equals('canvas')),
            reason: 'a rule that is not scoped to the fallback reaches the app');
      }
    }
  });

  test('it follows the reader dark-mode setting', () {
    // A page that is white in a dark browser is the same failure as ignoring
    // reduced motion: the reader already answered the question.
    expect(dvApplyPageHtml(_page, '<h1>x</h1>'),
        contains('prefers-color-scheme'));
  });

  test('the plain-text fallback gets it too', () {
    // Two entry points write the same block, and only one having a
    // stylesheet is how it goes missing on whichever pages take the other
    // path.
    final String out = dvApplyPageText(_page, <String>['Title', 'Body']);
    expect(out, contains('max-width'));
  });

  test('rebuilding does not stack stylesheets', () {
    // A build runs many times in a working tree. Counting the style elements
    // says nothing now that the block carries two of them; that applying it
    // again changes nothing is the property that matters.
    final String once = dvApplyPageHtml(_page, '<h1>x</h1>');
    final String twice = dvApplyPageHtml(once, '<h1>x</h1>');
    expect(twice, once);
  });

  test('an empty fallback adds nothing at all', () {
    // No content means no block, and a stylesheet for a block that is not
    // there is bytes on every page for nothing.
    expect(dvApplyPageHtml(_page, '   '), isNot(contains('<style')));
  });

  test('the content still comes through unescaped', () {
    final String out = dvApplyPageHtml(_page, '<h1>Hello</h1>');
    expect(out, contains('<h1>Hello</h1>'));
  });
}
