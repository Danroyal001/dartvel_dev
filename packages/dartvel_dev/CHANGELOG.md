## 0.13.10 — 2026-10-21

- Linux video, cameras and screens through GStreamer: frames drawn into Flutter, webcams and capture cards (`DVCameraDevice`, `DVBox.camera(device:)`), each display as a screen (`DVCameraLens.screen`; also the web's `getDisplayMedia`), JPEG photos and MP4 recording; the first audio output or microphone that opens.
- `DVWidgetRecorder` and `DVBox.recorded`: record part of the screen to MP4 or stream it over RTMP. `loop:` on media boxes; one camera or player shared by several boxes.
- `dartvel.startRoutes` (the page an installed target opens on); the build shows the generator's error; `dartvel_windowing` builds for the web, with `showInWindowDialog`.


## 0.13.9 — 2026-10-20

- Ordinary pages carry request-time data in their first document: export `dartvelRoutePageData` (route pattern -> resolver) from `lib/backend/page_data/index.dart`; `DVPageData.document` holds typed headings, paragraphs and links (`DVDocumentBlock`), escaped, with unsafe link schemes written as text. The file may not import Flutter (`DV-PAGE-010`).
- A backend function returning a model, or a model holding models, encodes (`dvToEncodable`); the server registers the application's models at startup. Before, `jsonEncode` failed on the generated extension `toJson`.


## 0.13.8 — 2026-10-20

- CSV import reads what export writes: a quoted value keeps its commas, quotes and line breaks (`dvParseCsv`, `dvSplitCsvRecords`), and resumable CSV chunks are cut by record. An app's own `exportCsv` file with a note like "first, second" could not be imported back.
- Fields typed `List<T>`, `Map<String, T>` or another model are rebuilt from JSON element by element (nested models through their own parser) instead of a cast that threw on decoded JSON.


## 0.13.7 — 2026-10-18

- `DVModifier.maxWidth`/`maxHeight` hold inside a column that stretches its children: the bounded box sits at the start edge instead of being forced to the full width (a lead paragraph capped at 680 ran 1,270 pixels). Under loose constraints nothing changes; `.centered()` still centres.
- `@DVBoot` bodies are lowered outside `abstract final class DV`, into a top-level `_dvBootSteps` list, so an app name that matches one of DV's statics (`Session`) resolves to the app's own.


## 0.13.6 — 2026-10-17

- `DVIconButton` is removed: an icon-only control is `DVBox(Icon(...), DVModifier().tooltip(...).onTap(...))`, with `.minimumTapTarget(width: 48, height: 48)` for touch. It stretched to fill whatever held it (an eye icon filled a password field).
- `DVAuthAppearance.frameBuilder` draws an app's own sign-in screen around the framework form; `signInTitle`/`signUpTitle`; `dartvel.auth.forgotPassword` links the sign-in form to the app's reset page; narrow screens show the brand.
- `DVBox.row` honours an explicit `crossAlign: .stretch`; an unset row still centres.


## 0.13.5 — 2026-10-17

- `@DVBoot` runs in every entry its code can run in: the app, and the web server, worker and cron processes, through one runner in dartvel_core (`DVBootStep`, `dvRunBoot`). A hook in a file that imports Flutter stays in the app; naming `server` from one is refused (`DV-RUN-008`).

## 0.13.4 — 2026-10-17

- Generation copies enums only from `lib/models` files that declare a data model; another file there keeps its own enums, so importing it beside the barrel compiles again.
- The prebuilt auth pages show a `dartvel.pwa.icon` (or `dartvel.auth.heroImage`) from the `web/` folder on the web, instead of a silent 404 on `/assets/web/...`.

## 0.13.3 — 2026-10-17

- An `@DVAppRoot` may wrap the project's own `@DVFunctionalWidget` (the application entry imports the generated widgets).

## 0.13.2 — 2026-10-15

- Dartvel 0.13.2: `generatePages`, always-visible page scrollbars.

## 0.13.1 — 2026-10-15

- Dartvel 0.13.1: host routing rewritten; pages keep their own descriptions.

## 0.13.0 — 2026-10-15

- Dartvel 0.13.0: one-line `DV.run(args)` entry, middleware fields, typed backend functions, conventions checks, host routing.

## 0.12.2 — 2026-10-14

- Released alongside dartvel_core, dartvel_flutter and dartvel_cli 0.12.2: the password eye everywhere, form fields in server-rendered HTML, private `/metrics`, and site pages read from a web-server binary.

## 0.12.1 — 2026-10-14

- Released alongside dartvel_cli 0.12.1 (model field defaults survive reads and migrations); no changes in this package.

## 0.12.0

- Released with the rest of Dartvel 0.12.0; see the repository CHANGELOG.

## 0.11.5

- Version alignment with Dartvel 0.11.5.

## 0.11.4 — 2026-10-08

- Resolve the matching 0.11.4 Dartvel package family.

## 0.11.3 — 2026-10-08

- Resolve the matching 0.11.3 Dartvel package family.

## 0.11.2 — 2026-10-07

- Resolve the matching 0.11.2 Dartvel package family.

## 0.11.1 — 2026-10-05

- Resolve the matching 0.11.1 Dartvel package family.

## 0.11.0 — 2026-10-05

- Resolve the matching 0.11.0 core, Flutter, shelf and CLI package family.

## 0.10.0 — 2026-10-02

- Released with dartvel_core, dartvel_shelf, dartvel_flutter and dartvel_cli
  0.10.0, and dartvel_generator 1.4.3. No code changes in this package.

## 0.9.3

- Released with dartvel_core, dartvel_flutter and dartvel_cli 0.9.3, and
  dartvel_shelf 0.9.2: Studio lists every page and designs data models,
  upstream Shelf adapter (`fromShelf`), native WebSockets with event-driven
  delivery, response body backpressure, and native static file streaming.
  The constraints on its siblings move with them.

## 0.9.2

- Released with dartvel_core, dartvel_flutter and dartvel_cli 0.9.2: the web
  page shows its text and a loading bar before Flutter starts, a DV loading
  bar for page loads and `DV.progress`, and Dartvel pages in a host on
  auto_route or Flutter's Navigator. The constraints on its siblings move
  with them.

## 0.9.1

- Released with dartvel_core, dartvel_shelf, dartvel_flutter and dartvel_cli
  0.9.1: Studio's own sign-in, and one page renderer for both web targets.

## 0.9.0

- Released with dartvel_core, dartvel_flutter and dartvel_cli 0.9.0: module
  sources reach more platforms through a carrier per target, and
  `DVBox.threePane`. The constraints on its siblings move with them.

## 0.8.0

- Released with dartvel_core, dartvel_flutter and dartvel_cli 0.8.0: links to
  headings, password managers on the auth pages, `dartvel add` for Dart,
  npm, C, Rust, WebAssembly, JVM and Apple sources, and the Studio formula
  bar and command palette. The constraints on its siblings move with them.

## 0.7.1

- Released with dartvel_flutter 0.7.1, which fixes Esc on a web page; no
  changes in this package.

## 0.7.0

- **`dartvel_database.dart` exports the cache adapters again.** It showed
  `DVCacheAdapter`, `DVMemoryCacheAdapter` and `DVDatabaseCacheAdapter` from
  dartvel_flutter, which had stopped exporting two of them, so publishing
  warned `undefined_shown_name` and an import of this entrypoint could not
  reach them. dartvel_flutter exports every adapter now, for
  `DV.Cache.withAdapter`, and this entrypoint shows `DVCache`, `DVCacheView`
  and all five adapters.

- **Breaking: the SDK floor is Dart 3.13.0 and Flutter 3.47.0.** Dart 3.13
  is the first release with primary constructors
  (`class Point(final int x, final int y);`), which the `dartvel create`
  scaffold, the samples and generated data models are written with; on Dart
  3.12 they are a compile error. Flutter 3.47.0 is the first stable release
  that ships Dart 3.13.0. Raise `environment: sdk:` to `">=3.13.0 <4.0.0"`
  and upgrade Flutter before taking this release.

## 0.6.2

- Documentation only: install the CLI with `dart pub global activate
  dartvel_cli` first, then Homebrew, the release binaries, dev_dependencies
  and npm.

## 0.6.1

- Declares the platforms it supports in pubspec.yaml, so pub.dev lists
  them instead of inferring them from platform-specific imports. No code
  changes.

## 0.6.0

- Tracks dartvel_core, dartvel_flutter and dartvel_cli 0.6.0 and
  dartvel_shelf 0.7.0. See their changelogs; several changes are breaking.

## 0.5.0

Ships the 0.5.0 CLI: link prefetch, per-page deferred bundles, image variants,
the launch splash, shell-first web-server streaming, and the retirement of the
build_runner generation path. Raises its floor to dartvel_cli 0.5.0.

## 0.4.1

Raises its floor to dartvel_cli 0.4.1, so an install can no longer resolve the
0.4.0 CLI that reported itself as 0.3.2 and offered itself as an update for
ever. The `^0.4.0` it declared would already admit 0.4.1; this makes 0.4.1 the
least it will accept.

## 0.4.0

Follows the 0.4.0 set, depending on each sibling with a caret constraint on
the version published beside it.

The 0.4.0 entry here first said this package pins its siblings exactly. It
does not: the constraints are carets, as they are for every package in the
set. Corrected in 0.4.1.

## 0.3.2

- Corrected the constraints on sibling Dartvel packages, which named the
  previous release rather than the one published alongside them. A caret on a
  0.x version stops at the next minor, so `dartvel_core: ^0.2.1` excluded the
  0.3.1 published beside it -- a user installing the 0.3.1 set resolved 0.2.x
  for every sibling and got none of what that release contained. `dart pub
  publish --dry-run` could not see it, because it resolves against
  pubspec_overrides.yaml and every sibling points at a local path.

## 0.3.1

- Ships the 0.3.1 CLI, which adds `dartvel update`.

## 0.3.0

Four queue brokers, both network databases reachable over TLS, static
generation that produces pages, and a page that can have a body.

### Queues, on real brokers

Seven adapters now: in-memory, database, Redis, SQS, RabbitMQ, Pub/Sub and
Kafka. The four that talk to a network service are verified in CI against the
real thing -- ElasticMQ, RabbitMQ's own image, Google's emulator and Apache
Kafka -- rather than against a fake that agrees with whatever the adapter does.

That distinction found nine bugs which every unit test had passed: a backoff
sent as an initial delay, an AMQP channel limit above the server's,
delivery-mode written to the wrong bit, publishes returning before the broker
had them, a payloadType that would have stopped every handler matching, a Fetch
reply parsed with three fewer fields than it has, offset commits sent to a
broker that was not the group's coordinator, and a first coordinator lookup
that is always refused and always retriable.

Each adapter is written around what its service actually offers. SQS and
Pub/Sub refuse `pending` rather than returning an empty list, because an empty
list reads as "there is nothing" when the truth is "I cannot see". Kafka is a
log, so it has no dead letters, no priority and no out-of-order retry, and
`lag` gives the honest version of a backlog: a distance, not a list.

### Databases

PostgreSQL and MySQL both negotiate TLS, which is what a managed endpoint
requires -- Aurora, Neon, Supabase, PlanetScale and Cloud SQL all demand it and
most refuse plaintext, so before this the adapters reached localhost and
nothing else. `sslMode` takes libpq's names, so a connection string copied from
a provider's console pastes in unchanged.

A refusal is fatal at `require` and above. Falling back would put the password
on the wire in the clear while the caller believed the connection was
encrypted.

### Pages can have bodies

A private `@DVPage` input had to be a single expression, so every page needing
a local, a loop or a condition was written as a one-line wrapper around a
public helper. Block bodies are lowered into the generated widget now.

`@DVFunctionalWidget` and `@DVBackendFunction` still require expression bodies.

### Static generation

`dartvel build web` writes a page per route and expands parameterised routes
through the application's own resolvers. `@DVModel(generatePages: true)`
now generates the route as well as the paths -- it previously produced a list
of addresses that all resolved to the application's own not-found page.

A page no route serves is refused rather than written.

### The web output

Crawler-visible HTML is built from the page's semantics tree rather than from
string literals in the source, so it carries real headings, anchors and
landmarks instead of one paragraph per source line. Pages gained structured
data, a stylesheet for `sitemap.xml`, and an `.htaccess` that path URLs need
and that nothing was writing.

In-app links push the route instead of tearing the document down and rebuilding
the whole application, which is what a real anchor in the semantics tree does
by default.

## 0.2.1

- First published release.

Dartvel's packages are published under the `dartvel_dev` name on pub.dev.
`dartvel` was taken on 2026-08-06 by an unrelated package, so the published
identifier carries a suffix while the command stays `dartvel`.
