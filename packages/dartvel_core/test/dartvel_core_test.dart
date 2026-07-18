import 'dart:convert';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('Res', () {
    test('json creates correct response', () async {
      final data = {'message': 'hello'};
      final res = Res.json(data);
      expect(res.status, 200);
      expect(res.headers.get('content-type'), contains('application/json'));

      final body = await res.body!.text();
      expect(jsonDecode(body), data);
    });

    test('text creates correct response', () async {
      final text = 'hello world';
      final res = Res.text(text);
      expect(res.status, 200);
      final body = await res.body!.text();
      expect(body, text);
    });

    test('notFound creates 404 response', () async {
      final res = Res.notFound();
      expect(res.status, 404);
      final body = await res.body!.text();
      expect(body, 'Not found');
    });

    test('notFound with message', () async {
      final res = Res.notFound('Custom error');
      expect(res.status, 404);
      final body = await res.body!.text();
      expect(body, 'Custom error');
    });
  });

  group('DVCSRF', () {
    test('generates non-empty random-looking tokens', () {
      const csrf = DVCSRF();
      final first = csrf.token();
      final second = csrf.token();

      expect(first, hasLength(greaterThanOrEqualTo(32)));
      expect(second, hasLength(greaterThanOrEqualTo(32)));
      expect(first, isNot(second));
      expect(csrf.validate(first), isTrue);
    });

    test('validates unsafe requests with matching tokens', () {
      const csrf = DVCSRF();
      final token = csrf.token();

      expect(
        csrf.validateRequest(
          method: 'POST',
          headerToken: token,
          bodyToken: token,
        ),
        isTrue,
      );
      expect(
        csrf.validateRequest(method: 'POST', headerToken: null),
        isFalse,
      );
      expect(
        csrf.validateRequest(
          method: 'POST',
          headerToken: token,
          bodyToken: '${token}x',
        ),
        isFalse,
      );
      expect(
        csrf.validateRequest(method: 'GET', headerToken: null),
        isTrue,
      );
    });
  });

  group('Queues, signals, messaging, and policies', () {
    test('queues dispatch and run typed jobs', () async {
      const harness = DVTestHarness();
      harness.resetQueues();
      final processed = <String>[];

      const queues = DVQueues();
      queues.register<String>((payload) {
        processed.add(payload);
      });

      final envelope = await queues.dispatch<String>('welcome-email');
      expect(envelope.queue, 'default');

      expect(await queues.work(), 1);
      expect(processed, ['welcome-email']);
      expect(await queues.pending(), isEmpty);
    });

    test('signal payloads use queues for background delivery', () async {
      const harness = DVTestHarness();
      harness.resetSignals();

      const queues = DVQueues();
      final delivered = <int>[];
      queues.register<int>(delivered.add);

      await queues.dispatch<int>(42, queue: 'signals');
      expect(await queues.work(queue: 'signals'), 1);

      expect(delivered, [42]);
    });

    test('mail and notifications use concrete local providers', () async {
      final mailProvider = DVMemoryMailProvider();
      const mail = DVNotificationMail();
      mail.useProvider(mailProvider);

      await mail.send(
        const DVMailMessage(
          from: DVMailAddress('system@example.com'),
          to: <DVMailAddress>[DVMailAddress('user@example.com')],
          subject: 'Welcome',
          text: 'Hello',
        ),
      );
      expect(mailProvider.sent.single.subject, 'Welcome');

      final notificationProvider = DVMemoryNotificationProvider();
      const notifications = DVNotificationsService();
      notifications.register(notificationProvider);

      await notifications.send(
        'user-1',
        const DVNotificationMessage(title: 'Hi', body: 'Body'),
      );
      expect(notificationProvider.sent.single.recipient, 'user-1');
    });

    test('authorization and cache invalidation are typed', () async {
      const authz = DVAuthorization();
      authz.register<String, int>('view', (user, resource) {
        return user == 'admin' && resource == 7;
      });

      expect(await authz.can<String, int>('admin', 'view', 7), isTrue);
      expect(await authz.can<String, int>('guest', 'view', 7), isFalse);

      const invalidation = DVCacheTags();
      invalidation.tag('users:7', <String>['users', 'users:7']);
      expect(invalidation.keysForTag('users'), contains('users:7'));
      expect(invalidation.revalidateTag('users'), contains('users:7'));
      expect(invalidation.keysForTag('users'), isEmpty);
    });
  });
}
