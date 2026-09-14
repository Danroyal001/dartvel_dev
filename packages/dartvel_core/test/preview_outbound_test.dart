// Preview Environments: a preview does not send anything to anybody.
//
// The hooks are in the paths an application already uses -- DV.Notifications
// mail, the notification providers, the scheduler -- rather than in a
// provider the preview is expected to register. A preview that captures only
// when the application remembered to swap its provider is a preview that
// mails a seeded address list the first time somebody forgets.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class RecordingMail implements DVMailProvider {
  final List<DVMailMessage> sent = <DVMailMessage>[];
  @override
  Future<void> send(DVMailMessage message) async => sent.add(message);
}

class RecordingPush implements DVNotificationProvider {
  final List<String> sent = <String>[];
  @override
  DVNotificationProviderKind get kind => DVNotificationProviderKind.firebase;
  @override
  Future<void> send(String recipient, DVNotificationMessage message) async =>
      sent.add(recipient);
}

const DVPreviewRuntime preview = DVPreviewRuntime(
  name: 'cart-c39f4dfa',
  visibility: DVPreviewVisibility.members,
  schedules: <String>{'nightly-report'},
);

DVMailMessage get message => const DVMailMessage(
      from: DVMailAddress('shop@example.com'),
      to: <DVMailAddress>[DVMailAddress('ada@example.com')],
      subject: 'Your order',
      text: 'Thanks',
    );

void main() {
  late List<DVPreviewFinding> findings;
  late RecordingMail mail;
  late RecordingPush push;

  setUp(() {
    findings = <DVPreviewFinding>[];
    mail = RecordingMail();
    push = RecordingPush();
    const DVNotificationMail().useProvider(mail);
    const DVNotificationsService().register(push);
  });

  tearDown(() {
    DVPreviewOutbound.deactivate();
    const DVNotificationsService().resetRouting();
  });

  group('mail', () {
    test('is captured, not sent, and reports DV-PREVIEW-006', () async {
      DVPreviewOutbound.activate(preview, onFinding: findings.add);
      await const DVNotificationMail().send(message);
      expect(mail.sent, isEmpty);
      expect(DVPreviewOutbound.mail.single.subject, 'Your order');
      expect(findings.single.code, 'DV-PREVIEW-006');
      expect(findings.single.message, isNot(contains('ada@example.com')),
          reason: 'a seeded address is still an address; the log is not the inbox');
    });

    test('a provider registered after the preview started does not send either',
        () async {
      DVPreviewOutbound.activate(preview, onFinding: findings.add);
      final RecordingMail late = RecordingMail();
      const DVNotificationMail().useProvider(late);
      await const DVNotificationMail().send(message);
      expect(late.sent, isEmpty);
      expect(DVPreviewOutbound.mail, hasLength(1));
    });

    test('routed email goes to the capture inbox', () async {
      DVPreviewOutbound.activate(preview, onFinding: findings.add);
      const DVNotificationsService().useMailSender(const DVMailAddress('shop@example.com'));
      await const DVNotificationsService().send(
        'u1',
        const DVNotificationMessage(
          title: 'Hi',
          body: 'There',
          channels: <DVNotificationChannel>[DVNotificationChannel.email],
        ),
        routes: const DVNotificationRoutes(email: DVMailAddress('ada@example.com')),
      );
      expect(mail.sent, isEmpty);
      expect(DVPreviewOutbound.mail, hasLength(1));
    });

    test('outside a preview mail is sent as it always was', () async {
      await const DVNotificationMail().send(message);
      expect(mail.sent, hasLength(1));
      expect(DVPreviewOutbound.mail, isEmpty);
    });
  });

  group('push', () {
    test('a named provider is not called', () async {
      DVPreviewOutbound.activate(preview, onFinding: findings.add);
      await const DVNotificationsService().send(
        'u1',
        const DVNotificationMessage(
          title: 'Hi',
          body: 'There',
          channels: <DVNotificationChannel>[DVNotificationChannel.push],
        ),
        provider: DVNotificationProviderKind.firebase,
      );
      expect(push.sent, isEmpty);
      expect(DVPreviewOutbound.notifications.single.recipient, 'u1');
      expect(findings.single.code, 'DV-PREVIEW-006');
    });

    test('a routed push reaches no device', () async {
      DVPreviewOutbound.activate(preview, onFinding: findings.add);
      await const DVNotificationsService().send(
        'u1',
        const DVNotificationMessage(
          title: 'Hi',
          body: 'There',
          channels: <DVNotificationChannel>[DVNotificationChannel.push],
        ),
        routes: const DVNotificationRoutes(pushTokens: <String>['device-token']),
      );
      expect(push.sent, isEmpty);
      expect(DVPreviewOutbound.notifications, hasLength(1));
    });

    test('outside a preview the provider is called', () async {
      await const DVNotificationsService().send(
        'u1',
        const DVNotificationMessage(title: 'Hi', body: 'There'),
        provider: DVNotificationProviderKind.firebase,
      );
      expect(push.sent, <String>['u1']);
    });
  });

  group('schedules', () {
    test('only declared schedules run, and the rest report DV-PREVIEW-008',
        () async {
      DateTime now = DateTime.utc(2026, 9, 5, 18);
      final DVScheduler scheduler = DVScheduler(clock: () => now);
      int digests = 0;
      int reports = 0;
      scheduler.register('weekly-digest', '* * * * *', () async => digests++);
      scheduler.register('nightly-report', '* * * * *', () async => reports++);
      DVPreviewOutbound.activate(preview, onFinding: findings.add);

      now = now.add(const Duration(minutes: 2));
      await scheduler.tick();
      now = now.add(const Duration(minutes: 1));
      await scheduler.tick();

      expect(digests, 0);
      expect(reports, 2);
      expect(findings.map((DVPreviewFinding f) => f.code).toSet(),
          <String>{'DV-PREVIEW-008'});
      expect(findings.first.message, contains('weekly-digest'));
    });

    test('outside a preview every schedule runs', () async {
      DateTime now = DateTime.utc(2026, 9, 5, 18);
      final DVScheduler scheduler = DVScheduler(clock: () => now);
      int digests = 0;
      scheduler.register('weekly-digest', '* * * * *', () async => digests++);
      now = now.add(const Duration(minutes: 2));
      await scheduler.tick();
      expect(digests, 1);
    });
  });
}
