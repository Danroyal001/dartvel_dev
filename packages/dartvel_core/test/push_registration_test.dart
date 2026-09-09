// The device side of push: getting a token, and handing it to routing.
//
// PushNotifications, PushNotificationProvider and LocalPushNotificationProvider
// live in lib/src/notifications/push.dart and were exported by nothing. The
// only file importing them was a test, reaching through package:dartvel_core/
// src/ to keep them covered -- so the API that registers a device, requests
// permission and subscribes to a topic existed, was tested, and could not be
// called by any application. The specification lists device token
// registration, topic subscriptions and token revocation as features; they
// were written and then left unreachable.
//
// This imports the public library only. If a name here cannot be resolved, an
// application cannot resolve it either, which is the whole point.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  test('a device can register and be handed a token', () async {
    final provider = LocalPushNotificationProvider();
    PushNotifications.setProvider(provider);

    await PushNotifications.initialize();
    await PushNotifications.requestPermission();
    final token = await PushNotifications.getToken();

    expect(token, isNotNull);
    expect(token, startsWith('local-'));
  });

  test('an incoming message reaches a listener through the manager', () async {
    final provider = LocalPushNotificationProvider();
    PushNotifications.setProvider(provider);

    final received = <String?>[];
    final subscription = PushNotifications.onMessage
        .listen((PushNotification n) => received.add(n.title));
    addTearDown(subscription.cancel);

    provider.simulateMessage(PushNotification(id: '1', title: 'Shipped'));
    await Future<void>.delayed(Duration.zero);

    expect(received, <String>['Shipped']);
  });

  test('the token it hands back is what routing sends to', () async {
    // The loop the two halves are meant to close: the device registers, the
    // application stores the token, and DV.Notifications resolves a recipient
    // to it. Neither half is much use without the other being callable.
    const harness = DVTestHarness();
    harness.resetNotifications();
    const service = DVNotificationsService();

    PushNotifications.setProvider(LocalPushNotificationProvider());
    final token = (await PushNotifications.getToken())!;

    final delivered = <String>[];
    service.register(_CapturingPushProvider(delivered));
    service.useRoutes(
      (String recipient) async => DVNotificationRoutes(
        pushTokens: <String>[token],
      ),
    );
    addTearDown(service.resetRouting);

    await service.send(
      'user-1',
      const DVNotificationMessage(
        title: 'Order shipped',
        body: 'On the way',
        channels: <DVNotificationChannel>[DVNotificationChannel.push],
      ),
    );

    expect(delivered, <String>[token]);
  });
}

class _CapturingPushProvider implements DVNotificationProvider {
  _CapturingPushProvider(this.recipients);

  final List<String> recipients;

  @override
  DVNotificationProviderKind get kind => DVNotificationProviderKind.firebase;

  @override
  Future<void> send(String recipient, DVNotificationMessage message) async {
    recipients.add(recipient);
  }
}
