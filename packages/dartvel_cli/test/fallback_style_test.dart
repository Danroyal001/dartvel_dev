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

  test('the style is inside the noscript block', () {
    // Outside it, the rules apply to the real application too -- and a
    // max-width on body would break every Dartvel app's own layout.
    final String out = dvApplyPageHtml(_page, '<h1>Hello</h1>');
    final int noscript = out.indexOf('<noscript>');
    final int style = out.indexOf('<style');
    final int close = out.indexOf('</noscript>');

    expect(noscript, greaterThanOrEqualTo(0));
    expect(style, greaterThan(noscript));
    expect(style, lessThan(close));
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
    final String once = dvApplyPageHtml(_page, '<h1>x</h1>');
    final String twice = dvApplyPageHtml(once, '<h1>x</h1>');
    expect('<style'.allMatches(twice).length, 1);
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
