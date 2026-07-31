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

**Recently implemented.** These were specified with no code behind them and
now have runtime implementations and tests:

| Surface | Status |
| :--- | :--- |
| `DV.lifecycle.app` / `.build`, `context.lifecycle.*` | ✅ Read-only enum signals |
| `DV.Modules.<id>` | ✅ Registry, per-module lifecycle, mount-point independence |
| `DV.transaction(...)`, `context.afterCommit`, `context.compensate` | ✅ Reverse-order compensation, nesting, isolation |
| `@DVStaticPaths()` | ✅ Discovered during generation and exported by the generated client barrel |
| `DVModelPageDataMode` | ✅ Drives generated `Model.Page.async/.signal/.fromId` renderers |
| `@DVModel(generatePublicPages: true)` | ✅ Emits static-path manifest entries and DB-backed `Model.publicStaticPaths()` resolvers |
| `DV.AI` provider adapters | ✅ Real HTTP adapters for Claude, OpenAI, Gemini, OpenRouter, and Ollama |

**Implemented, but not equally mature.** The feature table below marks each
area. Anything flagged ⚠️ Scaffold has an API surface and prebuilt pieces, but
provider integrations are incomplete — expect to fill gaps yourself.

**Still maturing:** generated public model pages and static paths now exist,
but every target must still be verified through `docs/build-targets.md` before
claiming production readiness for that target.

**Build targets** are individually verified with evidence in
[docs/build-targets.md](docs/build-targets.md); four of them can only be built
on hosts this project does not develop on, one TV target is blocked upstream,
and one is not yet demonstrated.

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
| **UI Primitives** | `DVBox`, `DVText`, and fluent styling built on `Mix` | ✅ Implemented |
| **Routing** | File-based pages router with strongly-typed navigation targets, generated onto `go_router` | ✅ Implemented |
| **State Management** | Riverpod-powered signals (`context.signal`, reactive models, `DV.global`) | ✅ Implemented |
| **Models & Forms** | `@DVModel` annotation + `DVForm<T>` automatic & manual controls | ✅ Implemented |
| **Backend Runtime** | Axum/Tokio Rust server calling Dart FFI, supporting SSE streams | ✅ Implemented |
| **Platform APIs** | Runtime platform/screen detection; camera, location, haptics, etc. are scaffolded pending native plugins | ⚠️ Partial |
| **Authentication** | API surface and prebuilt pages; provider integrations are not complete | ⚠️ Scaffold |
| **Database & Cache** | Real SQLite adapter (file + in-memory, WAL); Postgres/MySQL/Redis adapters are not complete | ⚠️ Partial |
| **PWA & SEO** | Automatic PWA manifest/worker & runtime/global SEO injection | ✅ Implemented |
| **AI Integration** | HTTP adapters for Claude, OpenAI, Gemini, OpenRouter, and Ollama, plus the deterministic local adapter | ✅ Implemented |
| **Sensitive Fields** | `@DVModel.sensitiveField()` redacts fields from public serialization, cards, logs, and AI context | ✅ Implemented |
| **Lifecycle Signals** | Read-only enum signals: `DV.lifecycle.app`/`.build`, `context.lifecycle.page`/`.request`/`.transaction` | ✅ Implemented |
| **Modules** | `DV.Modules.<id>` registry with per-module lifecycle and mount-point independence | ✅ Implemented |
| **Reversible Transactions** | `DV.transaction(...)` with `context.afterCommit(...)` and `context.compensate(...)` | ✅ Implemented |
| **Build Targets** | Mobile, web, desktop, plus TV/embedded via vendor embedders, with toolchain preflight and auto-install | ⚠️ Partial — see [table](#-build-targets) |

---

## 🛠️ CLI Commands

Manage the full-stack lifecycle directly with the Dartvel CLI:

```bash
# Project initialization
dartvel new [name]
dartvel init
dartvel doctor
dartvel doctor --target tizen      # check one target's toolchain

# Development
dartvel dev
dartvel watch
hotreload

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
```

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
| `web`, `linux`, `android`, `fireos` | ✅ Build, artifacts verified |
| `windows`, `macos`, `ios`, `tvos` | ⏭️ Need their own host — [run in CI](.github/workflows/platform-build-matrix.yml) |
| `tizen` / `tpk` | ✅ Signed 9.3MB TPK containing the engine and assets |
| `sony-elinux` | ❌ Blocked — the embedder's newest Flutter ships Dart 3.7.2, below Dartvel's ≥3.9 floor |
| `webos` | ⚠️ Embedder installs; a real build is not yet demonstrated |
| `vscode` | ✅ Builds — verified extension host JS and Flutter webview artifacts |

Flutter has **no desktop cross-compilation** — Windows needs Windows, the Apple targets need macOS. `dartvel build` skips what the host cannot build instead of failing the whole run.

**→ Full detail, evidence, and per-target setup: [docs/build-targets.md](docs/build-targets.md)**

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
| `tizen` | [Danroyal001/flutter-tizen](https://github.com/Danroyal001/flutter-tizen) | [flutter-tizen/flutter-tizen](https://github.com/flutter-tizen/flutter-tizen) | Samsung |
| `sony-elinux` | [Danroyal001/flutter-elinux](https://github.com/Danroyal001/flutter-elinux) | [sony/flutter-elinux](https://github.com/sony/flutter-elinux) | Sony |
| `webos` | [Danroyal001/flutter-webos](https://github.com/Danroyal001/flutter-webos) | [lg-flutter-webos/flutter-webos](https://github.com/lg-flutter-webos/flutter-webos) | LG |
| `vscode` | [Danroyal001/flutter-vscode](https://github.com/Danroyal001/flutter-vscode) | [SlowGen/flutter_vscode](https://github.com/SlowGen/flutter_vscode) | VS Code |

These embedders download a *vendor-built* Flutter engine per version, so a target can lag behind Dartvel's Flutter — and a version-pin bump alone cannot fix that. For Sony eLinux the binding constraint is the opposite direction and worth stating precisely: the embedder's Flutter is too **old** for Dartvel's own dependency floor. Details and evidence are in [docs/build-targets.md](docs/build-targets.md).

---

## 📦 Getting Started

### 1. Project Initialization
```bash
dartvel init my_app
cd my_app
dartvel dev
```

### 2. Declare Reactive Models
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

### 3. Build Safe Reactive Forms
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

### 4. Create FFI Backend Functions
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

Postgres, MySQL, MongoDB, Turso, ClickHouse and BigQuery adapters are **not**
implemented yet.

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
