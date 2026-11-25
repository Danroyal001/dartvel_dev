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
  boot files at `?v=<build>`, and so does every preload of the app's code,
  the splash's wasm/dart2js script included (an unversioned preload and a
  versioned loader request are two downloads of the 1 MB app); a page of a newer build than the worker's is
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

## Slow phone networks, first visit (after 3.47.4, November 2026)

Measured on sigmadev.digital (live release vs the same commit rebuilt), in
headless Chrome 155 as a 390 px phone with a 4x slower CPU, an empty cache in
a fresh profile, DevTools' Fast 3G (562 ms, 1.44 Mbit/s) and Slow 3G (2 s,
400 kbit/s) applied to the page and to its service worker, over HTTP/2
through the site's nginx. "First frame" is Dartvel's `dartvel-first-frame`.
The host was running other builds (load 15-35), so wall times move by about
5 s between runs; main-thread CPU time (trace `tdur`) does not, and is given
beside them. Scripts: `measure.mjs`, `trace.mjs`, `cputime.mjs`, `crit.mjs`.

| | Before (live on 3.47.0) | After (3.47.4 + this change) |
|---|---|---|
| Splash painted (FCP), Fast 3G | 0.8-1.4 s | 0.8-1.3 s |
| Bytes before the first frame | 3.76-3.98 MB | 2.74 MB |
| main.dart.wasm downloaded, Fast 3G | 20.0 s | 14.6-15.5 s |
| Route modules in, Fast 3G | 37-38 s (three waves) | 17.4-19.4 s (at once) |
| Main-thread CPU to first frame | 12.4-12.8 s | 8.5-9.8 s |
| First frame, Fast 3G | 38.5-41.0 s | 33.2-38.7 s |
| First frame, Slow 3G | 107.6-110.5 s | 80.1-94.6 s |

Where the time went, and what changed:

- **The app downloaded twice** (3.47.3): the splash preloaded
  `main.dart.wasm` without the loader's `?v=<build>`. 1 MB of the 1.2 MB saved.
- **Route modules in waves**: a page's deferred `main.dart_module<N>.wasm`
  files were asked for only after main.dart.wasm had run, one round trip per
  wave (0.6 s each on Fast 3G, 2 s on Slow 3G). The build now reads
  dart2wasm's deferred map and each page names its route's modules; a small
  script preloads them the moment main.dart.wasm and the renderer have
  downloaded, only in a browser that runs the wasm app.
- **Links prefetched behind the splash**: the first frame is held while the
  route loads, but frames still build, so a link's post-frame preload fetched
  and compiled other pages (/contact, /pricing-plans-and-services and 28
  modules) before the page showed. Links now wait for the first frame:
  about 1 s of main-thread CPU off the path.
- **The service worker registered 30 s after load** even with the app still
  loading, and its install (boot files, 25 pages and their parts) shared a
  slow line with it. It now waits for the first frame only.

Tried and dropped: preloading the fonts and the two manifests. Started with
the page, they shared the line with main.dart.wasm and delayed it by 10 s on
Slow 3G; started once the app and renderer were in, they began after the
engine had asked for FontManifest.json itself, which then came down twice.

What is left is CPU: with the network idle from about 20 s on Fast 3G, the
first frame waits on starting the app (Dart about 5 s, compiling wasm 3.5 s,
the renderer 2 s at 4x slowdown; headless Chrome draws without a GPU, which
overstates the renderer's share). The next step is a symbolised profile of
what the app does before its first frame.

## SSR-first: the page's own document instead of the splash (opt-in, November 2026)

`dartvel.web.ssrFirst: true` (off by default, see NEW_SPEC.md, *SSR-first*)
shows each page's server-rendered document, the block crawlers, find and
print already read, as the page from the first paint. Flutter takes over at
its first frame. Nothing about loading the app changes, so the first frame
comes when it did. What changes is what a visitor has until then: a page
they can read and tap after one round trip and a few kilobytes, instead of
the logo for 30 to 95 seconds.

Measured on sigmadev.digital the same way as the section above: headless
Chrome as a 390 px phone, 4x slower CPU, a fresh profile, DevTools Fast 3G
(562 ms, 1.44 Mbit/s) and Slow 3G (2 s, 400 kbit/s), over HTTP/2. Three runs
each, alternating A and B, and paused while any web build ran on the host
(load 10-19 throughout). **A** is the live release (Dartvel 132c51d5a). **B**
is the same binary behind a proxy that rewrites each page into what the
SSR-first build writes: the head style and handover script (byte-identical
to `dvSsrFirstHead`'s output for the site's colours), the document first in
the body, no logo preload, and a lazy logo. The change is HTML only, so the
app's code is the same in A and B. Both go through the same proxy, which
recompresses every page. *Readable* is the first paint with page text on
screen and on top. *Clickable* is a real link that hit-tests at its own
position. For A, both are the first frame. *Bytes* is everything downloaded
by then. The tool is `saas-metrics.tools.sigmadev.digital`, a Pro tool.

| Fast 3G | FCP | LCP | Readable | Clickable | First frame | Bytes until readable | CLS |
|---|---|---|---|---|---|---|---|
| Home, A | 0.8-1.9 s | 1.8-4.7 s | 31.2-32.6 s | 31.2-32.6 s | 31.2-32.6 s | 2,911 KB | 0.002 |
| Home, B | 1.0-1.3 s | 1.0-1.3 s | **1.0-1.3 s** | **1.0-1.3 s** | 29.4-33.4 s | **8 KB** | 0.000 |
| Pricing, A | 0.9-1.1 s | 1.9-2.1 s | 32.1-36.3 s | 32.1-36.3 s | 32.1-36.3 s | 2,906 KB | 0.002 |
| Pricing, B | 1.1-1.3 s | 1.1-1.3 s | **1.1-1.3 s** | **1.1-1.3 s** | 32.6-35.7 s | **16 KB** | 0.000 |
| Tool, A | 0.8 s | 1.7-1.9 s | 32.1-34.9 s | 32.1-34.9 s | 32.1-34.9 s | 3,912 KB | 0.002 |
| Tool, B | 1.0-2.2 s | 1.0-2.2 s | **1.0-2.2 s** | **1.0-2.2 s** | 30.5-33.9 s | **6-35 KB** | 0.000 |

| Slow 3G | FCP | LCP | Readable | Clickable | First frame | Bytes until readable | CLS |
|---|---|---|---|---|---|---|---|
| Home, A | 2.3-2.5 s | 6.0-6.3 s | 78.3-80.1 s | 78.3-80.1 s | 78.3-80.1 s | 2,911 KB | 0.002 |
| Home, B | 2.7-2.8 s | 2.7-2.8 s | **2.7-2.8 s** | **2.7-2.8 s** | 76.4-78.9 s | **8 KB** | 0.000 |
| Pricing, A | 2.5-2.7 s | 6.1-7.0 s | 81.3-84.0 s | 81.3-84.0 s | 81.3-84.0 s | 2,906 KB | 0.002 |
| Pricing, B | 2.6-3.3 s | 2.6-3.3 s | **2.6-3.3 s** | **2.6-3.3 s** | 79.6-82.6 s | **16 KB** | 0.000 |
| Tool, A | 2.3-2.4 s | 5.7 s | 93.7-95.2 s | 93.7-95.2 s | 93.7-95.2 s | 3,913 KB | 0.002 |
| Tool, B | 2.3-3.0 s | 2.3-3.0 s | **2.3-3.0 s** | **2.3-3.0 s** | 92.2-93.6 s | **6 KB** | 0.000 |

Total bytes per page are within 15 KB of each other (B skips the splash
logo). In A, FCP and LCP are the splash and its logo. In B they are the
document, so FCP is 0.1-0.4 s later (the page is about 0.6 KB larger and
paints text, not a colour) and LCP is earlier.

What a visitor sees at the handover, checked in Chrome at 390 px, light and dark:

- Up to 3.47.7 (the measurements above), the document was a reading column
  in the system font, in the site's light/dark page colours. At the first
  frame it faded out over 200 ms onto the app's own layout, fonts and
  imagery. Nothing moved (CLS 0.000), but the page changed look at that
  moment. Since then it is laid out as the app draws the page; see *SSR-first
  in the app's own look* below.
- A reader who has scrolled the document keeps their place. The section at
  the top of their screen is handed to the find runtime, which scrolls the
  app to it. The app first draws at its top, then scrolls there, about
  0.3 s after the fade.
- A link tapped before the app loads is a normal navigation to that page,
  served the same way.
- Focus inside the document moves to the app. A selection in progress
  holds the handover until it ends (at most 10 s).

Scripts: `measure.mjs` (with readable, clickable and CLS added),
`ssrproxy.mjs`, `matrix.sh`, `table.mjs`.

### SSR-first in the app's own look (November 2026)

The document is now laid out the way the app's first frame draws the page,
so the handover changes nothing a visitor can see (NEW_SPEC.md, *SSR-first
in the app's own look*). The build's capture, which already runs every
public route in Chrome, asks the app what it painted
(`dvPaintSnapshot`, through the capture hook) at each width of
`dartvel.web.ssrFirst.widths` (default 360, 390, 768, 1024, 1366, 1920), in
light and dark, and reads each link, button and field's box off the
semantics host. `dvSsrFirstLayout` keeps the document as it is and places
its text, links and fields at those boxes, in the app's fonts (the
FontManifest files, `font-display:swap`) and colours, over an
`aria-hidden` layer for surfaces, borders, shadows, images and icons.
Between two captured widths every box moves linearly; what is on screen at
one width and not the next switches at the midpoint. The rules for the first
two screens come first; the rest are in a second stylesheet after the
document, so the first screen paints without waiting for them. It applies
only on a screen with scripting, before the handover, in a browser that
reads nested CSS; print, no script, older browsers and the page after the
handover get the reading column.

Measured with the handover diff (`~/sigmadev-speed/handover-diff`: Chrome,
the SSR-first document with the app script refused against the app's first
frame, pixel diff and every visible text block found again by OCR) on
sigmadev.digital built with this change as a web-server binary, against the
same pages before it (the live site rewritten into SSR-first, 23 November).
*Median offset* is how far a block of the document is from the same text in
the app; *size* and *colour* count blocks whose glyph size or ink differ.

| Page | Width | Scheme | Pixel diff, before → now | Median offset, before → now | Size / colour mismatches now |
|---|---|---|---|---|---|
| Home | 390 | light | 68.4 % → 10.5 % | 34 → 1 px | 0/6, 0/6 |
| Home | 390 | dark | 23.4 % → 12.2 % | 34 → 1 px | 0/6, 0/6 |
| Home | 1024 | light | 64.6 % → 11.2 % | 137 → 1 px | 1/16, 1/16 |
| Home | 1024 | dark | 15.6 % → 12.3 % | 137 → 1 px | 1/16, 1/16 |
| Home | 1366 | light | 69.0 % → 8.1 % | 262 → 0 px | 2/18, 0/18 |
| Home | 1366 | dark | 12.1 % → 9.1 % | 253 → 1 px | 1/19, 0/19 |
| Pricing | 390 | light | 56.3 % → 3.5 % | 100 → 1 px | 0/6, 0/6 |
| Pricing | 390 | dark | 24.6 % → 4.4 % | 100 → 0 px | 0/6, 0/6 |
| Pricing | 1024 | light | 52.3 % → 4.4 % | 115 → 1 px | 0/17, 0/17 |
| Pricing | 1024 | dark | 14.6 % → 6.0 % | 115 → 1 px | 1/17, 0/17 |
| Pricing | 1366 | light | 46.6 % → 2.9 % | 217 → 1 px | 1/18, 0/18 |
| Pricing | 1366 | dark | 10.2 % → 4.3 % | 217 → 1 px | 2/17, 0/17 |

Every block on screen in both pictures is now in the app's font at its
size; the tool still lists as "not found" the text the document keeps for
screen readers only (a link's name, a menu that is closed), which is a 1 px
clipped box and paints nothing. What the pixel diff still saw then: glyph
antialiasing (the browser and Flutter rasterise the same font differently),
the home page's two radial glows behind the hero, which the site painted
with a `CustomPainter`, and its headline's fade, a `ShaderMask`. Neither a
custom painter nor a shader can be read back from the render tree.

#### The last gaps (24 November 2026)

- **Glows and gradient text.** `DVRadialGradient` (an elliptical radial
  gradient sized to the box), `DVGradientPainter` (gradients stacked over a
  box; any painter can implement `DVDescribedPainter`) and `DVGradientSpan`
  in a `DVGradientText` (text filled with a gradient along its line pieces)
  paint in Flutter and are read back by the snapshot, so the document draws
  them in CSS: the glows as `radial-gradient` layers, the faded run as the
  document's own text with `background-clip: text` (still selectable and
  findable; a selection shows its glyphs). sigmadev.digital's hero now uses
  them. Linear gradients also keep their angle and stops on a box of any
  shape, and radial ones their radius.
- **Text fields.** Material draws a field's border and fill with a painter
  of its own; the snapshot works them out from the `InputDecoration` and
  the theme as `InputDecorator` does (Material 3 and 2 defaults included).
  The text a field starts with is painted by its editable, not a paragraph,
  so the snapshot read none of it and every field stood empty until the app
  took over (sigmadev.digital's tools: the QR code's link, the price list's
  rows). It is now read (never from a password field) and becomes the
  input's `value`, in the app's font, colour and inner padding; a field
  the document has no input for, such as a menu that picks a value, has its
  text drawn with the layer.
- **Screen height.** Each width is read again at a screen a quarter
  taller; what moves or grows between the two gets a `dvh` term. The heights
  two widths were captured at are taken out before moving between widths,
  so they are not read as a change with width.
- **Tab.** A link in a closed menu could take the same words painted
  elsewhere at that width (sigmadev's header "Tools" took the footer
  heading's at 390), leaving a Tab stop of no size; such text is now
  matched last. A control the layout never places shows itself where the
  reader can see it when focused.
- **Stacking.** Every link and field is stacked above everything painted,
  so its text and focus ring are never under a surface. What the app pins
  to the screen and paints after the page's links -- a consent banner, a
  bottom sheet, an app bar -- is now lifted above them too, with the pinned
  controls on it, keeping its own order: sigmadev.digital's hero buttons
  ("Chat on WhatsApp", "See plans and prices") showed through its consent
  banner on a phone and a desktop. A pinned piece painted before any
  control's content, such as a background, stays behind.
- **Triple-click** already selected the paragraph in Chrome; the earlier
  report came from a check that clicked after Tab had scrolled the page.

#### The first paint (25 November 2026)

sigmadev.digital (3.47.8, SSR-first) painted a blank frame before its page
on a slow line, in light and dark: Chrome paints as soon as the head is
read, and the canvas was the browser's white until the body arrived.
Measured as above (390 px, Fast 3G, 4x CPU, fresh profile, app script
refused so only the document is timed; 15 runs each, host load 11-16, so
single runs vary by a second):

| | First paint | First text | What the first frame is |
|---|---|---|---|
| 3.47.8, dark | 520 ms (median) | 1,356 ms | a blank canvas, then the page |
| 3.47.8, light | 412 ms | 1,272 ms | white, then the page (its hero is dark) |
| now, dark | 1,656 ms | 1,656 ms | the first screen in place |
| now, light | 1,608 ms | 1,608 ms | the first screen in place |

- **The canvas is the app's colour.** The splash style paints
  `html{background}` in the splash colours, light and dark, so nothing
  before the body is white (every Dartvel web build, SSR-first or not).
- **The first paint waits for the first screen.** The SSR-first head adds a
  render-blocking `<link rel="expect" blocking="render">` naming
  `#dv-first-screen`, an empty `aria-hidden` element the layout writes after
  the document and before the stylesheet for below the fold. Chrome paints
  nothing until it is parsed, so the first frame is the whole first screen,
  consent banner and app bar included, never the canvas or half a page.
  The link is written by a script with the page's own URL: under
  `<base href="/">` a bare `#id` names the site root and is ignored on every
  other route. A page with no layout is held until it is parsed; Firefox and
  Safari ignore the attribute and paint on the app's colour. The same page
  with and without the link, 12 runs each, alternating: first text
  2,070 ms without, 2,246 ms with (within the noise of the host).
- **A small image on the first screen is in the first frame.** Holding the
  paint for the first screen did not hold it for images: the header logo of
  sigmadev.digital came 0.2 s (light) to 3 s (dark) after the first frame.
  The `<img>` was fetched on its own and decoded asynchronously, and the
  dark logo was a `content:url()` the browser only found once the
  stylesheet applied. The build now reads each image on the first screen
  from the web root it built and writes those up to 8 KB (24 KB a page,
  both schemes' variants counted) into the page as data URIs with
  `decoding="sync"`: a data URI loads at once, so the image is drawn in the
  frame the first screen is. A bigger image stays a URL with
  `fetchpriority="high"`, never waited for; below the first screen images
  stay `loading="lazy"`. sigmadev.digital home, Fast 3G, 4x CPU, 390 px,
  8 runs each alternating (host load ~20): first contentful paint median
  1,840 ms before / 1,562 ms after (light), 1,368 / 1,392 ms (dark), the
  page 72 KB / 80 KB compressed; the filmstrip shows the logo in the first
  painted frame in both schemes.
- **Fallback fonts the app does not bundle are not named.** The capture's
  theme carries Material's Linux fallback list (Ubuntu, Adwaita Sans,
  Cantarell, DejaVu Sans, Liberation Sans, Arial) from the build box. Flutter
  on the web never draws with system fonts, so the list only made the
  browser look each one up before the first layout, and draw in one the app
  never shows. In Chrome on Linux those lookups go to the browser's font
  service: before the first paint they took 675 ms in 150 calls (4x CPU),
  432 ms in 109 calls without the list. 10 KB less HTML (293 KB), the same
  after brotli.

The first text still comes about 0.9 s after the last byte of the
document. Almost all of it is one layout of the whole document, and most of
that is Chrome on Linux asking its font service for each font size the page
uses (a desktop Linux visitor pays it; Android draws fonts in process).
Splitting the stylesheet further does not move it: the first screen's rules
and text are in by about byte 120 K, in the first round trips, and both
stylesheets reach the browser before that layout starts.

Handover diff on the web-server build (`~/sigmadev-speed/handover-diff`,
home, light/dark), 3.47.8 → now: pixel diff 3.3 → 3.1 % and 3.6 → 3.2 %
at 390 px, 3.0 → 3.0 % and 2.7 → 2.6 % at 1366 px; offsets unchanged (median
4 px at 390, 1 px at 1366). Find, selection, Tab order and the accessibility
tree of the document are the same (67 headings and links on the home page).
  The browser test still triple-clicks.

Measured the same way, on the same sigmadev commit built twice as a
web-server binary (before: Dartvel at #294; after: this change, with the
site's hero on the new primitives). The tools pages are their own hosts
(`tools.` and `base64.tools.`), reached with `--host-rules` and
`--secure-origins`.

| Page | Width | Scheme | Pixel diff, before → now |
|---|---|---|---|
| Home | 390 | light | 10.5 % → 3.1 % |
| Home | 390 | dark | 12.2 % → 3.4 % |
| Home | 1024 | light | 11.2 % → 5.0 % |
| Home | 1024 | dark | 12.3 % → 4.4 % |
| Home | 1366 | light | 8.1 % → 3.2 % |
| Home | 1366 | dark | 9.1 % → 2.9 % |
| Pricing | 390 | light / dark | 3.5 / 4.4 % → 1.3 / 1.8 % |
| Pricing | 1024 | light / dark | 4.4 / 6.0 % → 2.4 / 3.6 % |
| Pricing | 1366 | light / dark | 2.9 / 4.3 % → 1.2 / 2.2 % |
| Tools | 390, 1024, 1366 | light / dark | 2.2-4.7 % → 2.2-4.5 % |
| Base64 tool | 390, 1024, 1366 | light / dark | 1.2-4.0 % → 1.2-3.7 % |

Median text offsets stay at 0-1 px (6 px on the base64 tool at 390, as
before). What is left is glyph antialiasing and, on the tool pages, a
dropdown's chosen value (the capture reads the page before the tool fills
it) and checkboxes, which Material paints itself.

Cost: about 0.3 KB more compressed on the home page (the gradient layers,
the `dvh` terms and the focus rule), and three more reads per route at
build time (nine instead of six).

Cost: the home page went from 8 KB to about 11 KB compressed before its
first screen can paint (the first stylesheet), and about 24 KB in all; the
build reads each route at six widths in two schemes, once each when the
app says it is idle; the whole capture of sigmadev.digital's 226 routes took
6 to 9 minutes on the shared build server under load.

### A sentence with links is one block (25 November 2026)

A paragraph with links in its line (`<p>words <a>link</a> words</p>`, what
the build writes for a sentence laid out with `DVWidgetSpan`) was laid out
piece by piece. The app paints such a sentence as one paragraph with a gap
for each link and each link's words in its gap, so no single piece of the
document matched the painted paragraph: its words were drawn by the
`aria-hidden` layer (CSS `content`, not text), the document's own words were
hidden for readers, and each link sat at its own box on top. On
sigmadev.digital/about it read "Questions, or a project in mind? Our , and
explain how we handle your data" with the links floating over the line, and
Ctrl+F and a selection could not run across a link. Now the `<p>` is matched
to that painted paragraph as a whole (its words, ignoring white space and the
links), placed as one block at its box, line height and wrapping, and its
links flow inline in their own colour and underline with no box of their
own. The paint snapshot also counts a paragraph's lines by line box, so the
link (a 32 px placeholder next to 24 px glyphs) no longer counts as a line:
the about page's two 32 px lines had been read as three of 21.33 px.

Measured on sigmadev.digital built as a web-server binary with this change
against the same branch on Dartvel main before it, /about and /danieleffiong
at 390, 1024 and 1366, light and dark: every sentence with links shows all
its words, no link overlaps a word, find matches "free quote. Our privacy
policy, terms and refund policy explain", a selection reads the sentence with
its spaces, Tab reaches each link at the app's x. Handover diff: pixel diff
unchanged on every page, viewport and scheme (the sentences are below the
first screen); the largest text offset on /about fell from 581 to 36 px on a
phone and from 282/1489 to 173 px at 1024/1366 (the 173 is the logo's reader
label, the same before), median offsets the same or 1 px lower. Page text
(220 sitemap paths) is identical to the build before, apart from the random
and clock tools.

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
