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

## What changed (0.10.0)

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

Measured after the 0.10.0 deploy; see the rows added below.

## Still to do

Ranked by what they would save:

1. **WebAssembly (skwasm) by default, with the JavaScript fallback**
   (`docs/web-roadmap.md` item 15): smaller and faster to start than
   CanvasKit plus dart2js, once every Dartvel web binding is
   `dart:js_interop`-clean.
2. **Brotli.** Everything is gzip; brotli is 15-20% smaller for JavaScript
   and WebAssembly. `dart:io` has no brotli encoder, so the build needs one
   (or the server to compress once and cache).
3. **Content-hashed file names**, so `main.dart.js` can be cached as
   immutable instead of revalidated on every visit. Flutter names its output
   without hashes; the deferred parts are loaded by name, which is what makes
   renaming more than a string replace.
4. **Font subsetting** to the glyphs the site uses.
