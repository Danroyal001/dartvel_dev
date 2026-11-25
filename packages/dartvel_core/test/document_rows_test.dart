// Lazy rows read from the server-rendered document. The build captures every
// page whole, and marks where each row of a lazy collection starts and ends
// (`<!-- dartvel:rows -->`, `<!-- dartvel:row -->`). After a navigation
// inside the app, a row the app has not built is read from that document --
// its links, headings and text -- instead of building its widgets.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  test('each collection, each row, its links, headings and text in order', () {
    const String doc = '<h1>Tools</h1>\n'
        '<!-- dartvel:rows -->'
        '<!-- dartvel:row --><section hidden="until-found" data-dv-anchor="1"><a href="https://qr.tools.example.com/" title="QR code" aria-label="QR code">QR code</a></section>'
        '<section hidden="until-found" data-dv-anchor="2"><p>Make a QR code &amp; print it.</p></section><!-- /dartvel:row -->'
        '<!-- dartvel:row --><section hidden="until-found" data-dv-anchor="3"><h3>Price <span id="dvr1">list</span></h3></section><!-- /dartvel:row -->'
        '<!-- /dartvel:rows -->'
        '<p>Between</p>'
        '<!--dartvel:rows--><!--dartvel:row--><p>Second list, row one</p><!--/dartvel:row--><!--/dartvel:rows-->';
    final List<DVDocumentCollection> collections = dvDocumentRows(doc);
    expect(collections, hasLength(2));
    expect(collections.first.rows, hasLength(2));
    final List<DVDocumentRowPart> first = collections.first.rows.first.parts;
    expect(first.map((DVDocumentRowPart p) => p.text), <String>['QR code', 'Make a QR code & print it.']);
    expect(first.first.href, 'https://qr.tools.example.com/');
    expect(first.last.href, isNull);
    expect(collections.first.rows[1].parts.single.text, 'Price list');
    expect(collections.first.rows[1].parts.single.headingLevel, 3);
    expect(collections[1].rows.single.parts.single.text, 'Second list, row one');
  });

  test('a collection inside a row is in that row: its words, and its rows for when the row is built', () {
    const String doc = '<!-- dartvel:rows --><!-- dartvel:row --><h2>Section</h2>'
        '<!-- dartvel:rows --><!-- dartvel:row --><p>Inner</p><!-- /dartvel:row --><!-- /dartvel:rows -->'
        '<!-- /dartvel:row --><!-- dartvel:row --><p>Next</p><!-- /dartvel:row --><!-- /dartvel:rows -->';
    final List<DVDocumentCollection> collections = dvDocumentRows(doc);
    expect(collections, hasLength(1));
    final DVDocumentRow outer = collections.single.rows.first;
    expect(outer.parts.map((DVDocumentRowPart p) => p.text), <String>['Section', 'Inner']);
    expect(outer.collections.single.rows.single.parts.single.text, 'Inner');
    expect(collections.single.rows[1].parts.single.text, 'Next');
    expect(collections.single.rows[1].collections, isEmpty);
  });

  test('what is hidden from readers, styles and scripts are not read', () {
    const String doc = '<!-- dartvel:rows --><!-- dartvel:row -->'
        '<div class="dvp" aria-hidden="true"><i id="dvp1"></i></div><style>a{color:red}</style>'
        '<script>x()</script><p>Kept</p><!-- /dartvel:row --><!-- /dartvel:rows -->';
    expect(dvDocumentRows(doc).single.rows.single.parts.map((DVDocumentRowPart p) => p.text), <String>['Kept']);
  });

  test('a document with no marks has no rows', () {
    expect(dvDocumentRows('<h1>Hi</h1><p>There</p>'), isEmpty);
  });

  test('the document in a page the server sent, between its text markers', () {
    const String page = '<html><body><!-- dartvel:text --><style>.dv-fallback{}</style>'
        '<div class="dv-fallback" data-dv-path="/tools"><p>Doc</p></div>\n<!-- /dartvel:text --><script>boot()</script></body></html>';
    expect(dvDocumentOfPage(page), '<p>Doc</p>');
    // The SSR-first layout's stylesheets and picture layer are for the first
    // paint, not for a copy kept for find: no image is fetched for it.
    const String laid = '<!-- dartvel:text --><div class="dv-fallback"><div class="dvl"><style class="dvl-style">a{}</style>'
        '<div class="dvp" aria-hidden="true"><img id="dvp0" src="assets/logo.png" alt=""></div><p>Doc</p>'
        '<style class="dvl-style">b{}</style></div></div>\n<!-- /dartvel:text -->';
    expect(dvDocumentOfPage(laid), '<div class="dvl"><p>Doc</p></div>');
    expect(dvDocumentOfPage('<html><body>nothing</body></html>'), isNull);
  });
}
