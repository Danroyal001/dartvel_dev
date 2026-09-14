## Unreleased
- **`dartvel db pull --local` prints `@DVModel` suggestions from the drift
  tables, isar collections and sqflite `CREATE TABLE` statements a project
  already has.** Column types map to model field types with nullability kept;
  a column with no model field type is named as not mapped rather than
  dropped. Suggestions are printed and never applied, and no sensitive field
  is guessed: the output says sensitivity was not inferred. `db pull` without
  the flag is unchanged.

- **`dartvel db migrate --plan`, `--dry-run --against snapshot` and
  `--production`.** `--plan` prints the class of every change the migration
  would make -- instant, online or blocking, from the SQLite library the CLI
  links -- and applies nothing, nor creates a database that is not there.
  `--dry-run --against snapshot` rehearses against
  `.dartvel/db/production.snapshot.json` (or `--snapshot <file>`): production's
  provider, server version, columns and row counts, gated as production, and
  exits 1 when the gate would refuse. `--production` refuses a blocking change
  without `--allow-blocking <reason>` (`DV-SCHEMA-002`), and a real run's
  override is appended to `.dartvel/db/schema_overrides.jsonl`; a dry run logs
  nothing. A provider the CLI has no connection to, with no snapshot, has
  nothing to classify its changes with, so against production they need the
  override. `--against` without `--dry-run` or `--plan` is refused rather than
  applied.

- **A string earlier in a file no longer hides a secret read from the
  secrets check.** `dvExtractSecretUses` stripped `//` and `/*` without
  knowing where a Dart string began, so
  `final u = 'https://api.example.com'; DV.Secrets.get('STRIPE_KEY');` lost
  everything after the URL's `//` and the read was never reported. A `/*` in
  a string, such as a glob, hid every read to the end of the file. Raw strings,
  triple-quoted strings, interpolations holding quotes and escaped quotes
  broke it the same way, and an undeclared or backend-scoped secret passed
  DV-SECRETS-001 and DV-SECRETS-002. The check now reads source with the lexer
  module trust uses, moved to `lib/src/analysis/dart_source_lexer.dart`, so
  there is one lexer and not two. It also no longer reports a read written
  inside a string or a nested block comment, it counts `DVSecrets().get(...)`
  as module trust already did, and each finding carries the line of the read.

- **`dartvel inspect adoption` reports what is Dartvel-managed and what is
  not: routes, models, screens and functions.** The managed half is generated
  pages, the graph's models and backend functions. The unmanaged half is host
  `GoRoute` paths, classes annotated `@freezed`, `@JsonSerializable`,
  `@MappableClass` or `@collection` and drift tables, files outside
  `pagesDir` that build a `Scaffold`, and `shelf_router` routes. Each kind
  says how it was counted and what it cannot see, and a route path that could
  not be read is listed as not measured instead of being left out of both
  counts. `--json` emits the same inventory.

- **`dartvel routes` fails on a route both the host router and a page define
  (DV-ADOPT-002), and on a model that already has a generated serializer
  (DV-ADOPT-003).** Both are checked before anything is written. Host routes
  are read from `GoRoute(path: ...)` calls, with nested routes joined to their
  parent, shell routes not prefixing, and parameter names ignored when
  comparing; a path that is not a plain string literal is logged as unchecked
  rather than passed. A model conflicts when `@freezed`, `@JsonSerializable`
  or `@MappableClass` sits anywhere in its annotation stack, or the class
  refers to generated `_$Name` code. Previously `@DVModel()` above
  `@freezed` generated no model at all and said nothing, because the model
  generator's pattern steps over `@pragma` only.


- **`dartvel.memory` reaches the running application, and doctor checks it.**
  The generated client installs the `memory` section and each device
  profile's `platform`, `ram` and `memory` override with `DVMemory.configure`
  at startup, so `DV.Memory.allocate` applies the declared defaults and
  per-target ceilings. A project that declares none generates nothing.
  `dartvel doctor` reports configuration mistakes, fails a device profile
  whose resolved memory budget exceeds its declared `ram`, and warns with
  `DV-MEMORY-004` when `touchPages` is forced on a configured mobile or
  embedded platform.
- **`dartvel init` adds Dartvel to a project that already exists, and is no
  longer an alias of `create`.** As an alias it replaced the adopting
  project's pubspec with the scaffold template. It now inserts the Dartvel
  dependency (`dartvel_core`, plus `dartvel_flutter` for a Flutter
  application) and a `dartvel:` key, and nothing else: every original line,
  comment and blank line is kept, and the edit is refused rather than written
  when it cannot be proven to be insertions only. The plan is printed first
  with a compatibility report -- the SDK constraint against Dartvel's floor,
  and every package the project shares with Dartvel against Dartvel's
  constraint, with a blocked `mix` pin naming the `dartvel_mix` drop-in. A
  check that cannot be made is reported as unchecked, never as compatible.
  `pagesDir` and `backendDir` are written out, and mapped away from
  `lib/pages` or `lib/backend` when the project's own files there would be
  claimed as pages or served as endpoints. `--dry-run` writes nothing;
  applying needs a yes at a terminal or `--yes`, refuses a blocked plan, and
  replaces the pubspec with one rename, refusing if it changed after the plan
  was shown. `create`'s DV-ADOPT-005 refusal now points at `init`.

- **`dartvel docs` builds the application's own reference from the project
  graph.** It covers models and fields (types, relations, policies, generated
  surfaces, and example data built from each field's type), backend functions
  (signature, doc comment and the request lifecycle stages in the order the
  generated backend runs them), the route index (pages, generated model pages,
  mounted module pages), jobs and cron, a policy matrix of resource against
  action, the module map with what each module was granted, and the
  diagnostics glossary from the registry `dartvel explain` reads. Descriptions
  are doc comments, read through each node's source mapping. A sensitive field
  is named, marked and never valued. Decision records under `docs/decisions`
  (or `dartvel.docs.decisions`) link to the nodes they name as
  `` `model:Order` ``, `` `function:checkout` `` and so on, and those nodes
  link back. `DV-DOCS-001` is reported for a name that no longer exists, and
  `DV-DOCS-002` for a node whose mapping no longer holds its declaration.
  `graph.json` in the site is byte-for-byte the graph `dartvel mcp` hands an
  agent. Output is byte-deterministic. `--output`, `--fatal-warnings`, and
  `--serve`, which serves on loopback and rebuilds on change.

- **The project graph marks a sensitive field wherever it sits in its
  annotation stack, and reads a backend function with middleware under its
  annotation.** `@DVModel.sensitiveField(encrypted: true)`, and a sensitive
  field with `@DVModel.searchableField()` under it, were described as ordinary
  fields to `dartvel inspect` and to an agent over `dartvel mcp`. The model
  generator already accepted both. A function with `@DVUseMiddleware` below
  `@DVBackendFunction` was read as an unannotated file named after itself, at
  line 1.

- **Generated output is byte-identical for identical inputs, and
  `dartvel generate --check` fails when it is stale.** Every generated file
  used to open with a wall-clock `// BUILD:` stamp, so every regeneration
  rewrote every file whether or not anything had changed. The stamps are gone.
  The generator version is recorded once, in the
  `lib/dartvel_client/dartvel_client.dart` header. `dvGenBuildId`, which
  `dartvel dev` prints when the backend starts, is now a hash of the generated
  backend routes instead of a time. `--check` regenerates two copies of the
  project in a scratch location and writes nothing into the project. It exits
  non-zero and prints `DV-GEN-001` for each path the generator would change,
  and `DV-GEN-002` for each path that differs between the two copies.

- **`dartvel flags list` and `dartvel flags prune`.** `list` prints every
  declared flag with its type, compiled default, owner, expiry and settle
  mode. `prune` prints the flags past their expiry, each with every
  `file:line` of application code that still reads it — generated output and
  the declarations themselves excluded — or says it has no remaining reads and
  can be deleted outright. The reads are the point: deleting a flag means
  deleting the branches it guards, and a list of due names without them is a
  list of reasons to leave the flags in. `set`, `rollout`, `off` and
  `override` change rules a deployment serves and are not here yet.

- **`@DVFlags()` generates typed `Flags` accessors** into
  `lib/dartvel_client/flags.g.dart`. A flag named by a string can be misspelt,
  and a misspelt flag does not throw — it misses and answers its default for
  ever — so each `@DVFlag` field becomes a `DVFeatureFlag<T>` member carrying
  its key, compiled default, owner, expiry, settle mode and, for an enum, its
  values, with its doc comment. `Flags.all` and `registerDartvelFlags()`
  declare them to the runtime. Refused rather than generated around: a flag
  with no `expires:` or `owner:`, a public `@DVFlags` class, a type a flag
  cannot carry (flags hold `bool`, `String`, `int`, `double` and enums; a
  structure is configuration), an impossible date, and a name declared twice.
  A flag past its expiry is a `DV-FLAGS-004` warning naming its owner.


- **`dartvel create` refuses to scaffold over a project it did not create
  (`DV-ADOPT-005`).** One of its steps replaces `pubspec.yaml` with the
  scaffold template. In an empty directory the file being replaced is the one
  `flutter create` wrote a second earlier, which is the intent. In a directory
  that already holds an application it replaced every dependency, version and
  setting the team had declared — and `init` and `new` are aliases of this
  same command, so the word someone with an existing project reaches for first
  was the destructive one. It announced itself as an information line reading
  "Overwriting pubspec.yaml with Dartvel configuration...". Nothing else in
  the CLI destroys a file it did not write. The check runs before
  `flutter create`, because after that there is no way to tell whose pubspec
  is on disk; a `dartvel:` key marks one the template wrote, and a
  commented-out example does not count as one.

- **`dartvel create` no longer pins a new project to a three-release-old
  `dartvel_shelf`.** The scaffold interpolates a version constant for
  dartvel_core, dartvel_flutter and dartvel_cli, but wrote `dartvel_shelf:
  ^0.3.0` as a literal beside them. A caret on a 0.x version stops at the next
  minor, so every project created since shelf 0.4.0 asked for `>=0.3.0 <0.4.0`
  and resolved a shelf from before most of what the project used existed. It
  is `dartvelShelfVersion` now, bumped by `tool/bump_version.dart` with
  everything else. The test that was supposed to cover this read the list of
  packages the constant feeds rather than the constraints the template writes,
  so the one wrong constraint was the one it could not see; it now reads the
  rendered pubspec.
- The site and the example applications declare the packages they are built
  against. All three said `^0.2.1` -- core, flutter and cli -- and `^0.3.0`
  for shelf, while the packages were at 0.5.0 and 0.6.0. Each resolves through
  `pubspec_overrides.yaml`, so nothing here ever built against the constraint
  and nothing failed; a reader copying the file got a release from before the
  features the application demonstrates. `tool/bump_version.dart` bumps them
  with the packages, and `tool/check_constraints.dart` fails the release if
  any application, or any scaffold constraint, stops admitting what is being
  published.

- `dartvel.windowing.enabled` reaches the runtime. The capability has taken
  the parameter since it was written and no build ever passed one, so a
  project that switched windows off still got them, and a window that
  degraded blamed the target rather than the line that withdrew them
  (`DV-WINDOW-005`).

## 0.5.0

- The package no longer ships `lib/builder.dart`, a build_runner Builder that
  wrote nothing and that no `build.yaml` ever declared, so it could not run
  even if a project asked it to. With it goes the `build` dependency every
  install of the CLI was resolving. Nothing imported it; if you did, the
  replacement is `dart run dartvel_cli:dartvel routes`.
- `dartvel create` no longer scaffolds a `build_runner` setup. Dartvel's code
  generation is `dart run dartvel_cli:dartvel routes`, which `dartvel dev` and
  `dartvel build` run for you, so a new project was resolving and downloading
  a builder it never used -- and being pointed at the retired
  `dartvel_generator` path. Add `build_runner` back yourself if some other
  package's builders need it (`json_serializable`, `freezed`,
  `flutter_vscode`); `dartvel dev` and `dartvel build` still run it when it is
  declared. The scaffolded README now has a "Generating" section naming
  `dartvel routes`.
- A home widget's preview page names itself with a level-1 heading of its
  title when it has no bar to carry one. `dartvel build web` audits every
  page for a level-1 heading, and the preview route rendered the widget and
  nothing else, so every application with a home widget failed its own web
  build on that page. With `showAppBar: true` the bar's title is the heading
  and the body does not repeat it; a widget that builds its own Scaffold is
  left alone, since a heading above one would break its layout.
- Image variants, NextFaster's other half. `dartvel build web` writes every
  raster image declared under `flutter.assets` at each configured width
  narrower than it, into `assets/_dartvel/img/<width>/`, and hands the
  application what it wrote as `DARTVEL_IMAGES`: `DVImageView` then asks for
  the width its slot needs on this screen. Never wider than the image, and
  never a width that was not written, so no variant is a 404. A GIF is left
  out, since resizing keeps one frame of an animation. Nor is a variant ever
  a bigger download than its source: re-encoding can undo compression the
  source already had -- the example's 1200-wide PNG came out larger at 1080
  -- and then the source's own bytes are written at that width instead.
- `dartvel.images` in pubspec.yaml: `widths`, `quality` and `remoteHosts`.
  A web-server build carries it into dartvel_routes.json for the server's
  `/_dartvel/image`, which resizes images from those hosts and no others.
- The semantics capture reads the slot each image was laid out in, from the
  page, and the prefetch manifest carries it. A link can then prefetch the
  variant for the visitor's pixel ratio rather than the build's. Those
  images stay out of a page's head, because which file a visitor needs
  depends on a screen the head cannot know.
- A web-server build marks guarded routes `"guarded": true` in
  dartvel_routes.json, from the router's own list, and carries
  `dartvel.web.server.streaming: shell` into the manifest. The server needs
  both to send a route's head before its data: a guarded route's answer
  depends on the request, so it is the one kind of route that must not be
  sent early.
- Pages are split out of main.dart.js on the web. Every page was imported
  `deferred`, but the generator copied each private page's body into the
  router, which is eager, so dart2js found all of it reachable from `main()`:
  the site built with three of its four pages having no deferred part at all
  (`deferredLibraryParts:{p0:[],p1:[],p2:[0],p3:[]}`). A lowered body now goes
  into `lib/dartvel_client/pages/<page>.g.dart`, which only the router's
  deferred import reaches, and every page gets parts of its own that
  `loadLibrary()` fetches.
- The service worker precaches those parts. A page's code used to be in
  main.dart.js, which every visit caches; once it is in a part, a page never
  opened online would fail to load offline.
- Each prerendered page names its own code and first-frame images in its
  head. dart2js writes which part files each deferred import loads into
  main.dart.js; `dartvel build web` reads that table with the generated
  router and adds a `<link rel="preload">` for the page's parts, so a page
  opened directly downloads them alongside main.dart.js instead of a round
  trip after it boots. The semantics capture now also records the images each
  page fetches while it renders, which are preloaded the same way -- as
  `fetch` with `crossorigin` for the bytes Flutter reads, since a preload
  requested any other way is not reused and the image downloads twice.
- The same lists are written to `dartvel_prefetch.json`, which a link reads to
  prefetch a page's images before the visitor gets there.
- A launch splash on every platform, from `dartvel.splash`, with nothing to
  install and nothing to run. The files `flutter create` writes open every
  application on white -- Android's launch theme, iOS's launch storyboard,
  and on the web a blank page for as long as main.dart.js takes -- and macOS
  on black. `dartvel build` now writes the colour and an optional image into
  each: the web shell and so every prerendered page, Android's launch
  background plus the API 31 splash that ignores it, the iOS storyboard with
  a dark-mode colour set, the macOS view and the Linux view. With nothing
  configured the colour is `dartvel.pwa.backgroundColor`, the image the
  project icon, and dark mode gets `#121212` rather than white. On the web
  the splash sits under Flutter's view, so the application covers it the
  moment it paints, and it is hidden with scripting off, where the page's
  content is the noscript block. A launch file somebody designed is left
  alone unless `dartvel.splash.overwrite` is set; Windows needs nothing,
  since its runner shows the window only on the first frame.
- `@DVClientCron` schedules run while a page is on screen rather than from the
  moment the router is created. The timer they started there had no owner:
  it was never stopped, creating a second router started a second one so
  every schedule ran twice, and a widget test that built the router ended
  with it still running -- which is why eight of the example's tests failed.
- Generated code passes the analyzer a Flutter project runs, where an info is
  a failure. Three things in it did not, in any application that used them:
  an AI tool's schema with `const` on one value and not its siblings, a
  redundant `const` in the sitemap entries, and a route target named after a
  page directory with an underscore in it.
- **A route's typed target is lowerCamelCase: `/next_shift` is
  `DVRoutes.nextShift`.** It was `DVRoutes.next_shift`, which Dart's style
  lint rejects. The old name is still generated, as a deprecated alias for
  the new one, so code written against it keeps compiling; it goes in the
  next minor release.
- The renderer starts downloading while the page parses. CanvasKit is 7 MB
  and nothing asked for it until flutter_bootstrap.js had arrived and run;
  index.html, and so every prerendered page, now preconnects to gstatic and
  preloads the CanvasKit files itself. The variant is chosen with the
  loader's own test -- the smaller `chromium` build where Blink has
  ImageDecoder and the ICU break iterators -- and each file is requested the
  way the loader requests it, so in Chrome both are fetched once and the
  loader takes them from the preload. No hints are written for a `--wasm`
  build or a loader told where CanvasKit is or which variant to use, since a
  hint for the wrong file is 7 MB for nothing.
- A web-server build writes `dartvel_prefetch.json` too, keyed by route
  pattern -- parameterised ones included, which the static build cannot
  serve -- so the server can name each route's own deferred parts and images
  in the head it sends. The shell is left alone: it is served for every
  route, and one route's list written into it would be wrong for all the
  others.
- `dartvel preview` streams `shell` as the deployed server does: the head,
  with the route's own parts, before the data; a guarded route waits and
  keeps its status; a record found hidden after the flush is a noindex page.
  It had only the older split, head after the data, so a developer
  previewing `shell` watched every page wait on the resolver and deployed
  something that behaved differently.

## 0.4.1

Fixes two faults the published 0.4.0 carried.

- The 0.4.0 binary reported itself as 0.3.2. `dartvel --version` prints a
  constant that no pubspec mentions, and the bump to 0.4.0 missed it. Because
  `dartvel update` compares the same constant with the latest release, every
  0.4.0 install offered itself 0.4.0 as an update, installed it, and offered
  it again.
- `dartvel create` wrote `^0.2.1` for dartvel_core, dartvel_flutter and
  dartvel_cli, and has since 0.3.0. A caret on a 0.x version stops at the next
  minor, so every new project resolved Dartvel 0.2.x. It writes `^0.4.0` now.
  **A project created with 0.3.x or 0.4.0 still says `^0.2.1`; change those
  three constraints to `^0.4.0` by hand.**
- Both versions are now moved by the release tooling and checked by the gate
  that runs before publishing, so a mismatch stops the publish itself.
- Headless Chrome is one shared copy per machine, in the user cache, instead of
  one per project under `.dart_tool`. A build already in the shared cache is
  reused whichever puppeteer release pins which, so projects resolving
  different puppeteer versions no longer each download their own 380 MB
  browser.

## 0.4.0

- `dartvel build android` writes the Activity, the capture provider and the
  permissions an application declares under `dartvel.android.permissions`,
  plus the two permissions the framework binds whether or not a project asked:
  `VIBRATE` and `USE_BIOMETRIC`. Both are normal permissions, granted at
  install with no dialog, which is exactly why their absence was invisible --
  the application ran, the binding was registered, and the call threw where
  nobody was looking.
- Only normal permissions are ever added on a project's behalf. A dangerous
  one would put a question in front of its users that its author never wrote,
  and there is a test asserting `BLUETOOTH_CONNECT`, `CAMERA`,
  `READ_CONTACTS`, `ACCESS_FINE_LOCATION` and `POST_NOTIFICATIONS` never
  appear in a manifest that asked for nothing.
- `dartvel db migrate` runs the statements it prints. It used to print a line
  per model, say they were synced successfully, and execute nothing at all.
  For Postgres or MySQL it writes the statements out and says it did not run
  them, because the CLI has no connection to a managed database.
- Declared middleware runs. Ten of the nineteen keys now reach the generated
  router in the order declared; the annotation previously had one reader, a
  check that the name was spelled correctly, which then dropped the list.

## 0.3.2

- Corrected the constraints on sibling Dartvel packages, which named the
  previous release rather than the one published alongside them. A caret on a
  0.x version stops at the next minor, so `dartvel_core: ^0.2.1` excluded the
  0.3.1 published beside it -- a user installing the 0.3.1 set resolved 0.2.x
  for every sibling and got none of what that release contained. `dart pub
  publish --dry-run` could not see it, because it resolves against
  pubspec_overrides.yaml and every sibling points at a local path.

## 0.3.1

- `dartvel update` fetches the latest published binary and replaces the running
  one, verifying its checksum first and keeping the old binary alongside. A
  no-op when already current.
- `@DVFunctionalWidget` generates a widget class rather than a function, so a
  generated component can be const and can reach a BuildContext without every
  caller threading one.
- Lowered page and widget bodies carry the imports they were written against,
  and a body that reaches for a private symbol is refused with a message naming
  it rather than emitting generated code that does not compile.

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
through the application's own resolvers. `@DVModel(generatePublicPages: true)`
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
