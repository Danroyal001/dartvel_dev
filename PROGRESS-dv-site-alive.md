# PROGRESS: dv-site-alive

Task: make dartvel.dev (sites/dartvel_site) look alive, 100% Dartvel, with
generic framework primitives for the motion, honest product story and proof,
and every Dartvel convention followed. Branch `agent/dv-site-alive`, PR into
`main`. Never merge or deploy.

## Review of the earlier attempt (2026-10-14)

The earlier commits on this branch were reviewed and mostly replaced:

- `DVModifier.meshGradient` was a static `LinearGradient`; `hoverGlow` was
  `hover(shadow)` and replaced the box's own hover state; `stagger` was
  `revealOnScroll(delay:)` again. The tests only asserted `isNotNull`.
- `lib/pages/index.dart` did not compile (`DVBox(if (narrow) ...)`), so the
  whole site test suite failed to load.
- The "live apps" band named five apps with descriptions nothing in the
  repository backs, some of which read as client names, and showed a figure
  of 5 for them. The story band claimed MCU and XR without saying they are
  paid targets.
- The hero terminal used `Container`, `Text`, `Row` and `Padding`, and the
  site linked to 69 pages by path string.

## Done (2026-10-15)

See the commit list on the branch. In short: real mesh, pointer glow and
staggered reveal primitives in `dartvel_flutter` (behaviour tests); typed
routes across the site; a home page with a live signals demo in the hero,
an honest ONE PROJECT band and a RUNNING ON DARTVEL band with only measured
numbers; `main.dart` is one `DV.run` call; the shared chrome is DVBox; the
deploy script is Dart; no private host paths in tracked files.

## Final report (2026-10-15)

### Works (tested)

- Framework, generic for every app (`packages/dartvel_flutter`):
  `meshGradient` (soft blobs that drift under the pointer, about 12 steps a
  second, none off screen; still under reduced motion), `hoverGlow` (follows
  the pointer, repaints without a rebuild, layers with `hover`),
  `revealChildren` (staggered reveal; `Expanded`/`Flexible` kept). 18
  behaviour tests, each seen failing first. Full package suite after merging main: 2778 pass, and the two failures listed under Not done, which fail on main too.
- Home page: a live demo of three signals in the hero (a test holds the
  printed code to the code that runs), ONE PROJECT band (web, web server,
  phones, desktops, microcontrollers, XR headsets, Studio, badged from
  spec-status/build-targets; MCU and XR say Cloud plan), RUNNING ON DARTVEL
  band (this site, its search, its Studio; only the two figures in
  docs/web-performance.md), staggered reveals in every band, a glow on every
  card, version and spec counts from their constants, dark and light
  filled-button contrast fixed (2.48:1 and 4.499:1 before).
- Conventions: typed routes for every site link (69 replaced, guarded by a
  test); `main.dart` is one `DV.run` call (a TODO names `DV.run(args)` +
  `@DVAppRoot`, which are Designed, not built); the layout, bands, bullets and
  code block are DVBox (guarded by a test); the backend sample on the home
  page returns a typed `String`, not a map; the site deploy script is Dart;
  no private host paths in tracked files (guarded by a test).
- Site suite: 420 pass, 1 skipped (needs the private enterprise checkout).
- Checked in Chromium on a `dartvel build web --no-prerender` build: 360,
  768, 1280 and 1920 px, light and dark, no horizontal overflow, no console
  errors apart from the sandbox's blocked outbound requests; hero still
  under `prefers-reduced-motion`, drifting under the pointer otherwise.
  Screenshots in docs/screens/site-alive/.

### Partial

- Lighthouse, mobile profile, home page, served locally with gzip: Performance
  60, Accessibility 100, Best Practices 79, SEO 100 (three runs; FCP 1.6 s,
  LCP 1.7-1.8 s, TBT 7.5-8.5 s, CLS 0.001). Performance is not 90: with all
  motion off it measures 61 (TBT 6.3 s), so what remains is the Flutter web
  payload (CanvasKit plus dart2js), the framework work already listed in
  docs/web-performance.md (Wasm, Brotli, hashed names, font subsetting) and
  the visible first frame in docs/site-gap-audit-2026-10.md #2. An earlier
  mesh that animated forever measured 140 s TBT; that is fixed.
- The build's semantics capture could not run here: this sandbox cannot reach
  www.gstatic.com, so CanvasKit never loaded in the capture's browser. The
  local check used `--no-prerender` with CanvasKit served from the build.
  Lighthouse on that build is close to, and not identical with, production.

### Not done

- Push and PR: this session had no write access to the repository.
- Still raw Flutter in site code: `PageScroll` (owns a ScrollController and
  uses ListenableBuilder; a functional widget has nowhere to own a
  controller, which needs a framework primitive), the stateful docs widgets,
  the fold and password-manager demos.
- Site search and the contact handler return `Map` payloads (JSON-shaped) from
  backend functions; site search is owned by other work and was left alone.
- Pricing and showcase pages: pricing is the owner's decision.
- Two framework tests fail on `main` too and were left to their owners:
  `web_bindings_test` (`window.setFullscreen` has no web answer) and
  `studio_editor_test` (dragging from the palette).
- No diff against the live site's HTML: the sandbox cannot reach it.
