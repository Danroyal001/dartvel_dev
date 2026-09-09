// DVNotificationMessage.channels was read by nothing.
//
// The spec's own example asks for email, push and in-app at once. The type
// carries the list, dartvel_flutter's sendTemplate takes a `channels:`
// argument and threads it into the constructor, and the flutter test suite
// asserts the field survived into the message. Then
// DVNotificationsService.send ignored it entirely: it looked up one provider
// by a `provider:` kind that defaulted to `local` and sent there. Asking for
// email and push delivered neither, and reported success.
//
// So this covers the routing that has to exist for the field to mean
// anything: a channel picks its own provider, a recipient id is resolved to
// the address that channel needs, preferences and quiet hours can suppress a
// channel, push falls back to Web Push, and a send that reached nobody says so
// instead of returning quietly.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class _Recorder {
  final List<DVHttpRequest> requests = <DVHttpRequest>[];
  DVHttpResponse response = const DVHttpResponse(statusCode: 200, body: '{}');

  Future<DVHttpResponse> send(DVHttpRequest request) async {
    requests.add(request);
    return response;
  }
}

/// A push provider that always fails, so the fallback path is reachable
/// without pretending a real service answered.
class _BrokenPushProvider implements DVNotificationProvider {
  _BrokenPushProvider(this.kind);

  @override
  final DVNotificationProviderKind kind;

  int calls = 0;

  @override
  Future<void> send(String recipient, DVNotificationMessage message) async {
    calls++;
    throw const DVPushProviderException('firebase', 'service unavailable',
        statusCode: 503);
  }
}

/// A recorder shaped like a provider, for the channels whose real providers
/// need credentials.
class _SpyProvider implements DVNotificationProvider {
  _SpyProvider(this.kind);

  @override
  final DVNotificationProviderKind kind;

  final List<DVSentNotification> sent = <DVSentNotification>[];

  @override
  Future<void> send(String recipient, DVNotificationMessage message) async {
    sent.add(DVSentNotification(recipient: recipient, message: message));
  }
}

const _message = DVNotificationMessage(
  title: 'Order shipped',
  body: 'Your order is on the way',
  channels: <DVNotificationChannel>[
    DVNotificationChannel.email,
    DVNotificationChannel.push,
    DVNotificationChannel.inApp,
  ],
);

void main() {
  const service = DVNotificationsService();
  const harness = DVTestHarness();

  late DVMemoryMailProvider mailbox;
  late DVMemoryNotificationProvider inbox;
  late DVWebPushKeyPair vapidKeys;
  late String subscription;

  setUp(() {
    // Seeded, so the encryption in the fallback path is deterministic.
    final random = Random(7);
    vapidKeys = DVWebPushKeyPair.generate(random);
    final browserKeys = DVWebPushKeyPair.generate(random);
    subscription = jsonEncode(<String, Object?>{
      'endpoint': 'https://push.example.test/subscription/abc',
      'keys': <String, String>{
        'p256dh': base64Url.encode(browserKeys.publicKey).replaceAll('=', ''),
        'auth': base64Url
            .encode(Uint8List.fromList(
                List<int>.generate(16, (int i) => (i * 7 + 3) & 0xff)))
            .replaceAll('=', ''),
      },
    });

    harness.resetNotifications();
    service.resetRouting();
    mailbox = harness.fakeMail();
    inbox = harness.fakeNotifications();
    service.useMailSender(const DVMailAddress('system@example.com'));
    DVObservability.metrics.reset();
  });

  group('a channel picks its own provider', () {
    test('email goes to the mail provider, not the in-app one', () async {
      service.useRoutes((String recipient) async => const DVNotificationRoutes(
            email: DVMailAddress('ada@example.com'),
          ));

      final delivery = await service.send(
        'user-1',
        const DVNotificationMessage(
          title: 'Order shipped',
          body: 'Your order is on the way',
          channels: <DVNotificationChannel>[DVNotificationChannel.email],
        ),
      );

      expect(mailbox.sent, hasLength(1));
      expect(mailbox.sent.single.subject, 'Order shipped');
      expect(mailbox.sent.single.text, 'Your order is on the way');
      expect(mailbox.sent.single.to.single.email, 'ada@example.com');
      expect(mailbox.sent.single.from.email, 'system@example.com');
      expect(inbox.sent, isEmpty,
          reason: 'the in-app provider was not one of the channels asked for');
      expect(delivery.delivered, <DVNotificationChannel>{
        DVNotificationChannel.email,
      });
    });

    test('push goes to the device token, not the user id', () async {
      final recorder = _Recorder();
      service.register(FirebasePushProvider(
        projectId: 'demo',
        accessToken: () async => 'token',
        transport: recorder.send,
      ));
      service.useRoutes((String recipient) async => const DVNotificationRoutes(
            pushTokens: <String>['device-token-1'],
          ));

      await service.send(
        'user-1',
        const DVNotificationMessage(
          title: 'Order shipped',
          body: 'On the way',
          channels: <DVNotificationChannel>[DVNotificationChannel.push],
        ),
      );

      expect(recorder.requests, hasLength(1));
      final body = jsonDecode(utf8.decode(recorder.requests.single.body))
          as Map<String, Object?>;
      final envelope = body['message']! as Map<String, Object?>;
      expect(envelope['token'], 'device-token-1',
          reason: 'sending the user id as a registration token is how a push '
              'silently reaches nobody');
    });

    test('several channels each deliver once', () async {
      final push = _SpyProvider(DVNotificationProviderKind.firebase);
      service.register(push);
      service.useRoutes((String recipient) async => const DVNotificationRoutes(
            email: DVMailAddress('ada@example.com'),
            pushTokens: <String>['device-token-1'],
          ));

      final delivery = await service.send('user-1', _message);

      expect(mailbox.sent, hasLength(1));
      expect(push.sent, hasLength(1));
      expect(inbox.sent, hasLength(1));
      expect(delivery.delivered, <DVNotificationChannel>{
        DVNotificationChannel.email,
        DVNotificationChannel.push,
        DVNotificationChannel.inApp,
      });
    });

    test('in-app addresses the recipient id when no route says otherwise',
        () async {
      await service.send(
        'user-1',
        const DVNotificationMessage(title: 'Hi', body: 'There'),
      );

      expect(inbox.sent.single.recipient, 'user-1');
    });
  });

  group('push falls back to web push', () {
    test('when no native push provider is registered', () async {
      final recorder = _Recorder();
      service.register(WebPushProvider(
        vapidKeys: vapidKeys,
        subject: 'mailto:ops@example.com',
        transport: recorder.send,
      ));
      service.useRoutes((String recipient) async => DVNotificationRoutes(
            webPushSubscriptions: <String>[subscription],
          ));

      final delivery = await service.send(
        'user-1',
        const DVNotificationMessage(
          title: 'Order shipped',
          body: 'On the way',
          channels: <DVNotificationChannel>[DVNotificationChannel.push],
        ),
      );

      expect(recorder.requests, hasLength(1));
      expect(delivery.delivered,
          contains(DVNotificationChannel.push));
      expect(
        delivery.attempts
            .where((DVNotificationAttempt a) =>
                a.outcome == DVNotificationOutcome.delivered)
            .single
            .provider,
        DVNotificationProviderKind.webPush,
      );
    });

    test('when the native provider fails, and the failure is still recorded',
        () async {
      final broken = _BrokenPushProvider(DVNotificationProviderKind.firebase);
      service.register(broken);
      final recorder = _Recorder();
      service.register(WebPushProvider(
        vapidKeys: vapidKeys,
        subject: 'mailto:ops@example.com',
        transport: recorder.send,
      ));
      service.useRoutes((String recipient) async => DVNotificationRoutes(
            pushTokens: const <String>['device-token-1'],
            webPushSubscriptions: <String>[subscription],
          ));

      final delivery = await service.send(
        'user-1',
        const DVNotificationMessage(
          title: 'Order shipped',
          body: 'On the way',
          channels: <DVNotificationChannel>[DVNotificationChannel.push],
        ),
      );

      expect(broken.calls, 1);
      expect(recorder.requests, hasLength(1));
      expect(delivery.delivered, contains(DVNotificationChannel.push));
      expect(
        delivery.attempts.map((DVNotificationAttempt a) => a.outcome),
        containsAll(<DVNotificationOutcome>[
          DVNotificationOutcome.failed,
          DVNotificationOutcome.delivered,
        ]),
        reason: 'a fallback that hides the first failure is how a broken push '
            'provider stays broken for months',
      );
    });

    test('a provider failure is counted where a scrape can see it', () async {
      service.register(_BrokenPushProvider(DVNotificationProviderKind.apns));
      service.useRoutes((String recipient) async => const DVNotificationRoutes(
            pushTokens: <String>['device-token-1'],
          ));

      await service.send(
        'user-1',
        const DVNotificationMessage(
          title: 'Order shipped',
          body: 'On the way',
          channels: <DVNotificationChannel>[
            DVNotificationChannel.push,
            DVNotificationChannel.inApp,
          ],
        ),
      );

      expect(
        DVObservability.metrics
            .counter('${dvMetricPrefix}notification_failures_total',
                <String, String>{'channel': 'push'})
            .value,
        1,
      );
    });
  });

  group('preferences', () {
    test('a muted channel is skipped without calling its provider', () async {
      service.useRoutes((String recipient) async => const DVNotificationRoutes(
            email: DVMailAddress('ada@example.com'),
          ));
      service.usePreferences(
        (String recipient) async => const DVNotificationPreferences(
          mutedChannels: <DVNotificationChannel>{DVNotificationChannel.email},
        ),
      );

      final delivery = await service.send(
        'user-1',
        const DVNotificationMessage(
          title: 'Order shipped',
          body: 'On the way',
          channels: <DVNotificationChannel>[
            DVNotificationChannel.email,
            DVNotificationChannel.inApp,
          ],
        ),
      );

      expect(mailbox.sent, isEmpty);
      expect(inbox.sent, hasLength(1));
      expect(
        delivery.attempts
            .firstWhere((DVNotificationAttempt a) =>
                a.channel == DVNotificationChannel.email)
            .outcome,
        DVNotificationOutcome.muted,
      );
    });

    test('an unsubscribed recipient gets nothing, and that is not an error',
        () async {
      service.usePreferences(
        (String recipient) async =>
            const DVNotificationPreferences(unsubscribed: true),
      );

      final delivery = await service.send(
        'user-1',
        const DVNotificationMessage(title: 'Hi', body: 'There'),
      );

      expect(inbox.sent, isEmpty);
      expect(delivery.delivered, isEmpty);
      expect(delivery.attempts.single.outcome, DVNotificationOutcome.muted);
    });
  });

  group('quiet hours', () {
    // 22:00 to 07:00 wraps midnight. A window compared as `from <= t && t < to`
    // is empty for every wrapping window, so quiet hours would silently never
    // apply -- and the only symptom is a phone buzzing at 3am.
    const night = DVQuietHours(
      from: Duration(hours: 22),
      to: Duration(hours: 7),
    );

    setUp(() {
      service.useRoutes((String recipient) async => const DVNotificationRoutes(
            email: DVMailAddress('ada@example.com'),
            pushTokens: <String>['device-token-1'],
          ));
      service.usePreferences(
        (String recipient) async =>
            const DVNotificationPreferences(quietHours: night),
      );
    });

    test('a window that wraps midnight covers both sides of it', () {
      expect(night.covers(DateTime.utc(2026, 1, 1, 23)), isTrue);
      expect(night.covers(DateTime.utc(2026, 1, 1, 2)), isTrue);
      expect(night.covers(DateTime.utc(2026, 1, 1, 12)), isFalse);
      expect(night.covers(DateTime.utc(2026, 1, 1, 7)), isFalse,
          reason: 'the end is exclusive, or a 07:00 alarm never fires');
    });

    test('the window is read in the recipient offset, not the server one', () {
      const tokyo = DVQuietHours(
        from: Duration(hours: 22),
        to: Duration(hours: 7),
        utcOffset: Duration(hours: 9),
      );
      // 14:00 UTC is 23:00 in Tokyo.
      expect(tokyo.covers(DateTime.utc(2026, 1, 1, 14)), isTrue);
      expect(tokyo.covers(DateTime.utc(2026, 1, 1, 23)), isFalse);
    });

    test('push is held during quiet hours', () async {
      final push = _SpyProvider(DVNotificationProviderKind.firebase);
      service.register(push);

      final delivery = await service.send(
        'user-1',
        const DVNotificationMessage(
          title: 'Order shipped',
          body: 'On the way',
          channels: <DVNotificationChannel>[DVNotificationChannel.push],
        ),
        now: DateTime.utc(2026, 1, 1, 23),
      );

      expect(push.sent, isEmpty);
      expect(
          delivery.attempts.single.outcome, DVNotificationOutcome.quietHours);
    });

    test('email still goes out during quiet hours', () async {
      final delivery = await service.send(
        'user-1',
        const DVNotificationMessage(
          title: 'Order shipped',
          body: 'On the way',
          channels: <DVNotificationChannel>[DVNotificationChannel.email],
        ),
        now: DateTime.utc(2026, 1, 1, 23),
      );

      expect(mailbox.sent, hasLength(1),
          reason: 'quiet hours silence an interruption; holding the mail is '
              'losing the message, which is a different thing');
      expect(delivery.delivered, contains(DVNotificationChannel.email));
    });
  });

  group('a send that reached nobody says so', () {
    test('no provider for the only channel asked for throws', () async {
      harness.clearNotificationProviders();

      await expectLater(
        service.send(
          'user-1',
          const DVNotificationMessage(title: 'Missing', body: 'Provider'),
        ),
        throwsStateError,
      );
    });

    test('a channel with no route for the recipient throws', () async {
      service.useRoutes(
        (String recipient) async => const DVNotificationRoutes(),
      );

      await expectLater(
        service.send(
          'user-1',
          const DVNotificationMessage(
            title: 'Order shipped',
            body: 'On the way',
            channels: <DVNotificationChannel>[DVNotificationChannel.email],
          ),
        ),
        throwsA(isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          contains('email'),
        )),
      );
    });

    test('one channel delivering is enough to not throw', () async {
      service.useRoutes(
        (String recipient) async => const DVNotificationRoutes(),
      );

      final delivery = await service.send(
        'user-1',
        const DVNotificationMessage(
          title: 'Order shipped',
          body: 'On the way',
          channels: <DVNotificationChannel>[
            DVNotificationChannel.email,
            DVNotificationChannel.inApp,
          ],
        ),
      );

      expect(inbox.sent, hasLength(1));
      expect(
        delivery.attempts
            .firstWhere((DVNotificationAttempt a) =>
                a.channel == DVNotificationChannel.email)
            .outcome,
        DVNotificationOutcome.noRoute,
      );
    });

    test('an email channel with no configured sender is a configuration error',
        () async {
      service.resetRouting();
      service.useRoutes((String recipient) async => const DVNotificationRoutes(
            email: DVMailAddress('ada@example.com'),
          ));

      await expectLater(
        service.send(
          'user-1',
          const DVNotificationMessage(
            title: 'Order shipped',
            body: 'On the way',
            channels: <DVNotificationChannel>[DVNotificationChannel.email],
          ),
        ),
        throwsStateError,
      );
      expect(mailbox.sent, isEmpty);
    });
  });

  group('the explicit provider escape hatch', () {
    test('naming a provider bypasses channel routing', () async {
      final spy = _SpyProvider(DVNotificationProviderKind.sms);
      service.register(spy);

      await service.send(
        '+15551234567',
        _message,
        provider: DVNotificationProviderKind.sms,
      );

      expect(spy.sent.single.recipient, '+15551234567');
      expect(mailbox.sent, isEmpty);
      expect(inbox.sent, isEmpty);
    });
  });
}
