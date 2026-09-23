// What "this page has crawler-visible text" is measured from.
//
// The check has been wrong twice in one day, both times in the direction that
// reads as a pass: it counted the `<noscript>` element, which now holds one
// style rule and no page at all, and then it matched `<div
// class="dv-fallback">` exactly while the build had started stamping the
// path onto that tag. Either way every page answers "there is something
// there", or every page answers "there is nothing", and neither number is
// about the page.
import 'package:test/test.dart';

import '../../tool/ci/prerendered_pages_check.dart';

void main() {
  test('the page\'s own text, from the block the build writes', () {
    const String page = '<html><body>'
        '<!-- dartvel:text --><style class="dv-fallback-style">.a{}</style>'
        '<noscript class="dv-fallback-style"><style>.b{}</style></noscript>'
        '<div class="dv-fallback" data-dv-path="/docs">'
        '<h1>Documentation</h1><p>Read the docs.</p>'
        '</div><!-- /dartvel:text --></body></html>';

    expect(dvPageTextLength(page), greaterThan(20));
  });

  test('a block with no attributes is still the block', () {
    // A build that stamped no path, which is what a page written by the
    // plain-text path looks like.
    const String page =
        '<html><body><div class="dv-fallback"><h1>Home</h1></div></body></html>';

    expect(dvPageTextLength(page), greaterThan(0));
  });

  test('a page that renders only under JavaScript counts as nothing', () {
    const String page = '<html><body><div id="app"></div></body></html>';

    expect(dvPageTextLength(page), 0);
  });

  test('the style beside the block is not the page', () {
    // The noscript element survives, holding one rule that turns the block
    // back on. Counting it would pass every page in a build that stopped
    // writing text entirely.
    const String page = '<html><body>'
        '<noscript class="dv-fallback-style">'
        '<style>.dv-fallback{display:block}</style></noscript>'
        '</body></html>';

    expect(dvPageTextLength(page), 0);
  });
}
