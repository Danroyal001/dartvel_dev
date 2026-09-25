# dartvel_core, surface by surface

Each section shows the spelling an application uses (through `DV.*` and its
generated data models) and, where it differs, the one a pure-Dart file that
depends only on `dartvel_core` uses. Each ends with what is not built yet,
taken from
[`docs/spec-status.json`](https://github.com/Danroyal001/dartvel_dev/blob/main/docs/spec-status.json),
which is the authority when this page and it disagree.

Generated code comes from one place: `dartvel routes`, which `dartvel build`
and `dartvel dev` run before anything else. Annotated inputs are private
(`class _Article`), and application code names only what is generated from
them (`Article`).

- [Data models and records](#data-models-and-records)
- [Record history, soft delete and conflicts](#record-history-soft-delete-and-conflicts)
- [Privacy and retention](#privacy-and-retention)
- [Authentication](#authentication)
- [Authorization](#authorization)
- [Cache](#cache)
- [Jobs and queues](#jobs-and-queues)
- [Notifications and mail](#notifications-and-mail)
- [Outbound webhooks](#outbound-webhooks)
- [Offline store](#offline-store)
- [Logs, metrics, health and traces](#logs-metrics-health-and-traces)

## Data models and records

A data model declares its fields once. The generated class carries its own
persistence: `Article.all()`, `Article.find(key)`, `article.save()`,
`article.destroy()`, and `copyWith`. The key is the model's public path field
(a `slug`, for example) where it has one.

```dart
final Article article = Article(
  slug: 'hello-world',
  title: 'Hello, world',
  authorId: 'user-1',
  editorNotes: 'Check the title',
);
await article.save();

final Article? found = await Article.find('hello-world');
final List<Article> all = await Article.all();
```

Data that is not a data model — a saved report, an audit entry — goes through
the record operations, which say nothing about SQL. The same calls run on
SQLite, PostgreSQL, MySQL and an in-memory engine, and on a document database
once one is configured.

```dart
const DVRecordShape reports = DVRecordShape(
  collection: 'weekly_reports',
  key: 'id',
  fields: <String, DVFieldType>{
    'id': DVFieldType.text,
    'team': DVFieldType.text,
    'week': DVFieldType.integer,
  },
);

final DVRecordAdapter records = DV.Database.records; // const DVDatabase().records
await records.ensure(reports);
await records.insert('weekly_reports', <String, Object?>{
  'id': 'r-38', 'team': 'design', 'week': 38,
});

final List<Map<String, Object?>> recent = await records.find(
  'weekly_reports',
  where: DVFilter.compare('week', DVCompare.greaterOrEqual, 30),
  orderBy: const <DVSort>[DVSort('week', descending: true)],
  limit: 10,
);
```

The database is configured once per process:
`const DVDatabase().configure(SqliteDVDatabaseAdapter.file('app.db'))`, or
`DVPostgresDatabaseAdapter` / `DVMySqlDatabaseAdapter`.
`MemoryDVDatabaseAdapter` runs the subset of SQL the framework itself issues,
and throws naming any statement outside it rather than answering wrongly.

**Not built yet** (Storage-Neutral Records is Partial, steps 1 and 2 of five):
the table under every generated data model, and the framework's cache, queue,
auth, analytics and webhook stores, still write SQL; there is no MongoDB
engine. `DVMemoryRecordEngine` runs the record operations and refuses SQL, the
way a document database would, and is what to test against.

## Record history, soft delete and conflicts

Every generated data model is versioned. A save writes at the version it read,
and is refused with `DVConflictError` when the row moved in between, so two
people editing one record do not silently overwrite each other.

```dart
try {
  await article.save();
} on DVConflictError catch (conflict) {
  // Someone saved a newer version after this one was read.
  DV.log('stored version is ${conflict.actualVersion}');
}

// Replace the stored row on purpose.
await Article.save(article, onConflict: DVConflict.lastWriteWins);
```

History and soft delete are opt-in on the annotation:

```dart
@DVModel(history: DVHistory(keep: Duration(days: 365)), softDelete: true)
class _Article { /* ... */ }
```

```dart
final List<DVHistoryEntry> entries = await article.history();
await article.revert(to: entries.first); // a new change; nothing between is lost

await article.destroy();                  // hidden from find() and all()
await Article.withDeleted.find(article.slug);
await Article.restore(article.slug);      // visible again
```

A sensitive field (`@DVModel.sensitiveField()`) is recorded in history as
changed, never with its value. `@DVModel(version: false)` turns the version
check off for a model that genuinely does not need it.

**Not built yet** (Partial): a scheduled job that prunes history by `keep`,
so nothing in a generated application prunes it yet; reload-and-merge in a
generated form; a Studio history view; keeping soft-deleted rows out of search
indexes and sync; database-level atomic transactions.

## Privacy and retention

A data model that holds personal data says whose it is and how long it is
kept. The build stops on personal data no subject path reaches (DV-PRIVACY-001)
and warns on personal data without a retention (DV-PRIVACY-002).

```dart
@DVModel(
  subject: DVSubject.field('customerId'),
  retain: DVRetention.days(90, from: 'createdAt', then: DVRetention.anonymize),
)
class _SupportTicket { /* ... */ }
```

`DVSubject.self` marks a row that is the person; `DVSubject.through(column,
parent: 'Order')` reaches them through a parent row. `@DVModel.retain(years:,
because:)` marks a field a law requires to keep, which an erasure anonymizes
around rather than deletes.

```dart
final DVExportArchive archive = await DV.Privacy.export(subject: 'user-1042');

final DVErasureResult result = await DV.Privacy.erase(
  subject: 'user-1042',
  reason: 'Deletion request from the account page',
);
if (!result.complete) {
  // An adapter could not be reached; result.unreached names it.
}
```

Erasure resolves every row before deleting any, purges the erased rows'
history, and returns an HMAC-signed receipt that names the subject only by
pseudonym. `DV.Privacy` is configured by the generated server from
`DARTVEL_PRIVACY_KEY`, and throws naming the key where nothing configured it.
The CLI has the same operations: `dartvel privacy check`, `erase`, `export`,
and `retention --plan`, which reports what a sweep would do and changes
nothing.

**Not built yet** (Data Compliance and Lifecycle is Partial): retention and
deadline schedules the deployment declares (they are fixed); export as one
file per model plus referenced files; file storage, cache-tag and crash-report
erasure adapters; a Studio view.

## Authentication

`DV.Auth` in an application signs in, signs up, runs TOTP and recovery codes,
and lists and revokes sessions. This package holds what it runs on: account
providers, password hashing, sessions, one-time codes, OAuth 2, SAML, LDAP
(where `dart:io` exists), WebAuthn passkeys and Web3 sign-in.

`DVDatabaseAuthProvider` keeps accounts in the application's own database, in
`dv_accounts`, with a PBKDF2 hash rather than the password. A wrong password
and an unknown address get the same refusal, so a sign-in form cannot be used
to find out who has an account.

```dart
final DVDatabaseAuthProvider accounts =
    DVDatabaseAuthProvider(const DVDatabase().adapter);

await accounts.signUp('ada@example.com', 'a long passphrase', name: 'Ada');
try {
  await accounts.signIn('ada@example.com', 'wrong');
} on AuthException catch (refused) {
  // refused.failure == AuthFailure.invalidCredentials
}
```

`LocalAuthProvider` keeps accounts in memory, and forgets them on restart; it
is for tests and prototypes.

**Not built yet** (Authentication is Shipped): biometric sign-in, which is a
device capability tracked under the platform bindings.

## Authorization

Authorization is `DV.Auth.authorization`, and it is default-deny: an action
no policy answers for is refused, and the refusal is logged once with the
reason. Policies are declared as classes whose methods are the conventional
actions — `viewAny`, `view`, `create`, `update`, `delete`, `restore`,
`forceDelete`, `export`, `impersonate` — and the generator registers them.

```dart
@DVPolicy(Order)
class OrderPolicy {
  // A route has no order to pass, so the resource is nullable.
  bool view(DVSessionPrincipal? user, Order? order) => user != null;

  bool update(DVSessionPrincipal? user, Order? order) =>
      user != null && (order == null || order.ownerId == user.userId);
}
```

A route or backend function that declares `policy:` asks it on the server,
with the caller as a `DVSessionPrincipal`.

A check registered in code wins over a declared one, whichever ran first:

```dart
// const DVAuthAuthorization() in a pure-Dart file.
DV.Auth.authorization.register<Member, Order>(
  'update',
  (Member member, Order order) => order.ownerId == member.id,
);

final bool canEdit = await DV.Auth.authorization.canAction(
  member,
  'Order.update',
  resource: order,
);
```

`register` takes the bare action (`'update'`) and the resource type, and is
asked as `'Order.update'`. Checks are typed: asked with a caller or resource
of a type the check does not take, one is refused and the reason logged once,
so a policy written for `DVSessionPrincipal` does not answer for a client-side
`DVAuthUser`. An API key's scopes narrow what a policy allows and
never widen it.

**Not built yet** (Authorization is Shipped): the generated admin does not ask
`view` or `viewAny` before listing or opening a record, and a `find` for a
missing key answers without asking a policy.

## Cache

In an application:

```dart
final List<String> names = await DV.Cache.remember<List<String>>(
  'products:names',
  const Duration(minutes: 10),
  fetchProductNames, // runs only when the key is missing or expired
);
DV.Cache.tag('products:names', <String>['products']);

// A product changed: every key tagged "products" goes.
await DV.Cache.revalidateTag('products');
```

`DV.Cache` also has `get`, `set`, `delete`, `staleWhileRevalidate` and `lock`,
and `DV.Cache.configure(...)` takes an adapter from this package:
`DVMemoryCacheAdapter`, `DVDatabaseCacheAdapter`, `DVRedisCacheAdapter`,
`DVMemcachedCacheAdapter` or `DVDistributedCacheAdapter`. A pure-Dart file
uses an adapter's `read`, `write`, `remove` and `clear` directly, with
`const DVCacheTags()` for the tag index.

## Jobs and queues

A job is a private payload class and a private handler; the generator writes
the public `SendWelcomeEmail` with its own `dispatch()`, which carries the
settings the annotation declared.

```dart
@DVJob(queue: 'mail', maxAttempts: 5, backoffSeconds: 60)
class _SendWelcomeEmail {
  final String userId;
  const _SendWelcomeEmail({required this.userId});
}

@DVJob.handler()
Future<void> _handleSendWelcomeEmail(SendWelcomeEmail job) =>
    sendWelcomeEmail(job.userId);
```

```dart
await SendWelcomeEmail(userId: 'user-1').dispatch();
await SendWelcomeEmail(userId: 'user-2').dispatch(queue: 'priority-mail');
```

A worker drains a queue in its own process — `dartvel queue work --queue mail`,
or a server started with `DARTVEL_ROLE=worker` — and is not something a page
calls. What an application does is look at what failed:

```dart
for (final DVJobEnvelope<DVJobPayload> job in await DV.Jobs.deadLetters('mail')) {
  DV.log('${job.id} failed ${job.attempts} times: ${job.lastError}');
  await DV.Jobs.retry(job.id); // or DV.Jobs.discard(job.id)
}
```

Jobs survive a restart on a durable adapter:
`DV.Jobs.useAdapter(DVDatabaseQueueAdapter(DV.Database.adapter))`. The
others are `DVRedisQueueAdapter`, `DVSqsQueueAdapter`, `DVAmqpQueueAdapter`
(RabbitMQ), `DVPubSubQueueAdapter` and `DVKafkaQueueAdapter`, each verified in
CI against a real broker. A job carries the tenant it was dispatched under,
and its handler runs as that tenant.

**Not built yet** (Queues is Partial): delayed execution, an exponential
backoff schedule, concurrency limits, pause and resume, uniqueness and
idempotency keys, progress events and cancellation. `DVJobState.completed` is
never produced: a finished job is removed rather than marked.

## Notifications and mail

Mail is part of notifications: `DV.Notifications.mail`.

```dart
DV.Notifications.mail.useProvider(SmtpMailProvider(
  host: 'smtp.example.com',
  username: 'apikey',
  password: DV.Secrets.get('SMTP_PASSWORD'),
));

await DV.Notifications.mail.send(const DVMailMessage(
  from: DVMailAddress('hello@example.com', name: 'Shop'),
  to: <DVMailAddress>[DVMailAddress('ada@example.com')],
  subject: 'Your order shipped',
  text: 'It arrives on Friday.',
));
```

A notification names a recipient id and the channels to try. Each channel
picks its own provider, and the id is turned into the address that provider
needs by the resolver given to `useRoutes`:

```dart
DV.Notifications.useRoutes((String recipient) async => DVNotificationRoutes(
      email: DVMailAddress(await emailOf(recipient)),
      pushTokens: await pushTokensOf(recipient),
    ));

final DVNotificationDelivery delivery = await DV.Notifications.send(
  'user-1',
  const DVNotificationMessage(
    title: 'Order shipped',
    body: 'It arrives on Friday.',
    channels: <DVNotificationChannel>[
      DVNotificationChannel.push,
      DVNotificationChannel.email,
    ],
  ),
);
```

Push tries the registered native provider (`FirebasePushProvider`,
`ApnsPushProvider`) and falls back to `WebPushProvider` when none is registered
or the native one fails. Quiet hours hold push, web push and SMS only, because
holding an email drops it. `send` throws when nothing reached the recipient for
a reason other than their own preferences. For tests, `DVMemoryMailProvider`
and `DVMemoryNotificationProvider` keep what they were given.

**Not built yet** (Mail and Notifications is Partial): no push provider has
been exercised against a real APNs or FCM service (SMTP has, against a real
server); attachments and tags on `DVMailMessage`; bounce and delivery-receipt
webhooks; queued-by-default mail; a durable in-app inbox; server-side device
token storage. The windows, macos, linux, tizen and webos provider kinds have
no implementation behind them.

## Outbound webhooks

Events this application sends to its customers' servers: declared, signed,
delivered per endpoint in order, and recorded in the application database.

```dart
DV.Webhooks.declare(const DVWebhookEvent(
  'order.paid',
  sensitiveFields: <String>{'cardLast4'}, // stripped from every payload
));

await DV.Webhooks.subscribe(
  url: 'https://partner.example.com/hooks',
  events: <String>{'order.paid'},
  signingSecret: 'PARTNER_WEBHOOK_SECRET', // the name of a secret
);

await DV.Webhooks.emit('order.paid', <String, Object?>{'orderId': 'o-42'});
```

Endpoints must be HTTPS and are refused, at subscribe and at every attempt and
redirect, when they resolve to a private, loopback or metadata address. What
the receiving side runs to check a delivery is in this package too:

```dart
bool isGenuine(Map<String, String> headers, String body, String secret) =>
    DVWebhookSignature.verify(
      secret: secret,
      timestamp: headers['dartvel-webhook-timestamp']!,
      body: body,
      header: headers['dartvel-webhook-signature']!,
      tolerance: const Duration(minutes: 5),
    );
```

**Not built yet** (Outbound Webhooks is Partial): `@DVWebhookEvent`
declarations are not generated, so an undeclared event is caught at runtime
rather than at build; model lifecycle events are not wired; draining is
caller-driven, with no standing worker; `dartvel.webhooks` is not read from
`pubspec.yaml`; tenant is recorded but not enforced.

## Offline store

A data model that must work without a network says so, and says how a write
made offline is resolved when it reaches the server:

```dart
@DVModel(offline: DVConflict.lastWriteWins)
class _Dispatch {
  final String id;
  final String reference;
  final int quantity;
  const _Dispatch({required this.id, required this.reference, required this.quantity});
}
```

The generated model builds both sides from the same declaration, so the
device's store and the server's replay cannot drift apart:

```dart
// On the device.
final DVOfflineStore dispatches =
    Dispatch.offlineStore(SqliteDVDatabaseAdapter.file('device.db'));
await dispatches.ensureSchema();
await dispatches.write(<String, Object?>{'id': 'd1', 'reference': 'R-1', 'quantity': 2});

// On reconnect, against the server side of the same data model.
final DVReplayResult result =
    await dispatches.replay(Dispatch.offlineRemote(serverDatabase));
```

Every replayed write is put to the model's policy before anything is written,
and a permanent refusal is dead-lettered rather than retried forever.

**Not built yet** (Offline-First Models is Partial), and this is the larger
part: `Dispatch.find`, `save` and `watch` do not go through the local store,
so writing offline is still a call on the store rather than an ordinary save;
nothing carries replay over the network yet, so there is no endpoint and no
client remote; there is no IndexedDB store on web; signing out does not clear
the store; a reconnect does not trigger replay.

## Logs, metrics, health and traces

Server code imports `package:dartvel_core/dv.dart` for the same two names an
application has:

```dart
DV.log('Refund accepted', context: <String, Object?>{'orderId': 'o-42'});
DV.log('Gateway slow', level: DVLogLevel.warn, code: 'PAY-SLOW');

DV.ObservabilityAndLogging.metrics
    .counter('refunds_total', <String, String>{'currency': 'usd'})
    .increment();

DV.ObservabilityAndLogging.health.register('payments', () async =>
    await gatewayReachable() ? DVHealthResult.up() : DVHealthResult.down('no answer'));

final DVSpan span = DV.ObservabilityAndLogging.tracer.startSpan('reprice-basket');
try {
  // ...
} finally {
  span.end();
}
```

Keys that look like secrets are redacted from log context. Metrics are served
at `GET /metrics` as Prometheus text and health checks at `GET /health`, each
under a deadline. Tracing carries W3C Trace Context across the request
boundary.

`DV.log` keeps a bounded in-process buffer (`recentLogs`) and writes nowhere
else until it is given a sink, and nothing gives it one by default — not the
generated server either. Give it one at startup:

```dart
DV.ObservabilityAndLogging.useLogging(
  sinks: <DVLogSink>[DVJsonLinesSink(stdout.writeln)],
);
```

**Not built yet** (Monitoring and Observability is Partial): a default log
sink; an OTLP exporter, so spans stay in an in-process buffer served at
`/_dartvel/traces` when diagnostics endpoints are on and reach no collector;
profiling and structured diagnostics.
