# New Spec v2

# Dartvel — The Complete Vision, to be implemented

> **Flutter's Laravel, Flutter's Expo, Flutter's Next.js, Flutter's Hasura.**
>
> A batteries-included, AI-native, full-stack platform for building Flutter applications.

Flutter remains the rendering engine.

Dartvel becomes the platform. 

---

# Philosophy

Developers should primarily write:

* Pages
* Models
* Backend Functions
* UI
* Business Logic

Everything else should be generated.

---

# Design Goals

* Dart-first
* AI-first
* Convention over configuration
* Zero boilerplate
* End-to-end type safety
* Batteries included
* Compile-time generation
* Production ready
* Native performance
* Flutter compatible

---

# Project Structure

```text
lib/

pages/
models/
backend/
components/
styles/
services/

main.dart
```

These paths are the defaults. Projects may override them under the `dartvel:`
key in `pubspec.yaml`, including glob patterns for file groups, directories, and
subdirectories. The `dartvel:` key may also point to a Dart config file:

```yaml
dartvel: dartvel_config.dart
```

That file must expose a public class extending `DartvelConfig`. The class name
must start with an uppercase letter and must not start with `_`, so the CLI can
import it. YAML config is internally normalized into the same strongly typed
config shape.


No controllers.

No repositories.

No DTOs.

No manual route maps. Generated route maps are supported out of the box.

No signal folders.

---

# Configuration

Everything lives inside:

```yaml
pubspec.yaml
```

under

```yaml
dartvel:
```

Including

* App config
* Auth
* Permissions
* Deployment
* SEO
* PWA
* Multi-tenancy
* AI
* Storage
* Database
* Providers

---

# UI

Stability: `Contract` · Status: `Shipped`

Two primitives.
Dartvel keeps the primitive surface area small:

```dart
DVBox(...)
DVBox.list(...)

DVText(...)
```

Everything else is built from them.

Images ( .backgroundImage() modifier on DVBox )

Cards ( .card() modifier on DVBox )

Text inputs ( .input() modifier on DVText )

Rows (`DVBox.row(children)`)

Columns (`DVBox.list(children)`)

Buttons ( .onTap() or .onPressed() alias modifier on DVBox or DVText )

Forms ( DVForm does exist )

Lists (`DVBox.list(children)`)

Grids (`DVBox.grid(children)`)

Masonry (`DVBox.masonry(children)`)

Navigation

Containers and Layouts

---

Collection layouts are modes on `DVBox`, not separate widgets.

## Static Layouts

Static content is passed as an exact `List<Widget>` to `DVBox.list`. The default
layout is vertical and maps to Flutter's `Column` for static content.

```dart
DVBox.list([
  DVText("One"),
  DVText("Two"),
  DVText("Three"),
])
```

Single-child boxes use `DVBox(widget)` so the public API stays strongly typed
without `dynamic`, `Object`, or `var`.

```dart
DVBox(DVText("Profile"))
```

Rows, grids, wraps, stacks, horizontally scrollable lists, and scrollable
regions are layout constructors for static children. `DVBox.row` is an inline,
non-scrollable row. Use `DVBox.horizontalScrollable` when the collection should
overflow horizontally:

```dart
DVBox.row([Avatar(user), DVText(user.name)])

DVBox.grid([PhotoCard(a), PhotoCard(b), PhotoCard(c)], columns: 3)

DVBox.wrapLine([Tag("Flutter"), Tag("Dart"), Tag("Rust")])

DVBox.stack([Background(), Avatar(), Badge()])

DVBox.horizontalScrollable([StoryCard(a), StoryCard(b), StoryCard(c)])

DVBox.list([...]).scrollable()
```

Explicit `DVBox.wrapLine([...])` or `.wrapLine()` is a layout mode for
collections. It is not the removed automatic wrapper behavior for arbitrary
widget composition. `wrap` remains a compatibility alias, but new code should
use `wrapLine`.

## Dynamic Collections

Runtime collections use `DVBox.builder`. The default is vertical, lazy, and
virtualized where the target platform supports it.

```dart
DVBox.builder(
  posts,
  (post) => PostCard(post),
)
```

`DVBox.builder(...)` returns `DVBoxBuilder`, which is not itself a widget. A
layout method such as `.list()`, `.grid(...)`, `.wrapLine()`, `.masonry()`,
or `.horizontalScrollable()` must be called.

Builder collections support the same layout modes:

```dart
DVBox.builder(posts, (post) => PostCard(post)).grid(columns: 2)

DVBox.builder(tags, (tag) => TagChip(tag)).wrapLine()

DVBox.builder(photos, (photo) => PhotoCard(photo)).masonry()

DVBox.builder(stories, (story) => StoryCard(story)).horizontalScrollable()
```

## Generated Model Components

Generated model components are application components, not layout primitives.
They compose `DVBox`, `DVText`, and generated controls internally.

```dart
User.Form()
User.List()
User.Grid()
User.Masonry()
User.Table()
User.Page() // generated default page with a title and User.List()
```

Annotated models are private generation inputs. `@DVModel() class _User ...`
generates the public `User` class in `dartvel_client`, and application code
imports that generated public class from `dartvel_client/dartvel_client.dart`.
The generated public class owns the ergonomic static model-aware API:

```dart
User.Form(user);
User.List(users, builder: (user) => UserCard(user));
User.Table(users, columns: 3);
User.Page(users);
```

The annotated `_User` class is not exported and should not be referenced by
application code. Do not generate or call extra top-level model component
wrappers; generated public model methods are the only model component API.

Tables remain model-generated because they include sorting, filtering,
pagination, resizing, keyboard navigation, virtualization, accessibility, and
column management. Tables use the platform-styled table/list design with a
Material data table fallback.

```dart
User.List().builder((context, user) => UserCard(user))

User.Table().builder((context, user) => UserRow(user))
```

This intentionally avoids `DVRow`, `DVColumn`, `DVGrid`, `DVList`,
`DVMasonry`, and `DVWrap`. `DVBox` is the universal layout primitive, `DVText`
is the universal text primitive, and higher-level CRUD experiences are generated
from models.

---

# Styling

Stability: `Contract` · Status: `Shipped`

Built on Mix.

Supports EVERY Mix modifier.

Shared styles:

```dart
final primary =
    DVStyleModifier()
        .padding(12)
        .rounded(12);
```

N/B: Let's actually use `DVModifier` since it covers widget functionality too, not just styles. We'll keep `DVStyleModifier` as an alias for backword compatibility


Usage

```dart
DVText("Save")
    .styleModifier(primary);
```

N/B: Let's actually use `.modifier()` since it covers widget functionality too, not just styles. We'll keep `.styleModifier()` as an alias for backword compatibility


Fluent modifiers

```dart
.padding()
.margin()
.color()
.backgroundColor()
.shadow()
.width()
.height()
.card()
.rounded()
```

No manual Mix `.wrap()`. Dartvel handles wrapping where necessary.

---

# Pages

Stability: `Contract` · Status: `Shipped`

Pages are private generation inputs. A page input is a private function, with
either an expression body or a block body — the generator lowers the body into
the generated page either way:

```dart
@DVPage()
Widget _usersPage(
    BuildContext context
) => DVBox.list([
    DVText('Users'),
]);
```

A page needing statements writes them, and the body is lowered as it stands:

```dart
@DVPage()
@pragma('vm:entry-point')
Widget _usersPage(BuildContext context) {
    final users = context.signal(<User>[]);
    if (users.value.isEmpty) {
        return DVText('Nobody here yet');
    }
    return DVBox.list([
        for (final user in users.value) DVText(user.name),
    ]);
}
```

`@DVPage()` alone is enough for page functions. Using both `@DVPage()` and
`@DVFunctionalWidget()` remains valid; Dartvel treats them the same for pages
and performs the generated wrapping internally.

`@DVPage` handles routing, transitions, and the unified Material/Cupertino page
scaffold. Page bodies return Dartvel content directly, usually `DVBox`,
`DVBox.list`, or `DVText`; application page code should not create `Scaffold`
or `CupertinoPageScaffold` manually.

Page shell options are configured on the annotation with const values:

```dart
@DVPage(
    title: 'Settings',
    shell: DVPageShellMode.adaptive,
    showAppBar: true,
    safeArea: true,
    centerTitle: true,
    backgroundColor: 0xFFFFFFFF,
    appBarBackgroundColor: 0xFFF8FAFC,
    appBarActions: const [],
    appBarLeading: null,
    // all Material and Cupertino scaffold features are unified here
)
Widget _settingsPage(BuildContext context) {
    return DVBox.list([
        DVText('Settings'),
    ]);
}
```

`DVPageShellMode` supports `adaptive`, `material`, `cupertino`, and `none`.
`adaptive` renders Cupertino page chrome on iOS/macOS and Material page chrome
elsewhere. `scaffold: false` or `shell: DVPageShellMode.none` disables the
generated shell for advanced embedding.

If a page source explicitly returns a `Scaffold` or `CupertinoPageScaffold`,
the generator does not wrap that page with the default `DVPage` shell unless
`@DVPage(scaffold: true)` is set explicitly. This keeps legacy/manual shell
pages working, while Dartvel-authored pages should move scaffold properties to
`@DVPage(...)` and return content only.

---

# Routing

Stability: `Contract` · Status: `Shipped`

Pages Router.

```
pages/index.dart
```

Generated route clients must import each `DVPage` with Dart deferred imports under the hood.
The generated `dartvel_client/dartvel_client.dart` barrel exposes generated page
wrappers, and route tables instantiate those wrappers instead of importing page
source files eagerly. On web this allows large applications to load each page
bundle when the route is first visited rather than loading every page in the
initial bundle.

Application code should import one generated entrypoint:

```dart
import 'package:my_app/dartvel_client/dartvel_client.dart';
```

That barrel exports Dartvel core, Dartvel Flutter primitives, generated
functions, routes, configuration, environment access, and generated model
helpers.

↓

```
/
```

```
pages/users.dart
```

↓

```
/users
```

```
pages/users/[id].dart
```

↓

```
/users/:id
```

Navigation is strongly typed.

```dart
.navigateToPage(.users)

// For routes with parameters
.navigateToPage(
    .users(id)
)
```

Example:

```dart
DVBox(DVText("Navigate to users")).onPressed(DV.Navigation.to(DVPages.users));

// For routes with parameters
DVBox(DVText("Navigate to user 1"))
    .onPressed(DV.Navigation.to(DVPages.user(id: 1)));
```

## Routing engine

The generated router targets **`go_router`** as its runtime engine. This is a
deliberate, load-bearing choice, not an incidental dependency:

- Type safety and code generation are Dartvel's responsibility, not the
  router's. Dartvel emits the strongly typed `DVPages`/`DVRoutes` surface, so
  `go_router`'s own (stringly-typed by default) API is never exposed to
  application code, and a second code generator such as `auto_route`'s
  `build_runner` pass is intentionally avoided — it would compete with Dartvel's
  generator over the same concern.
- Dartvel is URL-first. Static web generation, web-server rendering, and
  `sitemap.xml` all require that every route map to exactly one canonical URL.
  `go_router`'s URL-as-source-of-truth model is the correct foundation for that;
  deep links resolve to paths directly with no separate mapping layer.

`go_router` is an implementation detail behind the generated navigation surface.
Application code must use `DV.Navigation`, `DVPages`, and `.navigateToPage(...)`
rather than importing or calling `go_router` directly, so the engine can evolve
(for example, generating onto `StatefulShellRoute` for nested-stack navigation)
without breaking application code.

---


# State

Stability: `Contract` · Status: `Shipped`

Local

```dart
final counter =
    context.signal(0);
```

or

```dart
signal(context, 0);
```

The `DV.signal()` helper can also work without a Flutter `BuildContext` in pure
Dart apps. `DVContext` is a universal context object for Flutter, server, CLI,
and web environments.

```dart
DVContext.builder((DVContext context) {
  final count = signal(context, 0);
  return DVText(count.value.toString());
});
```

`DVContext` mirrors useful `BuildContext` capabilities in Flutter apps and
exposes Dartvel-specific context for non-Flutter platforms. Unsupported
Flutter-only context operations fail clearly outside Flutter instead of silently
pretending to work.

---

Global

Register

```dart
DV.global<Cart>(Cart());
```

Retrieve

```dart
DV.global<Cart>();              // no instance passed: a read
DV.global<Cart>(null, 'store'); // a read from a module's namespace
```

The signature is `T global<T>([T? instance, String namespace = ''])`. Passing an
instance registers it; passing none — or `null`, when a namespace argument
follows — reads. [Modules](#modules) uses the second form, which is the same
call rather than a different one.

Reactive

```dart
context.global<Cart>();
```

Models become reactive automatically

```dart
user.signal(context);
```

Collections too

```dart
users.signal(context);
```

Read-only

```dart
counter.read();
user.read();
```

Internally powered by Riverpod, so it works in Flutter and pure Dart.
Normal `signal()` tracks by parent widget or context. `DV.global` tracks by
data type, so each type must be unique. Setting the same type replaces the
previous value for that type.

---

# Models

Stability: `Contract` · Status: `Shipped`

```dart
@DVModel()
class _User(
    String name,
    String email,
);
```

Annotated models are private schema inputs by validation: `@DVModel() class
_User ...` generates the public `User` type. Generated static members such as
`User.Form(...)`, `User.List(...)`, `User.Table(...)`, and `User.Page(...)`
belong to that generated public class.

Pages, functional widgets, backend functions, jobs, AI tools, and models are
private generation inputs. This is a hard generator rule:
`@DVModel() class User`, `@DVPage() Widget usersPage(...)`,
`@DVFunctionalWidget() Widget button(...)`, and
`@DVBackendFunction() Future<User> getUser(...)` must fail with clear rename
messages that instruct the developer to rename them to `_User`, `_usersPage`,
`_button`, and `_getUser`. Application
code references only the generated public API from
`dartvel_client/dartvel_client.dart`, such as `UsersPage`, `Button`,
`getUser`, and `User`.

Private `@DVPage`, `@DVFunctionalWidget`, `@DVBackendFunction` and
`@DVJob.handler()` function inputs take either body. The generator lowers the
body into the generated public code, so no source-local `part` file is needed
and the generated file reads as ordinary Dart:

```dart
@DVPage()
Widget _usersPage(BuildContext context) => DVBox.list([DVText('Users')]);

@DVFunctionalWidget()
Widget _featureCard(String title) => DVBox(DVText(title));

@DVBackendFunction()
Future<String> _getEcho(String input) async => 'Echo: $input';
```

Generated page and backend scaffolds use that shape. A lowered body is moved
into generated code, so it cannot reach a private top-level symbol in the file
it came from: the generator refuses one that does, naming the symbol, rather
than emitting generated code that does not compile. Public annotated functional
widget inputs always fail.

Using the new native Dart data-class syntax. Automatically generates:
* Database schema
* CRUD
* Validation
* Serialization
* Equality, .copyWith, .merge, and .hashCode
* Forms, Pages, Lists, Tables, and generated components (`.Form`, `.Page`)
* APIs
* Queries
* Model sync and presence

---

# Record History and Optimistic Concurrency

Stability: `Draft` · Status: `Designed`

Offline-First Models answers what happens when a device that was disconnected
reconnects. Two people editing the same order on two desks, both online, is the
ordinary case, and it has the same shape: a write landing on a record that has
moved since it was read. This section answers it with the same vocabulary, and
keeps the record of what changed.

## One version, one conflict vocabulary

Every model carries a generated version. It is the same version offline replay
compares to decide whether a queued mutation is stale, so there is one notion
of "the row moved" rather than two that disagree at the edges.

Writes are checked against it by default:

```dart
final order = await Order.find(id);
await order.copyWith(quantity: 3).save();   // refused if the row moved
```

```dart
try {
  await order.save();
} on DVConflictError catch (conflict) {
  conflict.mine;    // what this session wrote
  conflict.theirs;  // what the row holds now
  conflict.base;    // what this session read
}
```

**Versioning is on by default, and opt-out.** A lost update is silent: the
second writer sees success, the first writer's change is gone, and nothing in
the system knows. Making the safe behaviour opt-in means every application has
it wrong until somebody notices in production. The cost is one integer column
and one predicate on update, which is the cheapest correctness in the
specification. `@DVModel(version: false)` exists for append-only tables where
writes never contend, and says so at the declaration.

`DVConflict` is the enum Offline-First Models already defines, with one member
added for the online case:

| Strategy | Resolution |
|---|---|
| `DVConflict.ask` | refuse the write and hand both versions to the caller — the online default |
| `lastWriteWins` | the later write by declared clock, whole model |
| `serverWins` | the local change is discarded and reported |
| `fieldMerge` | per field, the later write by declared clock |
| `DVConflict.resolver(fn)` | a typed resolver the application writes, given both versions |

The difference between online and offline is not the vocabulary; it is whether
anybody is there to ask. Online, the writer is present, so the default refuses
and lets them decide. Offline, nobody is present at the moment of the merge, so
a strategy has to decide in advance — which is why `DVConflict.ask` is not a
legal offline strategy and is refused at build time (`DV-HISTORY-002`).

Generated forms know the outcome: a refused save reloads the record, shows what
changed underneath, and offers the merge rather than throwing the person's
typing away.

## History

```dart
@DVModel(history: DVHistory(keep: Duration(days: 365)))
class _Order(
    String reference,
    int quantity,
);
```

```dart
await order.history();          // who changed what, when, in which transaction
await order.revert(to: entry);    // a reversible transaction, not a raw write
```

Each entry records the actor, the tenant, the transaction identifier, and the
fields that changed. It is written **in the same transaction as the change**,
because a change log that can miss entries when a separate write fails is not
a record of anything (`DV-HISTORY-005`).

**History is opt-in, and retention is declared with it.** A change log is a
second copy of the data with a different lifetime, so switching it on for every
model would double storage quietly and put values somewhere the application's
own retention rules were never applied. Retention is enforced by the generated
scheduled jobs the rest of the platform uses, not a new sweeper
(`DV-HISTORY-004`).

Volume has somewhere to go: history is stored in the application's database by
default and can be pointed at another adapter, ClickHouse among the databases
already supported, without changing what `order.history()` returns.

**Sensitive fields are recorded as changed, never as values.**
`@DVModel.sensitiveField()` excludes a field from logs, traces and analytics;
copying it into a history table would defeat that in the one place nobody
thinks to look. An entry says the field changed and by whom. The honest
consequence is that `revert` cannot restore one: it restores what it holds,
reports the fields it could not, and leaves them to be set deliberately
(`DV-HISTORY-003`).

## Soft delete

```dart
@DVModel(softDelete: true)
class _Invoice(
    String number,
);
```

```dart
await invoice.delete();     // marked, not removed
await Invoice.restore(id);
Invoice.find(id);           // excludes soft-deleted rows
Invoice.withDeleted.find(id);
```

Queries, model pages, tables, search indexes and sync all exclude soft-deleted
rows by default — Search already assumes this filter exists, and this is where
it is specified. Restoring is refused rather than forced when a unique field
has since been taken by a live record, because the alternative is two rows
claiming one invoice number (`DV-HISTORY-006`).

## Studio

Studio's undo over page documents and this are the same mechanism seen twice:
a versioned record with entries that can be reverted in a reversible
transaction. Studio reads `history()` for any model with it enabled, so an
administrator can see who changed a price and put it back without SQL.

## Diagnostics

| Code | Reason | Level |
|---|---|---|
| `DV-HISTORY-001` | write refused: the record changed since it was read | `error` |
| `DV-HISTORY-002` | `DVConflict.ask` declared as an offline strategy, where nobody is present to ask | `error` |
| `DV-HISTORY-003` | revert could not restore a sensitive field; history records the change, not the value | `warning` |
| `DV-HISTORY-004` | history entries removed by the declared retention | `info` |
| `DV-HISTORY-005` | history entry could not be written; the transaction was rolled back | `error` |
| `DV-HISTORY-006` | restore refused: a unique field is held by a live record | `error` |

## Deliberately absent

- **A second conflict vocabulary.** `DVConflict` is Offline-First Models', with
  `ask` added for the case where somebody is present.
- **History on by default.** It is a copy of the data with its own retention;
  turning it on for a model is a decision with a storage bill.
- **Reverting someone else's concurrent change silently.** `revert` is a
  reversible transaction and takes the same version check as any other write.

---

# Forms

Stability: `Contract` · Status: `Shipped`

Automatic

```dart
DVForm<User>()
```

Or alias

```dart
User.Form()
// The base class
```

---

Editing

```dart
// Accepts the model as a positional Arg. The Arg type is DVModel, base class for all the models
DVForm<User>(user)
// An instance of the base class
```

Or alias

```dart
// The instantiated object
user.Form()
```

Manual

```dart
DVForm<User>.builder((formControls) { return someComposedWidget; })
```

Editing

```dart
// Accepts the model as a positional Arg. The Arg type is DVModel, base class for all the models
DVForm<User>.builder((formControls) {}, user)
```

Generated controls, such as `formControls.email`. These render with
`DVText.input()`.

Generated validation, such as `formControls.emailIsValid`.

Generated submit ( formControls.submit(), .reset() ).

---

# Backend

Stability: `Contract` · Status: `Shipped`

Backend code is ordinary Dart.

```dart
@DVBackendFunction()
Future<User> _getUser(String id) async => User.find(id);
```

Parameters are automatically validated by type, with automatic valudation messages generated. The messages can be customized if needed. Automatic request and response conversion.

Call it like

```dart
await getUser(id);
```

In frontend or backend code. Works the same.

No raw REST (but still available).

No controllers.

No routes.

No generated SDKs (but still available).

No manual openapi configs, they get auto-generated

Just typed functions.

Under the hood, Dartvel compiles backend functions into a high-performance Rust runtime built on Axum and Tokio, exposing them through zero-boilerplate, strongly typed, zero-copy, FFI APIs. Developers continue writing only Dart. 

---


# Streaming Functions

Stability: `Contract` · Status: `Shipped`

Backend functions may return

```dart
Stream<T>
```

Example

```dart
@DVBackendFunction()
Stream<Message> _messages() => Message.stream();
```

Automatically translated to efficient streaming endpoints (such as Server-Sent Events or websockets with automatic fallback to polling, can be configured) while preserving Dart's native `Stream<T>` API.

---

All backend data is transmitted as form-data to allow large request sizes if necessary and to be compatible with web. Fields in the form-data are packed as binary flat-buffers. An efficient lightweight boundary is used for the form-data and documented in the request headers. This applies to backend functions and model events.

---

# Scheduling

Stability: `Draft` · Status: `Partial`

Backend

```dart
@DVBackendCron(...)
```

Client

```dart
@DVClientCron(...)
```

## A client schedule is a request, not a guarantee

`@DVClientCron(every: 5.minutes)` reads like a promise, and on a phone it is
not one. iOS decides when a background refresh task runs and may decide never;
Android's WorkManager will not schedule periodic work more often than every
fifteen minutes and Doze defers it to a maintenance window; a browser throttles
timers in a background tab. Dartvel states what each target really does rather
than letting the annotation imply a clock it does not have.

**Lifetime.** A client schedule ticks while the application is showing a page
and stops with the last one, and coming back ticks once straight away — what
came due while the application was away is due now, not up to an interval from
now. Registering again replaces the previous registration rather than adding to
it, so a second router cannot double a schedule.

| Target | What "every 5 minutes" becomes |
|---|---|
| iOS | a `BGTaskScheduler` refresh request; the system chooses the moment and may skip it, each run is seconds long, and a user force-quit stops it until the app is opened again |
| Android | `WorkManager` periodic work, floor of 15 minutes, deferred to Doze maintenance windows and to whatever the OEM's battery policy adds |
| Web | while the tab is open; a background tab is throttled to roughly one wakeup a minute, and a closed tab runs nothing |
| macOS, Windows, Linux | while the application runs; App Nap and timer coalescing shift the wakeup, and nothing runs once it is closed |
| Embedded, TV, kiosk | while the application runs, which on a kiosk is usually always; a restart restarts the schedule |

Dartvel does not install a launch agent, a scheduled task, or a service to make
a closed desktop application tick. That is a system-level install with its own
consent and its own uninstall story, and a framework that did it quietly would
be leaving something behind on a machine after the application was gone.

**The capability is typed**, like every other platform difference:

```dart
final report = DV.Schedules.capability(Schedules.refreshDashboard);
report.granularity;      // the finest interval this target will honour
report.whenBackgrounded; // runs | deferred | suspended
report.whenTerminated;   // never | wakesOnSchedule
```

`dartvel doctor` reads the same report, so a schedule asking for something the
target will not do is a finding at build time rather than a bug report about a
feature that "sometimes does not run".

| Code | Reason | Level |
|---|---|---|
| `DV-CRON-001` | declared interval finer than the target's granularity; coalesced to it | `warning` (analyze) |
| `DV-CRON-002` | client schedule on a target that runs nothing in the background | `info` at boot |
| `DV-CRON-003` | a run was skipped because the previous one was still running | `debug` |
| `DV-CRON-004` | the platform refused to register background work (permission or battery policy) | `warning` |

Work that must happen on time happens on the server. `@DVBackendCron` runs on a
machine that is awake, and a schedule that matters to somebody else's data or
to a deadline belongs there; `@DVClientCron` is for refreshing what this device
is showing.

---

# Queues, Jobs, and Signals

Stability: `Contract` · Status: `Shipped`

Dartvel has a durable background work layer inspired by Laravel queues and a
typed signal model inspired by Qt signals/slots, Dart streams, Riverpod, and
generated model sync delivery.

## Jobs

Jobs are ordinary typed Dart payloads. The generator discovers `@DVJob`
classes, generates readable dispatch helpers, and registers strongly typed
handlers. No job payload uses `dynamic`, `Object`, or untyped maps in public
APIs.

```dart
@DVJob(queue: 'mail', maxAttempts: 5, backoffSeconds: 60)
class _SendWelcomeEmail(String userId)

@DVJob.handler()
Future<void> _handleSendWelcomeEmail(SendWelcomeEmail job) async =>
    DV.Notifications.send(...);

await DV.Jobs.dispatch(SendWelcomeEmail(user.id));

// Or with the queue, priority, attempts and backoff the annotation declares,
// which plain DV.Jobs.dispatch cannot know:
await SendWelcomeEmail(userId: user.id).dispatch();
```

Job metadata is grouped under the job annotation: the handler is
`@DVJob.handler()`, not a standalone `@DVJobHandler`. That also leaves the
`DVJobHandler` typedef — the runtime handler function type — meaning what it
already means. Like private page and backend-function inputs, a private handler
takes either body and is lowered into the generated handler.

Queues support:
- named queues and generated queue constants
- priorities and delayed execution
- retries, exponential backoff, retry-until timestamps, and max attempts
- dead-letter queues with inspect, retry, discard, and replay commands
- worker scaling, concurrency limits, pause/resume, and graceful shutdown
- job uniqueness and idempotency keys
- scheduled jobs and cron-triggered jobs
- queued signal payloads
- typed progress events and cancellation tokens
- provider adapters for in-memory, database, Redis/Valkey, SQS, Pub/Sub,
  RabbitMQ, Kafka, and platform-native task schedulers where available

CLI:

```bash
dartvel queue work
dartvel queue failed
dartvel queue retry <job-id>
dartvel queue flush --queue mail
```

Runtime guarantees:
- Jobs are persisted before `dispatch` returns unless the configured provider is
  explicitly in-memory/test.
- Failed jobs are never silently dropped.
- Retried jobs preserve the original payload and append attempt metadata.
- Job handlers run with observability trace context and tenant context.
- Unsupported providers fail validation during `dartvel build`.

## Signals

Signals are already part of Dartvel through `context.signal(...)`,
`signal(context, ...)`, reactive models, `DV.global`, and generated model
sync.
Dartvel should not introduce separate signal/event annotations for the common
case.

```dart
final counter = context.signal(0);
counter.value++;

final userSignal = user.signal(context);
final cart = context.global<Cart>();
```

Derived values come from operating on signals — there is no separate computed
construct:

```dart
final a = context.signal(1);
final b = context.signal(2);
final c = a + b;
```

`c` is a signal. Adding, subtracting, comparing or concatenating signals
produces a signal that tracks its sources and changes when they change, so a
derived value is simply a value and there is nothing extra to reach for.

Because the result is itself a signal, derivations compose:

```dart
final total = (price * quantity) + shipping;
final inStock = stock > 0;
final canShip = agreed & paid;
final fullName = firstName + ' ' + lastName;
```

An operand may be another signal or a plain value. Reactivity rides on the
sources: reading a source inside the derivation subscribes the element exactly
as it would in a build method, so a derived signal stays current without
subscription bookkeeping of its own.

---

For background work and cross-client delivery, signals are just typed job
payloads or model sync events:

```dart
await DV.Jobs.dispatch(
  UserCreated(user.id),
  queue: DVQueues.signals,
);
```

Signal guarantees:
- Signal values are exact typed Dart values.
- UI state uses `context.signal` / `signal(context, value)`.
- Model state uses generated reactive model signals.
- Background signal delivery uses `DV.Jobs`.
- Cross-client delivery uses generated model sync.
- Model lifecycle signals are generated for create, update, delete, restore,
  attach, detach, and sync events.
- Model sync applies auth, tenant filters, and policy checks before
  delivery.
- Signals can bridge to native platform events through generated FFI/ffigen or
  JNI/jnigen bindings only. No Flutter platform channels.

---

# Authorization

Stability: `Contract` · Status: `Shipped`

Authentication identifies users. Authorization decides what they can do.

```dart
@DVPolicy(Post)
class PostPolicy {
  bool update(User user, Post post) => post.authorId == user.id;
}

await DV.Auth.authorize(user, DVPolicyAction.update, post);
final allowed = await DV.Auth.can(user, DVPolicyAction.delete, post);
```

Policy generation:
- `@DVPolicy(ModelType)` classes generate typed policy registries.
- Conventional policy methods include `viewAny`, `view`, `create`, `update`,
  `delete`, `restore`, `forceDelete`, `export`, and `impersonate`.
- Generated model components call policies automatically before rendering
  actions.
- Backend functions and model queries enforce policies even if UI guards are
  bypassed.
- Tenant scoping is part of policy evaluation, not a separate optional filter.

Policies apply to:
- pages
- backend functions
- model queries
- generated forms
- generated tables/lists
- storage objects
- model sync channels
- tenant boundaries

Usage:

```dart
@DVPage(policy: DVPolicies.viewAdmin)
Widget _adminPage(BuildContext context) => AdminDashboard();

@DVBackendFunction(policy: DVPolicies.refund)
Future<Refund> _refundOrder(Order order) async => Refund.create(order);
```

Generated UI can hide disabled actions, but backend enforcement is mandatory.
Unauthorized access returns typed errors with consistent HTTP status mapping and
structured observability events.

---

# Middleware

Stability: `Contract` · Status: `Partial`

Dartvel supports middleware for both pages and backend functions.

```dart
@DVUseMiddleware([DVMiddlewares.auth, DVMiddlewares.tenant, DVMiddlewares.rateLimitCheckout])
@DVPage()
Widget _checkoutPage(BuildContext context) => Checkout.Page();

@DVUseMiddleware([DVMiddlewares.auth, DVMiddlewares.csrf, DVMiddlewares.idempotency])
@DVBackendFunction()
Future<Order> _createOrder(CreateOrderInput input) async => Order.create(input);
```

Middleware can be global, route/page scoped, layout scoped,
backend-function scoped, model scoped, or storage scoped. Middleware order is
deterministic and generated at build time.

Built-ins:
- auth and policy enforcement
- tenant resolution
- CORS and preflight handling
- CSRF validation
- rate limiting and throttling
- request logging and tracing context
- security headers and CSP
- body limits and upload limits
- compression
- locale detection
- idempotency keys
- cache tags and revalidation hints
- feature flags and experiments
- maintenance mode

Page middleware:
- runs before route activation
- can redirect, block, preload data, set SEO context, or defer route bundles
- supports generated loading/error states
- must not force eager imports of deferred `DVPage`s

Backend middleware:
- runs in the Rust runtime around generated Dart function calls
- receives typed request metadata and typed function metadata
- can short-circuit with typed responses
- must propagate trace IDs, tenant IDs, auth IDs, and idempotency IDs

Middleware must be typed and generated. Unsupported middleware configuration
fails validation during `dartvel build`.

---

# Authentication

Stability: `Contract` · Status: `Shipped`

Like Firebase, WorkOS and Clerk.

```dart
DV.Auth.currentUser // Nullable, of type DVUser?
```

```dart
DV.Auth.signInWithEmailAndPassword()

DV.Auth.signInWithProvider() // Google, Facebook, Apple, etc.

DV.Auth.signInWithRawOAuth()

DV.Auth.signInWithPasskey() // Triggers the passkey flow for the OS or browser, with safe fallback

DV.Auth.signInWithBiometrics() // Triggers the default biometric flow for the platform, safe fallbac or failure, can be configured. has specific alternatives like DV.Auth.signInWithFingerprint() or DV.Auth.signInWithFaceRecognition()

DV.Auth.signInWithWeb3()

DV.Auth.signOut()

DV.Auth.signUp()

// etc.
// We'll also have prebuilt pages for each one. Just Make the first letter uppercase for the class name, and add `Page`, e.g `DV.Auth.SignInWithEmailAndPasswordPage(). Has inbuilt navigation slugs e.g `.navigateToPage(.signInWithEmailAndPasswordPage)` with the Page suffix too, can be overridden.
```

Authentication is provider-backed. Applications configure a typed
`DVAuthProvider` implementation for their identity service; calling an auth
method without a configured provider fails with a clear configuration error.
`DVLocalAuthProvider` is available only as an explicit development/test
adapter and must not be mistaken for production authentication.

Providers

* Email
* Google
* Apple
* GitHub
* Gitlab
* Bitbucket
* Microsoft
* Magic Links (`DVAuthTokens.issueMagicLink` / `redeemMagicLink`)
* OTP (`DVAuthTokens.issueOtp` / `redeemOtp`)
* LDAP
* SAML

---

# Theme

Stability: `Contract` · Status: `Shipped`

Global

```dart
DV.Theme
```

- Light (fallback if platform doesn't have a supported system theme e.g embedded devices)
- Dark
- System (default)

Dynamic (default) or manual switching

---

# Platform

Stability: `Contract` · Status: `Partial`

```dart
DV.Platform.*
```

Provides:
- Platform detection (DV.Platform.currentPlatform (enum))
- Screen size (DV.Platform.screen.size)
- Safe areas (DV.Platform.screen.safeAreaBounds)
- Breakpoints (DV.Platform.screen.breakPoints)
- Orientation (DV.Platform.deviceOrientation)
- Window (DV.Platform.Window) - Window bounds, properties and functionalities for the app/site. Web uses browser APIs; native platforms use generated FFI/JNI bindings where supported.
- Device type (DV.Platform.type (enum, e.g mobile, desktop, laptop, desktopOrLaptop, tablet, embeddedDisplay, watch, circularWatch, squareWatch, embeddedWithoutDisplay))
- Screen shape (DV.Platform.screen.shape (enum e.g square, rectangle, verticalRectangle, horizontalRectangle, custom))
- Full-screen and kiosk display control:
  - `DV.Platform.display.enterFullscreen()` // Where the platform supports it.
  - `DV.Platform.display.exitFullscreen()`
  - `DV.Platform.display.enableKiosk()` // enters fullscreen and enables kiosk-specific controls and configurable exit protection
  - `DV.Platform.display.disableKiosk()`
  - `DV.Platform.display.isFullscreen`
  - `DV.Platform.display.isKiosk` // .isFullscreen() will still return true so .isKiosk() checks if we're specifically in kiosk mode
  - Native implementations must be generated through FFI/ffigen or JNI/jnigen
    bindings named `display.enterFullscreen`, `display.exitFullscreen`,
    `display.enableKiosk`, and `display.disableKiosk`. Dartvel must not use
    Flutter platform channels for these APIs.
  - These four remain valid as sugar over `DV.Platform.display.kiosk`. The
    policy they obey — the two scopes, session reset, exit protection and what
    each target actually enforces — is specified in
    [Kiosk Mode](#kiosk-mode); a runtime call never changes policy, only
    state.

Native APIs, including:
- Android (DV.Platform.isAndroid)
- iOS (DV.Platform.isIOS)
- Windows (DV.Platform.isWindows)
- Linux (DV.Platform.isLinux)
- SONY E-Linux (DV.Platform.isSonyELinux)
- macOS (DV.Platform.isMacOS)
- Web (DV.Platform.isWeb)
- Fuchsia (DV.Platform.isFuchsia)
- Tizen (DV.Platform.isTizen)
- webOS (DV.Platform.isWebOS)
- Amazon (DV.Platform.isAmazon)
- TVs (DV.Platform.isTV, DV.Platform.isAndroidTV, DV.Platform.isAppleTV)
- Watches (DV.Platform.isWatch)
- Foldables (DV.Platform.isFoldable, DV.Platform.isDualFold, DV.Platform.isTriFold)
- Native APIs, Expo-style. (DV.Platform.*)
- Camera (DV.Platform.Camera)
- Media and Files (DV.Platform.FileStorage, proxy to DV.FileStorage)
- Location (DV.Platform.Location and DV.Location proxy)
- Bluetooth (DV.Platform.Bluetooth and DV.Bluetooth proxy)
- NFC (DV.Platform.NFC and DV.NFC proxy)
- Clipboard (DV.Platform.Clipboard, and DV.Clipboard proxy)
- Share (DV.Platform.Share or DV.Share proxy)
- Notifications (DV.Platform.Notifications and DV.Notifications proxy)
- Sensors (DV.Platform.Sensors and DV.Sensors proxy)
- Biometrics (DV.Platform.Biometrics and DV.Biometrics proxy)
- Deep Links (DV.Platform.DeepLinking and DV.DeepLinking proxy)
- Haptics (DV.Platform.Haptics and DV.Haptics proxy)
- Contacts (DV.Platform.Contacts and DV.Contacts proxy)
- Browser extension detection:
  - `DV.Platform.isChromiumExtension`
  - `DV.Platform.isFirefoxExtension`
- Browser extension APIs:
  - `DV.Platform.browserExtension.getManifest()`
  - `DV.Platform.browserExtension.sendMessage(...)`
  - `DV.Platform.browserExtension.tabsCreate(...)`
- Permissions, managed centrally through `pubspec.yaml`. (DV.Platform.*)

All under DV.Platform.*

Browser extension storage is not exposed through `DV.Platform.browserExtension`
to avoid duplicating storage APIs. Use `DV.FileStorage.*` for Chromium and
Firefox extension local storage behavior, with `DV.BlobStorage.*` as an alias.

---


# Database

Stability: `Contract` · Status: `Shipped`

Supports

* PostgreSQL
* MySQL
* SQLite
* MongoDB
* Turso
* ClickHouse
* BigQuery

Automatic migrations.
Automatic CRUD.
Automatic relationships.
Automatic model sync.

Local development database:
- SQLite is built in as the default zero-config local database
- WAL mode is enabled where supported
- generated migrations work the same locally and in production
- tests can use in-memory SQLite
- local queues/cache/session storage can share SQLite when configured

This is inspired by Bun's built-in SQLite approach: the local database should be
fast, available by default, and require no separate service for common
development and test workflows.

Automatic migrations stay automatic as a table grows, which is where the cost
of a change stops being obvious: see Schema Evolution for how each change is
classified and how a blocking one is choreographed rather than simply run.

---

# Schema Evolution

Stability: `Draft` · Status: `Designed`

Migrations alter a schema and Protocol Versioning and Client Compatibility
keeps old clients alive. Between the two sits the change that locks a
hundred-million-row table for forty minutes. Automatic migrations are only
automatic while the table is small; at scale the same one-line model edit is an
outage, and nothing in the specification told anyone which one they had just
written.

## Every change is classified

The migration planner classifies each change before it runs:

| Class | Meaning |
|---|---|
| `instant` | metadata only; the table is not rewritten and the lock is momentary |
| `online` | the table stays readable and writable throughout |
| `blocking` | readers or writers are held for the duration |

**The classification comes from the adapter, not the planner.** A planner with
the rules baked in would be wrong the day a database ships a new version, and
wrong for every adapter somebody else writes: adding a column with a default is
instant on PostgreSQL 11 and a rewrite on 10, and a new adapter cannot teach a
closed planner anything. `DVDatabaseAdapter.classify(change)` answers for the
server it is connected to, including its version.

What the shipped adapters report today:

| Change | PostgreSQL | MySQL 8 | SQLite / Turso | MongoDB | ClickHouse | BigQuery |
|---|---|---|---|---|---|---|
| add nullable column | instant | instant | instant | instant | instant | instant |
| add column with default | instant (11+) | instant | instant | instant | instant | blocking |
| add index | online (`CONCURRENTLY`) | online | blocking | online (4.2+) | online | instant |
| add `NOT NULL` | online (validated check, 12+) | blocking | blocking | n/a | n/a | blocking |
| change column type | blocking | blocking | blocking | n/a | blocking | blocking |
| rename column | instant | instant | instant | n/a | instant | blocking |
| drop column | instant | instant | blocking | instant | instant | blocking |

A rename is instant on the server and still breaking for a client, which is the
distinction the class alone does not carry: the cost of a change and its
compatibility are separate questions, answered here and in Protocol Versioning
respectively.

## Expand and contract

A `blocking` change is refused as written. The planner generates the safe
version of it instead, as five phases with a gate between each:

1. **Expand** — add the new column, table or index alongside the old shape.
   Nothing reads it yet.
2. **Dual-write** — generated model code writes both shapes. Reads stay on the
   old one.
3. **Backfill** — a resumable, rate-limited durable job copies the existing
   rows in chunks, with progress in Studio. It is an ordinary job on the
   existing queue machinery, so it survives a restart and can be paused.
4. **Verify** — every chunk is compared, and the switch is refused until they
   agree.
5. **Contract** — reads move to the new shape, dual-write stops, and the old
   column is dropped in a later release.

Each phase is a separate deploy. That is the point: a phase boundary is where
a rollback is still cheap, and an expand/contract compressed into one release
is the outage it was supposed to avoid.

## Verification, and why it is per chunk

The read switch requires three things at once: every chunk backfilled, every
chunk verified, and the dual-write discrepancy counter at zero for the whole
verification window.

Verification hashes each chunk on both shapes and compares the hashes — the
same chunks the backfill used, by the same job. Not `COUNT(*)`: counts agree
while values differ, which is the failure worth catching, and a single
whole-table hash can only say that something somewhere is wrong. A per-chunk
hash names the chunk, so the mismatch can be read, fixed and re-verified
without starting again (`DV-SCHEMA-004`).

## Throttling

A backfill competes with production traffic, so it is throttled against what
the database is doing rather than at a fixed speed — a fixed rows-per-second is
too slow on one deployment and an outage on another.

```yaml
dartvel:
  database:
    tier: standard        # small | standard | large; embedded targets declare
                          # this in the device profile instead
    backfill:
      targetReplicaLag: 5s
      maxWriteLatencyIncrease: 10%
```

| Tier | Starting rate |
|---|---|
| `small` | 500 rows/s |
| `standard` | 2,000 rows/s |
| `large` | 10,000 rows/s |

The starting rate is a starting point only. The job halves its rate when
replica lag or write latency crosses the budget and steps back up while they
stay under it, so a backfill finds the speed the database can actually take
and gives it back when traffic arrives.

## The deploy gate

```bash
dartvel db migrate --plan                        # classification per change
dartvel db migrate --dry-run --against snapshot  # rehearse on production shape
```

`--against snapshot` rehearses the plan against a snapshot of the production
schema and row counts, so the classification a developer sees is the one
production will apply, not the one their empty local database implies.

A `blocking` change reaching production is refused unless an explicit,
logged override accompanies it (`DV-SCHEMA-002`) — the same discipline as
`dartvel compatibility-check`, and for the same reason: sometimes the forty
minutes are worth it, at three in the morning, with everyone told. The gates
are sequenced with each other, too. A contract-breaking change raises the
protocol version in the release that expands, and the contract phase is refused
while any client inside the window still reads the old shape.

## Diagnostics

| Code | Reason | Level |
|---|---|---|
| `DV-SCHEMA-001` | a blocking change was written where an expand/contract plan exists | build `warning` |
| `DV-SCHEMA-002` | blocking migration against production without an override | gate `error` |
| `DV-SCHEMA-003` | backfill throttled below its floor for longer than the configured patience | `warning` |
| `DV-SCHEMA-004` | chunk verification mismatch; the read switch is refused | `error`, names the chunk |
| `DV-SCHEMA-005` | contract phase requested while clients inside the protocol window read the old shape | gate `error` |
| `DV-SCHEMA-006` | adapter cannot classify a change; treated as blocking | `warning` |
| `DV-SCHEMA-007` | dual-write discrepancy detected during verification | `error` |

`DV-SCHEMA-006` fails towards the expensive answer deliberately. An unknown
change treated as instant is an outage nobody predicted; treated as blocking it
is a plan somebody has to read.

---

# APIs

Stability: `Contract` · Status: `Shipped`

Generated automatically.

- RPC
- REST
- GraphQL
- OpenAPI and Swagger documentation

No manual endpoint creation, but available if needed.

---

# Platform API: Keys, Scopes and OAuth Provider

Stability: `Draft` · Status: `Designed`

APIs generates RPC, REST, GraphQL and OpenAPI for the application's own
clients, which are trusted: they ship with the application and authenticate as
a person. An application that is itself a platform has to let somebody else's
software in — with a key, a scope, a rate plan and an audit trail — and that is
a different problem with none of the same defaults.

## A scope is a set of policy actions

Scopes are not strings invented beside the API and compared by hand. They are
named sets of the actions authorization already defines, so the thing a key is
allowed to do is the thing a policy already decides:

```yaml
dartvel:
  platformApi:
    scopes:
      orders:read: [Order.view, Order.list]
      orders:write: [Order.create, Order.update]
      profile: [User.viewSelf]
```

A scope naming an action no policy defines fails the build, which is the
failure that otherwise appears as a partner's integration silently receiving
nothing (`DV-APIKEY-001`).

A third-party request runs the **same** generated request lifecycle as any
other call. Nothing forks: the key resolves to a principal at the
authentication stage, its scopes become the policy context at the
authorization stage, and every tenant filter, validation and audit step is the
one already there. A call outside its scopes is refused by the policy engine,
not by a gateway with its own opinion (`DV-APIKEY-002`).

## Keys

```dart
final key = await ApiKey.issue(
  organization: org,
  scopes: const ['orders:read'],
  expiresIn: const Duration(days: 90),
);
key.secret;   // shown once, at issue
```

Key material is stored hashed, like a password, with a short identifying
prefix in clear. A database that leaks does not leak working keys, and support
can still tell which key somebody means.

**Rotation overlaps rather than replaces.** Issuing a replacement leaves both
keys live until the old one expires, because rotating by replacement breaks
every caller at the moment of the swap and turns a routine hygiene task into an
outage nobody schedules. Revocation is the other operation and is immediate —
they are deliberately separate words (`DV-APIKEY-003`).

Rate plans per key ride the rate-limiting middleware that exists rather than a
second limiter, so a partner's quota is enforced in the same place as
everything else (`DV-APIKEY-006`).

## OAuth provider

Where partners need to act for the application's *users* rather than for
themselves, the application becomes an OAuth 2.1 / OIDC provider over
Authentication's existing session and token machinery — the same minting,
expiry and single-use guarantees, with generated consent screens naming the
scopes in the words the scope declaration gave them.

Machine-to-machine is part of this section, not a separate one: client
credentials is the same key and the same scope set with a grant instead of a
header. Splitting it would put two answers in the specification for "how does
another company's server call us", and they would drift.

An OAuth client asking for a scope the application does not define is refused
at registration, not at the first call (`DV-APIKEY-004`).

## The developer portal is a module

The portal — API reference from OpenAPI, the event catalogue, key management,
usage — is a Dartvel module the application mounts, and federated deployment is
its default:

```yaml
dartvel:
  modules:
    developers:
      source: { package: dartvel_developer_portal }
      mount: /developers
      deployment: federated
      auth: inherit
```

A module because that is what modules are: a full application boundary mounted
at a path the parent chooses, inheriting theme and auth, deployable separately.
Federated by default because a portal is public documentation with a login, its
traffic has nothing to do with the application's, and a partner reading
reference pages should not share a deployment with checkout.

It is opt-in. An application that is not a platform has no partners and should
not ship a portal to prove it.

## Diagnostics

| Code | Reason | Level |
|---|---|---|
| `DV-APIKEY-001` | a scope names a policy action that does not exist | `error` |
| `DV-APIKEY-002` | call refused: the key's scopes do not cover the action | `warning` |
| `DV-APIKEY-003` | rotation overlap expired; the previous key no longer authenticates | `info` |
| `DV-APIKEY-004` | an OAuth client registration asked for an undefined scope | `error` |
| `DV-APIKEY-005` | a key was issued with no expiry where the configuration requires one | `warning` |
| `DV-APIKEY-006` | a key exceeded its rate plan; the call was throttled | `warning` |

## Deliberately absent

- **A second authorization system.** Scopes name policy actions; `@DVPolicy`
  decides.
- **A gateway.** Third-party calls run the application's own request
  lifecycle; a parallel path would be a second place for tenant filters and
  audit to be wrong.
- **Dartvel as an identity provider.** The application becomes an OAuth
  provider for its own users. Running an IdP product is not a framework
  feature.

---

# Outbound Webhooks

Stability: `Draft` · Status: `Designed`

The security scope verifies webhooks the application *receives*. An
application that is a platform for its own customers has to *send* them, and
that is a queue, a signing scheme, a retry policy, a dead-letter list and a
delivery log — built badly once by every team that needs it, usually the week
after a customer asks why an event never arrived.

Subscriptions are generated models, so an endpoint belongs to a tenant, is
listed on a settings page and is authorized like any other row:

```dart
await DV.Webhooks.emit('order.shipped', order);
```

## The catalog is declared

```dart
@DVWebhookEvents()
abstract class _Events {
  @DVWebhookEvent(payload: Order)
  static const orderShipped = 'order.shipped';

  @DVWebhookEvent(payload: Order, on: DVModelLifecycle.created)
  static const orderCreated = 'order.created';
}
```

An event either comes from a model's lifecycle or is emitted explicitly; both
are declared in one place, and emitting a name that is not there is a build
error (`DV-WEBHOOK-006`). The same declaration generates the event catalog
the application publishes in its own API documentation, so the list a customer
reads cannot drift from the list the code can send.

Payload shape is versioned by the machinery Protocol Versioning and Client
Compatibility already defines. A subscription records the protocol version it
was created against, and a shape change that would break it is the same
build-time refusal a client-facing change is — a customer's endpoint is a
client, and it is the one client that cannot be asked to upgrade.

**Serialization honours `@DVModel.sensitiveField()` by construction.** A
sensitive field is absent from a delivery the way it is absent from a log,
and asking for one explicitly in a payload is a build error
(`DV-WEBHOOK-001`) rather than a runtime redaction somebody can configure
away. The endpoint at the other end belongs to somebody else; this is the one
serializer whose output the application cannot recall.

## Signing, and rotating without a gap

Each delivery carries a timestamp and an HMAC-SHA256 signature over
`timestamp.body`, with the key held in Secrets and Environments and scoped to
the subscription. Rotation sends **both** signatures for an overlap the
application configures, so a customer can switch keys without a window in
which every delivery fails verification (`DV-WEBHOOK-007`). A rotation that
requires simultaneous deployment on both sides is a rotation nobody performs.

The timestamp is in the signed material so a captured delivery cannot be
replayed a month later, and the documentation Dartvel generates for the
customer says to compare in constant time and to bound the age — the two
things a consumer implementation gets wrong.

## Delivery is durable work, partitioned per endpoint

Deliveries ride `DV.Jobs` with the retry, backoff and dead-letter behaviour
that already exists. What this section adds is the partitioning:

- Ordering is per subscription. Two events for one endpoint arrive in the
  order they were emitted, and head-of-line blocking within that endpoint is
  the point rather than a defect.
- Concurrency and in-flight depth are per subscription too, so **a consumer
  that takes thirty seconds to answer delays its own deliveries and nobody
  else's**. Without that, one customer's degraded endpoint is an outage for
  every other customer's webhooks, which is the failure this design exists to
  prevent.
- Delivery is at-least-once and each carries a stable delivery id in a
  header, because the honest alternative — exactly-once across a network to
  somebody else's server — does not exist.

An endpoint that keeps failing is disabled rather than retried forever: after
the configured run of consecutive failures it is marked disabled, the owner is
notified through `DV.Notifications`, and its queue stops (`DV-WEBHOOK-003`).
A dead endpoint that is retried indefinitely is a slow, permanent tax on the
queue and on the receiving host.

## The endpoint address is untrusted input

A subscription URL is supplied by a customer and fetched by the application's
own server, which is a server-side request forgery in every deployment that
does not think about it. **Dartvel resolves the host and refuses private,
loopback, link-local and cloud-metadata addresses** (`DV-WEBHOOK-002`), and
refuses a redirect that lands on one. `169.254.169.254` is not an edge case;
it is the first thing anyone tries.

```yaml
dartvel:
  webhooks:
    allowPrivateAddresses: false   # true only for a deployment with no metadata service
    retention: 30d
    disableAfter: 20
```

## Retention and replay

Every delivery is recorded — the event, the endpoint, the attempt count, the
response status and the timing — and Studio's inspector shows them with the
payload, which is what turns "we never got it" into an answer.

The **payload** is kept for `retention` and the **record** is kept
indefinitely. Replay works while the payload is there, and a replay requested
after retention is refused with `DV-WEBHOOK-005` rather than resent with an
empty body: a delivery whose payload is gone can be explained, and one that
arrives empty cannot be distinguished from a real event.

## Diagnostics

| Code | Reason | Level |
|---|---|---|
| `DV-WEBHOOK-001` | a payload names a field the model marks sensitive | build `error` |
| `DV-WEBHOOK-002` | endpoint resolved to a private, loopback, link-local or metadata address; refused | `warning` |
| `DV-WEBHOOK-003` | endpoint disabled after the configured run of failures | `warning` |
| `DV-WEBHOOK-004` | delivery exhausted its retries and moved to dead letters | `warning` |
| `DV-WEBHOOK-005` | replay requested after the payload retention window | `warning` |
| `DV-WEBHOOK-006` | an emitted event name is not in the declared catalog | build `error` |
| `DV-WEBHOOK-007` | signing key rotated; both signatures are sent until the overlap ends | `info` |

## Deliberately absent

- **A second queue.** Deliveries are jobs. There is no webhook worker, no
  webhook broker and no `DV.Webhooks` scheduler beyond the emit call.
- **Exactly-once delivery.** At-least-once with a delivery id, and the
  documentation tells the consumer to deduplicate on it.
- **Consumer SDKs.** Dartvel generates the catalog and the verification
  instructions; a customer's language is their business.
- **Arbitrary transports.** HTTPS POST. A queue-to-queue integration is a
  different feature and would not share this section's answers.

---

# Model Sync and Presence

Stability: `Contract` · Status: `Shipped`

Dartvel does not expose a separate `DV.Realtime` namespace. Do not add one.
Model sync and presence are generated capabilities built from models, signals,
and queues, not a separate realtime facade.

- model sync
- collection sync
- generated model subscriptions
- presence generated from authenticated model/session state, via
  `DVPresence` — channel membership keyed on identity rather than
  connection, tenant-scoped, expiring on silence because a crashed
  client never sends a departure
- collaborative editing through generated model operations
- reactive models
- WebSockets/SSE transport under the generated layer
- pub/sub rooms and topics as implementation details
- heartbeat and reconnect policies
- backpressure-aware streams
- horizontal fanout through Redis/Valkey, NATS, Kafka, or provider adapters
- no public `DV.Realtime`, `DVRealtime`, `@DVRealtime`, or realtime-specific
  namespace; generated clients expose model-aware APIs instead

```dart
final user = await User.find(id);
final userSignal = user.signal(context);

await user.sync();
await User.watch((users) {
  context.signal(users);
});
```

---

# Offline-First Models

Stability: `Draft` · Status: `Designed`

Model Sync and Presence specifies the connected case. Devices are not reliably
connected: phones lose signal in lifts, on trains and in basements, and a kiosk
may run isolated for days. Without a framework answer every application
hand-rolls a cache, a queue and a merge — the highest-defect corner of mobile
work, and three chances to lose somebody's writes.

Offline behaviour is declared on the model and generated:

```dart
@DVModel(offline: DVOffline(strategy: DVConflict.lastWriteWins, encrypt: true))
class _Order(
    String reference,
    int quantity,
);
```

Application code does not branch on connectivity. `Order.find`, `order.save`
and `Order.watch` read and write the same way in a tunnel as on Wi-Fi; what
changes is where the answer comes from and when the write reaches the server.

## The local store

The generated store is per target, and its schema comes from the same schema
diff that generates the server migration — not a second description of the same
model, which is how the two drift:

| Target | Store |
|---|---|
| Android, iOS, macOS, Windows, Linux, embedded, TV | SQLite through the adapter Dartvel already ships, WAL where supported |
| Web (JS and wasm) | IndexedDB |
| Any target with no writable storage | memory-backed, and it says so |

The memory-backed case is a declared degradation (`DV-OFFLINE-001`), not a
silent one: an application that cannot persist should know before somebody
closes the lid, and a kiosk with a read-only root is a real deployment.

A device holds only what its session may read. The local store is written
through the same policy engine and tenant scope as any query, so signing out
clears it, and a user cannot end up holding rows a server would have refused
them. Fields marked `@DVModel.sensitiveField()` are encrypted at rest with the
per-device application key from Secrets and Environments; `encrypt: true`
extends that to the whole model.

## The mutation log

Writes made offline append to a per-model mutation log and replay **in order**
through the existing sync transport when the device reconnects. There is no new
transport, no new namespace, and no second queue: replay is dispatched through
`DV.Jobs`/`DVQueues` like any other durable work, and reuses its retries,
backoff and dead letters.

```yaml
dartvel:
  offline:
    queue:
      maxMutations: 10000
      maxAge: 7d
```

The log is bounded, because an unbounded one on a device is a disk filling up
where nobody can see it. **At the bound, the next write is refused with a typed
failure; the oldest is never dropped.** Dropping the oldest keeps the app
feeling fine while silently discarding work somebody believed was saved, and no
later sync can recover it. A refusal is visible at the moment it happens, which
is when the application can tell the person and when they still remember what
they were doing (`DV-OFFLINE-002`).

A mutation the server rejects permanently — failed validation, refused
authorization — is not retried forever. It moves to the dead-letter list the
queue machinery already has, where `Order.pendingMutations` exposes it, so the
application can show the conflict and let somebody resolve it
(`DV-OFFLINE-003`).

## Conflicts

```dart
@DVModel(offline: DVOffline(strategy: DVConflict.fieldMerge))
class _Profile(
    String displayName,
    String bio,
);
```

| Strategy | Resolution |
|---|---|
| `lastWriteWins` | the later write by declared clock, whole model |
| `serverWins` | the local change is discarded and reported |
| `fieldMerge` | per field, the later write by declared clock |
| `DVConflict.resolver(fn)` | a typed resolver the application writes, given both versions |

The same enum answers the online case, where the writer is present to be
asked: see Record History and Optimistic Concurrency. `DVConflict.ask` is
that section's online default and is not legal as an offline strategy,
because offline there is nobody to ask (`DV-HISTORY-002`).

`fieldMerge` is per-field last-writer-wins, and it is deliberately not a CRDT.
A CRDT for collaborative text needs per-field merge state in both the stored
representation and the wire format, and shipping half of one would freeze a
format that the full version then has to break. Collaborative editing rides
generated model operations over live sync, where it already belongs; CRDT
merge, if it lands, extends `fieldMerge` later without changing what
applications wrote against it.

Clocks are declared rather than assumed: a device clock that is wrong by a day
would otherwise win every conflict for a day. The default is the server's
commit timestamp with a per-device monotonic counter for ordering local writes
between syncs, and skew beyond `offline.maxClockSkew` reports
`DV-OFFLINE-004`.

## What the application sees

```dart
final orders = Order.watch();          // local first, then live
order.syncState.listen((state) { });   // pending, syncing, synced, conflicted, rejected
Order.pendingMutations;                // what has not reached the server yet
```

Sync state is generated signals on the model, like every other reactive value
in Dartvel. There is no `DV.Offline` facade to consult, because the state
belongs to the data, not to a global.

## Diagnostics

| Code | Reason | Level |
|---|---|---|
| `DV-OFFLINE-001` | no writable storage; the store is memory-backed for this session | `warning` at boot, once |
| `DV-OFFLINE-002` | mutation log at its bound; the write was refused | `error`, surfaced to the application |
| `DV-OFFLINE-003` | mutation permanently rejected by the server; moved to dead letters | `warning` |
| `DV-OFFLINE-004` | device clock skew beyond the configured tolerance | `warning`, once per session |
| `DV-OFFLINE-005` | offline model has no conflict strategy for a field type it merges | build `error` |
| `DV-OFFLINE-006` | local store schema behind the protocol; store rebuilt from the server | `info` |

`DV-OFFLINE-006` is the tie to Protocol Versioning and Client Compatibility:
the local store is a client-side copy of a shape, so when the protocol moves
past what the device holds, the store is rebuilt rather than migrated in place.
Rebuilding is cheap and always correct; migrating a device database through a
schema change nobody can inspect is neither.

## Deliberately absent

- **A second realtime or offline namespace.** Replay rides model sync and the
  queue machinery. There is no `DV.Offline`, `DVOfflineManager`, or offline
  event system.
- **Offline authorization decisions.** A device enforces what it was told when
  it last synced and never invents a permission; a write that needed a check
  the device could not make is queued and decided by the server.
- **Background replay with no app.** Replay happens when the application runs;
  what a platform allows in the background is the client-schedule question, and
  it is answered there.

---

# Mail and Notifications

Stability: `Contract` · Status: `Partial`

Dartvel provides an application notification layer, not just low-level device
notification APIs.

```dart
await DV.Notifications.mail.send(
  DVMailMessage(
    from: DVMailAddress('support@example.com'),
    to: [DVMailAddress(user.email)],
    subject: 'Welcome',
    text: 'Thanks for joining',
  ),
);

await DV.Notifications.send(
  user.id,
  DVNotificationMessage(
    title: 'Order shipped',
    body: 'Your order is on the way',
    channels: [
      DVNotificationChannel.email,
      DVNotificationChannel.push,
      DVNotificationChannel.inApp,
    ],
  ),
);
```

Mail:
- typed `DVMailMessage`, `DVMailAddress`, attachments, headers, tags, and
  priority
- templates for text, HTML, and Markdown
- localized templates
- queued sending by default
- provider adapters for SMTP, SES, SendGrid, Mailgun, Postmark, Resend, and
  local/test
- delivery receipts and bounce/complaint webhooks as typed backend functions
- per-tenant sender identities and DKIM/SPF validation checks

Channels:
- email
- in-app
- database notifications
- push
- web push fallback
- SMS
- model sync

Push providers:
- Firebase Cloud Messaging for Android and supported Flutter targets
- APNS for Apple platforms
- Web Push for browsers and browser extensions
- Windows notification platform
- macOS notification platform
- Linux desktop notification portals where available
- Amazon/Tizen/webOS notification capabilities where available
- local/test provider

Runtime behavior:
- `DV.Notifications.send(...)` chooses channels from user preferences,
  notification defaults, and provider availability. Push is preferred where
  available.
- Push delivery falls back to Web Push when a browser/web target cannot use a
  native push provider.
- In-app notifications are model sync signals plus durable inbox records.
- Notification delivery is queued and retryable.
- Provider failures emit observability events and can fall back to secondary
  providers.
- Notification permissions are declared in `pubspec.yaml` and validated at
  build time.
- The `Notification` class exists as a DVModel.

Native push registration and delivery adapters must use generated FFI/ffigen or
JNI/jnigen bindings where native code is required. Browser push uses generated
web bindings. Dartvel must not use Flutter platform channels for these APIs.

Notification features:
- user notification preferences
- quiet hours
- templates
- localization
- delivery receipts
- retries
- queued delivery
- provider fallback
- unsubscribe management
- notification inboxes
- topic subscriptions
- device token registration
- token rotation and revocation
- per-channel rate limits
- tenant-aware branding

---

# File Storage

Stability: `Contract` · Status: `Shipped`

Unified API, supports:

- S3 (And s3 compatible, e.g MiniIO)
- Cloudflare R2
- Azure Blob
- Google Cloud Storage
- Local
- In-memory blobs (zram if supported, or raw blobs)

`DV.FileStorage.*`

```dart
await DV.FileStorage.put("avatar.png", bytes);
final bytes = await DV.FileStorage.get("avatar.png");
await DV.FileStorage.delete("avatar.png");
```

Streams:
```dart
await DV.FileStorage.putStream("avatar.png", bytesStream);
final bytesStream = await DV.FileStorage.getStream("avatar.png");
```

`DV.FileStorage` is the canonical surface, and `DV.BlobStorage` is an alias
for it. `DV.Storage` is a third name for the same storage, deprecated: it keeps
working and is removed in the next minor. The framework's own code calls the
canonical name, and a test fails if anything under `lib/` reaches for the
deprecated one, because a framework that calls its own deprecated name teaches
every reader to call it too.


---


# Cache

Stability: `Contract` · Status: `Shipped`

Unified cache layer.

- In-Memory
- Memcache
- Redis (Or Valkey)
- Distributed cache

Cache invalidation and revalidation are first-class:

```dart
await DV.Cache.set('users:list', users, const Duration(minutes: 5));
DV.Cache.tag('users:list', ['users']);
DV.Cache.revalidateTag('users');
```

Caches are per client by default and automatically prefixed by Dartvel.
Permissioned global helpers such as `DV.Cache.globalSet`,
`DV.Cache.globalGet`, `DV.Cache.globalTag`, and
`DV.Cache.globalRevalidateTag` use the backend/global cache when configured.

Supports:
- model query cache
- backend function cache
- page/data cache
- route cache
- cache tags
- stale-while-revalidate
- tenant-aware cache keys
- cache locks
- stampede protection
- generated invalidation from model writes

Rules:
- Cache keys are strongly typed where generated from models/functions.
- Model writes emit invalidation signals for affected model, relation, tenant,
  and custom tags.
- Backend functions can opt into caching with annotations or generated config.
- Page data cache must respect auth, tenant, locale, and policy context.
- Stale-while-revalidate returns stale data only when the policy/auth/tenant
  scope still matches.
- Cache locks prevent stampedes around expensive model queries and backend
  functions.
- Distributed providers must implement atomic compare-and-set or explicit
  lock APIs before Dartvel enables stampede protection.

CLI:

```bash
dartvel cache clear
dartvel cache revalidate users
dartvel cache inspect users:list
```

---

# Multi-tenancy

Stability: `Contract` · Status: `Partial`

- Enabled by default
- Shared database or Schema per tenant or Database per tenant
- Automatic tenant resolution
- Automatic filtering

```dart
DV.currentTenant // alias for DV.Tenants.currentTenant
```

---

# Organizations, Membership and Invitations

Stability: `Draft` · Status: `Designed`

Multi-tenancy resolves a tenant and filters every query by it. It says nothing
about the people inside one. Organizations, roles per organization,
invitations, seats and ownership transfer are in every business application,
and today each is a hand-written model set that authorization, billing and
Studio then have to be taught about one at a time.

## A tenant is not an organization

They are related and they are not the same thing, and the specification says
which is which because leaving it ambiguous puts the question in every
application's schema.

**A tenant is a data boundary.** It decides which rows a request may see,
which schema or database it reads, and how a request resolves to one. It has
to be stable for the life of the data: it appears in every row, in the
schema or database name, and in backups.

**An organization is a group of people.** It has a name somebody chose, roles,
members who come and go, an owner who may hand it over, and it can be renamed,
merged or closed.

One organization has exactly one tenant. A tenant may exist with no
organization at all.

Merging them reads as a simplification until the first rename: renaming a
group of people would move data, transferring ownership would rewrite a
boundary that backups refer to, and closing an organization would mean dropping
a database while an export is still running. Keeping them apart costs one
reference:

```dart
DV.currentTenant                 // the boundary, resolved per request
DV.Auth.currentMembership        // this person's role in the organization on it
```

## What is generated

```yaml
dartvel:
  organizations:
    roles: [owner, admin, member, billing]
    personalTenants: true       # consumer default; see below
    seats: paid                 # counted for Billing
```

`Organization`, `Membership` and `Invitation` are generated models with their
policies attached, so authorization sees them like any other model rather than
through a parallel permission system. Roles are a typed enum, not strings: a
policy that names a role that does not exist fails the build rather than
silently refusing everybody at run time (`DV-ORG-001`).

```dart
@DVPolicy()
bool _canInvite(DVContext context) =>
    context.membership.role >= DVOrgRole.admin;
```

Generated components come with them — `Organization.Members()`,
`Organization.Invitations()`, the accept-invitation page — assembled from the
same primitives as `User.Table()` and replaceable the same way.

## Invitations

Invitations reuse Authentication's token machinery rather than inventing a
second one: `DVAuthTokens.issueMagicLink` and `issueOtp` already mint,
expire and redeem single-use tokens, and an invitation is one of those with a
membership attached.

```dart
await Organization.invite(email, role: DVOrgRole.member);
```

Three ways in, all landing on the same `Membership`:

- an emailed link or code, redeemed by whoever holds it;
- SSO domain auto-join, where an identity from a verified domain becomes a
  member on first sign-in at a declared role;
- a per-organization SAML or LDAP bind, using the providers Authentication
  already lists, for tenants whose identity is their own.

An invitation to an address that is already a member is refused rather than
creating a second membership (`DV-ORG-002`), and a redeemed invitation cannot
be redeemed again, which is the token machinery's own guarantee rather than a
check somebody remembered to write.

## Personal tenants

**Consumer applications get a tenant per person and no organization.**
`personalTenants: true` is the default when no roles are declared. The boundary
is worth having even for one person — it is what makes "export my data" and
"delete my account" answerable — but a membership table for a party of one is
ceremony, and it turns every query in a consumer app into a join nobody needs.

An application that later declares roles does not migrate its data: the tenant
each person already has acquires an organization, and their membership is the
owner.

## Seats and ownership

Seat count is a query over memberships, and Billing reads it rather than
keeping a second counter that drifts from the truth. What counts as a seat is
declared, because the answer differs by product: every member, or only those at
a role, or only those who signed in this period.

Ownership transfer and closing an organization are reversible transactions.
Transfer moves the owner role and records who did it; closing is a soft delete
with a grace period, restorable until its retention expires, because an
organization closed by accident takes everybody's work with it
(`DV-ORG-004`). The last owner cannot leave or be demoted without naming a
successor (`DV-ORG-003`).

## Studio

Studio shows the organizations on a deployment, their members and pending
invitations, and who changed a role and when — which is Record History and
Optimistic Concurrency reading `Membership.history()`, not a second audit
trail.

## Diagnostics

| Code | Reason | Level |
|---|---|---|
| `DV-ORG-001` | a policy names a role the application does not declare | `error` |
| `DV-ORG-002` | invitation refused: the address is already a member | `warning` |
| `DV-ORG-003` | the last owner cannot leave or be demoted without a successor | `error` |
| `DV-ORG-004` | organization closed; restorable until the declared grace period expires | `info` |
| `DV-ORG-005` | SSO domain auto-join declined: the identity's domain is not verified | `warning` |
| `DV-ORG-006` | membership resolved on a tenant that has no organization | `error` |

## Deliberately absent

- **Nested organizations.** A parent and child tree changes every
  authorization question — whether a parent's admin reads a child's data is
  product-specific, and the framework answering it wrongly is worse than not
  answering. Applications that need a hierarchy model it over memberships.
- **A second permission system.** Roles feed `@DVPolicy`; authorization stays
  where it is.
- **Organization-scoped billing accounts as a separate concept.** An
  organization has one tenant and Billing bills a tenant.

---

# SEO

Stability: `Contract` · Status: `Shipped`

Global defaults

```yaml
dartvel:
  seo:
```

Per-page SEO is provided by generated/class page metadata and applied by the
generated router through `DartvelSeo`.

Supports:
- OpenGraph
- Twitter
- Structured data and content schema
- Meta tags

---

# PWA

Stability: `Draft` · Status: `Shipped`

- Enabled by default.

Automatic:
* Manifest
* Service Worker
* Offline support
* Install prompts
* Icons
* Background sync
* Permission handling
* Web capabilities where supported, exposed through `DV.Platform`

---

# Feature Flags and Staged Rollout

Stability: `Draft` · Status: `Designed`

A flag is a decision the application ships without having made: whether the
new checkout is on, which recommender runs, how many rows a list loads. It
exists so the decision can change without a release — and, when something is
wrong at two in the morning, so it can change in seconds rather than in a
store review.

Flags are declared, typed and dated. A bag of remote strings is what this
replaces.

```dart
@DVFlags()
abstract class _Flags {
  /// The rewritten checkout. Kill switch for the payments team.
  @DVFlag(owner: 'payments', expires: '2026-12-01')
  static const bool newCheckout = false;

  @DVFlag(owner: 'search', expires: '2026-11-01')
  static const String recommender = 'baseline';

  @DVFlag(owner: 'feed', expires: '2027-02-01')
  static const int pageSize = 20;
}
```

The generated `Flags.newCheckout` is a read-only signal, so a widget guarded
on a flag rebuilds when the rules change under it, and a flag composes with
the rest of the state layer without a second mechanism:
`Flags.newCheckout & user.isStaff` is a signal too.

The value written in Dart is the **default compiled into the binary**, not a
placeholder. It is what the flag answers before anything has synced, and it is
what every fallback below falls back to, which is why it is written where the
reviewer of the pull request can see it.

Flags carry `bool`, `String`, `int`, `double` and declared enums. They do not
carry maps or JSON: a flag holding a structure is configuration, Configuration
is already declared elsewhere, and the two drift the moment one of them is
edited in a console.

## Where a flag is evaluated

**On the client, from rules the client has synced.** The alternative — asking
the backend for each flag and caching the answer — is simpler to draw and
fails the two cases that decide whether flags are usable at all: the first
frame after a cold launch, and a device with no network.

The backend publishes one `DVFlagRules` document per environment: every flag
the deployment knows, its rules, and a `rulesVersion`. It travels on the
channel model sync already uses and lands in the same local store, so flag
rules are present exactly when synced models are, and a client that can read
its own data can answer its own flags.

Evaluation is a pure function of the rule set and an evaluation context —
identity, tenant, organization role, app version, platform, locale, and any
attributes the application declares. Given the same two inputs, a client and
the backend reach the same answer, which is the property that makes
client-side evaluation safe to reason about.

A read resolves in this order:

1. a local override, in a debug build only;
2. the synced rule set;
3. the default compiled into the build.

## Offline

A flag always has an answer, and the answer never becomes an error.

With no rule set yet synced — first launch, air-gapped device, a store on the
declared memory-backed degradation of `DV-OFFLINE-001`, which loses its
contents at every cold start — every flag answers with its compiled default
and `DV-FLAGS-001` says so once.

With a rule set synced and the network gone, the rules stay in force. **Stale
rules are used, not discarded.** A kill switch that expires back to "on"
because nobody could reach the server is worse than one that is a day out of
date, and discarding rules on a staleness deadline would turn a disabled
feature back on for precisely the users who are hardest to reach. `flags.maxAge`
therefore reports rather than expires: past it, `DV-FLAGS-009` fires on each
resolve attempt and the old answers keep being given.

Flag rules are not user data and hold no mutation log. Nothing is written
offline and replayed, so none of the conflict strategies in Offline-First
Models apply to them; a flag changed on the server while a client was offline
simply takes effect at the next sync.

## Staged rollout

```dart
DVFlagRollout.percentage(25, by: DVFlagSubject.user)
DVFlagRollout.percentage(10, by: DVFlagSubject.tenant)
DVFlagRollout.percentage(5, by: DVFlagSubject.device)
```

A subject's bucket is the first eight bytes of `SHA-256("$flagKey:$subjectId")`
modulo 10,000, and the flag is on when the bucket is below the threshold.
Three consequences follow from that arithmetic and they are the reasons for
it: the same person gets the same answer on every device and after every
reinstall without anything being stored; two flags at ten percent do not pick
the same tenth of the population, because the flag key is inside the hash; and
raising 10 to 20 never drops anyone who was already in.

A rollout whose subject is absent at evaluation — `by: DVFlagSubject.user`
while nobody is signed in — holds the flag at its default and reports
`DV-FLAGS-005`. It does not roll a die. A flag that flickers between two
frames is a bug report nobody can reproduce.

Rules also target directly: an app-version range, a platform, a tenant, an
organization role, a locale, or a declared attribute. Targeting composes with
a rollout — a percentage *within* a targeted population.

By default a changed rule takes effect as soon as it syncs, because a kill
switch that waits for a relaunch has not switched anything off. A flag whose
mid-session flip would strand somebody halfway through a flow declares
`settle: DVFlagSettle.onNextLaunch`, and its value is then pinned for the
process.

## On the backend

A backend function reads the same generated accessor. The evaluation context
is the request's own — the authenticated identity, `DV.currentTenant`, the
calling client's version — and the rules are the deployment's, never stale.

Client and server can disagree for the length of one sync, and the
specification says which wins rather than pretending they cannot: **the
client's answer decides what the client shows, the server's decides what the
server does.** Anything guarded on both sides must tolerate a client that is
briefly ahead or behind. When a disagreement is not tolerable — a flag gating
who may be charged — the guard belongs on the server and the client should
ask, which is a backend function and a `@DVPolicy`, not a flag.

A flag is never an authorization decision. Hiding a button is presentation;
who may act stays in `@DVPolicy`.

## Flags and OTA Updates

OTA Updates stages a *binary*: which code a device runs, gated on crash and
health signals. A flag stages *behaviour inside* a binary that every device
already has. The flag is the faster of the two by a wide margin — no patch to
download, no store, no restart — so a kill switch is the first response to an
incident and a rollback is the second.

The same health gates read both. A rollout whose cohort's crash rate crosses
the declared threshold is held, and `dartvel flags off` is what the gate
calls.

## Exposure

An exposure is recorded the first time a flag is resolved for a given
evaluation context in a session, as the Product Analytics event
`dartvel.flag_exposed` carrying the flag key, the value served, and the
`rulesVersion` that served it. Once per session, not per read: a flag read in
a build method would otherwise produce an event per frame.

Exposure is an analytics event and obeys consent like any other. Where consent
for the declared category is withheld, nothing is recorded and `DV-FLAGS-007`
reports the omission, because an experiment missing exposures from everyone
who refused tracking has a biased result, and the bias is invisible unless
something says it is there.

Dartvel assigns the cohort and records the exposure. It does not compute
significance; the events land in Product Analytics like the rest.

## Overrides

```bash
dartvel flags override newCheckout --on
dartvel flags override --clear
```

Overrides are for development and tests, are stored locally, and are compiled
out of release builds — a release binary has no code path that reads one. A
debug build running with an override in force reports `DV-FLAGS-008` at each
resolve, so a "it works on my machine" that is really "my override is on" is
visible in the log rather than in a post-mortem.

In tests, `DVFlags.withOverrides({...}, () async { ... })` scopes overrides to
the callback, and a test's flags never leak into the next one.

## CLI

```bash
dartvel flags list                       # every declared flag, rule and owner
dartvel flags status newCheckout
dartvel flags set newCheckout --on --environment production
dartvel flags rollout newCheckout --percentage 25 --by user
dartvel flags off newCheckout            # the kill switch, one word
dartvel flags prune                      # flags past their expiry
```

Flags are debt with an owner and a date on them. `expires:` is required, the
build warns past it with `DV-FLAGS-004`, and `dartvel flags prune` lists what
is due for deletion — with the code paths each flag still guards, from the
project graph.

## Studio

Studio shows each flag, who owns it, the rule in force per environment, the
rollout and its bucket count, and exposures over time. A rule changed in
Studio is a model write like any other, so Record History answers who turned
what off at 02:00 without a second audit trail.

## Diagnostics

| Code | Reason | Level |
|---|---|---|
| `DV-FLAGS-001` | no rule set has synced; flags answered with the defaults compiled into the build | `info` |
| `DV-FLAGS-002` | the synced rule set names a flag this build does not declare | `warning` |
| `DV-FLAGS-003` | the rule set is newer than this build understands; unreadable rules were skipped | `warning` |
| `DV-FLAGS-004` | a flag is past its declared expiry | `warning` |
| `DV-FLAGS-005` | a percentage rollout was evaluated with no subject identifier; the flag held its default | `error` |
| `DV-FLAGS-006` | a rule's value type differs from the flag's declared type; the flag held its default | `error` |
| `DV-FLAGS-007` | exposure not recorded: consent was withheld for the declared analytics category | `info` |
| `DV-FLAGS-008` | a local override is in force; this build is not answering from the rules | `warning` |
| `DV-FLAGS-009` | the rule set is older than `flags.maxAge` and is still in use | `warning` |

## Deliberately absent

- **Remote configuration.** A flag is typed, owned, dated and pruned. An
  untyped key-value service edited in a console is the thing this exists to
  stop, and adding one beside it would make the flag layer optional.
- **A per-read network call.** Every design that fetches a flag on demand has
  a story for the offline case, and the story is always a timeout in front of
  a frame.
- **Random assignment.** Bucketing is a hash of a stable identifier, so
  nothing is stored, nothing needs migrating, and nobody is reassigned by a
  reinstall.
- **A statistics engine.** Assignment and exposure are Dartvel's; reading the
  result is Product Analytics' and, past that, the reader's own tooling.
- **Flags that change schema, policy or pricing.** Schema Evolution, `@DVPolicy`
  and Billing each have an owner, and a flag that could silently overrule one
  of them would make all three unreadable.

---

# OTA Updates

Stability: `Contract` · Status: `Partial`

Dartvel uses Shorebird for Flutter OTA updates.

```bash
dartvel updates release
dartvel updates patch
dartvel updates rollback
```

Runtime surface:

```dart
final update = await DV.Updates.check();
if (update.available) {
  await DV.Updates.apply();
}

// also: DV.Updates.lockVersion(), DV.Updates.skipImmediateNextVersion(), DV.Updates.rollback()
```

Runtime update checks/apply/rollback use generated bindings named
`updates.check`, `updates.apply`, and `updates.rollback`. Native update
integration must use Shorebird-compatible generated bindings through
FFI/ffigen or JNI/jnigen where native glue is needed. Dartvel must not use
Flutter platform channels for OTA APIs.

Supports:
- channels
- staged rollouts
- forced update prompts
- minimum supported app versions
- rollback
- update health checks
- release notes
- environment targeting
- CI integration
- patch provenance metadata
- crash/health rollback gates
- tenant or cohort targeting where allowed by the store/runtime
- offline update state reporting
- generated update UI primitives built from `DVBox` and `DVText`

Server-side code is versioned separately from client OTA patches. A release/tag
must still create a matching backup branch.

Release safety:
- `dartvel updates patch` refuses to run from a dirty worktree unless
  `--allow-dirty` is passed.
- every OTA patch records the Git commit SHA, Dartvel version, Flutter version,
  Shorebird version, and target channel
- release/tag publishing must create the matching backup branch before or
  immediately after the tag/release is pushed
- if the intended tag already exists, Dartvel increments the patch version and
  creates a new tag/release/backup branch instead of reusing the old name

---

# Protocol Versioning and Client Compatibility

Stability: `Draft` · Status: `Designed`

The backend deploys daily; installed binaries live for weeks. Migrations handle
schema change on the server, OTA handles code change on the client, and neither
answers the question between them: what happens when a three-week-old binary
calls today's backend. On mobile that is not an edge case, it is the permanent
condition — the framework does not decide when people update — and with no
answer here the problem lands on every application team separately, which is
the situation Dartvel exists to end.

## The protocol version

Every build embeds a **protocol version**: an integer over the shapes a client
and a backend must agree on — model fields and their types, backend function
signatures, and the sync schema. It is derived from the project graph, so it
moves when the contract moves and not when anything else does. Most releases do
not touch it. Renaming a field, narrowing a type, or adding a required argument
does.

```json
{ "protocol": 7, "shape": "3f2ad9c1", "released": "2026-09-12" }
```

`shape` is the digest of the contract the integer stands for, and the build
compares the two: a change that alters the shape without incrementing the
integer fails the build (`DV-PROTO-001`) rather than shipping two different
contracts under one number. The lockfile is committed, so the history of the
protocol is in the repository next to the code that changed it.

## The window

The backend declares how far back it serves:

```yaml
dartvel:
  protocol:
    window: 3          # this version plus three previous
    minimumAge: 90d    # and never narrower than this
```

The default is three protocol versions or 90 days, whichever is **longer**.
Two numbers rather than one because either alone is wrong on a real schedule:
a team that ships weekly would strand a month-old install with three versions,
and a team that ships twice a year would carry adapters nobody needs with 90
days. The window is a floor, not a policy — what actually gates a deploy is the
client histogram below.

Serving a windowed version needs serialization adapters between it and the
current shape. They are **generated at build, for every version in the window**,
from the same schema diffs that produce migrations. Not lazily, per observed
client version: a lazy adapter is generated on a production server, in response
to a request from a stale client, along a path no test ever ran — and Dartvel
generates at build everywhere else for the same reason. The set is bounded by
the window, the diff already exists, and a generated adapter can be read in
review before it runs.

## Handshake

```dart
switch (await DV.Protocol.handshake()) {
  case DVProtocolResult.compatible:
    break;
  case DVProtocolResult.degraded:
    break;                       // typed, reported, and already applied
  case DVProtocolResult.upgradeRequired:
    break;                       // generated upgrade flow
}
```

The handshake runs before the first call a page makes, and its result is a
signal (`DV.Protocol.state`) so a page can show what it means rather than
discovering it through a failure.

**`degraded` may only hide what the old client never knew.** Without an
explicit opt-in, an adapter may:

- omit a field the old client's shape does not contain
- supply the server-side default for a new optional argument the old client
  does not send
- map a new enum member to the fallback member that enum declares — and where
  it declares none, this is `upgradeRequired`, not a guess
- serve a model, route, or function the old client never calls

It may not, without opt-in, change the meaning of anything the old client
already understands: no narrowing a type, no dropping a field the old shape
requires, no changing units or semantics in place, no rename without an alias,
and no loosening of authorization or validation. The line is that a degraded
response must still be *true* in the old client's vocabulary. Anything lossy is
a declared adapter, reviewed like any other code.

## Upgrading

Falling outside the window fires `DV.Upgrade.required`. Dartvel tries OTA first
— a patch that lands is an upgrade nobody had to visit a store for — and routes
to the generated upgrade page only when OTA cannot close the gap, which is the
case whenever the protocol change came with native code. The page is built from
`DVBox` and `DVText` like every other generated page, and an application may
replace it.

## The deploy gate

```bash
dartvel compatibility-check --against production
```

The candidate build's protocol is compared with the live client histogram from
monitoring — which versions are actually calling, and how much traffic each
carries. The deploy is refused when a version outside the candidate's window
still accounts for more than `protocol.strandThreshold` of sessions over the
last seven days (default `0.5%`). An override exists, takes an explicit flag,
and is logged with the histogram it overrode; stranding users is sometimes the
right call and is never a quiet one.

This is the same discipline as the migration gate in Schema Evolution, applied
to the other artifact, and the two are sequenced: a contract-breaking change
expands the schema and raises the protocol in one release, and contracts only
after the window has moved past the clients that read the old shape.

## Diagnostics

| Code | Reason | Level |
|---|---|---|
| `DV-PROTO-001` | contract shape changed without incrementing the protocol version | build `error` |
| `DV-PROTO-002` | a client outside the window called; upgrade required | `info`, per session |
| `DV-PROTO-003` | response degraded for a windowed client | `debug` |
| `DV-PROTO-004` | a lossy adaptation was requested with no declared adapter | build `error` |
| `DV-PROTO-005` | deploy would strand clients above the threshold | gate `error` |
| `DV-PROTO-006` | enum member added with no declared fallback, narrowing the window | `warning` (analyze) |

## Deliberately absent

- **Negotiation of arbitrary shapes at runtime.** The window is a declared,
  generated, reviewable set. A server that reshapes itself per caller is a
  server nobody can reason about.
- **A second transport or envelope.** The handshake rides the generated client
  and the existing sync transport.
- **Version pinning by the client.** A client states what it is; the backend
  decides what it serves.

---

# AI

Stability: `Contract` · Status: `Shipped`

First-class.

Providers:
- OpenAI
- Claude
- Gemini
- OpenRouter
- Llama/Ollama

Features
- Chat
- Embeddings (retrieval over the application's own models is Semantic Search
  and Embeddings)
- Agents
- MCP, both directions: `DVMcpServer` exposes the registered AI tools to an
  MCP client, and `DVMcpClient.adoptTools()` registers an external
  server's tools so `DV.AI` calls them like its own
- Transcription
- Structured outputs
- AI-native diagnostics
- AI project context
- Function and tool calling with `@DVAITool(description: ...)`. Tools are
  explicit opt-in by default; ordinary `@DVBackendFunction` functions are not
  exposed as AI tools unless a project-level config enables that behavior.

Tool generation:
- `dartvel build` and `dartvel routes` generate typed AI tool metadata inside
  the Dartvel client output.
- Apps import only `package:dartvel_client/dartvel_client.dart`; the generated
  barrel exports `dartvelAITools`. Do not import generated sibling files
  directly from application code.
- `dartvelAITools` is a typed `List<DVAIToolEntry>` containing the tool name,
  description, source import URI, and file path.
- Projects may set `dartvel.ai.exposeBackendFunctionsAsTools: true` in
  `pubspec.yaml` to expose backend functions as tools. Add `@DVAIHidden()` to
  a backend function that must remain private under that mode.

Framework tools are a separate registry from application tools, and the
separation is load-bearing rather than tidy:

- `dartvel mcp` serves Dartvel's own tools — the inspectors over the project
  graph, migration planning, doctor, and build validation — to a coding agent
  working on the application.
- `DVMcpServer` serves the application's tools, the ones `DV.AI.registerTool`
  and `@DVAITool` declare, to whatever the application exposes them to.

Framework tools must never enter the process-global tool registry. Application
AI tool exposure is explicit opt-in with `@DVAIHidden()` as the escape, and a
framework surface that let itself be adopted into that registry would make an
agent building the app indistinguishable from an agent the app serves to its
users — one of which can read the project's schema. The same redaction rule
applies to both: a `@DVModel.sensitiveField()` is described, never valued.

Agent-produced code has no privileged path. It passes the same typed
validation as hand-written code and carries the same provenance in source
mappings, so `dartvel inspect generated` can say what produced a given line
regardless of who asked for it.

Tool calls:
```dart
DV.AI.registerTool('sumLedger', (input) {
  final left = input['left'];
  final right = input['right'];
  if (left is! DVJsonNumber || right is! DVJsonNumber) {
    throw ArgumentError('sumLedger requires numeric left and right.');
  }
  return DVJsonNumber(left.value + right.value);
});

final result = await DV.AI.callTool('sumLedger', const {
  'left': DVJsonNumber(2),
  'right': DVJsonNumber(3),
});
```

Tool handlers use `DVJsonObject` and `DVJsonValue` (`DVJsonString`,
`DVJsonNumber`, `DVJsonBool`, `DVJsonList`, `DVJsonMap`, `DVJsonNull`) rather
than loose dynamic maps. The same metadata can map to platform equivalents such
as Android App Functions while remaining available to Dartvel-native AI and
WebMCP.

Structured outputs, transcription, and agents use the same typed JSON model:
```dart
final structured = await DV.AI.structuredOutput(
  'Summarize this ledger',
  const <String, DVJsonValue>{'summary': DVJsonString('string')},
);

final transcript = await DV.AI.transcribe(
  audioBytes,
  mimeType: 'audio/mpeg',
  language: 'en',
);

final agentResult = await DV.AI.runAgent(
  const DVAIAgentRequest(
    goal: 'Reconcile the ledger',
    context: <String, DVJsonValue>{
      'left': DVJsonNumber(4),
      'right': DVJsonNumber(6),
    },
    tools: <String>['sumLedger'],
  ),
);
```

`DVAIAdapter` providers implement chat, embeddings, typed structured output,
transcription, and agent execution. The local adapter provides deterministic
testable behavior so tests do not pass through ignored or empty AI paths.

---

# Monitoring and Observability

Stability: `Draft` · Status: `Partial`

Inspired by:
- Laravel Nightwatch
- Hasura
- Vercel
- OpenTelemetry

Built in:
- Logs
- Metrics
- Traces -- see Distributed Tracing
- Profiling
- Performance analysis
- Error reporting -- see Crash Reporting and Release Health, which is that
  line written out
- Structured diagnostics and fix-recommendations
- Structured, AI-readable logs

Application logging uses the discoverable `DV.ObservabilityAndLogging` service
and the shorter autocomplete-friendly `DV.log` shortcut:

```dart
await DV.log(
  "Checkout completed",
  {"orderId": order.id},
);

await DV.ObservabilityAndLogging.event(
  "checkout_completed",
  {"orderId": order.id},
);
```

---

# Distributed Tracing

Stability: `Draft` · Status: `Partial`

Monitoring and Observability lists traces. This is what a trace is here, what
gets a span without anybody writing one, and where the spans go — the third of
which is the part that is still missing, and is named as missing below rather
than described as though it were there.

## The wire format is not Dartvel's

Trace context travels as W3C `traceparent`:
`00-<32 hex trace id>-<16 hex span id>-<2 hex flags>`. The whole point of a
trace id is that something else recognises it — a load balancer's log, a
managed database's slow-query record, another team's service in another
language — and a proprietary header would make Dartvel the only thing that
could read its own traces.

## Sampling is decided from the trace id, once

The decision is a function of the trace id and the configured ratio, and it
**travels in the flags rather than being re-made**.

A service that rolls its own dice per process does not sample ten percent of
traces at ten percent; it keeps the whole of a four-service request with
probability 0.1⁴, which is one request in ten thousand. Everything else
becomes a fragment with a hole in the middle, and the symptom is tracing that
looks switched on and finds nothing. Deciding from the id means every service
in a trace reaches the same answer without coordinating, and a trace is whole
or absent.

Errors do not retroactively rescue an unsampled trace, and this section will
not claim they do. Keeping a whole trace because one span in it failed is
tail sampling, which needs something that has buffered the entire trace — a
collector, not a process inside it. What Dartvel does instead is local: a span
that records an error is kept in the process's own ring buffer whatever the
sampling said, and the crash report for a failure carries the trace id, so an
unsampled failure is still traceable to the request it happened in even when
the trace never left.

## What gets a span

Instrumented by the framework, from generated code rather than from calls
somebody remembered to write:

| Span | Named for |
| --- | --- |
| the inbound request | the route, and the Backend Function Request Lifecycle stage within it |
| a backend function | the function, with its arguments' shapes and none of their values |
| a database query | the statement shape — parameters are never attributes |
| an outbound HTTP call | host and path template |
| a queue publish, and the consume that follows it | the queue and the job type |
| a transaction | the `DV.transaction` boundary, with the compensations that ran |
| an AI call | the model and the token counts, not the prompt |

The ambient span hangs on the zone, so a query three calls deep becomes a
child of the request without every function in between taking a span
parameter it does not otherwise use. That threading is what stops people
instrumenting anything.

`DV.trace('name', () async { ... })` is there for the rest.

## Sensitive values are never attributes

A span attribute naming a `@DVModel.sensitiveField()` value is a build error
(`DV-TRACE-004`), the same rule analytics payloads already carry. Query spans
record the statement's shape and never its parameters, because a parameter is
where the personal data is.

Attributes are also bounded per span (`DV-TRACE-010`). An unbounded attribute
map is how a trace backend's bill becomes the reason tracing gets switched
off.

## Jobs are linked, not nested

A job enqueued by a request and run four hours later is part of the same
story and is not part of the same waterfall. The trace context travels in the
job envelope, and when the job runs outside the originating trace's window it
starts its **own** trace carrying a link back to the one that enqueued it
(`DV-TRACE-005`).

Nesting it would produce a trace whose root span lasted four hours, which no
viewer renders usefully and no p95 can be computed from. The link keeps the
connection navigable in both directions without pretending the two are one
operation.

A span still open past its declared maximum is closed as incomplete rather
than held for ever (`DV-TRACE-009`) — a leaked span is otherwise a memory leak
that also silently loses its parent's children.

## Client spans

A tap that leads to a backend call is one trace, and it starts on the device.
The generated client opens a span per call and sends the `traceparent`, so the
waterfall includes the time the network took, which is the part the server's
own numbers can never show.

**Client spans are exported through the deployment's own backend, never
straight to a collector.** Shipping an application with a collector endpoint
and a write key in it publishes both to everyone who downloads it, and what
gets written to that endpoint afterwards is no longer under anybody's control.
Ingest is off by default; a client span arriving at a deployment that has not
enabled it is refused and counted (`DV-TRACE-008`).

The client's sampling ratio is part of its build configuration and is applied
to the trace id the same way, so a client and the backend agree on the same
trace without a negotiation.

## Where spans go

```yaml
dartvel:
  tracing:
    ratio: 0.1
    exporter: otlp                # otlp | none
    endpoint: https://collector.internal:4318
    queue: 2048
    maxSpanDuration: 5m
```

OTLP over HTTP is the exporter, because Jaeger, Tempo, Honeycomb, Datadog and
the rest all accept it, and an adapter per vendor would be five copies of one
protocol.

Export is batched on a bounded queue and **never blocks a request**. A full
queue drops spans and counts them (`DV-TRACE-002`); a collector that cannot be
reached retries and then drops with a count (`DV-TRACE-003`). Neither is
allowed to add latency to the thing being measured, which is the failure mode
that makes people remove tracing rather than fix it.

With no exporter configured, spans stay in the in-process ring buffer and
`DV-TRACE-006` says so. That buffer is served at `/_dartvel/traces`, off
unless the process was started with diagnostics endpoints on — and when it is
on, `DV-TRACE-007` reports it, because an endpoint listing recent requests is
not something to discover later.

## Diagnostics

| Code | Reason | Level |
|---|---|---|
| `DV-TRACE-001` | an inbound `traceparent` was malformed; a new trace was started | `warning` |
| `DV-TRACE-002` | the export queue was full; spans were dropped | `warning` |
| `DV-TRACE-003` | the collector could not be reached; spans were dropped after the declared retries | `error` |
| `DV-TRACE-004` | a span attribute names a sensitive model field | `error` |
| `DV-TRACE-005` | a job ran outside its originating trace's window; its span is linked rather than nested | `info` |
| `DV-TRACE-006` | no exporter is configured; spans stay in the in-process buffer | `info` |
| `DV-TRACE-007` | the trace diagnostics endpoint is enabled; it is off by default | `warning` |
| `DV-TRACE-008` | a client span was refused: client ingest is not enabled on this deployment | `warning` |
| `DV-TRACE-009` | a span passed its maximum duration and was closed as incomplete | `warning` |
| `DV-TRACE-010` | a span reached its attribute limit; further attributes were dropped | `warning` |

## What is built, and what is not

Built: the W3C context type and its parsing, spans with attributes, errors and
status, the sampler that decides from the trace id, the exporter interface
with in-memory and ring-buffer implementations, the HTTP server middleware
that starts a span per request and propagates context, the trace id on every
log line, and `/_dartvel/traces` serving the ring buffer when diagnostics
endpoints are on.

Not built: the OTLP exporter, so nothing reaches a collector; spans for
database queries, outbound HTTP, queue publish and consume, transactions and
AI calls, so the only span most requests have is the request itself; trace
context in the job envelope and the links that follow from it; client spans
and their ingest; span attribute and duration limits; and `dartvel traces`
reading anything but the local buffer. The diagnostics above are registered
meanings, not emitted signals: nothing raises one yet, and a code that is
emitted for the wrong situation is worse than one that is not emitted at all.

## Deliberately absent

- **A Dartvel trace header.** W3C or nothing.
- **Tail sampling.** It needs a component that has seen the whole trace.
  Dartvel emits honestly and a collector decides; claiming otherwise in-process
  would be claiming to know the future of a request.
- **Per-vendor exporters.** They all take OTLP.
- **Blocking export.** Covered above, and it is why a bounded queue that drops
  with a count is the right behaviour rather than a backlog that grows.
- **A trace viewer of Dartvel's own.** `/_dartvel/traces` is a debugging
  buffer, not a product. Studio links a request to the trace in whatever
  backend the deployment sends spans to.

---

# Crash Reporting and Release Health

Stability: `Draft` · Status: `Designed`

Monitoring and Observability lists error reporting among the things that are
built in. This section is that line, written out, because a crash is not a log
with a higher severity and treating it as one loses most of them.

The difference is what the process is doing at the time. A log is written by a
program that will still be running afterwards, so it can allocate, await, and
put something on the network. A crash handler runs inside a process that is
already going down — often with a corrupt heap, sometimes on a signal handler
where allocation is not allowed at all. Anything that waits for a round trip
finishes after the process does.

So: **a crash is written to disk by the handler and sent by the next launch.**
The record is small, its buffer is reserved when the handler is installed, and
writing it is the only thing the handler does. `DV-CRASH-001` reports the
report that was recovered and sent.

## What is captured

| Where | Source |
| --- | --- |
| Flutter | `FlutterError.onError` and `PlatformDispatcher.onError` |
| Dart | uncaught errors in the guarded zone, and errors on every spawned isolate |
| Android | the JVM's uncaught-exception handler and a native signal handler |
| iOS and macOS | `NSException`, Mach exceptions, and signals |
| Linux and Windows | signal handlers and structured exception handling |
| Web | `error` and `unhandledrejection` on the window, plus the isolate's own |
| Backend | the server isolate's errors, and the Rust runtime's panics |

Application hangs are captured too: a watchdog notes when the platform thread
has not answered for the declared interval and files the stack it was on, as
`DV-CRASH-007`. An application that freezes is a crash to everyone except the
crash reporter.

Non-fatal errors — a caught exception the application wants recorded — go
through the same path with `DV.Crashes.record(error, stack)`, and are the only
thing here that is sampled.

## What a report carries

The stack, the release and patch it came from, the platform and device class,
the locale, the session length, the flags in force at the time, and the last
breadcrumbs.

Breadcrumbs are the navigations, backend calls, lifecycle transitions and
logged events that preceded the crash — a ring buffer with a declared size, so
a long session costs the same as a short one.

**Sensitive model fields never enter a report.** A value declared with
`@DVModel.sensitiveField()` is excluded by construction, the way it already is
from logs, traces and AI context, and breadcrumb payloads pass the redaction
the log path uses.

Local variables are not captured at all. A variable dump is the most useful
thing a crash reporter could send and the one thing it cannot make safe: the
values are whatever was in scope, which on a checkout screen is a card number.

## Identity and consent

A crash report is operational. It is sent without an analytics consent grant,
because the application cannot be fixed otherwise, and it carries no
advertising identifier and no user identity by default — an install-scoped
random id groups a device's own reports and is reset when the application is
reinstalled or when the person clears data.

An application that wants the reports tied to an account declares it, and that
declaration binds the reporting to the consent category it names — no grant,
no identity on the report, and the report still arrives. The same declaration
flows into the privacy manifest that App Store Publishing writes, so the store
answer and the running behaviour come from one place.

## Symbols

A release build is obfuscated and stripped, which is what makes its stacks
unreadable. `dartvel build` writes the debug information for each target as
part of the build rather than as a step somebody remembers, and `dartvel
crashes symbols upload` puts it in the symbol store keyed by release and
build id.

A build that obfuscates and keeps no symbols is refused (`DV-CRASH-002`).
Shipping one produces crash reports that can never be read, and the failure
arrives weeks later when somebody needs them.

On the web the source maps are **archived with the release and not deployed**.
Serving them publishes the source, and not serving them makes every web stack
a list of minified names; uploading them to the symbol store is how both are
true at once.

A report naming a release whose symbols never arrived is kept and symbolicated
later, if they turn up. Until then it says it is unsymbolicated
(`DV-CRASH-003`) rather than showing a plausible-looking frame list that is
the compiler's naming rather than the program's.

## Grouping

Reports group by a fingerprint taken from the top frames of the stack with
framework frames trimmed, so the group is named after the application's own
code rather than after `runApp`. A group keeps its identity across releases as
long as that signature holds, which is what makes "this regressed in 1.4.0"
answerable.

An application can override the fingerprint where the default is wrong — one
crash site reached from twenty callers, or twenty sites that are really one
bug behind a shared helper.

## Rate limits

A device in a crash loop restarts and crashes again, forever. Reports are
limited per device per release: the first few in full, then counted, with
`DV-CRASH-004` saying what was elided. A counted crash still contributes to
release health; it is the payload that stops, not the arithmetic.

## Release health

Two numbers per release and per OTA patch: **crash-free sessions** and
**crash-free users**. The second is the one that matters to a person, and the
first is the one that moves fast enough to act on.

Both are declared thresholds, and both are what the OTA rollback gate reads.
A patch whose crash-free sessions fall below its threshold is held and
`DV-CRASH-010` fires; the rollout stops, the gate calls `dartvel flags off`
for anything the release staged behind a flag, and `dartvel updates rollback`
is a decision somebody makes with the number in front of them.

Health is computed per cohort, not just per release, because a crash that
takes only the ten percent in a rollout disappears into a whole-release
average.

## Where reports go

```dart
DVCrashReporting(
  sink: DVCrashSink.dartvel(),        // the deployment's own backend
  hangThreshold: Duration(seconds: 5),
  breadcrumbs: 64,
  nonFatalSampleRate: 0.25,
)
```

`DVCrashSink` has adapters — the Dartvel backend, Sentry, Crashlytics, or an
application's own — and the capture path above is the same whichever is
configured. A deployment with no sink configured still captures and still
computes release health locally; it simply has nowhere to send the detail.

Disabling crash reporting for a build is a declaration, not an accident, and
the build says so (`DV-CRASH-009`).

## CLI

```bash
dartvel crashes list --release 1.4.0
dartvel crashes show <group>
dartvel crashes symbols upload
dartvel crashes health --release 1.4.0 --by cohort
```

## Studio

Studio shows groups ordered by the number of people affected rather than by
event count, each group's first and last sighting, the releases it appears in,
and release health per cohort next to the rollout that produced the cohort.

## Diagnostics

| Code | Reason | Level |
|---|---|---|
| `DV-CRASH-001` | a report was recovered from the previous run and sent at launch | `info` |
| `DV-CRASH-002` | the build obfuscates and kept no symbols; its reports could never be read | `error` |
| `DV-CRASH-003` | no symbols for the release a report names; the stack is unsymbolicated | `warning` |
| `DV-CRASH-004` | reports from this device were rate-limited for this release | `warning` |
| `DV-CRASH-005` | a report was dropped: the on-disk record was truncated by the crash that wrote it | `warning` |
| `DV-CRASH-006` | the native crash handler could not be installed; only Dart-level errors are captured | `warning` |
| `DV-CRASH-007` | an application hang exceeded the declared threshold | `warning` |
| `DV-CRASH-008` | a non-fatal error was dropped by the declared sampling rate | `debug` |
| `DV-CRASH-009` | crash reporting is disabled for this build | `info` |
| `DV-CRASH-010` | release health crossed its declared threshold; the rollout was held | `error` |

## Deliberately absent

- **Sending from inside the handler.** Every design that does it works in
  testing, where the crash is thrown by a button, and loses the reports that
  matter, where the process is already unwinding.
- **Local variable capture.** See above: it cannot be redacted, because
  nothing declares what those values are.
- **Sampling crashes.** Non-fatal errors are sampled. A crash is not: the
  hundredth occurrence is the one that tells you it is not rare.
- **A second breadcrumb API.** Breadcrumbs are the logs, navigations and
  lifecycle transitions already produced. An application that has to remember
  to leave them will not.
- **Screenshots and view hierarchies on crash.** They carry whatever was on
  screen, which is the same problem as variable capture with a wider blast
  radius.

---

# Product Analytics and Consent

Stability: `Draft` · Status: `Designed`

Monitoring and Observability watches the system: logs, metrics, traces,
diagnostics. Nothing measures the product — which screens people reach, which
steps they abandon, whether the ones who signed up last month came back. And
measuring at all is a consent question before it is a data question: GDPR
consent records, a cookie banner on the web, App Tracking Transparency on iOS.
Analytics without consent is the compliance breach; consent without analytics
is a banner in front of nothing. They are one section because they are one
decision.

## Events are types

```dart
class CheckoutCompleted extends DVAnalyticsEvent {
  const CheckoutCompleted(this.order, {this.coupon});
  final Order order;
  final String? coupon;
}

DV.Analytics.track(CheckoutCompleted(order));
```

An event is an ordinary data class, so its fields are checked by the compiler
and its name cannot be misspelled into a second funnel that nobody notices for
a quarter. Page views and model actions are generated from the route index and
the model graph, so the common events exist without anybody writing them.

**Payloads honour `@DVModel.sensitiveField()` by construction.** An event
carrying a model serializes the model's analytics shape, which excludes
sensitive fields the way logs and traces already do; naming one directly is a
build error rather than a value discovered later in somebody else's warehouse
(`DV-ANALYTICS-004`).

## Consent is generated policy

```yaml
dartvel:
  analytics:
    store: database              # or a configured adapter
    consent:
      categories:
        essential: { required: true }
        product: { default: denied }
        marketing: { default: denied }
```

Each event declares its category; `essential` covers what the application needs
to function and the rest default to denied until somebody says otherwise. The
generated `DV.Analytics.track` checks the category's consent state **before the
event leaves the device**: a denied category is dropped at the call, not
filtered later by a server that has already received it (`DV-ANALYTICS-001`).
That is the difference between a consent feature and a consent guarantee, and
it is only available to a framework that owns both ends.

The prompt is generated per platform: a banner on the web, the App Tracking
Transparency prompt on iOS where a category implies tracking, a settings screen
everywhere. A declared category with no way to ask on a platform the
application builds for is a build error, because the alternative is a category
that is denied for ever on that platform and nobody knowing why
(`DV-ANALYTICS-002`).

Consent records are models, with the retention the compliance rules of the
deployment require: what was asked, what was answered, when, and under which
version of the categories. A consent choice that cannot be written is not
treated as consent (`DV-ANALYTICS-006`).

## The store

The default store is the application's own database, which makes local
development zero-config and works on SQLite. Volume has an answer already in
the platform: ClickHouse is a supported database adapter, and event data is
exactly what it is for — append-heavy, column-shaped, read as aggregates. The
generated queries do not change when the store does, because both are database
adapters.

Provider adapters cover the hosted services — PostHog, Mixpanel, GA-class —
for applications that already have one. An adapter receives what consent
allowed and nothing else.

## No sampling, and a cap that is not sampling

**Product events are not sampled by default.** A trace answers "what happened
in this request" and survives sampling; a funnel answers "how many people
reached step three", and a sampled denominator is wrong in a way that looks
plausible on a chart. Tracing samples; this does not.

What is bounded is a runaway: a per-session event cap catches a loop firing the
same event thousands of times, drops the excess, and says so, which is a
different thing from quietly keeping one event in ten (`DV-ANALYTICS-003`).

## Funnels and retention

Funnels, retention and cohorts are queries over the store, and Studio renders
them beside the model and queue explorers rather than in a separate product.
Questions are declared like any other generated query, so a funnel is
inspectable in the project graph and cannot drift from the events it counts.

## Diagnostics

| Code | Reason | Level |
|---|---|---|
| `DV-ANALYTICS-001` | event dropped on the device: its category has no consent | `debug` |
| `DV-ANALYTICS-002` | a declared consent category has no way to ask on a target the application builds for | `error` |
| `DV-ANALYTICS-003` | per-session event cap reached; further events dropped | `warning` |
| `DV-ANALYTICS-004` | an event payload names a sensitive field | `error` |
| `DV-ANALYTICS-005` | an analytics provider is configured with no consent category declared | `error` |
| `DV-ANALYTICS-006` | a consent choice could not be recorded; it is not treated as consent | `error` |

## Deliberately absent

- **Sampling product events.** See above; a sampled funnel is a wrong answer
  that looks like a right one.
- **Dartvel as a hosted analytics service.** A self-hosted default and
  adapters; running somebody's analytics for them is a commercial decision,
  not a specification item.
- **Identity resolution across devices and vendors.** Stitching anonymous
  sessions to people is where analytics becomes tracking, and it belongs to the
  application's own declared purposes, not to a default.

---

# Testing

Stability: `Draft` · Status: `Shipped`

Dartvel has a first-class testing layer.

```bash
dartvel test
dartvel test e2e
dartvel test golden
dartvel test golden --update-goldens
```

Built-ins:
- generated model factories
- database refresh/migrations for tests
- fake auth users
- fake queues/jobs
- fake mail and notifications
- fake storage/cache
- fake AI providers
- backend function tests
- page tests
- golden UI tests
- browser/device E2E tests
- accessibility assertions
- generated test fixtures for models, forms, and policies

```dart
DV.Test.resetQueues();
DV.Test.resetSignals();
DV.Test.resetPolicies();
```

Test conventions:
- unit tests live next to Dart source or under `test/`
- page/widget tests use generated page wrappers, not annotated functions
  directly
- backend function tests call typed generated clients and direct handlers
- generated model factories use exact model types
- fake providers must be explicit: fake auth, fake queue, fake mail, fake push,
  fake storage, fake AI, fake native bindings
- no test should pass because a platform feature is silently ignored
- unsupported targets either use explicit fakes or fail validation

Generated helpers:

```dart
final user = UserFactory().admin().create();
await DV.Test.asUser(user, () async {
  await DV.Auth.authorize(user, DVPolicyAction.view, dashboard);
});
```

CI:
- `dartvel test` runs fast unit/framework tests
- `dartvel test e2e` runs browser/device tests
- `dartvel test native` validates generated FFI/JNI bindings for selected
  targets
- `dartvel test accessibility` runs generated semantics checks
- `dartvel test release` runs the pre-release gate used before tags/releases
- `dartvel test --watch` reruns affected tests on file changes
- `dartvel test golden --update-goldens` refreshes approved golden snapshots
- test sharding and per-file isolation are available in CI
- snapshots and golden tests are first-class

Like Bun's built-in test runner, Dartvel testing should be fast, integrated,
watchable, and require minimal extra setup. Unlike Bun, Dartvel must cover
Flutter widgets, generated backend functions, native bindings, and full-stack
app flows.

---

# Search

Stability: `Contract` · Status: `Shipped`

Dartvel should provide a generated search abstraction for models and content.

Providers:
- PostgreSQL full-text (`DVPostgresSearchProvider`)
- SQLite FTS
- Meilisearch
- Algolia
- OpenSearch/Elasticsearch

```dart
final results = await User.Search.query('ada');
```

Search integrates with queues, model lifecycle signals, tenant scoping, and
authorization policies.

Generated behavior:
- `@DVModel.searchableField()` on model properties generates typed index documents.
- model lifecycle signals enqueue index, update, and delete jobs.
- search results preserve model types and policy filters.
- tenant, locale, and soft-delete filters are applied automatically.
- ranking, facets, highlighting, typo tolerance, and synonyms are configured in
  `pubspec.yaml`.

```dart
@DVModel(searchable: true)
class _User (@DVModel.searchableField() String name);

final page = await User.Search.query(
  'ada',
  facets: User.SearchFacets(role: ['admin']),
);
```

Search providers are explicit and typed. Small applications and tests can use
the concrete local provider; production applications should configure a
database or hosted search adapter. An unconfigured generated search facade
throws a `StateError` instead of silently returning an empty result:

```dart
User.Search.useProvider(
  DVInMemorySearchProvider<User, UserSearchFacets>(
    records: users,
    document: (user) => '${user.name} ${user.role}',
    facetMatcher: (user, facets) =>
        facets == null || facets.role == null || facets.role!.contains(user.role),
  ),
);
```

No provider may return rows the current user cannot access. If the provider
cannot enforce policy filters directly, Dartvel post-filters and records the
extra cost in observability metrics.

Semantic retrieval over the same models — embeddings, hybrid ranking, and
what a vector query does to the post-filter rule — is Semantic Search and
Embeddings, immediately below.

---

# Semantic Search and Embeddings

Stability: `Draft` · Status: `Designed`

Search indexes words. AI answers questions. Between them is retrieval over the
application's own models — "orders where the customer sounded unhappy" — which
keyword search cannot do and a language model cannot do without being handed
the right rows first. That layer is declared on the model, like everything
else the framework generates:

```dart
@DVModel(searchable: true)
class _Ticket(
    @DVModel.searchableField(semantic: true) String body,
    String status,
);

final page = await Ticket.Search.query(
  'customer sounded unhappy about delivery',
  mode: DVSearchMode.hybrid,
);
```

`mode` is `keyword`, `semantic` or `hybrid`, and `keyword` stays the default:
it is what the existing generated index does, it costs nothing per query, and
a section that silently changed the meaning of every existing call would be a
breaking change wearing a feature's name.

## Embeddings are durable jobs

A write enqueues an embedding job through `DV.Jobs` — the same machinery as
every index update — and the vector lands in the configured adapter. Nothing
embeds inline on the write path: an embedder is a network call with a rate
limit, and a model save that waits on one turns a form submission into a
timeout during somebody else's outage.

Long fields are chunked, each chunk embedded and stored with its offset, and a
match on a chunk returns the record with the chunk that matched. A record is
one row in results however many chunks it has, because a search that returns
the same ticket five times is a search nobody uses twice.

## The embedder is declared, and pinned

```yaml
dartvel:
  search:
    semantic:
      embedder: openai/text-embedding-3-small
      dimensions: 1536
      vectorAdapter: DVPgVectorAdapter
```

There is **no default embedder**, and `semantic: true` without one is a build
error (`DV-SEMANTIC-001`). Vectors from two different models are not
comparable — not worse, *meaningless*: the nearest neighbours of a query
embedded by one model among vectors written by another are noise that looks
exactly like results. A default would pick an embedder for an application that
had not thought about it, and the index would be wrong in a way no test
notices and no user can report.

pgvector is the adapter to reach for when the application already has
PostgreSQL, and the search adapters that carry vectors themselves —
Meilisearch, OpenSearch, Algolia — are configured the same way. On-device
semantic search is off unless asked for; see the budget below.

## Changing the embedder builds a second index

The index records which embedder and which chunking produced it. When either
changes, Dartvel **builds a new index alongside the old one** and keeps
answering from the old one until the backfill finishes, then switches
(`DV-SEMANTIC-003`). It is the expand/contract choreography Safe Schema
Evolution uses, for the same reason: re-embedding in place leaves the index
holding two vintages of vector at once, and during that window every query
silently mixes them.

Backfill is a resumable, rate-limited durable job with progress in Studio,
because re-embedding a corpus is measured in hours and costs money per
thousand records.

## Authorization is in the query, not after it

A semantic index that leaks across policies is worse than no index, and
retrieval makes the usual answer insufficient. Search's rule — post-filter
what the provider cannot filter — works for keyword results because the
provider returns everything matching and the filter removes rows. A vector
query returns the **k nearest**, so filtering afterwards does not narrow a
result set, it empties one: ask for ten, have nine belong to another tenant,
show one, and the page reads as "nothing found" while the data is there.

So:

- **Tenant scope and every policy predicate the adapter can express are
  pushed into the vector query.** An adapter that cannot filter at all is
  refused for a multi-tenant or policy-scoped model at build time
  (`DV-SEMANTIC-002`) rather than serving one tenant's tickets to another.
- What genuinely cannot be pushed down is post-filtered **with refill**:
  Dartvel re-queries for more neighbours until it has `k` the caller may see
  or the index is exhausted, bounded by a configured multiple of `k`. Hitting
  that bound returns fewer results and says so (`DV-SEMANTIC-005`) rather than
  presenting a short page as a complete one.

The same policy engine decides both, so a semantic result set can never
contain a row `Ticket.find` would have refused.

## Costs are metered, and a budget refuses

Embedding a corpus and embedding every query both cost money per token, and
the meters already exist: an embedding job and a query embedding record
against Usage Metering and Quotas like any other unit. A tenant over its
budget gets a refusal with `DV-SEMANTIC-007`, which is a search that says it
cannot run, not a search that quietly falls back to keyword and returns
something different from what it returned yesterday.

## On-device

Semantic search on the device is opt-in and budgeted:

```yaml
dartvel:
  search:
    semantic:
      onDevice:
        maxBytes: 200MB
```

A vector index is dense — roughly `dimensions × 4` bytes per chunk before any
quantization — so a corpus that is unremarkable on a server is hundreds of
megabytes on a phone. Over the declared budget the device keeps the keyword
index and reports `DV-SEMANTIC-006`; it does not evict silently, because a
half-populated semantic index returns confidently wrong neighbours and there
is no way for the application to tell.

## Retrieval for AI features

```dart
final context = await Ticket.Search.retrieve(
  question,
  limit: 8,
  mode: DVSearchMode.hybrid,
);
```

`retrieve` is the shape an AI feature needs: the rows, their matched chunks,
and their scores, already filtered by the caller's own policies. It is the
same query path as `query`, so a feature cannot accidentally read through a
wider lens than the search page beside it, and what it returns is subject to
`@DVModel.sensitiveField()` exclusion before it reaches a prompt.

## Diagnostics

| Code | Reason | Level |
|---|---|---|
| `DV-SEMANTIC-001` | a `semantic: true` field with no declared embedder | build `error` |
| `DV-SEMANTIC-002` | the vector adapter cannot filter; semantic search refused on a scoped model | build `error` |
| `DV-SEMANTIC-003` | embedder or chunking changed; a new index is building and queries use the previous one | `info` |
| `DV-SEMANTIC-004` | an embedding job failed permanently; the record is absent from the index | `warning` |
| `DV-SEMANTIC-005` | refill bound reached; fewer results returned than asked for | `info` |
| `DV-SEMANTIC-006` | on-device index over its declared budget; keyword only | `warning` |
| `DV-SEMANTIC-007` | embedding budget exhausted for this tenant; the search was refused | `warning` |

## Deliberately absent

- **A default embedder.** Covered above; it is the one default in this
  section that would corrupt an index rather than inconvenience somebody.
- **A vector store of Dartvel's own.** pgvector and the search adapters that
  carry vectors are enough; a hand-rolled index would be the slowest and
  least-tested part of the framework.
- **Re-ranking models.** Hybrid scoring combines the two existing rankings;
  a cross-encoder re-ranker is a model call, and an application that wants
  one writes it as an AI feature over `retrieve`.
- **Semantic search as a default.** `keyword` stays the default mode, and
  nothing changes meaning for an application that does not opt in.

---

# Billing

Stability: `Draft` · Status: `Partial`

Dartvel should include an optional billing layer for SaaS/mobile apps.

Providers:
- Stripe
- Paddle
- app-store purchases where supported
- Play Billing where supported

Features:
- subscriptions
- invoices
- usage-based billing
- entitlements
- trials
- webhooks as typed backend functions

Generated behavior:
- billing customers link to authenticated users and tenants
- plans, prices, entitlements, and usage meters are typed config
- checkout/session creation is a typed backend function
- webhooks are generated backend functions with signature validation
- entitlement checks integrate with policies and generated UI guards
- app-store and Play Billing purchases use generated native bindings through
  FFI/ffigen or JNI/jnigen where native glue is required

```dart
await DV.Billing.checkout(
  plan: BillingPlan.pro,
  customer: user,
);

if (await DV.Billing.hasEntitlement(user, Entitlement.analytics)) {
  return AnalyticsDashboard();
}
```

Certain models can be recorded as billable:
```dart
@DVModel(billable: true, nativePrice: 100)
class _Book(@DVModel.searchableField() String title);
```

Native prices use the `nativeCurrency` setting under the `dartvel:` pubspec
key. Localization can auto-convert prices, and conversion rates can be
overridden.

---

# Purchases and Entitlements

Stability: `Draft` · Status: `Designed`

Billing sells through a payment gateway. On iOS and Android, digital goods
sold inside the application must go through StoreKit or Play Billing instead:
a gateway checkout for digital content is a rejected build, not a warning, and
Dartvel generates the purchase flow. Shipping the non-compliant path by default
would make that a framework bug wearing an application's name.

So the route is decided by the platform and the goods, and the application
writes one call:

```dart
await DV.Purchases.buy(Book.pro, customer: user);
```

On iOS, iPadOS, tvOS, macOS from the App Store and Android from Play, a
digital product goes to the store. On the web, on desktop outside a store, and
for anything physical, it goes to Billing's gateway. Nothing in application
code branches on the platform, because a branch written once in an application
is a branch nobody revisits when a store changes its rules.

## Digital or physical is declared, never guessed

```dart
@DVModel(billable: DVBillable.digital(
  appStore: 'com.example.book.pro',
  play: 'book_pro',
))
class _Book(String title);

@DVModel(billable: DVBillable.physical(nativePrice: 1200))
class _Mug(String colour);
```

A classifier that guesses from a model's fields would be wrong in both
directions, and each direction costs something different: a physical good sent
through the store loses 15–30% on a margin that cannot carry it, and a digital
good sent through the gateway is a rejected submission. **Dartvel never
guesses.** `billable: true` keeps its current meaning — gateway, and nothing
about stores — and a store build that finds it on a model refuses with
`DV-PURCHASE-001`, naming the model and the two things it could be. The build
that cannot finish is the cheap failure here; the one that ships is not.

`DVBillable.digital` requires a product identifier for every store target the
project builds for. A missing one is `DV-PURCHASE-002` at build time rather
than a purchase sheet that fails to open in front of a customer.

## The store owns the price

A store product's price comes from the store, in the customer's own currency,
through the tier the developer chose in App Store Connect or Play Console.
Dartvel displays that number and never a converted one. Billing's
`nativePrice`/`nativeCurrency` conversion stays where it is — on gateway
sales — because a page showing £7.99 above a sheet charging the €9.99 tier is
a mismatch the customer sees at the exact moment they are deciding to pay, and
it is also the kind of thing a store reviewer opens first.

When the store cannot be reached to read its prices, a purchase button shows
no price rather than a guessed one (`DV-PURCHASE-007`). A price that is wrong
by a currency is worse than a price that is missing for a moment.

## Receipts are validated on the server

The device reports what it bought; the server decides whether it did.

```dart
// Generated, one per store the project targets.
@DVBackendFunction(rawPath: '/_dartvel/purchases/apple')
Future<void> _appleNotifications(DVContext context) =>
    DV.Purchases.acceptNotification(context, DVStore.appStore);
```

Client-side receipt checks are worth nothing: the code doing the checking is
the code an attacker controls. Validation is a generated backend function that
calls the store's own verification endpoint with credentials held in Secrets
and Environments, and an entitlement is written only from that answer
(`DV-PURCHASE-003` when the store refuses a receipt).

Store server notifications — App Store Server Notifications v2, Play's
Real-Time Developer Notifications — arrive at generated endpoints and write
the same entitlement models, so a renewal, a refund, a chargeback and a family
sharing revocation all land the same way a purchase does. A notification for a
product the project does not declare is `DV-PURCHASE-004` rather than a silent
drop: it usually means a product was added in a console and not in the code.

**A purchase Play has not been told about is refunded after three days.**
Acknowledgement is part of granting the entitlement, in the same transaction,
not a step an application is expected to remember: `DV.transaction` writes the
grant and acknowledges, `context.compensate` releases it if acknowledgement
fails, and a grant that is somehow still unacknowledged when the window closes
reports `DV-PURCHASE-006`.

## Entitlements are synced, server-authored state

An entitlement bought on a phone unlocks the desktop session through ordinary
model sync. There is no second replication path and no `DV.Entitlements`
store: entitlements are generated models like any other, and they reach the
device the way a model does.

They are **server-authored**, which settles what would otherwise be a conflict
question. A device never writes an entitlement — it cannot, since the only
evidence that would justify one is a receipt the server validates — so the
offline conflict strategies do not apply to it. `DVOffline(strategy: ...)` on
an entitlement model is a build error (`DV-PURCHASE-008`) rather than a
strategy that would never fire, and `DVConflict.ask` in particular has no
meaning here: Record History and Optimistic Concurrency asks the writer to
choose between two versions, and there is only ever one writer.

What the device does hold is a snapshot with an end:

```dart
if (await DV.Purchases.entitled(user, Entitlement.analytics)) {
  return AnalyticsDashboard();
}
```

Each synced entitlement carries a `notAfter`, set from the subscription's paid
period with the store's own grace period added. Offline, access holds until
that moment and then stops (`DV-PURCHASE-005`). Without it a refunded annual
subscription would keep working on a device that never reconnected, which is
the failure mode every hand-rolled entitlement cache has; with it, a plane
journey is covered and a year of unpaid access is not.

`restore()` is generated and required — the App Store rejects an application
that sells a non-consumable with no way to get it back on a new device:

```dart
await DV.Purchases.restore();
```

Restoration asks the store what this store account owns and revalidates each
receipt server-side. A receipt that validates under a different application
user grants nothing and says so: two people sharing a device is ordinary, and
silently moving somebody's subscription to whoever is signed in is not a merge
problem, it is a refusal.

## Store policy is an adapter, never framework code

Which goods may be sold outside the store, whether an application may link to
its own checkout, and what that link must say, are decided by courts and
regulators and change between releases of this framework. The DMA, the US
anti-steering rulings and each store's response to them have all moved more
than once. **Nothing about them is compiled into Dartvel.**

```yaml
dartvel:
  purchases:
    policy: DVAppleStorePolicy   # or the application's own
```

A `DVStorePolicy` adapter answers one question — given a product, a platform
and a jurisdiction, where does this purchase go — and Dartvel ships the
conservative default for each store. An application operating under a regime
that permits an external purchase link supplies its own adapter and carries
that decision itself, which is the honest place for it: the framework cannot
know where a customer is standing or what a regulator decided last week.

## Development and the doctor

`dartvel dev` uses each store's sandbox — StoreKit's local `.storekit`
configuration and Play's licence testers — so a purchase flow can be walked
end to end without a real charge, with the same generated code the release
build runs.

`dartvel doctor --purchases` lints the policy before a submission does:
digital goods routed to a gateway, a missing product identifier, a store
credential that does not resolve in the environment being built for, and an
entitlement model carrying an offline strategy. Each is a typed finding with
the code that explains it, which is the difference between reading it here and
reading it in a rejection notice a week later.

## Diagnostics

| Code | Reason | Level |
|---|---|---|
| `DV-PURCHASE-001` | a `billable: true` model is sold on a store target without being classified digital or physical | build `error` |
| `DV-PURCHASE-002` | a digital product has no store product identifier for a target being built | build `error` |
| `DV-PURCHASE-003` | the store refused a receipt or purchase token; no entitlement was written | `warning` |
| `DV-PURCHASE-004` | a store server notification named a product the project does not declare | `warning` |
| `DV-PURCHASE-005` | an entitlement snapshot passed its `notAfter` while offline; access refused | `info` |
| `DV-PURCHASE-006` | a purchase was granted and not acknowledged to the store within its window | `error` |
| `DV-PURCHASE-007` | store prices could not be read; no price is shown rather than a converted one | `warning` |
| `DV-PURCHASE-008` | an offline conflict strategy is declared on a server-authored entitlement model | build `error` |

## Deliberately absent

- **Hard-coded store policy.** Covered above, and it is the one thing in this
  section that would age badly enough to be dangerous.
- **A receipt validator in the client.** There is no configuration that moves
  validation to the device, because every application that offers one is asked
  for it by somebody who wants to test faster and then ships it.
- **A `DV.Entitlements` namespace.** Entitlements are models. The purchase
  surface is `DV.Purchases`; what you own is data.
- **Cross-store transfer.** A purchase on Play does not become a purchase on
  the App Store. Dartvel syncs the entitlement, which is what an application
  actually wants; the receipt stays with the store that issued it.

---

# Usage Metering and Quotas

Stability: `Draft` · Status: `Designed`

Billing lists usage meters among its typed config and says nothing about where
the numbers come from. Multi-tenancy says who the numbers belong to. This is
the part between them: what is counted, who is allowed to count it, what
happens when a tenant reaches a limit, and which number the invoice is made
from.

```dart
@DVMeters()
abstract class _Meters {
  @DVMeter(unit: 'call', limit: DVLimit.entitlement)
  static const apiCalls = DVMeter.counter;

  @DVMeter(unit: 'GB-month')
  static const storedBytes = DVMeter.gauge;

  @DVMeter(unit: 'token')
  static const aiTokens = DVMeter.counter;
}

Meters.apiCalls.record(1);
Meters.aiTokens.record(response.usage.totalTokens);
```

A meter is scoped to `DV.currentTenant` without being told to. A recording
that reaches the store without a tenant is not a usage number, it is a number
with nowhere to go.

## Counting happens on the backend, and only there

**A meter cannot be recorded from client-reachable code, and trying is a build
error** (`DV-METER-001`) — the same shape of rule, for the same reason, as a
backend-scoped secret reached from a client.

A client-reported usage number is a number the customer controls. Every
metering system that trusted one has the same story afterwards, and it is not
a story about malice so much as about a retry loop in somebody's script. The
backend already sees the call it would have counted.

Some meters need nothing written at all: backend function invocations, storage
bytes, queue jobs and AI tokens are known to the framework, and declaring one
of those meters instruments it from the project graph rather than from calls
somebody remembered to add.

## Recording twice is the default failure

A metered call that is retried — by the client, by a queue, by a load balancer
that gave up early — arrives more than once, and a counter that takes both has
overcharged somebody.

Every recording carries an idempotency key, defaulting to the request id from
the Backend Function Request Lifecycle, and the store discards a key it has
already seen inside the period (`DV-METER-002`). A job records under the job's
own id, so a retried job counts once however many attempts it took.

Counters accumulate. Gauges are the current value at a sample, and a gauge is
billed on its average or its peak over the period, declared per meter, because
"gigabytes stored" is not a number you add up.

## Limits are declared over two different quantities

This is where seats come in, and the answer is not the obvious one.

A **flow** is a meter: events accumulating over a period. API calls, tokens,
messages sent. It is recorded.

A **level** is a query: how many of something exist right now. Seats,
projects, connected devices. It is counted when asked.

`DVLimit` covers both, and only one of them is metered:

```dart
@DVMeter(unit: 'call', limit: DVLimit.entitlement)      // flow: from the meter
static const apiCalls = DVMeter.counter;

DVLimit.query(Membership.seats, entitlement: Entitlement.seats)  // level
```

**Seats stay what Organizations, Membership and Invitations said they were: a
query over memberships that Billing reads, not a meter.** Metering them would
mean recording an increment when somebody is invited and a decrement when
somebody is removed, which is precisely the second counter that section
refused — and it drifts the first time a membership is deleted by a cascade,
a restore, or an organization closing. The quota layer covers levels and
flows alike; the recording layer covers flows only, because a level has an
authoritative answer already and recording it would be storing a derivative
of the truth beside the truth.

## What happens at the limit

```dart
@DVMeter(
  unit: 'call',
  limit: DVLimit.entitlement,
  atLimit: DVQuota.block,      // block | throttle | allowAndBill
  notifyAt: [0.8, 1.0],
)
```

`atLimit` is required wherever a limit is declared (`DV-METER-005`). There is
no default, because each of the three is somebody's correct answer and picking
one silently means a deployment finds out which it got during an incident:
`block` turns a customer's integration off, `throttle` makes it slow enough to
notice, and `allowAndBill` produces an invoice nobody expected.

`notifyAt` thresholds send through Notifications before the limit rather than
at it (`DV-METER-003`). A quota reached with no warning is a support ticket; a
quota approached with two is a renewal conversation.

Reaching a limit reports `DV-METER-004` with the behaviour that was applied,
so the log says what happened to the request rather than only that a number
was exceeded.

## The period, and what arrives late

The period is the tenant's **billing period**, taken from the provider, not a
calendar month — an invoice cut on the eleventh and usage counted from the
first is a reconciliation argument every month. A tenant with no billing
period falls back to the deployment's calendar period and says so
(`DV-METER-010`).

A record can arrive after its period closed: a queued job draining, a device
that was offline, a retry. Within a declared grace it is accepted into the
period it belongs to (`DV-METER-007`). After the grace it counts in the open
period (`DV-METER-008`) rather than being dropped, because usage that
happened is usage that happened, and an invoice already sent is not something
a framework should quietly reopen.

## Reconciliation, and which number is the invoice

Usage is reported to the billing provider at period close, and **the
provider's invoice is the customer-facing truth**. Dartvel's own store is the
evidence behind it: the same figures, per record, with the idempotency keys
and the timestamps that produced them.

They can disagree — a report that failed and retried, a provider that rounds,
a plan changed mid-period. `dartvel meters reconcile` produces the difference
per tenant per meter and does not resolve it automatically. Usage that could
not be reported is queued and retried, never dropped (`DV-METER-006`), because
a dropped report is revenue that silently did not exist.

A metered entitlement with no price on the plan is counted and not billed, and
says so (`DV-METER-009`) — that is a legitimate state while a meter is being
watched before it is charged for, and an illegitimate one that lasts a quarter
if nothing reports it.

## The store

Meters aggregate in the application's own database, which keeps local
development zero-config. High-volume deployments point the same generated
queries at ClickHouse, exactly as Product Analytics does, because the shape of
the data is the same: append-heavy, read as aggregates.

## CLI

```bash
dartvel meters list
dartvel meters usage --tenant acme --period current
dartvel meters reconcile --period 2026-08
```

## Studio

Studio shows usage per tenant against each tenant's own limits, the tenants
approaching one, and the reconciliation difference beside the invoice it
belongs to.

## Diagnostics

| Code | Reason | Level |
|---|---|---|
| `DV-METER-001` | a meter is recorded from client-reachable code | `error` |
| `DV-METER-002` | a duplicate recording was discarded by its idempotency key | `debug` |
| `DV-METER-003` | a meter passed a declared notification threshold | `warning` |
| `DV-METER-004` | a meter reached its limit; the declared behaviour was applied | `warning` |
| `DV-METER-005` | a meter declares a limit and no behaviour at the limit | `error` |
| `DV-METER-006` | usage could not be reported to the billing provider; it is queued, not dropped | `error` |
| `DV-METER-007` | a record arrived after its period closed and was accepted into it under the declared grace | `info` |
| `DV-METER-008` | a record arrived after the grace; it counts in the open period | `warning` |
| `DV-METER-009` | a metered entitlement has no price on the plan; usage is counted and not billed | `warning` |
| `DV-METER-010` | the tenant has no billing period; the deployment's calendar period was used | `info` |

## Deliberately absent

- **Client-side metering.** Covered above. There is no configuration that
  turns it on.
- **A second counter for seats.** Levels are queried, flows are metered, and
  the drift this avoids is the one Organizations already named.
- **Dartvel issuing the invoice.** The provider does that. Dartvel supplies
  the usage and keeps the evidence.
- **Automatic reconciliation.** A difference between two systems of record is
  something a person decides about. Resolving it silently would hide the class
  of bug the reconciliation exists to find.
- **Rating and pricing rules of its own.** Tiers, overage curves and discounts
  live in the provider's plan, where the finance team can already see them.

---

# Internationalization and Localization

Stability: `Draft` · Status: `Shipped`

Qt treats internationalization as a core app concern; Dartvel should too.

Features:
- typed translation keys
- generated locale files
- route locale negotiation
- pluralization
- date/number/currency formatting
- right-to-left layout support
- per-tenant locale defaults
- notification/mail template localization
- SEO alternate locale tags

Generated API:

```dart
class AppText {
  static const settingsTitle = DVTranslationKey('settings.title');
  static const inboxCount = DVTranslationKey('inbox.count');
}

DV.I18n.load(const DVTranslationCatalog(
  locale: LocaleTag.enUS,
  messages: <DVTranslationKey, String>{
    AppText.settingsTitle: 'Settings',
  },
  plurals: <DVTranslationKey, DVPluralForms>{
    AppText.inboxCount: DVPluralForms(
      one: '{count} message',
      other: '{count} messages',
    ),
  },
));

DVText(DV.I18n.t(AppText.settingsTitle)); // or `DVText(DV.I18n.translate(AppText.settingsTitle));` full alias
DVText(DV.I18n.plural(AppText.inboxCount, 3));
DV.I18n.formatCurrency(12.5, code: 'USD');

context.locale.set(LocaleTag.enUS);
```

Rules:
- all generated strings use typed keys
- missing translations fail build in strict mode
- page routes can use path, query, subdomain, or header locale strategies
- forms and validation messages localize automatically
- generated mail/notification templates localize with the same key system
- right-to-left layout flips spacing, alignment, icons, and navigation affordances
  where appropriate
- numbers, dates, currencies, and relative times are locale-aware
- SEO generates canonical and alternate locale metadata

---

# Accessibility

Stability: `Draft` · Status: `Shipped`

Dartvel-generated UI must preserve Flutter semantics and add generated checks for:
- semantic labels
- keyboard navigation
- focus order
- screen-reader landmarks
- high contrast
- reduced motion
- minimum tap targets
- table/list accessibility

Generated forms, tables, pages, and auth screens must be accessible by default.

Runtime and tooling:
- `dartvel test accessibility` checks generated pages, forms, tables, and common
  components
- generated controls expose labels, hints, roles, states, and validation errors
- generated tables support keyboard navigation, focus restoration, row/column
  announcements, and screen-reader summaries
- motion modifiers respect platform reduced-motion settings
- color modifiers can be checked for contrast in CI
- kiosk/embedded targets support switch control and hardware-key navigation
- accessibility regressions fail the release gate unless explicitly waived with
  a documented reason

Runtime API:
```dart
DVBox(DVText('Submit')).modifier(
  const DVModifier()
      .semanticLabel('Submit order')
      .semanticHint('Sends the order for processing')
      .semanticButton()
      .minimumTapTarget(),
);

final contrast = DV.Accessibility.contrast(
  foreground: Colors.black,
  background: Colors.white,
);

final target = DV.Accessibility.tapTarget(size: const Size(44, 48));
final report = DV.Accessibility.report([contrast, target]);
DV.Accessibility.useReducedMotion(true);
```

`DV.Accessibility` returns typed checks (`DVContrastCheck`,
`DVTappableTargetCheck`, `DVAccessibilityReport`) so CI and release gates can
fail on exact accessibility regressions instead of relying on ignored warnings.

---

# Desktop, Embedded, and Qt-Critical Capabilities

Stability: `Draft` · Status: `Partial`

Qt is strong on desktop, embedded, and device-creation workflows. Dartvel should
cover the same categories while keeping Flutter as the renderer.

Desktop:
- native menus
- tray/status icons
- global shortcuts
- multi-window apps — see [Multi-Window](#multi-window)
- window state persistence
- file associations
- drag and drop
- clipboard and selection integration
- printing
- system dialogs

Desktop APIs live under `DV.Platform.*` and generated app services:

```dart
await DV.Platform.Window.setTitle('Dartvel Admin');
await DV.Platform.Window.persistState('main');
await DV.Platform.Window.restoreState('main');
await DV.Platform.Tray.show(icon: 'assets/tray.png');
await DV.Platform.Tray.show(
  icon: 'assets/tray.png',
  tooltip: 'Dartvel',
  menu: const <DVTrayMenuItem>[
    DVTrayMenuItem(id: 'open', label: 'Open'),
  ],
);
await DV.Platform.Menus.setApplicationMenu(
  const DVApplicationMenu(<DVMenuItem>[
    DVMenuItem(
      id: 'file',
      label: 'File',
      children: <DVMenuItem>[
        DVMenuItem(id: 'quit', label: 'Quit', shortcut: 'Ctrl+Q'),
      ],
    ),
  ]),
);
await DV.Platform.Shortcuts.register(
  const DVGlobalShortcut(id: 'quick-open', accelerator: 'Ctrl+K'),
);
```

Desktop APIs are backed by generated native bindings registered under
`window.*`, `tray.*`, `menus.*`, and `shortcuts.*`; they must fail if the
binding is missing or rejects the request.

Embedded/device creation:
- kiosk mode and fullscreen mode — specified in [Kiosk Mode](#kiosk-mode),
  which owns the policy, the two scopes, enforcement per target and exit
  protection. They are named here because they are embedded capabilities, not
  restated, so there is one place a rule can be wrong
- boot-to-app packaging
- hardware capability manifests
- watchdog/health restart hooks
- offline-first local storage
- serial/USB/Bluetooth/NFC device APIs
- deterministic startup profiling
- startup watchdogs
- crash-safe local queues
- device fleet provisioning
- remote diagnostics
- update channels for kiosk/device fleets

Runtime API:
```dart
final manifest = await DV.Platform.device.capabilityManifest();
final health = await DV.Platform.device.health();

await DV.Platform.device.armWatchdog(
  timeout: const Duration(seconds: 10),
  reason: 'startup',
);
await DV.Platform.device.heartbeat();

final provisioning = await DV.Platform.device.provision(
  const DVFleetProvisioningRequest(
    deviceId: 'kiosk-1',
    fleetId: 'storefront',
    labels: <String, String>{'zone': 'front'},
  ),
);

final diagnostics = await DV.Platform.device.collectDiagnostics();
```

Embedded APIs use generated native bindings registered under
`device.capabilityManifest`, `device.health`, `device.watchdog.*`,
`device.fleet.*`, and `device.diagnostics.*`. They return typed Dartvel models
such as `DVHardwareCapabilityManifest`, `DVDeviceHealth`,
`DVDeviceProvisioningResult`, and `DVDeviceDiagnosticsBundle`.

Qt-style meta-object capabilities:
- generated metadata for pages, models, backend functions, jobs, signals, and
  policies
- runtime discovery for tools/devtools
- typed dynamic property maps for generated admin/devtools views
- signal/slot-like typed connection surfaces through `context.signal`,
  generated model signals, jobs, and model sync

Generated metadata powers:
- devtools inspectors
- AI project context
- generated docs
- admin dashboards
- route explorers
- schema browsers
- permission audits
- native capability manifests

Native implementations still follow the Dartvel rule: generated FFI/ffigen or
JNI/jnigen only, no Flutter platform channels.

---

---
# Platform Memory

Stability: `Draft` · Status: `Designed`

Deterministic, preallocated, reusable memory on every Dartvel target. Apps that
process large data — media pipelines, analytics, ML pre/post-processing,
embedded kiosk workloads — should not depend on GC timing or per-job
reallocation. `DVPlatformMemory` reserves a memory budget once at startup and
hands out typed scalars and arrays from it for the lifetime of the app,
arena-style.

One API, every target. The backing store is selected automatically:

- Android, iOS, Windows, Linux, macOS, Fuchsia, sony-elinux, Tizen, webOS —
  native-heap segments through generated FFI (outside the Dart GC; stable
  addresses, shareable with isolates and Rust bindings zero-copy).
- Web (JS and wasm) — `ArrayBuffer`-backed segments. Same API, best-effort
  budget: the browser may grant less than asked and the allocator degrades
  gracefully.

Memory is allocated in fixed power-of-two segments (default 256 MB native,
128 MB web, 64 MB mobile, 32 MB embedded). A single typed array never spans a
segment invisibly — larger arrays are chunked internally with constant-time
index math, and hot paths iterate contiguous chunks at full typed-data speed.

## Usage

```dart
final memoryAllocator = DV.Memory.allocate(gigabytes: 4);

final a = memoryAllocator.int(2);
final b = memoryAllocator.int(1);
final c = a.add(b); // 3 — result lives in the same preallocated memory

final samples = memoryAllocator.doubleList(50_000_000);
samples.fill(0.0);
await samples.transformAsync((v) => v * 2.0 + 1.0); // yields; UI stays live

memoryAllocator.reset(); // whole arena reusable instantly for the next job
```

Scalars (`DVInt`, `DVDouble`, `DVBool`) and lists (`MemorySlice<int>`,
`MemorySlice<double>`) expose standard primitive types; the storage
representation (float32, int16, uint8, int64-vs-float64 on JS) is converted
under the hood. No byte-level code in application logic; `rawBytes` /
`rawStruct` remain available for binary interop.

## Allocation through DV.Memory

`DV.Memory` is a factory, not a singleton arena. `DV.Memory.allocate(...)`
constructs and returns a `DVPlatformMemory` instance under the hood; every
call produces an independent arena with its own budget, segments, cursor, and
lifecycle. Applications may hold several at once — one per subsystem, one per
job class, one per module:

```dart
final memoryAllocator = DV.Memory.allocate(gigabytes: 4);
final frames = DV.Memory.allocate(megabytes: 512, segment: DVSize.mb(64));

final buffer = memoryAllocator.uint8(width * height * 4);
memoryAllocator.reset();   // resets this arena only
frames.dispose();          // releases this arena only
```

`DV.Memory.allocate` accepts the same parameters as the `DVPlatformMemory`
constructor (`gigabytes`, `megabytes`, `profile`, `segment`, `touchPages`) and
applies the per-target defaults and ceilings from configuration before
allocating. The factory also registers each live arena so diagnostics,
performance contracts, and the Studio memory panel can report per-arena and
aggregate usage. `DVPlatformMemory(...)` remains directly constructible;
factory-created arenas are simply the instrumented path.

## Configuration

Configuration supplies defaults and per-target ceilings that
`DV.Memory.allocate` applies to every arena it creates; it does not create a
global arena itself.

```yaml
dartvel:
  memory:
    budget: 4GB              # default budget when allocate() omits a size
    segment: 256MB
    touchPages: desktop      # commit physical pages at startup; never on
                             # mobile/embedded (OOM-killer pressure), no-op web
    targets:
      web:      { budget: 512MB, segment: 128MB }
      android:  { budget: 512MB, segment: 64MB }
      ios:      { budget: 512MB, segment: 64MB }
      tizen:    { budget: 128MB, segment: 32MB }
      webos:    { budget: 128MB, segment: 32MB }
      sony-elinux: { budget: 256MB, segment: 32MB }
```

Device profiles may override memory settings; `dartvel doctor` validates the
configured budget against the device profile's declared RAM.

## Platform semantics

- Preallocation is best-effort by contract. Each arena's `securedBytes`
  reports the capacity actually granted; applications size workloads from it.
- On native targets, segment addresses are stable and may be passed to
  isolates and generated Rust/FFI bindings for zero-copy shared-memory
  processing. On web, per-segment chunks align with worker transfer
  boundaries.
- `int64` scalars and lists are Supported on native and web-wasm, Supported
  with limitations on web-js (transparent float64 backing, exact to 2^53 —
  the ceiling of `int` under dart2js). Bitwise index math stays within
  32-bit-safe ranges on JS.
- `reset()` invalidates all previously handed-out scalars and slices; use
  after each processing job instead of reallocating.

## Diagnostics

Typed and explained, consistent with build validation:

```text
DV-MEMORY-001  Configured budget not fully secured (asked 4GB, granted 1.5GB).
DV-MEMORY-002  Arena exhausted; increase budget, reset(), or reduce workload.
DV-MEMORY-003  int64 requested on web-js; use intList()/int32()/float64().
DV-MEMORY-004  touchPages enabled on a mobile/embedded target.
```

Performance contracts add memory-arena metrics: secured capacity, high-water
usage, reset frequency, and segment fragmentation. Studio exposes the same
signals in a memory panel.

---

# Kiosk Mode

Stability: `Contract` · Status: `Partial`

(The `## Bindings` subsection declares Stability `Draft`; every other
subsection inherits the section labels, per Specification Status.)

Kiosk has two scopes, and everything below applies to both unless a rule says
which:

- **`device`** — the whole device is the kiosk. One application, one display
  or all displays, no windows (`open()` presents in place, `DV-WINDOW-002`).
- **`display`** — one window owns one display in kiosk mode and the
  application keeps ordinary windows on the others. The window kind is
  specified in Multi-Window › Kiosk windows; the policy it obeys is specified
  here.

A kiosk is a device — or a display — that runs one application for whoever
walks up to it: lobby displays, point-of-sale, self-checkout, ticketing,
wayfinding, medical intake, factory HMI, the customer-facing screen beside a
cashier. Kiosk mode is the set of guarantees that make that true — the
application fills the display, cannot be left by the user, restarts if it dies,
forgets each user when they walk away, and can be operated and exited by staff
without a keyboard hanging off the back.

## Kiosk restricts the surface, not the content

Kiosk mode changes what the *device or display* permits — fullscreen, input
confinement, no OS chrome, no escape, no second window on that surface — and
nothing about what the *application* permits. Routes still run their
middleware; policies still apply; tenant and locale resolve normally; a deep
link that would be refused outside kiosk is refused inside it. Nothing in this
section is a security boundary for application data; the Authorization and
Sensitive Model Fields sections are. Kiosk is a boundary for the *user's
ability to leave*.

## Two ways in

**Declared.** Configuration or a device profile sets the policy, and the built
artifact starts in kiosk at boot. This is the production path: boot-to-app on
eLinux images, Android lock-task launchers, Windows assigned access, TV
single-app profiles. There is no window of unlocked UI at startup.

```yaml
dartvel:
  kiosk:
    enabled: true
    scope: device
    home: /welcome
```

In `display` scope, the declaration names the kiosk windows — the route each
shows, the display it owns, the policy it obeys — and they open at boot before
anything else:

```yaml
dartvel:
  kiosk:
    enabled: true
    scope: display
    policies:
      customerDisplay:
        home: /customer-display
        routes: { allow: [/customer-display/**] }
        session: { idleTimeout: 60s, onIdle: reset }
        exit: { method: adminAuth }
    windows:
      customer:
        route: /customer-display
        display: Customer            # a display name from the device profile,
                                     # or primary | secondary | index:N
        policy: customerDisplay
```

Named policies are available to code as `DVKioskPolicies.customerDisplay`, so
a kiosk window opened at runtime (`DV.Window.open(..., kind: kiosk)`) uses a
declared policy rather than an ad-hoc one. There is no policy that is not in
the declaration.

**Runtime, under the declared policy.** `DV.Platform.display.kiosk` (device
scope) and `win.kiosk` (display scope) transition between kiosk and a
supervised *staff mode* for maintenance, configuration and troubleshooting.
Neither can enable kiosk where the policy did not declare it, and neither can
disable kiosk without satisfying the declared exit method. A build with no
kiosk policy has no kiosk runtime: the calls exist, report `DV-KIOSK-005`, and
change nothing.

```dart
DV.Platform.display.kiosk.state       // DVSignal<DVKioskState> — device scope
DV.Platform.display.kiosk.policy      // DVKioskPolicy, read-only
DV.Platform.display.kiosk.enforcement // DVKioskEnforcement — what the device honours

await DV.Platform.display.kiosk.exit(DVKioskExitRequest.pin('4821'));
await DV.Platform.display.kiosk.resume();
await DV.Platform.display.kiosk.resetSession(reason: DVKioskResetReason.idle);

customer.kiosk!.state                 // the same shape, per window — display scope
DV.Window.kiosks                      // DVSignal<List<DVWindow>>

enum DVKioskState { off, active, staffMode, resetting, locked, failed }
```

`enableKiosk()`, `disableKiosk()`, `isKiosk` and `isFullscreen` on
`DV.Platform.display` remain valid as sugar over `kiosk.resume()`,
`kiosk.exit(...)`, and `kiosk.state`. `DV.Kiosk` is the alias per the proxy
pattern. In `display` scope `DV.Platform.display.kiosk` refers to the device,
which is *not* in kiosk; the windows that are appear in `DV.Window.kiosks`.

## Policy

```yaml
dartvel:
  kiosk:
    enabled: true
    scope: device                     # device | display
    home: /welcome                    # attract / idle-return route
    routes:
      allow: [/welcome, /order/**, /help]   # default: all application routes
      external: block                 # block | allowlist
      externalAllow: []
    input:
      systemGestures: block           # edge swipes, home, recents, app switch
      hardwareKeys: block             # except accessibility keys, always
      shortcuts: block                # OS and browser shortcuts
      clipboard: disabled
      textSelection: disabled
    session:
      idleTimeout: 90s
      idleWarning: 15s                # countdown route/overlay before reset
      onIdle: reset                   # reset | home | none
      clearOnReset: [signals, forms, sharedStore, auth, clientCache]
    display:
      fullscreen: true
      hideCursor: auto                # auto (touch-only) | always | never
      screenDim: 5m                   # burn-in / power; 0 disables
      wake: onTouch
    windows: false                    # device scope: no windows (alias of
                                      # windowing.kiosk.allowWindows); in display
                                      # scope, `windows:` is the kiosk-window map
    notifications: suppress           # system-level; in-app inbox still works
    updates:
      apply: maintenanceWindow        # immediate | maintenanceWindow | staffMode
      window: "02:00-04:00"
    exit:
      method: pin                     # none | pin | gesture+pin | adminAuth | remote | hardwareCombo
      pin: secret:KIOSK_EXIT_PIN      # a DV.Secrets reference, never a value
      gesture: cornerTaps(5)
      maxAttempts: 5
      lockoutFor: 10m
      audit: true
```

In `display` scope the same keys live under `policies.<name>`, with two
differences the scope forces: `session.clearOnReset` may not contain `auth` or
an un-namespaced `sharedStore` (see Sessions), and `input.hardwareKeys`
defaults to `passthrough` (see Enforcement).

Device profiles may set or override any of this and are where displays get
their names (`displays: { Customer: { index: 1 } }`). A runtime `exit()` never
changes policy, only state. `dartvel doctor` validates that the declared
policy is enforceable on each configured target and that every declared kiosk
window's display exists in the profile.

## Sessions

A kiosk serves strangers in sequence, so **a session is anonymous and
disposable by default**. The idle reset — and any explicit `resetSession()` —
clears everything listed in `clearOnReset` and then navigates to `home`. After
reset, nothing a previous user typed, viewed, or authenticated is reachable
from that kiosk.

What a reset may clear depends on scope, and the difference is the point:

| `clearOnReset` entry | `device` scope | `display` scope |
|---|---|---|
| `signals` | all page and global signals | the kiosk window's page signals |
| `forms` | all | the kiosk window's |
| `sharedStore` | the whole store | keys under `kiosk.<name>.*` only |
| `auth` | `DV.Auth.signOut()` | **not permitted** — the session is the staff window's |
| `clientCache` | all | entries tagged to the kiosk window's routes |

A display-scoped policy that lists `auth` or an un-namespaced `sharedStore`
fails validation: a customer display timing out must not sign the cashier out.

- `idleWarning` presents a generated countdown (built from `DVBox`/`DVText`,
  restyleable) so a slow user is not cut off without notice.
- `onIdle: home` returns to the attract route without clearing state — for
  informational displays with no user data. `dartvel analyze` flags it when
  models with `sensitiveField` are reachable from allowed routes
  (`DV-KIOSK-009`).
- Reset is a transaction over local state: partial resets are not observable.
- Reset emits `DV.lifecycle.kiosk` transitions (`resetting → active`) — per
  window in display scope — and an observability event with the reason, never
  with user data.
- State a kiosk window shows *from* the staff window (the cart on a customer
  display) travels through model sync or shared keys the staff window writes
  under `kiosk.<name>.*`. A reset clears the kiosk side; the staff window's
  next write repopulates it. The staff window never has to know a reset
  happened.

## Exit protection

Exit is the one thing kiosk must make hard, and the one thing staff must be
able to do. The methods are a closed set:

| Method | Meaning | Where it degrades |
|---|---|---|
| `none` | device management owns exit; the app never exits itself | — |
| `pin` | numeric secret from `DV.Secrets` | never |
| `gesture+pin` | hidden gesture reveals the pin prompt | touchless devices → `pin` via hardware combo |
| `adminAuth` | `DV.Auth` session passing `DVPolicyAction.exitKiosk` | offline device → `pin` fallback if configured |
| `remote` | fleet command via `device.fleet.*` | disconnected device → cannot exit remotely |
| `hardwareCombo` | declared key combination | devices without keys |

Rules:

- Attempts are rate-limited (`maxAttempts`, `lockoutFor`); the lockout is
  `DVKioskState.locked`, visible on the kiosk and reported.
- Every attempt, success or failure, is an audit event with actor (if any),
  method, and outcome. The pin value never appears anywhere.
- The pin is a `DV.Secrets` reference resolved on device from the secure store;
  it is not in `pubspec.yaml`, not in the bundle, and rotates through the
  ordinary rotation hook.
- Staff mode is a state, not an unlock: the application is still running, still
  fullscreen by default, with the policy's restrictions lifted and a visible
  staff banner. `resume()` returns to kiosk and resets the session.
- In `display` scope, `adminAuth` is the natural method and needs no prompt on
  the kiosk display: the request comes from a peer window whose authenticated
  session passes `DVPolicyAction.exitKiosk`. The customer display never shows
  a pin pad unless its policy says `pin`.
- Deep links, notifications and OS intents do not constitute an exit path:
  under kiosk they are honoured only within `routes.allow`.

## Health and fleet

Kiosk composes with the embedded capabilities rather than duplicating them:

- `autostart` and `restartOnFailure` are honoured by the target's supervisor
  (systemd unit on eLinux images, lock-task launcher on Android, assigned
  access on Windows).
- The watchdog is armed on boot with `reason: 'startup'` and heartbeat runs
  from the application lifecycle; a missed heartbeat restarts the application,
  and a restart loop (more than `n` in `m` minutes) enters a generated
  diagnostics screen instead of looping forever (`DV-KIOSK-008`).
- Fleet commands: `kiosk.reload`, `kiosk.exit`, `kiosk.lock`, `kiosk.staffMode`,
  `kiosk.resetSession`, `kiosk.screenshot` (policy-gated; never during a
  visible user session). In display scope each command addresses a named kiosk
  window.
- OTA: `updates.apply: maintenanceWindow` defers `DV.Updates.apply()` to the
  window; `staffMode` applies only when staff are present; `immediate` is for
  displays with no user session. A forced update outside the window shows the
  generated update UI and resets the session first.

## Enforcement

What a device can actually enforce is a capability, reported honestly:

```dart
final e = DV.Platform.display.kiosk.enforcement;   // or customer.kiosk!.enforcement
e.fullscreen;        // can hold fullscreen
e.escapeBlocked;     // user cannot reach the OS from the app
e.systemGestures;    // edge/home/recents intercepted
e.hardwareKeys;      // power/volume/home intercepted
e.singleApp;         // OS prevents other apps from surfacing
e.strength;          // DVKioskStrength: device | supervised | fullscreenOnly
e.inputScope;        // DVKioskInputScope: device | display — display scope only
```

`inputScope` exists because a keyboard is a device and a touchscreen is a
display. Touch on an owned display is confinable per display wherever the OS
reports which display a touch came from; pointer input is confinable while the
kiosk window is focused; hardware keys and OS shortcuts are device-wide or
nothing. A display-scoped policy that blocks `hardwareKeys` therefore either
blocks them for the whole device — which the staff terminal will notice — or
not at all, and `enforcement.inputScope` says which (`DV-KIOSK-010`). The
honest default for display scope is `input.hardwareKeys: passthrough` with
touch and pointer confinement.

| Target | Mechanism | Strength | Label |
|---|---|---|---|
| eLinux (Sony) image / bundle | DRM/EGL fullscreen, no compositor, systemd supervision | `device` | `Supported` |
| Android (device owner / DPC) | Lock Task Mode, launcher replacement | `device` | `Supported` |
| Android (no device owner) | screen pinning | `supervised` | `Supported with limitations`¹ |
| iPadOS / iOS | Single App Mode via MDM; Guided Access | `device` / `supervised` | `Supported with limitations`² |
| Windows | Assigned Access / shell replacement; fullscreen + key hooks | `device` / `supervised` | `Supported with limitations`³ |
| macOS | fullscreen + presentation options | `fullscreenOnly` | `Supported with limitations` |
| Linux desktop | fullscreen; compositor-dependent gesture blocking | `supervised` | `Supported with limitations` |
| Tizen / webOS | single-app TV model; launcher/boot config | `device` | `Supported with limitations`⁴ |
| Web / PWA | Fullscreen, Keyboard Lock and Pointer Lock APIs | `fullscreenOnly` | `Supported with limitations`⁵ |
| Browser extension | not applicable | — | `Unsupported` |
| Watch | not applicable | — | `Unsupported` |
| Terminal (`-cli`/`-tui`) | full-screen alternate buffer; escape is the shell's | `fullscreenOnly` | `Supported with limitations` |

Display scope adds a requirement rather than a row: it needs
`capability.displayKiosk`, which requires multi-window and addressable
displays — the Windows, macOS and Linux rows (labelled per the Multi-Window
matrix) and eLinux multi-head configurations, where per-output DRM makes it the
strongest case. Everywhere else `scope: display` degrades to the in-place
fullscreen page described in Multi-Window › Kiosk windows.

¹ Screen pinning can be exited by the user with a known gesture; the app
reports `strength: supervised` and `DV-KIOSK-001`.
² iOS cannot enter Single App Mode programmatically; the declared policy is
realized by MDM, and the runtime API can only detect it. Guided Access is
user-managed and reported as `supervised`.
³ Assigned Access requires a provisioned account; without it the app is
fullscreen with key hooks and reports `supervised`.
⁴ TV platforms are single-app by construction, but exit is the remote's home
button and is not interceptable on consumer sets; kiosk on TVs means "boot to
app and return to it", reported as such.
⁵ The browser reserves `Esc` and cannot be prevented from leaving fullscreen;
`fullscreenOnly` is the honest label. Dedicated browser kiosk modes (launch
flags, ChromeOS kiosk apps) raise it to `device` when detected.

`Unsupported` appears here where it does not in the windowing matrix because
kiosk *is* the capability — there is no "present it another way" fallback for
locking a watch. The API still exists on those targets and reports
`DV-KIOSK-004`.

## Diagnostics

```dart
enum DVKioskDegradation {
  none, enforcementReduced, exitWeaker, noPolicy, unsupportedTarget,
  routeBlocked, bindingMissing, lockedOut, inputScopeWidened,
}
```

| Code | Reason | Level |
|---|---|---|
| `DV-KIOSK-001` | requested enforcement reduced (e.g. `device` → `supervised`) | `warning` at boot, once |
| `DV-KIOSK-002` | exit method degraded (e.g. `gesture+pin` → `pin` on touchless device) | `info` |
| `DV-KIOSK-003` | exit attempt failed; lockout after `maxAttempts` | `info`, audited |
| `DV-KIOSK-004` | kiosk requested on a target without kiosk capability | `info` |
| `DV-KIOSK-005` | runtime kiosk call with no declared policy | `warning` |
| `DV-KIOSK-006` | route outside `routes.allow` requested and blocked | `debug` |
| `DV-KIOSK-007` | native kiosk binding missing or refused | `error` |
| `DV-KIOSK-008` | restart loop detected; diagnostics screen shown | `error` |
| `DV-KIOSK-009` | `onIdle: home` with sensitive fields reachable from allowed routes | `warning` (analyze) |
| `DV-KIOSK-010` | display-scoped input confinement is device-wide on this platform | `warning` at boot, once |

`DV-KIOSK-001` and `010` fire once per boot, not per interaction: reduced
enforcement is a deployment fact the operator needs to know, not a stream.
`dartvel doctor --target <t>` reports the same findings before the build ships.

## Accessibility under kiosk

Kiosk blocks *escape*, never *access*. Switch control, screen readers,
hardware-key navigation and high-contrast/reduced-motion settings remain
available; `input.hardwareKeys: block` explicitly exempts accessibility keys
and the platform's accessibility shortcut. A generated accessibility toggle
may be placed on the attract route. `dartvel test accessibility` runs against
kiosk builds with the policy applied, and an accessibility regression under
kiosk fails the release gate like any other.

## Interaction with other sections

- **Multi-Window**: in `device` scope `kiosk.windows: false` is canonical and
  `open()` presents in place (`DV-WINDOW-002`); `windowing.kiosk.allowWindows`
  remains a compatibility alias. In `display` scope the kiosk window is a
  window kind that owns its display, specified under Multi-Window › Kiosk
  windows; this section owns the policy it obeys.
- **OTA**: governed by `kiosk.updates`; forced updates reset the session first.
- **Notifications**: system notifications are suppressed on the kiosk surface;
  in-app inbox and model-sync delivery continue.
- **Secrets**: the exit pin is a device-resolved secret; kiosk shared keys are
  encrypted with the application key as elsewhere.
- **Studio**: a kiosk panel shows fleet state, enforcement per device and per
  kiosk window, exit audit, session-reset counts, and lets an authorized
  operator issue fleet commands. Screenshots are policy-gated and never taken
  during a user session.
- **i18n**: the attract route may rotate locales; a session reset returns the
  kiosk to the profile's default locale.

## Configuration precedence

`deviceProfiles.<profile>.kiosk` overrides `dartvel.kiosk`; a `--device-profile`
build selects the profile. Runtime never changes policy. `dartvel inspect kiosk
--json` prints the effective policy per target and per kiosk window, with the
source of each value.

## Bindings

Stability: `Draft` · Status: `Designed`

Generated FFI/ffigen or JNI/jnigen bindings only, per the standing rule:

- `display.enterFullscreen`, `display.exitFullscreen` (existing)
- `display.kiosk.enable`, `display.kiosk.disable`, `display.kiosk.state`
  (the existing `display.enableKiosk` / `display.disableKiosk` names remain as
  aliases) — device scope
- `window.kiosk.enable`, `window.kiosk.disable`, `window.kiosk.state` —
  display scope, together with `window.display.assign`, `window.pin` and
  `window.unpin` from Multi-Window
- `kiosk.input.lock`, `kiosk.input.unlock` — gestures, keys, shortcuts, with a
  display argument where the platform can scope them
- `kiosk.enforcement.query`
- `kiosk.supervisor.register` — autostart / restart integration
- android: `kiosk.lockTask.start`, `kiosk.lockTask.stop`
- windows: `kiosk.assignedAccess.query`
- web: generated bindings over Fullscreen, Keyboard Lock and Pointer Lock
- fleet: `device.fleet.command` carries the `kiosk.*` commands above

A missing or refusing binding fails typed (`DV-KIOSK-007`), never silently.

## Testing

```dart
DV.Test.fakeKiosk(
  policy: DVKioskPolicies.customerDisplay,
  enforcement: DVKioskEnforcement.supervised(inputScope: DVKioskInputScope.device),
);

await customer.kiosk!.exit(DVKioskExitRequest.pin('0000'));
expect(customer.kiosk!.state.value, DVKioskState.active);       // wrong pin
expect(DV.Test.kioskAuditEvents.last.outcome, DVKioskExitOutcome.rejected);
```

Idle reset is testable with a fake clock; the e2e suite runs the attract →
session → idle → reset loop on eLinux and Android runners, and the
two-display staff/customer scenario on desktop runners with virtual displays;
the accessibility suite runs with the policy applied.

## Performance contracts

Measured: boot-to-kiosk-ready time (device) and boot-to-kiosk-window-ready
(display), idle-reset duration, exit-prompt latency after gesture, watchdog
heartbeat jitter, restart-loop detection time. Diagnostics: a reset that
exceeds its budget (user-visible dead time), an attract route that allocates
per frame (burn-in displays run for years), an allowed route that navigates
externally, and a kiosk-window reset that touched state outside its namespace.

## Security

- Exit protection is rate-limited and audited; the pin is a device-resolved
  secret and never logged.
- Deep links, intents and notifications cannot leave `routes.allow`.
- Session reset is transactional; in device scope it clears auth, so a
  walk-away user's identity is unreachable afterwards; in display scope it
  cannot reach the staff session at all.
- Remote commands require fleet authentication; `kiosk.exit` remotely is
  audited with the issuing operator.
- Enforcement strength and input scope are reported, never overstated: an
  application on a `fullscreenOnly` target must not be described to an
  operator as locked.

## Deliberately absent

- **Device-owner / MDM provisioning.** Dartvel integrates with Lock Task,
  Assigned Access, Single App Mode and TV launchers; it does not replace the
  device management that provisions them. `dartvel doctor` says which is
  required.
- **A custom Android launcher.** Lock Task under a device owner is the
  supported mechanism; shipping a launcher is a product, not a framework
  feature.
- **A promise of screen-capture prevention on web.** The browser does not
  offer it; the spec does not claim it.
- **Kiosk as a runtime toggle without a declared policy.** See Two ways in.
- **Inline per-window policies.** `DVWindowKiosk.policy` names a declared
  policy, so every kiosk the device can enter is visible in
  `dartvel inspect kiosk`.
- **A kiosk manager on `DV.Window`.** Display-scoped kiosk is `win.kiosk` on a
  window and `DV.Window.kiosks` as a list; there is no `DV.Window.kiosk`
  manager object, for the same reason there is no `DVWindowManager`.

# Terminal Rendering

Stability: `Draft` · Status: `Partial`

A Dartvel application can present itself in a terminal instead of a window,
without being a different application. The same widgets, the same pages, the
same generated model pages and Studio documents — drawn as cells rather than
pixels.

The point is not novelty. It is that a powerful application can live on a
powerful machine and be driven from anywhere: a server with no desktop, a
container, a phone over SSH. The application does not change; only where its
frames land does.

## Two ways in, and they are different

**A terminal-only build.** `dartvel build linux-cli` produces a binary that
renders in a terminal. It contains **no GUI backend at all** — not a window
that stays closed, not a fallback, nothing. It resolves the way
`sony-elinux-iso` already does: a suffix naming a base platform and a
presentation, not a new platform.

```
dartvel build linux-cli      dartvel build linux-tui
dartvel build windows-cli    dartvel build windows-tui
dartvel build macos-cli      dartvel build macos-tui
dartvel build fuchsia-cli    dartvel build fuchsia-tui
```

`-tui` and `-cli` are the same target under two names. `-tui` says what it
does; `-cli` says where it runs.

**A dual-mode build**, only when asked for. `dartvel build linux` produces a
GUI binary containing no terminal code. It carries both backends **only** if
the application opts in:

```yaml
dartvel:
  terminal: true
```

## What each build contains

| Build | GUI backend | Terminal backend |
|---|---|---|
| `dartvel build linux` | yes | **no** |
| `dartvel build linux` with `dartvel.terminal: true` | yes | yes |
| `dartvel build linux-cli` / `linux-tui` | **no** | yes |

There is no configuration under which an application gets a backend it did
not ask for. A GUI build without the opt-in is byte-for-byte what it is today;
a terminal build carries no window-server code it would never call.

## Nothing is carried by an application that did not ask

This is a constraint on the implementation, not a preference. A rendering
backend costs binary size for every user who never reaches it, so the
presentation is resolved at **build time** — from the `-cli`/`-tui` suffix or
the `dartvel.terminal` key — and only the backends an application asked for
are linked. The default on every desktop target is GUI alone.

That rules out the obvious shortcut of always shipping both and choosing at
startup. It is simpler, and it makes every application pay for a capability
most of them will never use.

## How a dual-mode application starts

For an application that opted into both, launching from a shell:

1. **GUI by default.** A terminal is where the command was typed, not
   necessarily where the application belongs.
2. **`--tui` starts in the terminal**, skipping the GUI entirely. This is the
   explicit path, and it is the one to reach for over SSH.
3. **No display available, and the application offers both** — a machine with
   no desktop installed, a headless container, a bare SSH session — the
   application says so and offers the alternative rather than choosing for the
   user:

   ```
   No display server is available.
   This app can run in your terminal instead. Continue in TUI mode? [Y/n]
   ```

The prompt exists because both silent answers are wrong. Silently redrawing as
text is indistinguishable from a bug at the moment it happens, and failing
outright wastes a capability the application was built with. Asking costs one
keystroke and is unambiguous.

An application that did **not** opt into terminal rendering has none of this:
no prompt, no flag, no branch. It fails to find a display exactly as it does
today.

## What the application can observe

```dart
DV.Platform.surface            // DVRenderSurface.gui | DVRenderSurface.terminal
DV.Platform.terminal           // null unless surface is terminal
DV.Platform.terminal.size      // columns and rows, as a signal
DV.Platform.terminal.graphics  // DVTerminalGraphics.kitty | .ansi
```

`DV.Platform` stays the stable surface, as it does for every other platform
capability; a terminal is another thing it reports on rather than a namespace
of its own.

`size` is a signal, so a layout responds to a resized terminal through the same
reactive path a resized window uses, not a parallel one.

## What a terminal costs

Stated rather than glossed, because a rendering mode that pretends to be
lossless is worse than one with documented edges:

- **Fidelity depends on the terminal.** Full-quality rendering uses the Kitty
  graphics protocol; where it is unavailable, rendering degrades to ANSI cells,
  which is coarser. Which one is active is reported by
  `DV.Platform.terminal.graphics` rather than guessed at.
- **Frames cost bandwidth over a slow link.** A 60fps animation redrawn across
  SSH is not free the way a local compositor is.
- **Pointer input is whatever the terminal reports**, and some report none.

## Windows in a terminal

`DV.Window.open(...)` is not a special case here. Terminal rendering is a
surface with a particular set of capabilities, and the windowing model already
describes what happens when a surface cannot honour a request: it presents the
route another way and reports why.

In a terminal, `open()` **navigates** — the route is presented as a page, with
`DVWindowPresentation.page` and `DVWindowDegradation.capabilityUnsupported`
(`DV-WINDOW-001`), exactly as on a phone. Application code does not branch on
whether it is in a terminal; it observes the presentation it got, the same way
it already does everywhere else.

### Why not spawn a second terminal

It is the obvious idea and it defeats the purpose. Opening a new terminal
*emulator* window requires a window server — which is the thing terminal
rendering exists to work without. On the machine where this matters most, a
server reached over SSH, there is exactly one pty and nothing to spawn into.

A multiplexer is the one honest exception: where the application is running
under `tmux` or similar, real additional surfaces exist and a window request
could be given one. That is a capability to detect, not to assume, and it is
deliberately left out of the first implementation. A feature that works only
under one multiplexer, and silently degrades everywhere else, is harder to
reason about than one that always navigates.

So the rule is: **navigate, and say so.** If multiplexer surfaces are added
later they raise the presentation from `page` to `window` for applications that
already work either way, because those applications were reading the
presentation rather than assuming it.

### Tab workspaces

`DVTabWorkspace` needs no terminal-specific behaviour. Tabs are a layout, and a
layout renders in cells as readily as in pixels. Tearing a tab out into its own
window degrades the same way `open()` does, and for the same reason.

## The embedder

Terminal rendering is driven by a Dartvel fork of a Flutter terminal embedder,
maintained the way the television and embedded forks are: pinned to the Flutter
version Dartvel ships, patched where upstream is short.

Upstream is a research project and does not need to already do everything —
that is what the fork is for. Producing a distributable binary rather than only
a development run, and whatever else Dartvel requires, is work the fork carries
rather than a reason to wait.
# 3D Scenes

Stability: `Draft` · Status: `Designed`

Dartvel applications get real-time 3D — product viewers, configurators,
data visualization, signage, games — rendered by Impeller through Flutter
GPU, with the same conventions as everything else in the platform: typed and
generated, signal-reactive, asset-validated at build time, degradation
reported rather than silent, and no new primitive.

## The viewport is a box

```dart
@DVPage(title: 'Espresso M3')
Widget _productPage(BuildContext context) => DVBox.list([
    DVText('Espresso M3').modifier(heading),
    DVBox.scene(
      DVScene(
        environment: DVEnvironments.studio,   // IBL; procedural studio default
        nodes: [
          DVModel3D(DVScenes.espressoM3)
              .rotationY(context.signal(0.0)) // a signal is a valid argument
              .animation(DVAnimations.espressoM3.steamLoop),
          DVCamera.orbit(
            target: DVVec3.zero,
            distance: 2.4,
            controls: true,                   // drag/pinch orbit built in
          ),
          DVLight.directional(direction: DVVec3(-1, -2, -1)).shadows(),
        ],
      ),
    ).aspectRatio(16 / 9).rounded(12),
  ]);
```

(Expression body per the generator rule for private `@DVPage` inputs; the
field-scoped annotation lives under the `DVModel` parent per the model
conventions — there is no standalone field annotation.)

`DVBox.scene` is a layout mode like `.grid` or `.stack`: the box owns size,
modifiers, gestures and accessibility semantics; the `DVScene` owns 3D
content. Scene nodes — `DVNode`, `DVModel3D`, `DVMesh`, `DVCamera`,
`DVLight`, `DVEnvironment` — are typed scene objects, not widgets, because a
scene graph and a widget tree have different lifecycles and a pretend-widget
node would be a lie with a `build` method. Node modifiers (`.rotationY`,
`.position`, `.scale`, `.material`, `.visible`, `.onTap` via GPU picking)
follow the fluent style of `DVModifier` and accept plain values **or
signals** — a signal-valued transform re-renders the frame when it changes,
so a turntable is one derived signal and no tickers.

Rendering: PBR materials with image-based lighting, directional/point/spot
lights with shadow casting (cached shadow tiles for static geometry), and a
blended animation system — surfaced as typed Dartvel API over the pinned
engine, not re-implemented.

## Assets: imported at build, typed at use

```text
assets/
  models/espresso_m3.glb
  materials/brushed_steel.fmat
  environments/showroom.hdr
```

`dartvel build` (and incrementally, `dartvel dev`) runs the import pipeline —
the engine's native-assets/data-assets build hooks, wrapped so applications
never configure them — and generates:

```dart
DVScenes.espressoM3                       // imported model, with its meshes
DVAnimations.espressoM3.steamLoop         // typed animation handles per model
DVMaterials.brushedSteel                  // .fmat material
DVEnvironments.showroom                   // IBL environment
```

- Import failures are build errors with codes (`DV-3D-002`), naming the file
  and the reason; a viewport cannot ship pointing at an asset that does not
  exist or did not convert.
- Custom shaders live in `shaders/` and are bundled by the same build step;
  a shader that fails to compile fails the build, per target API (Metal,
  Vulkan, GLES, WebGL2), not on the user's device.
- Asset variants (texture sizes, KTX2 compression) follow the Media Pipeline
  section's variant model; `dartvel analyze` flags textures over budget for
  the configured device profiles (`DV-3D-006`).

## Model-driven 3D

A model field can be a 3D asset, and the generated layer treats it like any
other media field:

```dart
@DVModel()
class _Product(
  final String name,
  @DVModel.model3dField(poster: true, maxSizeMb: 25) final DVFile? asset,
);

product.viewer3D()        // generated orbit viewer: DVBox.scene + camera + studio env
Product.Page()            // model page renders the viewer where the field appears
```

Uploads are validated (format, size, triangle budget) and processed by
generated jobs — poster render, optional compressed variants — through the
Media Pipeline's queue machinery. The generated viewer is an application
component like `User.Table()`: composed from `DVBox.scene`, replaceable, no
new primitive.

## Reactivity, sync, and multiplayer

Scene state is signal state; shared scene state is model state. Both rules
already exist — 3D just inherits them.

```dart
// Local: signals drive nodes directly (see the turntable above).

// Shared: a synced model binds to a node with interpolation, so remote
// transforms render smoothly under network jitter:
DVModel3D(DVScenes.kart)
    .syncTransform(kart.signal(context), interpolation: 120.ms)
```

`syncTransform` is a generated binding between a synced model's transform
fields and a node, with a fixed-delay interpolation buffer. Delivery, auth,
tenant filters and policy checks are model sync's, unchanged. There is no
scene-specific networking, no room/host API, and no second transport — a
"scene host" is an application that syncs models, which Dartvel apps already
are.

## Games: the flame_3d adapter

For game loops, Dartvel does not reinvent Flame. The optional
`dartvel_flame3d` adapter (a plugin package, per Pluggability) hosts a
flame_3d game inside `DVBox.scene`, maps Dartvel assets and signals into
Flame components, and keeps navigation, auth, billing and model sync on the
Dartvel side:

```dart
DVBox.scene.game(KartGame())   // Flame3DGame subclass; Dartvel owns the shell
```

Labelled `Experimental` on its own: flame_3d states plainly that it does not
guarantee semver, and the adapter's version pins flame_3d exactly. An
application that wants app-3D (viewers, configurators, dashboards) never
touches the adapter.

## Physics

The engine's abstract physics contract is surfaced as a typed choice, not a
Dartvel-built engine:

```yaml
dartvel:
  scene3d:
    physics: rapier        # none (default) | box3d | rapier
```

```dart
DVScene(
  physics: DVPhysics.enabled(gravity: DVVec3(0, -9.81, 0)),
  nodes: [
    DVModel3D(DVScenes.crate).rigidBody(mass: 4).collider.box(),
  ],
)
```

Backends ship prebuilt binaries for mainstream targets; exotic architectures
build from source and require a Rust toolchain — which `dartvel doctor
--target <t>` reports before the build fails halfway (`DV-3D-005`). Physics
state that must be shared follows the sync rule above; the physics world
itself is local simulation.

## Degradation: the poster contract

`DVBox.scene` never renders a hole. Where the target cannot render 3D — no
Flutter GPU on the embedder, `scene3d` disabled, GPU init failure — the box
renders the scene's **poster**: a build-time render of the scene's initial
frame (or the model field's generated poster), with typed degradation
readable on the viewport and reported once through `DV.log`.

```dart
enum DV3DDegradation { none, unsupportedTarget, disabledByConfig, gpuInitFailed, assetMissing }
```

Posters are also what Static Web Generation embeds, what the `<noscript>`
fallback shows, and what model-page SEO uses as the Open Graph image for a 3D
field — the degraded path and the crawler path are the same true image.

## Platform matrix

| Target | Renderer | Label |
|---|---|---|
| iOS | Impeller (Metal), default | `Supported` |
| Android | Impeller (Vulkan/GLES), default | `Supported` |
| macOS | Impeller — enabled by Dartvel's build config | `Supported with limitations`¹ |
| Windows | Impeller — enabled by Dartvel's build config | `Supported with limitations`¹ |
| Linux | Impeller — enabled by Dartvel's build config | `Supported with limitations`¹ |
| Web (JS and wasm) | engine WebGL2 backend; no Flutter GPU in browsers | `Supported with limitations`² |
| eLinux (Sony) | Impeller GLES on device GPU | `Experimental`³ |
| Tizen / webOS | embedder forks lack Flutter GPU today | `Unsupported` → poster⁴ |
| Watch | — | `Unsupported` → poster |
| Terminal (`-cli`/`-tui`) | cells, not pixels | `Unsupported` → poster |

¹ Impeller is not the default on desktop; `dartvel build` enables it for
`scene3d` projects and `dartvel doctor` verifies the driver story per machine.
Desktop rows carry the same upstream caveat as windowing: flag-gated upstream,
absorbed by the pinned toolchain.

² The engine's built-in WebGL2 backend runs under both CanvasKit and Skwasm
with no flags; feature gaps versus native (shadow fidelity, compressed
texture formats) are reported through capability, not discovered visually.
The flame_3d adapter's web path uses its experimental WebGPU backend and
inherits that label.

³ The signage case — a 3D product loop on a kiosk — is exactly Dartvel's
embedded identity, and exactly where GPU drivers vary most. `Experimental`
until per-board evidence exists in `docs/build-targets.md`; device profiles
declare the GPU, and `dartvel doctor --target sony-elinux` validates it.

⁴ "Unsupported → poster" is honest twice over: the capability is absent, and
the API still renders something true. No target throws.

## Configuration

```yaml
dartvel:
  scene3d:
    enabled: true
    physics: none                  # none | box3d | rapier
    assets:
      models: assets/models
      materials: assets/materials
      environments: assets/environments
      compressTextures: auto       # auto | ktx2 | off
    poster:
      generate: true
      size: 1200x630               # OG-friendly default
    budgets:                       # feed dartvel analyze / performance contracts
      frameMs: 8                   # per viewport, on the profile device
      maxDrawCalls: 300
      maxTextureMb: 128
```

## Diagnostics

| Code | Reason | Level |
|---|---|---|
| `DV-3D-001` | scene presented as poster (unsupported target / disabled / GPU init failed) | `info`, once per boot |
| `DV-3D-002` | asset failed to import or is missing at build | build `error` |
| `DV-3D-003` | shader failed to compile for a configured target | build `error` |
| `DV-3D-004` | `scene3d` API used without `scene3d.enabled` | build `error` |
| `DV-3D-005` | physics backend needs a toolchain the machine lacks | build `error` via doctor |
| `DV-3D-006` | texture/mesh over the device-profile budget | `warning` (analyze) |
| `DV-3D-007` | per-frame allocation detected in a scene callback | `warning` (analyze) |
| `DV-3D-008` | `syncTransform` bound to a non-synced model | build `error` |

## Studio and scene documents

The engine serializes scenes as documents (`.fscene`), which slots straight
into Studio's existing shape: a `DV3DSceneDocument` is stored through
`DV.Database`, rendered by the same runtime the app uses, versioned and
delivered like a `DVPageBundle` — so a signage fleet's scene can be updated
OTA without an app release, with the same idempotent-apply and
previous-bundle-rollback rules. Studio v1 exposes inspect-and-edit of node
properties; a full 3D editor canvas is a later phase and is not promised
here.

`dartvel inspect scene3d --json` lists scenes, their assets, budgets and
per-target support through the project graph, like every other inspector.

## Testing and performance

- Golden 3D tests render with a fixed camera, the procedural studio
  environment, and deterministic time, per target renderer:
  `dartvel test golden` covers viewports like any widget.
- `DV.Test.fake3D()` substitutes a headless backend so scene *logic* (signals,
  sync bindings, physics stepping) tests without a GPU.
- Performance contracts gain: viewport frame time against `budgets.frameMs`,
  draw calls, texture memory, shader compile time at build, poster generation
  time. Diagnostics `DV-3D-006/007` land in `dartvel analyze performance`.

## Deliberately absent

- **A second realtime stack.** No scene networking, rooms, or hosts; model
  sync is the delivery system, with `syncTransform` as the binding.
- **An audio engine.** The ecosystem's FMOD integration is commercially
  licensed; Dartvel does not bundle a licensing obligation into a framework
  feature. Audio remains pluggable.
- **A Dartvel-built renderer or physics engine.** Pinned engines behind a
  typed surface, per the `go_router` precedent.
- **Scene nodes as widgets.** Widgets lay out; nodes render. `DVBox.scene` is
  the one place the trees meet.
- **AR/VR/XR.** A different input, display and permission model; a separate
  proposal if ever.
- **A promise of `Contract` stability today.** Upstream is experimental and
  says so; this section is `Draft` until Flutter GPU stops renaming its
  verbs, and the promotion to `Contract` is a status change, not a redesign.

---

# Multi-Window

Stability: `Contract` · Status: `Partial`

(The `## Bindings` subsection below declares its own labels — Stability
`Draft` — because it tracks a flag-gated upstream surface; every other
subsection inherits the section labels, per Specification Status.)

Desktop-class applications are made of windows. The hard part is not opening
one; it is defining what a window *means* across targets that disagree about
whether windows exist at all.

## A window is a route

Every Dartvel window hosts exactly one route. This is the single decision that
makes one API possible across platforms that implement "another window" in four
unrelated ways:

| Platform family | "Open a window" means | Content addressed by |
|---|---|---|
| Windows / macOS / Linux | native window, same engine | route |
| Web | `window.open('/route')`, separate instance | URL (the route) |
| Android | new task, separate engine | deep link (the route) |
| iPadOS | new `UIScene`, separate root | scene activation URL (the route) |

Dartvel is URL-first — static generation, server rendering and sitemaps already
require every route to map to one canonical URL — so windows inherit that for
free. The route is the serialization of "what this window shows". Anything a
window shows is therefore deep-linkable, restorable after a restart, and
subject to the same middleware, policies, tenant scope and locale as any
navigated page, because it is one. A window with no route is not expressible.

**Identity is the canonical URL.** Route *and* parameters:
`DVPages.order(id: 1)` and `DVPages.order(id: 2)` are two distinct windows;
opening `DVPages.order(id: 1)` twice focuses the existing one. Query
parameters participate in identity only when the page declares them as
identity (`@DVPage(windowIdentity: [...])`); undeclared query parameters are
view state and do not create a second window.

## Surface

`DV.Platform.Window` grows from "the current window" into the window manager,
with `DV.Window` as its alias per the established proxy pattern. There is one
namespace; the existing `setTitle` / `persistState` / `restoreState` members
read as sugar over `DV.Window.current` and remain valid.

```dart
DV.Window.current                  // DVWindow — the window this code runs in
DV.Window.main                     // DVWindow — see "Main window"
DV.Window.all                      // DVSignal<List<DVWindow>>
DV.Window.capability               // DVWindowingCapability
DV.Window.displays                 // DVSignal<List<DVDisplay>> (read-only)
DV.Window.kiosks                   // DVSignal<List<DVWindow>> — windows in kiosk mode
DV.Window.shared                   // DVWindowSharedStore

final win = await DV.Window.open(
  DVPages.orders,
  options: DVWindowOptions(
    size: Size(900, 620),
    constraints: BoxConstraints(minWidth: 480, minHeight: 320),
    title: 'Orders',
    kind: DVWindowKind.regular,      // regular | dialog | popup | tooltip | satellite | kiosk
    owner: null,                     // required for dialog/popup/tooltip/satellite
    modality: DVWindowModality.none, // none | window | application
    duplicate: false,                // true: a second window on the same URL
    display: null,                   // DVDisplayHint — which display, never where on it
    kiosk: null,                     // DVWindowKiosk — kiosk kind only
  ),
);

final class DVDisplay {
  final String id;                 // stable for the display's connection
  final String name;               // from the device profile, else OS-reported
  final Rect bounds;               // logical pixels
  final double devicePixelRatio;
  final bool isPrimary;
  final DVWindow? kioskOwner;      // set while a kiosk window owns this display
}

DVDisplayHint.primary
DVDisplayHint.secondary            // first non-primary, in OS order
DVDisplayHint.byIndex(1)
DVDisplayHint.byId(id)
DVDisplayHint.byName('Customer')   // device profiles name displays; see Kiosk Mode

DV.Window.byRoute(DVPages.orders);   // DVWindow? — existing window for a URL
await DV.Window.closeAll(except: [DV.Window.main]);
```

`DV.Navigation` gains a target rather than a second API:

```dart
DV.Navigation.to(DVPages.orders, window: DVWindowTarget.newWindow);
DV.Navigation.to(DVPages.orders, window: DVWindowTarget.current);   // default
```

### DVWindow

```dart
win.id;              // stable for the window's life; not persisted
win.route;           // DVRoute — what it shows, including parameters
win.kind;            // DVWindowKind
win.owner;           // DVWindow? — null for regular windows
win.lifecycle;       // DVSignal<DVWindowLifecycle>
win.presentation;    // DVWindowPresentation: window | page | dialog | overlay
win.degradation;     // DVWindowDegradation
win.isVirtual;       // presentation != window
win.isMain;
win.display;         // DVSignal<DVDisplay?> — null for virtual windows
win.kiosk;           // DVWindowKiosk? — null unless kind == kiosk

win.size;            // DVSignal<Size>
win.setSize(Size);   // no-op on virtual windows, logged at debug
win.setTitle(String);// maps to page title on virtual windows
win.setFullscreen(bool);
win.minimize(); win.maximize(); win.restore();
await win.close();   // closes the window, or pops the route — same call
```

**There is no `activate()` and no `focus()`.** `open()` opens, focuses and
activates. Bringing an existing window forward is the same verb: opening a URL
a window already shows focuses that window. `DV.Window.byRoute(r)` exists for
*reading* whether a window exists; to bring it forward, open its route. One
verb, idempotent by URL; a deliberate second window says `duplicate: true`.

**Placement is not part of the contract.** There is no `position` and no
`setPosition`. Wayland forbids app-positioned windows, Flutter's windowing API
exposes none, and web, Android and iPadOS delegate placement to the OS. The
only placement input is `DVDisplayHint` — *which display*, never where on it —
and it is best-effort by name.

## Kinds, ownership and modality

| Kind | Meaning | Owner | Fallback presentation |
|---|---|---|---|
| `regular` | top-level peer window | none | pushed page |
| `dialog` | owned, focus-taking | required | modal route |
| `popup` | owned, transient, dismiss on outside interaction | required | overlay |
| `tooltip` | owned, non-interactive, follows anchor | required | overlay |
| `satellite` | owned, non-modal companion (palette, inspector) | required | overlay |
| `kiosk` | owns one display; fullscreen, pinned, exit-protected | none | fullscreen page in the current surface |

- Owned windows close when their owner closes, in reverse open order. An owned
  window cannot outlive its owner; a request with a closed owner fails typed
  (`DV-WINDOW-007`) rather than adopting `main`.
- `modality: window` (default for `dialog`) blocks input to the owner only.
  `modality: application` blocks all windows of the application and is
  honoured only where the OS supports it; elsewhere it degrades to
  `window` and reports `DV-WINDOW-008` at `debug`. Nothing is blocked that the
  platform cannot block — a fake application-modal that leaks input is worse
  than an honest window-modal.
- `popup` and `tooltip` on desktop are the native window kinds the Flutter
  windowing API provides for exactly this purpose, which is why menus and
  tooltips align to the cursor instead of clipping to the parent window.

## Kiosk windows

A kiosk window is a regular window that owns a display and carries a policy it
cannot be argued out of. It is how one application serves a customer-facing
display and a staff terminal at once: the staff window is ordinary; the
customer window is kiosk. It is also how one process drives a signage wall —
one kiosk window per display.

```dart
final customer = await DV.Window.open(
  DVPages.customerDisplay,
  options: DVWindowOptions(
    kind: DVWindowKind.kiosk,
    display: DVDisplayHint.byName('Customer'),
    kiosk: DVWindowKiosk(policy: DVKioskPolicies.customerDisplay),
  ),
);

customer.kiosk!.state;          // DVSignal<DVKioskState>
customer.kiosk!.enforcement;    // what this platform honours for one display
await customer.kiosk!.resetSession();

// From the staff window, already authenticated:
await customer.kiosk!.exit(DVKioskExitRequest.adminAuth());
```

Rules:

- **It owns its display.** `DVDisplay.kioskOwner` is set for the window's
  life. Another window requesting that display is placed on a different one
  and reports `DV-WINDOW-011`. If the display disconnects, the kiosk window
  degrades to a fullscreen page in the current surface (`DV-WINDOW-010`) and
  reclaims the display when it returns — the reclaim is `open()` of the same
  URL, so it is idempotent.
- **It is pinned.** Fullscreen, no move, no resize, no minimize; those requests
  are refused and logged at `debug` (`DV-WINDOW-012`). A user close request is
  refused. The window closes only through `kiosk.exit(...)` satisfying the
  policy's exit method, or through application exit.
- **Its policy is a declared kiosk policy.** `DVWindowKiosk.policy` names a
  policy from `dartvel.kiosk.policies` (see Kiosk Mode); the window inherits
  its `routes`, `input`, `session`, `display`, `notifications` and `exit`
  sections. Input confinement for *one* display is platform-limited — a
  keyboard is a device, not a display — and `enforcement.inputScope` reports
  `display` or `device` rather than implying more than is true.
- **Its session is its own.** A kiosk window's idle reset clears its page
  signals and the shared keys under `kiosk.<name>.*`; it does not sign out the
  application or touch other windows. The staff terminal is unaffected by the
  customer display timing out. (Device-scoped kiosk clears the application
  session; display-scoped never does. See Kiosk Mode › Sessions.)
- **Exit can come from a peer.** `adminAuth` is satisfied by any window whose
  authenticated session passes `DVPolicyAction.exitKiosk`, so staff exit the
  customer display from the terminal they are already signed into. Every exit
  is audited with the actor.
- **It keeps the process alive.** Kiosk windows count as regular windows for
  the exit policy: closing the staff window does not take the signage down.
- **Declared kiosk windows open at boot**, from `dartvel.kiosk.windows`, before
  workspace restore and before `main` presents. They are never part of a
  persisted workspace; a kiosk window comes from policy, not from state.
- **Where no display can be owned** — a phone, a single-display desktop with
  the display already in use, a terminal — `kind: kiosk` degrades like every
  other kind: the route is presented as a fullscreen page and reported. Device
  scope is the right tool for a single-display device; display scope is for
  the second one.

## Main window and process exit

The first window opened is `main`. It is a peer for every purpose except two:

- **Restore anchor.** Workspace restore and deep links with no target land in
  `main`.
- **Exit policy.** `exit: lastWindow` (default on desktop) ends the process
  when the last *regular or kiosk* window closes; owned windows do not count.
  `exit: mainWindow` ends the process when `main` closes; `exit: explicit`
  never exits on window close (tray-resident applications).

If `main` closes under `exit: lastWindow` while other regular windows remain,
the oldest remaining regular window becomes `main`. `DV.Window.main` is a
signal-backed getter so tray and workspace code follows the promotion.

On targets without a process to exit in this sense (web, Android tasks,
iPadOS scenes) the policy is a no-op and is reported once by `dartvel doctor`.

## Lifecycle

```dart
enum DVWindowLifecycle {
  requested, creating, created, ready, active,
  inactive, minimized, maximized, fullscreen,
  closing, closed, failed,
}
```

Lifecycle is a generated read-only enum signal per Lifecycle Signals: the
runtime owns transitions, application code observes. Guarantees:

- `requested → creating → created → ready` occurs exactly once per window.
  `ready` means the route has resolved and the first frame is presented.
- `active` / `inactive` track OS focus. Exactly one window is `active` at a
  time per engine; on separate-engine targets each engine reports its own.
- `minimized` / `maximized` / `fullscreen` are display states entered from
  `active` or `inactive` and return there.
- `closing` is observable and cancellable: a page may register
  `context.window.onCloseRequest(() async => confirmDiscard())`; returning
  `false` returns the window to its prior state. The OS "force close" path
  (process kill) bypasses this and is why the shared store exists.
- `failed` is terminal and only reachable before `ready`; a window that fails
  after `ready` is `closed` with a logged reason.
- Virtual windows run the same states over their route's page lifecycle, so
  observers do not branch on `isVirtual`.

## open() never fails

Where a real window cannot be created, `open()` presents the route the way the
platform can: `regular` becomes a pushed page, `dialog` a modal route, and
`popup`, `tooltip` and `satellite` overlays. The returned `DVWindow` is real
either way, `DV.Window.all` lists virtual windows alongside real ones, and
`close()` pops the route. **Application code never branches on capability.**

Failing is removed; reporting is not. Every fallback carries a stable code, is
written to observability through `DV.log`, and is readable on the window.

```dart
enum DVWindowDegradation {
  none, capabilityUnsupported, kioskLocked, gestureRequired,
  platformRefused, bindingRefused, disabledByConfig,
  displayUnavailable, displayHintUnmatched, restoredRouteUnresolvable,
  ownerClosed, modalityReduced,
}
```

Not every code is a member. `DV-WINDOW-011` and `DV-WINDOW-012` are reported
on the window's `codes` and nowhere else, because each describes one
placement or one refused call rather than the state the window came to rest
in: a window placed away from a kiosk-owned display is otherwise ordinary,
and a pinned window refusing a move is still pinned afterwards.

| Code | Reason | Level |
|---|---|---|
| `DV-WINDOW-001` | target has no multi-window capability | `debug` |
| `DV-WINDOW-002` | kiosk mode active; the surface stays locked | `info` |
| `DV-WINDOW-003` | web popup blocked — called outside a user gesture | `warning` |
| `DV-WINDOW-004` | platform refused (OS window limit, task creation denied) | `warning` |
| `DV-WINDOW-005` | `windowing.enabled: false` in configuration | `info` |
| `DV-WINDOW-006` | native binding missing or refused the request | `error` |
| `DV-WINDOW-007` | owned window requested with a closed owner | `warning` |
| `DV-WINDOW-008` | application modality reduced to window modality | `debug` |
| `DV-WINDOW-009` | restored route missing, unauthorized, or unresolvable | `info` |
| `DV-WINDOW-010` | kiosk window's display unavailable; presented in place, fullscreen | `warning` at boot, once |
| `DV-WINDOW-011` | window requested on a kiosk-owned display; placed elsewhere | `info` |
| `DV-WINDOW-012` | move/resize/minimize/close refused on a pinned kiosk window | `debug` |
| `DV-WINDOW-013` | `display:` hint matched no connected display; the OS placed the window | `warning` |

Levels are calibrated to whether the developer can act. A phone has no windows
and the fallback is the intended behaviour, so warning on every call would
train people to ignore the channel; a blocked popup and a refused task are
fixable. `dartvel analyze performance` aggregates degradations per call site,
so a site that always degrades is one finding, not a thousand log lines.

`DV-WINDOW-006` is the one `error`: a binding that is present but refuses is a
platform integration defect, not a capability limit, and it must not be dressed
up as graceful degradation. It still degrades — the route is still presented —
but it is reported as the bug it is.

Honest about what degrades: `setSize` and `constraints` are no-ops on a virtual
window and log at `debug`; `setTitle` maps to the page title; opening N windows
on a phone yields N stacked routes. A workspace UI should still read
`capability.multiWindow` when deciding whether to *offer* "open in new window"
— degrading a call is right, advertising a control that surprises is not.
Kiosk degradation is not a security hole: kiosk restricts the surface, not the
content, and the route still faces the same middleware and policies.

## Capability

```dart
final cap = DV.Window.capability;
cap.multiWindow;        // can a second OS-level window exist
cap.sameEngine;         // do windows share one engine (object handover)
cap.tearOut;            // can a tab detach into a window by drag
cap.inPageViews;        // web: in-page multi-view embedding
cap.ownedWindows;       // native popup/tooltip/satellite kinds
cap.applicationModal;   // OS supports app-wide modality
cap.displays;           // more than one display is addressable
cap.displayKiosk;       // a window can own one display in kiosk mode
```

Capability is a snapshot at process start plus a signal for the two things
that change at runtime — `displays` and kiosk state — so a workspace can hide a
"move to display" control the moment the display is unplugged.

## Deep links and external open requests

An OS-level request to open a route — deep link, app link, file association,
`dartvel://` URL, a second launch of a single-instance desktop application —
is delivered to `DV.Window.open(route)` with `DVWindowOptions.external`. It is
therefore idempotent by URL: a link to an order already on screen focuses that
window; a link to a new order opens one (or navigates, on targets without
windows). Middleware and policies run before presentation as for any route.
Single-instance behaviour on desktop is on by default (`singleInstance: true`)
and is what makes "second launch focuses the running app" true.

What makes the OS deliver that request in the first place is verification, and
its two files are generated from the route index: see
[Deep-link verification files](#deep-link-verification-files).

## Shared window state

Two handover modes, chosen automatically from `capability.sameEngine`:

- **sameEngine** (desktop, web in-page views): the moved content is the same
  Dart object tree, so signals, in-flight requests and scroll positions survive
  by construction.
- **shared** (web `window.open`, Android tasks, iPadOS scenes): the new window
  is a separate engine, so state crosses through a watched store — one writer
  publishes, every other window is notified and its signals update.

`DV.Window.shared` is a typed, watched key-value store scoped to application,
tenant and user. One API on every platform, desktop included:

```dart
await DV.Window.shared.set('workspace.activeTab', DVJsonString(tab.id));
final tabId = DV.Window.shared.signal<DVJsonString>('workspace.activeTab');

// or declared at the signal, with the wiring generated:
final activeTab = context.signal('', shared: 'workspace.activeTab');
```

A store rather than message passing: a message is delivered once, to whoever
is listening at that instant; a window opened five seconds later gets nothing
and crash recovery has nothing to read. A store has no delivery moment — late
joiners read current state on open, and the same bytes that sync a running
window restore a crashed one. This is why there is **no `DV.Window.broadcast`**:
the store publishes state, which a late or restarted window can read; a message
API would publish events, sitting alongside model sync doing a worse version of
its job.

What varies per target is which of the store's two jobs the OS performs:

| Target | Notification | Persistence |
|---|---|---|
| Windows / macOS / Linux | in-process — signals | platform key-store-backed file via `DV.FileStorage` |
| Android | `OnSharedPreferenceChangeListener` | `SharedPreferences` |
| iPadOS | KVO | `NSUserDefaults` |
| Web | `storage` event | `localStorage` |

Rules:

- **Keys are namespaced.** `workspace.*` is reserved for `DVTabWorkspace`;
  application keys must not start with `dv.` or `workspace.`. A violating key
  is a build error where static, a typed runtime failure otherwise.
- **Encryption is Dartvel's, not the store's.** Values are encrypted with the
  application key (Secrets and Environments) before the write, so the backing
  store is a dumb byte sink on every target — one code path, one threat model.
  Encryption is whole-store, never per key.
- **Writes are coalesced.** A signal changing per frame must not write per
  frame; shared writes are debounced and batched per flush (`debounceMs`).
- **Last write wins, per key.** Keys are the conflict unit. State that needs
  merge semantics is model state — use a model.
- **Large values spill.** Anything over `spillThresholdKb` goes to
  `DV.FileStorage` with an encrypted pointer left behind; the pointer write is
  the notification.
- **The store is not for model data.** Models converge through model sync,
  which applies auth, tenant filters and policy checks before delivery;
  duplicating rows into the store would bypass all three. The store holds view
  state: active tab, tab order, layout, scroll offsets, drafts.
- **`DV.Secrets` values never reach it.** A backend-scoped secret on a client
  is a `DV-SECRETS-001` violation regardless of encryption; that stays a build
  error.
- **Entries are ephemeral by contract**, session-scoped and swept by age
  (`sweepAfter`). A crashed application leaves a readable store — that is the
  recovery feature — but a stale one is collected rather than kept.
- **An undecryptable store is discarded, not fatal**, and reported through
  `DV.log`.

Genuinely separate processes — a second *instance*, which `singleInstance`
prevents by default — fall outside preference listeners and degrade to polling
at `pollMs`, reported once by `dartvel doctor`.

## Persistence and restore

```dart
await DV.Window.persistWorkspace('default');
await DV.Window.restoreWorkspace('default');
```

A persisted workspace is the ordered list of regular windows — each as
canonical URL, kind, size, display hint and title — plus the `workspace.*`
shared keys. It is tenant- and user-scoped like all stored state. Owned windows
are never persisted; they are derived from their owners' pages.

Kiosk windows are excluded from persistence by contract; they open from
`dartvel.kiosk.windows` before anything else.

`restoreOnLaunch: true` restores `default` at boot, before `main` presents,
so the user sees their workspace rather than a flash of the home route.
Restore is defensive: a URL whose route no longer exists, no longer resolves,
or is no longer authorized for the current user is skipped and reported
(`DV-WINDOW-009`, `info`) rather than opening an error page in a window.
If nothing restores, `main` opens the home route.

## Inheritance and scope

A window inherits **theme, locale, tenant, auth session and module scope** from
the application; none is per-window. The one per-window surface is `title`.
This is a rule, not a limitation to be lifted: a per-window theme would be the
first thing a workspace's shared store could not represent, and a per-window
tenant would be a data-isolation hole with a friendly name.

**Shortcuts** are focus-scoped by default: a page's shortcuts fire only when
its window is `active`. `DV.Platform.Shortcuts.register` (global shortcuts)
stays global and fires regardless of focus, as its name says.

**Accessibility**: each real window is its own semantics tree and announces
its title on `ready` and on focus gain, matching platform convention. Virtual
windows announce as route changes. `dartvel test accessibility` covers both.

## Platform matrix

| Target | Multi-window | Mechanism | Handover | Owned kinds | Label |
|---|---|---|---|---|---|
| Windows | yes | Flutter windowing (`RegularWindow`, FFI) | sameEngine | yes | `Experimental`¹ |
| macOS | yes | Flutter windowing | sameEngine | yes | `Experimental`¹ |
| Linux | yes | Flutter windowing; Wayland: never placement | sameEngine | yes | `Experimental`¹ |
| Web | yes | `window.open(route)`; in-page multi-view | shared / sameEngine² | overlay only | `Supported with limitations` |
| Browser extension | in-page only | multi-view tier; `tabsCreate` for routes | sameEngine² | overlay only | `Supported with limitations` |
| Android | yes | task-per-window via engine groups | shared | no | `Supported with limitations` |
| iPadOS | yes | `UIScene` | shared | no | `Supported with limitations` |
| iOS (iPhone) | no | navigation fallback | — | overlay only | `Supported with limitations`³ |
| Fuchsia | plausible | view-based compositor | sameEngine | tbd | `Experimental` |
| Tizen / webOS | no | single-fullscreen app model | — | overlay only | `Supported with limitations`³ |
| eLinux / embedded | no by policy | kiosk stays locked | — | overlay only | `Supported with limitations`³ |
| Watch | no | navigation fallback | — | overlay only | `Supported with limitations`³ |
| Terminal (`-cli`/`-tui`) | no | navigation fallback; multiplexer surfaces deferred | — | overlay only | `Supported with limitations`³ |

¹ **Upstream dependency, stated plainly.** Flutter's desktop windowing API
(`RegularWindow`, `RegularWindowController`, `WindowRegistry`, window-backed
dialogs and tooltips) ships behind `flutter config --enable-windowing` and
still uses framework-internal imports on the application side. Dartvel is the
churn absorber: the generated bindings under `window.*` are the only code
touching that surface, so an upstream rename is a Dartvel point release rather
than an application change. Out-of-tree embedders (the television and
embedded forks) implement windowing by overriding `createWindowingOwner`, which
is how a future TV or Fuchsia row could turn on without touching this
contract. Desktop rows stay `Experimental` for as long as the flag exists.

² Web is two tiers by design: `window.open` for OS-level windows, and in-page
multi-view embedding for panels and workspace regions. The second tier serves
the browser-extension targets, where `open()` of a regular window maps to
`DV.Platform.browserExtension.tabsCreate(route)` and an owned kind maps to an
in-page overlay.

³ The *capability* is unsupported; the *API* is not. `capability.multiWindow`
reports false and no OS window is created, but `open()` presents the route, so
application and workspace code compiles and runs unchanged. No target is
labelled `Unsupported`, because the label describes what an application can
rely on, and every target can rely on `open()` presenting the route.

Display-scoped kiosk (`capability.displayKiosk`) requires `multiWindow` and
`displays`; it is available on the desktop rows and on eLinux multi-head
configurations, with per-display enforcement reported as described under
Kiosk Mode › Enforcement.

## Configuration

```yaml
dartvel:
  windowing:
    enabled: true
    singleInstance: true          # desktop: second launch focuses, not forks
    exit: lastWindow              # lastWindow | mainWindow | explicit
    restoreOnLaunch: true
    workspace:
      persist: true
      tearOut: auto               # auto | disabled
    sharedState:
      encrypt: true               # informational; cannot be disabled
      debounceMs: 50
      spillThresholdKb: 32
      pollMs: 250                 # separate-process fallback only
      sweepAfter: 24h
    web:
      inPageViews: true
      openInNewWindow: true
    android:
      freeform: auto
    # kiosk policy lives under dartvel.kiosk (see Kiosk Mode);
    # windowing.kiosk.allowWindows remains a compatibility alias of
    # dartvel.kiosk.windows in device scope.
```

`sharedState.encrypt` is shown for discoverability and validates as `true`;
setting `false` is a build error, because a per-project opt-out is how the one
project that mattered ships plaintext drafts.

## Bindings

Stability: `Draft` · Status: `Designed`

Generated FFI/ffigen or JNI/jnigen bindings only, per the standing rule:

- desktop: `window.open`, `window.close`, `window.setTitle`, `window.setSize`,
  `window.setFullscreen`, `window.minimize`, `window.maximize`,
  `window.restore`, `window.observeLifecycle`, `window.displays`,
  `window.display.assign`, `window.pin`, `window.unpin`,
  `window.instance.acquire` (single-instance lock)
- android: `window.task.open`, `window.task.close` (JNI, engine groups)
- ios: `window.scene.request`, `window.scene.close`
- web: generated bindings over `window.open`, `localStorage`, the `storage`
  event, and the multi-view embedder API; extension targets add `tabs.create`
- shared store: `window.shared.get`, `window.shared.set`,
  `window.shared.observe`; desktop needs no `observe`, since notification is
  in-process

A missing or refusing binding fails typed (`DV-WINDOW-006`), never silently.

## Inspection, Studio and the project graph

Windows and tabs are project-graph nodes. `dartvel inspect windows --json`
answers like every other inspector: the static picture (which routes declare
window identity, workspace pages, configured exit and restore policy) and,
against a running app, the live window list with route, kind, owner, lifecycle
state, presentation, degradation, handover mode, and the capability report per
configured target. Studio's window inspector renders the same data and lets
an operator close, focus (via open) and inspect a window's shared keys —
values shown decrypted only to an authorized session, never logged.

## Testing

```dart
DV.Test.fakeWindowing(
  const DVWindowingCapability(multiWindow: false),   // simulate a phone
);
DV.Test.fakeWindowing(DVWindowingCapability.desktop());

final win = await DV.Window.open(DVPages.orders);
expect(win.presentation, DVWindowPresentation.page);
expect(win.degradation, DVWindowDegradation.capabilityUnsupported);
```

Fakes are explicit; no test passes because windowing was silently absent.
Golden tests run per window, keyed by route, and `dartvel test e2e` drives
real tear-out on desktop runners where the flag is available.

## Performance contracts

Measured: time from `open()` to `ready` (real and virtual), tear-out handover
time on same-engine targets, shared-store write rate and coalescing ratio,
store size and spill count, and restore-on-launch duration. Diagnostics:
a call site that always degrades, a shared key written more than once per
frame before coalescing, a workspace whose restore exceeds the startup budget,
and owned windows outliving the frame budget on close.

## Security

- A window presents a route, so middleware and policies run before
  presentation; there is no window-level bypass of auth, tenant or policy.
- Kiosk keeps the surface locked (`DV-WINDOW-002`); content still presents in
  place under the same policies.
- Web `open()` requires a user gesture for real windows; the platform enforces
  it and Dartvel reports it (`DV-WINDOW-003`) rather than attempting a bypass.
- The shared store is encrypted with the application key and never holds
  `DV.Secrets` values or model rows.
- Restore never opens a route the current user is not authorized for.

## Compatibility

`DV.Platform.Window.setTitle` / `persistState` / `restoreState` continue to
work as sugar over `DV.Window.current`. No existing surface is removed, so no
project has to move. `dartvel migrate-code` is where a rewrite to the explicit
form would live, and that command is designed and not built; see *Upgrade and
compatibility*.

## Deliberately absent

Closed as a list so they are not reopened item by item:

- **A second windowing namespace.** `DV.Window` (= `DV.Platform.Window`) is
  the whole surface. No `DVWindowManager`, no `DV.Windows`, no `DVWindowing` —
  not as a public type, not as a documented name, ever. Anything the
  implementation needs beyond `DV.Window` and `DVWindow` is private.
- **Window placement / `setPosition`** — three targets could honour it, one
  refuses; not a capability. Display hint only.
- **`activate()` / `focus()`** — `open()` is the one verb; idempotent by URL.
- **`DV.Window.broadcast` / messaging** — the store publishes state; events
  belong to model sync.
- **`DVTab.widget(...)`** — a tab without a route cannot tear out on any
  separate-engine target, cannot deep-link, cannot restore. Make a page.
- **Per-window theme, locale, tenant or auth** — inheritance is the rule.
- **Spawning terminal emulators for windows** — requires the window server
  terminal rendering exists to avoid; multiplexer surfaces deferred.
- **Store encryption opt-out** — whole-store, always on.

# Tab Workspaces

Stability: `Contract` · Status: `Partial`

`DVTabWorkspace` is a generated application component — like `User.Table()`,
composed from `DVBox` and `DVText`, introducing no new primitive — that owns
the tab strip, reordering, tear-out and re-dock, wired to `DV.Window`.

```dart
@DVPage(title: 'Workspace')
Widget _workspacePage(BuildContext context) => DVTabWorkspace(
      initialTabs: [
        DVTab(DVPages.orders),
        DVTab(DVPages.customers),
        DVTab(DVPages.reports),
      ],
      workspace: 'default',          // persistence name; null disables
    );
```

A tab is a route — the same identity a window has — which is what makes
tear-out navigation rather than surgery.

- **Reorder** — drag within the strip; on TV and watch the strip renders as a
  platform-appropriate switcher and reorder is a context action. Pure UI; no
  windowing capability required.
- **Tear-out** — drag beyond the strip, or a context-menu action where drag is
  unavailable. Gated on `capability.tearOut`; executes
  `DV.Window.open(tab.route)`. Where `tearOut` is false the drag gesture is
  absent rather than broken, and the explicit "open in new window" affordance
  is shown only where `capability.multiWindow` is true.
- **Re-dock** — dragging a tab into another window's strip. Same-engine targets
  hit-test across windows and hand the object over; separate-engine targets
  re-dock by adoption: the receiving workspace adds the route, the source
  closes it. Same convergence, two steps.
- **Empty-window rule** — a workspace window whose last tab leaves closes
  itself; if the OS closes a workspace window around its tabs, they fold into
  `main`. Workspace state policy, not window callbacks, so tear-out, re-dock
  and cleanup are one transition.
- **Duplicate tabs** — a route already open as a tab focuses that tab; a
  deliberate second tab says `DVTab(route, duplicate: true)`, mirroring
  `open()`.
- **Persistence** — layout, tab order and active tab persist under the
  workspace name through `persistWorkspace` / `restoreWorkspace`, tenant- and
  user-scoped.

Capability-shaped, never capability-broken:

```text
tearOut: true       → detachable tabs                        (desktop, iPad)
tearOut: false,
  multiWindow: true → tabs plus explicit "open in new window" (web, Android)
multiWindow: false  → tabs only; open() navigates            (iPhone, TV, watch, kiosk, terminal)
```

Web tear-out by drag is false because a drag ending on the desktop cannot open
a popup without a gesture-attributed call; web gets the explicit affordance,
which satisfies the gesture requirement.

Tear-out on a separate-engine target is: write the tab's `workspace.*` shared
keys, open the window at the route, let the new engine read them on boot. The
route carries identity and the store carries state, so a slow-starting window
loses nothing — the state is waiting for it.

Tear-out never produces a kiosk window: kiosk windows come from policy, not
from a gesture, and a tab dragged out of a strip is a regular window.

Sharing is always explicit at the signal declaration. A workspace does not
implicitly share its tabs' page signals, because implicit persisted writes of
arbitrary signal values are both a redaction risk and a write-amplification
one.

# Dartvel Studio

Stability: `Draft` · Status: `Shipped`

Dartvel Studio is the admin section every Dartvel application ships with —
WordPress's admin for a Flutter platform. Every app is fully self-contained,
frontend and backend, regardless of publish target: the app carries the tools
to manage itself.

Studio provides:
- **Page management with a visual builder.** Pages are managed like WordPress
  content, edited with a builder that sits between a free canvas (Figma) and a
  page-based editor (WordPress/FlutterFlow) — Framer's middle ground.
- **Model management.** Generated model CRUD, driven by the same metadata the
  admin already uses.
- **Backend function and workflow building.** Drag-and-drop composition of
  backend behaviour, Webflow/FlutterFlow-style. A `DVWorkflowDocument` is a
  serializable step tree — `call`, `set`, `condition`, `return` — that
  `DVWorkflows.run` executes directly, so saving publishes, and
  `toDartSource()` exports as an ordinary `@DVBackendFunction`, so the builder
  can be dropped. Steps call actions registered with
  `DVWorkflows.registerAction`, which is the same code an application calls.
  A workflow fails loudly: an unknown action or variable stops the run and
  names the step, rather than yielding null and reporting success.

## The page builder

The builder manipulates **real widgets, not a canvas facsimile**. No
CustomPaint re-implementation of the UI: the editing surface instantiates the
same `DVBox`/`DVText`/generated components the running app renders, so what is
edited is what ships. It must be feature-rich enough that Dartvel itself could
be rebuilt with it.

- Drag/drop inserts and moves actual widgets. `DVStudioPalette` is the source
  list, `DVStudioCanvas` renders the document as real widgets with selection
  and drop targets layered over it, and `DVStudioEditorController` owns
  selection and a bounded undo/redo history — an editor without undo is not an
  editor, since a mis-drop that cannot be reversed loses work.
- Properties, modifiers, gestures, and actions are edited on the selected
  widget through `DVStudioInspector`; actions bind to `DV.Navigation`,
  backend functions, and signals.
- View-code at any time (Figma/Webflow-style), and full code export: a page
  document exports to the same private `@DVPage` source a hand-written page
  uses, with no builder runtime required afterwards.

The load-bearing primitive is the **page document**: a serializable widget
tree (`DVPageDocument`) that the builder edits, the renderer instantiates as
real widgets, the store persists through `DV.Database`, and the exporter lowers
to Dart source. Everything else in the builder is UI over these four
operations.

```dart
final document = DVPageDocument(route: '/pricing', title: 'Pricing');
// Editor operations — what drag/drop and the inspector call:
final editor = DVPageDocumentEditor(document);
editor.insert(DVPageNode.text('Plans'), parent: document.root.id);
editor.update(nodeId, (node) => node.withProperty('fontSize', 24));
editor.move(nodeId, parent: otherId, index: 0);

// The same document, three ways out:
DVPageDocumentRenderer(document)   // real widgets, in-app and in-editor
document.toDartSource()            // full code export, @DVPage form
await DVPageStore().save(document) // persisted, immediately publishable
```

## Publishing

- Saving publishes: stored documents are served to running apps immediately —
  page content is data, like WordPress posts.
- **A stored document overrides the compiled page.** A compiled `@DVPage` is
  the entrypoint an app ships with, not a permanent fixture: the editor has to
  be able to change it, or a shipped page could never be edited, only added
  to. Deleting the document restores the compiled page, so an edit is always
  revertible.
- Routes with no compiled page at all are served from the store too, so the
  editor can add pages as well as edit them.
- A page already on screen reloads when its own document is saved, so an edit
  reaches a running app without navigation.
- Compiled export: `document.toDartSource()` emits the page as ordinary
  `@DVPage` source for projects that want the builder out of the loop.
- OTA on command: `dartvel updates patch` pushes builder-made changes to
  installed applications. Documents travel as a `DVPageBundle` — a versioned
  set of pages plus the routes it withdraws — and `DVPageBundleInstaller`
  writes them into the store on apply. Applying a version twice is a no-op,
  because a patch can be delivered more than once and re-applying it would
  undo edits made since. A rollback ships the previous bundle rather than
  inverting one, which is the only way to be sure what an app ends up with.

---

# Admin, Devtools, and Scaffolding

Stability: `Draft` · Status: `Shipped`

Other batteries-included frameworks provide strong admin and tooling surfaces.
Dartvel should generate them from the same metadata used by models, pages,
jobs, signals, policies, and middleware.

```bash
dartvel devtools
dartvel admin generate
```

Generated admin/devtools include:
- model CRUD admin
- queue/job dashboard
- failed job retry/discard controls
- mail/notification outbox
- policy and permission explorer
- route/page explorer
- cache/tag explorer
- model sync channel inspector
- search index status
- billing/customer/entitlement views
- logs/metrics/traces views

Admin UI must use `DVBox`, `DVText`, generated model components, and Dartvel
modifiers. It must not introduce new primitive widgets.

---

# Data Import, Export, and Reporting

Stability: `Draft` · Status: `Partial`

Dartvel should include typed bulk data workflows:
- CSV, JSON, NDJSON, and Excel import/export, and PDF export
- generated import validation
- row-level error reports
- resumable imports through queues
- tenant-aware exports
- policy-filtered exports
- scheduled reports
- streamed large exports

```dart
await User.Import.csv(file);
await User.Import.resumableCsv(file, queue: 'imports', chunkSize: 500);
await User.Import.ndjson(lines);
await User.Import.resumableNdjson(lines, queue: 'imports', chunkSize: 500);
await User.Import.excel(tabSeparatedRows);
final export = User.Export.ndjson(users);
final spreadsheet = User.Export.excel(users);
final document = await User.Export.pdf(users);
final invoice = await order.Export.pdf();  // one record, the instance alias
final tenantExport = User.Export.csv(
  users,
  options: DVExportOptions<User>(
    tenantId: 'tenant_123',
    policyFilter: (user) => user.active,
    chunkSize: 1000,
  ),
);
await for (final chunk in User.Export.streamNdjson(users)) {
  await DV.FileStorage.put(chunk.fileName, chunk.bytes);
}
final report = await Order.Report.monthly(...);
final scheduled = Order.Report.scheduleMonthly(cron: '0 8 1 * *');
await Order.Report.dispatchMonthly(
  cron: '0 8 1 * *',
  queue: 'reports',
);
```

Exports use storage providers and queued jobs for large datasets.
Resumable imports dispatch typed `DVImportChunk` payloads through `DVQueues`, so
workers can process large files without holding the entire import in one request.
Tenant-aware and policy-filtered exports use `DVExportOptions<T>`, attach export
metadata to `DVExportResult`, and can stream CSV/NDJSON chunks for large files.
Scheduled reports generate typed `DVScheduledReport` payloads and dispatch them
through `DVQueues`, so cron workers can execute report generation with durable
retry, queue selection, priority, and report-period metadata.

## PDF

Billing implies invoices and this section implies reports, and both of those
are documents somebody prints, attaches to an email, or files for seven years.
PDF is an export format here:

```dart
final receipt = await Order.Export.pdf(
  orders,
  options: DVExportOptions<Order>(tenantId: 'tenant_123'),
  document: const DVPdfOptions(
    paper: DVPaper.a4,
    margins: DVInsets.mm(18),
    header: DVPdfRunning.title,
    footer: DVPdfRunning.pageNumbers,
  ),
);
```

**It is the same rendering path as everything else.** A PDF is produced by
printing the document Static Web Generation already produces for that route or
model page — the same semantic HTML, the same generated styles, the same
fonts as the application's own, embedded. Dartvel does not carry a second
layout engine for paper. A separate PDF widget tree would mean every invoice
existed twice, diverging quietly until somebody noticed the printed total was
from last year's template, and it would need its own tables, pagination and
text shaping, which a print stylesheet already has.

Paged behaviour — repeating a table's header row across pages, keeping a total
with its table, page breaks between records — is CSS, in the print stylesheet
that generated pages already carry. An application overrides it the way it
overrides any other generated style.

Rendering runs where a browser engine is: the web-server or the backend, using
the same headless browser `dartvel build web` uses to capture semantics. A
client asks the backend for the document rather than rendering one, because
putting a rendering engine on a phone to produce a file it is about to upload
is the second path this section refuses. A deployment with no renderer
available fails typed at build (`DV-EXPORT-002`) rather than at the moment
somebody presses Download.

Exports are policy-filtered and tenant-scoped as above, and
`@DVModel.sensitiveField()` values are excluded from the document by the same
rule that excludes them from a CSV — a PDF is a serialization like any other,
and the most likely one to be emailed to somebody outside the tenant.

| Code | Reason | Level |
|---|---|---|
| `DV-EXPORT-001` | PDF export requested for a route with no generated document | build `error` |
| `DV-EXPORT-002` | no PDF renderer available in this deployment | build `error` |
| `DV-EXPORT-003` | document exceeded the configured page or byte budget | `warning` |

---

# Secrets and Environments

Stability: `Draft` · Status: `Partial`

A secret compiled into a client bundle ships to every visitor. Because Dartvel
compiles both ends from one project, it can make that a build error rather than
a code-review habit — no stack assembled from separate frontend and backend
repositories can.

Secrets are **backend-scoped by default**. Reaching one from client-reachable
code is a typed build error, `DV-SECRETS-001`. Genuinely public values — a
publishable Stripe key, a map tile token — opt in explicitly, and the opt-in is
visible in the declaration rather than inferred from a call site.

## Declaration

Secrets are declared under `dartvel:` in `pubspec.yaml`. **Names and scopes
only; never values.**

```yaml
dartvel:
  secrets:
    PAYSTACK_SECRET:
      scope: backend            # default; may be omitted
      required: [production, staging]
    PUBLIC_STRIPE_KEY:
      scope: client             # ships to the bundle, deliberately
      required: [production]
    OPENAI_API_KEY:
      scope: backend
      required: []              # optional everywhere
```

The declaration is what makes the rest possible: an enumerable set is what
`dartvel deploy` validates, what rotation iterates, and what an inspector can
report. An undeclared name used through `DV.Secrets` is a build error naming
the pubspec key to add, because a typo in a secret name is otherwise a runtime
failure in production.

A `scope: client` secret must carry the `PUBLIC_` prefix. There is one client
opt-in, not two: the prefix is the marker in the environment and the generated
`env.g.dart`, and the declaration is where it is justified.

## Access

```dart
final key = DV.Secrets.get('PAYSTACK_SECRET');     // throws if unresolved
final opt = DV.Secrets.maybeGet('OPENAI_API_KEY'); // null if unresolved
final url = DV.Secrets.getOr('CACHE_URL', 'memory://');
DV.Secrets.has('PAYSTACK_SECRET');
```

Resolution order is process environment, then `.env` for local development,
then values supplied by `DV.Secrets.configure(...)`. Vault and KMS adapters
plug in behind the same call, so application code never learns where a value
came from.

## What is guaranteed, and by which layer

Stated separately because the layers have different strengths, and a reader
deciding what to rely on needs to know which is which.

1. **Values never reach a client bundle.** Only `PUBLIC_`-prefixed variables are
   emitted into the generated `env.g.dart`, and a web build resolves the process
   environment to nothing at all — the browser implementation returns null by
   construction and `DV.Secrets.get` throws `DVSecretNotFoundException` naming
   the backend function to fetch the value through. This is a structural
   guarantee: it holds whether or not any analysis runs.
2. **`DV-SECRETS-001` reports a backend-scoped secret reached from client
   code.** A diagnostic over the declared set and the generated client's import
   graph. It is a strong signal, not a proof — a value routed through an
   indirection it cannot follow is a false negative, which is exactly why layer
   1 is structural and layer 2 is advisory on top of it.
3. **`dartvel deploy` refuses to ship when a declared secret required for the
   target environment does not resolve.** Checked against the declaration, so a
   secret forgotten in a new environment fails the deploy rather than the first
   request that needs it.

## Redaction

Secret values are excluded from logs, traces, diagnostics and error messages by
construction — the same exclusion set as `@DVModel.sensitiveField()`, which
remains the single normative list. An exception raised while resolving a secret
names the key, never the value.

## The application key

The secrets above are backend-scoped. A client also needs a key — for the
shared window store, and for anything else Dartvel encrypts at rest on a
device — and it is a different key with a different threat model. Conflating
the two is how a device key ends up on a server, or a server key in a bundle.

```bash
dartvel key generate     # writes to the platform key store, never the repo
dartvel key rotate
dartvel key status
```

The application key is **never in the bundle and never in `pubspec.yaml`**.
That is this section's own rule rather than caution: only `PUBLIC_`-prefixed
values reach the generated `env.g.dart`, and a key shipped to every visitor
encrypts nothing. A server-side framework can keep such a key in an
environment file because it lives on a machine the operator controls; an
application's store lives on the user's device, so the key must come from
somewhere the user's own OS protects.

| Target | Key custody |
|---|---|
| Windows | DPAPI-protected, per user |
| macOS / iPadOS | Keychain, app-scoped |
| Linux | Secret Service (libsecret), keyring-backed |
| Android | Android Keystore, hardware-backed where available |
| Web | non-extractable WebCrypto `CryptoKey` in IndexedDB |

Generated at first run, per install and per user, so it is not a shared secret
and there is nothing to leak into version control. The web row is the
strongest in one specific way: a non-extractable `CryptoKey` cannot be read
back even by the application's own JavaScript, so it survives an XSS that
would trivially lift a string from `localStorage`.

Rotation re-encrypts in place through the same hook shape as below. Backend
encryption of model fields at rest uses the server-held key from `DV.Secrets`
in the ordinary way; these two never meet.

## Rotation

```dart
DV.Secrets.onRotate('PAYSTACK_SECRET', (String value) async {
  await paymentGateway.reconfigure(value);
});
```

Rotation hooks fire when a resolver reports a new value, so a long-lived client
holding a connection can rebuild it without a restart. A secret with no hook is
simply re-read on next access.

## Testing

`DV.Test.withSecrets({...})` supplies values for the duration of a test and
restores the previous state after, so a suite never depends on the developer's
environment and a forgotten override cannot leak into the next test.

---

# Deployment

Stability: `Draft` · Status: `Shipped`

## Monolith
Single native backend binary. x64 linux by default, can be targeted optionally.

## Function mode
Each backend function can be deployed independently.

Targets:
- AWS Lambda
- Cloud Run
- Containers
- Edge runtimes
- Fly.io
- Railway
- Bare metal

---

# Backend Release Management

Stability: `Draft` · Status: `Designed`

Deployment says where a backend runs. This says how a new one replaces the one
already running, and how it goes back.

OTA Updates gives clients channels, staged rollout, health gates and rollback
with a provenance record. The backend serving those clients has none of that,
and it is the half that cannot be rolled back by asking a device to fetch an
older bundle. Schema Evolution's expand and contract steps also have to be
sequenced against a deploy that can move backwards: a contract that runs while
the previous release is still serving takes the column that release reads.

## Strategies, and what an adapter can actually do

```yaml
dartvel:
  deploy:
    strategy: canary          # recreate | blue-green | canary
    canary:
      steps: [5, 25, 50, 100]
      hold: 10m
```

Whether a strategy is available is the **adapter's** answer, not the
planner's — the same rule Schema Evolution uses for migration classification,
and for the same reason: a closed list in the planner cannot be taught by a new
adapter, and platforms differ in what they can weight.

| Adapter | Canary | How |
|---|---|---|
| Cloud Run | yes | revision traffic weights |
| AWS Lambda | yes | alias weights per version |
| Fly.io | yes | per-machine rollout |
| Kubernetes-style containers | yes | replica-set weighting through the configured ingress |
| Bare metal, single container, edge runtimes with no weighting | no | blue-green with a health gate |

**Where a platform cannot weight traffic, Dartvel does not simulate it.**
Splitting by DNS or by starting a second fleet and hoping looks like a canary
and is not one: DNS caches for as long as a resolver feels like, so neither the
split nor the rollback is a measurement anybody can trust. Such an adapter
degrades to blue-green, says so in the plan, and keeps the health gate
(`DV-RELEASE-002`).

## Health is the request lifecycle, not a ping

A canary is promoted or rolled back on what the Backend Function Request
Lifecycle already reports. Its stages are numbered, so a failure has a place
rather than a rate: authorization refusals at stage 12 rising against the
previous release is a different fault from transactions failing at stage 17,
and a `/healthz` that answers 200 while both happen is the reason a ping is not
a health check.

```yaml
dartvel:
  deploy:
    gate:
      errorRate: 1%           # against the release being replaced, not absolute
      stages:
        commit: 0.1%          # stage 17 failures
        authorization: 2%     # stage 12 refusals
      latencyP95: +20%
```

Thresholds are relative to the release being replaced, because absolute numbers
encode one deployment's traffic and are wrong on the next. A gate with no
previous release to compare against — a first deploy — holds the rollout and
says so rather than passing vacuously.

## Rollback, and what a release is

```bash
dartvel deploy --plan          # the sequence, before anything runs
dartvel deploy rollback        # to the previous release, by provenance record
dartvel deploy rollback --to 2026-09-11T14:02Z
```

A release carries the provenance record OTA patches carry: what was built, from
which commit, with which generated protocol version, which migration plan ran,
and who released it.

**The release is the unit of rollback, including in function mode.** Rolling
back one function and leaving its neighbours is a state nobody described: the
functions in a release share generated serialization, one protocol version and
one schema expectation, so a mixed fleet answers the same client two ways. Per
function rollback is refused, naming the release to roll back instead
(`DV-RELEASE-004`). Function mode still deploys functions independently — that
is what it is for — but a rollback restores the set that was released together.

## The deploy is the migration's choreography

Schema Evolution's plan is not a separate ceremony run by hand; its steps are
the deploy's steps:

```text
1. expand        — add alongside, dual-write; the old shape still reads
2. deploy        — the new release rolls out under the strategy above
3. backfill      — resumable, rate-limited, verified per chunk
4. read switch   — after verification reports no discrepancy
5. contract      — once no windowed release reads the old shape
```

Step 5 is gated by Protocol Versioning and Client Compatibility, not by a
timer: contract is refused while a client inside the window still reads what it
would drop (`DV-RELEASE-005`). A deploy that would run a blocking migration
against production is refused without an explicit, logged override — the same
discipline `dartvel compatibility-check` applies to clients.

## Diagnostics

| Code | Reason | Level |
|---|---|---|
| `DV-RELEASE-001` | health gate tripped; the rollout was rolled back | `error` |
| `DV-RELEASE-002` | the adapter cannot weight traffic; canary degraded to blue-green | `warning` |
| `DV-RELEASE-003` | no previous release to compare against; the gate held the rollout | `warning` |
| `DV-RELEASE-004` | per-function rollback requested; the release is the unit | `error` |
| `DV-RELEASE-005` | contract step refused while a windowed client still reads the old shape | `error` |
| `DV-RELEASE-006` | a release was deployed with no provenance record; rollback cannot name it | `warning` |

## Deliberately absent

- **A traffic manager of Dartvel's own.** Weighting belongs to the platform;
  where there is none, the plan says so.
- **Service mesh and multi-region orchestration.** Region pinning and a
  multi-region backplane are their own question, and pretending a deploy
  strategy answers it would be worse than the gap.
- **Rollback of data.** A migration's contract step is refused while it is
  unsafe; it is not undone afterwards by guessing. Restoring data is the
  database's own backup and recovery story.

---

# Preview Environments

Stability: `Draft` · Status: `Designed`

Deployment says where a backend runs and Backend Release Management says how a
new one replaces it. This says how a branch gets one of its own, for as long as
somebody is looking at it.

A preview is a whole deployment: the backend, its database, its storage, and
the web build, at a URL nobody has to configure. It exists because the question
a reviewer actually has is "what does this do", and a diff does not answer it.

```bash
dartvel preview create                 # from the current branch
dartvel preview create --from-pr 412
dartvel preview list
dartvel preview open
dartvel preview logs --follow
dartvel preview destroy
```

## The database is fresh, and that is not a limitation

A preview gets an empty database, migrated by the project's own migration plan
and filled by the project's own seeds. **It is never a copy of production.**

That is the decision this section exists to make, because the other answer is
tempting and irreversible. Production data in an environment with a generated
URL, a short life and none of production's controls is a leak that cannot be
walked back, and "it was only for a review" is not a thing anyone gets to say
afterwards. The seeds are also the better test: a preview built from seeds
fails when the seeds have rotted, which is the moment to find out.

Where a provider offers database branching — Neon, PlanetScale, and the
adapters that follow them — the branch may be used, and it is used **for the
schema**. Branching one that holds `@DVModel.sensitiveField()` values is
refused unless a sanitization step is declared and runs first
(`DV-PREVIEW-003`). A refusal here is not conservatism: the field annotation
already says these values need a policy decision to reach a client, and a
preview is a client with a guessable address.

```yaml
dartvel:
  preview:
    database: fresh           # fresh | branch
    sanitize: lib/dev/sanitize.dart   # required when database: branch
    ttl: 7d
    idle: 30m
    max: 10
    visibility: members       # members | link | public
```

## Secrets

A preview is its own environment, named `preview`, and Secrets and
Environments' `required:` lists apply to it like any other. A secret required
in production and absent for previews is a **plan-time refusal**
(`DV-PREVIEW-002`), not a runtime failure in front of the reviewer.

Production values are never resolved for a preview. The reason is narrower
than "hygiene": a preview holding a live payment key takes real money from
whoever clicks the button, and the first anyone knows is the settlement report.

## A preview does not send anything to anybody

Notifications, queues and schedules are the part of a preview that can reach
the outside world, so they default to the providers that cannot.

- Mail goes to a capture inbox, readable with `dartvel preview mail` and in
  Studio, and every capture reports `DV-PREVIEW-006`.
- Push notifications are a no-op with the same report.
- Queues are the preview's own; a preview never consumes a production queue.
- Scheduled jobs do not run unless the preview declares which ones should,
  because a preview left open over a weekend should not send a week of digests
  to a seeded address list (`DV-PREVIEW-008`).

Each default is overridable per preview, and overriding is a declaration in
the project rather than a flag somebody passes once.

## Who can see it

`visibility: members` is the default: the preview is behind the deployment's
own organization membership, so opening it asks for a sign-in and a person who
is not a member does not get in. `link` gives an unguessable URL to anyone
holding it. `public` is a declaration, reported as `DV-PREVIEW-007`, for the
case where the preview is the demo.

Every preview is excluded from indexing whatever its visibility —
`X-Robots-Tag: noindex`, a matching `robots.txt`, and the canonical link the
SEO section writes pointing at production. A preview outranking the product it
previews is a well-attested way to lose traffic, and it happens because
indexing is opt-out everywhere else.

## The client half

A preview builds the web target and serves it against the preview backend, so
the URL is the whole of what a reviewer needs.

For mobile there is no preview install, and Dartvel does not pretend
otherwise: it does not push a build to a store or a device. What a preview
gives a native application is a backend a debug build can be pointed at, and
the web build to look at meanwhile. Reviewing a native change on a device is
the OTA channel's job.

A preview's generated protocol version is free to differ from production's. It
serves only its own clients, so Protocol Versioning's window is not in play,
and a preview is where a protocol change should be found to be breaking.

## Lifetime and cost

A preview is destroyed when its branch merges or its pull request closes, and
after `ttl:` otherwise. It suspends after `idle:` and wakes on the next
request — a preview nobody has opened in an hour should not be holding a
machine.

`max:` caps how many exist at once. At the cap the oldest idle preview is
suspended rather than destroyed, and `DV-PREVIEW-004` says which: destroying
somebody's environment to make room for another is a surprise, suspending it
is a slow first request.

Destroying takes the database and the storage bucket with it
(`DV-PREVIEW-009`). Nothing about a preview is meant to outlive it.

## What the adapter decides

Whether previews are available at all is the deployment adapter's answer, the
same way traffic weighting is in Backend Release Management. An adapter that
cannot create an isolated environment on demand — a bare-metal target, an edge
runtime with a single fixed deployment — reports `DV-PREVIEW-010` and
`dartvel preview` is unavailable, rather than producing something called a
preview that shares production's database.

## CI

`dartvel preview create --from-pr` is one step in a workflow, and the URL it
prints is what the workflow comments. The preview's own diagnostics — a failed
migration, a missing preview secret, a refused branch — are the step's exit
code, so a preview that could not be built fails the check instead of leaving
a stale link from the last successful run.

## Diagnostics

| Code | Reason | Level |
|---|---|---|
| `DV-PREVIEW-001` | preview created; it is destroyed when the branch merges or its TTL expires | `info` |
| `DV-PREVIEW-002` | a secret required for previews has no value; the preview was not deployed | `error` |
| `DV-PREVIEW-003` | database branching refused: the source holds sensitive fields and no sanitization is declared | `error` |
| `DV-PREVIEW-004` | the concurrent preview cap was reached; the oldest idle preview was suspended | `warning` |
| `DV-PREVIEW-005` | preview suspended after the declared idle interval | `info` |
| `DV-PREVIEW-006` | an outbound notification was captured rather than sent, because this is a preview | `info` |
| `DV-PREVIEW-007` | the preview is declared publicly visible; it is excluded from indexing but not from visitors | `warning` |
| `DV-PREVIEW-008` | a scheduled job did not run: schedules are off in previews unless declared | `info` |
| `DV-PREVIEW-009` | preview destroyed; its database and storage went with it | `info` |
| `DV-PREVIEW-010` | the deployment adapter cannot host previews | `warning` |

## Deliberately absent

- **Production data in a preview.** Covered above, and it is the line the rest
  of this section is arranged around.
- **A preview of a native build on a device.** Stores and signing are real
  constraints, and a command that claimed to install a branch on a phone would
  be doing something else.
- **Sharing production's database "just for reads".** A read of a real
  person's row is the leak; the write was never the only risk.
- **Previews of a preview.** A branch gets one environment. Stacking them is a
  cost story with no reviewer asking for it.

---

# CLI

Stability: `Contract` · Status: `Shipped`

Dartvel should feel like a single fast toolkit, not a bag of unrelated tools.
Bun is a useful benchmark here: runtime, package/task runner, shell, test
runner, and bundler are discoverable through one executable.

Project

```bash
dartvel new
dartvel init
dartvel doctor
# etc.
```

Development

```bash
dartvel dev          # aliases: run, start
```

`dartvel dev` is the whole loop. It watches the configured sources and does
only what a change needs:

| Changed | What happens |
| --- | --- |
| A page or widget | Regenerate, then Flutter's own hot reload |
| A backend function | Regenerate, restart the backend, reload the app — the generated client changed with it |
| Rust | Rebuild the native runtime and restart the backend; no Dart changed, so the app is left alone |
| An env file | Regenerate, restart the backend, reload the app |

Hot reload and hot restart are Flutter's: `r` and `R` reach the running
`flutter run`. Nothing is rebuilt to show a changed widget.

Unchanged content costs nothing. Each watched path is digested, so a
touched-but-identical file does no work — editors save on focus loss and build
tools stamp mtimes, and acting on the event rather than the content would
restart a backend for a stray save.

There is no separate `dartvel watch` or `dartvel hotreload`. The second name in
particular was wrong: it never asked Flutter to reload anything, so the command
that sounded like it handled reloading was the one that did not.

Database

```bash
dartvel db migrate
dartvel db migrate --plan                        # classification per change
dartvel db migrate --dry-run --against snapshot  # rehearse on production shape
dartvel db push
dartvel db pull
dartvel db seed
```

Generate

```bash
dartvel generate page
dartvel generate model
dartvel generate backend-function
dartvel generate form
```

Build

```bash
dartvel build
```

Deploy

```bash
dartvel deploy
dartvel deploy lambda
dartvel deploy edge
dartvel deploy --plan
dartvel deploy rollback
dartvel compatibility-check --against production
dartvel preview create --from-pr 412
dartvel preview list
dartvel preview open
dartvel preview logs --follow
dartvel preview mail
dartvel preview destroy
dartvel privacy check
dartvel privacy export --subject user:1042
dartvel privacy erase --subject user:1042 --reason "DSAR 2026-114"
dartvel privacy retention --plan
dartvel meters list
dartvel meters usage --tenant acme --period current
dartvel meters reconcile --period 2026-08
```

Flags

```bash
dartvel flags list
dartvel flags status newCheckout
dartvel flags set newCheckout --on --environment production
dartvel flags rollout newCheckout --percentage 25 --by user
dartvel flags off newCheckout
dartvel flags prune
```

Observability

```bash
dartvel logs
dartvel traces
dartvel metrics
dartvel crashes list --release 1.4.0
dartvel crashes show <group>
dartvel crashes symbols upload
dartvel crashes health --release 1.4.0 --by cohort
```

AI

```bash
dartvel ai context
dartvel ai doctor
dartvel ai generate
```

## Shell and Task Runner

Dartvel should provide a cross-platform shell/task surface inspired by Bun's
`Bun.$`, but typed for Dart and safe by default.

```dart
final result = await DV.$('git status --short');
final files = await DV.$('ls **/*.dart').text();
final safe = await const DVShell().runCommand(
  DVShellCommand('git')
      .arg('status')
      .arg('--short')
      .env('CI', 'true'),
);
```

```bash
dartvel task clean
dartvel task build:web
dartvel sh "flutter doctor"
dartvel sh "dart list.dart *.dart | dart filter.dart > report.txt 2> errors.txt"
```

Tasks can live in `pubspec.yaml`, `.dartvel.sh`, or `.dartvel.dart`.

```yaml
dartvel:
  tasks:
    build:web: flutter build web
```

```bash
# .dartvel.sh
task clean: flutter clean
build:web: flutter build web
```

```dart
// .dartvel.dart
// task check: dart test
void main(List<String> args) {}
```

Requirements:
- cross-platform on Windows, Linux, and macOS
- safe argument escaping by default
- typed stdout/stderr/exit-code result
- glob support
- environment variable helpers
- pipes and redirection
- script files such as `.dartvel.sh` or `.dartvel.dart`
- no shell injection when interpolating values
- works in CI and generated release scripts

## Build and Bundle Tooling

Dartvel should own the full build orchestration:
- route/client generation
- backend generation
- Flutter build
- Rust runtime build
- native binding generation
- web assets and PWA generation
- single-command production bundles where target platforms allow it
- build graph caching
- affected-file incremental rebuilds

`dartvel build` should include `dartvel routes` automatically. Users should not
need to remember separate generation commands for normal workflows.

---

# Package Structure

```dart
package:dartvel/dartvel.dart

package:dartvel/dartvel_core.dart
package:dartvel/dartvel_ui.dart
package:dartvel/dartvel_backend.dart
package:dartvel/dartvel_database.dart
package:dartvel/dartvel_auth.dart
package:dartvel/dartvel_ai.dart
package:dartvel/dartvel_platform.dart
package:dartvel/dartvel_storage.dart
package:dartvel/dartvel_cli.dart
package:dartvel/dartvel_observability.dart
package:dartvel/dartvel_rust_bindings.dart
```

All Dartvel code is valid on all platforms. Native integrations must use FFI/ffigen or JNI/jnigen bindings; unsupported platform targets fail during validation or are excluded from the generated artifact rather than silently ignoring work.

Dartvel also supports rust bindings for writing rust code in dart using constructs
e.g

```dart
var a = DV.Rust.Int(1);
var b = DV.Rust.Int(2);
var c = a + b;
```

Automatically handles FFI on native native platforms and WASM on web

---


# Home Widgets

Stability: `Draft` · Status: `Partial`

Allows building home-screen and lock-screen widgets on supported platforms,
such as Jetpack Glance or Remote Compose on Android, using `@DVHomeWidget` on
any widget, whether Flutter-native, `DVClassWidget`, or `DVFunctionalWidget`.
Unsupported targets are excluded from the compiled binary/artifact or fail
validation based on project configuration.

`DVClassWidget` is the class form of a Dartvel widget — `abstract class
DVClassWidget extends DartvelPage` — for a widget that wants a class rather
than an annotated function. It carries the same shell properties a page does,
and the generators recognise it wherever they recognise an `@DVPage` function,
so a home widget may be written either way.

```dart
@DVHomeWidget()
@DVFunctionalWidget()
Widget _stepCounterWidget(BuildContext context) =>
    DVBox.list([DVText('Steps'), DVText('${DV.global<StepCounter>().today}')]);
```

Home widgets act like `DVPage` and support the same shell properties. They can
launch and navigate to pages within the app, and a page can navigate back to the
widget. Dartvel generates a page that centers the widget content.

Shares widget tree and state with the parent app

---

# CSRF Protection

Stability: `Contract` · Status: `Shipped`

In:
- Backend functions
- Forms
- Model queries
- DB queries
- Model sync events


---


# The Golden Path

Dartvel provides one clearly recommended path from project creation to
production. Advanced customization is always available, but the default
experience is:

```text
Create
→ Model
→ Page
→ Function
→ Generate
→ Run
→ Test
→ Build
→ Deploy
→ Observe
→ Upgrade
```

## Create the project

```bash
dartvel new my_app
cd my_app
dartvel dev
```

`dartvel new` scaffolds the default project structure (`lib/pages`,
`lib/models`, `lib/backend`, `lib/components`, `lib/styles`, `lib/services`,
`main.dart`, `pubspec.yaml`).

`dartvel dev` starts the complete local Dartvel environment: the Flutter
application, the Dartvel backend, the code generator, analyzer integration, the
zero-config SQLite database, the model sync runtime, the cron scheduler, the
storage emulator, notification preview, Dartvel Studio, and the observability
collector.

```text
Dartvel is ready

App:        http://localhost:3000
Backend:    http://localhost:3001
Studio:     http://localhost:3002
Database:   Connected
Model sync: Running
Cron:       Running
Generator:  Watching
```

There is no `DV.Realtime` runtime; model sync is generated from models,
signals, and queues.

## Define a model

Annotated models are private generation inputs (`_`-prefixed) and generate the
public class.

```dart
@DVModel()
class _User(
  final String name,
  final String email,
  final DVImage? avatar,
  final String? biography,
);
```

Dartvel generates the schema, migration, CRUD, validation, serialization,
queries, forms, list, table, page, REST/RPC/GraphQL/OpenAPI surfaces, model
sync support, and admin representation for the public `User` type.

## Create a page

```dart
@DVPage()
Widget _usersPage(BuildContext context) => User.List();
```

File location determines the route (`lib/pages/users.dart` → `/users`).

## Add backend behavior

```dart
@DVBackendFunction()
Future<User> _createUser(String name, String email) async =>
    User.create(name: name, email: email);
```

The function is called identically from frontend or backend code:

```dart
final user = await createUser(name, email);
```

## Generate, migrate, test, build, deploy, observe, upgrade

```bash
dartvel generate
dartvel db migrate
dartvel test          # or: e2e | golden | native | accessibility | release
dartvel build android # see Build targets
dartvel deploy        # or: cloud-run | lambda | container | fly | railway
dartvel logs          # dartvel metrics | dartvel traces | dartvel studio
dartvel upgrade --plan && dartvel compatibility-check && dartvel upgrade
```

During development, generation happens incrementally through `dartvel dev`.

The golden path is the recommended path, not the only path. Every layer retains
escape hatches (see Pluggability).

---

# Lifecycle Signals

Stability: `Contract` · Status: `Partial`

Dartvel does not introduce a `DVService` lifecycle abstraction. Lifecycle state
is modelled as generated, read-only **enum signals** — the same signal system
described under State. Their conceptual type is `DVSignal<TEnum>`: a read-only
reactive value that can be read directly, observed, exposed through `DV.global`,
consumed by modules and generated diagnostics, and displayed in Dartvel Studio.
The generator owns the transitions; application code observes rather than
assigns.

## Application lifecycle

```dart
enum DVAppLifecycle {
  uninitialized, initializing, booting, ready, backgrounded,
  suspended, resuming, shuttingDown, stopped, failed,
}
```

```dart
DV.lifecycle.app.listen((state) async {
  if (state == DVAppLifecycle.booting) {
    DV.global<PaymentGateway>(
      PaystackGateway(secret: DV.Secrets.get('PAYSTACK_SECRET')),
    );
  }
});
```

## Page lifecycle

```dart
enum DVPageLifecycle {
  created, resolving, loading, ready, entering, active,
  inactive, leaving, disposing, disposed, failed,
}

context.lifecycle.page.listen((state) {
  if (state == DVPageLifecycle.active) {
    DV.log('page_view');
  }
});
```

## Module, request, transaction, and build lifecycles

```dart
enum DVModuleLifecycle {
  discovered, resolving, validating, loading, loaded, mounting,
  mounted, active, suspended, unmounting, unloaded, failed,
}

enum DVRequestLifecycle {
  received, contextCreated, decoding, tenantResolving, tenantResolved,
  authenticating, authenticated, securityChecking, rateLimitChecking,
  validating, authorized, transactionStarting, executing, preparingResponse,
  committing, encoding, completed, cancelled, rollingBack, failed,
}

enum DVTransactionLifecycle {
  created, active, preparing, committing, committed, rollingBack,
  rolledBack, compensating, compensated, cancelled, failed,
}

enum DVBuildLifecycle {
  idle, scanning, analyzing, generating, validating, compiling,
  bundling, completed, failed,
}
```

Access points:

```dart
DV.lifecycle.app
DV.lifecycle.build
DV.Modules.store.lifecycle
context.lifecycle.page          // in a page
context.lifecycle.request       // in a backend function
context.lifecycle.transaction   // in a transaction
```

The CLI, Studio, analyzer, and external tools observe the same canonical state.

---

# Backend Function Request Lifecycle

Stability: `Contract` · Status: `Shipped`

Every `@DVBackendFunction` runs through a generated request lifecycle. When the
first parameter is a `DVContext`, it is injected automatically and is never
treated as a client-supplied argument.

```dart
@DVBackendFunction()
Future<User> _getUser(DVContext context, String id) async => User.find(id);
```

Generated stages (each updates `context.lifecycle.request`):

```text
1. Request received
2. Trace and correlation identifiers created
3. Transport envelope decoded (form-data + binary flat-buffers)
4. DVContext created
5. Environment resolved
6. Tenant resolved
7. Authentication resolved
8. Origin, CORS, and CSRF rules evaluated
9. Rate and quota limits evaluated
10. Parameters decoded
11. Parameters validated
12. Authorization policies evaluated
13. Transaction opened where required
14. Function executed
15. Reversible operations recorded
16. Deferred operations prepared
17. Transaction committed
18. After-commit operations dispatched
19. Response encoded
20. Metrics, logs, and traces finalized
21. Response returned
```

Most functions never observe the lifecycle manually; it primarily supports
plugins, observability, security, debugging, Studio, and advanced behavior.

## Function configuration

```dart
@DVBackendFunction(
  transaction: DVTransactionMode.auto,
  authentication: DVAuthentication.required,
  rateLimit: '100/hour',
)
Future<Order> _createOrder(DVContext context, OrderInput input) async =>
    Order.create(input);
```

## Raw HTTP paths

Raw HTTP exposure stays part of `@DVBackendFunction`; there is no separate
`@DVRawRoute` primitive.

```dart
@DVBackendFunction(rawPath: '/payments/webhook')
Future<void> _paymentWebhook(DVContext context) async =>
    Payments.acceptWebhook(context);

@DVBackendFunction(rawPathSuffix: '/public')
Future<Product> _getProduct(String id) async => Product.find(id);
```

`rawPath` exposes an exact custom path. `rawPathSuffix` keeps the generated path
and appends a suffix (`/dartvel/functions/products/getProduct/public`). The two
are mutually exclusive.

---

# Modules

Stability: `Contract` · Status: `Partial`

A Dartvel module is a **complete, composable Dartvel application boundary**. A
module may contain pages, models, backend functions, components, styles, assets,
cron functions, configuration, storage namespaces, database migrations,
permissions, SEO/PWA configuration, AI tools, observability, and other modules.

A module can be run, built, and deployed independently; embedded into another
Dartvel application; mounted as a micro-site or micro-app; used as a
backend-only capability; distributed as a Dart package; or maintained inside a
monorepo. A module is itself a valid Dartvel project:

```bash
cd modules/store
dartvel dev            # runs the store standalone
```

## Module declaration

In the module's `pubspec.yaml`:

```yaml
dartvel:
  module:
    id: store
    name: Store
    version: 1.0.0
    routes:
      base: /
    exports:
      pages: true
      functions: true
      models: [Product, Cart, Order]
    auth:
      mode: inherited
    theme:
      mode: inherited
```

## Parent mounting

In the parent application's `pubspec.yaml`:

```yaml
dartvel:
  modules:
    store:
      source:
        path: modules/store
      mount: /store
      deployment: embedded   # embedded | split-backend | federated | backend-only
      auth: inherit
      theme: inherit
      globals: scoped
```

Route bases are rewritten automatically: the standalone `/products/:id` becomes
`/store/products/:id`. The parent receives generated, typed access:

```dart
DV.Modules.store                 // namespace
DV.Modules.store.lifecycle       // DVSignal<DVModuleLifecycle>
DV.Modules.store.config
DV.Modules.store.manifest
DV.Modules.store.assets.logo     // asset paths rewritten on mount

.navigateToPage(.store.home)
.navigateToPage(.store.product(product.id))
```

## Deployment modes

- **embedded** — compiled into the parent artifact while keeping its namespace.
  Best for feature modules, large monoliths, monorepos, and closely coupled
  product areas.
- **split-backend** — UI ships in the parent; module backend functions deploy as
  a separate service, and generated clients call it automatically. Best for
  independently scaled domains and gradual service migration.
- **federated** — built and deployed as an independent Dartvel application,
  mounted into the parent's route/navigation system. The module publishes a
  signed manifest (identifier, version, routes, capabilities, assets, auth/theme
  modes, public functions, public signals, compatibility requirements,
  deployment location, integrity signature); the parent verifies it before
  integration. Best for micro-sites, micro-frontends, partner and white-label
  sections.
- **backend-only** — contributes models, backend functions, cron functions, AI
  tools, storage behavior, and migrations, but no pages.

A standalone module runs as its own application but may still export typed
contracts to other Dartvel applications.

## Modules as micro-sites and micro-apps

A micro-site or micro-app is just a module with its own route tree, page index,
SEO defaults, sitemap entries, theme, assets, models, backend, deployment
policy, and PWA configuration:

```yaml
dartvel:
  modules:
    documentation:
      source: { path: modules/documentation }
      mount: /docs
      deployment: federated
      theme: override
      auth: public
      sitemap: include
```

The same module responds at `/products` standalone and `/store/products`
mounted; generated navigation always uses the correct route base, so module code
must not hard-code its mount point.

Per-module modes:

- **shell**: `inherit` | `extend` | `override` | `none`
- **auth**: `inherit` (uses the parent's `DV.Auth`) | `independent` |
  `federated` (securely exchanged identity) | `public`
- **theme**: `inherit` | `extend` | `override` | `isolated`
- **data**: `shared` | `schema-isolated` | `database-isolated` | `remote`

A parent cannot mount a module on a target that cannot satisfy the module's
required capabilities unless a configured fallback exists (see Platform
Compatibility).

## Module globals

Modules receive scoped `DV.global` registries — Dartvel does not add a separate
DI/service-container primitive. Globals are isolated by default between
independently deployed modules; sharing is deliberate.

```dart
DV.global<Cart>(Cart(), 'store');
final cart = DV.global<Cart>(null, 'store');
final same = DV.Modules.store.global<Cart>();  // generated convenience
```

Inside the module the namespace is inferred, so `DV.global<Cart>()` resolves to
the module registry. Exported and inherited globals are declared explicitly:

```yaml
dartvel:
  module:
    globals:
      export: [cart, checkoutState]

dartvel:
  modules:
    store:
      globals:
        inherit: [auth, theme, currentTenant]
```

---

# Generated Model Pages

Stability: `Contract` · Status: `Partial`

Every model generates a semantic page for one record: `User.Page()`,
`Post.Page()`, `Product.Page()`. Default composition inspects the model's public
fields in this order:

```text
1. Featured image  2. Title  3. Main text content  4. Remaining text
5. Remaining media  6. Structured fields  7. Relationships  8. Generated actions
```

- **Featured image** — the first public image/media field, else the page begins
  with the title or primary text.
- **Web favicon** — a resized, compressed, content-hashed derivative of the
  featured image, cached, included in SSG output, and generated on demand for
  web-server rendering. Fallbacks: configured model favicon → module favicon →
  application favicon.
- **Main content** — the largest text block, chosen from long-text metadata,
  declaration order, schema type, display priority, and actual non-empty length.
- Sensitive and hidden fields are excluded (see Sensitive Model Fields).

Explicit overrides:

```dart
@DVModel.featuredImage() final DVImage cover;
@DVModel.pageTitle()     final String title;
@DVModel.mainContent()   final String body;
@DVModel.pageOrder(3)    final String author;
@DVModel.hideFromPage()  final String internalReference;
@DVModel.model3dField()  final DVFile? asset;
```

Field-scoped model annotations live under the `DVModel` parent, alongside
`@DVModel.sensitiveField()`, `@DVModel.searchableField()` and
`@DVModel.model3dField()`. There are no standalone `@DVFeaturedImage`,
`@DVPageTitle`, `@DVMainContent`, `@DVPageOrder` or `@DVHideFromPage`
annotations.

A `@DVModel.model3dField()` renders through the generated viewer where the
field appears, and contributes its poster to the page's Open Graph image; see
[3D Scenes](#3d-scenes).

## Page data modes

```dart
enum DVModelPageDataMode {
  auto, sync, async, reactive, cached, staleWhileRevalidate,
}
```

`auto` (default) picks rendering from the input: an existing model renders
synchronously; an id/route parameter triggers an async query; a signal renders
reactively; a stream renders streaming; a cached record renders immediately then
refreshes.

```dart
User.Page(user)
User.Page.async(getUser(id))
User.Page.signal(user.signal(context))
User.Page.fromId(id)
User.Page.fromId(id, dataMode: DVModelPageDataMode.async)   // per-page override
```

```dart
@DVModel(pageDataMode: DVModelPageDataMode.staleWhileRevalidate)
class _User(...)
```

Model-page SEO derives from model data (title → page title, summary/first
excerpt → meta description, featured image → OG image, type/relationships →
structured data, canonical route → canonical URL); all values can be overridden.

---

# Reversible Transactions

Stability: `Contract` · Status: `Shipped`

The canonical transaction API is:

```dart
final order = await DV.transaction((DVContext context) async {
  final order = await Order.create(customer: customer, total: cart.total);
  await Inventory.reserve(cart.items);
  await DV.FileStorage.put('orders/${order.id}/receipt.json', receiptBytes);
  return order;
});
```

Operations executed through Dartvel primitives participate automatically in the
active transaction. Dartvel can reverse model create/update/delete, relationship
changes, database writes, file creation/replacement, cache changes,
tenant-scoped mutations, and generated model-sync mutations by recording the
previous state or inverse operation.

- **Database-local** — one transactional database uses its native
  begin/execute/commit, rollback on failure.
- **Distributed** — spanning systems uses a compensation log: execute → record
  inverse → continue; on failure reverse completed operations and run
  compensation functions.

`context.lifecycle.transaction` exposes a `DVSignal<DVTransactionLifecycle>`.
Nested `DV.transaction` calls join the active transaction by default; an
isolated transaction can be requested where supported.

## Irreversible and external effects

Truly irreversible effects (email, SMS, webhooks, settled payments, external API
mutations) run after commit; external effects with an inverse register
compensation:

```dart
await DV.transaction((context) async {
  final order = await Order.create(...);
  context.afterCommit(() async {
    await DV.Notifications.send(customer.id, OrderConfirmed(order));
  });
});

await DV.transaction((context) async {
  final payment = await gateway.charge(amount);
  context.compensate(() async => gateway.refund(payment.id));
  await Order.create(paymentId: payment.id);
});
```

---

# Background and Durable Work

Stability: `Contract` · Status: `Shipped`

Signals and cron functions remain the primary reactive and scheduled
primitives, and `@DVJob`/`DV.Jobs`/`DVQueues` (see Queues, Jobs, and Signals)
remain the durable background-work layer. To keep common cases ergonomic, a
backend function can opt into background/durable execution, which the generator
compiles down onto the existing jobs/queues system — it does not introduce a
parallel primitive:

```dart
@DVBackendFunction(background: true, durable: true, retries: 5)
Future<void> _generateReport(String reportId) async =>
    Reports.generate(reportId);
```

Workflows are ordinary backend functions composed from other typed backend
functions inside a transaction; durable state is stored in generated models and
resumed by backend cron or durable function execution:

```dart
@DVBackendFunction(durable: true)
Future<Order> _fulfilOrder(Order order) async => fulfilOrderWorkflow(order);

Future<Order> fulfilOrderWorkflow(Order order) async =>
    DV.transaction((context) async {
      await chargeCustomer(order);
      await reserveInventory(order);
      await arrangeDelivery(order);
      return order;
    });
```

This keeps the primitive set small: signals, backend functions, transactions,
cron functions, and models.

---

# Sensitive Model Fields

Stability: `Contract` · Status: `Partial`

`@DVModel.sensitiveField()` marks a model field as sensitive. By default such a
field is redacted from logs; excluded from AI context, traces, analytics, public
serialization, search indexing, and Open Graph/structured data; hidden from
generated model pages, tables, and admin views; protected from accidental debug
printing; subject to stricter authorization; and audited when accessed.

```dart
@DVModel()
class _User(
  final String name,
  @DVModel.sensitiveField() final String nationalId,
  @DVModel.sensitiveField(encrypted: true) final String recoveryToken,
  @DVModel.sensitiveField(showInForms: true, showInAdmin: false)
  final String recoveryEmail,
);
```

`encrypted: true` seals the value with AES-256-GCM before it is written and
opens it when the row is read. The keyring is `DARTVEL_FIELD_KEYS`, written
newest first as `<id>:<base64 32-byte key>`. It is a backend-scoped secret and
resolves through [Secrets and Environments](#secrets-and-environments) like any
other, so a vault or KMS adapter can serve it without generated code learning
where the value came from. The scope is the part that may not move: generated
model code is compiled into the application bundle as well as the server, so a
key reachable from client code would ship to every visitor. Backend scope is
what prevents that, and it is structural rather than advisory — a web build
resolves no backend secret at all. A process with no keyring
raises on the field rather than falling back to plaintext, which also settles
where such a model lives: the server persists it, and a device reading or
writing the same model against its local database gets that refusal instead of
a plaintext column. Rotation is adding
a key at the front and leaving the old one behind it — a stored value records
which key sealed it. Only `String` and `String?` can carry the flag, and not
the field generated lookups use, since a randomized ciphertext never matches a
plaintext in a `WHERE` clause.

Explicit policy authorization is required before sensitive fields are sent to
clients. This extends the existing security scope (authentication,
authorization, CSRF, CORS, origin validation, XSS/injection/SSRF protection,
secure file handling, rate limiting, secrets, encryption, audit logging,
dependency validation, tenant isolation, security headers, CSP, webhook
verification, sensitive-data redaction). CSRF applies to state-changing browser
requests using automatically attached credentials, not to database queries
themselves.

---

# Data Compliance and Lifecycle

Stability: `Draft` · Status: `Designed`

Sensitive Model Fields says which values are sensitive and who may read them.
This says how long they are kept, what happens when somebody asks for a copy,
and what happens when somebody asks to be forgotten — the three questions a
data protection request turns into, and the three no application answers by
having a `delete` button.

None of it works without one declaration, so it comes first.

## The subject path

Erasure and export are walks over the model graph, and a walk needs to know
which rows belong to whom.

```dart
@DVModel(subject: DVSubject.self)
class _User(
  final String email,
  @DVModel.sensitiveField() final String nationalId,
);

@DVModel(subject: #user)
class _Order(
  final User user,
  final Money total,
  @DVModel.retain(years: 7, because: 'tax law')
  final Invoice invoice,
);

@DVModel(subject: #author)
class _Message(
  final User author,
  final Conversation conversation,
  final String body,
);
```

**A model that carries a sensitive field and declares no subject path is a
build error** (`DV-PRIVACY-001`). The alternative is the failure this whole
section exists to prevent: an erasure that runs, reports success, and leaves a
table nobody remembered behind. A declaration the generator can enumerate is
the only thing that makes "everything" checkable, and it is checkable —
`dartvel privacy check` lists every model, its subject path, and its
retention.

Models with no personal data declare nothing. A `Currency` lookup table is not
a compliance question and should not be made to look like one.

## Retention

```dart
@DVModel(retain: DVRetention.days(90))          // then deleted
@DVModel(retain: DVRetention.indefinite)        // deliberately, and it says so
@DVModel(retain: DVRetention.days(30, then: DVRetention.anonymize))
```

Retention is swept by a durable job on the schedule the deployment declares,
and the sweep is resumable and rate-limited like any other backfill — deleting
four million rows in one transaction is how a retention policy takes a
database down.

A model carrying personal data with no declared retention is kept for ever and
`DV-PRIVACY-002` says so at build time. It is a warning rather than an error
because "indefinitely" is a legitimate answer for an account record; it is not
a legitimate answer nobody made.

## Erasure

```dart
final result = await DV.Privacy.erase(subject: user, reason: 'DSAR 2026-114');
```

The walk visits every model whose subject path reaches the subject and applies
what each field declared:

| Declaration | What happens |
| --- | --- |
| default | the row is deleted |
| `@DVModel.sensitiveField(onErase: DVErase.anonymize)` | the field is replaced with a tombstone value; the row stays |
| `@DVModel.retain(years: 7, because: ...)` | the row is kept and its personal fields are anonymized |

**The conflict between erasure and retention is reported, not resolved
silently.** An invoice a tax authority requires for seven years cannot be
deleted because somebody asked, and an erasure that quietly kept it — or
quietly deleted it — is the same bug with two different regulators. The result
names every row kept, the declaration that kept it, and the `because:` string
that was written when somebody decided (`DV-PRIVACY-003`). That string exists
so the answer to "why do you still have my invoice" is in the codebase rather
than in somebody's memory.

Erasure is a durable job with a declared deadline, because the deadline is the
regulation's — thirty days under GDPR, and an erasure still running on day
thirty-one is the breach (`DV-PRIVACY-004`). It reports progress, survives a
restart, and an adapter it could not reach is an error rather than a silent
partial success (`DV-PRIVACY-009`): a subject's rows removed from the database
and left in the search index have not been erased.

The walk covers what the framework owns — the database, File Storage objects
the subject's rows reference, cache entries under the subject's tags, the
analytics store, and crash reports carrying a declared identity. It cannot
cover a third-party sink it does not know about, and that is exactly why an
unreachable adapter is reported instead of assumed clean.

## Backups

A backup is immutable, so nothing can be deleted from it. Pretending otherwise
is the most common false claim in this area.

Erasure writes a **tombstone** — the subject's pseudonymous id and the time —
to a log that is itself backed up. A restore replays the log before the
restored deployment serves anything, so a subject erased in March is erased
again the moment a February backup comes back (`DV-PRIVACY-005`). The backup
still holds the bytes until it ages out of its own retention; what changes is
that no restored system ever serves them.

## Export

```dart
final archive = await DV.Privacy.export(subject: user);
```

The same walk, producing a machine-readable archive — JSON per model plus the
referenced files — which is the portability half of the same right.

A record naming more than one subject exports **the requesting subject's own
contribution and nothing else**. A conversation is the ordinary case: the
person's messages are theirs, the other person's messages are the other
person's, and an export containing both would be a data protection breach
performed in the name of data protection (`DV-PRIVACY-006`).

## Analytics and consent records

Events keyed to the subject are deleted or de-identified with everything else.
Aggregates are not: a funnel count of nine hundred is not personal data and
recomputing every historical aggregate to make it eight hundred and
ninety-nine is not what anybody asked for.

Consent records outlive the erasure, holding the pseudonymous id, what was
asked, what was answered and when — no personal fields (`DV-PRIVACY-010`).
They are the evidence that the consent existed and that the erasure ran, and
evidence destroyed on request stops being evidence.

## The audit trail

Every export and erasure is recorded through Record History, carrying who
asked, who ran it, when, what the walk covered and what was kept. The record
holds the pseudonymous id and no personal field, so it proves the erasure
happened without holding what was erased.

## CLI

```bash
dartvel privacy check                       # every model: subject path, retention
dartvel privacy export --subject user:1042
dartvel privacy erase --subject user:1042 --reason "DSAR 2026-114"
dartvel privacy retention --plan            # what the next sweep would delete
```

`--plan` before a sweep is the same discipline `dartvel deploy --plan` and
`dartvel db migrate --plan` already apply: a deletion nobody previewed is one
nobody can be talked out of.

## Studio

Studio lists open requests, their deadlines and how far each walk has got,
which is what makes a thirty-day clock something a team can see rather than
something a lawyer discovers.

## Diagnostics

| Code | Reason | Level |
|---|---|---|
| `DV-PRIVACY-001` | a model carries a sensitive field and declares no subject path; erasure cannot reach it | `error` |
| `DV-PRIVACY-002` | a model carrying personal data declares no retention; it is kept indefinitely | `warning` |
| `DV-PRIVACY-003` | rows were kept under a declared retention; their personal fields were anonymized | `info` |
| `DV-PRIVACY-004` | an erasure passed its declared deadline | `error` |
| `DV-PRIVACY-005` | a restore replayed the erasure tombstone log | `info` |
| `DV-PRIVACY-006` | an exported record names another subject; only the requesting subject's contribution was included | `info` |
| `DV-PRIVACY-007` | a retention sweep deleted rows | `info` |
| `DV-PRIVACY-008` | a retention sweep would delete rows a longer retention holds; the longer one won | `warning` |
| `DV-PRIVACY-009` | an erasure could not reach a configured adapter; the subject's data there was not removed | `error` |
| `DV-PRIVACY-010` | a consent record was retained after erasure as evidence, carrying no personal fields | `info` |

## Deliberately absent

- **Legal advice.** Dartvel makes retention, erasure and export declarable,
  enumerable and checkable. Which regulation applies, and what it requires, is
  not a framework's answer, and a built-in "GDPR mode" would be a claim nobody
  can stand behind.
- **Deleting from backups.** See above. A tombstone replayed on restore is the
  honest version; a command that claims to reach into an immutable archive is
  not.
- **Data residency and multi-region placement.** Backend Release Management
  leaves the multi-region backplane out for the same reason, and pinning rows
  to a region is that question rather than this one.
- **Erasure of another controller's copy.** An export tells the subject where
  their data went; a framework cannot delete from a third party that never
  agreed to be deleted from.
- **A second audit log.** Record History already answers who did what.

---

# Static Web Generation

Stability: `Draft` · Status: `Shipped`

`dartvel build web` does not ship a single shared `index.html`. Dartvel
generates a route-specific HTML document for every known static page:

```text
build/web/
  index.html
  users/index.html
  about/index.html
  products/index.html
  products/product-1/index.html
  sitemap.xml
  robots.txt
  assets/
  flutter/
```

Every generated page contains a route-specific title, meta description,
canonical URL, Open Graph/social metadata, structured data, a route-specific
favicon, the Flutter bootstrap/loader, preload hints, and a raw-text fallback:

```html
<noscript>Raw semantic text representation of the page.</noscript>
```

The raw text is generated from `DVText`, model-page fields, SEO descriptions,
static page content, and accessible semantic labels. When scripting is enabled
and Flutter is supported, the Flutter application takes over.

A page carrying a `DVBox.scene` viewport contributes its **poster** — the
build-time render described in [3D Scenes](#3d-scenes) — to the generated
page, to the `<noscript>` fallback, and to the Open Graph image of a model
page whose 3D field it is. The degraded path and the crawler path are the same
true image, so neither is a placeholder nobody checks.

## Dynamic routes during SSG

Static routes are always generated. Parameterized routes require a known list of
values:

```dart
@DVModel(generatePublicPages: true)
class _Product(...)
```

That renders one page per published record, which is the common case and needs
nothing else. When the set to generate is a subset, a particular order, or
drawn from somewhere the model does not know about, name a resolver instead:

```dart
@DVModel(publicPathsResolver: productPaths)
class _Product(...)

Future<List<String>> productPaths() async {
  return Product.public().select((product) => product.slug);
}
```

The route is the model's own either way, so it is never written out as a
string — a route repeated in an annotation drifts the moment the page file
moves, which is what file-based routing exists to prevent.

For routes without generated static instances, Dartvel produces a configured
fallback document, a client-rendered fallback, a 404, or a redirect to the
web-server deployment.

## Sitemap

Dartvel has a complete generated route index, so it emits `sitemap.xml`
automatically (static pages, generated model pages, module pages, exported
federated micro-site pages, canonical URLs, last-modified, priorities, change
frequencies, alternate locale URLs). Sensitive, private, and authenticated
routes are excluded by default.

```yaml
dartvel:
  seo:
    sitemap:
      enabled: true
      exclude: [/admin/**, /account/**]
      defaults: { priority: 0.5, changeFrequency: weekly }
```

```dart
@DVPage(
  sitemap: DVPageSitemap(
    priority: 0.8,
    changeFrequency: DVSitemapChangeFrequency.daily,
  ),
)
Widget _productsPage(BuildContext context) => Product.List();
```

## Deep-link verification files

Android App Links and iOS Universal Links are only links until the platform
verifies them, and verification is two JSON documents served from the site the
links point at. Both are functions of things Dartvel already holds — the route
index and the application identifiers, both nodes in the project graph — so
`dartvel build web` writes them:

```text
build/web/
  .well-known/assetlinks.json
  .well-known/apple-app-site-association
```

```yaml
dartvel:
  deepLinks:
    domains: [example.com, www.example.com]
    android:
      package: com.example.app
      fingerprints: playAppSigning      # or an explicit SHA-256 list
    ios:
      appId: ABCDE12345.com.example.app
    exclude: [/admin/**, /account/**]
```

The path patterns come from the route index and exclude authenticated and
sensitive routes by the same rule the sitemap uses, so a link file cannot claim
a route the application will refuse to open. A URL-first framework that made
people hand-write this JSON would be asking them to keep a second copy of their
routing table in a file no compiler reads.

`dartvel doctor --target android,ios` checks the deployed reality rather than
the generated file: both documents reachable over HTTPS at the exact path, no
redirect, served as JSON, listing this application, and covering the routes it
claims. It also compares the Android fingerprints with the certificate the
build is actually signed by — the usual cause of links that work in debug and
open a browser in production is a file carrying the local keystore's
fingerprint while the store serves a Play-signed binary, so `playAppSigning`
reads the configured upload and signing certificates rather than assuming the
one on the machine.

| Code | Reason | Level |
|---|---|---|
| `DV-LINKS-001` | deep-link domains declared with no application identifier for a target | build `error` |
| `DV-LINKS-002` | verification file unreachable, redirected, or not served as JSON | doctor `error` |
| `DV-LINKS-003` | fingerprint in the served file does not match the signing certificate | doctor `error` |
| `DV-LINKS-004` | a route the application handles is not covered by the served patterns | doctor `warning` |

---

# Web Server Rendering

Stability: `Draft` · Status: `Partial`

`dartvel build web-server` creates a Dartvel web server that generates
route-specific HTML on demand:

```text
Request received → Route resolved → Page data resolved →
Auth and visibility checked → SEO + structured data generated →
Favicon selected → Raw semantic text generated → Flutter bootstrap embedded →
HTML response returned
```

`GET /products/123` returns HTML containing the SEO, featured image, favicon,
and text content for product `123`; the Flutter client then activates when
supported. Async page data may be awaited, cached, streamed, rendered
stale-while-revalidate, or deferred to the client.

```yaml
dartvel:
  web:
    server:
      pageDataMode: stale-while-revalidate
      cache: redis
      streaming: true
```

`streaming: true` sends the head as its own write, after the page data has
resolved. `streaming: shell` sends the shell's head before the data: base,
charset, every preload, the splash and a preload for each script the body
loads, so the browser downloads the application and the page's code while the
server queries. The title and the rest of the head the data writes follow when
the data does, then the body. The cost is the status code: 200 is on the wire
before the data says whether the record exists, so a missing, hidden or
unauthorized record is a page marked `noindex` with none of the data in it (a
soft 404), and a resolver that throws gets the route's own page, marked the
same way. A route the router guards is never sent early; it waits for the data
and answers with its real status, exactly as with `true`.

Mounted modules contribute their routes to static generation, server rendering,
sitemap/SEO generation, and asset generation. A federated micro-site may serve
its own HTML while still appearing in the parent route index and sitemap.

---

# Embedded, Television, and Extension Build Targets

Stability: `Contract` · Status: `Partial`

Beyond mobile, web, and desktop, Dartvel supports dedicated builds for webOS,
Tizen, Sony's Flutter Embedded Linux ecosystem, and VS Code extensions.

```bash
dartvel build webos
dartvel build tizen
dartvel build sony-elinux
dartvel build sony-elinux-iso
dartvel build sony-elinux-img
dartvel build vscode
```

Each target is driven by the platform's dedicated Flutter embedder or host
extension generator rather than plain `flutter build`:

- **webOS** → `flutter-webos` (LG)
- **Tizen** → `flutter-tizen` (Samsung)
- **Sony eLinux** → `flutter-elinux` (Sony)
- **VS Code** → `flutter_vscode` extension generator and webview helper

Dartvel shells out to these embedders, adapting their invocation behind the
stable `dartvel build` surface. When an embedder is not installed, the target is
skipped with a clear message instead of failing the whole build, and
`dartvel doctor --target <t>` validates that the embedder is present.

## VS Code Extension

`dartvel build vscode` packages a Dartvel app as a VS Code extension using the
Dartvel fork of `flutter_vscode`. This target is not a raw `flutter build web`.
It follows the extension-host flow:

1. Generate Dartvel routes/client/backend artifacts.
2. Run `dart run build_runner build --delete-conflicting-outputs` so annotated
   VS Code controller APIs produce current bindings. These are
   `flutter_vscode`'s builders; Dartvel's own generation is step 1.
3. Run `dart run flutter_vscode:generate_vscode_extension` so the VS Code
   extension scaffold, webview helper wiring, and typed controller bindings are
   present.
4. Run `flutter pub get`.
5. Run `npm install`.
6. Run `npm run compile` to build the TypeScript extension host package.

Application code uses annotated Dart controller APIs for VS Code commands and
messages, initializes `VSCodeWebViewHelper` in the Flutter webview entry point,
and imports Dartvel through the generated `dartvel_client/dartvel_client.dart`
barrel. Dartvel keeps the fork at
`https://github.com/Danroyal001/dartvel_vscode` and tracks upstream
`SlowGen/flutter_vscode`.

The VS Code target requires Node.js/npm, a project dependency on
`flutter_vscode`, and `build_runner` in `dev_dependencies` so controller
bindings are generated before the extension scaffold compiles. `dartvel build
vscode` validates those dependencies before running the scaffold generator, and
`dartvel doctor --target vscode` reports whether npm is on PATH. After
`npm run compile`, Dartvel validates that a
compiled extension-host JavaScript file exists under `out/` or `dist/`, that
`build/web/flutter_bootstrap.js` exists, and that `build/web/assets/` exists.
Those artifacts must be fresh from the current build invocation, so stale
output from a previous run cannot make the build pass. Verification evidence is
recorded in `docs/build-targets.md`; do not infer future compatibility from
command wiring alone.

## webOS

`dartvel build webos` packages the application for a configured webOS target
(webOS OSE, compatible webOS televisions, and embedded webOS devices), covering
remote-control navigation, television-safe areas, lifecycle integration, media
controls, and fullscreen/kiosk modes.

```yaml
dartvel:
  targets:
    webos:
      profile: television
      architecture: arm64
      fullscreen: true
      input: { remoteControl: true, keyboard: true }
      permissions: [media, network, storage]
```

```text
build/webos/release/
  application.ipk
  manifest.json
  checksums.json
```

## Tizen

`dartvel build tizen` packages the application for the configured Tizen profile
(`television`, `mobile`, `wearable`, `embedded`). Dartvel generates Tizen
manifests, privilege declarations, application identifiers, signing
configuration, remote-control mappings, lifecycle bindings, and native or web
runtime packaging.

```yaml
dartvel:
  targets:
    tizen:
      profile: television
      architecture: arm64
      certificate: environment:TIZEN_CERTIFICATE
      input: { remoteControl: true }
      permissions: [internet, media, filesystem]
```

Output is `build/tizen/release/application.wgt` or `.tpk` depending on the
selected runtime profile.

## Sony Embedded Linux

Sony's Flutter Embedded Linux tooling builds application bundles for embedded
Linux architectures. Dartvel provides three related targets.

**Application bundle** — `dartvel build sony-elinux` builds the app and the Sony
eLinux runner without building an OS image.

```yaml
dartvel:
  targets:
    sony-elinux:
      architecture: arm64        # arm | arm64 | x64
      releaseMode: release
      renderer: egl
      displayBackend: drm
      fullscreen: true
      kiosk: true
      autostart: true
```

```text
build/sony-elinux/arm64/release/bundle/
  dartvel_app  lib/  data/  assets/  manifest.json
```

**Bootable ISO** — `dartvel build sony-elinux-iso` assembles a bootable ISO
(minimal Linux OS, bootloader, kernel, system libraries, Flutter eLinux engine,
Dartvel app, native bindings, device/network configuration, autostart, recovery
and diagnostics) for VMs, development hardware, installation media, and
read-only kiosk installs.

```text
build/sony-elinux/arm64/release/
  dartvel-app.iso  dartvel-app.iso.sha256  build-manifest.json
```

**Flashable disk image** — `dartvel build sony-elinux-img` builds a raw disk
image for SD cards, eMMC, USB drives, and development boards.

```yaml
dartvel:
  targets:
    sony-elinux:
      architecture: arm64
      board: generic-arm64
      image:
        size: 8GB
        filesystem: ext4
        compression: xz
        partitions: { boot: 512MB, root: 3GB, data: remaining }
      application: { autostart: true, restartOnFailure: true, kiosk: true }
```

```text
build/sony-elinux/arm64/release/
  dartvel-app.img  dartvel-app.img.xz  dartvel-app.img.sha256
  partitions.json  build-manifest.json
```

## Build-format relationship

The dedicated commands are equivalent to selecting a format explicitly; the
named commands remain first-class because they are easier to discover and
automate.

```bash
dartvel build sony-elinux            # == dartvel build sony-elinux --format bundle
dartvel build sony-elinux-iso        # == dartvel build sony-elinux --format iso
dartvel build sony-elinux-img        # == dartvel build sony-elinux --format img
```

## Device profiles

Reusable embedded-device profiles capture architecture, board, toolchain,
kernel, display backend, GPU renderer, resolution, orientation, touch/remote
support, network defaults, filesystem, partitions, native capabilities, update
behavior, and startup behavior.

```yaml
dartvel:
  deviceProfiles:
    lobby-display:
      platform: sony-elinux
      architecture: arm64
      display: { width: 1920, height: 1080, orientation: landscape }
      kiosk: true
      input: { touch: true, keyboard: false }
```

```bash
dartvel build sony-elinux-img --device-profile lobby-display
```

## Build validation

Before building, Dartvel validates toolchain availability, architecture and
engine compatibility, platform permissions, native bindings, required system
libraries, signing credentials, device-profile compatibility, and disk-image and
bootloader configuration. Failures are typed and explained:

```text
DV-ELINUX-004
The selected application requires Bluetooth, but the sony-elinux device profile
does not provide a Bluetooth adapter or fallback implementation.
```

Validation is also available through
`dartvel doctor --target webos|tizen|sony-elinux|vscode`.

## Updated build target list

```bash
# Mobile
dartvel build android
dartvel build ios
# Web
dartvel build web
dartvel build web-server
# Desktop
dartvel build windows
dartvel build linux
dartvel build macos
# Television, embedded, and extension platforms
dartvel build webos
dartvel build tizen
dartvel build sony-elinux
dartvel build vscode
# Complete Sony Embedded Linux system images
dartvel build sony-elinux-iso
dartvel build sony-elinux-img
```

---

# Unified Development, Transparency, and Contracts

## Unified development

`dartvel dev` owns the complete development loop, watching pages, models, backend
functions, modules, configuration, native bindings, assets, routes, migrations,
AI tools, and home widgets. Change behavior: UI change → Flutter hot reload;
route change → route regeneration and deferred-bundle refresh; backend-function
change → backend reload; model change → schema diff and migration preview;
module change → affected-module rebuild; configuration change → subsystem
reload; Rust/native change → native binding rebuild. Studio and the DevTools
extension expose the same runtime signals the framework uses.

## Generated-code transparency

Generated behavior is always inspectable. Dartvel may hide generated output
during normal development but never obscures how an application works; generated
code carries source mappings back to models, pages, functions, annotations,
configuration entries, and module manifests.

```bash
dartvel inspect routes
dartvel inspect model User
dartvel inspect function createOrder
dartvel inspect module store
dartvel inspect transaction
dartvel inspect schema
dartvel inspect generated
dartvel explain DV001
```

### The project graph

Every inspector above answers a question about the same thing: what this
application is made of. That is one artifact, not eight — a versioned
**`DartvelProjectGraph`** carrying routes, models and their fields, backend
functions, jobs, modules, static paths, the schema, migration plans, the
protocol version and its window, memory arenas, 3D scenes, API scopes,
privacy declarations, release plans, analytics events and their consent
categories, feature flags with their owners, expiry dates and rollout rules,
each model's subject path and retention, usage meters and their limits, and
capability metadata, each node keeping the source mapping it was derived from.

The graph is the contract, and `--json` is how it is read:

```bash
dartvel inspect routes --json
dartvel inspect model User --json
dartvel inspect --json            # the whole graph
```

```json
{
  "graphVersion": 1,
  "models": [
    {
      "name": "User",
      "source": "lib/models/user.dart:7",
      "fields": [
        {"name": "email", "type": "String"},
        {"name": "taxId", "type": "String", "sensitive": true}
      ]
    }
  ]
}
```

`graphVersion` is a contract: a consumer that understands version 1 keeps
working, and a breaking change to the shape increments it rather than quietly
reshaping a field.

This ordering is deliberate and is the opposite of how the feature is usually
proposed. `--json` looks like a flag to add to commands that already exist,
but the generators do not share a model of the project — each rediscovers what
it needs from source, so eight inspectors would mean eight partial answers that
disagree at the edges. The graph is the work; `--json` is a serialization of
it. Building it in that order is also what lets the other subsystems stop
re-deriving the same facts: generated span names, stale-flag analysis, image
field discovery and the specification status index are all questions about the
graph.

**Sensitive fields are named, never valued.** `@DVModel.sensitiveField()` is
excluded from logs, AI context, traces, analytics, public serialization,
search, model pages, tables and admin; `--json` output and MCP tool results are
the same kind of surface and are covered by that rule. A sensitive field
appears in the graph as a field that exists, marked `"sensitive": true`, with
no value — the schema is what an agent needs, and the data is what it must not
be handed.

Diagnostics are part of the contract. Every error and warning Dartvel emits
carries a stable code, and `dartvel explain <code>` describes the cause and the
fix. A code is an identifier other tools can match on, so it does not change
meaning between releases.

## Platform compatibility

Every capability carries generated support metadata: `Supported`,
`Supported with limitations`, `Experimental`, `Community supported`,
`Unsupported`. Modules declare required capabilities; a parent cannot mount a
module on a target that cannot satisfy them without a configured fallback.

```bash
dartvel doctor --targets android,ios,web,vscode
```

## Upgrade and compatibility

Dartvel upgrades preserve source, generated-code, protocol, database, module,
plugin, and deployment compatibility. Automated code migrations handle changes
such as `DVStyleModifier → DVModifier`, `.styleModifier() → .modifier()` and
`DV.Storage → DV.FileStorage`. Module manifests declare compatible Dartvel
versions, validated before compiling or mounting.

```bash
dartvel upgrade --plan
dartvel compatibility-check
dartvel migrate-code
dartvel upgrade
```

**Designed, not built.** None of those four commands exists yet. There is no
`upgrade`, no `compatibility-check` and no `migrate-code` under
`packages/dartvel_cli`, and no rewrite-rule list for one to run, so every
rename above is a manual edit today. `dartvel update` updates the CLI itself
and `dartvel updates` ships over-the-air patches to a released application;
neither is this, and the near-miss in the names is worth stating once.

`DV.Storage → DV.FileStorage` is the first rule waiting for the command.
`DV.Storage` is deprecated in the current release and goes in the next minor,
which is the shape of change `migrate-code` exists to absorb. `DV.BlobStorage`
is deliberately not in the list: it is a supported alias, not a name on its way
out, and rewriting it would churn working code for nothing.

## Performance contracts

Dartvel measures application/page startup, web and route bundle size, backend
cold start and request overhead, serialization overhead, signal rebuild counts,
database query counts, model sync latency, memory usage, generated-code size,
module loading, SSG build duration, and server-render duration. Generated
diagnostics include N+1 queries, unbounded collections, excessive signal
rebuilds, route bundles over budget, blocking work in backend functions, module
dependency cycles, uncompressed large model images, and non-deterministic SSG
queries.

```bash
dartvel analyze performance
dartvel build --report
dartvel benchmark
```

## Pluggability and escape hatches

Dartvel is opinionated but every major subsystem is pluggable: any Flutter
widget (`DVBox(ExistingFlutterWidget())`), any Dart package, raw SQL, existing
state-management libraries, custom HTTP behavior, native FFI/JNI/Rust, external
services, custom build hooks, platform-specific projects, custom
serializers/databases/deployment adapters, and custom UI systems. A plugin may
contribute pages, models, backend functions, cron functions, signals, modules,
native bindings, providers, storage/database/auth/deployment adapters, Studio
panels, analyzer rules, and build hooks. Raw HTTP behavior stays on
`@DVBackendFunction`, so no separate raw-route abstraction is required.

---

# Mental Model

```text
Pages define application entry points.
Models define data and generate pages, forms, lists, tables, APIs, storage.
Backend functions define server operations, raw HTTP, background and durable work.
Signals define local, global, model, lifecycle, and cross-module reactivity.
DV.global exposes globally available reactive objects.
Cron functions define scheduled behavior.
DV.transaction coordinates reversible operations.
Modules compose complete apps, micro-sites, micro-apps, and backend domains.
DVBox defines layout, collections, and surfaces; DVText defines text.
Modifiers define styling, interaction, accessibility, and behavior.
The generated route index powers navigation, SSG, server rendering, SEO, sitemaps.
Flutter remains the renderer. Dart remains the language. Dartvel is the platform.
```

The rule for scope: design the contracts for the full vision from the beginning,
then implement them progressively without shrinking the platform's intended
destination.

---

# Specification Status

The scope rule above is why this section exists and why it takes the shape it
does. "Design the contracts for the full vision, then implement progressively"
means a section can be **finished as a contract and unbuilt as code at the same
time** — that is the method working, not a defect. A single ladder ending in
`Implemented` would rank a frozen, fully designed contract below a shipped one
and quietly pressure the spec toward describing only what exists.

So status is **two independent axes**, and every h1 section carries both. An h2
subsection inherits its parent's labels unless it declares its own.

**Stability** — how much the surface can still move:

| Label | Meaning |
|---|---|
| `Draft` | Shape under discussion. APIs are illustrative; names and signatures may change without notice. |
| `Contract` | Frozen surface. A breaking change requires the migration path in [Upgrade and compatibility](#upgrade-and-compatibility), not a spec edit. |

**Status** — how much of it is built:

| Label | Meaning |
|---|---|
| `Designed` | Nothing shipped yet. |
| `Partial` | Some of the contract is shipped; the section says which part, and what is absent. |
| `Shipped` | The contract is implemented and covered by tests. |

The two are genuinely orthogonal. `Contract`/`Designed` is a promise the
platform intends to keep and will not casually reword — the most valuable state
for anyone building against the roadmap. `Draft`/`Partial` is code that exists
while its surface is still being argued about, which is a warning to callers.

## Evidence, not adjectives

A `Partial` or `Shipped` label **must name what proves it** — a test file, a
source path, a CLI command. This borrows the discipline `docs/build-targets.md`
already applies to build targets, where "verified" means the command was run and
the artifact inspected, and for the same reason: a status nobody can check is a
status that drifts.

The machine-readable index is `docs/spec-status.json`, checked into the
repository so that reading it needs no toolchain:

```json
{
  "section": "Secrets and Environments",
  "stability": "Draft",
  "status": "Partial",
  "evidence": [
    "packages/dartvel_core/lib/src/secrets/secrets.dart",
    "packages/dartvel_core/test/secrets_test.dart"
  ],
  "absent": "DV-SECRETS-001 reachability analysis; rotation hooks; deploy-time validation"
}
```

`dart run tool/spec_status_check.dart` fails when a section's claim cannot be
substantiated: an entry naming a section the spec does not contain, a section
the index omits, a `Partial` or `Shipped` entry whose evidence path does not
exist, or a `Partial` entry that does not say what is absent. Running it in CI
is what keeps the labels honest — without it this is another list that ages.

The index is the single source of truth for implementation status. The agent
rule files point at it rather than restating it; a status paragraph copied
across eleven files is exactly the drift this section exists to end.

`docs/spec-vocabulary.md` is the companion crib: one page of the words this
specification uses precisely — generation inputs, field-scoped annotations,
the namespaces that exist and the ones that do not, both label sets, and the
diagnostic-code format. It records rules stated normatively here, so that a
proposal written in prose stops drifting from the conventions the code
already follows.

---

# The Vision

Developers write only:
* Pages
* Models
* Backend Functions
* UI
* Business Logic

Dartvel automatically provides:
* Routing
* State management
* CRUD
* Validation
* Forms
* Authentication
* APIs
* Model sync
* Database access
* Storage
* Native device APIs
* Scheduling
* Multi-tenancy
* SEO
* PWA
* Observability
* AI tooling
* Deployment
* Infrastructure
* Native rust bindings

while Flutter remains the rendering engine and Dart remains the only language developers write.

# App Store Publishing and Privacy Manifests

Stability: `Draft` · Status: `Partial`

`dartvel publish <store>` takes a built application to Google Play, App Store
Connect, TestFlight or Firebase App Distribution, declared under
`dartvel.publish` in `pubspec.yaml`. The plan is resolved and validated before
anything runs, because the expensive part is an upload of a binary that took
minutes to produce: a track nobody publishes to is refused rather than
corrected to the nearest, credentials that were never declared are refused
rather than left to a tool that stops to ask, and App Store Connect is refused
off macOS at the start rather than with "command not found" at the end.
`--dry-run` prints what would run.

What follows is the rest of the story — credentials, tracks, metadata, and the
two store declarations that are questions about the project rather than about
the developer.

## Credentials: declared here, held elsewhere

**Dartvel holds no signing key and no store credential.** It declares which
ones a publish needs, resolves them through Secrets and Environments at the
moment of use, and refuses before the upload when one is missing.

```yaml
dartvel:
  publish:
    play:
      track: internal
      credentials: PLAY_SERVICE_ACCOUNT   # a secret name, not a path
    appstore:
      keyId: APPSTORE_KEY_ID
      issuerId: APPSTORE_ISSUER_ID
      privateKey: APPSTORE_API_KEY
```

The reason is custody, not convenience. An Android app signing key cannot be
rotated without losing the listing, so a framework that kept one would be
holding something irreplaceable on behalf of every application built with it —
a key-custody product wearing a build tool's clothes. Signing identities stay
where their platforms already keep them: the macOS keychain for certificates
and provisioning profiles, the CI secret store for service accounts and API
keys, Google Play App Signing for the upload key's counterpart.

That splits cleanly:

| Dartvel resolves and passes through | The developer or CI holds |
|---|---|
| store API keys and service accounts, by secret name | the secret values themselves |
| which identity a build signs with, by name | keystores, certificates, provisioning profiles |
| the track, rollout and locale a publish targets | store account access |

A publish from a laptop reads the same declaration as a publish from CI; only
the secret resolver differs, which is the point of naming rather than
embedding (`DV-STORE-001`).

## Tracks, rollout and metadata

```bash
dartvel publish play --track beta --rollout 10
dartvel publish testflight --group "Internal QA"
dartvel publish appstore --phased
```

Store metadata is versioned in the repository and localized through
Internationalization and Localization, so the description a store shows is
reviewed like any other text and translated by the same pipeline. A locale the
store lists as supported with no metadata written for it is reported before the
upload rather than published in English (`DV-STORE-004`).

**Screenshots come from golden tests.** The application already renders
deterministic goldens at declared device sizes under `dartvel test golden`; a
second screenshot pipeline would drift from what ships, and the drift is
invisible until somebody compares a store listing with a running app. A store
size with no declared golden is refused rather than filled with a stretched
image (`DV-STORE-003`).

```yaml
dartvel:
  publish:
    screenshots:
      appstore-6.7: golden/checkout_iphone_67.png
      play-phone: golden/checkout_pixel.png
```

## Privacy manifests and Data Safety are generated

Apple's `PrivacyInfo.xcprivacy` and Google Play's Data Safety form ask two
questions: which personal data the application collects, and which
required-reason APIs it uses. Both are already in the project graph. The model
graph knows which fields are declared `@DVModel.sensitiveField()` and what they
are; the native binding manifest knows which platform APIs the build actually
registers; the configured providers know whether anything leaves for analytics
or advertising.

So Dartvel writes both declarations from the application rather than asking a
developer to describe their own app from memory a year after writing it:

```bash
dartvel publish appstore --plan     # shows the declaration it will submit
```

- Collected data types come from sensitive fields and the models reachable from
  backend functions the client calls, each naming the field it was derived
  from.
- Required-reason API entries come from the binding manifest: the file
  timestamp, user defaults, disk space, active keyboard and boot time APIs
  Apple enumerates, with the reason code the binding declares. A binding that
  uses one and declares no reason fails the build, because the store rejects
  the upload for it and the rejection arrives days later (`DV-STORE-006`).
- Purpose and linkage — whether data is linked to the person, whether it is
  used for tracking — are declared per data type. Dartvel proposes a default
  from the graph and refuses to guess where the answer is a legal judgement
  rather than a fact about the code.

`dartvel doctor` compares the declaration against the application on every run
and reports drift in either direction: a field added since the form was
written, a binding removed that the form still claims, a tracking provider
configured that the manifest does not mention (`DV-STORE-002`). This is the
half that decays — the declaration is written once and the application keeps
moving — and it is the half a store checks.

## Other stores

Extension marketplaces (VS Code, browser stores) and television stores publish
through the same command and the same plan-first discipline, each driven by its
own vendor tool. What a store cannot do is not simulated: a store with no
staged rollout refuses `--rollout` rather than uploading and ignoring it.

## Diagnostics

| Code | Reason | Level |
|---|---|---|
| `DV-STORE-001` | a declared store credential is not resolvable in this environment | `error` |
| `DV-STORE-002` | privacy declaration drift between the application and the store form | `error` |
| `DV-STORE-003` | a store screenshot size has no declared golden | `error` |
| `DV-STORE-004` | a store-supported locale has no metadata written for it | `warning` |
| `DV-STORE-005` | the store does not support an option the publish asked for | `error` |
| `DV-STORE-006` | required-reason API used by a binding that declares no reason | `error` |

## Deliberately absent

- **Credential custody.** Declared, resolved, never held. See the table above.
- **Answering the store's judgement calls.** Linkage and tracking purposes are
  declared by the developer with a proposed default; a framework that guessed
  would be filing a legal statement on somebody's behalf.
- **Store account provisioning.** Creating accounts, agreements and bundle
  identifiers is the developer's, once, in the store's own console.

# Takeaway

- user says I want to build an app for X
- Dartvel already has it covered
