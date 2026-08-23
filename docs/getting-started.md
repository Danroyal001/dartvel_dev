# Getting started

Every command on this page was run against a fresh project before it was
written. Where something is unfinished, it says so rather than being left out.

Dartvel is **alpha**. Read [the alpha section of the README](../README.md) for
what that means before building anything you have to keep.

---

## Prerequisites

- **Flutter 3.44.5 or newer, with Dart ≥ 3.12.** One floor, declared by every
  Dartvel package. It comes from `dartvel_mix`, Dartvel's fork of `mix`.

  Parts of Dartvel would resolve on an older Dart — the backend packages only
  need 3.9, which is what `code_assets` requires — but declaring that
  separately is how a target gets measured against the wrong number, so
  Dartvel declares one. If your Dart is below 3.12, `pub get` says so directly
  instead of failing later on a transitive package you did not choose.
- **Rust and `cbindgen`** if you want the native backend runtime. Without them
  the native asset build skips with a message and the rest still works.
- Platform toolchains only for the platforms you build. `dartvel doctor`
  reports what is missing before you need it.

---

## Create a project

```bash
dartvel create --name hello_dartvel
```

`init` and `new` are aliases for the same command. Useful flags:

| Flag | Default | Effect |
|---|---|---|
| `--name` | prompted | Project name |
| `--org` | `com.example` | Organisation domain |
| `--[no-]web` | on | Include web |
| `--[no-]mobile` | on | Include Android and iOS |
| `--[no-]desktop` | off | Include Linux, macOS, Windows |
| `--[no-]ssr` | — | Enable SSR/SSG features |

It scaffolds a Flutter project, replaces `pubspec.yaml` with Dartvel
configuration, writes `.env` and `.env.example`, and runs `flutter pub get`.

## What you get

```text
lib/
  main.dart
  pages/
    index.dart
    index.loading.dart
    index.error.dart
  models/
  backend/
    functions/
      health.get.dart
      contact.dart
  components/
```

Configuration lives in `pubspec.yaml` under `dartvel:`:

```yaml
dartvel:
  backendHost: 0.0.0.0
  backendPort: 3000
  devBackendHost: http://localhost:3000
  prodBackendHost: https://api.hello-dartvel.com
  pagesDir: lib/pages
  backendDir: lib/backend
```

`pagesDir` and `backendDir` are defaults, not requirements — point them
elsewhere and generation follows.

---

## Generate

```bash
dartvel routes
```

This writes `lib/dartvel_client/`: the router, the typed backend client,
configuration, environment access, and generated model helpers.

**Generated output is not meant to be committed.** The scaffold's `.gitignore`
excludes it. Anyone cloning your project runs generation before the app will
compile — including your CI.

`dartvel build <target>` runs generation for you, so `routes` is only needed
when you want the client refreshed without a build.

---

## Add a page

Routing is file-based. Create `lib/pages/about.dart`:

```dart
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/widgets.dart';

@DVPage(title: 'About')
Widget _aboutPage(BuildContext context) => DVBox.list([
      DVText('About this app'),
    ]);
```

Run `dartvel routes` and `/about` exists.

Three rules that will otherwise cost you an afternoon:

- **The annotated function is private.** `_aboutPage`, not `aboutPage`.
  Dartvel generates the public API from it, and a public annotated input is a
  hard error with a rename message.
- **It must be expression-bodied** while body lowering is still being built.
  For a larger page, keep the annotated input as an expression and put the body
  in a public helper — which is exactly what the generated `index.dart` does:

  ```dart
  @DVPage(title: 'Dartvel')
  Widget _indexPage(BuildContext context) => buildIndexPage(context);

  Widget buildIndexPage(BuildContext context) { ... }
  ```

- **Do not build a `Scaffold`.** `@DVPage` owns the page shell. Put
  `showAppBar`, `title`, `centerTitle` and the rest on the annotation.

Dynamic segments come from the filename: `lib/pages/users/[id].dart` becomes
`/users/:id`.

---

## Add a model

```dart
@DVModel()
class _User {
  final String slug;
  final String name;
  final bool published;

  const _User({
    required this.slug,
    required this.name,
    required this.published,
  });
}
```

Private again, and for the same reason: `_User` generates the public `User`,
and application code uses `User` — never `_User`.

That gives you `User.Form(...)`, `User.List(...)`, `User.Table(...)` and
`User.Page(...)`, plus schema, CRUD, validation, serialization and equality.

---

## Add a backend function

`lib/backend/functions/greet.get.dart`:

```dart
@DVBackendFunction()
Future<String> _getGreeting(String name) async => 'Hello, $name';
```

Call it from anywhere — frontend or backend — as `getGreeting(name)`. The
filename decides the route; the annotation decides the rest.

Same two rules: private input, expression body.

---

## Run and build

```bash
dartvel dev                 # development server
dartvel build web
dartvel build linux
dartvel doctor --target macos
```

`dartvel build` checks host support and toolchains **before** doing any
generation work, and skips a target the host cannot build rather than failing
the whole run. Missing tools are named; Dartvel offers to install the ones it
can fetch unattended and prints instructions for the licence-gated ones — it
will never silently install Xcode, Visual Studio, the Android SDK or Tizen
Studio.

Per-target status, evidence, and setup: [build-targets.md](build-targets.md).

---

## Import one thing

```dart
import 'package:hello_dartvel/dartvel_client/dartvel_client.dart';
```

That barrel exports Dartvel core, the Flutter primitives, generated functions,
routes, configuration, environment access and model helpers. Import it rather
than the generated files beside it — those are implementation detail and their
names are not a stable surface.

---

## What is not finished

Being specific, because a getting-started guide that oversells is worse than
none:

- **Twelve of sixteen build targets produce a verified artifact. One — `linux`
  — is verified by actually running.** An inspected artifact proves the build
  compiles and links, not that the application starts.
- **webOS and Sony eLinux are blocked.** Both embedders ship a Dart below
  `mix`'s floor. That is ours to fix by re-pinning the forks, not a vendor
  limit.
- **Fuchsia** builds the Flutter bundle and stages the app; its fork needs a
  build-only entry point.
- **Block-bodied annotated inputs are not supported yet.** Expression bodies
  and a public helper, as above.
- **Terminal rendering** resolves its targets and selects backends, but the
  terminal backend itself is not built.
- **HTTP/3 is implemented and verified against a live server**, alongside
  HTTP/2. Early Hints arrive over HTTP/2 only — no Rust crate surfaces 1xx
  responses over HTTP/3, which is a crate gap rather than a protocol limit.
- Several provider integrations are partial. `docs/spec-status.json` records
  every specification section with what is present and what is absent, and
  `dart run tool/spec_status_check.dart` fails if a claim cites evidence that
  does not exist.

---

## Where to look next

| | |
|---|---|
| Per-target build status and evidence | [build-targets.md](build-targets.md) |
| Outbound HTTP, protocols, early hints | [http-transport.md](http-transport.md) |
| The full design specification | [../NEW_SPEC.md](../NEW_SPEC.md) |
| What is built, per spec section | `docs/spec-status.json` |

`NEW_SPEC.md` is a **design specification, not a description of what ships
today**. Where it and the code disagree, the code wins.
