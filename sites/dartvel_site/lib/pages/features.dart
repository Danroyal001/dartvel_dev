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
    'padding, rounded, colour, typography, shadows, tap targets and semantics '
    'on one chain, built on Mix.',
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
    'the table, the admin surface and the sync.',
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
    'Policies over models and functions, enforced before a handler runs '
    'rather than inside it.',
  ),
  (
    'Middleware',
    'Request pipeline',
    'Composable middleware around backend functions, with the request '
    'lifecycle observable as a signal.',
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
    'Multi-tenancy',
    'Tenant scoping',
    'Tenant resolution and scoping through the model and request layers.',
  ),
  (
    'SEO',
    'Head tags and prerendering',
    'dartvel build web writes the title, description, canonical, Open Graph '
    'and Twitter tags from configuration, and prerendered routes carry '
    'semantic content for crawlers.',
  ),
  (
    'AI',
    'DV.AI',
    'A local adapter, structured outputs and embeddings, with provider '
    'extension points.',
  ),
  (
    'CSRF Protection',
    'On by default',
    'Token issue and verification wired through the request pipeline rather '
    'than left to the application.',
  ),
  (
    'Lifecycle Signals',
    'Read-only enums',
    'DV.lifecycle.app and .build, context.lifecycle.page, .request and '
    '.transaction. Application code observes them; it does not assign them.',
  ),
  (
    'Modules',
    'DV.Modules.<id>',
    'A module is a whole Dartvel application boundary, mounted by a parent. '
    'Module code never hard-codes its mount point.',
  ),
  (
    'Generated Model Pages',
    'Model.Page(...)',
    'Public pages from a model, with .async, .signal and .fromId. Static '
    'paths come from the model rather than a route written out as a string.',
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
    'Sensitive Model Fields',
    '@DVModel.sensitiveField()',
    'Excluded from logs, AI context, traces, analytics, public serialization, '
    'search, generated pages, tables and admin by default. Reaching a client '
    'takes an explicit policy.',
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
    'One versioned graph of routes, models, functions and jobs, with the '
    'source each was derived from. --json is a serialization of it, and '
    'dartvel mcp serves it to a coding agent.',
  ),
  (
    'Pages',
    'Every annotation',
    '@DVPage, @DVFunctionalWidget, @DVBackendFunction and @DVJob.handler all '
    'take a block body. No more one-line wrappers around a public helper.',
  ),
  (
    'Scheduling',
    'Cron on both sides',
    'Five-field cron parsed the way cron actually reads it, day-of-month OR '
    'day-of-week, with nextAfter for the next tick and a scheduler that '
    'dispatches onto the queue rather than running inline.',
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
    'SQLite by default',
    'Zero-config SQLite with WAL for local work and in-memory for tests, the '
    'same generated migrations against Postgres and MySQL, and one adapter '
    'API in front of all of them.',
  ),
  (
    'Monitoring and Observability',
    'DV.log, metrics, traces',
    'Structured logs that carry trace context, a Prometheus exposition '
    'endpoint, health checks that report down rather than hang, and W3C '
    'trace propagation through the Rust runtime.',
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
    'actually do; explain looks up any diagnostic code.',
  ),
  (
    '.dartvel.sh',
    'DVShell',
    'A typed shell for project tasks — commands as values, results as '
    'values — reachable from Dart, from dartvel task and from dartvel sh.',
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
    'Pages are built from the same widgets the app renders, with drag-and-drop, '
    'an inspector, undo, mobile-first breakpoints and one-click export to an '
    'ordinary @DVPage. Every mutation is also an edit another editor can apply. '
    'Pro adds what only matters with more than one person: Figma import, '
    'reusable components, revision history, multi-user editing with presence, '
    'roles, an audit trail and approval before a page goes live.',
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
    'real Chrome on every push, not read off the generator.',
  ),
];

/// Half built: what is present and what is absent, in the repository's own
/// words. The checker holds this list to the index's Partial sections exactly.
const List<(String, String, String)> partial = <(String, String, String)>[
  (
    'Platform',
    'Runtime APIs everywhere; Linux bindings behind most names',
    'Present: the platform and screen APIs, FFI/JNI binding registration, and on Linux the bindings for clipboard, window, notifications, shortcuts, menus, printing, dialogs, kiosk keys and the device APIs. Absent: the names with no host API to reach on each platform -- 32 on Linux, 24 on web, 33 on Windows, 33 on macOS, 30 on iOS -- many of which do not apply there at all.',
  ),
  (
    'Mail and Notifications',
    'Every channel, no live push service yet',
    'Present: email, in-app, push and web push with a VAPID signature pinned to the published P-256 vectors, local and test providers, and templates rendered in the recipient\'s language. Absent: no provider has been exercised against a real APNS or push service.',
  ),
  (
    'OTA Updates',
    'Page bundles, not native patches',
    'Present: page bundles ship as data through DV.Updates and need no native patching. Absent: Shorebird-backed native patch application.',
  ),
  (
    'Billing',
    'Stripe and Paddle; not the app stores',
    'Present: checkout for a plan\'s configured price and webhooks that grant and revoke entitlements, each believed only when its own signature matches in constant time within five minutes. Absent: App Store and Play Billing purchases, which need the store bindings.',
  ),
  (
    'Desktop, Embedded, and Qt-Critical Capabilities',
    'Built on Linux; Windows and macOS behind the same names',
    'Present on Linux: global shortcuts, the application menu, printing, system dialogs, file associations, app links and deep links, the launch that opens what the app was started with, and the device and fleet APIs -- manifest, health, watchdog, provisioning, diagnostics. Absent: tray icons (not claimed: no desktop shell runs under Xvfb to watch one), drag and drop, and on Windows and macOS everything Linux has.',
  ),
  (
    'Kiosk Mode',
    'Policy, clock, windows and desktop enforcement; mobile and embedded per target',
    'Present: the policy, state machine and enforcement matrix checked by dartvel doctor; named policies generated as DVKioskPolicies, with a device profile\'s kiosk entry over the section when dartvel build --device-profile selects it; the device-scope kiosk installed at start as DV.Platform.display.kiosk; display-scope kiosk windows pinned to a display; the session clock with its countdown and reset, on DV.lifecycle.kiosk; on Linux hardware-key blocking that never covers the keys accessibility needs, pointer confinement and notification suppression, on Windows hot keys and pointer confinement with what Win32 refuses reported unenforced, on macOS the presentation options that disable process switching and force quit; the screen-side host with its diagnostics screen; restart-loop detection; the sensitive-field analyze rule; and dartvel inspect kiosk, the effective policy per target and per window with each value\'s source. Absent: native enforcement on Android, iPadOS and the embedded targets.',
  ),
  (
    'Terminal Rendering',
    'A backend you opt into at build time',
    'Present: the terminal backend is linked only when asked for, through the dartvel_cli_flt fork; the terminal\'s size as a signal, read again on every resize; and launch negotiation wired into main -- --tui, no display with both backends, and the hand-off to the terminal runner beside the GUI binary. Absent: the rendering backend itself, Kitty with an ANSI fallback, and a distributable runner.',
  ),
  (
    'Multi-Window',
    'Windows, displays and the single-instance launch',
    'Present: window identity as canonical URL, the Linux open binding, display enumeration, the exit policy, owned windows, honest modality, the single-instance launch that opens what the app was started with and hands a later launch to the first process, workspace restore, tear-out, display-scope kiosk windows, the Studio window inspector, dartvel inspect windows with the live list a running app publishes, and the performance contract: open-to-ready, tear-out handover, shared-store coalescing, size and spills, and restore duration are measured, the four diagnostics are findings, and dartvel analyze performance reads them. Device profile display names reach the generated client through dartvel build --device-profile, and every DV-WINDOW code has an emitter. Absent: display enumeration is Linux-only.',
  ),
  (
    'Tab Workspaces',
    'Tabs that tear out, re-dock and persist',
    'Present: the tab strip, reorder, tear-out gated on capability, re-dock by adoption, the empty-window rule, duplicate tabs, deduplication by route, a switcher on TV and watch, and persistence scoped to the tenant and the user that drops routes that no longer resolve. Absent: same-engine hit-testing across windows.',
  ),
  (
    'Secrets and Environments',
    'Declared, rotated, and kept where the platform keeps keys',
    'Present: the declaration manifest and its analyze rule, rotation hooks, dartvel key generate | rotate | status, and the application key in the Secret Service on Linux, DPAPI on Windows, the Keychain on macOS and a non-extractable WebCrypto key on the web, with a file only the user can read as the fallback. Absent: the Android Keystore.',
  ),
  (
    'Web Server Rendering',
    'The SEO half, not the rendering half',
    'Present: the server serves the SPA index with the prerendered title and semantic content injected, so a crawler gets markup. Absent: rendering Flutter to HTML on the server; a user still waits for the bundle.',
  ),
  (
    'Embedded, Television, and Extension Build Targets',
    'Builds that exist; devices that have not run them',
    'Present: tizen and vscode build. Absent: neither has been run; fuchsia\'s engine does not build at Flutter 3.44.5; webOS and Sony eLinux ship a Dart below the 3.12 floor, so their embedders cannot resolve the example.',
  ),
];

@DVPage(title: 'Features — Dartvel', showAppBar: false)
@pragma('vm:entry-point')
Widget _featuresPage(BuildContext context) => SingleChildScrollView(
      child: DVBox.list(<Widget>[
        const Section(
          children: <Widget>[
            Eyebrow('WHAT WORKS TODAY'),
            Heading('Forty-four shipped sections.', level: 1),
            Body(
              'This list is the repository’s own record of what is built, not '
              'a description of what is planned. A tool checks it and fails '
              'when a section claims to be built and the evidence it names '
              'does not exist, so this page cannot quietly get ahead of the '
              'code.',
              width: 660,
            ),
            Body(
              'Twelve more sections are partial. They are listed as '
              'partial, with what is absent written next to what is present.',
              width: 660,
            ),
          ],
        ),
        Section(
          tint: true,
          children: <Widget>[
            // A grid where there is room. Twenty-two full-width rows
            // separated by hairlines is a list to scroll past rather than a
            // set of things to compare, and every one of them looked the
            // same as the last.
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final int columns = constraints.maxWidth >= 900
                    ? 2
                    : 1;
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
                        child: FeatureRow(
                            area: f.$1, surface: f.$2, body: f.$3),
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
            const Heading('What is partial, and what is missing from it.',
                level: 2),
            const Body(
              'Each of these has real code behind it and a named gap. The '
              'gap is written next to the work, in the repository’s words, '
              'and the same tool holds this list to the index.',
              width: 660,
            ),
            DVBox.list(<Widget>[
              for (final (String area, String surface, String body) f
                  in partial)
                FeatureRow(area: f.$1, surface: f.$2, body: f.$3),
            ], spacing: 14),
          ],
        ),
        const SiteFooter(),
      ], spacing: 0),
    );

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
              // Without any level at all they were twenty-two paragraphs, so
              // the page had a title and no structure under it -- for a screen
              // reader moving by heading and for the crawler-visible HTML
              // alike.
              .semanticHeading(2),
        ),
        SiteChip(surface),
      ], spacing: 10),
      DVText(body).modifier(
        const DVModifier().fontSize(15).color(palette.muted).height(1.6),
      ),
    ], spacing: 6),
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
