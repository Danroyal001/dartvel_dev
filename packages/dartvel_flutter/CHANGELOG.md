## 0.4.0

Android went from 10 bound native bindings to 36, and web from 16 to 41. Both
numbers are counted from source by `dart tool/binding_coverage.dart` rather
than written down, because every per-platform figure in this repository has
been wrong at some point.

Android now covers runtime permissions, the camera, the media picker,
contacts, location, sensors, biometric availability, local notifications, the
device runtime, files, screen geometry, NFC availability and most of
Bluetooth. The Activity that permission results and activity results are
delivered to is written into the application by `dartvel build android`.

Three Android bugs that had shipped since the capability list existed, all
found by a new on-device gate rather than by any unit test:

- All three haptics bindings threw on every device at API 31 or above. The
  `vibrator_manager` service returns a `VibratorManager`, which holds a
  vibrator rather than being one, and the cast to `Vibrator` threw.
- `notifications.sendLocal` and `files.writeBytes` answered with types their
  own callers refused. `DVFiles.writeBytes` asked through `require<bool>` and
  the binding answered with a byte count, so the call threw on Linux, Windows
  and macOS while writing a perfectly correct file.

Web bindings are registered only after a probe for the API behind them, so a
browser without Web NFC or the Contact Picker leaves those names unregistered
and `DVNativeBridge.isRegistered` keeps telling the truth. A capability the
browser has and refuses raises `DVWebPermissionDenied` carrying the browser's
own words, so a refusal can no longer be read as an absence.

The Linux clipboard was worse than unimplemented: a copy made the process the
owner of the X11 CLIPBOARD selection without running a GLib main loop to
answer for it, which made every paste on the machine hang until the asking
application timed out.

## 0.3.2

- Corrected the constraints on sibling Dartvel packages, which named the
  previous release rather than the one published alongside them. A caret on a
  0.x version stops at the next minor, so `dartvel_core: ^0.2.1` excluded the
  0.3.1 published beside it -- a user installing the 0.3.1 set resolved 0.2.x
  for every sibling and got none of what that release contained. `dart pub
  publish --dry-run` could not see it, because it resolves against
  pubspec_overrides.yaml and every sibling points at a local path.

## 0.3.1

- `DVModifier.border` draws a border, so a rule or hairline no longer needs a
  raw Container and BoxDecoration.
- `files.readBytes`, `files.writeBytes` and `files.delete` bindings, confined to
  a root the application names.

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
