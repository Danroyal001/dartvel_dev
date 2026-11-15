// A search box in the document the server sends has its own "x".
//
// The running app's search fields have a clear button (DVSearchClear in
// dartvel_flutter): shown while there is text, named "Clear search", which
// empties the field and keeps the focus in it, with Escape doing the same.
// The server-rendered document is the page before Flutter paints and the page
// for a reader with no scripting, and its search box has to behave the same:
// a native <input type="search">, and a clear button with the same name.
import 'package:dartvel_cli/src/build/semantic_html.dart';
import 'package:test/test.dart';

DVSemanticNode field(String label, {String type = 'search'}) =>
    DVSemanticNode(role: 'textbox', label: label, fieldType: type);

/// The "x" the running app drew. The document writes its own.
const DVSemanticNode capturedClear = DVSemanticNode(role: 'clear');

void main() {
  late String html;
  setUp(() {
    html = dvSemanticHtml(<DVSemanticNode>[field('Search'), capturedClear]);
  });

  test('a captured search field is a native search input', () {
    expect(html, contains('<input id="dv-field-1" type="search" '
        'name="Search" data-dv-field="Search"'));
  });

  test('it has a clear button: a real button, named "Clear search", with its '
      'tooltip, pointing at its field, and hidden while the field is empty',
      () {
    final RegExpMatch? button =
        RegExp(r'<button[^>]*class="dv-clear"[^>]*>([^<]*)</button>')
            .firstMatch(html);
    expect(button, isNotNull, reason: html);
    final String tag = button!.group(0)!;
    expect(tag, contains('type="button"'));
    expect(tag, contains('aria-label="Clear search"'));
    expect(tag, contains('title="Clear search"'));
    expect(tag, contains('aria-controls="dv-field-1"'));
    expect(tag, contains(' hidden'));
    expect(button.group(1), 'Clear search');
  });

  test('pressing it empties the field, tells the page, puts the focus back '
      'and hides itself', () {
    final String onclick = RegExp(r'<button[^>]*onclick="([^"]*)"')
        .firstMatch(html)!
        .group(1)!;
    expect(onclick, contains("getAttribute('aria-controls')"));
    expect(onclick, contains(".value=''"));
    expect(onclick, contains('.focus()'));
    expect(onclick, contains("new Event('input'"));
    expect(onclick, contains('hidden=true'));
  });

  test('typing shows the button; Escape with text clears it', () {
    final String input =
        RegExp(r'<input [^>]*>').firstMatch(html)!.group(0)!;
    expect(input, contains('oninput="'));
    expect(input, contains('.hidden=!this.value'));
    expect(input, contains('onkeydown="'));
    expect(input, contains("'Escape'"));
  });

  test('the "x" the app drew is not written a second time', () {
    expect(RegExp('class="dv-clear"').allMatches(html), hasLength(1));
  });

  test('a field that is not a search field has no clear button', () {
    expect(dvSemanticHtml(<DVSemanticNode>[field('Name', type: 'text')]),
        isNot(contains('dv-clear')));
  });

  test('read from the capture: type="search" survives', () {
    final List<DVSemanticNode> nodes = DVSemanticNode.listFromJson(
        '[{"role":"textbox","label":"Search","field":"search"}]');
    expect(dvSemanticHtml(nodes), contains('type="search"'));
    expect(dvSemanticHtml(nodes), contains('class="dv-clear"'));
  });
}
