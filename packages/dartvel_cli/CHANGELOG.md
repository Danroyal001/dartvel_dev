## Unreleased

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
