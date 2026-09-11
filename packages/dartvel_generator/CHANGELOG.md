## Unreleased

- **The `build_runner` builders are retired.** Generate with `dart run
  dartvel_cli:dartvel routes` instead, or with `dartvel build`, which
  generates before it builds. The CLI writes the whole client -- the
  `dartvel_client` barrel every page imports, the router, each page's body,
  functional widgets, models, backend functions and config -- where these
  builders wrote only the router, env, config, runtime and page bodies, and so
  could never generate a client from a clean checkout: with no barrel the
  first page's `@DVPage` cannot be resolved and the build stops. Every project
  on this path was already running `dartvel routes` first.
- Nothing breaks today. The builders still generate exactly what they
  generated before and are still `auto_apply: dependents`; each now logs one
  warning per build naming the command that replaces it and the release that
  removes it. They were kept rather than deleted because a builder that
  vanishes takes the `router.g.dart` it wrote into `lib/` with it, leaving a
  project broken with no explanation.
- **Removal is scheduled for `dartvel_generator` 2.0.0.** To migrate: drop
  `build_runner` and `dartvel_generator` from `dev_dependencies` and run `dart
  run dartvel_cli:dartvel routes`. Keep `build_runner` only for some other
  package's builders; `dartvel build` and `dartvel dev` still run it for those.

The three fixes below landed in the same release: they are what made the
case for retiring the path rather than keeping two generators in step over
one concern.

- Pages are split out of main.dart.js on the web when built with
  `dart run build_runner build`, as `dartvel routes` has done since the
  change that introduced it. The router builder copied each private page's
  body into router.g.dart, which is eager, so dart2js found all of it
  reachable from `main()` and the page's deferred import guarded nothing. A
  new `page_body_builder` writes each lowered body into
  `lib/dartvel_client/pages/<path under lib>.g.dart`, and the router imports
  that library `deferred` and calls its `dvPageBody`. The pages directory is
  read from the pubspec, so a custom `dartvel.pagesDir` works; a deleted
  page's body library is removed by build_runner with its input.
- The build_runner router registers every page with `DVRoutePreloaders`, as
  `dartvel routes` always has. Without it no link in a build_runner
  application preloaded anything, and `dartvel build web` could not tell
  which deferred import a route loads.
- A function page gets a data scope. The build_runner router built every
  other route inside a `DvDataLoader` and skipped it for function pages, so a
  function page that read `DvDataScope.of(context)` found nothing above it
  and threw -- basic_app's own page does, and its widget test failed.
  `dartvel routes` never had the exception.

## 1.2.0

- Follows `dartvel_core` 0.4.0.
- Generated model queries filter by tenant where a model asks for it: a tenant
  column, a predicate on every read, the tenant written into every write, and
  a delete that cannot reach another tenant's row. They arrive together
  because any one of them alone looks exactly like the feature working.

## 1.1.1

- Corrected the constraints on sibling Dartvel packages, which named the
  previous release rather than the one published alongside them. A caret on a
  0.x version stops at the next minor, so `dartvel_core: ^0.2.1` excluded the
  0.3.1 published beside it -- a user installing the 0.3.1 set resolved 0.2.x
  for every sibling and got none of what that release contained. `dart pub
  publish --dry-run` could not see it, because it resolves against
  pubspec_overrides.yaml and every sibling points at a local path.

## 1.1.0

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

## 1.0.0

- Initial version.
