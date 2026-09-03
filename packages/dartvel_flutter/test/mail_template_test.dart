// A mail template rendered in the recipient's language.
//
// The i18n section promises localised mail and notification templates and
// the mail layer took a finished subject and body. So every application
// either sent English to everyone or built its own per-locale rendering
// beside the catalogue that already held the translations.
//
// A template is translation keys. Rendering it is DV.I18n.t for the chosen
// locale with the same argument interpolation a page uses. Strict: a missing
// translation for the recipient's locale is an error, because the silent
// alternative is an email whose subject is the key name.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

const DVTranslationKey subjectKey = DVTranslationKey('mail.welcome.subject');
const DVTranslationKey bodyKey = DVTranslationKey('mail.welcome.body');

const DVMailTemplate welcome = DVMailTemplate(subject: subjectKey, text: bodyKey);

void main() {
  late DVMemoryMailProvider outbox;

  setUp(() {
    outbox = DVMemoryMailProvider();
    DV.Notifications.mail.useProvider(outbox);
    DV.I18n.load(const DVTranslationCatalog(
      locale: LocaleTag.enUS,
      messages: <DVTranslationKey, String>{
        subjectKey: 'Welcome, {name}',
        bodyKey: 'Thanks for joining, {name}.',
      },
    ));
    DV.I18n.load(const DVTranslationCatalog(
      locale: LocaleTag('fr-FR'),
      messages: <DVTranslationKey, String>{
        subjectKey: 'Bienvenue, {name}',
        bodyKey: 'Merci de nous avoir rejoints, {name}.',
      },
    ));
  });

  const DVMailAddress from = DVMailAddress('support@example.com');

  test('renders in the locale asked for, with arguments', () async {
    await DV.Notifications.mail.sendTemplate(
      welcome,
      from: from,
      to: <DVMailAddress>[const DVMailAddress('ada@example.com')],
      locale: const LocaleTag('fr-FR'),
      args: <String, String>{'name': 'Ada'},
    );

    expect(outbox.sent.single.subject, 'Bienvenue, Ada');
    expect(outbox.sent.single.text, 'Merci de nous avoir rejoints, Ada.');
  });

  test('a missing translation for that locale is an error, not a key name',
      () async {
    // 'mail.welcome.subject' as a subject line, to a real customer, is the
    // failure that would otherwise ship.
    await expectLater(
      DV.Notifications.mail.sendTemplate(
        welcome,
        from: from,
        to: <DVMailAddress>[const DVMailAddress('x@example.com')],
        locale: const LocaleTag('de-DE'),
      ),
      throwsA(isA<StateError>()),
    );
    expect(outbox.sent, isEmpty);
  });

  test('recipients in different locales each get their own message', () async {
    await DV.Notifications.mail.sendTemplateTo(
      welcome,
      from: from,
      recipients: <DVMailAddress, LocaleTag>{
        const DVMailAddress('ada@example.com'): const LocaleTag('fr-FR'),
        const DVMailAddress('bob@example.com'): LocaleTag.enUS,
        const DVMailAddress('cleo@example.com'): const LocaleTag('fr-FR'),
      },
      args: <String, String>{'name': 'there'},
    );

    // One message per locale, not per recipient and not one for everyone.
    expect(outbox.sent, hasLength(2));
    final DVMailMessage french =
        outbox.sent.firstWhere((DVMailMessage m) => m.subject.startsWith('Bienvenue'));
    expect(french.to.map((DVMailAddress a) => a.email),
        containsAll(<String>['ada@example.com', 'cleo@example.com']));
    expect(french.to, hasLength(2));
  });

  test('an html body is rendered when the template has one', () async {
    const DVTranslationKey htmlKey = DVTranslationKey('mail.welcome.html');
    DV.I18n.load(const DVTranslationCatalog(
      locale: LocaleTag.enUS,
      messages: <DVTranslationKey, String>{
        subjectKey: 'Welcome',
        bodyKey: 'Thanks',
        htmlKey: '<p>Thanks, <b>{name}</b></p>',
      },
    ));
    await DV.Notifications.mail.sendTemplate(
      const DVMailTemplate(subject: subjectKey, text: bodyKey, html: htmlKey),
      from: from,
      to: <DVMailAddress>[const DVMailAddress('x@example.com')],
      locale: LocaleTag.enUS,
      args: <String, String>{'name': 'Ada'},
    );
    expect(outbox.sent.single.html, '<p>Thanks, <b>Ada</b></p>');
  });

  test('with no locale given, the current one is used', () async {
    DV.I18n.useLocale(const LocaleTag('fr-FR'));
    addTearDown(() => DV.I18n.useLocale(LocaleTag.enUS));
    await DV.Notifications.mail.sendTemplate(
      welcome,
      from: from,
      to: <DVMailAddress>[const DVMailAddress('x@example.com')],
      args: <String, String>{'name': 'Ada'},
    );
    expect(outbox.sent.single.subject, 'Bienvenue, Ada');
  });
}
