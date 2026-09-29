// One page renderer for both ways a Dartvel site is served.
//
// The web-server binary used to render a route from plain lines guessed out
// of the source and never minified it, while `dartvel build web` used the
// captured semantics tree and minified every file. /docs/ai served 0 links,
// 0 headings and 0 code blocks to a crawler where the static build had 58,
// 12 and 4. dvRenderRoutePage is the one function both call.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String _shell = '<!DOCTYPE html>\n<html>\n  <head>\n    <meta charset="UTF-8">\n'
    '    <title>Site</title>\n  </head>\n  <body>\n    <script src="main.dart.js"></script>\n'
    '  </body>\n</html>\n';

const String _captured = '<main><h1>AI</h1><p>Ask the model.</p>'
    '<h2>Structured output</h2><p>Use <strong>schemas</strong>, see '
    '<a href="/docs">the docs</a>.</p><pre><code>final x = 1;\n  final y = 2;</code></pre></main>';

int _count(String html, String tag) =>
    RegExp('<$tag[ >]').allMatches(html).length;

void main() {
  const DVRoutePage page = DVRoutePage(
    route: '/docs/ai',
    title: 'AI — Site',
    description: 'Models that answer.',
    siteUrl: 'https://example.com',
    siteName: 'Site',
    html: _captured,
    text: <String>['AI', 'Ask the model.'],
  );

  test('the captured document keeps its links, headings, emphasis and code', () {
    final String html = dvRenderRoutePage(_shell, page);
    expect(_count(html, 'a'), 1);
    expect(_count(html, 'h2'), 1);
    expect(_count(html, 'strong'), 1);
    expect(_count(html, 'pre'), 1);
    expect(_count(html, 'code'), 1);
    expect(html, contains('<a href="/docs">the docs</a>'));
    // A code block keeps its own line breaks and indentation.
    expect(html, contains('final x = 1;\n  final y = 2;'));
  });

  test('it is minified: no indentation left outside a code block', () {
    final String html = dvRenderRoutePage(_shell, page);
    final String outsidePre = html.replaceAll(RegExp(r'<pre[\s\S]*?</pre>'), '');
    expect(outsidePre, isNot(contains('\n  ')));
    expect(html.split('\n').length, lessThan(6));
    // And rendering is stable: minifying it again changes nothing.
    expect(dvMinifyHtml(html), html);
  });

  test('the head is the page\'s own', () {
    final String html = dvRenderRoutePage(_shell, page);
    expect(html, contains('<title>AI — Site</title>'));
    expect(html, contains('https://example.com/docs/ai'));
    expect(html, contains('Models that answer.'));
  });

  test('the source lines are the last resort, and it says when it used them', () {
    final List<String> told = <String>[];
    final String html = dvRenderRoutePage(
        _shell,
        const DVRoutePage(route: '/x', title: 'X', text: <String>['X', 'Some words.']),
        onUncaptured: told.add);
    expect(told, <String>['/x']);
    expect(html, contains('Some words.'));
  });

  test('a page read back from the manifest renders the same bytes', () {
    final DVRoutePage back = DVRoutePage.fromJson(page.toJson());
    expect(dvRenderRoutePage(_shell, back), dvRenderRoutePage(_shell, page));
  });

  test('a route that asks not to be indexed says so in its own head', () {
    // Studio's pages are routes of the application, rendered by this same
    // function, and nothing about an operator's screen belongs in a search
    // engine. A page that says nothing gets no robots tag at all.
    const DVRoutePage studio = DVRoutePage(
        route: '/__studio', title: 'Studio', robots: 'noindex, nofollow');
    final String html = dvRenderRoutePage(_shell, studio);
    expect(html, contains('<meta name="robots" content="noindex, nofollow">'));
    expect(dvRenderRoutePage(_shell, DVRoutePage.fromJson(studio.toJson())),
        html);
    expect(dvRenderRoutePage(_shell, page), isNot(contains('name="robots"')));
  });
}
