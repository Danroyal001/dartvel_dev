# Flutter web: what Dartvel solves, and what is left

Status as of 2026-09-28, after 0.7.0. Flutter draws a web page on a canvas,
so a great deal of what a browser does for an ordinary page does nothing on a
Flutter one. Dartvel has been closing that gap one behaviour at a time. This
page lists what is done, and ranks what is left by value to real users times
feasibility, with the approach for each.

"Done" means shipped in the page shell or the build, with tests. "Partial"
means some of it works and the rest is named. "Missing" means nothing yet.

## Already solved

| Behaviour | Status | Where |
|---|---|---|
| Crawlers read each page (SEO, `<noscript>` parity) | Done | `page_text.dart`, `crawler_text_check.dart` |
| Per-route `<title>`, description, Open Graph, hreflang, sitemap | Done | `seo_head.dart`, `static_seo.dart` |
| Ctrl+F / Find in page reaches the canvas | Done (Chromium, Firefox 139+; Safari unchecked) | `find/`, `find_in_page_check.dart` |
| Esc from the page reaches the browser (closes the find bar) | Done (0.7.1) | `accessibility/page_escape.dart` |
| Text selection and copy on every page | Done | `DVPageShell` `SelectionArea` |
| Right-click menu on text and links, with a way to the browser's own | Done | `_selectionMenu`, `widgets/browser_menu*.dart` |
| Links: middle-click, Ctrl/Cmd-click, open in new tab, keyboard focus | Done | `routing/nav_link.dart`, `link_interception.dart` |
| Link previews on hover and long press | Done | `DVNavLink` preview |
| Preloading a route before the click (hover, viewport, eager) | Done | `route_prefetch*.dart` |
| Keyboard scrolling, TV remote D-pad, switch control | Done | `accessibility/` |
| Printing (Ctrl+P prints the page text, not a bitmap) | Done | `dvFallbackCss` `@media print` |
| PWA manifest, service worker, install prompt, offline sync | Done | `pwa/`, `pwa_service_worker.dart` |
| Deferred loading per page | Done | `client_generator.dart` (`deferred as`) |
| Accessibility with screen readers (semantics, heading levels) | Done for headings, labels, links; landmarks partial | `DVModifier.semanticHeading` |

## What is left, ranked

Value is how many real users hit it and how much it hurts; feasibility is how
much of it Dartvel can do from where it sits (page shell, build, web glue)
without an engine change. Effort: S under a day, M a few days, L a week or
more.

| # | Pain point | Status | Approach | Effort |
|---|---|---|---|---|
| 1 | **Links to a heading (`/docs/ui#layouts`)** | Missing in the framework (dartvel.dev hand-rolls it) | The page shell already enumerates every heading for find. Give each one a slug id, scroll to `#slug` on load and on a same-page hash change, and write the same `id`s into the build's HTML so the link works for crawlers and before boot. | S-M |
| 2 | **Password managers and autofill on sign-in and sign-up** | Partial: hints on sign-up only, no form grouping, nothing saved | Put the prebuilt auth forms' fields in one `AutofillGroup` with username/password hints, submit on Enter, and call `TextInput.finishAutofillContext()` only after the server accepts, so the browser offers to save the password that worked and fills it next time. | S |
| 3 | Scroll position on Back/Forward and reload | Missing | Record each Scrollable's offset in `history.state` (web) / page storage keyed by history entry; restore when that entry is shown again, after the page has laid out. | M |
| 4 | First paint: real text before the engine boots (LCP, CLS) | Partial: the build writes the page text but hides it | Show the build's semantic HTML as a styled skeleton until Flutter's first frame, then hand over. LCP becomes the text, not the splash image. | M |
| 5 | Browser translation (Chrome, Edge, Google Translate) | Missing | Keep the mirror translatable, watch it for translated text (`MutationObserver`, `<html class="translated-*">`), and feed translated paragraphs back to the page's `RenderParagraph`s by anchor. | L |
| 6 | Hover status bar (href preview), native drag of a link to a tab | Partial: previews are Dartvel's own | While a pointer is over a `DVNavLink`, place a real `<a href>` at its rect in the DOM. The browser then shows the URL, drags it, and offers its own link menu; clicks still go through `link_interception.dart`. | M |
| 7 | Forced colours / high contrast | Partial: Flutter reports it, Dartvel's themes ignore it | Map `MediaQuery.highContrastOf` and `forced-colors` to a high-contrast `DVTheme` variant and system colours for focus rings. | S-M |
| 8 | OG image per route | Partial: one image per site or per model page | The build already renders every route in Chrome; save a 1200x630 capture per route and point `og:image` at it. | M |
| 9 | Selection: Share and "Search the web" | Missing | Two more items in the page's selection menu: `navigator.share` where it exists, and a search URL with the selected text. | S |
| 10 | Screen reader landmarks and live regions | Partial | Page shell regions (`header`, `main`, `nav`) as semantics roles, and `DV.Notifications` in-app messages as polite live regions. | S-M |
| 11 | OS text size and browser zoom | Partial: browser zoom works; OS text size on Android Chrome not verified | Verify `textScaler` follows the root font size; honour it in `DVText` defaults. | S |
| 12 | RTL and `<html lang dir>` per locale | Partial: hreflang done | Set `lang`/`dir` on `<html>` from the active locale at build and at runtime. | S |
| 13 | Spellcheck underlines in text fields | Missing (engine) | Flutter web edits in a real `<input>` but draws the text itself; needs the engine's spell-check API on web. Track upstream. | L |
| 14 | Paste of images/rich content, drag files in and out | Partial (`platform/drag_drop.dart`) | Web: `paste` and `drop` listeners on the view feeding `DV.FileStorage` picks; drag-out via a `DownloadURL` drag image. | M |
| 15 | Wasm (skwasm) by default | Partial: served correctly, not the default | Make `dartvel build web --wasm` the default once every Dartvel web binding is `dart:js_interop`-clean; keep the JS fallback. | M |
| 16 | Memory on low-end phones | Unmeasured | Measure on a 2 GB Android; image cache limits by device memory (`navigator.deviceMemory`). | M |
| 17 | Analytics without jank | Done for consent; batching unverified | Send on `visibilitychange` with `sendBeacon`, never on the frame. | S |

IME and composition for CJK and Android keyboards are Flutter's own and work
through its text input; Dartvel's job is not to take keys from it, which the
Esc fix covers. Open in new tab and per-route titles are done.

## Built after this list

Items 1 and 2 are built for the next release: heading links, and password
managers on the prebuilt auth pages. Each has a section on dartvel.dev with a
live demo.
