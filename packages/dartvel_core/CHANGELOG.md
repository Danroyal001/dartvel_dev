## Unreleased

- A kiosk says when it blocks a route. `routes.allow` was parsed, scanned by
  doctor and given `DV-KIOSK-006` for a route being blocked, and the redirect
  that did the blocking reported nothing -- so a kiosk sending `/admin` back
  to its home page looked exactly like a link that was wrong.
  `DVKioskDegradation.routeBlocked` is the member that names it, and it was
  assigned nowhere until now. The block is logged at `debug`, the level the
  registry gives that code, with the route and where it went.
- An exit result carries the degradation rather than a code spelled out
  beside it. `DVKioskExitResult.degradation` is `lockedOut` after
  `maxAttempts`, `noPolicy` in a build with no kiosk policy, and `none`
  otherwise; `code` derives from it. The codes were string literals written
  next to the enum members that mean the same thing -- two places to change
  and one of them silently stale -- and `DVKioskDegradation.lockedOut` was
  assigned nowhere at all, so a caller could only learn what had happened by
  matching the text of a code.

- Diagnostic codes for the sections the third pass added: `DV-STORE` (store
  publishing and privacy declarations), `DV-RELEASE` (backend release
  management), `DV-HISTORY` (record history and optimistic concurrency),
  `DV-ORG` (organizations and invitations), `DV-ANALYTICS` (product analytics
  and consent) and `DV-APIKEY` (platform API keys, scopes and the OAuth
  provider). Specified, not built; `dartvel explain` can answer them.

- The diagnostic registry carries the codes the specification added for
  protocol versioning, offline-first models, schema evolution, client
  schedules, 3D scenes and PDF export. `dartvel explain` answered "unknown
  code" for twenty codes the document publishes, and the test that exists to
  catch exactly that disagreement was failing. Its row pattern also skipped
  any family with a digit in it, so the whole `DV-3D` family was outside the
  check in both directions; it is inside it now.

- `dvKioskLocksWindows` reports whether a running kiosk policy holds the
  surface to one window -- true in `device` scope, which the specification
  defines as one application with no windows. The windowing capability reads
  it, so `open()` under a device kiosk names the kiosk (`DV-WINDOW-002`)
  rather than reporting the target as incapable of windows.

## 0.5.0

- The `DV.Database` docs say whose code generation the `build_runner` step
  they describe is: drift's. Dartvel's own generation is `dart run
  dartvel_cli:dartvel routes`, and the build_runner path through
  `dartvel_generator` is retired, so a step that just said "run code
  generation" now reads as the retired one.
- `DVImageVariants`: the widths images are resized to (Next.js's defaults
  unless `dartvel.images.widths` says otherwise), the one address a variant
  is asked for by, and the checks a server applies to a request for one -- a
  width outside the set, a path out of the site, a host not in
  `dartvel.images.remoteHosts`, credentials in an address. The widget, the
  link prefetch and the server all call it, so all three name the same file:
  a prefetch of a slightly different address is a second download, not a
  cache hit.
- `dartvel.web.server.streaming: shell` -- `DVPageStreaming.shell`, alongside
  `head` (`true`) and `off` (`false`), which read and write exactly as
  before. `DVWebServerSettings.streaming` stays, now true for either kind of
  streaming; `streamingMode` says which.
- `dvHeadParts` splits a page's head into what no render of its shell
  changes and what page data writes -- the SEO block, a stray title or
  description, the icon, the structured data. The first part is identical in
  every render of one shell, which is what makes it safe to send before the
  data exists.
- `DVRoutePreloads` reads the prefetch manifest a web-server build writes
  and gives a served route its own `<link rel="preload">` list, by the
  pattern the request matched: its deferred parts as scripts, its images as
  they are fetched, nothing the shell already names and no image drawn
  through a variant, since which file that is depends on the screen.
- `dvShellFirstChunks` is shell-first streaming as one function, the route's
  preloads in its first write, and both servers stream through it -- the
  deployed one and `dartvel preview`, which had only the older head-after-data
  split, so the page previewed was not the page served.

## 0.4.0

Breaking: `DVFieldCipher` takes its randomness through a named constructor.
`DVFieldCipher.secure(keyring)` is what an application wants; the unnamed
constructor is `@visibleForTesting` and exists so a test can supply a
deterministic source. A cipher that silently accepted a seeded `Random` in
production was a key generator with no entropy.

- The Android permission table gained the names the capture bridge resolves at
  run time, so a request can never name a permission the manifest lacks --
  Android refuses an undeclared permission instantly, with no dialog, and the
  answer is indistinguishable from a person tapping Deny.
- Billing gained usage meters, trials, invoices and a webhook receiver, with
  every grant keyed by a real customer identity rather than `toString()`. The
  default `toString()` of an ordinary object is the same constant for every
  instance, so passing a logged-in user filed every user under one key.
- Webhooks are applied newest-wins per subscription. Providers do not
  guarantee order, and a stale `active` arriving behind a cancellation handed
  a cancelled customer their entitlement back with a valid signature.

## 0.3.2

- Corrected the constraints on sibling Dartvel packages, which named the
  previous release rather than the one published alongside them. A caret on a
  0.x version stops at the next minor, so `dartvel_core: ^0.2.1` excluded the
  0.3.1 published beside it -- a user installing the 0.3.1 set resolved 0.2.x
  for every sibling and got none of what that release contained. `dart pub
  publish --dry-run` could not see it, because it resolves against
  pubspec_overrides.yaml and every sibling points at a local path.

## 0.3.1

- Kept web-compatible: the distributed cache hashes in 32-bit arithmetic, and
  the LDAP client is behind a conditional export. Both broke `flutter build web`
  outright.
- The main barrel exports Request, Response and Headers again; the full wire
  type set moved to `package:dartvel_core/http.dart`.

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
