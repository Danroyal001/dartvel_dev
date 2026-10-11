// The device half of push: one PushNotificationProvider over the `push.*`
// bindings that Android (FCM) and the browser (Web Push) each register.
//
// Two rules the tests hold it to. The permission prompt is a user action:
// starting the provider, which the generated runtime does at launch, must ask
// for nothing -- a prompt at first paint is how a site loses the permission
// for good. And a platform with no binding degrades rather than throws, which
// is the whole capability model.
import 'dart:async';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

const List<String> _names = <String>[
  'push.token',
  'push.unsubscribe',
  'push.drainMessages',
  'push.subscribeToTopic',
  'push.unsubscribeFromTopic',
  'permissions.request',
  'permissions.isGranted',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> calls;
  late List<Object?> arguments;
  late List<Map<String, Object?>> pending;
  late DVDevicePushProvider provider;

  void bind(String name, Object? Function(Object?) answer) {
    DVNativeBridge.register(name, (Object? args) {
      calls.add(name);
      arguments.add(args);
      return answer(args);
    });
  }

  setUp(() {
    calls = <String>[];
    arguments = <Object?>[];
    pending = <Map<String, Object?>>[];
    provider = DVDevicePushProvider(
      vapidPublicKey: 'BKey',
      pollInterval: Duration.zero, // no timer: tests poll explicitly
    );
  });

  tearDown(() async {
    await provider.dispose();
    for (final String name in _names) {
      DVNativeBridge.unregister(name);
    }
  });

  group('polling', () {
    test('starts only where the platform has a queue', () async {
      final DVDevicePushProvider timed = DVDevicePushProvider();
      await timed.initialize();
      expect(timed.isPolling, isFalse);
      await timed.dispose();
    });

    test('runs once the platform has one, and stops on dispose', () async {
      bind('push.drainMessages', (Object? _) => <Object?>[]);
      final DVDevicePushProvider timed = DVDevicePushProvider();
      await timed.initialize();
      expect(timed.isPolling, isTrue);
      await timed.dispose();
      expect(timed.isPolling, isFalse);
    });
  });

  group('permission', () {
    test('starting the provider asks for nothing', () async {
      bind('permissions.request', (Object? _) => true);
      bind('push.token', (Object? _) => 'tok');
      await provider.initialize();
      expect(calls, isNot(contains('permissions.request')));
    });

    test('requestPermission asks for the notifications permission', () async {
      bind('permissions.request', (Object? _) => true);
      await provider.requestPermission();
      expect(calls, <String>['permissions.request']);
      expect(arguments.single, <String, Object?>{'permission': 'notifications'});
    });

    test('a refusal is not an error', () async {
      bind('permissions.request', (Object? _) => false);
      await expectLater(provider.requestPermission(), completes);
    });

    test('with no binding it completes quietly', () async {
      await expectLater(provider.requestPermission(), completes);
    });
  });

  group('token', () {
    test('is whatever the platform binding hands back', () async {
      bind('push.token', (Object? _) => 'fcm-token-1');
      expect(await provider.getToken(), 'fcm-token-1');
    });

    test('carries the VAPID public key for the browser to subscribe with',
        () async {
      bind('push.token', (Object? _) => '{"endpoint":"https://p/1"}');
      await provider.getToken();
      expect(arguments.single, <String, Object?>{'vapidPublicKey': 'BKey'});
    });

    test('is null where no platform binding exists', () async {
      expect(await provider.getToken(), isNull);
    });

    test('an empty answer is no token', () async {
      bind('push.token', (Object? _) => '');
      expect(await provider.getToken(), isNull);
    });
  });

  group('messages', () {
    Map<String, Object?> message(String id, {bool opened = false}) =>
        <String, Object?>{
          'id': id,
          'title': 'Order shipped',
          'body': 'On the way',
          'data': <String, Object?>{'orderId': '42'},
          'receivedAt': 1760000000000,
          'opened': opened,
        };

    test('a received message reaches onMessage', () async {
      bind('push.drainMessages', (Object? _) => pending.toList());
      pending.add(message('m1'));
      final Future<PushNotification> next = provider.onMessage.first;
      await provider.poll();
      final PushNotification got = await next;
      expect(got.id, 'm1');
      expect(got.title, 'Order shipped');
      expect(got.body, 'On the way');
      expect(got.data, <String, Object?>{'orderId': '42'});
      expect(got.receivedAt.millisecondsSinceEpoch, 1760000000000);
    });

    test('a tapped notification reaches onMessageOpenedApp, not onMessage',
        () async {
      bind('push.drainMessages', (Object? _) => pending.toList());
      pending.add(message('m2', opened: true));
      final List<String> received = <String>[];
      final StreamSubscription<PushNotification> sub =
          provider.onMessage.listen((PushNotification n) => received.add(n.id));
      final Future<PushNotification> opened = provider.onMessageOpenedApp.first;
      await provider.poll();
      expect((await opened).id, 'm2');
      expect(received, isEmpty);
      await sub.cancel();
    });

    test('a message the bridge hands over twice is delivered once', () async {
      bind('push.drainMessages', (Object? _) => pending.toList());
      final List<String> received = <String>[];
      final StreamSubscription<PushNotification> sub =
          provider.onMessage.listen((PushNotification n) => received.add(n.id));
      pending.add(message('m3'));
      await provider.poll();
      await provider.poll();
      await Future<void>.delayed(Duration.zero);
      expect(received, <String>['m3']);
      await sub.cancel();
    });

    test('a malformed entry is skipped, not fatal to the rest', () async {
      bind('push.drainMessages', (Object? _) => <Object?>[
            'garbage',
            <String, Object?>{'no': 'id'},
            message('m4'),
          ]);
      final Future<PushNotification> next = provider.onMessage.first;
      await provider.poll();
      expect((await next).id, 'm4');
    });

    test('polling with no binding does nothing', () async {
      await expectLater(provider.poll(), completes);
    });
  });

  group('topics', () {
    test('subscribe and unsubscribe go to the platform', () async {
      bind('push.subscribeToTopic', (Object? _) => true);
      bind('push.unsubscribeFromTopic', (Object? _) => true);
      await provider.subscribeToTopic('news');
      await provider.unsubscribeFromTopic('news');
      expect(calls, <String>['push.subscribeToTopic', 'push.unsubscribeFromTopic']);
      expect(arguments.first, <String, Object?>{'topic': 'news'});
    });

    test('a platform with no topics says so rather than pretending', () async {
      // Web Push has no topics. Silently succeeding would leave the user
      // subscribed to nothing and the app believing otherwise.
      await expectLater(
          provider.subscribeToTopic('news'), throwsA(isA<UnsupportedError>()));
    });
  });

  test('unsubscribing deletes the registration', () async {
    bind('push.unsubscribe', (Object? _) => true);
    expect(await provider.unsubscribe(), isTrue);
    expect(calls, <String>['push.unsubscribe']);
  });
}
