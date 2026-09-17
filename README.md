# Dartvel

> **Flutter's Laravel.**
>
> A batteries-included, AI-native, full-stack platform for building Flutter applications.

---

## ⚠️ Alpha status: read this first

Dartvel is an **alpha**. It is usable and much of it is real, but it is not
finished, and this section exists so you can tell the difference without
reading the source.

**[NEW_SPEC.md](NEW_SPEC.md) is a design specification.** It describes where
Dartvel is going. Where the spec or this README disagrees with the code, the
code wins.

**Published**, and installable three ways. See
[Getting Started](#-getting-started).

[dartvel.dev](https://dartvel.dev) is built with Dartvel, which is the reason
several of its worst bugs are fixed: Flutter's hash URLs silently sent every
deep link to `/`, the semantics tree was never built so no crawler and no
screen reader saw anything, and links tore the document down and rebuilt the
whole application instead of routing. None of those show up in a unit test.

**Status lives in one file, and a tool checks it.**
[`docs/spec-status.json`](docs/spec-status.json) records every spec section
with two labels: how much its public surface can still move (`Draft` or
`Contract`) and how much is built (`Designed`, `Partial` or `Shipped`). A
partial section says what is missing. `dart run tool/spec_status_check.dart`
fails when a section claims to be built and the evidence it names does not
exist, and `dartvel spec status` prints the summary. This README does not
repeat the totals, because a count copied by hand is wrong a week later.

The feature table below uses the same labels. ⚠️ Partial means there is an API
and working pieces, with gaps the index names. 📐 Designed means the contract
is settled and nothing is built behind it yet.

**How "verified" is used here.** A target marked ✅ in
[docs/build-targets.md](docs/build-targets.md) had its build run and its
artifact inspected. That proves it compiles and links. It does not prove the
application starts, so most targets go further: the
[runtime verification workflow](.github/workflows/runtime-verification.yml)
launches the app on every push and photographs what it drew: Linux, Linux in a
terminal, the web, Android on an emulator, macOS, iOS and tvOS on simulators,
Windows, Sony eLinux on a virtual device, and both browser extensions. The
web-server build is started and asked for each route. A capture is checked for
*pixels*. Every job used to end at `test -s capture.png`, which a blank screen
satisfies: a crash before the first frame still writes a full-size image of
one colour.

webOS runs in a Wayland window on ARM under emulation in its own workflow. Its
engine is a 32-bit ARM build Google does not publish, so Dartvel builds it
from source. It has not been run on a television. Fuchsia is blocked on its
engine, which does not build at Flutter 3.44.5: four attempts are recorded,
and the last matches the embedder fork's own invocation and still fails on a
Dart VM thread-local linked into a shared library. Tizen and VS Code build and
have not been run.

If you hit something that claims to work and does not, that is a bug in these
docs as much as in the code. Please report it.

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
| **UI Primitives** | `DVBox`, `DVText`, `DVNavLink`, and fluent styling through `DVModifier` | ✅ Shipped |
| **Routing** | File-based pages with strongly-typed navigation targets, generated onto `go_router`. Path URLs on the web, and `DVNavLink` for links that preload and preview | ✅ Shipped |
| **State Management** | Riverpod-powered signals (`context.signal`, reactive models, `DV.global`) | ✅ Shipped |
| **Models & Forms** | `@DVModel` generates schema, CRUD, validation, serialization, `User.Form(...)`, `User.Table(...)` and `User.Page(...)` | ✅ Shipped |
| **Record History** | Versioned writes refused on conflict, opt-in history with revert, soft delete and restore on generated models. No Studio history view or scheduled retention yet | ⚠️ Partial |
| **Offline-First Models** | `DVOfflineStore`: local writes, an ordered mutation log replayed on reconnect, dead letters. `@DVModel(offline:)` is not generated yet, so it is wired by hand | ⚠️ Partial |
| **Backend Runtime** | Axum/Tokio Rust server calling Dart over FFI, with SSE streams | ✅ Shipped |
| **Platform APIs** | `DV.Platform` through `dart:ffi` and jnigen, never platform channels. Coverage differs a lot per target and iOS binds the fewest; `dart tool/binding_coverage.dart` counts it from the source | ⚠️ Partial |
| **Authentication** | Local provider with salted password hashes, OAuth2 (PKCE) presets for Google, GitHub, GitLab, Bitbucket and Microsoft, LDAP, SAML 2.0, passkeys (WebAuthn) and Sign-In with Ethereum | ✅ Shipped |
| **Sessions & Second Factor** | Hashed session tokens rotated at every privilege change, device lists and revocation, TOTP with recovery codes, served by the generated backend. No passkey second factor or per-tenant MFA policy yet | ⚠️ Partial |
| **Outbound HTTP** | `DV.Http` with declared hosts, retries, a per-host circuit breaker and test fakes. A native client speaks HTTP/2 and HTTP/3 ([details](docs/http-transport.md)). No provider adapters use `DV.Http` yet | ⚠️ Partial |
| **Outbound Webhooks** | `DVWebhooks`: durable deliveries on queues, HMAC signing with key rotation, private-address refusal on every hop, dead letters. Subscriptions are not generated models yet | ⚠️ Partial |
| **Database** | SQLite (file and in-memory, WAL), PostgreSQL and MySQL, each on its own wire protocol, with TLS on both network engines | ✅ Shipped |
| **Queues & Jobs** | `@DVJob` with typed dispatch and handlers on seven adapters: in-memory, database, Redis, SQS, RabbitMQ, Pub/Sub and Kafka. The four hosted ones are tested in CI against a real broker. No delayed jobs, backoff schedule or uniqueness keys yet | ⚠️ Partial |
| **Cache** | Memory, database, Redis, Memcached and multi-node distributed adapters, with tags and revalidation | ✅ Shipped |
| **File Storage** | Memory, S3 and S3-compatible stores (R2, MinIO), Azure Blob and Google Cloud Storage. No local disk adapter or streaming put and get yet | ⚠️ Partial |
| **Notifications** | SMTP and HTTP mail (Resend, SendGrid, Postmark, Mailgun, SES), FCM, APNS over HTTP/2, Web Push (RFC 8291/8292) and Twilio SMS. No bounce webhooks, attachments or durable inbox yet | ⚠️ Partial |
| **Search** | SQLite FTS5, PostgreSQL full-text, Meilisearch, Algolia and OpenSearch/Elasticsearch behind one provider contract | ✅ Shipped |
| **Semantic Search** | `DVSemanticIndex`: embeddings queued on save, keyword, semantic and hybrid modes, tenant scoping pushed into the vector query. The index is wired by hand and the only vector adapter is in-memory | ⚠️ Partial |
| **SEO** | `dartvel build web` writes head tags, JSON-LD, per-route HTML from the semantics tree, `sitemap.xml` and `robots.txt` | ✅ Shipped |
| **PWA** | Manifest, icons, a service worker that precaches routes and replays writes made offline (tested in a real Chrome on every push), an offline page, and `DV.Platform.install` | ✅ Shipped |
| **AI Integration** | Adapters for Claude, OpenAI, Gemini, OpenRouter and Ollama plus a deterministic local one, structured output, tool calling and agents | ✅ Shipped |
| **Feature Flags** | Typed flags from `@DVFlags`, percentage and targeted rollout, `dartvel flags list` and `prune`. Nothing publishes rules per environment yet | ⚠️ Partial |
| **OTA Updates** | `dartvel updates release`, `patch` and `rollback` over Shorebird, or into a patch source your own web-server binary hosts. Patches apply on Android; iOS is not proven | ⚠️ Partial |
| **Crash Reporting** | Crashes written by the handler and sent on the next launch, breadcrumbs, fingerprints, release health. No native signal or JVM handlers yet | ⚠️ Partial |
| **Usage Metering** | Per-tenant counters and gauges with limits, billing periods and reporting to a billing provider. No `@DVMeter` generation or CLI yet | ⚠️ Partial |
| **Observability** | Prometheus metrics on `/metrics`, real health checks on `/health`, W3C Trace Context with sampling decided from the trace id. There is no log sink and no OTLP exporter | ⚠️ Partial |
| **Sensitive Fields** | `@DVModel.sensitiveField()` keeps fields out of public serialization, logs and AI context; `encrypted: true` adds AES-256-GCM at rest on the generated model's own read and write path | ⚠️ Partial |
| **Lifecycle Signals** | Read-only enum signals: `DV.lifecycle.app`/`.build`, `context.lifecycle.page`/`.request`/`.transaction`. Some states are not emitted yet | ⚠️ Partial |
| **Modules** | `DV.Modules.<id>` with modules mounted at build time, their pages, backend functions, cron and tables merged into the parent | ⚠️ Partial |
| **Reversible Transactions** | `DV.transaction(...)` with `context.afterCommit(...)` and `context.compensate(...)` | ✅ Shipped |
| **Scheduling** | `@DVBackendCron` and `@DVClientCron`, a cron evaluator, and database leases so one process runs each occurrence. No per-target capability report yet | ⚠️ Partial |
| **Testing** | `dartvel test` with unit, e2e, golden, native, accessibility and release modes; generated model factories with sequences | ✅ Shipped |
| **Deployment** | `dartvel build web-server` makes one executable with the backend, the web app and Studio. `dartvel deploy` ships to Firebase, Vercel, Netlify and Cloudflare, or writes a per-function artifact | ✅ Shipped |
| **Dartvel Studio** | The admin dashboard and visual page editor. The web-server binary serves it at `/__studio`: always in a development build, and in a release build only when `dartvel.admin.enabled` is set | ✅ Shipped |
| **Development Builds** | `dartvel dev` pairs with a `--profile development` build over TLS and hot reloads it on save, on Android, iOS, macOS, Linux and Windows | ⚠️ Partial |
| **Dartvel Cloud** | The CLI side of hosted builds and store deploys (`--cloud`). The hosted service has not launched | ⚠️ Partial |
| **Data Workflows** | CSV, NDJSON and Excel import and export, resumable chunked imports on queues, scheduled reports. No PDF export | ⚠️ Partial |
| **Secrets** | Declared under `dartvel.secrets`, with `DV-SECRETS-001` failing a build that reaches a backend secret from client code, and the application key held in the Windows, macOS, Android and iOS key stores. No Vault or KMS adapters | ⚠️ Partial |
| **i18n** | CLDR plural rules, typed translation keys, route locale negotiation, and `dartvel i18n extract`/`check` over ARB catalogues | ✅ Shipped |
| **Accessibility** | Contrast and tap-target checks, `DVTable` keyboard navigation, switch control, and a release gate in `dartvel build web` that audits the semantics tree a real browser produced | ✅ Shipped |
| **Terminal Rendering** | `-cli`/`-tui` targets, build-time backend selection, terminal size and graphics detection. The renderer lives in the `dartvel_cli_flt` fork, which a build needs installed | ⚠️ Partial |
| **Multi-Window** | A window is a route and `open()` never fails. Real OS windows open on Linux through `dartvel_windowing`; elsewhere `DV.Window` degrades and reports a stable code | ⚠️ Partial |
| **Kiosk Mode** | Policies validated by `dartvel doctor`, the idle and reset clock, and hardware-key blocking on Linux | ⚠️ Partial |
| **Build Targets** | Mobile, web, desktop, TV and embedded through vendor embedders, with toolchain preflight and auto-install | ⚠️ Partial, see [Build Targets](#-build-targets) |

---

## 🛠️ CLI Commands

A selection. `dartvel --help` lists every command and `dartvel help <command>`
explains one.

```bash
# Start a project
dartvel create my_app              # alias: new
dartvel init                       # add Dartvel to an existing Flutter project
dartvel doctor
dartvel doctor --target tizen      # check one target's toolchain

# Develop: generation, hot reload, backend, native runtime, device pairing
dartvel dev                        # aliases: run, start

# Build (see Build Targets below)
dartvel build [platform]
dartvel build web-server
dartvel build ios --profile development
dartvel build android --cloud      # on Dartvel Cloud, once it launches

# Studio access on a deployed web-server binary
dartvel admin grant <user-id> --database dartvel_data/data.db
dartvel admin revoke <user-id> --database dartvel_data/data.db
dartvel admin list --database dartvel_data/data.db

# Over-the-air updates
dartvel updates release
dartvel updates patch
dartvel updates rollback --release-version 1.2.0 --patch-number 3

# Stores and deployment
dartvel deploy --store play        # also: appstore, testflight, firebase-app-distribution
dartvel deploy --provider vercel    # also: firebase-hosting, netlify, cloudflare

# Database
dartvel db migrate
dartvel db push
dartvel db pull
dartvel db seed

# Generators
dartvel routes                     # regenerate the client without a build
dartvel generate page
dartvel generate model
dartvel generate backend-function
dartvel generate form

# Look around
dartvel inspect routes             # also: models, functions, jobs
dartvel spec status                # what is built, per spec section
dartvel flags list
dartvel explain DV-WINDOW-004      # what a diagnostic code means
dartvel explain DV-KIOSK           # every code in a family
```

Dartvel degrades rather than throwing where a target cannot do what was asked.
A phone has no second window, and a web popup outside a user gesture is
blocked. Every degradation carries a stable code that keeps its meaning between
releases, and `dartvel explain` is how you read one without searching the
specification by hand.

---

## 🎯 Build Targets

```bash
dartvel build              # every target this host can build
dartvel build web
dartvel build web-server   # one executable: backend, web app and Studio
dartvel build android --profile development   # a build dartvel dev can pair with
dartvel build tizen        # alias: dartvel build tpk
dartvel build sony-elinux --format iso        # also: sony-elinux-iso, sony-elinux-img
dartvel build webos
dartvel build tvos --simulator   # the only unsigned tvOS build
dartvel build linux-cli    # the terminal backend and no GUI code
dartvel build vscode       # VS Code extension host + Flutter webview
```

A short version of [docs/build-targets.md](docs/build-targets.md), which has
the evidence for every row. "Runs" means the application was launched and
what it drew was checked, usually on every push.

| Target | Status |
| :--- | :--- |
| `linux`, `web`, `android`, `macos`, `ios`, `windows` | ✅ Build and run in CI (emulator and simulator for the mobile targets) |
| `web-server` | ✅ Builds and runs on the host it is built on: linux-x64, linux-arm64, macos-arm64, macos-x64, windows-x64 and windows-arm64, each verified in CI |
| `tvos` | ✅ Builds and runs on a simulator in debug. Signed device builds are not verified |
| `sony-elinux` | ✅ Builds and runs on a virtual device, debug and release |
| `chrome-extension`, `firefox-extension` | ✅ Build and run, loaded in the real browser |
| `linux-cli` | ✅ Runs in a pty in CI, with the terminal embedder built there. Locally the build needs `dartvel_cli_flt` installed |
| `webos` | ✅ Runs in a Wayland window on ARM under emulation. Not run on a television |
| `fireos` | ✅ Builds (the Android toolchain) |
| `tizen` / `tpk` | ✅ Builds a signed TPK where Tizen Studio is installed. CI can only check that it skips, since the SDK is licence-gated |
| `vscode` | ✅ Builds. Not run |
| `fuchsia` | ❌ Blocked: the Fuchsia embedder engine does not build at Flutter 3.44.5 |

Flutter has **no desktop cross-compilation**. Windows needs Windows, and the
Apple targets need macOS. `dartvel build` skips what the host cannot build
instead of failing the whole run, and the
[CI matrix](.github/workflows/platform-build-matrix.yml) covers the hosts a
development machine does not have.

**New here? [docs/getting-started.md](docs/getting-started.md)** walks through
a project, a page, a model and a backend function.

### Toolchain preflight

Before building, Dartvel checks that the host supports the target and that the required tools are installed. Missing tools are named, and Dartvel offers to install what it safely can:

```bash
dartvel build tizen                      # asks before installing
dartvel build tizen --auto-install       # installs without asking
dartvel build tizen --no-auto-install    # never installs; fail instead
dartvel doctor --target tizen            # just check
```

Under CI (`CI=true`, `GITHUB_ACTIONS`, and friends) it installs unattended, so a pipeline never hangs on a prompt. Anything installed mid-run is added to `PATH` immediately, so the build that installed a toolchain can use it.

Dartvel auto-installs the embedders (from its forks), the webOS `ares` CLI, and Linux desktop dependencies. It deliberately does **not** auto-install licence-gated or multi-gigabyte vendor SDKs (Xcode, Visual Studio, the Android SDK, Tizen Studio) and prints instructions for those instead.

### Embedder forks

Embedded, TV and terminal targets run through a dedicated Flutter embedder, never plain `flutter build`. Dartvel forks each one so it can be pinned and patched against the Flutter version Dartvel ships:

| Target | Embedder fork | Upstream | Vendor |
| :--- | :--- | :--- | :--- |
| `tizen` | [Danroyal001/dartvel_tizen](https://github.com/Danroyal001/dartvel_tizen) | [flutter-tizen/flutter-tizen](https://github.com/flutter-tizen/flutter-tizen) | Samsung |
| `sony-elinux` | [Danroyal001/dartvel_elinux](https://github.com/Danroyal001/dartvel_elinux) | [sony/flutter-elinux](https://github.com/sony/flutter-elinux) | Sony |
| `webos` | [Danroyal001/dartvel_webos](https://github.com/Danroyal001/dartvel_webos) | [lg-flutter-webos/flutter-webos](https://github.com/lg-flutter-webos/flutter-webos) | LG |
| `fuchsia` | [Danroyal001/dartvel_fuchsia](https://github.com/Danroyal001/dartvel_fuchsia) | [fuchsia/flutter-embedder](https://fuchsia.googlesource.com/flutter-embedder/) | Fuchsia |
| `vscode` | [Danroyal001/dartvel_vscode](https://github.com/Danroyal001/dartvel_vscode) | [SlowGen/flutter_vscode](https://github.com/SlowGen/flutter_vscode) | VS Code |
| `tvos` | [Danroyal001/dartvel_tvos](https://github.com/Danroyal001/dartvel_tvos) | [fluttertv/flutter-tvos](https://github.com/fluttertv/flutter-tvos) | Apple TV (community) |
| `<desktop>-cli` | [Danroyal001/dartvel_cli_flt](https://github.com/Danroyal001/dartvel_cli_flt) | [jiahaog/flt](https://github.com/jiahaog/flt) | Terminal (community) |

Vendor embedders download a prebuilt Flutter engine per version, so a target
can lag behind Dartvel's Flutter, and bumping a version pin cannot fix that.
The webOS and eLinux release engines are built from source for this reason. An
embedder's Flutter can also be too old for Dartvel's floor of Dart 3.12 and
Flutter 3.44. Details are in [docs/build-targets.md](docs/build-targets.md).

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
  dartvel_dev: ^0.5.0
```

Or the pieces directly, where you want only some of them:
[`dartvel_core`](https://pub.dev/packages/dartvel_core) (models, database,
cache, queues, auth, notifications, AI),
[`dartvel_flutter`](https://pub.dev/packages/dartvel_flutter) (UI, routing,
signals, native platform APIs),
[`dartvel_shelf`](https://pub.dev/packages/dartvel_shelf) (the Rust runtime),
[`dartvel_cli`](https://pub.dev/packages/dartvel_cli) (generation, build,
dev server, deploy). Every package needs Dart 3.12 and Flutter 3.44 or newer.

To add Dartvel to a Flutter project you already have, run `dartvel init`. It
adds the dependency and the `dartvel:` key and nothing else.

### 3. Start it

```bash
dartvel create my_app
cd my_app
dartvel dev
```

`dartvel dev` runs generation, the Flutter app and the backend together, and
reloads only what changed: a page edit hot-reloads Flutter, a backend edit
restarts the server, a Rust edit rebuilds the native library. It also prints a
QR code for [development builds](#-development-builds-and-pairing) on your
phone.

Generation is the CLI's job. `dartvel dev` and `dartvel build` run it first,
and `dartvel routes` runs it alone. It writes the client under
`lib/dartvel_client/`, and application code imports that one barrel.

### 4. Add a page

Routing is file-based. `lib/pages/about.dart` is served at `/about`:

```dart
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'About us')
Widget _aboutPage(BuildContext context) => const DVBox.list(<Widget>[
      DVText('About us'),
      DVText('We make tools for Flutter teams.'),
    ]);
```

The annotated function is private. Dartvel generates the public route from it.

### 5. Declare a model

```dart
// lib/models/article.dart
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Article {
  final String slug;
  final String title;
  final bool published;

  const _Article({
    required this.slug,
    required this.title,
    required this.published,
  });
}
```

`_Article` generates the public `Article`, with its table, CRUD, validation,
serialization and widgets. Application code uses `Article`:

```dart
final Article article = Article(slug: 'hello-world', title: 'Hello', published: false);
await article.save();
final Article? found = await Article.find('hello-world');

Widget editor(Article article) =>
    Article.Form(article, (Article edited) => edited.save());
Widget table(List<Article> articles) => Article.Table(articles);
```

### 6. Write a backend function

```dart
// lib/backend/functions/hello.get.dart is served at GET /api/hello.
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<Map<String, Object?>> _hello(String name) async =>
    <String, Object?>{'greeting': 'Hello, $name'};
```

The file name sets the route and the HTTP method. The Axum server calls the
function over FFI, and the generated client calls it by name from anywhere in
the app:

```dart
final Map<String, Object?> greeting = await hello(name: 'Ada');
```

---

## 🖥️ One binary: web-server and Studio

`dartvel build web-server` writes `build/server`, a single executable that
carries the backend, the native server library and the web app. It runs on
the operating system and CPU it was built on, so build on the kind of machine
you deploy to, then copy it there and start it:

```bash
dartvel build web-server
scp build/server host:/srv/my_app/
ssh host 'cd /srv/my_app && DARTVEL_PORT=8080 ./server'
```

With no `DATABASE_URL` it creates a SQLite database in `dartvel_data/` beside
itself on the first run, with a table per model, and reuses it after that.
`DARTVEL_DATA_DIR` moves that directory. Pages are rendered on request, with
the head, structured data and crawler-visible text generated from each page's
data.

The binary also carries Studio at `/__studio` (`dartvel.admin.path` moves
it): the page builder, a table of each model's records with an edit form, the
build's routes, functions and jobs, and the list of Studio grants. The build
compiles it with Flutter alongside the web app, and it reads and writes through
the binary's own database. A development build serves it with no
configuration. A release build includes it only when `pubspec.yaml` asks:

```yaml
dartvel:
  admin:
    enabled: true
```

Even then it opens only for a signed-in person allowed the `Studio.access`
action, and by default nobody is. Grants live in the application's own
database, so you give them on the server:

```bash
dartvel admin grant user_123 --database dartvel_data/data.db
dartvel admin list --database dartvel_data/data.db
dartvel admin revoke user_123 --database dartvel_data/data.db
```

Hosts: `dartvel_shelf` ships its native library for linux-x64, linux-arm64,
macos-arm64, macos-x64, windows-x64 and windows-arm64, and CI builds the binary
on each one, copies it alone into an empty directory and checks that it serves
a page, writes to the SQLite file it creates and keeps that across a restart.
On Windows the file is `build/server.exe`. There is no cross-building: a Linux
arm64 server needs a binary built on Linux arm64.

Limits today: the macOS binary has only the ad-hoc signature `dart compile exe`
gives it, and a copy downloaded through a browser has not been tried.
PostgreSQL and MySQL are not migrated automatically on start.

---

## 📲 Development builds and pairing

There is no separate dev-client app to install. A development build is an
ordinary build with a profile:

```bash
dartvel build android --profile development   # also ios, macos, linux, windows
```

That is a Flutter debug build carrying Dartvel's pairing code. `dartvel dev`
always serves pairing: it prints a QR code, and a development build that scans
it connects over TLS, checks that the server holds the key from the link, and
hot reloads on every save. Each run of `dartvel dev` uses a fresh key and token.
The pairing port defaults to 8787 (`--pairing-port`).

`dartvel deploy --store` refuses a development build for Play's alpha, beta and
production tracks and for the App Store. Play internal testing, TestFlight and
Firebase accept one.

CI pairs, edits and hot reloads on an Android emulator, an iOS simulator, and
Linux, macOS and Windows desktops.

---

## 🚚 Over-the-air updates

`dartvel updates` drives [Shorebird](https://shorebird.dev), the Flutter code
push tool, and `DV.Updates.check()` and `apply()` call its updater over FFI in
the running app.

```bash
dartvel updates release --platform android
dartvel updates patch --platform android
dartvel updates rollback --release-version 1.2.0 --patch-number 3
```

Patches do not have to go through Shorebird's service. With `--patch-source`,
releases and patches are published into a patch source your own web-server
binary serves, and no Shorebird account is needed:

```bash
export DARTVEL_UPDATES_TOKEN=...   # the token the server was started with
dartvel updates patch --patch-source https://app.example.com/
```

CI releases the example this way, patches it into its running web-server
binary, and checks that an Android emulator picks the patch up after a
relaunch. `--patch-source` is Android only for now, and applying a patch on
iOS has not been proven, because it needs a physical device and a signing
team.

---

## ☁️ Dartvel Cloud

Dartvel Cloud runs builds and store uploads on machines Dartvel operates, so
a TV, device, browser or editor build does not need that vendor's SDK on your
desk, and an iOS build does not need a Mac. The CLI side is in this
repository:

```bash
export DARTVEL_CLOUD_TOKEN=...
dartvel key cloud android-keystore ./upload.jks   # keep a signing credential there
dartvel key cloud                      # list them by name, never by value
dartvel build tizen --cloud            # a signed TPK, without Tizen Studio here
dartvel build sony-elinux --cloud      # an eLinux release bundle
dartvel build tvos --cloud --simulator # an Apple TV app, on a macOS worker
dartvel build vscode --cloud           # a VS Code extension and its web build
dartvel build android --cloud          # streams the log, downloads to build/cloud/android
dartvel deploy --store play --cloud    # builds an App Bundle in release and uploads it
```

Built end to end in CI against the service and a worker: Android, Fire OS,
iOS, tvOS (simulator), Tizen, Sony eLinux, `linux-cli`, and Chrome, Firefox
and VS Code extensions. macOS, Windows, Linux, web and web-server are accepted
and not yet run end to end. webOS and Fuchsia are not on Cloud, because their
embedders ship a Dart below Dartvel's floor and no local build finishes either.
[docs/build-targets.md](docs/build-targets.md#dartvel-cloud) has what each
came back as.

Every cloud build is paid; there is no free tier for builds. Plans open when the
hosted service launches ([dartvel.dev/cloud](https://dartvel.dev/cloud#plans));
until then the `--cloud` flags have no service to talk to. Building on your own
machines and hosting your own web-server binary stay free.

---

## 🔒 Authentication

Sign-in methods, prebuilt pages, and server-side sessions:

```dart
// Sign in
await DV.Auth.signInWithEmailAndPassword(email: email, password: password);
await DV.Auth.signInWithProvider('google');
await DV.Auth.signInWithPasskey();
await DV.Auth.signInWithWeb3();

// Prebuilt pages
DV.Auth.SignInWithEmailAndPasswordPage();
DV.Auth.SignInWithProviderPage();
DV.Auth.SignInWithPasskeyPage();
```

An account with a second factor stops halfway through sign-in and asks for a
code. TOTP enrollment, recovery codes and device sessions are on `DV.Auth` too:

```dart
try {
  await DV.Auth.signInWithEmailAndPassword(email: email, password: password);
} on DVMfaRequired {
  await DV.Auth.completeSecondFactor(code: await askForCode());
}

final DVTotpEnrollment enrollment = await DV.Auth.enrollTotp();
await DV.Auth.confirmTotp(await askForCode());

final List<DVSession> sessions = await DV.Auth.sessions();
await DV.Auth.revoke(sessions.last.id);   // sign one device out
await DV.Auth.revokeOthers();             // every device but this one
```

Session tokens are stored only as hashes and replaced at every privilege
change. A browser gets a `__Host-` cookie and a native client gets a bearer
token. Passkeys as a second factor and per-tenant MFA policy are not built yet.

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

`DVMemcachedCacheAdapter` is available beside the Redis one. The database
adapter stores values as JSON, so a value that cannot be encoded raises
`ArgumentError`, and a `List<String>` comes back as `List<Object?>`.
`DVMemoryCacheAdapter` keeps the Dart object and has neither restriction.

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
DV.FileStorage.configure(S3FileStorageAdapter(
  bucket: 'assets',
  region: 'us-east-1',
  credentials: DVAwsCredentials(
    accessKeyId: env.awsKeyId,
    secretAccessKey: env.awsSecret,
  ),
  endpoint: Uri.https('minio.internal:9000'),   // optional; R2/MinIO
));

await DV.FileStorage.put('avatar.png', bytes, contentType: 'image/png');
final keys = await DV.FileStorage.list(prefix: 'avatars/');
```

Path-style addressing (`{endpoint}/{bucket}/{key}`) is the default because R2
and MinIO require it; pass `usePathStyle: false` for virtual-hosted AWS
buckets. A missing object reports `DVFileStorageException.isNotFound` rather
than a generic failure, and deleting an object that is already gone succeeds.

`AzureBlobFileStorageAdapter` and `GcsFileStorageAdapter` cover Azure Blob
Storage and Google Cloud Storage. CI runs them against Azurite and
fake-gcs-server, the emulators for each.

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

`DVPostgresSearchProvider` uses PostgreSQL's own full-text engine over a
table you name, so the index lives in the database and cannot go stale
relative to its rows.

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

## 📱 Platform: Expo-style native APIs

Hardware and OS APIs sit behind one static interface:

```dart
final photoBytes = await DV.Platform.camera.takePhoto();
final coordinates = await DV.Platform.location.getCoordinates();
await DV.Platform.haptics.impact();
```

Each call goes to a binding registered through `dart:ffi` or jnigen. On a target
with no binding for a call, the call throws a "not registered" error. How many
calls each target binds varies a lot, and `dart tool/binding_coverage.dart`
counts them. Android permissions are declared under `dartvel.android.permissions` in
`pubspec.yaml`.

**How this compares to Expo.** People looking for "Expo for Flutter" usually
want some of these:

| What Expo gives you | Dartvel today |
| :--- | :--- |
| An all-in-one SDK with auth, push, storage and analytics set up | Framework services you configure in `pubspec.yaml` and code. Nothing is copied into your project to maintain |
| Over-the-air updates | `dartvel updates` over Shorebird, with `DV.Updates` bound over FFI and an optional self-hosted patch source. Proven on Android; see [Over-the-air updates](#-over-the-air-updates) |
| Development builds | `--profile development` builds that pair with `dartvel dev` by QR code. See [Development builds](#-development-builds-and-pairing) |
| Cloud builds, credentials and store submission (EAS) | The CLI for [Dartvel Cloud](#-dartvel-cloud) is built and the hosted service has not launched. Locally, `dartvel deploy --store` hands the upload for Play, the App Store, TestFlight or Firebase to that store's own tool |

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
