# dartvel_core

The pure-Dart runtime of [Dartvel](https://dartvel.dev): the part that runs
the same on a phone, in a browser, on a server and inside the `dartvel`
command.

Data models and their records, history and retention; the database, cache and
queue adapters; authentication providers and the authorization registry; mail
and notifications; privacy erasure and export; outbound webhooks; the offline
store; logging, metrics and traces; and the HTTP wire types both sides of a
request share. Nothing here imports Flutter, so a `dartvel build web-server`
binary, a queue worker and the CLI can all depend on it.

## Who depends on it directly

Most people do not. An application depends on
[`dartvel_dev`](https://pub.dev/packages/dartvel_dev), which brings this in
together with the Flutter half, and reaches everything below through `DV.*`
and its generated data models:

| Package | What it adds on top of `dartvel_core` |
|---|---|
| [`dartvel_flutter`](https://pub.dev/packages/dartvel_flutter) | The application's `DV`: `DV.Auth`, `DV.Cache`, `DV.Jobs`, `DV.Notifications`, `DV.Privacy`, `DV.Webhooks`, `DV.FileStorage`, plus UI, routing, signals and `DV.Platform` |
| [`dartvel_cli`](https://pub.dev/packages/dartvel_cli) | The `dartvel` command, and the one code generator: `@DVModel`, `@DVJob` and `@DVPolicy` become code written against this package |
| [`dartvel_shelf`](https://pub.dev/packages/dartvel_shelf) | The Rust/Axum server, reached over FFI, speaking the `Request`/`Response`/`Headers` types defined here |

Depend on `dartvel_core` yourself when the code you are writing must not pull
in Flutter: a backend function, a queue worker, a tool, or a library that
other Dartvel projects will use. That code uses the same classes `DV.*` wraps,
constructed directly:

```dart
const DVQueues().dispatch(payload);            // DV.Jobs.dispatch(payload)
const DVAuthAuthorization().canAction(...);    // DV.Auth.authorization.canAction(...)
const DVNotificationsService().mail.send(...); // DV.Notifications.mail.send(...)
```

Server-side code has no `DV` of its own beyond logging (`DV.log` and
`DV.ObservabilityAndLogging`, from `package:dartvel_core/dv.dart`), so this
spelling is the one a pure-Dart file uses today.

## Install

```sh
dart pub add dartvel_core
```

Dart 3.13 or later, the floor every Dartvel package declares.

```dart
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/dv.dart'; // DV.log, for server-side code
```

HTTP/1.1 goes through `package:http`. HTTP/2 and HTTP/3 use a native client
built from this package's `rust/` crate by a build hook, which runs only when
`cargo` and `cbindgen` are on the `PATH` and skips with a message otherwise.
`SqliteDVDatabaseAdapter` loads the system SQLite library (`libsqlite3.so` on
Linux, from `libsqlite3-dev` or your distribution's equivalent).

## What is in it

The status column is copied from
[`docs/spec-status.json`](https://github.com/Danroyal001/dartvel_dev/blob/main/docs/spec-status.json)
as of this release: *Shipped* is built as specified; *Partial* means the
runtime described below works and the file lists, in writing, what does not
yet exist.

| Surface | In an application | Status |
|---|---|---|
| Data models: `@DVModel`, find/save/destroy, optimistic versions | `Article.find`, `article.save()` | Shipped |
| Storage-neutral records | `DV.Database.records` | Partial |
| Record history, soft delete, revert | `article.history()`, `Article.restore(id)` | Partial |
| Authentication providers, sessions, MFA, passkeys, SAML, LDAP | `DV.Auth` | Shipped |
| Authorization: policies, default deny | `DV.Auth.authorization` | Shipped |
| Cache: set, get, has, delete, clear, remember, tags, lock; the store named in `dartvel.cache` | `DV.Cache` | Partial |
| Queues and jobs, seven adapters | `DV.Jobs`, `@DVJob` | Partial |
| Mail and notifications | `DV.Notifications`, `DV.Notifications.mail` | Partial |
| Privacy: subject paths, retention, erasure, export | `DV.Privacy` | Partial |
| Outbound webhooks | `DV.Webhooks` | Partial |
| Offline data models | `@DVModel(offline: ...)`, then `save()` | Partial |
| Logs, metrics, health, traces | `DV.log`, `DV.ObservabilityAndLogging` | Partial |

The full list of what `dartvel.dart` exports is in the
[API reference](https://pub.dev/documentation/dartvel_core/latest/).
[`doc/surfaces.md`](https://github.com/Danroyal001/dartvel_dev/blob/main/packages/dartvel_core/doc/surfaces.md)
goes through each surface in more depth, including what is not built.

## Data models

A data model is a private class the generator reads. The public `Article` is
generated from it by `dartvel routes`, which `dartvel build` and `dartvel dev`
run first; application code names only the generated class.

```dart
@DVModel(
  history: DVHistory(keep: Duration(days: 365)),
  softDelete: true,
  subject: DVSubject.field('authorId'),
  retain: DVRetention.indefinite,
)
class const _Article({
  required final String slug,
  required final String title,
  required final String authorId,
  @DVModel.sensitiveField() required final String editorNotes,
});
```

```dart
final Article article = (await Article.find('hello-world'))!;
try {
  await article.copyWith(title: 'Hello again').save();
} on DVConflictError {
  // Someone saved a newer version after this one was read.
}

final List<DVHistoryEntry> entries = await article.history();
await article.revert(to: entries.first);
```

A save writes at the version it read, so two people editing the same record
cannot silently overwrite each other; the second is refused with
`DVConflictError` and decides. `DVConflict.lastWriteWins` replaces the stored
row on purpose. Sensitive fields are recorded in history as changed, never as
values.

## Jobs

```dart
@DVJob(queue: 'mail', maxAttempts: 5, backoffSeconds: 60)
class const _SendWelcomeEmail({required final String userId});

@DVJob.handler()
Future<void> _handleSendWelcomeEmail(SendWelcomeEmail job) =>
    sendWelcomeEmail(job.userId);
```

```dart
await SendWelcomeEmail(userId: 'user-1').dispatch();
```

A worker is a process, not a line in a page: `dartvel queue work --queue mail`
runs it. Without the generator, the same queue is `const DVQueues()`:
`register<T>(handler)`, `dispatch(payload, queue: ...)` and `work(queue: ...)`.
The in-memory adapter is the default; `DVDatabaseQueueAdapter`,
`DVRedisQueueAdapter`, `DVSqsQueueAdapter`, `DVAmqpQueueAdapter`,
`DVPubSubQueueAdapter` and `DVKafkaQueueAdapter` survive a restart.

## Authorization

Every check is default-deny: an action nobody registered a policy for is
refused, and the refusal is logged once with the reason. A policy class is
registered by the generator, and a route or backend function that declares
`policy:` asks it on the server with the caller as a `DVSessionPrincipal`:

```dart
@DVPolicy(Order)
class OrderPolicy {
  // A route has no order to pass, so the resource is nullable.
  bool update(DVSessionPrincipal? user, Order? order) =>
      user != null && (order == null || order.ownerId == user.userId);
}
```

A check can also be registered and asked in code. It is typed: asked with a
caller or resource of another type, it refuses and says why, rather than
casting.

```dart
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

## Notifications and mail

```dart
DV.Notifications.mail.useProvider(SmtpMailProvider(
  host: 'smtp.example.com',
  username: 'apikey',
  password: DV.Secrets.get('SMTP_PASSWORD'),
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

Where each recipient can be reached, per channel, comes from
`DV.Notifications.useRoutes(...)`, and what they asked to receive from
`usePreferences(...)`. `send` returns what happened on each channel, so a push
held for quiet hours and one that had nowhere to go are different answers;
when nothing reached the recipient for any reason other than their own
preferences, it throws rather than reporting success. Mail providers: SMTP,
SES, Resend, SendGrid, Postmark and Mailgun. Push: FCM, APNs, Web Push (also
the fallback when native push fails), and Twilio for SMS.

## Running the example

[`example/main.dart`](https://github.com/Danroyal001/dartvel_dev/blob/main/packages/dartvel_core/example/main.dart) runs with no generated code and no
Flutter: records with an optimistic write, database-backed accounts, a queue
drained by a worker, a policy check, cache tag invalidation, a notification on
two channels, and webhook signature verification.

```sh
dart run example/main.dart
```

[`example/README.md`](https://github.com/Danroyal001/dartvel_dev/blob/main/packages/dartvel_core/example/README.md) shows the generated side.

## Links

- [API reference](https://pub.dev/documentation/dartvel_core/latest/)
- [Documentation](https://dartvel.dev/docs)
- [Repository](https://github.com/Danroyal001/dartvel_dev), with this package
  under `packages/dartvel_core`
- [Specification status](https://github.com/Danroyal001/dartvel_dev/blob/main/docs/spec-status.json)
- [Changelog](https://pub.dev/packages/dartvel_core/changelog)

## The name

The framework is Dartvel and the command is `dartvel`. The umbrella package on
pub.dev is `dartvel_dev` because `dartvel` was taken on 2026-08-06 by an
unrelated package. The libraries under it keep their plain names.
