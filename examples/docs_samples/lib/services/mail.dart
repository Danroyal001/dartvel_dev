import '../dartvel_client/dartvel_client.dart';

// docs:start mail-provider
void configureMail() {
  DV.Notifications.mail.useProvider(SmtpMailProvider(
    host: 'smtp.example.com',
    username: 'apikey',
    password: DV.Secrets.get('SMTP_PASSWORD'),
  ));
}
// docs:end

Future<void> sendMail() async {
  // docs:start mail-send
  await DV.Notifications.mail.send(const DVMailMessage(
    from: DVMailAddress('hello@example.com', name: 'Shop'),
    to: <DVMailAddress>[DVMailAddress('ada@example.com')],
    subject: 'Your order shipped',
    text: 'It arrives on Friday.',
  ));
  // docs:end
}

Future<void> notify() async {
  // docs:start notifications-send
  DV.Notifications.register(DVMemoryNotificationProvider());

  final DVNotificationDelivery delivery = await DV.Notifications.send(
    'user-1',
    const DVNotificationMessage(
      title: 'Order shipped',
      body: 'It arrives on Friday.',
      channels: <DVNotificationChannel>[DVNotificationChannel.inApp],
    ),
  );
  // docs:end
  DV.log('$delivery');
}
