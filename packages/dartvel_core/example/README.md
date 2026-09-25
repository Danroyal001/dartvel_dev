# dartvel_core examples

## Runs as it is

```sh
dart pub get
dart run example/main.dart
```

[`main.dart`](main.dart) needs no generated code and no Flutter. It uses the
classes an application reaches through `DV.*`, constructed directly the way a
backend function, a queue worker or a test does:

```text
records: first sign-off changed 1 row
records: second sign-off changed 0 rows
accounts: signed up ada@example.com
accounts: ada@example.com refused: That e-mail address and password do not match an account.
accounts: nobody@example.com refused: That e-mail address and password do not match an account.
jobs: sending the welcome email to user-1
jobs: sending the welcome email to user-2
jobs: 2 completed, 0 left
authorization: owner true, stranger false, unregistered action false
cache: after revalidating, null
notifications: inApp via local: delivered, email: delivered
notifications: mail to ada@example.com, 1 in-app record
webhooks: signed body verifies true, altered body verifies false
```

The second sign-off changing nothing is the optimistic write working: its
filter names the value it read, the first writer changed it, and nought
changed is how the second learns it lost. The two refused sign-ins get the
same answer on purpose.

## What an application writes

In a Dartvel project most of this is declared, and `dartvel routes` — which
`dartvel build` and `dartvel dev` run first — generates the rest into
`lib/dartvel_client/`. The declarations are private; the application names
only what is generated from them, through the one barrel.

A data model:

```dart
// lib/models/article.dart
import 'package:dartvel_core/dartvel.dart';

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

A job:

```dart
// lib/jobs/welcome.dart
import '../dartvel_client/jobs.g.dart'; // the job types, without Flutter
import 'package:dartvel_core/dartvel.dart';

@DVJob(queue: 'mail', maxAttempts: 5, backoffSeconds: 60)
class const _SendWelcomeEmail({required final String userId});

@DVJob.handler()
Future<void> _handleSendWelcomeEmail(SendWelcomeEmail job) =>
    sendWelcomeEmail(job.userId);
```

A policy, which the generator registers with `DV.Auth.authorization`, and
which a route or backend function declaring `policy:` asks on the server:

```dart
// lib/policies/article_policy.dart
import '../dartvel_client/dartvel_client.dart';

@DVPolicy(Article)
class ArticlePolicy {
  // A route has no article to pass, so the resource is nullable.
  bool update(DVSessionPrincipal? user, Article? article) =>
      user != null && (article == null || article.authorId == user.userId);
}
```

And the code that uses them:

```dart
import '../dartvel_client/dartvel_client.dart';

Future<void> retitle(String slug, String title) async {
  final Article article = (await Article.find(slug))!;
  try {
    await article.copyWith(title: title).save();
  } on DVConflictError {
    // Someone saved a newer version after this one was read.
    return;
  }
  await DV.Cache.revalidateTag('articles');
}

Future<void> welcome(String userId) async {
  // Queued with the settings @DVJob declared; a worker process runs it.
  await SendWelcomeEmail(userId: userId).dispatch();
}
```

[`doc/surfaces.md`](https://github.com/Danroyal001/dartvel_dev/blob/main/packages/dartvel_core/doc/surfaces.md)
goes through each surface, including what is not built yet.
