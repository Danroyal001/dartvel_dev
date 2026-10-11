import '../dartvel_client/dartvel_client.dart';

// docs:start push-send
void configurePush() {
  // The service-account key (FCM_SERVICE_ACCOUNT_JSON) and the VAPID private
  // key (VAPID_PRIVATE_KEY, VAPID_SUBJECT) are read from DV.Secrets.
  DV.Notifications.register(FirebasePushProvider.fromSecrets());
  DV.Notifications.register(WebPushProvider.fromSecrets());
}
// docs:end

// docs:start push-receive
Future<void> enablePush() async {
  // Called from a tap: starting push asks for nothing.
  await PushNotifications.requestPermission();
  final String? token = await PushNotifications.getToken();
  if (token != null) DV.log('push token ready');
  PushNotifications.onMessage.listen((PushNotification note) {
    DV.log('push: ${note.title}');
  });
}
// docs:end

// docs:start push-topic
Future<void> announce() async {
  final FirebasePushProvider fcm = FirebasePushProvider.fromSecrets();
  await fcm.sendTopic(
    'news',
    const DVNotificationMessage(title: 'New release', body: 'Version 2 is out.'),
  );
  await fcm.sendData('device-token', <String, String>{'sync': 'orders'});
}
// docs:end
