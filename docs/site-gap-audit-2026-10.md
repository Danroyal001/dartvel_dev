# dartvel.dev and Studio: gap audit, October 2026

Walked on 14 October 2026 against the live site (release `20261014120453-8a0f77b8`,
Dartvel 0.12.1, then `20261014153908-8f3e69d7` with the search fix) and the
source on `main`. The marketing and docs site is measured against vercel.com,
flutter.dev and laravel.com; Studio against Figma, Webflow, Bubble and Power
Apps (see `docs/studio/PARITY.md`, which stays the Studio source of truth).

How it was checked: every route in `sitemap.xml` fetched (status, title,
description, h1, every link), common URLs a person would guess, the raw
server-rendered HTML before Flutter, and a real headless Chrome (our own, not
the shared one) at 390x844 and 1440x900 in light and dark: screenshots,
horizontal overflow, console errors, splash time, text selection, find-in-page,
the first 40 Tab stops, tooltips and the sign-in fields. Timings are from
localhost with software rendering: compare them with each other, not with a
phone.

Ranked by how badly they fail a reader. **P0** breaks a promise or a core task,
**P1** fails a basic a demanding user expects, **P2** is wrong or weak, **P3**
is polish. "Owner" says who fixes it: *framework* (here, generic for every
Dartvel app), *docs* (site docs pages), *site look* (the marketing redesign on
`agent/dv-site-alive`), *Studio* (Studio parity on `agent/dv-studio-parity`),
or *release*.

## P0

| # | Gap | Where | Evidence | Fix | Owner | State |
|---|---|---|---|---|---|---|
| 1 | Site search answered every query with a 500 since 12 Oct | `/api/search` (Ctrl+K on every page) | `Invalid argument (documents): hold no words to learn from` at `site_search.dart:73`. `DVSitePages` read `dartvel_routes.json` from disk; a web-server binary serves its site from its pack, so the corpus was empty | Read the manifest through `DVAssetSources`; empty corpus answers `[]`; deploy check queries search | framework + site | **Fixed, deployed** (#120, release `20261014153908-8f3e69d7`); live `?q=signal` answers 200 with results |
| 2 | The first screen is a logo splash, not the page | every route | Server HTML sits in `.dv-fallback`, clipped to 1x1 px by `@media screen{...clip-path:inset(50%)}` and `hidden="until-found"`; splash 3.5 to 6 s before any text; `main.dart.js` 3.3 MB sent `Cache-Control: no-cache` | Show the server-rendered document, styled in the app theme, until Flutter's first frame, then hand over in place; long-lived caching for hashed JS. Breaks the rule "a real, visible document from the first frame" | framework | Open; see "The visible first frame" below |
| 3 | `npm i dartvel_dev` and `dartvel update` broken for 0.12.1 | GitHub release `v0.12.1` | Release had no assets; npm wrapper 404s on `releases/download/v0.12.1/dartvel-linux-amd64`; `latest.json` 404 | Build and attach Linux amd64/arm64, `SHA256SUMS`, `latest.json`; make the release step refuse a release with no assets | release | In progress (binaries built locally, see STATUS) |
| 4 | Keyboard users cannot reach most of a docs page | `/docs/*` | 40 Tabs loop over about 18 stops at 1440 px (header, first 8 sidebar links, one "On this page" entry); never the search box, the other ~45 sidebar links, Copy buttons, prev/next or footer. At 390 px Tab only cycles the header and "Open the docs menu" | Focus traversal must scroll off-screen controls into view and include the whole page; add a skip-to-content link | framework | Open |

## P1

| # | Gap | Where | Evidence | Fix | Owner |
|---|---|---|---|---|---|
| 5 | No show/hide on any Studio password field | `/__studio/login`, setup, record editor | Owner report; fields were bare obscured inputs | One `DVPasswordReveal` toggle button with `aria-pressed`, also in the server HTML | framework, **PR open** (`agent/dv-password-reveal`) |
| 6 | Server-rendered pages lose their forms | any page with a text field | The capture skipped the `<input>` inside a Flutter text field node; the sign-in document was a heading and a paragraph | Captured text fields become labelled inputs; Studio sign-in/setup documents carry theirs | framework, **in the same PR** |
| 7 | `/metrics` is public | `https://dartvel.dev/metrics` | 200 with Prometheus request counts and uptime to anyone | Serve metrics on loopback only, or behind the Studio grant | framework |
| 8 | Focus is barely visible and lands on nothing | every page | First Tab lands on an invisible full-viewport container; the home logo link is never a stop; "Compared" and "pub.dev" take two Tabs each; focus fill is 1.32:1 on white (needs 3:1) | One stop per control, a 3:1 focus ring | framework |
| 9 | Dark-mode primary button text fails contrast | `/` "Create your first app" | White on `#7BA2FF` is 2.48:1 (needs 4.5:1) | Darker button or dark text in the dark theme | site look |
| 10 | 404 page and Studio sign-in ignore the site theme | `/404-test-xyz`, `/__studio/login` | Flutter default lavender/indigo instead of `#2F6BFF`; 404 has no header or footer, no server text, the home page's title and a canonical pointing at the bad URL | Render both in the app layout and theme; 404 gets its own title and text and no canonical | framework (404, Studio theme rule) |
| 11 | Features page contradicts the changelog | `/features` | "3D Scenes ... Absent: a GPU renderer" and XR "Absent: a WebGL2 renderer", against 0.11.4 and `spec-status.json`; XR and terminal not marked paid | Regenerate from `spec-status.json`; mark paid targets | site look (marketing page) |
| 12 | Studio page contradicts itself and PARITY.md | `/studio` | Pro "adds ... reusable components, revision history" while free Studio lists both as built; "All ten sections" with 13 screens | Make the free/Pro split match PARITY.md | site look |
| 13 | Old version numbers | `/`, `/docs`, `/vs/pocketbase` | "dartvel_dev 0.11.5 is on pub.dev", "0.11.5 current version", "Dartvel 0.11.5 ships 24 spec sections", "(v0.11.5) are Linux only", "Maturity ... v0.11.5"; "6 packages" (7 now) | Read the version from the package at build time instead of writing it | docs (here) + site look (home) |
| 14 | Homebrew formula pinned to 0.5.0 | tap | The docs say the tap "can be a version behind" | Update the formula on release (`tool/ci/homebrew_formula.dart` exists) | release |

## P2

| # | Gap | Where | Evidence | Fix | Owner |
|---|---|---|---|---|---|
| 15 | Studio sign-in form | `/__studio/login` | Email and password `autocomplete="off"` in Flutter; each label drawn twice (caption above and floating label inside); no heading in the Flutter view; shows the package name "Studio · dartvel_site"; no "forgot password" | Autocomplete `username`/`current-password`, one label, an h1, a readable project name, a reset flow | Studio (the server HTML now carries the right autocomplete, PR above) |
| 16 | A sitemap page is a 200 stub | `/docs/platform` | "This page moved", canonical to itself, listed in `sitemap.xml` | 301 to `/docs/native-access`, drop from the sitemap | docs (here) |
| 17 | Home says there is no hosted build service | `/` "Coming from Expo" | "There is no hosted build service and no certificate management" while `/cloud` sells one ("not open yet") | "Dartvel Cloud builds are coming", link `/cloud` | site look |
| 18 | Logs report pages as 404 | server log | Every page request logs `GET /docs/deploying 404` (118 for `/` in a day) while the reader gets 200; `/docs/search` "404"s are these | The API layer must not log a request it hands on to the page renderer | framework |
| 19 | Docs table of contents entries with inline code have no name | `/docs` "Run it with `dartvel dev`" | Semantics node with an empty label | Pass the plain text as the label | framework |
| 20 | 0.12.1's change is barely documented | `/docs/models`, `/docs/database` | Two paragraphs on field defaults went live with 0.12.1 | An "Adding a field" section with an example and the migration behaviour | docs |
| 21 | A docs page for unbuilt work is in the sitemap | `/docs/existing-native-apps` | "Native host artifact generation and typed host APIs are planned" | Badge as Planned, keep out of the sitemap until built | docs |
| 22 | A normal page cannot carry request-time data in its server HTML | framework | Only model pages render request data on the server; any other page's HTML is what the build captured | A per-route data hook the web-server render path calls, the same one for `web` prerender | framework (lower priority, owner's lead asked to record it) |

## P3

| # | Gap | Where | Evidence | Fix | Owner |
|---|---|---|---|---|---|
| 23 | No-JS page is bare and navigation-first | every page with scripting off | About 60 nav links before the h1, no skip link; "Search the site" and "Copy code" are inert `<strong role=button>` | Main content first (or a skip link); leave out controls that need script | framework |
| 24 | SEO details | site | No `<lastmod>`, every priority 0.5; one shared `og:image`; `www.dartvel.dev` answers 200 instead of 301; `/favicon.ico` and `/llms.txt` 404 | lastmod from the build, per-page social cards, www 301, favicon and llms.txt routes | framework (sitemap/llms) + hosting |
| 25 | Studio login file names a missing page | `~/.config/dartvel-site-studio.txt` | Says sign in at `/login` (404) | Point at `/__studio/login` | ops |

## Missing basics against vercel.com, flutter.dev and laravel.com

| Basic | dartvel.dev | Note |
|---|---|---|
| Site search | Was broken, now works | #1 |
| Version selector for docs | Absent | laravel.com and flutter.dev both have one |
| "Edit this page on GitHub" | Absent | all three have it |
| Previous / next | Present | |
| Breadcrumbs | Partial (section label only) | |
| On this page | Present | |
| Copy button on code | Present, with tooltip | |
| Dark-mode toggle | Absent (follows the system) | vercel.com has one |
| Changelog / release notes page | Absent (`/changelog` 404) | laravel.com/docs/releases, flutter.dev release notes |
| API reference | Absent (pub.dev docs not linked) | api.flutter.dev, laravel.com/api |
| Community (Discord, forum) | Absent | GitHub, pub.dev, npm present |
| Status page | Absent | vercel-status.com |
| 404 page in the site layout | Absent | #10 |
| Per-page social card | Absent | #24 |

URLs people try that answer 404: `/blog`, `/changelog`, `/pricing`,
`/docs/getting-started`, `/docs/installation`, `/docs/install`, `/community`,
`/search`, `/status`, `/login`, `/docs/changelog`, `/docs/api`, `/vs/flutterflow`.
The cheapest win is redirects for the docs guesses (`/docs/getting-started`,
`/docs/install*` to `/docs`, `/pricing` to `/cloud`) through `dartvel.redirects`.

What checked out: no horizontal overflow at 390 or 1440 px in either theme on
the 11 pages tried, no console errors, text selection and copy work, every
docs page's text is findable with Ctrl+F, tooltips show on icon buttons, every
sitemap route answers 200 with a unique title, a description and one h1, and
all internal links answer 200.

## Studio basics (list only; Studio parity is owned on `agent/dv-studio-parity`)

Not signed in for this walk (the stored login has no password), so this is the
sign-in screen plus source and `docs/studio/PARITY.md`.

- Missing entirely: multiplayer cursors and presence; comments and pins;
  component variants; constraints; styles and design tokens; vector and pen
  tools; prototype flows, interactions and scroll effects; forms on the page
  palette; a plugin marketplace; an app lifecycle editor and governance tools
  (Power Apps).
- Partial: drag and drop (tap to insert only); auto-layout hugging and filling;
  breakpoints (device switcher, no breakpoint rails); asset library; CMS
  collections bound to page lists; page workflows and a condition builder;
  a privacy-rule editor (Bubble); roles (grants by address, no role editor);
  environments; SEO panel (title only); page settings; logs and a debugger;
  connectors; content review.
- Present: undo/redo, components with properties, version history,
  publish/deploy, the GitHub pull request flow.
- Accessibility on the sign-in: see #15. Tab order there is right (Email,
  Password, then the eye, then Sign in).

## The visible first frame (#2), what it needs

The owner's rule is that every page is a real, visible, selectable,
keyboard-navigable document from the first frame, and Flutter takes over in
place without a flash or a jump. Today the server sends that document and
hides it: on screen it is a 1 px clipped box, each section is
`hidden="until-found"` (so neither Tab nor a screen reader reaches it), and the
splash covers the screen until Flutter paints. What it takes:

1. Show `.dv-fallback` on screen until `flutter-first-frame`, in the app's
   theme: the build knows the theme's colours and fonts (the splash already
   carries the background), so `page_text.dart` can emit the document's
   stylesheet from them instead of the fixed reading column. The splash stops
   covering a page that has a document.
2. Drop `hidden="until-found"` until the handover, so the document is
   focusable and read by screen readers while it is the page; put it back when
   Flutter takes over (find-in-page keeps working as it does now).
3. Hand over in place: on the first frame, keep the scroll position and the
   focused element's identity (by the same `data-dv-field` and anchor ids the
   document now carries), then switch the document to the clipped mode. Form
   fields already carry what was typed across (password reveal PR).
4. Layout match, to avoid a jump: the document has to lay out close to what
   Flutter draws (same column width, same type scale, same header height),
   which needs the app's layout metrics at build time. Without it the switch
   is a visible re-layout, which is still far better than a 4 to 6 second
   splash.
5. Tests: a page check that the document is visible and focusable before the
   first frame, and the handover keeps scroll and focus; the existing
   `find_in_page_check.dart` and `server_pages_check.dart` keep passing.

Steps 1 and 2 are generic and contained (`page_text.dart`, the splash, the
find-in-page script); step 3 builds on the field takeover; step 4 is the
expensive part.
