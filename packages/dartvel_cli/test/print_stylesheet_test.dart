// A Dartvel page prints as the document it is, not as a screenshot of a
// canvas.
//
// Flutter web paints into a canvas, and a canvas prints as one bitmap the
// width of the window: one page, clipped, at screen resolution, with nothing
// the reader can select and no page breaks anywhere sensible. Every Dartvel
// build already writes the page's real HTML for crawlers and for readers with
// scripting off, and that is exactly what a printer should be given.
//
// Which is why the block cannot stay inside `<noscript>`. A browser that is
// running scripts does not parse noscript content into the document at all,
// so no stylesheet can reach it and no printer can see it. It goes in the
// document, hidden from the screen, and shown again for print and for a
// reader with no scripting.
import 'package:dartvel_cli/src/build/minify.dart';
import 'package:dartvel_cli/src/build/page_text.dart';
import 'package:test/test.dart';

const String _page = '<html><head></head><body></body></html>';

void main() {
  test('the printer gets the page, not the canvas', () {
    final String out = dvApplyPageHtml(_page, '<h1>Invoice</h1>');
    expect(out, contains('@media print'));
    // Whatever Flutter paints into is not what gets printed.
    expect(out, contains('flutter-view'));
    expect(out, contains('flt-glass-pane'));
    expect(out, contains('canvas'));
  });

  test('the block is in the document, where a printer can reach it', () {
    // Inside `<noscript>` this content is text, not elements, for every
    // browser that is running the app -- which is every browser somebody
    // prints from.
    final String out = dvApplyPageHtml(_page, '<h1>Invoice</h1>');
    final int heading = out.indexOf('<h1>Invoice</h1>');
    expect(heading, greaterThan(0));

    final int noscript = out.indexOf('<noscript>');
    if (noscript >= 0) {
      final int close = out.indexOf('</noscript>');
      expect(heading > noscript && heading < close, isFalse,
          reason: 'the printed content cannot sit inside a noscript block');
    }
  });

  test('the application keeps the screen to itself', () {
    // In the document and not on it: the reader sees the app, not the app
    // with its own outline printed above it.
    final String out = dvApplyPageHtml(_page, '<h1>Invoice</h1>');
    expect(out, contains('.dv-fallback{display:none}'));
  });

  test('a reader with no scripting is shown it', () {
    // The one thing noscript is still for: turning the block back on for the
    // reader whose browser will never run the app.
    final String out = dvApplyPageHtml(_page, '<h1>Invoice</h1>');
    expect(
        out,
        contains('<noscript class="dv-fallback-style">'
            '<style>.dv-fallback{display:block}</style></noscript>'));
  });

  test('print takes the reading column off and the ink down', () {
    final String out = dvApplyPageHtml(_page, '<h1>Invoice</h1>');
    final String print = out.substring(out.indexOf('@media print'));
    // A dark background prints as a solid rectangle of toner.
    expect(print, contains('background:#fff'));
    expect(print, contains('@page{margin:'));
  });

  test('a link prints its address, which a printed page cannot be clicked for',
      () {
    expect(dvApplyPageHtml(_page, '<a href="/x">x</a>'), contains('attr(href)'));
  });

  test('the block says which page it is', () {
    // Because the app routes on the client: after one navigation the block a
    // build wrote is the page the reader arrived on, not the page they are
    // looking at. Printing that is a worse answer than printing nothing, and
    // it is the kind that looks right.
    expect(dvApplyPageHtml(_page, '<h1>Invoice</h1>', path: '/invoice/12'),
        contains('<div class="dv-fallback" data-dv-path="/invoice/12">'));
    expect(dvApplyPageText(_page, <String>['Invoice'], path: '/invoice/12'),
        contains('data-dv-path="/invoice/12"'));
  });

  test('a page navigated away from is not the page to print', () {
    expect(dvFallbackIsStale('/invoice/12', '/invoice/13'), isTrue);
    expect(dvFallbackIsStale('/invoice/12', '/invoice/12'), isFalse);
    // The same page, written two ways.
    expect(dvFallbackIsStale('/docs/', '/docs'), isFalse);
    expect(dvFallbackIsStale('/', '/'), isFalse);
    // A build that stamped nothing gives nothing to compare, and a block
    // removed on a guess is a page that stops printing for no reason.
    expect(dvFallbackIsStale(null, '/x'), isFalse);
  });

  test('a page with no path stamps none', () {
    expect(dvApplyPageHtml(_page, '<h1>x</h1>'),
        contains('<div class="dv-fallback">'));
  });

  test('the style goes with the block it is for', () {
    // The rules that hide what Flutter paints into live in this style
    // element. Dropping a stale block has to drop them too, or print hides
    // the application and shows the empty space the block used to fill.
    final String out = dvApplyPageHtml(_page, '<h1>x</h1>', path: '/x');
    expect(out, contains('<style class="dv-fallback-style">'));
    expect(out, contains('<noscript class="dv-fallback-style">'));
  });

  test('the rules survive the minifier the build runs over them', () {
    // Both of these are new, and the one that shipped broken would be this:
    // a print stylesheet nobody looks at until they print, minified by a pass
    // that runs on every build.
    final String page = dvApplyPageHtml(_page, '<h1>x</h1>', path: '/x');
    final String small = dvMinifyHtml(page);

    // Or the assertions below pass on a string nothing happened to.
    expect(small.length, lessThan(page.length));
    expect(small, contains('.dv-fallback{display:none}'));
    expect(small, contains('@media print{'));
    expect(small, contains('content:" (" attr(href) ")"'));
    expect(small, contains('@page{margin:18mm}'));
    expect(small, contains('data-dv-path="/x"'));
    expect(small, contains('<noscript class="dv-fallback-style">'));
  });

  test('the plain-text fallback prints too', () {
    // Two entry points write the same block, and only one of them printing is
    // how it goes missing on whichever pages take the other path.
    final String out = dvApplyPageText(_page, <String>['Invoice', 'Paid']);
    expect(out, contains('@media print'));
    expect(out, contains('<h1>Invoice</h1>'));
  });
}
