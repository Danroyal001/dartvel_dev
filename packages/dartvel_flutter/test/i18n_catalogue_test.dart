// The catalogue shape the spec documents has to compile.
//
// NEW_SPEC.md writes a catalogue as a const:
//
//   DV.I18n.load(const DVTranslationCatalog(
//     locale: LocaleTag.enUS,
//     messages: <DVTranslationKey, String>{AppText.settingsTitle: 'Settings'},
//   ));
//
// That did not compile. DVTranslationKey overrode == and hashCode, and Dart
// refuses a key without primitive equality in a const map: "The key
// 'DVTranslationKey {...}' does not have a primitive equality."
//
// So the documented way to write a catalogue was impossible, and the only way
// that worked was a non-const map -- which the generated catalogues the spec
// calls for could not use either.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Typed keys, exactly as the spec writes them.
class AppText {
  static const DVTranslationKey settingsTitle =
      DVTranslationKey('settings.title');
  static const DVTranslationKey inboxCount = DVTranslationKey('inbox.count');
}

void main() {
  setUp(() => const DVI18n().reset());

  test('a const catalogue compiles and resolves', () {
    // The whole point: this is a const map with DVTranslationKey keys.
    const DVTranslationCatalog catalogue = DVTranslationCatalog(
      locale: LocaleTag.enUS,
      messages: <DVTranslationKey, String>{
        AppText.settingsTitle: 'Settings',
      },
      plurals: <DVTranslationKey, DVPluralForms>{
        AppText.inboxCount: DVPluralForms(
          one: '{count} message',
          other: '{count} messages',
        ),
      },
    );

    const DVI18n i18n = DVI18n();
    i18n.load(catalogue);
    i18n.useLocale(LocaleTag.enUS);

    expect(i18n.t(AppText.settingsTitle), 'Settings');
    expect(i18n.plural(AppText.inboxCount, 1), '1 message');
    expect(i18n.plural(AppText.inboxCount, 4), '4 messages');
  });

  test('a key built at runtime resolves to the same entry', () {
    // Two keys with the same string are the same key. Without this, a key read
    // from a config file or a database column would miss every lookup and
    // silently render its own name.
    const DVI18n i18n = DVI18n();
    i18n.load(const DVTranslationCatalog(
      locale: LocaleTag.enUS,
      messages: <DVTranslationKey, String>{
        AppText.settingsTitle: 'Settings',
      },
    ));
    i18n.useLocale(LocaleTag.enUS);

    final DVTranslationKey runtime =
        const DVTranslationKey('settings.${'title'}');
    expect(i18n.t(runtime), 'Settings');
  });

  test('a missing key returns its own name rather than throwing', () {
    const DVI18n i18n = DVI18n();
    i18n.useLocale(LocaleTag.enUS);
    expect(i18n.t(const DVTranslationKey('nope')), 'nope');
  });

  test('strict mode names the key and the locale', () {
    // A build gate needs to say which string is missing where, not just that
    // something is.
    const DVI18n i18n = DVI18n();
    i18n.useLocale(LocaleTag.enUS);
    expect(
      () => i18n.t(const DVTranslationKey('nope'), strict: true),
      throwsA(isA<StateError>().having(
        (StateError e) => e.message,
        'message',
        allOf(contains('nope'), contains('en-US')),
      )),
    );
  });

  test('loading a second catalogue for a locale replaces the first', () {
    const DVI18n i18n = DVI18n();
    i18n.useLocale(LocaleTag.enUS);
    i18n.load(const DVTranslationCatalog(
      locale: LocaleTag.enUS,
      messages: <DVTranslationKey, String>{
        AppText.settingsTitle: 'Settings',
      },
    ));
    i18n.load(const DVTranslationCatalog(
      locale: LocaleTag.enUS,
      messages: <DVTranslationKey, String>{
        AppText.settingsTitle: 'Preferences',
      },
    ));
    expect(i18n.t(AppText.settingsTitle), 'Preferences');
  });
}
