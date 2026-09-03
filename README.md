# Dartvel

> **Flutter's Laravel.**
>
> A batteries-included, AI-native, full-stack platform for building Flutter applications.

---

## ⚠️ Alpha status — read this first

Dartvel is an **alpha**. It is usable and much of it is real, but it is not
finished, and this section exists so you can tell the difference without
reading the source.

**[NEW_SPEC.md](NEW_SPEC.md) is a design specification, not a description of
what ships today.** Where the spec and this README disagree with the code, the
code wins.

**Published**, and installable three ways — see
[Getting Started](#-getting-started) rather than a second copy of it here.

[dartvel.dev](https://dartvel.dev) is built with Dartvel, which is the reason
several of its worst bugs are fixed: Flutter's hash URLs silently sent every
deep link to `/`, the semantics tree was never built so no crawler and no
screen reader saw anything, and links tore the document down and rebuilt the
whole application instead of routing. None of those show up in a unit test.

**What is actually built** is not listed here, deliberately. A hand-written
table of recent work is out of date the week after it is written, and this one
was. [`docs/spec-status.json`](docs/spec-status.json) carries a status per spec
section and `dart run tool/spec_status_check.dart` fails when a section claims
to be built and the evidence it names does not exist. `dartvel spec status`
prints the same thing.

**Implemented, but not equally mature.** The feature table below marks each
area. Anything flagged ⚠️ Partial has an API surface and prebuilt pieces, but
is incomplete in the way the row names — expect to fill gaps yourself.
📐 Designed means the contract is settled in NEW_SPEC.md and **no
implementation exists behind it**; it is listed so the shape is public, not
because you can use it.

**How "verified" is used here.** A target marked ✅ had its build run and its
artifact inspected — the file listed, its type checked. That proves it
compiles and links; it does not prove the application starts.

Eleven targets go further and are run in CI: Linux, Linux in a terminal, the
web, a web server rendering each route, Android, macOS, iOS, Windows, tvOS,
Sony eLinux, and both browser extensions. The app is launched on a virtual
device, an emulator or a real browser and screenshotted, and the screenshot is
checked for *pixels* rather than for existing. That check earned itself. Every job used to end at
`test -s capture.png`, which a blank screen satisfies — a crash before the
first frame produces a full-size image of one colour, a few kilobytes on disk,
and a green build.

**Where it says shipped, a tool agrees.** Per-section status lives in
[`docs/spec-status.json`](docs/spec-status.json), checked by
`dart run tool/spec_status_check.dart`, which fails when a section claims to be
built and the evidence it names does not exist. Each entry carries two labels
— how much the public surface can still move, and how much is built — so a
frozen contract that is deliberately unbuilt reads as the scope rule working
rather than as a gap. Twenty-two sections are shipped; thirty-three are
partial and say what is missing.

**Build targets** are individually verified with evidence in
[docs/build-targets.md](docs/build-targets.md). Thirteen of fifteen build.
webOS builds and runs in a Wayland window on ARM under emulation — its engine
is a 32-bit ARM build Google does not publish, so Dartvel builds it from
source — though it has not been run on a television. Fuchsia is blocked on its
engine, which does not build at Flutter 3.44.5: four attempts are recorded,
and the last matches the embedder fork's own invocation exactly and still
fails on a Dart VM thread-local being linked into a shared library.

If you hit something that claims to work and does not, that is a bug in these
docs as much as in the code — please report it.

---

## 📖 The Complete Vision

Dartvel simplifies developer workflows. Instead of writing controllers, repositories, DTOs, route maps, or boilerplate state folders, you primarily write:
* **Pages** (`@DVPage()`)
* **Models** (`@DVModel`)
* **Backend Functions** (`@DVBackendFunction()`)
* **UI & Style Modifiers** (`DVBox`, `DVText`, `.modifier()`)
* **Business Logic**

Everything else is automatically compiled, generated, or served by the framework.

---

## 🚀 Key Features

| Feature | Description | Status |
| :--- | :--- | :--- |
| **UI Primitives** | `DVBox`, `DVText`, `DVNavLink`, and fluent styling built on `Mix` | ✅ Implemented |
| **Routing** | File-based pages router with strongly-typed navigation targets, generated onto `go_router`. Path URLs on the web, and `DVNavLink` for links that preload and preview | ✅ Implemented |
| **State Management** | Riverpod-powered signals (`context.signal`, reactive models, `DV.global`) | ✅ Implemented |
| **Models & Forms** | `@DVModel` annotation + `DVForm<T>` automatic & manual controls | ✅ Implemented |
| **Backend Runtime** | Axum/Tokio Rust server calling Dart FFI, supporting SSE streams | ✅ Implemented |
| **Platform APIs** | `DV.Platform` on six platforms — Linux, web, Windows, Android, iOS, macOS — through `dart:ffi` and jnigen, never platform channels. Biometrics, NFC, Bluetooth and tray need an `Activity` or a desktop the web has not got; each absence is recorded with its reason | ⚠️ Partial |
| **Authentication** | Local provider with salted password hashes, OAuth2 (PKCE) with Google/GitHub/GitLab/Bitbucket/Microsoft presets, LDAP, SAML 2.0, passkeys (WebAuthn) and Sign-In with Ethereum | ✅ Implemented |
| **Outbound HTTP** | Protocol negotiation with ordered fallback, RFC 8297 early hints, and a native HTTP/2 client on the `h2` crate verified against a live server; HTTP/3 is not complete | ⚠️ Partial |
| **Terminal rendering** | `-cli`/`-tui` targets resolve, build-time backend selection, `DV.Platform.surface`, launch negotiation. The terminal backend itself is not built | ⚠️ Partial |
| **Database** | SQLite (file + in-memory, WAL), PostgreSQL and MySQL, each on its own wire protocol, with TLS on both network engines so Aurora, Neon, Supabase, PlanetScale and Cloud SQL are reachable | ✅ Implemented |
| **Queues & Jobs** | `@DVJob` with typed dispatch and handlers on seven adapters -- in-memory, database, Redis, SQS, RabbitMQ, Pub/Sub and Kafka. The four network ones are verified in CI against a real broker | ✅ Implemented |
| **Cache** | A pluggable cache with memory, database, Redis, Memcached and multi-node distributed adapters, tags and revalidation | ✅ Implemented |
| **Mail & Notifications** | SMTP plus HTTP mail (Resend, SendGrid, Postmark, Mailgun, SES), FCM push, APNS over native HTTP/2, Web Push (RFC 8291/8292), and Twilio SMS | ✅ Implemented |
| **SEO** | `dartvel build web` writes the head tags, JSON-LD, per-route HTML built from the semantics tree, `sitemap.xml` with a styled stylesheet, and `robots.txt` | ✅ Implemented |
| **PWA** | Manifest, a viewport meta on every built page, icons generated from web/icon.png, a service worker that precaches the build's routes and keeps an outbox of writes made offline, replayed in order once the network is back -- verified in a real Chrome on every push -- a self-contained offline page, and `DV.Platform.install` for the install prompt | ✅ Shipped |
| **AI Integration** | HTTP adapters for Claude, OpenAI, Gemini, OpenRouter, and Ollama, plus the deterministic local adapter | ✅ Implemented |
| **Sensitive Fields** | `@DVModel.sensitiveField()` redacts fields from public serialization, cards, logs, and AI context | ✅ Implemented |
| **Lifecycle Signals** | Read-only enum signals: `DV.lifecycle.app`/`.build`, `context.lifecycle.page`/`.request`/`.transaction` | ✅ Implemented |
| **Modules** | `DV.Modules.<id>` registry with per-module lifecycle and mount-point independence | ✅ Implemented |
| **Reversible Transactions** | `DV.transaction(...)` with `context.afterCommit(...)` and `context.compensate(...)` | ✅ Implemented |
| **Observability** | Structured logs, Prometheus metrics on `/metrics`, real health checks on `/health`, and W3C Trace Context propagation with sampling decided from the trace id | ✅ Implemented |
| **Scheduling** | `@DVBackendCron` and `@DVClientCron` collected into generated entries, a CLDR-correct cron evaluator, and `DVScheduler` to run them | ✅ Implemented |
| **Testing** | `dartvel test` with unit, e2e, golden, native, accessibility and release modes; generated model factories with per-call sequences | ✅ Implemented |
| **Deployment** | `dartvel deploy` to Firebase, Vercel, Netlify and Cloudflare, plus function mode writing a per-function artifact for Lambda, Cloud Run, containers, edge, Fly, Railway and bare metal. It refuses to ship an environment whose required secrets do not resolve | ✅ Implemented |
| **Data workflows** | CSV, NDJSON and Excel import/export, resumable chunked imports through queues, policy-filtered and streamed exports, scheduled reports | ✅ Implemented |
| **Secrets** | Declared under `dartvel.secrets`; `DV-SECRETS-001` fails the build when a backend-scoped secret is reached from client code. Rotation hooks and platform key stores are not built | ⚠️ Partial |
| **i18n** | CLDR plural rules, typed translation keys, and `dartvel i18n extract`/`check` over ARB catalogues. No route locale negotiation or localized mail templates yet | ⚠️ Partial |
| **Accessibility** | Contrast and tap-target checks, semantic modifiers, and `DVTable` with keyboard navigation, focus that survives a sort and per-cell announcements. Nothing fails a release on a regression yet | ⚠️ Partial |
| **Multi-Window & Kiosk** | Specified as a contract — a window is a route, `open()` never fails, kiosk is a per-device or per-display policy. `DV.Window` degrades correctly on every target; **no native window bindings exist, so no OS window is created yet** | 📐 Designed |
| **Build Targets** | Mobile, web, desktop, plus TV/embedded via vendor embedders, with toolchain preflight and auto-install | ⚠️ Partial — see [table](#-build-targets) |

---

## 🛠️ CLI Commands

Manage the full-stack lifecycle directly with the Dartvel CLI:

```bash
# Project initialization
dartvel create [name]
dartvel doctor
dartvel doctor --target tizen      # check one target's toolchain

# Development — one loop: generation, hot reload, backend, native runtime
dartvel dev
dartvel run                        # alias

# Production builds (see Build Targets below)
dartvel build [platform]
dartvel build web --no-auto-install

# Database management
dartvel db migrate
dartvel db push
dartvel db pull
dartvel db seed

# Generators
dartvel generate page
dartvel generate model
dartvel generate backend-function
dartvel generate form

# Diagnostics — look up a code the runtime logged
dartvel explain DV-WINDOW-004      # what it means, and how serious it is
dartvel explain DV-KIOSK           # every code in a family
dartvel explain                    # which families exist
```

Dartvel degrades rather than throwing where a target cannot do what was asked —
a phone has no second window, a web popup outside a user gesture is blocked —
and every degradation carries a stable code that never changes meaning between
releases. `dartvel explain` is how you read one without searching the
specification by hand.

---

## 🎯 Build Targets

```bash
dartvel build              # every target this host can build
dartvel build web
dartvel build tizen        # alias: dartvel build tpk
dartvel build sony-elinux  # also: sony-elinux-iso, sony-elinux-img
dartvel build webos
dartvel build vscode       # VS Code extension host + Flutter webview
```

Verified on Linux x64 against `examples/dartvel_example`. "Verified" means the command was run and the artifact inspected:

| Target | Status |
| :--- | :--- |
| `linux` | ✅ Builds **and runs** — an integration test launches it under Xvfb in CI on every push |
| `web`, `android`, `fireos` | ✅ Build, artifacts verified |
| `windows` | ✅ Verified on a CI host — `dartvel_example.exe` is a PE32+ x86-64 binary beside `dartvel_shelf.dll` |
| `macos` | ✅ Verified on a CI host — a Mach-O **universal binary** (x86_64 + arm64) with the Rust runtime bundled as a framework |
| `ios`, `tvos` | ✅ Verified on a CI host — `Runner.app`, and for tvOS an `appletvsimulator` build rather than an iPhone one |
| `tizen` / `tpk` | ✅ Signed 9.3MB TPK containing the engine and assets |
| `chrome-extension`, `firefox-extension` | ✅ Build — MV3 service worker and event-page manifests, verified to differ |
| `vscode` | ✅ Builds — verified extension host JS and Flutter webview artifacts |
| `webos`, `sony-elinux` | ❌ Blocked — both embedders ship a Dart below `mix`'s ≥3.11 floor. Ours to fix by re-pinning the forks, not a vendor limit |
| `fuchsia` | ⚠️ Builds the Flutter bundle and stages the app; the fork needs a build-only entry point |

Flutter has **no desktop cross-compilation** — Windows needs Windows, the Apple targets need macOS. `dartvel build` skips what the host cannot build instead of failing the whole run, and the [CI matrix](.github/workflows/platform-build-matrix.yml) covers the hosts this repository's development machine does not have.

**Twelve of sixteen targets build with an inspected artifact. One — `linux` — is verified by actually running.** That distinction is deliberate: an artifact existing proves compilation, not that the application starts.

**→ Full detail, evidence, and per-target setup: [docs/build-targets.md](docs/build-targets.md)**

**→ New here? [docs/getting-started.md](docs/getting-started.md)** — create a project, add a page, add a model, add a backend function. Every command on that page was run against a fresh project before it was written.

### Toolchain preflight

Before building, Dartvel checks that the host supports the target and that the required tools are installed. Missing tools are named, and Dartvel offers to install what it safely can:

```bash
dartvel build tizen                      # asks before installing
dartvel build tizen --auto-install       # installs without asking
dartvel build tizen --no-auto-install    # never installs; fail instead
dartvel doctor --target tizen            # just check
```

Under CI (`CI=true`, `GITHUB_ACTIONS`, and friends) it installs unattended, so a pipeline never hangs on a prompt. Anything installed mid-run is added to `PATH` immediately, so the build that installed a toolchain can use it.

Dartvel auto-installs the embedders (from its forks), the webOS `ares` CLI, and Linux desktop dependencies. It deliberately does **not** auto-install licence-gated or multi-gigabyte vendor SDKs — Xcode, Visual Studio, the Android SDK, Tizen Studio — and prints instructions for those instead.

### Embedder forks

Embedded/TV targets run through the vendor's dedicated Flutter embedder, never plain `flutter build`. Dartvel forks each one so it can be pinned and patched against the Flutter version Dartvel ships:

| Target | Embedder fork | Upstream | Vendor |
| :--- | :--- | :--- | :--- |
| `tizen` | [Danroyal001/dartvel_tizen](https://github.com/Danroyal001/dartvel_tizen) | [flutter-tizen/flutter-tizen](https://github.com/flutter-tizen/flutter-tizen) | Samsung |
| `sony-elinux` | [Danroyal001/dartvel_elinux](https://github.com/Danroyal001/dartvel_elinux) | [sony/flutter-elinux](https://github.com/sony/flutter-elinux) | Sony |
| `webos` | [Danroyal001/dartvel_webos](https://github.com/Danroyal001/dartvel_webos) | [lg-flutter-webos/flutter-webos](https://github.com/lg-flutter-webos/flutter-webos) | LG |
| `vscode` | [Danroyal001/dartvel_vscode](https://github.com/Danroyal001/dartvel_vscode) | [SlowGen/flutter_vscode](https://github.com/SlowGen/flutter_vscode) | VS Code |

These embedders download a *vendor-built* Flutter engine per version, so a target can lag behind Dartvel's Flutter — and a version-pin bump alone cannot fix that. For Sony eLinux the binding constraint is the opposite direction and worth stating precisely: the embedder's Flutter is too **old** for Dartvel's own dependency floor. Details and evidence are in [docs/build-targets.md](docs/build-targets.md).

---

## 📦 Getting Started

### 1. Install

The CLI is a single self-contained binary. The Dart runtime and the Rust
server library are linked into it, so nothing has to be installed first —
**you do not need Dart or Flutter to run `dartvel`.** You do need Flutter to
*build* an application, for whichever target you are building.

```bash
# Homebrew — a prebuilt binary
brew install Danroyal001/dartvel_dev/dartvel_dev

# npm — downloads the same binary
npx dartvel_dev --help

# pub — if you already have the Dart SDK
dart pub global activate dartvel_cli
```

Or take the binary straight from a
[release](https://github.com/Danroyal001/dartvel_dev/releases): Linux, macOS
and Windows on x64, Linux and macOS on arm64. Then put it on your PATH:

```bash
dartvel ensure-path
```

`dartvel --version` reports the CLI, the Dart SDK, Flutter and Shorebird, so a
missing toolchain shows up before a build fails on it.

**The published name is `dartvel_dev` and the command is `dartvel`.** They
differ because `dartvel` was taken on pub.dev on 2026-08-06 by an unrelated
package. Everything you interact with is called `dartvel`.

### 2. Add it to a project

```yaml
dependencies:
  dartvel_dev: ^0.3.0
```

Or the pieces directly, where you want only some of them:
[`dartvel_core`](https://pub.dev/packages/dartvel_core) (models, database,
cache, queues, auth, notifications, AI),
[`dartvel_flutter`](https://pub.dev/packages/dartvel_flutter) (UI, routing,
signals, native platform APIs),
[`dartvel_shelf`](https://pub.dev/packages/dartvel_shelf) (the Rust runtime),
[`dartvel_cli`](https://pub.dev/packages/dartvel_cli),
[`dartvel_generator`](https://pub.dev/packages/dartvel_generator).

### 3. Start it

```bash
dartvel create my_app
cd my_app
dartvel dev
```

`dartvel dev` runs generation, the Flutter app and the backend together, and
reloads only what changed: a page edit hot-reloads Flutter, a backend edit
restarts the server, a Rust edit rebuilds the native library.

### 4. Declare Reactive Models
Annotated models automatically generate DB schemas, validation, forms, and serializations:
```dart
// lib/models/user.dart
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _User {
  final String name;
  final String email;

  const _User({required this.name, required this.email});
}
```

### 5. Build Safe Reactive Forms
Render custom-designed form layouts with auto-generated controls, validation states, and submit triggers:
```dart
// lib/pages/index.page.dart
import 'package:your_app/dartvel_client/dartvel_client.dart';

@DVPage()
Widget _indexPage(BuildContext context) {
  return DVForm<User>.builder(
    (formControls) {
      final userControls = formControls as UserFormControls;
      return DVBox.list([
        DVText(userControls.name).modifier(DVModifier().input()),
        DVText(userControls.email).modifier(DVModifier().input()),
        DVText('Save').modifier(
          DVModifier().onPressed(
            userControls.emailIsValid ? userControls.submit : null,
          ),
        ),
      ]);
    },
    const User(name: 'John Doe', email: 'john@example.com'),
  );
}
```

### 6. Create FFI Backend Functions
Write plain Dart functions that are compiled into a high-performance Rust runtime using Axum and FFI:
```dart
// lib/backend/functions/hello.get.dart
import 'package:dartvel_core/dartvel.dart';
import 'package:your_app/dartvel_client/dartvel_client.dart';

@DVBackendFunction()
Future<User> _getUser(String id) async {
  return User(name: 'User $id', email: 'user$id@example.com');
}
```

Call it directly from your frontend code:
```dart
final user = await getUser('101');
```

---

## 🔒 Authentication

Support Clerk-style authentication and native OS login flows out-of-the-box:

```dart
// Core Methods
await DV.Auth.signInWithEmailAndPassword(email: email, password: password);
await DV.Auth.signInWithProvider('google');
await DV.Auth.signInWithPasskey();
await DV.Auth.signInWithWeb3();

// Prebuilt Widgets & Pages
DV.Auth.SignInWithEmailAndPasswordPage();
DV.Auth.SignInWithProviderPage();
DV.Auth.SignInWithPasskeyPage();
```

---

## 🔄 Reversible Transactions

Wrap work that must succeed or unwind together. Irreversible effects go in
`afterCommit` so they never fire for work that rolled back; external effects
Dartvel cannot reverse itself register a `compensate` inverse:

```dart
final order = await DV.transaction((context) async {
  final payment = await gateway.charge(cart.total);
  context.compensate(() => gateway.refund(payment.id));   // undo on failure

  final order = await Order.create(paymentId: payment.id);

  context.afterCommit(() async {                          // only if committed
    await DV.Notifications.send(customer.id, OrderConfirmed(order));
  });

  return order;
});
```

Compensations run in **reverse registration order**, so each unwinds while what
it depended on still stands. Nested `DV.transaction` calls join the active
transaction (pass `isolated: true` to opt out), and a failing compensation
doesn't stop the others — `DVCompensationException` carries the original cause
alongside the rollback failures.

---

## 🔁 Lifecycle Signals

Lifecycle is exposed as **read-only** enum signals. The framework owns the
transitions; your code observes them:

```dart
DV.lifecycle.app.listen((state) {
  if (state == DVAppLifecycle.booting) {
    DV.global<PaymentGateway>(PaystackGateway(secret: ...));
  }
});

DV.lifecycle.app.value;   // DVAppLifecycle.ready
DV.lifecycle.build.value; // DVBuildLifecycle.idle
```

Also available: `context.lifecycle.page`, `.request`, and `.transaction`, plus
`DV.Modules.<id>.lifecycle`. There is no setter on the public signal type — a
failing observer can't break a transition for anyone else.

---

## 🗄️ Local Database

SQLite is the zero-config local database — no separate service for development
or tests:

```dart
// Tests and ephemeral work
DV.Database.configure(SqliteDVDatabaseAdapter.memory());

// Development and production files: WAL and foreign keys on by default
DV.Database.configure(SqliteDVDatabaseAdapter.file('.dartvel/app.db'));

await DV.Database.execute(
  'INSERT INTO users (name, age) VALUES (?, ?)',
  <Object?>['Ada', 36],
);
final rows = await DV.Database.query(
  'SELECT * FROM users WHERE age > ?',
  <Object?>[30],
);
```

This executes arbitrary SQL — DDL, joins, aggregates, transactions, blobs.
`MemoryDVDatabaseAdapter` remains available but understands only a few
statement shapes and throws on anything else; prefer
`SqliteDVDatabaseAdapter.memory()` for tests.

SQLite needs `dart:ffi`, so on web `SqliteDVDatabaseAdapter` throws
`UnsupportedError` at construction naming the alternative, rather than
degrading to a fake database. The import is conditional, so web and Wasm
builds do not pull in `dart:ffi` at all.

Postgres and MySQL adapters ship too, each speaking its own wire protocol, and
the Postgres one negotiates TLS — which is what a managed endpoint such as
Aurora, Neon, Supabase or Cloud SQL requires, most of them refusing plaintext
outright. `sslMode` takes libpq's names, so a connection string copied from a
provider's console pastes in unchanged.

The supported engines are SQLite, PostgreSQL and MySQL, each with their
wire-compatible variants. MongoDB, ClickHouse and BigQuery are **out of scope
by decision**, not waiting in a backlog.

---

## 🧊 Cache

`DV.Cache` runs on a swappable adapter. It defaults to process-local memory;
point it at a database to survive restarts and share the application's SQLite
file:

```dart
final db = SqliteDVDatabaseAdapter.file('.dartvel/app.db');
DV.Database.configure(db);
DV.Cache.configure(DVDatabaseCacheAdapter(db));   // shares the same file

await DV.Cache.set('users:list', users, const Duration(minutes: 5));
DV.Cache.tag('users:list', <String>['users']);
await DV.Cache.revalidateTag('users');
await DV.Cache.purgeExpired();
```

Across several servers, keys are placed by rendezvous hashing rather than
`hash % n`. That is not a detail: with a modulo, adding or removing one node
remaps almost every key, so the cache misses on nearly everything at once, the
database takes the full load, and nothing reports an error.

```dart
DV.Cache.configure(DVDistributedCacheAdapter(
  nodes: <String, DVCacheAdapter>{
    'cache-a': DVRedisCacheAdapter(await DVRedisClient.connect(host: 'a')),
    'cache-b': DVRedisCacheAdapter(await DVRedisClient.connect(host: 'b')),
  },
  replicas: 2,   // survive losing one node without losing its keys
));
```

A node that cannot be reached costs its own keys and no others: a read from it
is a miss rather than an exception, because a cache outage should not become an
application outage. Locks run on the primary alone, so two callers cannot each
win on a different node.

---

## 📬 Durable queues

`DV.Queues` defaults to an in-memory adapter, so dispatched jobs are lost on
restart. Point it at a database to make them durable:

```dart
const DVJobPayloadCodecs().register(
  DVJobPayloadCodec<SendWelcomeEmail>(
    name: 'send_welcome_email',                       // stable across releases
    encode: (job) => <String, Object?>{'userId': job.userId},
    decode: (json) => SendWelcomeEmail(json['userId']! as String),
  ),
);
DV.Queues.useAdapter(DVDatabaseQueueAdapter(db));
```

A durable queue has to write bytes, so every persisted payload type needs a
codec. Dispatching a type with no codec throws, and so does draining a job
whose codec is missing from the running process — neither silently drops work.
The in-memory adapter keeps the Dart object and needs no codec.

All five network adapters ship: Redis, SQS, RabbitMQ, Pub/Sub and Kafka. The
four that talk to a hosted service are verified in CI against the real thing --
ElasticMQ, RabbitMQ's own image, Google's emulator and Apache Kafka -- rather
than against a fake, which is how nine bugs were found that every unit test
had passed.

Each is written around what its service actually offers rather than over it.
SQS and Pub/Sub refuse `pending` instead of returning an empty list, because an
empty list reads as "there is nothing" when the truth is "I cannot see". Kafka
is a log, so it has no dead letters, no priority and no out-of-order retry, and
`lag` gives the honest version of a backlog: a distance, not a list.

---

## 🗂️ File storage

`DV.FileStorage` runs on a swappable adapter, defaulting to process-local
memory. `S3FileStorageAdapter` covers AWS S3 and S3-compatible stores
(Cloudflare R2, MinIO), signing each request with SigV4:

```dart
DV.Storage.configure(S3FileStorageAdapter(
  bucket: 'assets',
  region: 'us-east-1',
  credentials: DVAwsCredentials(
    accessKeyId: env.awsKeyId,
    secretAccessKey: env.awsSecret,
  ),
  endpoint: Uri.https('minio.internal:9000'),   // optional; R2/MinIO
));

await DV.Storage.put('avatar.png', bytes, contentType: 'image/png');
final keys = await DV.Storage.list(prefix: 'avatars/');
```

Path-style addressing (`{endpoint}/{bucket}/{key}`) is the default because R2
and MinIO require it; pass `usePathStyle: false` for virtual-hosted AWS
buckets. A missing object reports `DVFileStorageException.isNotFound` rather
than a generic failure, and deleting an object that is already gone succeeds.

Azure Blob and Google Cloud Storage adapters are **not** implemented yet.

---

---

## 🔔 Push notifications

`FirebasePushProvider` sends through FCM's HTTP v1 API. Minting a Google
access token needs RSA JWT signing, which Dartvel does not bundle, so the token
comes from your own credentials layer and is fetched per send — an expired one
is never reused:

```dart
DV.Notifications.register(
  FirebasePushProvider(
    projectId: 'my-project',
    accessToken: () => googleCredentials.accessToken(),
  ),
);
```

A stale device token surfaces as `DVPushProviderException` with
`isUnregisteredToken == true`, which is the signal to prune the token rather
than retry it.

---

## ✉️ SMTP

`SmtpMailProvider` speaks SMTP over a raw socket, so it works against any mail
server rather than a vendor API:

```dart
DV.Notifications.mail.useProvider(SmtpMailProvider(
  host: 'smtp.example.com',
  username: env.smtpUser,
  password: env.smtpPassword,
));
```

STARTTLS is issued automatically when the server advertises it and the
connection is not already secure, and capabilities are re-read afterwards
because servers commonly advertise `AUTH` only once the channel is encrypted.
`AUTH PLAIN` is preferred over `AUTH LOGIN`; a server offering neither fails
loudly. A `4xx` reply is reported as `DVSmtpException.isTransient` so callers
can retry rather than treating it as permanent.

Raw TCP is unavailable in browsers, so on web the connection throws
`UnsupportedError` naming the HTTP providers instead — the import is
conditional, verified by a passing `flutter build web` and Wasm dry run.

---

---

## 💬 SMS

`TwilioSmsProvider` fills the `sms` notification channel:

```dart
DV.Notifications.register(TwilioSmsProvider(
  accountSid: env.twilioAccountSid,
  authToken: env.twilioAuthToken,
  fromNumber: '+15550000000',        // or messagingServiceSid: 'MG…'
));
```

Exactly one of `fromNumber` or `messagingServiceSid` is required, checked at
construction rather than failing on the first send. SMS has no subject line, so
a non-empty `title` becomes the first line of the body rather than being
dropped. Twilio's error code and message are surfaced on
`DVPushProviderException`.

---

**APNS and Web Push are both implemented.**

APNS needed HTTP/2, which `package:http` does not speak — on native it is
`dart:io`'s `HttpClient`, which is HTTP/1.1 only. Rather than narrow the
feature, Dartvel ships a native HTTP/2 client, and `ApnsPushProvider` pins
itself to HTTP/2 so it can never silently downgrade to an endpoint Apple does
not run. See [`docs/http-transport.md`](docs/http-transport.md).

Web Push is `WebPushProvider`: RFC 8291 `aes128gcm` payload encryption and
RFC 8292 VAPID signing, both required rather than optional. The push service is
untrusted infrastructure that never sees the plaintext, and it refuses an
anonymous POST because anyone who learned the endpoint could otherwise send to
it. P-256 ECDH, HKDF and AES-GCM come from `pointycastle`, which this project
already depends on — the earlier note that no bundled library provided them was
looking only at `crypto`.

---

---

## 🔎 Full-text search

`DVSqliteSearchProvider` indexes records with SQLite's FTS5 extension, so
matching is word-based and results are ranked by relevance:

```dart
final search = DVSqliteSearchProvider<User, UserFacets>(
  database: db,
  records: users,
  document: (user) => '${user.name} ${user.bio}',
  facetMatcher: (user, facets) =>
      facets?.role == null || facets!.role!.contains(user.role),
);
final page = await search.query('ada lovel');   // prefix-matches the last term
```

Unlike `DVInMemorySearchProvider`, which scans for substrings, this matches
whole words — `lovelace` no longer hits `Unlovelaced` — and orders by BM25.
Raw user input is quoted term by term, so FTS5 operators someone types
(`AND`, `*`, `:`, quotes) are searched for literally instead of executing as
query syntax or raising an error.

FTS5 does the matching; models stay in Dart and facets are applied afterwards,
so ranked ids are read in full before paging. That suits datasets that fit in
memory rather than very large corpora.

For hosted search, `MeilisearchProvider` and `AlgoliaSearchProvider` speak the
same `DVSearchProvider` contract over the shared HTTP transport:

```dart
final search = MeilisearchProvider<Product, ProductFacets>(
  baseUrl: Uri.https('search.example.com'),
  apiKey: env.meilisearchKey,
  indexName: 'products',
  fromJson: (hit) => Product.fromJson(hit),
  facetFilter: (facets) => <String>[
    if (facets?.category case final c?) for (final v in c) 'category = "$v"',
  ],
);
```

Dartvel pages are 1-based; Algolia counts from zero, so the page number is
translated in both directions and callers always see the page they asked for.
A rejected query or an unreadable response throws
`DVSearchProviderException` rather than returning an empty page.

`OpenSearchProvider` covers OpenSearch and Elasticsearch, which share this
query API. It translates the three things they do differently so callers still
see one contract: paging is offset-based (`from`/`size`) rather than page
numbers, hits arrive nested under `hits.hits[]._source`, and the total is an
object on 7.x but a bare integer on 6.x. It authenticates with HTTP Basic when
given credentials, an `ApiKey` header when given a key, and neither for an open
cluster.

A PostgreSQL full-text provider is **not** implemented yet.

---

The database-backed cache adapter stores values as JSON, so only JSON-encodable
values can be cached — a value that cannot be encoded raises `ArgumentError`
rather than being silently dropped. The round trip is JSON's, not Dart's: a
`List<String>` comes back as `List<Object?>`. `DVMemoryCacheAdapter` has no
such restriction. Redis/Memcached adapters are **not** implemented yet.

---

## 🤖 AI Providers

`DV.AI` is provider-backed. Configure an adapter once, then use the same typed
surface everywhere:

```dart
DV.AI.configure(AnthropicDVAIAdapter(apiKey: DV.Secrets.get('ANTHROPIC_API_KEY')));

final answer = await DV.AI.chat('Summarize this ledger');
final structured = await DV.AI.structuredOutput(
  'Extract the totals',
  const <String, DVJsonValue>{'type': DVJsonString('object')},
);
```

Shipped adapters and what each service actually serves:

| Adapter | Chat | Embeddings | Structured output | Transcription |
| :--- | :---: | :---: | :---: | :---: |
| `AnthropicDVAIAdapter` | ✅ | ❌ | ✅ | ❌ |
| `OpenAIDVAIAdapter` | ✅ | ✅ | ✅ | ✅ |
| `GeminiDVAIAdapter` | ✅ | ✅ | ✅ | ✅ |
| `OpenRouterDVAIAdapter` | ✅ | ❌ | ✅ | ❌ |
| `OllamaDVAIAdapter` | ✅ | ✅ | ✅ | ❌ |
| `LocalDVAIAdapter` | ✅ | ✅ | ✅ | ✅ |

❌ means the provider has no such endpoint — the call throws `UnsupportedError`
naming the capability rather than returning an empty result. Provider rejections
and payloads Dartvel cannot parse throw `DVAIProviderException` carrying the
status code and response body.

Every adapter takes a `send` transport, so tests drive the exact wire format
without network access:

```dart
final adapter = OpenAIDVAIAdapter(
  apiKey: 'test',
  send: (request) async =>
      const DVAIHttpResponse(statusCode: 200, body: '{"choices":[...]}'),
);
```

`LocalDVAIAdapter` stays the deterministic development/test adapter and is what
`DV.Test.fakeAI()` installs.

### Agents and tool calling

Register a tool with a description and JSON Schema, and the model decides when
to call it:

```dart
DV.AI.registerTool(
  'getWeather',
  (input) => DVJsonString('sunny in ${(input['city']! as DVJsonString).value}'),
  description: 'Look up the current weather for a city.',
  parameters: const <String, DVJsonValue>{
    'type': DVJsonString('object'),
    'properties': DVJsonMap(<String, DVJsonValue>{
      'city': DVJsonMap(<String, DVJsonValue>{'type': DVJsonString('string')}),
    }),
    'required': DVJsonList(<DVJsonValue>[DVJsonString('city')]),
  },
);

final result = await DV.AI.runAgent(
  const DVAIAgentRequest(
    goal: 'What is the weather in Paris?',
    tools: <String>['getWeather'],
  ),
);
result.usedTools; // ['getWeather'] — only tools the model actually called
```

`AnthropicDVAIAdapter` drives the Messages API `tool_use`/`tool_result` loop and
`OpenAIDVAIAdapter` (with `OpenRouterDVAIAdapter`) drives `tool_calls` — the
model selects tools and decides when to stop. `GeminiDVAIAdapter` and
`OllamaDVAIAdapter` use the prompt-based fallback: allowed tools run up front
and their results go into the prompt. The fallback is also used when a request
names no registered tool.

A tool that throws is reported back to the model as an error result so it can
recover, and is left out of `usedTools`. A loop that never settles fails with
`DVAIProviderException` after `maxAgentIterations` (8) model turns rather than
spinning.

---

## 📱 Platform Expo-style Native APIs

Access local hardware or OS APIs using a unified static interface:

```dart
final photoBytes = await DV.Platform.camera.takePhoto();
final location = await DV.Platform.location.getCurrentLocation();
await DV.Platform.haptics.impact();
```

All permissions are centrally managed under the `dartvel` block in `pubspec.yaml`.

**How this compares to Expo.** People looking for "Expo for Flutter" usually
want one of three things, and Dartvel covers them unevenly:

| What Expo gives you | Dartvel today |
| :--- | :--- |
| An all-in-one SDK — auth, push, storage, analytics preconfigured | Covered, and then some: these are framework services rather than a starter template you copy once and maintain forever |
| Over-the-air updates | `dartvel updates release/patch/rollback` drives [Shorebird](https://shorebird.dev), the Flutter code-push framework. The CLI wrapper works; `DV.Updates.check()`/`apply()` has no native binding yet |
| Zero-config cloud builds, certificates and store submission (Expo Launch) | **Not covered.** Dartvel emits GitHub Actions and Codemagic configuration and `dartvel deploy` ships web and function targets, but it does not manage signing certificates or provisioning profiles, and there is no hosted build service |

The third row is the honest gap. If cloud builds and store submission are what
you came for, Expo Launch added Flutter support in 2025 and does that job;
Dartvel is the framework underneath, not the pipeline around it.

---

## 🔗 Links

`DVNavLink` is a link, not a tap handler. That distinction earned itself: the
dartvel.dev header was hand-rolled twice and shipped dead once, because
`onTap: () => DV.Navigation.to(target)` compiles, runs and navigates nowhere —
it builds the callback and never calls it.

```dart
DVNavLink(
  to: DVRoutes.docs,
  child: const DVText('Documentation'),
)
```

A Flutter app is a canvas, so almost nothing a link normally does exists
unless the link does it. Each of these works the same on every platform,
rather than only where the system happens to provide it:

| | |
| :--- | :--- |
| **Navigates** | with its padding as part of the hit area, so a click that looks on-target does not miss |
| **Announces itself** | as a link carrying its destination, not as tappable text |
| **Takes keyboard focus** | and answers Enter, with a focus node you can supply |
| **Middle and modifier click** | open the destination beside this page instead of replacing it |
| **Preloads** | Dartvel pages are deferred, so a hover fetches the bundle the click is about to need — the same work, a few hundred milliseconds earlier |
| **Previews** | a card of the destination on a resting pointer, and on a long press where there is no pointer |

Link previews are the part iOS gives to Safari and nothing gives to anyone
else. Dartvel built the router, so it can build the destination — which is why
this works on a phone, a television and the web alike.

```dart
DVNavLink(
  to: DVRoutes.report,
  preload: DVLinkPreload.immediate,  // none | hover | immediate
  preview: DVLinkPreview.none,       // none | auto
  child: const DVText('Annual report'),
)
```

The preview is a picture of a destination, not the destination: it ignores
pointers, so a stray tap inside cannot activate whatever it is showing.
Preloading is an optimisation, so a failure is reported and swallowed rather
than stopping the tap that follows.

---
