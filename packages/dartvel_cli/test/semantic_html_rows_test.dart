// The rows of a lazy collection, marked in the document the build writes.
//
// While the build captures a page every lazy DVBox collection is built
// whole and marked in the semantics tree (identifiers dartvel:rows and
// dartvel:row). The document carries the marks as comments, so the running
// app can read a row it has not built from the document instead of building
// it (document_rows.dart in dartvel_core and dartvel_flutter). Nothing a
// reader, a crawler or a stylesheet sees changes.
import 'package:dartvel_cli/src/build/semantic_html.dart';
import 'package:dartvel_core/dartvel.dart' show dvDocumentRows;
import 'package:test/test.dart';

void main() {
  test('a collection and its rows are marked with comments around what they say', () {
    final String html = dvSemanticHtml(<DVSemanticNode>[
      const DVSemanticNode(label: 'Tools', headingLevel: 1),
      DVSemanticNode(role: 'rows', children: <DVSemanticNode>[
        for (int i = 0; i < 2; i++)
          DVSemanticNode(role: 'row', children: <DVSemanticNode>[
            DVSemanticNode(label: 'Tool $i', href: 'https://t$i.example.com/'),
            DVSemanticNode(label: 'Does thing $i'),
          ]),
      ]),
    ]);
    expect(html, contains('<!-- dartvel:rows -->'));
    expect(RegExp('<!-- dartvel:row -->').allMatches(html), hasLength(2));
    expect(html.replaceAll(RegExp(r'<!--.*?-->\n?'), '').trimRight(),
        '<h1>Tools</h1>\n'
        '<a href="https://t0.example.com/" title="Tool 0" aria-label="Tool 0">Tool 0</a>\n<p>Does thing 0</p>\n'
        '<a href="https://t1.example.com/" title="Tool 1" aria-label="Tool 1">Tool 1</a>\n<p>Does thing 1</p>',
        reason: 'the document is what it was, less the marks');
    final rows = dvDocumentRows(html).single.rows;
    expect(rows[1].parts.map((p) => p.text), <String>['Tool 1', 'Does thing 1']);
    expect(rows[1].parts.first.href, 'https://t1.example.com/');
  });

  test('a row that says something itself says it inside its marks', () {
    final String html = dvSemanticHtml(<DVSemanticNode>[
      const DVSemanticNode(role: 'rows', children: <DVSemanticNode>[
        DVSemanticNode(role: 'row', label: 'Merged row text'),
      ]),
    ]);
    expect(html, '<!-- dartvel:rows -->\n<!-- dartvel:row -->\n<p>Merged row text</p>\n<!-- /dartvel:row -->\n<!-- /dartvel:rows -->');
  });
}
