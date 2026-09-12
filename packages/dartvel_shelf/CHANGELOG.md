## Unreleased

- **Two servers started at the same moment no longer share a request
  handler.** `0.4.0`'s fix made each server snapshot the registered handler
  at `aw_start`, which closed the request-time half: one global was no longer
  read on every request. The window between the two calls stayed open, and it
  is the one `dart test` walks into every run — one library load, a suite per
  isolate, a thread per isolate. Two isolates interleave as register A,
  register B, start A, start B, and A's snapshot is B's handler, so A answers
  its own port out of B's router: a plausible 404 for a route A registered
  itself, or B's body for a path they share, with nothing thrown. When B then
  stops and frees the callback A is still holding, the next request into A
  aborts the process on "Callback invoked after it has been deleted". The
  pending registrations are keyed by thread now, so the two calls cannot
  interleave: `serve()` makes both without yielding, and an isolate has a
  thread of its own. `test/concurrent_serve_test.dart` races two isolates
  through `serve()` twenty-five times; it fails on the first pass without the
  fix.

- **The committed library and its bindings no longer carry symbols this crate
  cannot build.** `a7ea535f` moved the HTTP client to dartvel_core and removed
  `dv_http_send`, `dv_http_cancel`, `dv_http_next_event` and
  `dv_http_free_buf` from the cbindgen header; the generated bindings and the
  committed `.so` were never regenerated, so both kept them. Nothing in this
  package has ever called them — they resolve out of dartvel_core's own
  library, where they belong — but anyone who rebuilt from source got a
  library without them and a red `native_symbols_test`, for doing exactly
  what that test's failure message says to do. The bindings are regenerated
  and the library rebuilt. The guard now checks the other direction too: when
  a refactor removes a symbol, the bindings and the binary are left behind
  *together*, still agree with each other, and the old one-way comparison
  stays green.

## 0.6.0

- `/_dartvel/image?src=&w=&q=` on a web-server build, NextFaster's image
  optimizer. An image in the site, or on a host listed in
  `dartvel.images.remoteHosts`, is resized to one of the configured widths,
  once, off the event loop, and kept under the system's temporary directory.
  A PNG goes out as WebP to a browser that accepts it; a JPEG stays a JPEG,
  because the encoder only writes lossless WebP and that is larger than a
  JPEG of a photograph; a GIF is passed through, since resizing keeps one
  frame of an animation. Never larger than the source. An ETag keyed on the
  source's bytes answers a revalidation with 304.
- What it refuses: a width outside the set (every width is a cache entry and
  work somebody else can make the server do), a path out of the site whether
  by `..` or by a link inside it pointing out, a host nobody allowed, and a
  redirect from an allowed host to anywhere, which would undo the allowlist.
- Shell-first rendering, with `dartvel.web.server.streaming: shell`. The
  server sends the shell's head -- base, charset, every preload, the splash,
  and a preload for each script the body loads -- before a route's data has
  resolved, and starts resolving it at the same moment, so the browser
  downloads the application and the page's code while the database answers.
  With `true` the head was a separate write but went out after the data, so
  nothing reached the browser until the query returned. Proven through the
  native runtime: the early bytes reach a socket while the data is held back.
- The status code is the price. A record found hidden or unauthorized once
  200 is on the wire is a page marked `noindex` with none of its data, a
  soft 404; a resolver that throws gets the route's own page, marked the same
  way, and the document still ends. A guarded route is never sent early: it
  waits and answers 401 or 404 exactly as it did, so a signed-out request
  still looks like one for a page that does not exist. Federated routes are
  still redirected.
- A served route names its own code and images. The static build writes each
  page's deferred parts and first-frame images into that page's head; the
  server answers every route from one shell and named none of them, so the
  early head under `shell` carried the renderer and the bootstrap and nothing
  of the page itself. It now reads the build's `dartvel_prefetch.json` --
  kept, and read again when a deploy replaces it -- and adds the matched
  route's list to the head: in the first write under `shell`, before the
  data, since the list depends on the route and never on the data. Nothing
  the shell already names is added twice.

## 0.5.0

Minor rather than patch: the request and response types this package shares
with `dartvel_core` moved with core's 0.4.0, and the server generation reads
`dartvel.server` for CORS and compression rather than expecting the
application to pass them to a `serve` call nobody writes.

- Saying nothing about CORS now means no CORS headers rather than answering
  every origin, since that is the setting most likely to be wrong and a
  default nobody chose should not be it.
- A value the build cannot honour stops the build: credentials from any
  origin, an origin written with a path or a trailing slash, and compression
  written as the string `false`.

## 0.4.2

- Corrected the constraints on sibling Dartvel packages, which named the
  previous release rather than the one published alongside them. A caret on a
  0.x version stops at the next minor, so `dartvel_core: ^0.2.1` excluded the
  0.3.1 published beside it -- a user installing the 0.3.1 set resolved 0.2.x
  for every sibling and got none of what that release contained. `dart pub
  publish --dry-run` could not see it, because it resolves against
  pubspec_overrides.yaml and every sibling points at a local path.

## 0.4.1

- The wire types moved to dartvel_core; this package re-exports them, so
  existing imports keep working.

## 0.4.0

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

## 0.3.0

- First published release.

Dartvel's packages are published under the `dartvel_dev` name on pub.dev.
`dartvel` was taken on 2026-08-06 by an unrelated package, so the published
identifier carries a suffix while the command stays `dartvel`.
