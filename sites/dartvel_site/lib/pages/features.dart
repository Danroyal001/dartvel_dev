import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';
import '../components/site.dart';

/// Every section the repository records as Shipped, and nothing else.
///
/// The list is taken from docs/spec-status.json, which is checked by a tool
/// that fails when a section claims to be built and the evidence it names does
/// not exist. A marketing page that listed more than that would be the first
/// place the project stopped being honest.
/// Public because the page body is lowered into the generated router,
/// which reaches a page's public symbols through its import and cannot see
/// a private one at all.
const List<(String, String, String)> shipped = <(String, String, String)>[
  (
    'UI',
    'DVBox and DVText',
    'One layout primitive with a fluent modifier chain. DVBox.list, .row, '
        '.grid and .wrapLine for collections; DVBox(child) for a single one.',
  ),
  (
    'Styling',
    'Fluent modifiers',
    'padding, rounded, colour, typography, shadows, tap targets and '
        'semantics on one chain, built on Mix. Rotation takes degrees '
        'rather than radians, so the number a designer reads in Figma is '
        'the number in the source. blur and backdropBlur are separate '
        'methods, because one softens the box and the other softens '
        'whatever shows through it. The chain reaches text as well as boxes '
        'now, and a rounded box clips what is inside it -- both were '
        'accepted and ignored before, which is how every circular avatar '
        'came through as a square photograph.',
  ),
  (
    'Routing',
    'File-based pages',
    'A file under lib/pages is a route. Navigation is typed against generated '
        'targets, so a moved page is a compile error rather than a 404.',
  ),
  (
    'State',
    'Signals',
    'context.signal, signal(context, value), reactive models and DV.global. '
        'Operating on signals returns a signal, so a + b and stock > 0 track '
        'their sources without a separate computed type.',
  ),
  (
    'Models',
    '@DVModel',
    'One annotated class generates the typed client, serialization, the form, '
        'the table, the admin surface and the sync. Which meant that reading the '
        'annotation wrongly cost all of them at once, and it was read wrongly in '
        'two ways. The pattern that finds a model stopped at the first closing '
        'bracket, so a string argument containing one -- a schema type of '
        'Product (beta), say -- ended the annotation early and the model was not '
        'found at all: no class, no table, no admin row, no graph node, on a '
        'build that succeeded. Six separate parsers carried that pattern, and a '
        'model one of them misses while another finds it is a table in the '
        'database with no row anywhere else. The same scan now skips strings and '
        'comments, because an annotation written about in a paragraph is not an '
        'annotation -- this page describes one further down, and a parser that '
        'took the first one it saw in the file read the paragraph.',
  ),
  (
    'Forms',
    'DVForm<T>',
    'Inputs, validation and error surfaces derived from the model, so a field '
        'added to the model appears in the form.',
  ),
  (
    'Backend',
    '@DVBackendFunction',
    'A Dart function becomes an endpoint, served by an Axum and Tokio runtime '
        'in Rust reached over FFI, with the client generated alongside it.',
  ),
  (
    'Streaming Functions',
    'Server-sent events',
    'A backend function that returns a stream is served as SSE, with a typed '
        'client that consumes it.',
  ),
  (
    'Authorization',
    'DV.Auth.authorization',
    'Policies over models, functions and pages, enforced before the '
        'handler runs rather than inside it, and default-deny: a policy '
        'nobody registered answers no. A page declares one through '
        '@DVPage(policy:), and a page whose application has configured '
        'nothing to answer it is refused rather than opened. Policy classes '
        'are consulted now -- the specification\'s own headline example '
        'compiled and was never read. Absent: a generated admin still draws '
        'New and Delete without asking first.',
  ),
  (
    'Theme',
    'Light and dark',
    'A themed surface that follows the system by default. This site runs on '
        'it — switch your appearance and it follows.',
  ),
  (
    'Model Sync and Presence',
    'Built on models and signals',
    'Generated sync, subscriptions, presence and fanout. There is no '
        'DV.Realtime namespace, deliberately: it is models, signals and queues.',
  ),
  (
    'SEO',
    'Head tags, prerendering and a sitemap that says something',
    'dartvel build web writes the title, description, canonical, Open '
        'Graph and Twitter tags from configuration, and prerendered routes '
        'carry semantic content for crawlers. The sitemap leaves out routes '
        'the router guards; it used to publish every private one, because '
        'it read path literals and a pattern cannot see the guard three '
        'lines under it. A page tunes its own entry with @DVPage(sitemap:), '
        'the project sets the defaults under dartvel.seo.sitemap, and a '
        'priority outside 0 to 1 is refused rather than clamped, since a '
        'crawler discards the whole entry.',
  ),
  (
    'AI',
    'DV.AI, and tools a provider can call',
    'A local adapter, structured outputs and embeddings, with provider '
        'extension points. A function marked as an AI tool is registered with a '
        'handler now, which it was not: the generated list carried a name, a '
        'description and a file path, so an assistant could read that a function '
        'existed and had no way to run it. Each tool gets a JSON Schema, because '
        'every provider requires one, and an argument of the wrong type is '
        'refused by name rather than coerced -- a tool that quietly received 0 '
        'for a number it could not read would run and be wrong, which is the '
        'thing a schema exists to prevent.',
  ),
  (
    'CSRF Protection',
    'On by default',
    'Token issue and verification wired through the request pipeline rather '
        'than left to the application.',
  ),
  (
    'Reversible Transactions',
    'DV.transaction',
    'context.afterCommit and context.compensate, so a failure unwinds what '
        'ran rather than leaving it half-applied.',
  ),
  (
    'Background and Durable Work',
    '@DVJob and DV.Queues',
    'Durable jobs and queues. background: true and durable: true on a backend '
        'function are sugar that compiles onto the same layer.',
  ),
  (
    'Authentication',
    'Four ways in',
    'WebAuthn assertions, SAML 2.0 built against signature wrapping rather '
        'than around it, LDAP over BER, and Sign-In with Ethereum bound to a '
        'nonce, a domain and a clock.',
  ),
  (
    'Cache',
    'Rendezvous hashing',
    'Keys spread across several servers. Adding or removing a node moves only '
        'that node’s share — with a modulo it moves almost everything, and the '
        'cache empties without reporting anything.',
  ),
  (
    'File Storage',
    'S3, Azure Blob, GCS',
    'Verified against Azurite and fake-gcs-server in CI, not against fakes. '
        'Azure signs the encoded path, which only a real server will tell you.',
  ),
  (
    'Search',
    'Meilisearch, OpenSearch, Algolia',
    'With highlights and facet counts, which an engine returns only when the '
        'query asks. Run against real Meilisearch and OpenSearch in CI.',
  ),
  (
    'APIs',
    'Flat-buffer envelope',
    'Form-data whose fields are binary buffers, so an int stays an int. Over '
        'text multipart the type is gone by the time a parameter is decoded.',
  ),
  (
    'Admin, Devtools, and Scaffolding',
    'dartvel inspect, dartvel mcp',
    'One versioned graph of routes, models, functions and jobs, each '
        'carrying the source it came from. --json is a serialization of it, '
        'and dartvel mcp serves it to a coding agent. The dashboard is '
        'served by the backend at a path the project chooses rather than a '
        'constant -- a fixed admin path is most of why wp-admin is the most '
        'scanned URL on the internet. It is guarded, absent from a release '
        'build unless asked for, and answers a signed-out request exactly '
        'as a route that does not exist, since a 401 where the rest of the '
        'site answers 404 tells a scanner the host has one.',
  ),
  (
    'Pages',
    'Every annotation',
    '@DVPage, @DVFunctionalWidget, @DVBackendFunction and @DVJob.handler all '
        'take a block body. No more one-line wrappers around a public helper.',
  ),
  (
    'Queues, Jobs, and Signals',
    'DV.Jobs and DVQueues',
    'Typed job payloads with retries, backoff, dead letters and idempotency '
        'keys. Signals stay context.signal and reactive models; cross-client '
        'delivery rides model sync rather than a second event system.',
  ),
  (
    'Database',
    'SQLite by default, and migrations that run',
    'Zero-config SQLite with WAL for local work, in-memory for tests, '
        'Postgres and MySQL with TLS, and one adapter API in front of all '
        'of them. Migrations execute now: dartvel db migrate used to print '
        'a line per model, say they were synced successfully, and run '
        'nothing at all. For Postgres or MySQL it writes the statements out '
        'and says it did not run them, because the CLI has no connection to '
        'a managed database. A table that already has rows is left alone '
        'rather than half migrated.',
  ),
  (
    'Testing',
    'dartvel test',
    'Fake auth, queues, mail, storage, AI and windowing, generated model '
        'factories, and a build that fails on an accessibility regression instead '
        'of warning about one.',
  ),
  (
    'Data Import, Export, and Reporting',
    'Order.Import.csv',
    'Generated CSV, NDJSON and Excel import and export per model. Resumable '
        'imports are chunked onto the queue with the header carried on every '
        'chunk, so a worker can always rebuild a row.',
  ),
  (
    'Deployment',
    'dartvel deploy',
    'Web and server targets to Firebase, Vercel, Netlify, Cloudflare or a '
        'custom host from one command, with the backend compiled to its Rust '
        'runtime and the client to its target.',
  ),
  (
    'CLI',
    'One tool',
    'create, dev, build, doctor, inspect, explain, i18n, queue, cache and sh. '
        'build runs generation for you; doctor says what each target can '
        'actually do; explain looks up any diagnostic code. The shell is part of '
        'it: a typed surface for project tasks, commands as values and results '
        'as values, reachable from Dart, from dartvel task and from dartvel sh.',
  ),
  (
    'Backend Function Request Lifecycle',
    'context.lifecycle.request',
    'Every call moves through received, decoding, authenticating, validating, '
        'authorized, executing, committing and encoding as a read-only signal, '
        'with trace, tenant and idempotency IDs carried the whole way.',
  ),
  (
    'Static Web Generation',
    'dartvel build web',
    'Per-route HTML built from the semantics tree a real browser produced, '
        'sitemap.xml and robots.txt, a service worker and install prompt, and a '
        'build that fails when a page would ship with nothing to see.',
  ),
  (
    'Internationalization and Localization',
    'Typed keys, CLDR plurals',
    'Translation keys are typed and extracted to ARB; plurals follow CLDR, '
        'not English. Locale negotiation reads the path, a stored preference and '
        'Accept-Language in that order, with a per-tenant default; mail and '
        'notification templates render in the recipient\'s language, and every '
        'prerendered page carries hreflang.',
  ),
  (
    'Dartvel Studio',
    'Visual builder, exports to code',
    'Pages built from the same widgets the application renders, on a '
        'canvas that draws them the way the page will. Styling travels to '
        'the canvas and behaviour does not, because a canvas that navigates '
        'away when you tap the card you are editing is worse than one that '
        'shows it unstyled. Drag-and-drop, an inspector, undo, mobile-first '
        'breakpoints, and one-click export to an ordinary @DVPage whose '
        'source is handed to the analyzer in CI. Pro adds components, '
        'revision history, multi-user editing, roles and approval before a '
        'page goes live -- and Figma import, where frames become pages, '
        'prototype links become navigation, and auto-layout, gradients, '
        'blurs, strokes and icons all survive the crossing.',
  ),
  (
    'Accessibility',
    'Audited at release, driveable by a switch',
    'dartvel build web audits the semantics tree a real browser produced and '
        'fails on a nameless control, an empty heading or a skipped level, unless '
        'waived with a written reason. Generated tables navigate by keyboard and '
        'announce cells; contrast and tap targets are checked against published '
        'minimums; motion follows the platform\'s reduced-motion setting. Kiosk '
        'and embedded pages are driveable by one or two switches, auto-scan, or a '
        'remote\'s D-pad, and a kiosk\'s key block never covers the keys '
        'accessibility needs.',
  ),
  (
    'PWA',
    'Installable, offline, and it keeps your writes',
    'dartvel build web writes the manifest, the icons from web/icon.png, the '
        'offline page and a service worker that caches assets and keeps an '
        'outbox: a write made while the network is gone is answered 202 and '
        'replayed, in order, once it is back. That last part is proven in a '
        'real Chrome on every push, not read off the generator. The install '
        'prompt asks the browser now, and did not: it returned a value only a '
        'test could set, so it reported an acceptance whatever the person at the '
        'screen chose and then marked the application installed -- which hides '
        'the button, so an application somebody declined could never be '
        'installed from inside it again. The binding that opens the browser\'s '
        'own dialog was written and called by nothing at all, so tapping Install '
        'opened nothing. It waits for the answer now, because the browser only '
        'opens the dialog when asked and reports the choice afterwards.',
  ),
  (
    'Scheduling',
    'Cron on both sides, and it runs now',
    'Five-field cron parsed the way cron actually reads it, '
        'day-of-month OR day-of-week, with nextAfter for the next tick and '
        'a scheduler that dispatches onto the queue rather than running '
        'inline. A served backend registers every declared schedule and '
        'ticks; an application with none starts no timer. A schedule says '
        'for itself whether the periods missed while the process was down '
        'are run when it comes back. On a phone it ticks only while the '
        'application is in front of somebody, and ticks once immediately on '
        'return.',
  ),
];

/// Half built: what is present and what is absent, in the repository's own
/// words. The checker holds this list to the index's Partial sections exactly.
const List<(String, String, String)> partial = <(String, String, String)>[
  (
    'Generated Model Pages',
    'Model.Page(...), wearing its own icon',
    'Public pages from a model, with .async, .signal and .fromId. '
        'Static paths come from the model rather than a route written out '
        'as a string. A model page wears its own favicon now: a model '
        'declares one, a module\'s models carry the module\'s, and '
        'dartvel.seo.favicon is the application\'s. Absent: the resized, '
        'content-hashed derivative of the featured image, since pointing an '
        'icon straight at a photograph serves several hundred kilobytes as '
        'thirty-two pixels.',
  ),
  (
    'Lifecycle Signals',
    'Five of six change',
    'DV.lifecycle.app and .build, context.lifecycle.page, .request and '
        '.transaction. Application code observes them; it does not assign '
        'them. Five of the six move -- the request signal on a backend '
        'function that asks for a context, the page signal on every '
        'generated route, and the application signal reporting what the '
        'platform gives it, where hidden counts as backgrounded and '
        'inactive counts as nothing. Absent: the states belonging to a data '
        'fetch or a route transition, and anything that advances the build '
        'signal.',
  ),
  (
    'Middleware',
    'Ten run, tracing wraps, two guard the body, five say why not',
    'Ten middlewares run in the order declared, wrapped around the '
        'handler, with the request lifecycle observable as a signal. The '
        'nineteen keys did nothing until recently: the annotation had one '
        'reader, a check that the name was spelled correctly, which then '
        'dropped the list. Body and upload limits are checked where the '
        'body is read instead, because by the time a chain has anything to '
        'say the body is already in memory. dartvel.server configures CORS '
        'and compression for the whole server. The remaining five fail the '
        'build naming what to use instead.',
  ),
  (
    'Multi-tenancy',
    'All three strategies, and a shared database that filters',
    'Present: the current tenant is resolved from the configured source '
        'and held in a zone, so it follows async work instead of leaking '
        'between concurrent requests. Generated model queries filter by it '
        '-- a column, a predicate on every read, the tenant written into '
        'every write, and a delete that cannot reach another tenant\'s row, '
        'all arriving together because any one of them alone looks exactly '
        'like the feature working. All three strategies do something now; '
        'schema-per-tenant and database-per-tenant used to produce exactly '
        'the shared strategy\'s queries against exactly the same database. '
        'A raw query the application writes itself is checked too. Absent: '
        'creating the per-tenant schemas, which needs a list of tenants the '
        'build does not have.',
  ),
  (
    'Sensitive Model Fields',
    '@DVModel.sensitiveField(); encrypted: true refused',
    'Excluded from logs, AI context, traces, analytics, public serialization, '
        'search, generated pages, tables and admin by default. Reaching a client '
        'takes an explicit policy. encrypted: true is not implemented: there is '
        'no server-side field-encryption key surface yet, so a field declaring '
        'it fails generation, naming the model and field, rather than being '
        'stored as plaintext under a flag that says otherwise.',
  ),
  (
    'App store publishing',
    'One command to a store, and every refusal before the upload',
    'Present: dartvel publish takes a built application to Google Play, App Store Connect, TestFlight or Firebase App Distribution, declared once in pubspec.yaml. The work is an upload of a binary that took minutes to produce, so every refusal comes before it: a track nobody publishes to is refused rather than corrected to the nearest, credentials that were never declared are refused rather than left to a tool that stops to ask a pipeline with nobody to answer, and App Store Connect is refused off macOS at the start rather than with "command not found" at the end of a long build. --dry-run shows what Dartvel would do to a store account before it does it, and the upload uploads and nothing else. Absent: the stores are driven through their own tools rather than their APIs, so a machine without one is told to install it; nothing has been published from CI, which needs an account and a signing identity; and metadata, screenshots and staged rollouts are deliberately left alone.',
  ),
  (
    'Home Widgets',
    'Generated pages, packaged on Android and on Apple',
    'Present: @DVHomeWidget on any widget generates a page at '
        '/widgets/<id> and packages it for the home screen -- an '
        'AppWidgetProvider, layout and receiver on Android, and a WidgetKit '
        'bundle with its own entitlements and an Xcode target on iOS and '
        'macOS. Both draw the platform\'s own views rather than the Flutter '
        'tree, because a home screen is composed in the launcher\'s process '
        'and that cannot host a Flutter engine; what crosses is data, '
        'written through DVHomeWidgets.publish. A tap deep-links back into '
        'the application. Absent: an immediate refresh on Apple, since '
        'WidgetCenter is Swift-only.',
  ),
  (
    'Modules',
    'Mounted, with their routes, a verified manifest and their deployment modes',
    'Present: a module is a whole Dartvel application that a parent '
        'mounts. The build takes the module\'s own route base off and puts '
        'the mount point on, generates it before the parent, and serves its '
        'pages from the parent\'s router -- in the route index, in the '
        'sitemap, reachable as DV.Modules.<id>. A federated module '
        'publishes a signed manifest that the parent verifies before '
        'mounting, so a replayed version, a colliding route or an untrusted '
        'key is refused by name. Shell, auth, theme and data modes each '
        'apply at run time. Absent: the exports block, which is read by '
        'nothing -- named rather than half-built, because what a list of '
        'models governs is ambiguous and guessing would enforce something '
        'nobody chose.',
  ),
  (
    'Platform',
    'Runtime APIs everywhere; Linux bindings behind most names',
    'Present: the platform and screen APIs, FFI/JNI binding registration, and on Linux the bindings for clipboard, window, notifications, shortcuts, menus, printing, dialogs, kiosk keys and the device APIs. Absent: the names with no host API to reach on each platform -- 32 on Linux, 24 on web, 33 on Windows, 33 on macOS, 30 on iOS -- many of which do not apply there at all.',
  ),
  (
    'Mail and Notifications',
    'Every channel; SMTP against a real server, push not yet',
    'Present: email, in-app, push and web push with a VAPID signature pinned to the published P-256 vectors, local and test providers, and templates rendered in the recipient\'s language. The SMTP provider is exercised against a real SMTP server in a container, with the source of what arrived read back -- which is the only way to see the half of this that is accepted and wrong, and it found two things. A subject with an accent in it went down the wire as raw UTF-8 in a header that has to be ASCII: the server took it, and the clients that do not guess the encoding show it as mojibake to whoever was sent it. The body declared no transfer encoding, which means seven-bit, which it was not. Both are fixed and both are now checked against a server rather than against a connection this repository wrote. Absent: no provider has been exercised against a real APNS or push service.',
  ),
  (
    'OTA Updates',
    'Staged across a fleet, but not native patches',
    'Present: page bundles ship as data through DV.Updates and need no native patching, on named channels, and a staged rollout decides from the device and the version rather than at random -- so a device asked twice is answered the same. One question is asked and answered in one place: the channel\'s offer, the device\'s place in the rollout, a pinned version, a skipped one and a kiosk\'s maintenance window, so a check says whether to apply now, why not when not, and when it will be, and applying something the check held back is refused with the reason rather than quietly skipped. Absent: Shorebird-backed native patch application.',
  ),
  (
    'Billing',
    'Stripe and Paddle, and a price that is a price',
    'Present: checkout for a plan\'s configured price, and webhooks '
        'believed only when their own signature matches in constant time '
        'within five minutes. @DVModel(billable: true, nativePrice: 100) '
        'carries that price now and carried nothing before. A price needs '
        'three things to mean anything: a currency, a rule for what the '
        'integer counts -- a hundred yen is a hundred yen -- and a '
        'conversion that refuses rather than returning the same number '
        'under a different code. Absent: App Store and Play Billing '
        'purchases, and the rates themselves, which the application '
        'supplies.',
  ),
  (
    'Desktop, Embedded, and Qt-Critical Capabilities',
    'Built on Linux, and most of it on Windows and macOS',
    'Present on Linux: global shortcuts, the application menu, '
        'printing, system dialogs, file associations, deep links, the '
        'device and fleet APIs, and startup measured phase by phase. '
        'Present on Windows and macOS, each proven on its own runner: '
        'shortcuts delivered by id, the application menu, the tray and its '
        'menu, and the device APIs. Drag and drop, the tray and serial '
        'ports work on all three. NFC through neard and Bluetooth through '
        'BlueZ are present on Linux, including writing a tag and pairing a '
        'device -- the fussy part being that nearly every way those go '
        'wrong still reports success.',
  ),
  (
    'Kiosk Mode',
    'Policy, clock, windows and desktop enforcement; mobile and embedded per target',
    'Present: the policy, state machine and enforcement matrix, checked '
        'by dartvel doctor. Device- and display-scope kiosks, a session '
        'clock on DV.lifecycle.kiosk, and native enforcement per target -- '
        'lock task on Android, proved on an emulator with Android\'s own '
        'dumpsys as the second opinion; key blocking and pointer '
        'confinement on Linux; hot keys on Windows; presentation options on '
        'macOS; Fullscreen, Keyboard Lock and Pointer Lock in a browser. '
        'Text selection, the clipboard, cursor hiding and screen dimming '
        'are enforced in Dart. Whatever a platform refuses is reported '
        'unenforced rather than passed over, because a kiosk that could not '
        'hold and says nothing reads exactly like one that did. Absent: '
        'iPadOS, Tizen and webOS, and the three things a rule written in '
        'Dart cannot reach -- the system clipboard, the cursor outside the '
        'application\'s own surface, and the backlight.',
  ),
  (
    'Terminal Rendering',
    'A backend you opt into at build time',
    'Present: the terminal backend is linked only when asked for, through the dartvel_cli_flt fork; the terminal\'s size as a signal, read again on every resize; and launch negotiation wired into main -- --tui, no display with both backends, and the hand-off to the terminal runner beside the GUI binary. A Dartvel application renders in a terminal, verified in a pty: it could not before, because the bundle build reads a compiler configuration for a project\'s build hooks that nothing wrote where it looks, so the job proving the terminal had been rendering the embedder\'s own sample instead. Absent: the fork\'s own renderer, Kitty with an ANSI fallback, and a distributable runner.',
  ),
  (
    'Multi-Window',
    'Windows, displays and the single-instance launch',
    'Present: window identity as canonical URL, display enumeration on '
        'all three desktops, the exit policy, owned windows, honest '
        'modality, the single-instance launch that opens what the app was '
        'started with and hands a later launch to the first process, '
        'workspace restore, tear-out, display-scope kiosk windows, and a '
        'measured performance contract that dartvel analyze performance '
        'reads. The shared store reads its own tuning now: four numbers the '
        'specification documents and the build had never read, so a project '
        'that asked for a 64Kb spill threshold got 32. Absent: pollMs and '
        'sweepAfter, which have nothing behind them at all, and the three '
        'web and Android keys.',
  ),
  (
    'Tab Workspaces',
    'Tabs that tear out, hand over between windows and persist',
    'Present: the tab strip, reorder, tear-out gated on capability, the empty-window rule, duplicate tabs, deduplication by route, a switcher on TV and watch, persistence scoped to the tenant and the user that drops routes that no longer resolve, and a re-dock that hands the tab over instead of rebuilding it -- the element moves between workspaces in one frame, so what was half typed, where the list had been scrolled to and the controllers behind them are the same objects on the other side. Absent: the drag cannot leave a window. The OS holds the pointer in the window it went down in and Flutter routes the whole drag to that view, so no strip elsewhere ever sees it; a cross-window move is an action on the tab menu instead, and tear-out into a brand-new window still builds the route from scratch.',
  ),
  (
    'Secrets and Environments',
    'Declared, rotated, and kept where the platform keeps keys',
    'Present: the declaration manifest and its analyze rule, rotation hooks, dartvel key generate | rotate | status, and the application key in the Secret Service on Linux, DPAPI on Windows, the Keychain on macOS and a non-extractable WebCrypto key on the web, with a file only the user can read as the fallback. Absent: the Android Keystore.',
  ),
  (
    'Web Server Rendering',
    'Pages assembled on request, from the route\'s data',
    'Present: the request pipeline the spec describes, given a resolver for the route\'s data -- route resolved with its parameters, page data resolved by the declared mode (awaited, cached, stale-while-revalidate, or deferred to the client), visibility checked with 404 and 401, the head and JSON-LD structured data generated from the data, the page\'s favicon, crawler-visible text, the Flutter bootstrap, and streaming that sends the head first. The resolver is generated from the application\'s models: a public model page is its row\'s title, content, image and published flag, read from the database when the page is asked for, hidden when unpublished. The kept pages can live in a shared cache, so a second server serves what the first resolved, and a page\'s schema.org type is the one its model declares.',
  ),
  (
    'Embedded, Television, and Extension Build Targets',
    'Builds that exist; devices that have not run them',
    'Present: tizen and vscode build. Absent: neither has been run; fuchsia\'s engine does not build at Flutter 3.44.5; webOS and Sony eLinux ship a Dart below the 3.12 floor, so their embedders cannot resolve the example.',
  ),
  (
    'Monitoring and Observability',
    'Metrics and health are real; logs are not',
    'Present: DVMetrics renders Prometheus text exposition and every server answers GET /metrics with it; dartvel metrics reads that endpoint and says so when nothing answers or nothing has been recorded yet, rather than printing a sample. DVHealth backs GET /health with real checks on a deadline. Tracing carries W3C Trace Context across the request boundary, with sampling decided from the trace id alone so a distributed request is not resampled at every hop. Absent: there is no log sink anywhere in the runtime, so DV.log and DV.ObservabilityAndLogging.event do not exist and nothing an application logs goes anywhere -- dartvel logs says so plainly instead of printing invented lines. Spans are captured but only into an in-process list nothing exports or serves, so dartvel traces has nothing to read either. Profiling, performance analysis, error reporting, and structured, AI-readable diagnostics are all unbuilt too.',
  ),
];

// Tuned, so the whole chain runs on a real project rather than only in a
// test: the annotation, the constant the generator writes into the
// router, the build that reads it back, and the <priority> and
// <changefreq> in build/web/sitemap.xml that CI then asserts.
//
// This file also describes the annotation in prose, a few hundred lines
// up, which is the shape that broke the parser once: it searched for the
// first @DVPage( in the file and found the paragraph.
@DVPage(
  title: 'Features — Dartvel',
  showAppBar: false,
  sitemap: DVPageSitemap(
    priority: 0.8,
    changeFrequency: DVSitemapChangeFrequency.weekly,
  ),
)
@pragma('vm:entry-point')
Widget _featuresPage(BuildContext context) => SingleChildScrollView(
  child: DVBox.list(<Widget>[
    const Section(
      children: <Widget>[
        Eyebrow('WHAT WORKS TODAY'),
        Heading('Thirty-six shipped sections.', level: 1),
        // Two sentences that were one forty-five word sentence with a
        // clause chain, and a second that said "partial" three times.
        Body(
          'This is the repository’s own record, not a roadmap. A checker '
          'reads it on every build and fails the build when a section '
          'claims to be built and the evidence it names is not there.',
          width: 620,
        ),
        Body(
          'Twenty-one more are half done. Each says what is missing, '
          'next to what already works.',
          width: 620,
        ),
      ],
    ),
    Section(
      tint: true,
      children: <Widget>[
        // A grid where there is room. Twenty-one full-width rows
        // separated by hairlines is a list to scroll past rather than a
        // set of things to compare, and every one of them looked the
        // same as the last.
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final int columns = constraints.maxWidth >= 900 ? 2 : 1;
            if (columns == 1) {
              return DVBox.list(<Widget>[
                for (final (String area, String surface, String body) f
                    in shipped)
                  FeatureRow(area: f.$1, surface: f.$2, body: f.$3),
              ], spacing: 14);
            }
            const double gap = 18;
            final double width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: <Widget>[
                for (final (String area, String surface, String body) f
                    in shipped)
                  SizedBox(
                    width: width,
                    child: FeatureRow(area: f.$1, surface: f.$2, body: f.$3),
                  ),
              ],
            );
          },
        ),
      ],
    ),
    Section(
      children: <Widget>[
        const Eyebrow('HALF BUILT'),
        const Heading(
          'What is partial, and what is missing from it.',
          level: 2,
        ),
        const Body(
          'Each of these has real code behind it and a named gap. The '
          'gap is written next to the work, in the repository’s words, '
          'and the same tool holds this list to the index.',
          width: 660,
        ),
        DVBox.list(<Widget>[
          for (final (String area, String surface, String body) f in partial)
            FeatureRow(area: f.$1, surface: f.$2, body: f.$3),
        ], spacing: 14),
      ],
    ),
    const SiteFooter(),
  ], spacing: 0),
);

/// How much of a record a card shows before it is folded.
///
/// Four lines is about forty words, which is the first two sentences of every
/// one of these -- and the first two sentences are the summary, because they
/// were written as one.
const int kFeatureRecordLines = 4;

/// A lower bound on how wide one character can be, at the size a record is
/// set in.
///
/// Deliberately under any real glyph: it is used to work out how much text
/// could possibly fit on a line, and guessing low there means measuring a
/// little more than necessary rather than cutting a record short.
const double kNarrowestGlyph = 3;

/// One shipped capability: the area, the surface you actually type, and what
/// it does.
@DVFunctionalWidget()
Widget _featureRow(
  BuildContext context, {
  required String area,
  required String surface,
  required String body,
}) {
  final Palette palette = Palette.of(context);
  return DVBox(
    DVBox.list(<Widget>[
      // A wrapping line rather than a row. The chip carries an API name and
      // some of them are long: in a fixed row the pair overflowed its card by
      // a few pixels at one width and by forty at another, and an overflow
      // clips in release with nothing to say it did.
      DVBox.wrapLine(<Widget>[
        DVText(area).modifier(
          const DVModifier()
              .fontSize(17)
              .fontWeight(FontWeight.w700)
              .color(palette.ink)
              // Level 2, not 3: these sit directly under the page's h1 and
              // nothing on the page is an h2, so 3 skipped a level and a
              // reader navigating by heading was told they had missed one.
              // Without any level at all they were twenty-one paragraphs, so
              // the page had a title and no structure under it -- for a screen
              // reader moving by heading and for the crawler-visible HTML
              // alike.
              .semanticHeading(2),
        ),
        SiteChip(surface),
      ], spacing: 10),
      // The record, given the shape it was always two things in.
      //
      // Each of these is one string because that is how spec-status.json
      // holds it, and one string is what it was drawn as: a single block with
      // "Present:" and "Absent:" inside it as words. Shorter than it used to
      // be and still a wall -- no paragraphs, and the two halves that matter
      // most left for a reader to tell apart by punctuation.
      //
      // Parsed here rather than rewritten in the data, so the card cannot
      // carry a second copy of the record that drifts from the first.
      SiteRecord(body: body),
    ], spacing: 12),
    const DVModifier()
        // No height: a wrap gives its children unbounded height, so
        // double.infinity here collapsed every card and the section rendered
        // empty. Cards size to their content instead.
        .paddingOnly(left: 18, top: 16, right: 18, bottom: 18)
        // page, not surface: the section this sits on is tinted with surface,
        // so a card in the same colour is an invisible card.
        .backgroundColor(palette.page)
        .rounded(12)
        .border(Border.all(color: palette.rule)),
  );
}
