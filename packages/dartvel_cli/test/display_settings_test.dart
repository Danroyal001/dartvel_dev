// `dartvel: display:` in pubspec reaches the app as compile-time values.
//
// The app cannot read pubspec.yaml at run time, so the build hands the
// scaling and a declared screen class over as defines, the same way it hands
// over image variants. A typo must fail the build: a signage app that says
// `screen: bilboard` and silently draws at desktop size is the bug this
// setting exists to prevent.
import 'package:dartvel_cli/src/build/display_settings.dart';
import 'package:test/test.dart';

void main() {
  test('nothing declared, nothing passed: the app uses auto', () {
    expect(dvDisplayDefines(null), isEmpty);
    expect(dvDisplayDefines(<String, Object?>{}), isEmpty);
  });

  test('scaling and screen become defines', () {
    expect(
      dvDisplayDefines({
        'display': {'scaling': 'off', 'screen': 'billboard'},
      }),
      [
        '--dart-define=DARTVEL_DISPLAY_SCALING=off',
        '--dart-define=DARTVEL_SCREEN_CLASS=billboard',
      ],
    );
    expect(dvDisplayDefines({'display': {'scaling': 1.5}}), ['--dart-define=DARTVEL_DISPLAY_SCALING=1.5']);
    expect(dvDisplayDefines({'display': {'scaling': 'auto'}}), ['--dart-define=DARTVEL_DISPLAY_SCALING=auto']);
  });

  test('a value the app would not understand fails the build', () {
    expect(() => dvDisplayDefines({'display': {'screen': 'bilboard'}}), throwsA(isA<FormatException>()));
    expect(() => dvDisplayDefines({'display': {'scaling': 'big'}}), throwsA(isA<FormatException>()));
    expect(() => dvDisplayDefines({'display': {'scaling': 0}}), throwsA(isA<FormatException>()));
  });
}
