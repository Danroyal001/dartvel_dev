# Web load performance

How fast a Dartvel web build loads, measured, and what was changed to make
it faster. Numbers come from `dart tool/web_vitals.dart`, which runs
Lighthouse 12 in headless Chrome: mobile is Lighthouse's default profile
(a mid-range phone on a throttled 4G connection), desktop its desktop
preset. The server was under load from other builds during every run, so
compare rows taken the same day rather than reading any one as a ceiling.

## Before (0.9.0, 2026-09-28)

https://dartvel.dev, served by the Dartvel web-server binary behind nginx.

| URL | Profile | TTFB | FCP | LCP | TTI | TBT | Transferred | App JS/Wasm | Renderer | Fonts |
|---|---|---|---|---|---|---|---|---|---|---|
| https://dartvel.dev/ | mobile | 16 ms | 2809 ms | 2819 ms | 30198 ms | 17210 ms | 4299 KB | 1050 KB | 1544 KB | 237 KB |
| https://dartvel.dev/docs/ui | mobile | 16 ms | 1941 ms | 2185 ms | 32289 ms | 20028 ms | 4261 KB | 1041 KB | 1544 KB | 237 KB |
| https://dartvel.dev/ | desktop | 62 ms | 616 ms | 767 ms | 7867 ms | 4147 ms | 4299 KB | 1050 KB | 1544 KB | 237 KB |
| https://dartvel.dev/docs/ui | desktop | 21 ms | 651 ms | 883 ms | 5072 ms | 2061 ms | 4400 KB | 1092 KB | 1544 KB | 237 KB |

What the numbers say:

- **The server is not the problem.** Time to first byte is tens of
  milliseconds, and the HTML is 7 KB compressed.
- **The first paint was the splash, and nothing to read followed it for
  seconds.** FCP and LCP were the splash image; the page's text, which the
  build already writes for crawlers, was kept off the screen until Flutter
  drew its first frame.
- **Interactive is late because of the bytes and the main thread.** About
  4.3 MB goes over the wire: the compiled app (1 MB gzipped), the renderer
  (1.5 MB) and 237 KB of fonts. Parsing and compiling them is where the
  total blocking time goes.
- **Nothing said the page was alive.** A still splash for 30 seconds on a
  phone reads as a page that died.

## What changed (0.9.1)

Written into every page's HTML by `dartvel build web`, before any Dart runs:

- **The page's own text is the page until the first frame.** In its reading
  column, over the splash colour, handed back to the app when Flutter paints.
  LCP becomes that text instead of the splash image.
- **A loading bar across the top that follows real progress**: it moves to a
  milestone as the compiled app, the renderer and a font arrive (the
  browser's resource timings), creeps between milestones, and completes on
  the first frame. `role="progressbar"`, `aria-busy` on the document, still
  under reduced motion. On by default (`dartvel.splash.progress: false` turns
  it off; `splash.progressColor` colours it).
  It stays above the splash until the app has loaded.
- **A pulsing "Loading…" line under the splash logo**, in the splash's own
  colours (dark text on a light splash, light on a dark one), still under
  reduced motion, so a slow load never looks hung. Studio's splash shows the
  same line. `dartvel.splash.loadingText` sets the words; `false` removes it.
- **The splash stays until the app's first frame**, at every window width,
  and the head preloads the splash logo first, so a slow phone never sees a
  blank splash.
- **No first-frame picture (removed 7 Nov 2026).** 0.13.22 to 0.13.24 showed a
  picture of each page, captured at build time, before the app loaded. It
  looked finished but did nothing when pressed, and visitors took the site
  for broken. The splash, its loading line and its loading bar replace it
  until the real app has drawn; `dartvel.web.firstFrame` is ignored with a
  warning.
- **`main.dart.js` is preloaded from the head**, so the largest download
  starts while the HTML is parsed rather than after `flutter_bootstrap.js`
  has run and asked for it.

After the first frame the same bar is `DvDefaultLoading`, which a deferred
page and a page's data show, on every platform, and `DV.progress` for an
application's own work.

## After

Measured after the 0.9.1 deploy; see the rows added below.

## Fonts and repeat visits (after 0.13.22)

Measured on a copy of the sigmadev.digital site (branch `site/release-1107`,
`firstFrame.widths: [390]`, a setting since removed), built as a web-server binary on the same host,
and loaded in headless Chromium as a 393 px phone through a proxy that
applies Lighthouse's slow 4G (150 ms round trip, 1.6 Mbit/s down, 750 kbit/s
up) to every byte, the service worker's own fetches included, with a 2x CPU
slowdown. "First frame" is Flutter's `flutter-first-frame` event. Script:
a Playwright run against the proxy, two visits in one browser profile.

| Build | Visit | Bytes to first frame | Network requests | FCP | First frame |
|---|---|---|---|---|---|
| 0.13.22, PWA off (as deployed) | first | 3730 KB | 74 | 2.3 s | 23.8 s |
| 0.13.22, PWA off | second | 14 KB (73 revalidations) | 73 | 1.9 s | 7.9 s |
| this change, PWA on | first | 2997 KB | 89 | 2.6 s | 18.7 s |
| this change, PWA on | second | 0.8 KB | 0 (all from the worker) | 0.5 s | 4.4 s |
| next release, same browser | first after the deploy | 932 KB | 0 | 2.6 s | 10.4 s |
| next release, same browser | second | 0.8 KB | 0 | 0.4 s | 4.4 s |

The release changed one string on the home page: 9 of the build's 957 files
changed, main.dart.js (787 KB) among them. The first visit after the deploy
ran the new build -- its HTML and the app's code both carried the new text --
and downloaded the changed files only; the worker's install that followed
cost 58 KB more, because every unchanged file was copied from the previous
build's cache, which was then deleted.

Fonts on that first visit went from 1336 KB in 12 files (one of them Roboto
from fonts.gstatic.com) to 437 KB in 8, none third-party. The build prints
its own estimate: `fonts: 1.3 MB -> 387 KB on the wire, 12 files -> 8`.

After the first frame the worker installs and downloads what a later visit
needs and the first one did not: every deferred part and up to 25 pages,
940 KB for this site (3.9 MB for the whole first visit). The pages are
bounded by `dartvel.pwa.precacheRoutes`.

What changed:

- **Fonts** (`web_fonts.dart`, every `web` and `web-server` build): static
  faces a variable font of the same design draws are served by it (the
  engine sets `wght` from every TextStyle's FontWeight, CanvasKit and skwasm
  alike); families no compiled code and no data names are dropped; text
  fonts are subset with Flutter's own `font-subset` to Latin, common symbols
  and every character the project's sources and content contain; everything
  is WOFF2 (pure Dart, null transform, brotli from the native library) under
  a content-hashed name, sent as immutable; and Roboto comes from the Flutter
  SDK's copy, because the engine fetches it from fonts.gstatic.com whenever
  the manifest has no family by that name. A character the subset lacks is
  drawn by the engine's Noto fallback, fetched when it is needed.
- **The service worker** (`pwa_service_worker.dart`): the page asks for its
  boot files at `?v=<build>`; a page of a newer build than the worker's is
  served from the network and the worker replaces itself, an open tab of the
  previous build keeps its own cache, and a page of the worker's build is
  served from the cache with no network. Precaching is per file and never
  fails the install. A release copies every unchanged file (by content hash,
  `dartvel_sw_assets.json`) from the cache it replaces. Google's renderer and
  fallback fonts are kept by their versioned URL. The page reports what its
  first, uncontrolled visit downloaded, and the worker keeps that from the
  HTTP cache. Registration waits for the app's first frame.

## Build time (after 0.13.24)

Measured on a fresh `dartvel create` web-server app with 30 generated pages
(35 routes read, measured before the first-frame picture was removed, with
it turned off), on the same 8-core host
while other builds ran (load 8 to 11), so compare rows rather than reading
any one as a ceiling: Flutter's own compile of the same app varied from
169 s to 245 s between runs. Times run from `Building Dartvel project` to
`Build complete`, leaving out the CLI's own start (`dart run` from source).

| Step | Before, cold | After, cold | After, one page edited | After, nothing changed |
|---|---|---|---|---|
| Code generation | 26 s | 7 s | 7 s | 6 s |
| `flutter build web --wasm` | 191 s | 213 s | 203 s | reused |
| Deferred dart2wasm, rerun | 149 s after Flutter | beside Flutter (0.4 s after it) | beside Flutter | reused |
| Semantics read | 387 s (35 fresh loads, one at a time) | 23 s | 22 s | reused |
| Backend compile | about 45 s, after everything else | beside Flutter | beside Flutter | reused |
| Pack and brotli of the web files | the rest of 179 s | 14 s | 13 s | 2 s |
| **Total** | **951 s** | **277 s** | **262 s** | **20 s** |

The "before" warm builds were not measured. Plain `flutter build web --release --wasm` on the same app: 169 s cold,
11.6 s with nothing changed.

What changed:

- **Semantics read: one boot per window, several windows.** Every route was
  a fresh page load, and each load booted the whole app (code, renderer,
  first frame) for most of the 11 s a route took. The read now opens a pool
  of windows (three quarters of the cores, at most eight; `--capture-jobs`),
  boots the app once in each and moves it between routes through a hook the
  app installs only under automation (`globalThis.__dartvelCapture`). The
  hook forgets decoded images before each move, so a route's image list is
  what a fresh load records; a route the router does not arrive at (a
  redirect) and an app without the hook get fresh loads. Each page needs a
  window of its own: Flutter draws in animation frames, which a browser runs
  only for the page its window shows, and with tabs most routes came back
  empty. On the sample, every tree and image list equals a fresh load's
  (the home page differs only in the clock it prints). 35 routes: 387 s
  before, 66 s with one window, 24 s with six. `--no-capture-in-app` turns
  the moving off.
- **The deferred dart2wasm starts when Flutter starts its own**, with the
  same command, instead of after `flutter build web` ends.
- **The backend compile starts beside Flutter** (it reads none of the web
  output) and is kept in `.dartvel/cache` under its own inputs, so a page
  edit or an unchanged rebuild reuses it.
- **Flutter's engine files are encoded while Flutter compiles**, into
  `~/.dartvel/cache/asset_encodings`, shared by every project on the
  machine, and the native brotli encoder is no longer a leaf FFI call: as
  one, a multi-second encode kept every isolate of the build from reaching a
  safepoint, so the encoding isolates ran one at a time and the main isolate
  stood still (3 timer ticks in 12 s).
- **Image variants** are made on a pool of isolates and kept by the content
  of their source, so an unchanged image is copied on the next build (the
  sample has none; not in the table).

Where the time still goes, cold: Flutter's compile is most of it, and the
read can only start once the finished app exists, so a cold Dartvel build
is Flutter's compile plus about a minute (generation, the read, the pack).
It is not faster than a plain `flutter build web` cold, and with nothing
changed Flutter's own build skips its compile too, so neither is it faster
there. What Dartvel no longer repeats on a warm build is its own work: the
read, the backend compile and the encoding.

Not done: Flutter's own one-module dart2wasm still runs beside the deferred
one (removing it means writing what `--wasm` adds to the output by hand);
generation still runs as a `dart run` subprocess (7 s); font subsetting is
one font after another (3 s on the sample).

For 221 routes (sigmadev.digital) the read at the sample's rate, six
windows and one boot each, would be about two minutes; its pages are
heavier than the sample's, so that is an estimate, not a measurement.

## Still to do

Ranked by what they would save:

1. **WebAssembly (skwasm) by default, with the JavaScript fallback**
   (`docs/web-roadmap.md` item 15): smaller and faster to start than
   CanvasKit plus dart2js, once every Dartvel web binding is
   `dart:js_interop`-clean.
2. **Content-hashed file names for the app's code**, so `main.dart.js` can
   be cached as immutable by a browser with no service worker. Flutter names
   its output without hashes and the deferred parts are loaded by name; the
   worker's `?v=<build>` covers repeat visits in the meantime.
3. **The WOFF2 glyf transform**, a few per cent more off every font.

(Brotli is done: the web-server binary keeps and sends its files as brotli.
Font subsetting is done, above.)
