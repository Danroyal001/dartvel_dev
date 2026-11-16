# Duplicated code paths: audit, 15 Nov 2026

Places where one job is done by two separate implementations that can drift.
The rule they are measured against: `web` and `web-server` share one render
path (web prerenders, web-server renders on request), Studio uses the app's
one render path, splash and theme, and Dartvel has one code generator (the
CLI). Read from `origin/main` at `0be822724`, by grep and reading only.

Ranked by risk: how likely the copies already disagree, and how much a
reader, a crawler or a security boundary sees when they do.

| # | Risk | Job | Status |
|---|---|---|---|
| 1 | High | Rendering a data-backed page (model pages, page-data resolver) | Open |
| 2 | High | Answering a page request: deployed server vs `dartvel dev --release` preview | Partly fixed (redirect query) |
| 3 | High | `dartvel prerender`: second capture, sitemap and robots pipeline | Open |
| 4 | High | Which pages an application has: project graph (Studio, admin) vs client generator | Fixed |
| 5 | Medium | Route paths and annotation parsing: retired `dartvel_generator` vs CLI | Open |
| 6 | Medium | "Is this request signed in?" assembled five times | Open |
| 7 | Medium | The home page's head written outside `dvRenderRoutePage` | Open |
| 8 | Medium | Docs site: a second web app with a hand-written HTML shell | Open |
| 9 | Low-medium | Studio's splash redrawn in Flutter next to the web splash | Open |
| 10 | Low-medium | Two default security-header sets that disagree | Fixed |
| 11 | Low | Rust runtime: SPA fallback and route matcher beside the Dart ones | Open (latent) |
| 12 | Low | Semantics-capture file name computed twice in the build | Open |
| 13 | Low | `encodeNativeRequest` duplicated for web | Accept |

## 1. Rendering a data-backed page (High)

- Path A: `packages/dartvel_core/lib/src/web/route_page.dart:253`
  `dvRenderRoutePage` -> `dvStaticPage` (`:29`). Used by the static build
  (`build_command.dart:4856`), the deployed server for routes with no data
  (`dartvel_shelf/lib/src/ssr_helper.dart:320`), the preview
  (`dartvel_cli/lib/src/build/web_server.dart:628`) and Studio
  (`dartvel_core/lib/src/admin/admin_server.dart:315`).
- Path B: `packages/dartvel_core/lib/src/web/page_data.dart:486`
  `dvRenderPage` -> `dvRenderRoute` (`:458`) + `_dvWithDocument` +
  `dvApplyPageExtras` (`:813`). Used by both servers whenever a page-data
  resolver answers (model pages, Studio-published pages), for refusals
  (401/404 bodies) and for a manifest without a `page` entry.
- Same job: the head, structured data, icon and crawler-visible document of
  one route.
- Observed divergence: `dvRenderRoute` passes no `alternates`,
  `defaultAlternate`, `robots` or `schemaType` to `dvSeoHead`, and writes
  structured data from `DVPageData.structuredData` inside `<!--dv:ld-->`
  markers instead of `dvStructuredData` inside the SEO region. A model page on
  a multilingual site has hreflang links and a `robots` meta in the static
  build and has neither when the web-server binary renders the same URL.
  The two also disagree on where JSON-LD lives, so a page rendered by one and
  then the other can carry two blocks.
- Fix: `dvRenderPage` builds a `DVRoutePage` from the `DVPageData` (title,
  description, image, favicon, schemaType, document as `html`, text) and
  calls `dvRenderRoutePage`; `dvRenderRoute` becomes a thin wrapper over the
  same function for the refusal bodies. One parity test: the same route and
  data through the static build and through `handleSsrFallback` give the same
  bytes.

## 2. Answering a page request: deployed vs preview (High, partly fixed)

- Path A (production): `packages/dartvel_shelf/lib/src/ssr_helper.dart:148`
  `_fromManifest`, on Dartvel's own `Request`.
- Path B (`dartvel dev --release`, `release_server.dart:85`):
  `packages/dartvel_cli/lib/src/build/web_server.dart:231`
  `dvWebServerHandler`, on `package:shelf`.
- Same job: host redirects, `dartvel.redirects`, host mounts, the guard and
  sign-in redirect, refusals, rendering, 404, caching and streaming. Both
  call the shared render function, but everything around it is written
  twice, and the comments say "as the deployed server answers them".
- Observed divergences:
  - `dartvel.redirects` kept the request's query in production
    (`ssr_helper.dart:192`) and dropped it in the preview
    (`web_server.dart:477`): `/old?ref=mail` went to `/new?ref=mail` deployed
    and to `/new` in preview. **Fixed in this PR** (see below).
  - The 401 body for a signed-out guarded route is `dvRenderRoute` of the
    shell's title in production (`ssr_helper.dart:296`) and `dvServeRoute`
    in the preview (`web_server.dart:~600`).
  - `_signInLocation` is copied word for word (`ssr_helper.dart:541`,
    `web_server.dart:905`); the host resolution is copied twice more
    (`ssr_helper.dart:529` `_requestHost`, `web_server.dart:891`
    `_shelfRequestHost`).
- Fix: the preview wraps the deployed handler instead of reimplementing it:
  convert the shelf request to `core.Request` (the preview already has
  `_coreRequest`, `web_server.dart:769`) and call `handleSsrFallback`, keeping
  only the dev-only parts (Studio dev grant, local files) in the CLI. Until
  then, every rule both need lives in core and both call it, as
  `dvRedirectLocation` now does.

## 3. `dartvel prerender`: a second capture pipeline (High)

- Path A: `packages/dartvel_cli/lib/src/commands/prerender_command.dart`:
  its own static server (`:85`), route discovery by scraping `<a href>`s
  from the home page, its own semantics walker (`:151`), its own file naming
  for `.dart_tool/dartvel_semantics/`, and its own `sitemap.xml` (`:230`)
  and `robots.txt` (`:252`) written into `build/web`.
- Path B: the build's capture, `packages/dartvel_cli/lib/src/build/semantics_capture.dart`
  (`dvSemanticsExtractScript` `:116`, `dvSemanticsPathFor` `:119`,
  `dvCaptureHandler`), and `dvSitemap`/`dvRobots`
  (`static_seo.dart:315`, `:393`) called from `build_command.dart:4768`.
- Observed divergences: the prerender walker is the old one. It skips
  wrapper elements (so a heading inside Flutter's `<header>` landmark is
  lost), reads no text fields, no `dartvel:` identifiers and no media, and
  captures guarded routes. It writes to the same files the build reads, so
  running it after a build replaces good captures with worse ones. Its
  sitemap lists every scraped link, guarded routes included, with no XSL,
  exclusions or priorities, and its default `--base-url` is
  `http://localhost:8080`, so the production sitemap and robots.txt end up
  naming localhost. The build's own fallback message still tells people to
  run it (`semantics_capture.dart:285`).
- Fix: `dartvel prerender` becomes "run the build's capture": call the
  capture `build_command` runs (`dvCaptureHandler`, `dvSemanticsExtractScript`,
  `dvSemanticsPathFor`, the router's route list) and write no sitemap or
  robots of its own, or retire the command and point the message at
  `dartvel build web`.

## 4. Which pages an application has (High, fixed)

- Path A: `packages/dartvel_cli/lib/src/graph/project_graph.dart` `_routesIn`
  (was `:212`): every Dart file under `lib/`, routed with
  `RouteUtils.routeFor(rel, 'lib/pages')`, function pages only. The graph
  feeds Studio's routes tab and the admin dashboard.
- Path B: the client generator's scan of `dartvel.pagesDir`
  (`client_generator.dart:224`), which makes the router, and
  `dvGeneratedPageRoutes` (`adoption/adoption_build_checks.dart:128`),
  documented as "as the client generator discovers them".
- Observed divergence: with `dartvel.pagesDir: lib/screens` the graph listed
  `/lib/screens/index` instead of `/`; an `@DVPage` function outside the
  pages directory showed up as a route the router does not have; class pages
  (`extends DVClassWidget`/`DartvelPage`) were missing.
- **Fixed in this PR**: the graph takes its page list from
  `dvGeneratedPageRoutes(root, pagesDir)` and only names each page.
- Still open in the same file: backend functions are routed with
  `RouteUtils.routeFromRel(rel, 'lib/backend')` and found by
  `rel.contains('/backend/functions/')`, ignoring `dartvel.backendDir`; and
  the client generator's own page loop is not yet `dvGeneratedPageRoutes`
  itself, so there are still two scanners (the generator and the shared one).

## 5. Retired `dartvel_generator` vs the CLI (Medium)

- Path A: `packages/dartvel_generator/lib/src/utils/route_utils.dart` (whose
  comment says "Mirrors dartvel_cli's copy of this function") and
  `router_builder.dart` (its own page scan and `@DVPage` patterns).
- Path B: `packages/dartvel_cli/lib/src/generators/route_utils.dart`,
  `client_generator.dart`.
- Observed divergences (`diff` of the two `route_utils.dart`):
  `routeFor('lib/pages/(marketing)/index.dart')` is `/` in the CLI and
  `/index` in the generator; the generator's `extractParams` does not strip
  comments, so a `// note` beside a parameter becomes part of the next type;
  its `coerce` has no data-model support. The builders still auto-apply to
  every project that depends on the package.
- Fix: the CLI's copy survives. Either remove the builders in the planned
  release, or have `dartvel_generator` import the CLI's `RouteUtils` (needs a
  public `package:dartvel_cli/route_utils.dart` and a dependency on
  `dartvel_cli`) and delete its copy.

## 6. "Is this request signed in?" (Medium)

- The same `DVSessionAuthentication.authenticateRequest(plainLocal:...,
  authorization:..., cookie:..., host:...)` call is assembled by hand in
  `dartvel_core/lib/src/admin/studio_api.dart:414`,
  `admin/model_data_api.dart:139`, `admin/admin_server.dart:165`, the
  generated backend (`dartvel_cli/lib/src/generators/backend_generator.dart:1365`)
  and the preview (`dartvel_cli/lib/src/build/web_server.dart:793`).
- Drift already visible: `dvAdminAuthorized` runs it under
  `dvWithRequestTenant`, the others do not; the preview resolves the host
  through its own `_shelfRequestHost` and builds `plainLocal` from
  `requestedUri`, the rest through `DVSessionScope.requestHost` and
  `request.url`. A change to how sessions are read (a new cookie name, a
  header) has to land in five places, one of them a code template.
- Fix: one core function, e.g. `DVSessionAuthentication.ofRequest(Request)`,
  used by all four core sites and emitted by the generator; the preview calls
  it on `_coreRequest(request)`.

## 7. The home page's head (Medium)

- Path A: `packages/dartvel_cli/lib/src/commands/build_command.dart:4231`
  `_writeSeoHead`: `dvSeoHead` + `dvStructuredData` + `dvApplyFavicon` +
  `dvApplyPageHtml`/`dvApplyPageText` on `index.html`.
- Path B: `dvRenderRoutePage(shell, home)` (`build_command.dart:4863`), which
  then overwrites the same file on a static build.
- Drift risk: the first write is redundant whenever `/` is a route, and is
  the only one when it is not (no pages, or a host app whose root is not a
  Dartvel page). Its comments describe gaps (`WebSite` JSON-LD, the root's
  favicon) that `dvStaticPage` has since closed, which is how the two drift.
  On web-server builds this head and body sit in the shell every request is
  rendered from.
- Fix: write only the shared shell parts here (favicon, viewport) and render
  `/` through `dvRenderRoutePage` with a `DVRoutePage` made from the site's
  declarations when the router has no `/` page.

## 8. Docs site: a second web app (Medium)

- `packages/dartvel_cli/lib/src/build/docs_build.dart:61` `dvDocsIndexHtml`
  is a hand-written HTML document with its own palette (`#F3F3F7`/`#111116`)
  and no splash, and `dvBuildDocs` compiles `DVDocsApp` as a second Flutter
  web app under the docs mount.
- Against the rules: everything is Dartvel with no hand-written pages; one
  render path, one splash, the app's theme; every page server-rendered and
  selectable from the first frame. Studio was moved into the app for the same
  reason (it leaked as a separate build).
- Fix: docs screens become routes of the application under the docs mount,
  rendered through `dvRenderRoutePage` like Studio's.

## 9. Studio's splash (Low-medium)

- Path A: the web splash written into `index.html` by `dvWriteWebSplash`
  (`build/native_splash.dart`).
- Path B: `packages/dartvel_flutter/lib/src/studio/studio_host.dart:186`
  `DVStudioSplashView`, a Flutter redraw of it, fed by
  `client_generator.dart:5335` `_studioSplashArg`, which repeats the image
  file names as literals ("the names dvWriteWebSplash gives the pictures").
- Drift risk: the configuration is shared (`DVSplash.fromConfig`), the
  drawing is not; a layout or animation change to one leaves Studio's load
  looking different from the app's, and renaming the image files breaks
  Studio's picture silently.
- Fix: share the file names as constants now; longer term keep the web
  splash on screen until Studio's deferred code is in, as the app does at
  first frame, so there is one splash.

## 10. Default security headers (Low-medium)

- `packages/dartvel_core/lib/src/http/security_headers.dart:24`
  `dvDefaultSecurityHeaders` (`SAMEORIGIN`, HSTS `max-age=31536000` only
  over TLS) vs `packages/dartvel_core/lib/src/middleware/middleware.dart:228`
  `Middleware.securityHeaders()` (`DENY`, HSTS with `includeSubDomains`
  always).
- Drift risk: a route that opts into the middleware gets a different policy
  from the framework default, including an HSTS `includeSubDomains` the
  default deliberately refuses ("a framework cannot know what else runs
  under the same domain").
- Fix: the middleware starts from `dvDefaultSecurityHeaders` and states only
  what it adds.

## 11. Rust runtime beside the Dart server (Low, latent)

- `packages/dartvel_shelf/rust/src/lib.rs:2249` `catch_all_handler` can serve
  a SPA root's `index.html` straight from disk for any GET, which would skip
  the Dart SSR (head, crawler text, guard). It is off today
  (`dartvel_shelf/lib/src/server.dart:722` passes `null` to
  `_configureSpaRoot`); a future caller that passes the root reopens the
  guarded-page leak fixed in Dart.
- `lib.rs:480` `parse_route_pattern` mirrors core's URLPattern reading for
  per-route body limits; documented, and a mismatch gives a route the wrong
  body limit.
- Fix: delete the SPA branch (and `aw_configure_spa_root`), or document that
  page requests must reach Dart; keep a shared test table of patterns run by
  both the Rust and Dart matchers.

## 12. Semantics-capture file name (Low)

- `build_command.dart:4659` `_semanticHtmlFor` recomputes the file name that
  `semantics_capture.dart:119` `dvSemanticsPathFor` owns (and which
  `build_command.dart:4450`, `:4611` already call).
- Fix: call `dvSemanticsPathFor`.

## 13. `encodeNativeRequest` (Low, accept)

- `dartvel_core/lib/src/http/native_client.dart:74` and
  `native_client_web.dart:33` are identical and the duplication is stated
  and justified. Nothing to do beyond keeping them identical.

## What was checked and is already one path

- Head, crawler text and minify for static and web-server routes:
  `dvRenderRoutePage` (finding 1 is the exception).
- `dvSeoHead`, `dvMinifyHtml`, `dvPageText`, `dvRobotsTxt`, favicon: the CLI
  files re-export core.
- Studio's screens: rendered by `DVAdminServer` through `dvRenderRoutePage`.
- Static sitemap and web-server sitemap both call `dvSitemap`; robots both
  call `dvRobots`.
- Guard discovery in the client generator goes through `discoverGuards`.

## Fixed in this PR

1. `dvRedirectLocation(to, query)` in `dartvel_core` (`web/page_data.dart`):
   the one rule for carrying the query on a redirect, used by both servers
   for host redirects and `dartvel.redirects`. Test:
   `packages/dartvel_cli/test/config_redirects_test.dart`, group "the preview
   answers a redirect with the query the deployed server keeps".
2. The project graph's pages come from `dvGeneratedPageRoutes` and
   `dartvel.pagesDir`. Test: `packages/dartvel_cli/test/project_graph_test.dart`,
   "pages are the ones the generated router serves, from dartvel.pagesDir".
