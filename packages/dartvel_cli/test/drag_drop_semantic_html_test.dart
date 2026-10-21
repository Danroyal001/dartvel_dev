import 'package:dartvel_cli/src/build/semantic_html.dart';
import 'package:test/test.dart';

void main() {
  test('a named drag surface keeps its tooltip and accessible name in HTML', () {
    final html = dvSemanticHtml(const [
      DVSemanticNode(role: 'hoverable', label: 'Drop "files" & links'),
    ]);
    expect(html, contains('title="Drop &quot;files&quot; &amp; links"'));
    expect(html, contains('aria-label="Drop &quot;files&quot; &amp; links"'));
    expect(html, contains('role="group"'));
    expect(html, isNot(contains('role="button"')));
  });

  test('a drag surface preserves the content and controls inside it', () {
    final html = dvSemanticHtml(const [
      DVSemanticNode(
        role: 'hoverable',
        label: 'Drop here',
        children: [
          DVSemanticNode(label: 'Files accepted'),
          DVSemanticNode(href: '/help', label: 'Drop help'),
        ],
      ),
    ]);
    expect(html, contains('title="Drop here" aria-label="Drop here"'));
    expect(html, contains('Files accepted'));
    expect(html, contains('<a href="/help"'));
  });
}
