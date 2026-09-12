## Unreleased

- Three window degradations that no window could ever carry now report where
  their condition occurs. `kioskLocked` (`DV-WINDOW-002`) is set when a
  device-scope kiosk holds the surface, `disabledByConfig` (`DV-WINDOW-005`)
  when a project wrote `windowing.enabled: false`, and `gestureRequired`
  (`DV-WINDOW-003`) when a browser refuses a window outside a user gesture.
  All three were declared, given codes and documented, and assigned nowhere:
  every one of those windows reported the generic "this target has no
  windows" instead, and `dartvel explain` described situations the API could
  not produce.
- `open()` asks the browser for the window on the web, through
  `DVWindowManager.browserWindowOpener`. The web has no `window.open` binding
  and cannot have one, so every web call reported a missing binding --
  `DV-WINDOW-006`, an `error` blaming the integration for the browser doing
  its job. A window the browser opens is a window; one it refuses is
  `gestureRequired`; and `close()` closes it through the handle the page
  opened it with, since a browser lets a page close only its own windows.
- `DVWindowDegradation.displayHintUnmatched` reports a `display:` hint that
  matched no connected display (`DV-WINDOW-013`). That situation and a kiosk
  window whose display is gone (`DV-WINDOW-010`) both reported
  `displayUnavailable`, whose `code` said 013 -- so a kiosk window presenting
  in place logged 010 and carried a degradation naming 013, and `dartvel
  explain` on either described the other. `displayUnavailable` keeps the kiosk
  meaning and now names the code that path has always logged. **A window whose
  `display:` hint went unhonoured reports `displayHintUnmatched` rather than
  `displayUnavailable`**; the behaviour is unchanged, and a hint still never
  falls back to another display.

## 0.5.0

- A page's title in its app bar is its level-1 heading, on the Material and
  Cupertino shells alike. Both bars mark their title a header with no level,
  which the web draws as an `<h2>`, so every page with a bar had headings and
  none at level 1 -- and `dartvel build web`'s accessibility audit refused
  every such page, which is why the example application had never produced
  a web build.
- `DVImageView` asks for the variant its slot needs on a web build with
  image variants: its laid-out width times the screen's pixel ratio, snapped
  to the configured widths, the way NextFaster's `srcset` does -- so a phone
  downloads the 640 and not the 3840. An asset uses the file the build wrote
  at that width, a remote image on an allowed host goes through a
  web-server's `/_dartvel/image`, and a slot wider than the image uses the
  image itself. With no variants built it renders exactly as before, with no
  layout pass.
- A link prefetches that variant for the visitor's own pixel ratio, not the
  build's, and puts it in the image cache under the provider the widget will
  ask for. The build records each image's slot for this, since a request for
  the 384-wide file says only that the slot was somewhere under 384.
- A link that preloads fetches the page's document and images as well as its
  code. `loadLibrary()` only ever fetched the Dart. On the web the link now
  adds a `<link rel="prefetch">` for the route's prerendered HTML -- what a
  new tab, a reload or a shared link opens -- and one for each image
  `dartvel build web` recorded the page painting, then hands each image to
  Flutter's image cache once the browser has it, so the page paints it on its
  first frame. In that order so the image is downloaded once. `DVRoutePrefetch`
  holds both steps and can be replaced; off the web it fetches nothing.
- Links preload once they have been on screen for 300 ms, as well as on hover.
  `DVLinkPreload.visible` is the new default: hover was the only trigger, and
  a phone has no pointer to arrive, so no link on a touch screen preloaded
  anything unless it was marked `immediate`.
- A link is followed when the mouse button goes down rather than when it
  comes up, which is the hundred-odd milliseconds a click takes. Only for a
  mouse's primary button: touch, stylus, keyboard and screen readers keep the
  tap, ctrl and cmd still open beside the page, and the release that follows
  is not followed a second time on either the Flutter or the browser side.
- `DVShowingPages` runs work while a page is on screen: started with the
  first page and stopped with the last, counted because two are mounted
  whenever one is leaving as the next arrives. Registering the same id again
  replaces the earlier job. The generated client schedules use it, which
  fixes three things at once: their timer was started with the router and
  never stopped, a second router ran every schedule twice, and every widget
  test that built the router failed with "A Timer is still pending".

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
