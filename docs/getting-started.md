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

An application serving more than one customer configures tenancy in the same
place:

```yaml
dartvel:
  tenancy:
    isolation: shared-database   # or schema-per-tenant, database-per-tenant
    source: subdomain            # or header, path-prefix, query-parameter
    header: X-Tenant             # when source is header
    queryParameter: tenant       # when source is query-parameter
    ignoredHostLabels: [www]     # www.example.com is the site, not a tenant
    require: true                # refuse a request that names no tenant
```

Every key is optional and the defaults are the ones above. A value Dartvel
does not implement fails the build rather than being ignored: a misspelled
`isolation` left on the floor would run the shared-database default while the
pubspec says otherwise, and every query would still return rows.

Under `database-per-tenant` the application also has to say how to open one
tenant's database, with `DV.Database.configureTenantDatabases(...)`, since the
build cannot know. Which models carry a tenant is per model, with
`@DVModel(tenantScoped: true)` — a table deliberately shared between tenants,
a currency list or a country table, would be broken by a predicate it never
asked for.

Every platform shows something before an application's first frame, and the
files `flutter create` writes make it white. `dartvel build` writes a splash
instead, with nothing configured, and this is how to say what it looks like:

```yaml
dartvel:
  splash:
    color: "#0A0D13"            # default: pwa.backgroundColor, then #FFFFFF
    darkColor: "#0A0D13"        # default: color if one is declared, then #121212
    image: assets/splash.png    # default: the project icon, if it has one
    darkImage: assets/splash-dark.png
    imageWidth: 120             # logical pixels; default reads the image as 4x
    android12Image: assets/a12.png  # Android 12+ draws this in its own splash
    overwrite: false            # replace a launch screen designed by hand
    enabled: true
```

Images are PNG. On the web the splash is in `index.html` and in every
prerendered page, painted before any script runs and removed on the first
frame. On Android it is the launch background and the Android 12 splash; on
iOS the launch storyboard; on macOS the view's colour until it draws. Dartvel
replaces those files only while they are still Flutter's templates or carry
its `dartvel:splash` marker, so a launch screen you designed stays yours
unless `overwrite` says otherwise. Per-target detail is in
[build-targets.md](build-targets.md#launch-splash).

On the web, `DVImageView` fetches an image at the width its slot needs, the
way a `srcset` does: its laid-out width times the screen's pixel ratio,
snapped to a fixed set of widths, so a phone downloads the 640-pixel file
rather than the 3840. And a link that preloads a page prefetches that same
file for the visitor's screen.

```yaml
dartvel:
  images:
    widths: [640, 750, 828, 1080, 1200, 1920, 2048, 3840]  # default: Next.js's, plus 16 to 384
    quality: 75                  # JPEG quality, 1 to 100
    remoteHosts:                 # a web server resizes images from these, and only these
      - cdn.example.com
      - "*.images.example.net"   # its subdomains, not images.example.net itself
```

`dartvel build web` writes every raster image declared under
`flutter.assets` at each of those widths narrower than the image, into
`assets/_dartvel/img/<width>/`, so a static host needs no server to serve
them; an image narrower than a slot is used as it is, never enlarged. A
`dartvel build web-server` also answers `/_dartvel/image?src=&w=&q=`, which
resizes an image from one of the `remoteHosts` on its first request and keeps
it. The limits are deliberate:

- A width outside the list is refused, so the number of files per image is
  the length of the list, and nobody else chooses how much resizing the
  server does.
- A host not in `remoteHosts` is refused before anything is fetched, and a
  redirect from an allowed one is not followed. An endpoint that fetches any
  address it is given reaches whatever the server can reach.
- WebP only replaces PNG. The encoder writes lossless WebP, which is smaller
  than a PNG and larger than a JPEG of a photograph, so a JPEG stays a JPEG.
  A GIF is served as it is: resizing it would keep one frame of an animation.
- A static build has no server, so a remote image there is fetched as it is.
- Only `DVImageView` does this. `Image.asset` and `Image.network` fetch what
  they are given.

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
- **Terminal rendering** resolves targets, selects backends and negotiates
  launch, but the `dartvel_cli_flt` embedder is not built, so
  `dartvel build linux-cli` skips with a message naming what is missing.
  `dartvel doctor --target linux-cli` reports the same thing. It does not fall
  back to a desktop build — a `-cli` binary that contained a GUI would be the
  opposite of what the suffix promises.
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
