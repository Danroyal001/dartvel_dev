# Changelog

All notable changes to this project will be documented in this file.

Dartvel is pre-1.0. Minor versions may contain breaking changes; breaking
changes are called out explicitly below.

## Unreleased

- Navigator 2.0: `dartvelNavigator2_0Routes(at:, onLocationChanged:)` returns
  every Dartvel route as `DVNavigatorRoute` entries to spread into an app's own
  route table, with `dvNavigatorPages(location, table)` for its RouterDelegate.
  Replaces the per-location `dartvelPages` and `dartvelPageFor` (removed).
- Every link has a preview: parameter routes preview the concrete path with its
  parameters, and guarded pages and config routes preview a sign-in card with
  their public title instead of building the protected page.
- `dartvel create` and `dartvel init` are one command: in an existing project
  both adopt it (plan first, `--dry-run`/`--yes`, nothing overwritten); where
  there is no project both create one. `create` no longer refuses.

- Billing: subscription lifecycle on Stripe and Paddle: change plan (with or without proration),
  cancel now or at period end, pause, resume, status, and a customer-portal link, each acting on the
  customer's current subscription.
- Every form is now a keyboard form with nothing added: Tab walks the fields and controls in draw order, Enter moves to the next field and submits from the last one, and every `.onTap()`/`.onPressed()` control is a focusable button with a visible focus ring and a screen-reader name. A refused save is announced in a live region, written under the field it names, and given the focus.
- `DVVisibilityToggle` (sealed: `eye`, `none`, `custom(builder)`) for password/sensitive field visibility toggles. `.input(obscureText: true)` gets the eye by default; `.none` turns it off and `.custom(builder)` replaces it.

## 0.10.0 — 2026-10-02

Packages: dartvel_core, dartvel_shelf, dartvel_flutter, dartvel_cli and
dartvel_dev 0.10.0; dartvel_generator 1.4.3 (constraint only).

### Highlights

- **Studio is part of the application** (details below), and it passes the
  browser check on a real web-server build: sign-in by keyboard, every screen
  server-rendered with its own address, back and forward, deep links, Ctrl+F,
  text selection and copy, Tab order, screen-reader labels, Enter submits the
  sign-in, and no page errors.
- **Typing keys reach text fields on every Dartvel page.** Space, Enter, the
  arrows, Home and End were taken by the page before a focused field saw them,
  so Enter did not submit forms. Fixed in `dartvel_flutter`.
- **Studio:** reusable components in free Studio with an Insert panel, the
  canvas draws a page exactly as the site does, the app's own splash while
  Studio loads, Figma/Bubble/Power Apps keyboard shortcuts, and syncing
  Studio's changes to the repository (file writes in `dartvel dev`, bundled in
  builds, GitHub pull request or push).
- **Sensitive model fields are write-only inputs**, like a password field, in
  `Model.Form()` and Studio's record form.
- **Dartvel Preview**, the app that opens a `dartvel dev` project on a device,
  first slice; `dartvel preview` folds into `dartvel dev --release` and
  `dartvel deploy --preview`.
- **`@DVBackendFunction(aiTool: DVAITool(...))`** makes a backend function an
  AI tool without exposing every backend function.
- **Keyboard shortcuts** (`DVShortcutScope`) and interactive link previews.
- Docs: a `/docs/platform` page for `DV.Platform`, adopting Dartvel in an
  existing native app, and the accepted Server State (`initServerState`)
  design in the spec.

### Deprecated (no breakage)

- `dartvel.webPrerender` is ignored with a warning; it never did anything.
- `DV.Platform`'s capitalised members (`Window`, `Camera`, `DeepLinking`, ...)
  are `@Deprecated` aliases of the lowerCamel ones (`window`, `camera`,
  `deepLinks`, ...) for one release. `Notifications` and `notifications` are
  different members and both stay.
- `dartvel preview` forwards to the new commands for one release.

### Breaking

- `dvAdminAsset`/`DVAdminAsset` and the separately built Studio
  (`dvBuildStudio`) are removed (see Removed below).

### Details

- `dartvel dev --release` serves an existing production web build locally,
  with `--host` and `--port`. It uses the same route renderer as web-server.
- Branch deployments move to `dartvel deploy --preview`, with `--from-pr`,
  `--list`, `--open`, `--logs`, `--destroy` and `--sweep`. Log retrieval remains
  unsupported; `--logs [--follow]` reports that limitation.
- `dartvel preview` is hidden from help and forwards to the new commands
  with a deprecation message for one release.

**Coding agents are set up from one source.** A Dartvel project had no agent
documentation at all, so whichever agent you opened it in inferred the rules
for itself, and eleven tools each wanted a differently named file to be told
the same thing. `dartvel create` and `dartvel init` now write `AGENTS.md`,
`CLAUDE.md`, `GEMINI.md`, `AGENT.md`, `CONVENTIONS.md`, `.cursorrules`,
`.cursor/rules/dartvel.mdc`, `.windsurfrules`, `.clinerules`,
`.kiro/steering/dartvel.md`, `.github/copilot-instructions.md` and
`.aider.conf.yml`, each carrying one block generated from
`docs/agents/rules.md` as it ships with the CLI, and `dartvel dev` replaces
that block so the rules an agent reads match the Dartvel version installed.

Everything between `<!-- dartvel:begin agents -->` and
`<!-- dartvel:end agents -->` is Dartvel's. Everything outside is the project's
and a refresh never touches it: a `CLAUDE.md` written before Dartvel was
adopted keeps all of its text and gains the block below it, a file deleted by
hand comes back, and a refresh that changes nothing writes nothing and prints
nothing. Codex, OpenCode, Devin and ChatGPT read the root `AGENTS.md` and get no
file of their own, which `AGENTS.md` states. The block names the documentation
shipped with the installed CLI, and `dartvel docs` when there is none beside it,
so it never points at a path that does not exist.

**Security: Studio is part of the application, guarded by the server.**
Studio was a second Flutter application, built on its own and served as
files under its mount, and serving files by path is how
`/__studio/index.html` reached a signed-out visitor with the whole Studio UI.
Studio's screens are now routes of the project's own app, at `<mount>` and
`<mount>/login`, and nothing under the mount is ever a file.

### Changed

- **Studio's pages are the application's pages.** The web-server binary (and
  `dartvel preview`) answers `<mount>` and `<mount>/login` with the
  application's own shell, rendered for that route by `dvRenderRoutePage`,
  the function every page is rendered by, with `noindex, nofollow`,
  `no-store` and no framing. `<mount>` goes only to a caller with the Studio
  grant; everybody else is sent to `<mount>/login`, and the app checks the
  grant again on every visit before it builds any Studio section.
- **Studio's code is a deferred library of the application.** Its screens
  and its sign-in are two deferred libraries, so a public page loads none of
  Studio. `dartvel build web-server` compiles Studio in with the
  `dartvel.studio` define, takes the parts only Studio's screens load out of
  the web root, and the binary keeps them in memory and hands them only to a
  session with the Studio grant; to anybody else they are a path that does
  not exist. A build whose Studio code would land in a public file is
  stopped.
- **No Studio where nothing can guard it.** An application with
  `dartvel.admin.enabled: false` has no Studio route generated at all, and a
  static `dartvel build web` never carries Studio: it has no server to guard
  it with.
- **`dartvel dev` runs Studio in the app.** A web app is run with Studio's
  routes, Flutter's development server passes `<mount>/api/` to the
  development backend, and the grant link opens on the app itself.
- Studio reads the project graph through `<mount>/api/graph`, behind the
  grant, instead of as a file.
- **Studio says who is signed in, and signs out properly.** The foot of
  Studio's rail shows the signed-in account and a **Sign out** control;
  signing out ends the session on the server (`<mount>/api/auth/sign-out`)
  and clears the cookie, not only this browser's copy.
- The first-run setup is the third Studio route, `<mount>/setup`, rendered
  from the application's shell like the sign-in; a documentation site with
  `access: studio` sends a signed-out reader to Studio's sign-in, which now
  brings them back to the page they wanted.
- **Cost to public pages:** a public page's JavaScript grows by about 1.2%
  (around 12 KB gzipped on dartvel.dev; `main.dart.js` +40 KB raw). dart2js
  keeps a Flutter framework method in `main.dart.js` once any code calls it
  on a class the page already builds, even when only Studio's deferred code
  does, and Studio's route registration itself lives there. Studio's own
  screens (about 360 KB) are in no public file. Accepted for this release.

### Removed

- The separately built Studio (`dvBuildStudio`), the static admin dashboard
  it replaced, and `dvAdminAsset`/`DVAdminAsset`, which resolved a request
  under the mount to a file on disk (the documentation site, a separate
  compiled app, keeps its own file resolution).

## 0.9.3 — 2026-09-29

**Studio lists every page the application has, and data models can be
designed in Studio.** Pages lists compiled routes from the route
manifest alongside stored pages, marked Code, Studio or Override;
compiled pages open read-only, **Edit this page** creates an override, and
**Restore compiled page** deletes it. In Studio's Data section, data models
(fields, types, validation rules, relations, indexes, access) are created,
edited and served with an instant data API at `/_dartvel/data/<Model>`, and
can be written to `lib/models` as `@DVModel` declarations during development.
**dartvel_shelf gains native WebSockets, upstream Shelf adapter (`fromShelf`),
streaming backpressure and native static file serving.** WebSocket connections
are backed by Axum/tungstenite with event-driven native wakeup callbacks;
`fromShelf()` mounts existing Shelf pipelines onto the native runtime;
response bodies stream with bounded-queue backpressure to prevent native
memory growth; and native static file serving supports byte ranges, HEAD, and
conditional requests.

dartvel_core, dartvel_flutter, dartvel_cli and dartvel_dev go to 0.9.3;
dartvel_shelf goes to 0.9.2; dartvel_generator 1.4.2 is unchanged.

### Added

- **Studio lists every page the application has.** Pages listed only what
  Studio had stored, so a site of fifty compiled pages opened on "0 / No
  stored pages yet". It now lists the compiled routes -- from the generated
  route manifest inside the application, from the build's project graph on a
  served Studio -- with the stored pages, each marked Code, Studio or
  Override, dynamic routes with their parameters; the overview's counts and
  the Site map show the same list. A compiled page opens read-only, as the
  application draws it or as its captured structure; **Edit this page** makes
  an override that takes the route over when deployed, and **Restore compiled
  page** deletes it. `dartvel admin generate` opens `DVStudioInApp` over the
  project's own routes and models, and the router generates
  `dartvelPagePreview`. (dartvel_flutter, dartvel_core, dartvel_cli)
- **Data models are designed in Studio.** A model's name, key, fields and
  their types, rules (smallest, largest, shortest, longest, pattern,
  unique), relations, indexes and who may use its data are made and changed
  in Studio's Data section, stored as a definition beside its records and
  served at once, with records browsed, created, edited and deleted in the
  same place. A designed model has a data API at `/_dartvel/data/<Model>`
  governed by its access, and on `dartvel dev` it can be written to
  `lib/models` as the `@DVModel` that compiles back to the same model.
  `@DVModel.validate(...)`, `@DVModel.uniqueField()` and `@DVModel(indexes:,
  access:)` declare the same rules in code. (dartvel_core, dartvel_flutter,
  dartvel_cli)
- **Upstream Shelf adapter:** `package:dartvel_shelf/shelf.dart` provides
  `fromShelf()` to mount existing Shelf pipelines, cascading handlers, and
  middlewares directly on Dartvel's native server runtime. (dartvel_shelf)
- **Native WebSockets:** `package:dartvel_shelf/web_socket.dart` provides
  `webSocketHandler` and `wsHandler` backed by Axum and tungstenite with
  event-driven native frame delivery callbacks (`aw_register_ws_wakeup_handler`).
  (dartvel_shelf)
- **Response and request body streaming with backpressure:** Bounded-queue
  backpressure prevents unbounded native memory growth when clients read
  slowly; request bodies are pulled chunk-by-chunk. (dartvel_shelf)
- **Native static file serving:** Native static asset handling streams via
  `tower-http` `ServeFile` with byte ranges (`206`, `416`), `HEAD`, conditional
  requests (`ETag`, `If-Modified-Since`), and path traversal protection.
  (dartvel_shelf)

## 0.9.2 — 2026-09-28

**A web page shows something to read, and how far it has got, before
Flutter starts.** The page text the build already writes for crawlers is
the page until the first frame, so the largest contentful paint is text
rather than the splash; a thin bar across the top follows the compiled app,
the renderer and the fonts as they arrive and completes on the first frame;
and `main.dart.js` is preloaded from the head. After the first frame the same
bar is `DvDefaultLoading` on every platform, and **`DV.progress`** shows it
for an application's own work. **Adopting Dartvel keeps the router an app
has:** besides go_router, the generated client mounts into auto_route
(`dartvelAutoRoutes`) and Flutter's Navigator 1.0 (`dartvelOnGenerateRoute`)
and 2.0 (`dartvelPageFor`), and `dartvel init` names any other router with
those three. The specification gains a **Brownfield** section: Dartvel
inside an existing native app, measured against Expo's. Numbers before the
change are in docs/web-performance.md.

dartvel_core, dartvel_flutter, dartvel_cli and dartvel_dev go to 0.9.2;
dartvel_shelf 0.9.1 and dartvel_generator 1.4.2 are unchanged. Nothing to
migrate: a page that wants the old spinner passes its own `loading:`.

## 0.9.1 — 2026-09-28

**Studio signs people in itself, and the web-server binary serves the page
the static build writes.** dartvel.dev now runs on the web-server binary,
and these are what that turned up. dartvel_core, dartvel_shelf,
dartvel_flutter, dartvel_cli and dartvel_dev go to 0.9.1; dartvel_generator
stays at 1.4.2, which already accepts it.

### Added

- **Studio signs people in itself, at `<admin.path>/login`.** It used to answer
  a signed-out visitor as a path nobody serves and leave signing in to the
  application's `/login`, which an application can turn off or replace and
  whose router does not know the mount exists. The sign-in is a Flutter page
  of the Studio app, in Studio's own style, light and dark, phone to desktop:
  it signs in against the application's accounts at `<mount>/api/auth/*`,
  asks for the second factor when the account has one, and then loads Studio
  from the server, which still decides on the `Studio.access` grant. A
  signed-out visit to a Studio page is sent there; Studio's data and API
  still answer a stranger as a path nobody serves. (dartvel_core,
  dartvel_flutter)

### Fixed

- **`dartvel build web` and the web-server binary render a page with one
  function.** The binary rendered routes from plain lines guessed out of the
  page source and never minified them, so a crawler or a reader with
  scripting off got no links, headings or code blocks, and the home page was
  250 lines where the static build wrote 32. Both now render with
  `dvRenderRoutePage` in dartvel_core: the static build for every route at
  build time, the binary on request from the page the build wrote into its
  manifest, `dartvel preview` likewise. The minifier, the static page head
  and the structured data moved into dartvel_core for it. (dartvel_core,
  dartvel_shelf, dartvel_cli)
- **The semantics capture waits out a slow first paint.** One route missing
  puppeteer's 30-second navigation timeout on a loaded machine failed the
  whole build; each route now has 120 seconds and three tries. (dartvel_cli)
- **HEAD on a server-rendered page answers as GET does.** It answered 404
  while GET answered 200, so an uptime monitor or a crawler that asks HEAD
  first saw no pages. (dartvel_shelf)
- **The PWA service worker leaves Studio and API reads to the browser.** It
  served every same-origin GET cache-first until the next deploy, Studio's
  API included, so Studio showed stale records. (dartvel_cli)
- **Signing in with `from=` a path the router does not serve loads it from the
  server** instead of drawing the application's not-found page.
  (dartvel_flutter)
- **Every Dartvel link has its right-click menu, wherever it is.** The menu
  (Open in a new tab, Copy link address, More) belonged to the page shell's
  selection area, so a link with none above it -- the default 404 page's
  "Go to the home page", a page with `selectable: false`, a kiosk with
  selection off -- showed its hover preview and no menu at all, the browser's
  own being off. `DVNavLink` now opens the same menu itself when no page menu
  covers it. (dartvel_flutter)
- **The web server answers a path no route serves with a 404.** It returned
  the application shell with a 200, a soft 404 a crawler indexed as a page.
  The shell is still the body, so the app draws its not-found page, and a
  page published from Studio still answers 200. (dartvel_shelf, dartvel_cli,
  dartvel_core)

## 0.9.0 — 2026-09-28

**Placement follows call sites: a module source reaches more of the
platforms Dartvel builds for, through a carrier per target.** The placement
matrix is in NEW_SPEC.md. A Dart package that needs `dart:io` no longer
throws in the browser: its asynchronous calls cross to a generated backend
route, which runs them behind the policy the application names in
`dartvel.modules.<id>.backendPolicy` -- the call runs with the server's
authority, so the build refuses one with no policy (DV-MODULE-021). C and
Rust compile to WebAssembly for the browser when the module is generated;
functions of numbers are real there and stay synchronous. npm packages and
WebAssembly binaries run on the Linux, macOS and Windows desktops in the
Node `dartvel build` copies into the bundle. A Swift package that imports no
Apple framework runs on Linux, Windows and the backend; one that does names
the import that blocks it. Also **`DVBox.threePane`**, one pane per panel of
a tri-fold, with a live demo on the UI page.

dartvel_core, dartvel_flutter, dartvel_cli, dartvel_dev and dartvel_shelf go
to 0.9.0 and dartvel_generator to 1.4.2. To migrate: a module regenerated
with `dartvel add --refresh` depends on `dartvel_core ^0.9.0`, and one that
carries a call to the backend needs `backendPolicy:` under its mount.

## 0.8.0 — 2026-09-28

Three things that were impossible or missing. **`dartvel add` wraps a package
from any ecosystem as a module:** a Dart package (`pub:`, `git:`, `path:`),
an npm package (`npm:`), a C library or a Rust crate (`c:`, `cargo:`), a
WebAssembly binary (`wasm:`), a JVM library (`maven:`, `jar:`) and a Swift
package or CocoaPod (`swift:`, `pod:`), each reached as `DV.Modules.<id>`
with what every operation does on a device, in a browser and on the backend
declared in the module and checked by the build. On the web, **a link to a
heading opens the page at that heading**, and **password managers save and
fill the prebuilt sign-in and sign-up pages.** Studio gains **a formula bar,
a command palette (Ctrl+K) and Ctrl+D**.

dartvel_core, dartvel_flutter, dartvel_cli and dartvel_dev go to 0.8.0;
dartvel_shelf to 0.8.1 and dartvel_generator to 1.4.1, which only accept the
new core. Nothing to migrate. `dartvel inspect modules [--json]` is new, and
`dartvel build` now refuses a call it can see to a module operation that
cannot run where it is building (DV-MODULE-013, DV-MODULE-014).

## 0.7.1 — 2026-09-28

A fix release. On the web, every page reported Esc handled, so the browser
never saw it, and Esc pressed in the page did not close the find bar. Esc now
reaches the browser unless the page has something open to close. A
dialog opened over a page also lost its keys to the page beneath. Both are
fixed in dartvel_flutter; nothing to migrate.

dartvel_core, dartvel_flutter, dartvel_cli and dartvel_dev go to 0.7.1.
dartvel_shelf stays 0.8.0 and dartvel_generator 1.4.0.

## 0.7.0 — 2026-09-27

`DV.Cache` becomes four calls, every data model gets a public page unless it
opts out, and outbound webhooks can go as CloudEvents or signed the Standard
Webhooks way, with an AsyncAPI 3.0 catalog served beside `openapi.json`.
Change capture and offline data models are declared rather than wired, and
application-facing Dart is written with primary constructors, which raises
the SDK floor to Dart 3.13.0 and Flutter 3.47.0.

dartvel_core, dartvel_flutter, dartvel_cli and dartvel_dev go to 0.7.0,
dartvel_shelf to 0.8.0 and dartvel_generator to 1.4.0 (after 1.3.1; its
0.6.1 and 0.6.2 were numbered with the family by mistake). The package
changelogs list every change; the ones below need action.

### Breaking

- **`DV.Platform.tray.show(icon:)` takes a generated asset.** The icon is a
  `DVAssetRef`, the `DVAsset` value `dartvel routes` generates, instead of a
  path string, so a renamed or unlisted icon is a compile error rather than an
  empty tray slot. Rewrite `icon: 'assets/tray.png'` as `icon: DVAsset.tray`.

- **Every data model gets public pages unless it opts out.**
  `@DVModel(generatePublicPages:)` now defaults to `true`: each record is served
  at `/<plural-kebab-model>/:<slug|id|first String field>` (`Article` at
  `/articles/hello-world`, `BlogPost` at `/blog-posts/42`), rendered statically
  by `dartvel build web` and listed in the sitemap. **Migration:** add
  `generatePublicPages: false` to every `@DVModel` whose records must not have a
  page; the build log names each model that got one by default. What a page
  shows is decided by the model:
  - A `@DVModel.sensitiveField()`, and the field naming the privacy `subject:`,
    are never on a page, in its head, structured data, crawler text, the static
    build or the sitemap, except on the rendered page for a viewer the model's
    new `viewSensitive` policy admits (`DVPolicyAction.viewSensitive`).
  - A record the model's `view` policy refuses answers 404, exactly as a missing
    or unpublished one, and is not enumerated. Server page data and static
    paths are resolved as nobody.
  - Accounts, sessions, credentials and audit records (read from the model's
    name), rows that are their own privacy subject, tenant-scoped models,
    models with a protected or no `String` key, and models whose route an
    application page already serves get no page unless they say
    `generatePublicPages: true`. An explicit `true` that cannot be honoured
    stops the build.

- **`DV.Cache` is four calls: `get`, `set`, `has` and `delete`.** Everything
  else is a named option on them. Rewrite `remember(key, compute, ...)` and
  `staleWhileRevalidate(...)` as `get(key, compute: compute, ttl: ...,
  tags: ..., staleFor: ...)`; `tag(key, tags)` as `set(key, value,
  tags: tags)`; `revalidateTag(tag)` as `delete(DVCacheTag(tag))`; and
  `clear()` as `delete(DVCache.all)`. `delete(key)` is unchanged: `delete`
  takes one positional target, a `String` key, a `DVCacheTag` or
  `DVCache.all`, as `get`, `set` and `has` take the key, and throws an
  `ArgumentError` naming the type of anything else.
- **The cache's machinery left `DV.Cache`.** `lock`, `purgeExpired`,
  `keysForTag`, `tags`, `configure`, `adapter` and the `global*` helpers are
  the framework's `DVCacheRuntime`, exported from
  `package:dartvel_core/framework.dart`. Work only one process may do is a
  schedule, whose occurrences are claimed once across cron processes.
  `DVCacheLock` and its `release()` are gone.
- **The cache's default store is configuration.** Name it in
  `dartvel.cache` (`store: memory | database | redis | memcached`,
  `url: ${REDIS_URL}`, `prefix:`) and the generated server opens it at
  startup. `DV.Cache.withAdapter(adapter)` switches store in code, and the
  adapters are exported for it; `DVRedisClient` and `DVCacheTags` stay out of
  the generated barrel.
- **A cache adapter implements `delete`**, as `DV.Cache` names it; `remove`
  still works for callers, as a deprecated extension.

### Added

- **Webhook deliveries in CloudEvents or signed the Standard Webhooks way.**
  `dartvel.webhooks.format: cloudevents` sends each delivery as a CloudEvents
  1.0.2 event, structured (`application/cloudevents+json`) or with
  `mode: binary` as `ce-` headers; `signature: standard` signs with
  `webhook-id`, `webhook-timestamp` and `webhook-signature`, verifiable by the
  official standardwebhooks libraries. Dartvel's envelope and signature stay
  the default. `DVCloudEvent.fromHttp` reads either mode on the receiving side
  and `DVStandardWebhookSignature.verify` checks the signature.
- **An AsyncAPI 3.0 document for the webhook events an application sends**,
  generated from its `DVWebhookEvent` declarations and served at
  `/api/asyncapi.json` beside `openapi.json`.

- `DV.Cache.has`, and `DV.Cache` in backend code through `DV` from
  `package:dartvel_core/dv.dart` -- the same cache a page reaches.
- `DV-CACHE-001` to `005`: the build refuses a `dartvel.cache` block it cannot
  honour, and the server refuses to start on a store it cannot open rather than
  giving each instance a cache of its own. A Redis store also carries the
  shared rate limit.

### Fixed

- A read-through `get<List<String>>` against a database, Redis or Memcached
  store is a hit. The value came back as `List<dynamic>`, failed the type
  check, and was recomputed on every call.

Change data capture is declared, not wired. `@DVModel(capture: true)` on a data
model and destinations under `dartvel.capture` in `pubspec.yaml` are all an
application writes; the generated server records every write, delivers it on
the job queue with retries, backfills a new destination, reports lag and takes
erased records out of every copy.

### Breaking

- **The change capture machinery is no longer in `package:dartvel_core/dartvel.dart`.**
  `DVCapture`, `DVCaptureConsumer`, `DVCaptureSink`, `DVWarehouseSink`,
  `DVCapturePrivacyAdapter`, the delivery and backfill jobs and the change and
  batch types moved to `package:dartvel_core/framework.dart`. An application
  that built a log, a consumer or a sink, or called `ensureSchema`,
  `configure`, `consumer`, `deliverAll`, `registerJobs` or `dispatchDelivery`,
  declares its destinations instead:

  ```yaml
  dartvel:
    capture:
      retention: 7d
      destinations:
        warehouse:
          type: database
          connection: WAREHOUSE_URL   # the secret's name, never its value
          models: [Order]
          lagThreshold: 10m
  ```

  `DVCaptureWriteError` stays in the application barrel.
- **`Model.backfillTo(consumer)` is no longer generated.** A destination that
  has never been copied to, or a data model newly added to one, is backfilled
  by the server.

- **An offline data model syncs by itself, and its machinery is no longer
  public.** `Model.offlineStore(database)` and `Model.offlineRemote(database,
  validate:)` are no longer generated, and `DVOfflineStore`, `DVOffline`,
  `DVOfflineRemote`, `DVMutation`, `DVReplayResult`, `DVRemoteOutcome`,
  `DVOfflineClock` and `DVOfflineStorePrivacyAdapter` are no longer exported
  from `package:dartvel_core/dartvel.dart`. A data model declaring
  `@DVModel(offline: ...)` is saved, deleted and read like any other: replace
  a store write with `record.save()`, `pending()` with `record.syncState`, and
  delete the replay call and the server-side remote -- the runtime sends the
  queue and the generated backend applies it. `DVSyncState` and
  `DVOfflineQueueFullError` stay public.

### Added

- **Offline data models work offline with nothing wired up.** `save()` and
  `destroy()` write the device's copy at once and queue the change; reads come
  from the device copy; the queue is sent when the app starts, after each
  write, when `DV.Platform.network` says the server is reachable again, and
  on a backoff after a failed send. The device store is a SQLite file on
  phones, desktops and TVs and IndexedDB in a browser. Signing out sends what
  it can and then empties the store.

### Fixed

- **The generated backend's replay route works against a real database and a
  typed policy.** It created none of its own tables, so the first replay
  failed with a server error; and it asked the model's policy with a map,
  which every policy written against the model refused. It now prepares its
  tables, builds the class your server-side policy takes from the record, and
  answers with its time so a device can correct its clock.

### Breaking

- **The SDK floor is Dart 3.13.0 and Flutter 3.47.0.** Dart 3.13
  is the first release with primary constructors
  (`class Point(final int x, final int y);`), which the `dartvel create`
  scaffold, the samples and generated data models are written with; on Dart
  3.12 they are a compile error. Flutter 3.47.0 is the first stable release
  that ships Dart 3.13.0. Raise `environment: sdk:` to `">=3.13.0 <4.0.0"`
  and upgrade Flutter before taking this release.

### Changed

- **Primary constructors everywhere an application sees Dart.** The
  examples, the docs samples, the READMEs, the site, the model `dartvel db
  pull --local` suggests and the generated models, jobs and functional
  widgets declare their classes as
  `class const _Order({required final String id});`, and a `dartvel create`
  project is on Dart 3.13 so its own classes can be too. The
  generator reads inputs written either way, and old-style inputs generate
  exactly what they did.

## 0.6.2 — 2026-09-26

Documentation only: every README installs the CLI with `dart pub global
activate dartvel_cli` first, then Homebrew, the release binaries,
dev_dependencies and npm. dartvel_shelf is 0.7.2.

## 0.6.1 — 2026-09-26

Every published package declares its platforms in `pubspec.yaml`, so pub.dev
lists Android, iOS, Linux, macOS, Web and Windows instead of inferring them
from platform-specific imports, which listed dartvel_flutter as Linux and
Windows only and dartvel_core as supporting nothing. No code changes.
dartvel_shelf is 0.7.1. On main, `tool/pubspec_platforms_check.dart` now
fails when a published package stops declaring them.

## 0.6.0 — 2026-09-25

Studio grows from a record browser into the place a team runs its application
from — records, published pages, flags, the content workflow and data models of
mounted modules — and the application's own backend takes over sign-in, second
factors and sessions. Underneath, records gained history, retention and
erasure, so privacy requests are something `dartvel privacy` can answer rather
than something a team writes by hand.

dartvel_core, dartvel_flutter, dartvel_cli and dartvel_dev go to 0.6.0,
dartvel_shelf to 0.7.0, dartvel_generator to 1.3.1 (it only accepts the new
core). The package changelogs list every change; the ones below need action.

### Breaking

- **`dartvel publish` is removed.** Store submission is `dartvel deploy --store`.
- **`dartvel build <target> --profile development|profile|release`** is the one
  way to choose the build mode (`release` by default). `--release` and
  `--no-release` are usage errors, and `dartvel build dev-client` is gone: a
  development shell is `dartvel build android --profile development`.
- **A generated model built by hand no longer replaces a stored row.** `save()`
  on a model that was not read throws `DVConflictError` (`DV-HISTORY-001`)
  instead of overwriting; replacing without reading is
  `save(onConflict: DVConflict.lastWriteWins)`.
- **Generated models persist through `DVRecordTable`**, so their tables carry
  versions and can be erased and swept. Regenerate the client.
- **`dartvel init` adds Dartvel to an existing project** and is no longer an
  alias of `create`; `create` refuses to scaffold over a project it did not
  create (`DV-ADOPT-005`).
- **`LocalAuthProvider.signIn` no longer says whether an account exists.** An
  unknown e-mail and a wrong password fail the same way.
- **On Android and iOS the application key lives in the platform keyring**, never
  in a file; a device without one refuses rather than falling back.
- **`DVModelAdmin` checks the model's policy** before it offers New, Edit or
  Delete, and again before it writes.
- **`DV.Auth` signs in through the application's own backend**
  (`/auth/sign-in`, `/auth/sign-up`, `/auth/second-factor`, `/auth/sign-out`).
- **dartvel_shelf's committed library and bindings** no longer carry the HTTP
  client symbols that moved to dartvel_core.

### Binaries

This release was cut while GitHub Actions was unavailable for the repository,
so the self-contained binaries attached to it were built by hand: Linux only.
macOS and Windows binaries are added by re-running the CLI release workflow for
v0.6.0; until then `npm i -g dartvel_dev` works on Linux, and elsewhere
`dart pub global activate dartvel_cli` is not an alternative (see
`npm/dartvel_dev/index.js`), so use a Linux machine or wait for the workflow.

## 0.5.0 — 2026-09-11

Everything that makes a page arrive before it is asked for: the page itself,
its code, its images, and the renderer underneath them. Most of it is
NextFaster's playbook, checked in a real browser rather than assumed -- and the
checks are most of what the rest of this release is, because each one found
something that every unit test had passed.

### Added

- **A link fetches what it points at.** It preloads once it has been on screen
  for 300 ms, or as soon as a pointer reaches it: `DVLinkPreload.visible` is
  the default now, because hover is a desktop trigger and no link on a phone
  ever fired. A mouse follows the link when the button goes down rather than
  when it comes up. On the web it also prefetches the route's prerendered HTML
  -- what a new tab, a reload or a shared link opens -- and the images the page
  opens with, then hands each image to Flutter's cache once the browser has it,
  so it is downloaded once rather than twice.
- **Every page is its own bundle again.** Pages were imported `deferred` and
  their bodies copied into the eager router, so dart2js put them in
  main.dart.js: this site built with three of its four pages having no deferred
  part at all. A page's body now goes in a library only its deferred import
  reaches. The site's build went from one part file to nine, and each
  prerendered page preloads its own in its head, so a page opened directly
  downloads them alongside main.dart.js instead of a round trip after it boots.
  The same lists go into `dartvel_prefetch.json` for links to read.
- **Images in the size they are drawn at.** `dartvel build web` writes every
  declared raster image at each configured width, `DVImageView` asks for the
  one its slot needs on this screen, and a web-server build answers
  `/_dartvel/image` for remote images from hosts you list and no others. A link
  prefetches the variant for the visitor's own pixel ratio, under the same
  cache key the widget will ask for: measured in Chrome, a phone-density screen
  fetched the 640 and a 2x screen the 828, each exactly once.
- **A launch splash on every platform**, from `dartvel.splash`, with nothing to
  install and nothing to run: the web shell and every prerendered page,
  Android's launch theme and its API 31 splash, the iOS storyboard with a
  dark-mode colour, the macOS and Linux views. Windows already waits for the
  first frame. With nothing configured it takes the PWA background colour and
  the project icon.
- **The web server can send a page's shell before its data.**
  `dartvel.web.server.streaming: shell` writes the head, its preloads and the
  splash while the data query is still running, then the title and body when it
  answers -- and the route's own deferred parts are named in that first chunk.
  A guarded route still waits and still answers 401 or 404. `dartvel preview`
  streams through the same code, so preview and production cannot drift.
- **The renderer starts downloading while the page is still being parsed.**
  CanvasKit is 7 MB and nothing asked for it until flutter_bootstrap.js had
  arrived and run. Every page now preconnects to where it lives and preloads
  the variant the Flutter loader will choose, tested condition for condition
  against the loader's own check; in Chrome both files are fetched once.

### Changed

**The `build_runner` code-generation path is retired.** Dartvel generates with
`dart run dartvel_cli:dartvel routes` — or with `dartvel build` and `dartvel
dev`, which generate before they run. If your project has `build_runner` and
`dartvel_generator` in `dev_dependencies` for Dartvel's sake, drop both and run
`dart run dartvel_cli:dartvel routes` instead. Keep `build_runner` only for
another package's builders (`drift_dev`, `json_serializable`,
`flutter_vscode`); `dartvel build` and `dartvel dev` still run it when it is
declared.

`dartvel_generator`'s builders still work and now warn on every build, naming
the command that replaces them. They are removed in `dartvel_generator` 2.0.0.
Nothing breaks today: the builders were left in place because
`auto_apply: dependents` runs them in every project that depends on the
package, and a builder that disappears takes the `router.g.dart` it wrote into
`lib/` with it.

Why: `dartvel routes` writes the whole client — the `dartvel_client` barrel
every page imports, the router, each page's body, functional widgets, models,
backend function clients and config. The builders wrote only part of it, so
they could never generate a client from a clean checkout: with no barrel, the
first page's `@DVPage` cannot be resolved and the build stops. Every project on
that path was really running both generators in sequence, and three bugs lived
in the difference between them — page bodies copied into the eager router,
no link preloading, and function pages built with no data scope.

`dartvel create` no longer scaffolds `build_runner`, and the `basic_app` and
`class_widgets_app` examples — the last two applications on the old path —
now generate with one command.
**Two defaults changed.** Links preload on sight rather than only on hover
(`DVLinkPreload.visible`), and a web build that declares raster images now
writes resized variants of each one -- up to twelve files per image, which an
image-heavy application will notice in its build size. `dartvel.images.widths`
sets the list.

**A route's typed target is lowerCamelCase.** `/next_shift` is
`DVRoutes.nextShift`, because `DVRoutes.next_shift` is a name Dart's own style
lint rejects, and a Flutter project's CI fails on it. The old name is still
generated as a deprecated alias, so code written against it keeps compiling;
it goes in the next minor.

### Fixed

- **Client cron schedules ran twice and never stopped.** The timer was started
  when the router was created, owned by nothing: a second router started a
  second timer, and every widget test that built a router ended with "A Timer
  is still pending" -- eight of the example's own tests, which no job ran.
  Schedules now run while a page is on screen and stop with the last one.
- **Generated code failed the analyzer its users run.** `flutter analyze`
  fails on an info, and three things in generated output produced one: an AI
  tool's schema, the sitemap entries, and route targets named after a page
  directory with an underscore.
- **Every page names itself with a level-1 heading.** A page's app-bar title
  is that heading now, on both the Material and Cupertino shells, and a
  generated home-widget page carries one of its own. Without it `dartvel build
  web`'s own accessibility audit refused every page with a bar -- which is why
  the example application had never produced a web build at all. CI builds it
  now.
- **An image variant is never a bigger download than its source.** Re-encoding
  can undo compression the source already had; when it does, the source's own
  bytes are written at that width.

## 0.4.1 — 2026-09-11

A patch for two faults in 0.4.0, both in versions that live in source rather
than in a pubspec, which the release tooling did not know to move.

The 0.4.0 CLI reported itself as 0.3.2, so `dartvel update` offered 0.4.0 to
machines already running it, for ever. And `dartvel create` had been writing
`^0.2.1` since 0.3.0, so new projects resolved Dartvel 0.2.x and none of the two
releases after it. **If you created a project with 0.3.x or 0.4.0, change
`dartvel_core`, `dartvel_flutter` and `dartvel_cli` to `^0.4.0` in its
pubspec.** Both versions are now moved by `tool/bump_version.dart` and checked
by `tool/check_constraints.dart`, which runs before anything is published.

Headless Chrome, which `dartvel build web` uses to capture what crawlers see,
is now one copy per machine instead of one per project.

## 0.4.0 — 2026-09-10

0.3.0 and 0.3.1 shipped without their own entries here, so this covers
everything since 0.2.1. The version is a minor rather than a patch because
`DVFieldCipher`'s constructor changed and because eight hundred commits of
behaviour changed underneath a number that said 0.3.2.

**Android and web stopped being declarations.** Android went from 10 native
bindings to 36 and web from 16 to 41, counted from source by
`dart tool/binding_coverage.dart` rather than written down -- every
per-platform figure in this repository had been wrong at some point, in both
directions.

**A new gate runs the bindings on a real device.** The emulator job asserts
that registration completed, that every name the capability set advertises has
a handler, that nothing is registered which the set omits, that the safe
bindings invoke, and that text survives a clipboard round trip. It found three
bugs in its first three runs, all of which had shipped in 0.3.1: every haptics
binding threw on API 31 and above, and two manifest permissions were never
written. All three were invisible to the unit suites, which call bindings
directly and accept whatever comes back.

That is the shape of most of this release. `dartvel db migrate` printed
success and executed nothing. Declared middleware reached the generated router
and was dropped. Two of three multi-tenancy strategies produced exactly the
queries the shared strategy produces, so every tenant read every tenant's rows
on the two settings chosen to prevent that. A Dartvel copy on Linux took the
X11 clipboard away from the whole session and made every paste on the machine
hang. `DV.Updates.check()` still throws on every platform, and this release
says so rather than implying otherwise.

**Known and stated:** nothing below the Dart layer on Android has been
executed outside the emulator job, `updates.check`/`apply`/`rollback` are
registered by nothing, and twenty-one specification sections remain partial
with their gaps named in `docs/spec-status.json`.


Two tranches of work. The first filled in provider and adapter implementations
for subsystems that had an API surface but no way to reach a real service. The
second built the subsystems the spec named and nothing stood behind — Studio,
GraphQL, model sync and presence, MCP, the generated admin — and then went
looking for the difference between what the documentation claimed and what a
clean checkout could actually do.

### Added

- **AI providers.** `DV.AI` had only the deterministic `LocalDVAIAdapter`.
  HTTP adapters now exist for Claude (`AnthropicDVAIAdapter`), OpenAI,
  OpenRouter, Gemini and Ollama, covering chat, embeddings, structured output
  and transcription. A capability a provider does not serve throws
  `UnsupportedError` naming it, and a rejected request throws
  `DVAIProviderException` carrying the status and body — neither degrades to an
  empty result.
- **Agents and tool calling.** `runAgent` drives the provider's own tool loop
  (Anthropic `tool_use`, OpenAI `tool_calls`) so the model chooses tools, rather
  than firing every requested tool up front. Tools carry a description and JSON
  Schema via `DV.AI.registerTool(..., description:, parameters:)`. A throwing
  tool is reported back to the model as an error result instead of failing the
  run; a loop that never settles throws after `maxAgentIterations`.
- **SQLite database.** `SqliteDVDatabaseAdapter.memory()` and `.file()` execute
  arbitrary SQL, with WAL and foreign keys on by default for file databases.
  `MemoryDVDatabaseAdapter` understood only four statement shapes.
- **Pluggable cache and durable queues.** `DV.Cache` and `DV.Queues` now run on
  adapters, with `DVDatabaseCacheAdapter` and `DVDatabaseQueueAdapter` able to
  share one SQLite file with the application. Durable jobs need a
  `DVJobPayloadCodec`; dispatching or draining a payload with no registered
  codec throws rather than dropping work.
- **Search backends.** `DVSqliteSearchProvider` (FTS5, word matching and BM25
  ranking), plus `MeilisearchProvider`, `AlgoliaSearchProvider` and
  `OpenSearchProvider`. Paging models differ per service and are translated, so
  callers always see the page they asked for.
- **Mail providers.** `SmtpMailProvider` speaks SMTP over a socket, with
  STARTTLS, `AUTH PLAIN`/`LOGIN` and dot-stuffing. HTTP providers cover Resend,
  SendGrid, Postmark, Mailgun and SES, the last signed with the new
  `DVAwsSigV4`.
- **Push and SMS.** `FirebasePushProvider` (FCM HTTP v1), which flags a stale
  device token as `isUnregisteredToken` so callers prune rather than retry, and
  `TwilioSmsProvider` for the `sms` channel.
- **File storage.** `DV.FileStorage` runs on an adapter, with
  `S3FileStorageAdapter` for S3, Cloudflare R2 and MinIO.
- **Authentication.** `DVPasswordHasher` (PBKDF2-HMAC-SHA256, per-password
  salt, constant-time compare) plus `DVOAuth2Client`, an authorization-code
  client with PKCE and constant-time state validation, with presets for Google,
  GitHub, GitLab, Bitbucket and Microsoft.
- **`DV.Navigation`.** The spec makes it the navigation API, with `go_router` an
  implementation detail behind it, but only `context.navigateToPage(...)`
  existed. `DV.Navigation.to(target)` returns a `VoidCallback` for use in
  handlers, so the generated `createDartvelRouter()` hands the live router to
  `DVNavigation.attach`. Navigating with no router attached throws naming
  `createDartvelRouter()`.
- **`DV.Secrets`.** Only `PUBLIC_`-prefixed variables reach the generated
  `env.g.dart`, so nothing else was readable. Secrets resolve from the process
  environment through a conditional import; a web build resolves nothing and
  says to fetch the value through a backend function, because a secret compiled
  into a browser bundle ships to every visitor.
- **`DV.Tenants`.** `DV.currentTenant` is now genuinely an alias for it.
  Tenants resolve from a subdomain, header, path prefix, query parameter or a
  supplied resolver, and `CommonMiddleware.tenant(require: true)` aborts a
  request that names none rather than serving the default tenant's data. The
  `tenant` middleware name previously passed build validation while resolving
  nothing.
- **`DVImage`.** The spec declares `final DVImage? avatar` on a model; the type
  did not exist. It is a value so models can serialize it, with `DVImageView`
  as the rendering half, and `fromJson` accepts a bare URL string.
- **Platform device namespaces.** `DV.Platform.location`, `.NFC`, `.Camera` and
  the rest now carry the names the spec uses, each with a top-level `DV.X`
  proxy. `DV.Platform.fileStorage` and `.Notifications` return the `DV.*`
  surfaces rather than a parallel platform-local copy.
- **Generated jobs.** `@DVJob` was an annotation nothing read. The generator now
  emits the public payload with `fromJson`/`toJson`, a `dispatch()` carrying the
  annotation's queue, priority, attempts and backoff, and `DVJobQueues`
  constants; codecs and handlers register from `configureDartvelRuntime()`.
  Handlers are `@DVJob.handler()`. Generation fails on a handler for a job no
  `@DVJob` declares and on two handlers for one job.
- **Semantic model pages.** `Page.sync` rendered `Model.Card` — the flat field
  dump a list row uses. Pages now compose as featured image, title, main
  content, then the remaining fields, with `@DVModel.featuredImage()`,
  `.pageTitle()`, `.mainContent()`, `.pageOrder(n)` and `.hideFromPage()` as
  overrides. Main content resolves at render time because the largest text block
  depends on the record, not the schema.
- **`dartvel cache` reaches a persistent cache.** `clear` took only in-process
  tag metadata; it now takes `--database`/`--table`, and `cache purge` drops
  expired entries. Tag output says it reflects the CLI process only.

- **Dartvel Studio.** The WordPress-style admin whose page builder sits between
  a free canvas and a page editor, manipulating real widgets rather than a
  canvas facsimile. `DVPageDocument` is the serializable widget tree;
  `DVPageDocumentEditor` is the four operations every builder gesture reduces
  to — insert, remove, move (which refuses a drop into the node's own subtree),
  update. `DVPageDocumentRenderer` instantiates the actual `DVBox`/`DVText`/
  `DVImageView` widgets identically in-editor and in-app, with bound actions
  driving `DV.Navigation`, and `DVPageStore` persists through `DV.Database` —
  saving is publishing, page content is data. The running app serves stored
  pages and reloads them on save, a stored document overrides the compiled page
  rather than the reverse, and pages ship through OTA as versioned bundles.
  Visual backend workflows follow the same shape: a runner, a store, code
  export, and a canvas where steps drag into condition branches with undo/redo.
- **GraphQL.** The spec lists it among the generated APIs and nothing existed.
  This is the executable subset a generated API needs, not a general server
  library: operations, selection sets, arguments, variables, aliases, and named
  plus inline fragments, served at `/graphql`. Error semantics follow the spec —
  a request-level failure returns only errors, while a field-level failure nulls
  that field and appends a named error, so one bad resolver does not take down
  the response. Directives and subscriptions error rather than silently
  no-oping. Models generate their own schema and resolvers, and introspection
  answers `__schema`, `__type` and `__typename`.
- **Model sync, persistence and presence.** The Model Sync and Presence section
  had nothing behind it: no change delivery, and generated models had no `save`,
  `find`, `all`, `watch` or `sync`. `DVModelSync` is the hub the spec's rules
  demand — typed per-model change streams with tenant filtering and policy
  checks applied before delivery rather than in the UI, and a transport seam so
  arriving envelopes re-enter the local streams and remote changes look exactly
  like local ones. `DVPresence` keys channel membership on authenticated
  identity rather than connection, tenant-scoped, expiring on silence because a
  crashed client never sends a departure. Deliberately not a realtime facade;
  the spec forbids one.
- **Generated admin surfaces.** `Model.Admin()` is one call rather than a
  generated screen — the model already knows how to list, save, delete and blank
  itself, so `DVModelAdmin` is the screen around those. Beyond model CRUD: a
  queue and job dashboard with retry and single-job discard, cache/tag and
  route/page explorers showing real state, and outbox, policy/sync, entitlements
  and events surfaces. The admin opens the Studio.
- **MCP, both directions.** `DVMcpServer` serves Dartvel's registered AI tools
  to an MCP client and `DVMcpClient` consumes an external server, with
  `adoptTools()` registering the peer's tools into the same registry so an agent
  run calls a remote tool exactly like a local one. Both speak JSON-RPC 2.0 over
  a transport seam, with a newline-delimited implementation for stdio. The tools
  served are exactly the ones `DV.AI.registerTool` knows about, so a client and
  Dartvel's own agent runs see one surface rather than two registries that
  drift.
- **Databases.** PostgreSQL and MySQL/MariaDB adapters speaking their wire
  protocols directly.
- **Cache and queues.** A Redis adapter with real compare-and-set locks, a
  Memcached adapter, and a Redis-backed durable queue. Cache gained locks,
  stampede protection, stale-while-revalidate, tenant-aware keys and the
  permissioned global helpers.
- **PostgreSQL full-text search.** The index lives in the database rather than a
  separate service: one datastore to operate, and results that cannot go stale
  relative to the rows they came from. Ranking uses `ts_rank` rather than table
  order, and stemming means "learn" finds "learning" — pinned by a test, since
  that is the behaviour a `LIKE` cannot reproduce.
- **Magic links and one-time passcodes.** Two of the four auth providers the
  spec listed with nothing behind them, both the same primitive: a secret issued
  to a channel the user controls, redeemable once, within a window. Only the
  hash is stored, so a dump of the token table does not let anyone sign in, and
  comparison is constant time so a timing difference cannot reveal how much of a
  code was right.
- **Web Push.** `DVNotificationChannel.webPush` was an enum value with nothing
  behind it. A browser subscription cannot be posted to like a device token —
  the push service is untrusted infrastructure, so RFC 8291 encrypts the payload
  end to end against a key only the subscribing user agent holds, and an
  unencrypted body is a protocol error rather than a degraded send. VAPID
  application-server identification ships alongside it.
- **Linux native bindings.** The first native bindings that actually do
  something. Every `DV.Platform` API had thrown "not registered" since the
  bridge existed; eight names now work on Linux desktop through direct libX11,
  libgtk-3 and GDBus calls — `dart:ffi`, not platform channels, per the spec —
  covering clipboard, screen geometry, desktop notifications and window control.
  A binding that cannot be implemented is left unregistered so it still throws
  rather than returning a plausible lie.
- **OpenAPI.** Documents generated for backend functions and served.
- **Middleware.** The `csrf`, `idempotency`, `locale`, `featureFlags` and
  `maintenance` built-ins, which previously passed build validation while doing
  nothing.
- **`context.computed`.** Computed values that stay reactive to their source
  signals, plus a fix for same-type signal collision.
- **SEO and OTA.** Structured data emission, and OTA version gates.
- **New build targets.** `chrome-extension` and `firefox-extension` produce
  loadable MV3 bundles from web output plus a generated manifest and background
  script. `fuchsia` returned as a target on a Dartvel-forked embedder that
  packages an arbitrary Flutter app. `tvos` moved onto the community
  `flutter-tvos` embedder — see *Fixed* for why that matters.
- **Platform scaffold generation.** `dartvel build` generates the platform
  directory an embedder refuses to build without (`tizen/`, `elinux/`, `webos/`,
  `tvos/`) through the vendor's own `create`, rather than failing with a manual
  step. A scaffold that fails partway is removed rather than left to satisfy the
  next run's existence check.
- **Streaming HTTP transport.** `dvStreamHttpRequest` yields a body as it
  arrives and keeps the client open until it ends; `DVHttpResponse.data`
  decodes JSON, returning text when the body is not JSON and null when empty.
- **Page bundles reach installed apps.** `DV.Updates.applyPages(from:)` fetches
  a Studio bundle and applies it, returning a typed `DVPageUpdateResult` rather
  than a bool, because the interesting outcomes are not success and failure: a
  redelivered patch is inert on purpose, a version-locked device declines on
  purpose, and a source with nothing to serve is not an error. It deliberately
  avoids `DVNativeBridge` — page bundles are data, not code, so they need no
  Shorebird patch and no store review. The bundle machinery and the override
  machinery were each already tested; nothing had joined them.
- **The page builder's styling vocabulary.** The renderer honoured two of the
  twenty-one properties `DVModifier` offers and the inspector exposed one of
  those two, so `padding` was applied by the platform with no control able to
  set it. Both now read one `dvStudioProperties` list carrying each property's
  name, how it is edited, and the closure that applies it, which makes the
  drift structurally impossible rather than merely repaired. Twelve controls:
  fontSize, letterSpacing, padding, margin, width, height, rounded, color,
  backgroundColor, fontWeight, align and card. Colours are read from both the
  `0xAARRGGBB` integer the `@DVPage` annotation uses and the `#RRGGBB` string a
  web colour input produces; an unreadable value is ignored rather than guessed
  at, so a typo renders unstyled instead of black.
- **Encrypted model fields.** `@DVModel.sensitiveField(encrypted: true)` used to
  be read by nothing, then refused outright, because there was no server-side
  key to wire it to. `DVFieldCipher` is AES-256-GCM over a keyring read from
  `DARTVEL_FIELD_KEYS` in the server process environment — the key can live
  nowhere the generator reaches, since generated model code is compiled into the
  application bundle too. The generator seals the value before it becomes a
  bound parameter and opens it in `_fromRow`, so the plaintext is never in a
  statement a driver might log; with no keyring the field raises rather than
  falling back to plaintext. The model and column names are authenticated with
  the value, so a ciphertext moved to another column will not open. The ring
  holds several keys, newest first, so rotation does not have to rewrite every
  row before the new key takes over. Refused at generation time: a non-String
  field, and the field generated lookups use, where a randomized ciphertext
  would make `find()` miss and `save()` duplicate the row.
- **`docs/spec-status.json` and its checker.** Implementation status per spec
  section, with two independent labels — `stability` (Draft/Contract) and
  `status` (Designed/Partial/Shipped) — because a frozen contract that is
  deliberately unbuilt is the scope rule working, not a gap. A Partial or
  Shipped entry must cite evidence that exists and Partial must say what is
  absent; `dart run tool/spec_status_check.dart` enforces both and runs in CI.
  It replaces the status paragraph that had been copied across seven agent rule
  files, rather than becoming an eighth copy.

### Fixed

- **Local auth accepted any password.** `LocalAuthProvider.signIn` and
  `DVLocalAuthProvider.signInWithEmailAndPassword` returned a user for any
  e-mail with any password and never stored the password at sign-up. Both now
  keep salted hashes and reject an unknown account or a wrong password. They
  remain development and test adapters.
- **Shipped features were unreachable from applications.** `dartvel_flutter`
  re-exports core through a `show` list, and `DVDatabaseQueueAdapter`,
  `DVJobPayloadCodec(s)`, `LocalAuthProvider` and `AuthProvider` were missing
  from it — the durable-queue feature was unusable despite passing its own
  tests. The focused entrypoints (`package:dartvel/dartvel_ai.dart` and
  siblings) exported only their facade, so no adapter could be passed to
  `configure`. Both surfaces now have tests that import the way an application
  does and fail to compile when a symbol is missing.
- **Sensitive fields reached generated exports.** `@DVModel.sensitiveField()` is
  specified as excluded from generated tables, but CSV and Excel emitted a
  column per field and the JSON/NDJSON exports called `toJson()` rather than
  `toPublicJson()` — `Account.Export.csv(accounts)` produced a file containing
  every tax number. Sensitive columns now require
  `DVExportOptions(includeSensitiveFields: true)`.
- **Sensitive fields reached generated forms.** `showInForms` defaults to false,
  but the generator read only the annotated field's name and never its
  arguments, so every sensitive field got a form getter.
- **A source directory was never committed, so no clean clone could build.**
  `.gitignore`'s bare `build/` matches at every depth, and
  `packages/dartvel_cli/lib/src/build/` is a source directory that happens to be
  named build. Its only file existed solely as an untracked file on the machine
  that wrote it — `git log --all` on the path is empty. Because the import sits
  at the top of `build_command.dart`, ahead of any platform dispatch, *every*
  `dartvel build <target>` failed to compile from a fresh checkout. The ignore
  rule now carves out `lib/` trees, and the file is rebuilt against the test
  that did survive.
- **`dartvel build tvos` built an iPhone app.** The CLI mapped `tvos` onto the
  iOS toolchain and ran `flutter build ios --no-codesign`, so the platform
  matrix reported a green tvOS job for an artifact that was not a tvOS app.
  tvOS now runs through the `flutter-tvos` embedder, which carries its own
  Flutter SDK and origin-signed engine artifacts.
- **A model-less application generated a client that did not compile.** The
  generated runtime calls `registerDartvelModels()` unconditionally, but an
  application with no `@DVModel` inputs got a bare `library` stub — the function
  was discarded with the rest of the buffer. Two of the three example apps were
  broken.
- **The native-asset hook built for the host, not the target.** A macOS
  universal build invokes the hook once per architecture and `lipo`s the
  results, so answering both requests with a host-arch dylib failed the link
  with "have the same architectures". The triple now comes from the requested
  target OS and architecture.
- **The same hook could block forever.** Because a universal build runs it twice
  concurrently, both invocations contended on one `~/.rustup` lock, and the hook
  prints nothing while blocked — a build went silent for five hours and
  fifty-six minutes before CI's own cap killed it. Nothing in the hook can wait
  indefinitely now.
- **Toolchain installed, toolchain not found.** Auto-install extends the PATH
  handed to child processes, but the scaffold step did not receive that
  environment, so the availability check resolved an embedder that the very next
  line could not execute.
- **`dartvel doctor` could not answer for three buildable targets.** The
  allowlist was a hand-written literal that rejected `tvos` outright and made
  the browser-extension arms of the check unreachable. It is now derived from
  the build command's own target sets.
- **The generated client depended on a package nothing declared.** It imported
  `dio`, which meant every Dartvel application depended on a third-party HTTP
  package whether it wanted to or not — and until `dartvel_core` declared it,
  none of them compiled. Requests and SSE streams now go through Dartvel's own
  transport.
- **Entitlements were keyed by `hashCode`, so customers shared them.**
- **`DVForm` threw away every edit it collected**, and form fields drew their
  value as a placeholder.
- **Generated models could not survive a JSON round trip**, and the generated
  client did not compile for common field types.
- **Routes starting with an underscore generated private targets.**
- **The generated admin pages called a modifier that never existed.**
- **The `dartvel_shelf` native build was broken** and streaming responses did
  not work.
- **The Studio inspector overflowed once it had more than four fields.** An
  unbounded label overflowed its row, and the inspector had no bounded height
  to scroll within. Labels are now flexible with accepted values on their own
  hint line, and the three editor panes share the height the toolbar leaves.

### Changed — breaking

- `DV.Cache.revalidateTag` returns `Future<Set<String>>`; it now removes
  entries through the configured adapter.
- `DV.Test.fakeStorage()` returns a `DVMemoryFileStorageAdapter` rather than the
  raw `Map`, and a missing object throws `DVFileStorageException` rather than
  `StateError`.
- `LocalAuthProvider` requires an account to exist before sign-in and raises the
  minimum password length to 8; failures are `AuthException` carrying an
  `AuthFailure`.

### Not implemented

Recorded so the gaps are visible rather than assumed, and corrected as things
ship — an earlier revision of this list went stale and claimed Postgres, MySQL,
Redis, Memcached, PostgreSQL full-text search, Web Push, magic links and OTP
were missing weeks after they landed.

Still absent: MongoDB, Turso, ClickHouse and BigQuery databases; SQS, Pub/Sub,
RabbitMQ and Kafka queues; Azure Blob and Google Cloud Storage; APNS, which
needs HTTP/2; LDAP and SAML; GraphQL directives and subscriptions, which error
rather than silently no-op.

Partial: the `DV.Platform` device APIs. Eight binding names work on Linux
desktop over `dart:ffi`; the other 35 remain unregistered there, and all 43 are
unimplemented on Android, iOS, macOS, Windows and web. An unregistered binding
throws rather than returning a plausible value.

### Verified

Suites, on Linux x64 with Flutter 3.44.5 / Dart 3.12.2:

- `packages/dartvel_core`: 496 passing (6 skipped, needing memcached).
- `packages/dartvel_cli`: 236 passing.
- `packages/dartvel_flutter`: 191 passing.
- `packages/dartvel`, `packages/dartvel_generator`, `packages/dartvel_shelf`:
  4, 2 and 5 passing.
- `examples/`: 16, 1 and 1 passing across the three apps.

Builds, run and inspected rather than inferred:

- `web`, including the Wasm dry run, which is the real check — it fails on
  `dart:ffi` and `dart:io` reachability that plain JS compilation tolerates.
- `linux`, verified by **running** it: the release binary ran headless under
  Xvfb with the hook-built `libdartvel_shelf.so` bundled, and a screenshot
  showed the UI with `DV.Platform` reporting `linux`/`desktop` and signals live.
- `chrome-extension` and `firefox-extension`, with the two manifests confirmed
  to differ rather than one being a copy of the other — Firefox refuses a
  manifest declaring `service_worker`, so a shared one would silently not load.
- `ios`, on a macOS runner: `Runner.app`, 15.4 MB.

`macos` reached Xcode and failed in `lipo`; the fix is in but unverified.
`windows` and `tvos` remain unproven. `sony-elinux` and `webos` are blocked by
Dart version floors in their vendor embedders. See `docs/build-targets.md`,
which records the evidence per target and what each one actually hit.

## 0.2.1 — 2026-07-29

Packages at 0.2.1: `dartvel`, `dartvel_core`, `dartvel_flutter`, `dartvel_cli`.

### Fixed

- Generated private `@DVPage` expression bodies now compile when they reference
  generated client APIs and public source support symbols.
- The Dartvel example app no longer routes through public widget helper
  functions for generated page inputs.
- `dartvel --version` reports the active CLI package version instead of a stale
  fallback.
- CLI `db`, `ai`, `deploy`, plugin, and form generation commands now fail
  honestly or produce concrete artifacts instead of placeholder success output.

### Verified

- `packages/dartvel_cli`: `dart analyze .`, focused generator/version tests.
- `packages/dartvel_generator`: `dart analyze .`, `dart test`.
- `examples/dartvel_example`: `flutter analyze`, `flutter test`,
  `flutter build web`.

## 0.2.0 — 2026-07-26

Packages at 0.2.0: `dartvel`, `dartvel_core`, `dartvel_flutter`, `dartvel_cli`.

### Added

- **Lifecycle signals.** `DV.lifecycle.app` / `.build` and
  `context.lifecycle.page` / `.request` / `.transaction`, as read-only enum
  signals. The framework owns transitions; application code observes them. A
  failing observer cannot break a transition for others.
- **Modules.** `DV.Modules.<id>` registry with per-module lifecycle, immutable
  parent-supplied config, and `resolve()` so module code never hard-codes its
  mount point.
- **Reversible transactions.** `DV.transaction(...)` with
  `context.afterCommit(...)` for irreversible effects and
  `context.compensate(...)` for external effects Dartvel cannot reverse.
  Compensations run in reverse registration order; a failing compensation does
  not stop the rest, and `DVCompensationException` carries the original cause
  alongside rollback failures. Nested calls join the active transaction unless
  `isolated: true`.
- **`@DVStaticPaths()`** is now discovered during generation and emitted to
  `dartvel_client/static_paths.g.dart`, so parameterized routes can be
  statically generated.
- **Toolchain preflight for `dartvel build`.** Checks host support, then
  required tooling, before doing any generation work. Prompts interactively,
  installs unattended under CI so a pipeline cannot hang, and honours
  `--auto-install` / `--no-auto-install`. Tools installed mid-run are added to
  the `PATH` handed to child processes.
- **Embedded and television build targets:** `tizen` (alias `tpk`),
  `sony-elinux` (plus `-iso` / `-img`), and `webos`, each driven by the
  vendor's Flutter embedder through a Dartvel-maintained fork.
- **`@DVModel.sensitiveField()`** redaction: excluded from `toPublicJson()`,
  generated cards, search, logs and AI context, while `toJson()` stays complete
  for persistence.
- `DV.baseUrl` / `DV.api(...)` for application code.
- `DV.currentTenant` is now dynamic, with context scoping and `withTenant`.
- GitHub Actions matrix for the Windows/macOS/iOS/tvOS targets that cannot be
  built on a Linux development machine.

### Changed

- **Breaking:** model-scoped annotations now live under `DVModel`:
  `@DVSensitiveModelField()` → `@DVModel.sensitiveField()` and
  `@DVSearchable()` → `@DVModel.searchableField()`. The old names remain as
  `@Deprecated` aliases and both spellings still generate.
- **Breaking:** `DVBox.wrapLine` is the canonical wrap layout; `DVBox.wrap`
  remains a compatibility alias.
- `go_router` is named as the generated router's engine.
- The licence is now unambiguously proprietary. The previous file declared the
  work private above a fully commented-out MIT grant.

### Fixed

- `dartvel build <platform>` honours the positional argument. It was read only
  from `-p/--platform` (default `all`), so every documented positional form was
  silently ignored and built every platform.
- Desktop targets are no longer claimed to cross-compile. `dartvel build
  windows` reported itself available on Linux and hard-failed instead of
  skipping; Flutter has no desktop cross-compilation.
- Tizen TPKs contain the Flutter payload. Native builds produced a ~15KB
  package holding only the compiled runner — installable, but inert — because
  `tizen package -e` reports success without injecting the payload on Tizen SDK
  CLI 10.x. Fixed in the fork; verified 15KB → 9.3MB.

### Known gaps

- `Model.Page` data-mode rendering (`.async` / `.signal` / `.fromId`) and
  `@DVModel(generatePublicPages: true)` are **not** implemented. The
  `DVModelPageDataMode` enum and both annotation parameters are accepted and
  surfaced as generated metadata, but no generator acts on them.
- `sony-elinux` cannot build a Dartvel app: the embedder's newest Flutter ships
  Dart 3.7.2, below the ≥3.9 floor required by `dartvel_shelf`'s native-asset
  build hook.
- `webos` builds are not yet demonstrated.
- `windows`, `macos`, `ios` and `tvos` are unverified pending a CI run.

See [docs/build-targets.md](docs/build-targets.md) for per-target evidence and
the *Alpha status* section of [README.md](README.md) for what is implemented.

## v0.1 — 2025-08-28

Initial pre-release of dartvel.

Packages at 0.1.0:
- dartvel_core
- dartvel_flutter
- dartvel_cli
- dartvel_shelf
