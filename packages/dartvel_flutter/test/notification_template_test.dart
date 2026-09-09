// A notification rendered in the recipient's language.
//
// The mail half exists; this is the other channels. DV.Notifications.send
// took a finished title and body, so an in-app or push notification to a
// French user said whatever the developer wrote in English. A template is
// translation keys, rendered strictly through DV.I18n for the recipient's
// locale -- a missing translation is an error, not a notification whose title
// is a key name.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

const DVTranslationKey titleKey = DVTranslationKey('notify.shipped.title');
const DVTranslationKey bodyKey = DVTranslationKey('notify.shipped.body');
const DVNotificationTemplate shipped = DVNotificationTemplate(title: titleKey, body: bodyKey);

void main() {
  late DVMemoryNotificationProvider outbox;

  setUp(() {
    outbox = DVMemoryNotificationProvider();
    DV.Notifications.register(outbox);
    DV.I18n.load(const DVTranslationCatalog(
      locale: LocaleTag.enUS,
      messages: <DVTranslationKey, String>{
        titleKey: 'Order shipped',
        bodyKey: 'Order {order} is on the way.',
      },
    ));
    DV.I18n.load(const DVTranslationCatalog(
      locale: LocaleTag('fr-FR'),
      messages: <DVTranslationKey, String>{
        titleKey: 'Commande expédiée',
        bodyKey: 'La commande {order} est en route.',
      },
    ));
  });

  test('renders in the locale asked for, with arguments', () async {
    await DV.Notifications.sendTemplate(
      'user-1',
      shipped,
      locale: const LocaleTag('fr-FR'),
      args: <String, String>{'order': '42'},
      channels: <DVNotificationChannel>[DVNotificationChannel.inApp],
    );

    expect(outbox.sent.single.recipient, 'user-1');
    expect(outbox.sent.single.message.title, 'Commande expédiée');
    expect(outbox.sent.single.message.body, 'La commande 42 est en route.');
    expect(outbox.sent.single.message.channels, <DVNotificationChannel>[DVNotificationChannel.inApp]);
  });

  test('a missing translation is an error, not a key name', () async {
    await expectLater(
      DV.Notifications.sendTemplate('user-1', shipped, locale: const LocaleTag('de-DE')),
      throwsA(isA<StateError>()),
    );
    expect(outbox.sent, isEmpty);
  });

  test('data travels with the message', () async {
    await DV.Notifications.sendTemplate(
      'user-1',
      shipped,
      locale: LocaleTag.enUS,
      args: <String, String>{'order': '42'},
      data: <String, String>{'orderId': '42'},
    );
    expect(outbox.sent.single.message.data, <String, String>{'orderId': '42'});
  });

  test('with no locale given, the current one is used', () async {
    DV.I18n.useLocale(const LocaleTag('fr-FR'));
    addTearDown(() => DV.I18n.useLocale(LocaleTag.enUS));
    await DV.Notifications.sendTemplate('user-1', shipped, args: <String, String>{'order': '1'});
    expect(outbox.sent.single.message.title, 'Commande expédiée');
  });

  // The channels argument travelled into the message and no further, so a
  // template asking for email reached the in-app provider instead. Now that
  // the channel picks its own provider, the translated subject has to arrive
  // as mail -- and the caller has to be able to see that it did, which a
  // Future<void> could not say.
  test('a template asking for email arrives as mail, translated', () async {
    final DVMemoryMailProvider mailbox = DVMemoryMailProvider();
    DV.Notifications.mail.useProvider(mailbox);
    DV.Notifications.useMailSender(const DVMailAddress('shop@example.com'));
    DV.Notifications.useRoutes(
      (String recipient) async =>
          const DVNotificationRoutes(email: DVMailAddress('ada@example.com')),
    );
    addTearDown(DV.Notifications.resetRouting);

    final DVNotificationDelivery delivery = await DV.Notifications.sendTemplate(
      'user-1',
      shipped,
      locale: const LocaleTag('fr-FR'),
      args: <String, String>{'order': '42'},
      channels: <DVNotificationChannel>[DVNotificationChannel.email],
    );

    expect(mailbox.sent.single.subject, 'Commande expédiée');
    expect(mailbox.sent.single.text, 'La commande 42 est en route.');
    expect(mailbox.sent.single.to.single.email, 'ada@example.com');
    expect(outbox.sent, isEmpty);
    expect(delivery.delivered,
        <DVNotificationChannel>{DVNotificationChannel.email});
  });
}
