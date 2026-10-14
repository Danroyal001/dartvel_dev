// Studio's sign-in and setup, as the documents the server sends.
//
// They said what Studio is and nothing else: no field to type an address
// into, no password field, no eye. Before Flutter painted -- and for a reader
// whose browser never runs it -- the sign-in page was a heading and a
// paragraph. Now each carries the fields the app draws, under the same
// labels, so the app can take over what was typed, and the password fields
// carry the same eye.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/framework.dart';
import 'package:test/test.dart';

String _document(DVStudioScreenSpec screen) => dvStudioDocumentFor(
      DVStudioTarget(screen: screen),
      mount: '/__studio/${screen.id}',
      data: const DVStudioProjectData(),
      navigation: false,
    ).html;

/// The `<input>` named [label], or null.
String? _input(String html, String label) =>
    RegExp('<input[^>]*data-dv-field="$label"[^>]*>').firstMatch(html)?.group(0);

void main() {
  group('the sign-in document', () {
    final String html = _document(dvStudioSignInScreen);

    test('has an email field a password manager recognises', () {
      final String? email = _input(html, 'Email');
      expect(email, isNotNull, reason: html);
      expect(email, contains('type="email"'));
      expect(email, contains('autocomplete="username"'));
      expect(html, contains('<label for="${RegExp('id="([^"]+)"').firstMatch(email!)!.group(1)}">Email</label>'));
    });

    test('has a password field with the eye', () {
      final String? password = _input(html, 'Password');
      expect(password, isNotNull, reason: html);
      expect(password, contains('type="password"'));
      expect(password, contains('autocomplete="current-password"'));
      final String id = RegExp('id="([^"]+)"').firstMatch(password!)!.group(1)!;
      final String? eye =
          RegExp('<button[^>]*aria-controls="$id"[^>]*>').firstMatch(html)?.group(0);
      expect(eye, isNotNull, reason: html);
      expect(eye, contains('type="button"'));
      expect(eye, contains('aria-label="Show password"'));
      expect(eye, contains('title="Show password"'));
      expect(eye, contains('aria-pressed="false"'));
    });

    test('field ids are unique', () {
      final List<String> ids = RegExp(r'\bid="([^"]+)"')
          .allMatches(html)
          .map((RegExpMatch match) => match.group(1)!)
          .toList();
      expect(ids.toSet(), hasLength(ids.length));
    });
  });

  test('the setup document has the three fields the setup asks for, and an '
      'eye on each password', () {
    final String html = _document(dvStudioSetupScreen);
    expect(_input(html, 'The address it printed'), contains('type="email"'));
    expect(_input(html, 'The password it printed'), contains('type="password"'));
    expect(_input(html, 'A new password of your own'),
        contains('autocomplete="new-password"'));
    expect(RegExp('class="dv-reveal"').allMatches(html), hasLength(2));
  });

  test('other screens carry no fields: a screen is not a form', () {
    expect(_document(dvStudioScreens.first), isNot(contains('<input')));
  });

  test('with scripting off the eye is not drawn, since it could not work', () {
    expect(dvFallbackStyle, contains('.dv-reveal{display:none}'));
    // Inside the noscript block, not the stylesheet every reader gets.
    final int noscript = dvFallbackStyle.indexOf('<noscript');
    expect(dvFallbackStyle.indexOf('.dv-reveal{display:none}'),
        greaterThan(noscript));
  });
}
