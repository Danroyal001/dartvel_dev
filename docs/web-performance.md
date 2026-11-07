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
`firstFrame.widths: [390]`), built as a web-server binary on the same host,
and loaded in headless Chromium as a 393 px phone through a proxy that
applies Lighthouse's slow 4G (150 ms round trip, 1.6 Mbit/s down, 750 kbit/s
up) to every byte, the service worker's own fetches included, with a 2x CPU
slowdown. "First frame" is Flutter's `flutter-first-frame` event. Script:
a Playwright run against the proxy, two visits in one browser profile.

| Build | Visit | Bytes to first frame | Network requests | FCP | First frame |
|---|---|---|---|---|---|
| 0.13.22, PWA off (as deployed) | first | 3730 KB | 74 | 2.3 s | 23.8 s |
| 0.13.22, PWA off | second | 14 KB (73 revalidations) | 73 | 1.9 s | 7.9 s |
| this change, PWA on | first | 2987 KB | 71 | 2.3 s | 18.8 s |
| this change, PWA on | second | 0.8 KB | 0 (all 95 from the worker) | 0.5 s | 4.1 s |

Fonts on that first visit went from 1336 KB in 12 files (one of them Roboto
from fonts.gstatic.com) to 437 KB in 8, none third-party. The build prints
its own estimate: `fonts: 1.3 MB -> 387 KB on the wire, 12 files -> 8`.

After the first frame the worker installs and downloads what a later visit
needs and the first one did not: every deferred part and up to 25 pages,
1.8 MB for this site. `dartvel.pwa.precacheRoutes` bounds the pages.

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
