// What dartvel_core does with no generated code and no Flutter.
//
//     dart run example/main.dart
//
// A Dartvel application reaches these through `DV.*` and its generated data
// models. This file uses the same classes directly, the way a backend
// function, a worker or a test does, so it runs from a clean checkout.
// example/README.md shows the generated side.

import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/dv.dart';

Future<void> main() async {
  // DV.log keeps a bounded buffer and writes nowhere else until it is given
  // a sink, and nothing gives it one by default. DVJsonLinesSink writes one
  // JSON object per line; this prints the message alone so the output reads
  // as prose.
  DV.ObservabilityAndLogging.useLogging(sinks: <DVLogSink>[_PrintMessages()]);

  await records();
  await accounts();
  await jobs();
  await authorization();
  await cache();
  await notifications();
  webhookSignatures();
}

/// Storage-neutral records: the same calls on SQLite, PostgreSQL, MySQL or a
/// document engine. The in-memory development database needs no server and
/// no native library; swap in `SqliteDVDatabaseAdapter.file(...)` for a real
/// one.
Future<void> records() async {
  const DVDatabase database = DVDatabase();
  database.configure(MemoryDVDatabaseAdapter());

  const DVRecordShape reports = DVRecordShape(
    collection: 'weekly_reports',
    key: 'id',
    fields: <String, DVFieldType>{
      'id': DVFieldType.text,
      'team': DVFieldType.text,
      'week': DVFieldType.integer,
      'signedOff': DVFieldType.boolean,
    },
  );

  final DVRecordAdapter records = database.records;
  await records.ensure(reports);
  await records.insert('weekly_reports', <String, Object?>{
    'id': 'r-38',
    'team': 'design',
    'week': 38,
    'signedOff': false,
  });

  // An optimistic write: the filter names what was read, so a second writer
  // who got there first leaves nothing to change, and nought is the conflict.
  Future<int> signOff() => records.update(
    'weekly_reports',
    <String, Object?>{'signedOff': true},
    where: DVFilter.all(<DVFilter>[
      DVFilter.equals('id', 'r-38'),
      DVFilter.equals('signedOff', false),
    ]),
  );

  DV.log('records: first sign-off changed ${await signOff()} row');
  DV.log('records: second sign-off changed ${await signOff()} rows');
}

/// Accounts kept in the application database, with PBKDF2 password hashes.
/// A wrong password and an unknown address get the same refusal, so a
/// sign-in form cannot be used to learn who has an account.
Future<void> accounts() async {
  final DVDatabaseAuthProvider accounts = DVDatabaseAuthProvider(
    MemoryDVDatabaseAdapter(),
  );

  final AuthUser? ada = await accounts.signUp(
    'Ada@example.com',
    'a long passphrase',
    name: 'Ada',
  );
  DV.log('accounts: signed up ${ada?.email}');

  for (final String email in <String>[
    'ada@example.com',
    'nobody@example.com',
  ]) {
    try {
      await accounts.signIn(email, 'not the passphrase');
    } on AuthException catch (refused) {
      DV.log('accounts: $email refused: ${refused.message}');
    }
  }
}

/// A typed payload. In an application this is generated from a private
/// `@DVJob` class, and carries its own `dispatch()`.
class WelcomeEmail {
  const WelcomeEmail(this.userId);

  final String userId;
}

/// Queues: dispatch a typed payload, and let a worker drain it.
Future<void> jobs() async {
  const DVQueues queues = DVQueues();

  queues.register<WelcomeEmail>((WelcomeEmail job) {
    DV.log('jobs: sending the welcome email to ${job.userId}');
  });

  await queues.dispatch(const WelcomeEmail('user-1'), queue: 'mail');
  await queues.dispatch(const WelcomeEmail('user-2'), queue: 'mail');

  // What `dartvel queue work --queue mail` does in a worker process.
  final int done = await queues.work(queue: 'mail', maxJobs: 10);
  DV.log(
    'jobs: $done completed, ${(await queues.pending('mail')).length} left',
  );
}

class Member {
  const Member(this.id);

  final String id;
}

class Order {
  const Order({required this.id, required this.ownerId});

  final String id;
  final String ownerId;
}

/// Authorization is default-deny: an action nobody registered is refused.
Future<void> authorization() async {
  const DVAuthAuthorization authorization = DVAuthAuthorization();

  authorization.register<Member, Order>(
    'update',
    (Member member, Order order) => order.ownerId == member.id,
  );

  const Order order = Order(id: 'o-1', ownerId: 'ada');
  final bool owner = await authorization.canAction(
    const Member('ada'),
    'Order.update',
    resource: order,
  );
  final bool stranger = await authorization.canAction(
    const Member('bob'),
    'Order.update',
    resource: order,
  );
  final bool unregistered = await authorization.canAction(
    const Member('ada'),
    'Order.refund',
    resource: order,
  );
  DV.log(
    'authorization: owner $owner, stranger $stranger, '
    'unregistered action $unregistered',
  );
}

/// A cache adapter and tag invalidation. `DV.Cache` in an application wraps
/// the configured adapter with remember, locks and stale-while-revalidate.
Future<void> cache() async {
  final DVMemoryCacheAdapter store = DVMemoryCacheAdapter();
  const DVCacheTags tags = DVCacheTags();

  await store.write('products:names', <String>[
    'Huila',
    'Yirgacheffe',
  ], const Duration(minutes: 10));
  tags.tag('products:names', <String>['products']);

  // A product changed: every key tagged "products" goes.
  for (final String key in tags.revalidateTag('products')) {
    await store.remove(key);
  }
  DV.log('cache: after revalidating, ${await store.read('products:names')}');
}

/// Notifications and mail. The memory providers keep what they were given,
/// which is what a test asserts on; production registers SMTP, SES, FCM,
/// APNs, Web Push or Twilio instead.
Future<void> notifications() async {
  const DVNotificationsService notifications = DVNotificationsService();
  final DVMemoryMailProvider mail = DVMemoryMailProvider();
  final DVMemoryNotificationProvider inApp = DVMemoryNotificationProvider();

  notifications.mail.useProvider(mail);
  notifications.register(inApp);
  notifications.useMailSender(const DVMailAddress('shop@example.com'));

  final DVNotificationDelivery delivery = await notifications.send(
    'user-1',
    const DVNotificationMessage(
      title: 'Order shipped',
      body: 'It arrives on Friday.',
      channels: <DVNotificationChannel>[
        DVNotificationChannel.inApp,
        DVNotificationChannel.email,
      ],
    ),
    routes: const DVNotificationRoutes(
      email: DVMailAddress('ada@example.com', name: 'Ada'),
    ),
  );
  DV.log('notifications: ${delivery.attempts.join(', ')}');
  DV.log(
    'notifications: mail to ${mail.sent.single.to.single.email}, '
    '${inApp.sent.length} in-app record',
  );
}

/// What a customer's server does with a delivery from `DV.Webhooks`.
void webhookSignatures() {
  const String secret = 'whsec_example';
  const String body = '{"event":"order.paid","orderId":"o-42"}';
  final String timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000)
      .toString();

  final String header = DVWebhookSignature.header(
    timestamp: timestamp,
    body: body,
    secrets: <String>[secret],
  );

  bool genuine(String received) => DVWebhookSignature.verify(
    secret: secret,
    timestamp: timestamp,
    body: received,
    header: header,
    tolerance: const Duration(minutes: 5),
  );

  DV.log(
    'webhooks: signed body verifies ${genuine(body)}, '
    'altered body verifies ${genuine('$body ')}',
  );
}

class _PrintMessages implements DVLogSink {
  @override
  void write(DVLogRecord record) => stdout.writeln(record.message);
}
