// The fields of a form, in the document the server sends.
//
// A page's form used to vanish from its server-rendered HTML: the capture
// walked links, headings and Flutter's semantics nodes and skipped the
// <input> Flutter puts inside a text field's node, so a sign-in page went out
// as its heading and nothing else. A reader before Flutter painted, a reader
// with no scripting and a screen reader in the document all met a form with
// no fields. Now a field is a labelled input, and a password field carries the
// same eye the running app draws: a button named "Show password", with that
// name as its tooltip, and aria-pressed for whether the password is showing.
import 'package:dartvel_cli/src/build/semantic_html.dart';
import 'package:test/test.dart';

DVSemanticNode field(String label, {String type = 'text'}) =>
    DVSemanticNode(role: 'textbox', label: label, fieldType: type);

/// The eye the running app put beside a password field. The document writes
/// its own, so the captured one must not come out a second time.
const DVSemanticNode capturedEye = DVSemanticNode(role: 'reveal');

void main() {
  group('a captured text field', () {
    test('is a labelled input, named for the field it was', () {
      final String html = dvSemanticHtml(<DVSemanticNode>[field('Email', type: 'email')]);
      expect(html, contains('<label for="dv-field-1">Email</label>'));
      expect(html, contains('<input id="dv-field-1" type="email" name="Email" '
          'data-dv-field="Email"'));
    });

    test('a multi-line field is a textarea', () {
      final String html =
          dvSemanticHtml(<DVSemanticNode>[field('Notes', type: 'textarea')]);
      expect(html, contains('<textarea id="dv-field-1" name="Notes" '
          'data-dv-field="Notes"></textarea>'));
    });

    test('two fields get two ids', () {
      final String html = dvSemanticHtml(<DVSemanticNode>[
        field('Email', type: 'email'),
        field('Password', type: 'password'),
      ]);
      expect(html, contains('id="dv-field-1"'));
      expect(html, contains('id="dv-field-2"'));
    });

    test('a field with no name is not written: an input nobody can name is '
        'one a screen reader announces as "edit text"', () {
      expect(dvSemanticHtml(<DVSemanticNode>[field('')]), isEmpty);
    });

    test('its label is escaped', () {
      final String html = dvSemanticHtml(<DVSemanticNode>[field('"><script>')]);
      expect(html, isNot(contains('<script>')));
    });
  });

  group('a captured password field', () {
    late String html;
    setUp(() {
      html = dvSemanticHtml(<DVSemanticNode>[
        field('Password', type: 'password'),
        capturedEye,
      ]);
    });

    test('is a password input', () {
      expect(html, contains('<input id="dv-field-1" type="password" '
          'name="Password" data-dv-field="Password"'));
    });

    test('has the eye: a real button, named, with its tooltip, not pressed, '
        'pointing at the field it reveals', () {
      final RegExpMatch? button =
          RegExp(r'<button[^>]*class="dv-reveal"[^>]*>([^<]*)</button>')
              .firstMatch(html);
      expect(button, isNotNull, reason: html);
      final String tag = button!.group(0)!;
      expect(tag, contains('type="button"'));
      expect(tag, contains('aria-label="Show password"'));
      expect(tag, contains('title="Show password"'));
      expect(tag, contains('aria-pressed="false"'));
      expect(tag, contains('aria-controls="dv-field-1"'));
      // A name in the document too, for a reader with no styles.
      expect(button.group(1), 'Show password');
    });

    test('pressing it flips the field and the pressed state', () {
      final String onclick =
          RegExp(r'onclick="([^"]*)"').firstMatch(html)!.group(1)!;
      expect(onclick, contains("getAttribute('aria-controls')"));
      expect(onclick, contains("'password'"));
      expect(onclick, contains("setAttribute('aria-pressed'"));
    });

    test('the eye the app drew is not written a second time', () {
      expect(RegExp('class="dv-reveal"').allMatches(html), hasLength(1));
    });
  });

  test('a captured eye with no field before it writes nothing', () {
    expect(dvSemanticHtml(const <DVSemanticNode>[capturedEye]), isEmpty);
  });

  test('read from the capture: a textbox node keeps its field type', () {
    final List<DVSemanticNode> nodes = DVSemanticNode.listFromJson(
        '[{"role":"textbox","label":"Password","field":"password"}]');
    expect(nodes.single.fieldType, 'password');
    expect(dvSemanticHtml(nodes), contains('type="password"'));
  });
}
