# Find in Page — Proposal

**Status: Draft 2026-09-25, not yet reviewed.** On approval this becomes a
section of NEW_SPEC.md beside SEO and PWA, with `Stability: Draft` and
`Status: Planned` in `docs/spec-status.json` until the files that prove it
exist.

Pressing Ctrl+F (Cmd+F) on a Dartvel web page finds nothing. The browser's
find bar searches the document, and a Flutter page is a canvas: the words a
reader can see are not in the document. On a phone, "Find in page" from the
browser menu fails the same way, and there is no keyboard shortcut to
intercept. This is [flutter/flutter#65504](https://github.com/flutter/flutter/issues/65504),
open since 2020 with several hundred reactions, and it is the complaint that
keeps Flutter web on admin panels rather than on documents.

It matters more to Dartvel than to Flutter in general, because Dartvel is
URL-first and ships documents: the site, its spec index, its CLI reference,
and every application's model pages. A reader who cannot find a word on a
docs page concludes the site is broken, not that the renderer is a canvas.

---

## Where Flutter is, as of this week

The premise that Flutter will not prioritise this is out of date. On
2026-09-24 the issue moved from P3 to **P1** and was self-assigned on the
framework team. Two artefacts back it:

- [RFC 170 (flutter/rfc#25)](https://github.com/flutter/rfc/pull/25) —
  *Pluggable App-Level Find-in-Page on SelectableRegion & SelectionArea*:
  a `FindInPageController`, a `FindInPageScope`, `SelectableRegion.findOnly`,
  search highlight colours on `DefaultSelectionStyle`, and a "scanner mode" on
  `RenderViewport` for content that is scrolled away.
- [flutter/flutter#193186](https://github.com/flutter/flutter/pull/193186) —
  the draft prototype, described by its author as an agent-driven experiment,
  with a public WebAssembly demo.

Both are in-app find: Flutter draws the find bar and the highlights. Neither
makes the **browser's** find reach the page, and the RFC does not claim to.
That settles the split:

1. Dartvel does not build a rival framework-level find controller. It puts a
   thin, stable surface in front of one, implements it itself today, and moves
   onto `FindInPageController` when that lands. Application code does not
   change on the day it does.
2. Dartvel builds the part Flutter cannot, because Dartvel already has the
   ingredient: **a copy of the page's text in the document.**

---

## What Dartvel already has

Three existing pieces carry most of this:

- **The page-text block.** `dvApplyPageText` / `dvApplyPageHtml`
  (`packages/dartvel_core/lib/src/web/page_text.dart`) write each route's text
  into the served HTML as real semantic HTML — headings, paragraphs, links,
  code — inside `.dv-fallback`. The capture step renders the page in Chrome so
  the words come from the page and not from string literals. Today the block
  is `display:none`, shown only to no-script readers and printers.
- **Its lifecycle.** `_dropStaleFallback`
  (`packages/dartvel_flutter/lib/src/seo_platform_web.dart`) removes the block
  once the reader routes off the page it was written for, so it is correct for
  exactly one page.
- **A SelectionArea on every page.** `DVPage` wraps its body in a
  `SelectionArea` unless the page opts out (`selectable: true` by default) or a
  kiosk policy forbids selection. That is the same registrar Flutter's RFC
  builds find on, so Dartvel pages are ready for it without any change.

`display:none` is why the browser's find skips the block. Content that is
`display:none` or `visibility:hidden` is not searchable. Content marked
`hidden="until-found"` is.

---

## 1. The browser's own find reaches the page (web)

**Problem.** The find bar a reader already knows, on desktop and on mobile,
finds nothing, and intercepting Ctrl+F only covers desktop keyboards. It also
overrides a browser feature people rely on, which the #65504 thread calls out
as bad practice.

**Proposal.** Keep a searchable copy of the current page's text in the
document and send the browser's matches to Flutter.

- **Findable, not visible.** The page-text block's sections are emitted as
  `hidden="until-found"` elements rather than under `display:none`. The browser
  searches them, counts them and cycles through them like any other text. Each
  section carries `data-dv-anchor`, identifying the paragraph or semantic node
  it mirrors.
- **The browser says what it found.** When a match lands in a hidden section,
  the browser fires `beforematch` on that element before revealing it.
  Dartvel's web runtime handles the event, looks up the anchor, and
  `DV.Navigation` scrolls the Flutter page to that paragraph with
  `Scrollable.ensureVisible`. It then highlights the paragraph through the
  page's `SelectionArea` highlight. The mirror element is set back to
  `until-found` on the next task, so it never paints over the canvas. The
  mirror lives in a zero-size, clipped, `aria-hidden` container, so the
  browser's own scroll to it is invisible, and assistive tech reads the
  semantics tree as it does today rather than reading the page twice.
- **It follows the reader.** The block stops being a one-page artefact.
  Instead of `_dropStaleFallback` removing it after the first navigation, the
  runtime rewrites the mirror on every route change and every settled content
  change (debounced after the frame). It takes the text from the page's
  `SelectionArea`, whose registrar already knows every `RenderParagraph` on the
  page. The build-time block still covers the first paint, crawlers,
  no-script readers and printing, so none of that regresses. The print rules
  move with the mirror, which also fixes today's "printing after a navigation
  falls back to the canvas".
- **Mobile works.** "Find in page" on Chrome for Android uses the same
  mechanism. There is no keyboard shortcut to intercept, and nothing is
  intercepted: this is the case the thread said a custom search bar cannot
  solve.

**What it cannot do, stated up front:**

- `beforematch` names the element, not the query or the offset. Dartvel knows
  *which paragraph* matched, not *which word*. The reader gets scrolled to and
  shown the paragraph, not the exact word. The browser's own highlight is on
  the hidden mirror. Section 2's find bar is the answer when exact-word
  highlighting matters.
- Support. `hidden="until-found"` and `beforematch` are in Chromium and in
  recent Firefox. Safari support has to be checked in the prototype before this
  section is written into the spec. Where either is missing, the page behaves
  as it does today, and section 2 takes Ctrl+F.
- The mirror is as complete as the text Dartvel knows about. Section 3 covers
  what the page has not built yet.

**Privacy.** The mirror puts the text of the page in front of the reader into
the DOM: text that is already on their screen and, with semantics enabled,
already in the DOM through Flutter's semantics tree. It writes nothing for a
guarded route that the build-time block does not already exclude, and a page
can opt out with `findable: false` (below) for content that should never be in
the DOM at all.

## 2. An in-app find bar (every platform)

**Problem.** Native desktop and mobile builds have no browser find. Web
browsers without `until-found` have none that works. Some pages want real
per-word highlighting.

**Proposal.** The page shell carries a find bar, scoped to the page's
`SelectionArea`, the way it already carries keyboard scrolling, a remote's
D-pad and switch control: inert until it is asked for, and nothing an
application places or has to remember. There is no find-bar widget to add,
because a page that is findable only when somebody wrapped it is unfindable
on the days they forget.

```dart
// sketch
DVPage(
  findable: false,                   // opt out; the default is true, beside selectable
  child: ...,
);

DV.Find.open(query: 'retention');    // programmatic, for a page's own search action
DV.Find.results;                     // a signal: count, current, matches
DV.Find.keys = DVFindKeys.always;    // app-style products; see below
```

- **Keys.** On native desktop builds, Ctrl/Cmd+F opens the bar. On web, Ctrl+F
  is **not** intercepted where section 1 works, because the browser's find is
  what the reader asked for. Where it does not work, the bar takes Ctrl+F. An
  application can set `DV.Find.keys` to `DVFindKeys.always` for an app-style
  product (a mail client, a chat), which is what Gmail and Slack do.
- **Engine.** Until Flutter ships one, Dartvel implements matching and
  highlighting over the `SelectionArea` registrar: the same `RenderParagraph`
  set, and highlights drawn as selection-style rects in the theme's search
  colour. When `FindInPageController` lands, `DV.Find` becomes a facade over it
  and Dartvel's own engine is deleted. `findable` maps onto
  `SelectableRegion.findOnly`, which is also how a kiosk page with
  `textSelection: disabled` stays findable without becoming selectable.
- **Mobile.** No keyboard, so the bar is opened from the page's app bar action
  or the context menu `DVPage` already builds (`_selectionMenu`).

## 3. Text the page has not built

**Problem.** A `ListView.builder` builds only the rows near the viewport. A
mirror or a find bar that reads rendered paragraphs misses every row that was
never built, which is the "even when scrolled off screen" in the title of
#65504.

**Proposal.** Generated lists know their data. A `DVRecordTable` (and the
admin tables built on it) registers each record's text fields — the
`@DVModel.searchableField()`s where the model declares them — with the page's
find scope from the records it already holds, not from rendered rows. It also registers an index-to-offset mapping, so a match on an unbuilt
row scrolls to that index and then highlights once the row builds. This is the
approach [`find_in_page`](https://pub.dev/packages/find_in_page) takes with
`FindableListView`, and the same constraint applies: exact scrolling needs a
known or estimated item extent. Records a list has not fetched are not
searched. Searching the data is `Model.search(...)`'s job, and the find bar
offers it ("Search all tickets…") when the model is `@DVModel(searchable: true)`.

Arbitrary hand-written `ListView.builder`s get what Flutter's viewport
"scanner mode" gives them when it lands, and nothing before that.

---

## The Dartvel site goes first

`sites/dartvel_site` is built from `DVPage`s, so it gets sections 1 and 2
without page changes. Its long documents — the spec index, the CLI
reference, the feature pages — are where the lack of find hurts most, which
makes it the adopter that proves the design. The `runtime-verification`
workflow's web job gains a check. On a docs route, `window.find()` in Chrome
for a phrase below the fold must fire `beforematch` on the mirror. After that,
the Flutter page's scroll offset must place the matching paragraph on screen.
Whether `window.find()` exercises `until-found` the way the find bar does is
the first thing the prototype has to establish.

## Drafting order

1. **Prototype section 1 on the site:** `until-found` sections, `beforematch`
   to scroll and highlight, a runtime mirror from the `SelectionArea`. Measure
   the mirror's cost on the longest docs page, and check browser support,
   Safari included.
2. **Spec text and `spec-status.json` entry.** `Draft` / `Planned`, promoted as
   files land.
3. **Section 2**, behind `DV.Find`, with its own engine.
4. **Section 3** for generated model lists.
5. **Swap `DV.Find` onto `FindInPageController`** when RFC 170 merges. Delete
   Dartvel's engine.

## Open questions

- Exact-word highlight from a browser match. Is there a reliable signal (the
  selection after the find bar closes, a scroll-position heuristic as in the
  #65504 thread's experiments) worth using, or is the paragraph the right
  granularity?
- Mirror size on very large pages. Should there be a cap, and what does the
  reader see when it is hit?
- Whether to contribute section 1 upstream. It depends on a copy of the text
  in the document, which Flutter web does not keep and Dartvel does. The RFC is
  the place to ask whether the engine's semantics DOM could carry it instead.
