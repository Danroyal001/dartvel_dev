// Owner, 20 Nov 2026, on dartvel.dev with scripting off: "What's that margin
// on the noscript version?" The document painted its dark background on its
// own 44rem reading column only, so the page around it stayed the browser's
// white, with the default 8px body margin on top. With no script the page
// itself takes the document's colours, light and dark, edge to edge.
import 'package:dartvel_core/src/web/page_text.dart';
import 'package:test/test.dart';

void main() {
  test('with no script the whole page takes the document background, with no body margin', () {
    expect(dvFallbackNoscriptCss, contains('html,body{margin:0;background:#fff}'));
    expect(dvFallbackNoscriptCss, contains('@media (prefers-color-scheme:dark){html,body{background:#0a0d13}}'));
  });

  test('the page colours match the reading column, so no band shows at its sides', () {
    expect(dvFallbackCss, contains('color:#0b1020;background:#fff}'));
    expect(dvFallbackCss, contains('.dv-fallback{color:#f2f5fa;background:#0a0d13}'));
  });

  test('a page whose app runs is not repainted: the page colours are only in the noscript style', () {
    expect(dvFallbackCss, isNot(contains('html,body{')));
    expect(dvFallbackStyle, contains('<noscript class="dv-fallback-style"><style>$dvFallbackNoscriptCss</style></noscript>'));
  });
}
