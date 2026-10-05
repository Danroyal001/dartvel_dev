# Studio parity: Figma, Webflow, Bubble, Power Apps

**What this file is.** A feature-by-feature comparison of Dartvel Studio against the four
tools it is measured by, with the evidence for every verdict. It exists because the honest
answer to "how far along is Studio?" is a list, not a sentence.

**How to read a verdict.**

| Verdict | Meaning |
| --- | --- |
| **Done** | Usable today in free Studio, from a browser, on a build from this repository. The evidence names the file that carries it. |
| **Partial** | Something real exists and something real is missing. The missing half is named in the same row. |
| **Missing** | Nothing. No file, no screen, no partial. |

"Partial" is the common verdict on purpose. A row that reads Done means somebody can do
the thing, not that it works the way the tool it is compared to does it.

**Evidence.** Every row names a Dart source file under `packages/`, or a screenshot under
`docs/studio/`. A row with no file is a row that is not built. Claims here are checked
against the source, not against a demo, and a screenshot is only evidence for the screen
it shows.

**What "free Studio" means.** Studio is free: it ships in
every `web-server` binary with no cloud account. Features marked *Pro* are not in this
repository and are not counted as Done anywhere below.

**Scope.** Free Studio as served by `dartvel build web-server`. Not counted: Studio Pro
(Figma import, team review transport, enterprise SSO), and the in-application
`dartvel admin generate` build, which mounts the same sections without the server.

---

## The honest summary

Free Studio today is **a page builder that draws the real page**, plus a **data and
backend surface for the project**, plus **access control for people who may use it**. It
is not a design tool, it is not a visual site builder in the Webflow sense, and it is not
an application platform in the Bubble or Power Apps sense.

Concretely, the four biggest gaps against these tools:

1. **No visual design primitives** the way Figma has them: no auto-layout inspector with
   per-side padding and margin readouts, no constraint solver, no components with typed
   variants and properties bound to a component set, no prototyping links, no design
   tokens or styleguide management, no Figma import.
2. **No responsive design surface**: breakpoints exist in the document model and a device
   switcher changes the artboard width, but there are no breakpoint rails, no per-breakpoint
   container behaviour, and no way to see two widths side by side.
3. **No collaboration**: no presence, no cursors, no comments on a canvas, no live
   multiplayer. The review workflow exists (draft, review, approved, scheduled, published)
   but it is a state machine, not a conversation.
4. **No no-code logic surface that is not code-shaped**: workflows are built from steps
   (that part is real), but there is no visual condition builder over page data, no
   reusable rules library, no scheduled triggers UI beyond a publish slot.

The pages Studio builds are **Dartvel pages**, which is a deliberate difference and not a
gap: what comes out is a real Flutter widget tree, runs on every platform Dartvel targets,
and is readable and editable as source. The cost is that Studio cannot offer anything the
Dartvel widget set does not already have.

Two foundations have improved. Studio used to be a second Flutter application,
served as files under the mount, with no URL for any screen but the mount itself and an
empty `<body>` the app painted over. It is now routes of the application, on the same render
path as every public page, each with its own address and a document behind it, described in
[A URL for every screen](#a-url-for-every-screen-and-what-it-is-read-by).

And Studio's own controls used to be pictures of controls: a `GestureDetector` around a
`Container`, which a mouse can press and nothing else — Tab skipped every button, Enter and
Space did nothing, and a screen reader heard the words on a control without ever being told
it was one. Shared controls now carry keyboard and semantic behaviour
(`DVStudioIconButton`, `DVStudioControl`, `DVStudioSwitch`). Coverage of those widgets
and the main screens does not prove every editor, dialog or setup step accessible.
Full accessibility remains **Partial** until those flows are verified too.

---

## Against Figma

| Figma feature | Studio | Evidence |
| --- | --- | --- |
| Visual canvas with direct manipulation | **Done** | `packages/dartvel_flutter/lib/src/studio/studio_editor.dart`, `studio_screen.dart:1887` (workspace, artboard, viewport controls at `:2431`) |
| Drag from a palette into the canvas | **Partial** — insert by tapping a palette entry or the command palette; there is no drag-and-drop gesture | `studio_screen.dart` `_leftColumn` `:2228`; `studio_operations.dart` `dvStudioShortcuts` |
| Layer tree with nesting, rename, reorder | **Done** | `studio_screen.dart` layers panel, `studio_editor.dart` node tree helpers |
| Select on canvas, edit properties in an inspector | **Done** | `studio_screen.dart` right pane `_paneBar` `:2002`, formula bar `studio_formula_bar.dart` |
| Undo / redo | **Done** | `studio_editor.dart:24` (`_undo`/`_redo`), `:265` `undo()`, `:274` `redo()` |
| Multiplayer cursors and presence | **Missing** | no presence code in `packages/dartvel_flutter/lib/src/studio/` |
| Comments and pins on the canvas | **Missing** | no comment or pin model in the editor |
| Components / libraries with instances | **Done** — components with props, `Ctrl+Alt+K` to make one from a selection | `studio_components.dart`, `studio_components_section.dart`, screenshot `docs/studio/nocode/components.png` |
| Component variants (boolean, enum, instance-swap properties) | **Missing** — props exist, variant sets do not | `studio_components.dart:47` `DVStudioComponentProp` (text, picture, colour, action only) |
| Auto layout (Figma's own algorithm, per-side padding/gap, wrap, alignment matrix) | **Partial** — Flutter's flex/grid/wrap/stack layouts with padding, gap, alignment, aspect ratio, on a per-node property chain; Figma-style *auto*-sizing and hugging/filling rules are not modelled | `packages/dartvel_flutter/lib/src/studio/page_document.dart:1424` `dvStudioLayouts`, `dvStudioNodeProperties` |
| Constraints (left/right, scale, centre) | **Missing** — no constraint fields in the node property map | `page_document.dart` node properties |
| Styles, stylesheets, styleguide, design tokens | **Missing** — no style table in the document model | `page_document.dart` |
| Grid and layout views, section/frame containers | **Partial** — a `grid` layout and a `wrap` exist as node layouts; no layout-grid, no section container, no component set | `page_document.dart:1424` |
| Responsive design (breakpoint rails, per-breakpoint overrides) | **Partial** — `DVBreakpoint` values `mobile/tablet/desktop/wide` with per-node property overrides exist and export to Dart; the editor has a device switcher (Desktop 1280, Tablet 834, Phone 390), not breakpoint rails | `packages/dartvel_flutter/lib/dartvel_flutter.dart:5058` `DVBreakpoint`, `studio_screen.dart:469` `_DVStudioDevice`, `page_document.dart:71` |
| Prototype flows, smart animate, overlays | **Missing** — a node action can navigate (`action.type == 'navigate'`, `page_document.dart:581`), which is a link, not a prototype | `page_document.dart:174`, `:581` |
| Interactions and animations | **Missing** | no animation fields in the node model |
| Vector editing, pen tool, booleans | **Missing** | no vector node type; the palette has Text, Image, Button, Spacer, Divider (`page_document.dart:890` `dvStudioLeafTypes`) |
| Placeholder images, unsplash, assets panel | **Partial** — image source goes through `DVImage`'s reader (`page_document.dart:908`), so assets and URLs work; there is no asset browser or stock library in Studio | `page_document.dart:902` |
| Export to code | **Done** — every node type carries `source`, and a page exports as a `@DVPage` Dart file | `page_document.dart:890` (`source:` on each leaf), `studio_editor.dart` export |
| Import from Figma | **Missing in free Studio** (Studio Pro) | not in this repository |
| Dev mode / inspect a live page | **Partial** — the captured structure of a compiled page is opened in the editor (`studio_structure`), which is a tree, not Figma's inspect mode | `packages/dartvel_core/lib/src/admin/studio_site.dart:170` `dvStudioPageContentIn` |
| Version history and restore | **Done** — numbered versions, compare, restore | `studio_review.dart`, screenshot list in `dartvel capture studio` gallery |

## Against Webflow

| Webflow feature | Studio | Evidence |
| --- | --- | --- |
| Visual site builder with boxes | **Done** | `studio_editor.dart`, `page_document.dart:1424` |
| Box model: margin, padding, sizing, per-side borders, radius | **Partial** — padding, gap, alignment, sizing, radius, background, border sides are in the node property chain (`page_document.dart:1444` border sides); numeric per-side padding and margin fields are now present; linked-edge presets and the broader box-model design surface remain partial | `page_document.dart` node properties, `studio_formula.dart` |
| Flexbox and Grid | **Done** — row, column, wrap, grid, stack as node layouts, exported as Flutter layouts | `page_document.dart:1424` |
| Breakpoints and responsive design mode | **Partial** — device switcher and per-node breakpoint overrides, but no breakpoint rails, no separate breakpoint canvases, no element-visibility-per-breakpoint UI | `studio_screen.dart:469`, `dartvel_flutter.dart:5058` |
| Reusable components (symbols) with fields | **Done** — components with props and an Insert panel | `studio_components_section.dart`, screenshot `docs/studio/nocode/insert-panel-components.png` |
| CMS: collections bound to page lists | **Partial** — data models and records exist (`DVStudioModelsSection`, records through the API), and the formula bar completes model fields, but a page cannot be bound to a collection as a repeater/list from Studio | `studio_server.dart:975` `dvStudioDataSection`, `studio_formula.dart:425` |
| Interactions and animations | **Missing** | no animation model in the document |
| Interactions: scroll-triggered effects | **Missing** | — |
| SEO per page | **Partial** — a Studio page carries a route and a title, and the title becomes the route's title and its `<title>` (`page_document.dart:363` `DVPageDocument`). There is **no description, no social image, no SEO panel with a preview**, and no robots or sitemap UI in Studio; the framework's `DVRoutePage` carries all of them (`packages/dartvel_core/lib/src/web/route_page.dart:132`), but nothing in Studio sets them for a page a person built | `page_document.dart:363`, `route_page.dart:132` |
| Hosting and publishing | **Done, and different** — Studio publishes into *your own* web-server binary; there is no Dartvel-hosted site. Deploy is in the editor toolbar with a platform menu | `studio_screen.dart` `_actions` `:2499`, `studio_server.dart` |
| Custom code (embeds, before/after) | **Partial** — a page made in Studio exports as Dart source you can edit; there is no embed block in the palette | `page_document.dart:890` |
| Interactions with forms and submissions | **Missing** — there is a form widget in Dartvel (`DVForm<T>` from a data model) but Studio's palette has no way to add or configure one | palette list `page_document.dart:890` |
| Site map and page settings | **Partial** — the Site map section lists every compiled and stored route and opens one in the editor; a page's route and title are editable on the canvas. There is **no page-settings panel**: no description, no image, no social card, no unpublish | `studio_server.dart:984` `dvStudioSiteMapSection`, `page_document.dart:363`, `studio_screen.dart:1159` `_overview` |
| Multi-page templates, symbol pages | **Partial** — components are page fragments, not whole-page templates | `studio_components.dart` |

## Against Bubble

| Bubble feature | Studio | Evidence |
| --- | --- | --- |
| Data types with fields and types | **Done** — the model designer writes a model and its fields, with types, validation and defaults | `studio_model_designer.dart`, `packages/dartvel_core/lib/src/admin/studio_model_schema.dart` |
| Records: list, create, edit, delete | **Done** — records through `DVStudioApi`, with versioning and conflict detection | `packages/dartvel_core/lib/src/admin/studio_api.dart:712` `_models`/`_recordsOf`, `model_data_api.dart` |
| Privacy rules per field and per action | **Partial** — authorization exists in the framework (`DV.Auth.authorization`, `@DVModel.sensitiveField()`), and every Studio write goes through the API, but there is **no privacy-rule editor in Studio** | `packages/dartvel_core/lib/src/auth/`, no privacy UI in `packages/dartvel_flutter/lib/src/studio/` |
| Workflows: visual trigger/action steps | **Done, for backend functions** — the function builder is a step list with runs, conditions and variables, saved server-side | `packages/dartvel_flutter/lib/src/studio/functions/functions.dart`, `studio_server.dart:906` `dvStudioServerSections`, `dvFunctionStudioSections` |
| Page workflows (on page load, button action chains) | **Partial** — a node's action is a navigation; there is no page-load workflow editor or chained action list | `page_document.dart:174`, `:581` |
| Roles and permissions in the UI | **Partial** — the Team section grants and lists access by address, but there is no role editor with per-action permissions | `studio_server.dart:966` (`access` → "Team") |
| Responsive and mobile preview | **Partial** — device switcher, and Dartvel pages are responsive Flutter layouts; no mobile preview UI of its own | `studio_screen.dart:469` |
| API connector (Bubble calls outside services) | **Partial** — there is no visual API connector; Dartvel's backend functions, written in Dart or built as workflows, and the page client is generated | `packages/dartvel_cli/lib/src/generators/backend_generator.dart` |
| Plugins and marketplace | **Missing** — the Modules section only shows text to paste into `pubspec.yaml` | `studio_modules.dart` |
| Debugger / logs | **Partial** — Operations has service levels, alert rules, incidents and a status-page preview; there is no request log or workflow run log viewer | `studio_operations.dart`, `studio_incidents.dart` |
| Scheduled triggers | **Partial** — a publish slot can be scheduled (`studio_review.dart:1468`), and queues and jobs exist, but there is no trigger editor | `studio_review.dart`, `studio_server.dart:932` (Jobs → "Tasks") |
| Version control and deploy | **Done, and different** — writes to the repository and opens a GitHub pull request, and Deploy publishes into the running binary | `studio_repository_section.dart`, `studio_screen.dart:2499` |
| Search index | **Partial** — models have `searchableField()`; there is no search-index configuration screen in Studio | `packages/dartvel_core/lib/src/annotations/annotations.dart` |
| File storage | **Partial** — `DV.FileStorage` exists and image nodes can read through it; Studio has no storage browser | `page_document.dart:908` |

## Against Power Apps

| Power Apps feature | Studio | Evidence |
| --- | --- | --- |
| Data sources connected to an app | **Done** — the project's own database through the generated API; models listed with their records | `studio_server.dart:975`, `studio_api.dart:712` |
| Forms and galleries over that data | **Partial** — a form exists per model (`Model.Form()`) and records are editable in Studio, but Studio has no gallery/form *layout* surface to place them on a page | `packages/dartvel_core/lib/src/annotations/annotations.dart` (`@DVModel`), no form palette entry `page_document.dart:890` |
| Formula bar over selected fields | **Done** — the formula bar edits the selected node's field with typed formulas, completions, validation and Esc to revert | `studio_formula_bar.dart`, `studio_formula.dart`, screenshots `docs/studio/formula-bar.png`, `docs/studio/formula-bar-error.png` |
| Power Fx expressions | **Partial** — a Dart expression evaluator over the field's kind, not the Power Fx language; no user-defined functions or relative references | `studio_formula.dart` |
| Conditions and branching logic | **Partial** — conditions exist in backend function steps; no condition builder for page data | `functions/functions.dart` |
| App lifecycle (Start, Update, Fix data) | **Missing** | no lifecycle editor in Studio |
| Connectors and APIs | **Partial** — backend functions, Dart FFI, and HTTP clients exist in the framework; Studio has no connector gallery | `packages/dartvel_core/lib/src/http/`, `NEW_SPEC.md` |
| Environments (dev/test/prod) | **Partial** — `dartvel dev` writes to the repository and Deploy publishes to the running binary; there is no environment switcher with separate data | `studio_repository_section.dart` |
| Roles and security (per app, per screen) | **Partial** — grants exist (Team); no per-screen or per-field security editor | `studio_server.dart:966` |
| Notifications and approvals | **Partial** — the content workflow has approval states and a publish schedule; `DV.Notifications` exists in the framework, with no Studio screen to configure it | `studio_review.dart`, `packages/dartvel_core/lib/src/notifications/` |
| Governance: solution checker, managed environments | **Missing** | — |
| Keyboard/command shortcuts | **Done** — a Shortcuts section writes an app's keyboard shortcuts without code, plus Figma/Bubble/Power Apps shortcuts on the Ctrl+/ sheet | `studio_app_shortcuts.dart`, `studio_shortcuts` section `studio_screen.dart:186`, screenshot `docs/studio/nocode/shortcuts.png` |
| Accessibility of Studio and its output | **Partial** — shared controls (`DVStudioControl`, `DVStudioIconButton`, `DVStudioSwitch`) provide roles, labels, keyboard activation and focus rings (`studio_style.dart`). The browser probe on a real web-server build (2026-10-02, `docs/studio/evidence/2026-10-02/results.json`) passes all 25 checks with no page errors: keyboard sign-in, Enter submits it, every screen server-rendered, back/forward, deep links, Ctrl+F, Tab, screen-reader buttons, and drag-select-and-copy in the workspace. Fixed for that run: text beside the rail and list panes could not be drag-selected (`DVSelectionColumn`), Space/Enter/arrows/Home/End never reached a text field on any page so no form submitted with Enter (`editing_focus.dart`), and a reshaped selection area crashed a release build on a screen switch (`DVBrowserMenu.nativeMenuOn`). Setup, dialogs, component editing and full assistive-technology flows remain unverified; the row stays Partial. | `studio_style.dart`, `studio_routes.dart`, `selection_column.dart`, `editing_focus.dart`, `test/studio_selection_test.dart`, `test/selection_column_test.dart`, `test/typing_keys_test.dart`, `test/browser_menu_selection_test.dart`, `docs/studio/evidence/2026-10-02/results.json` |

---

## Studio's own screens, and what each is for

| Section | What it does | Verdict against the others |
| --- | --- | --- |
| Pages | Site overview, page list with thumbnails, the canvas editor, layers, insert panel, inspector, formula bar, deploy, review, export | The closest to Figma's canvas and Webflow's builder. Partial. |
| Components | Reusable parts with props, an Insert panel, `Ctrl+Alt+K` | Done for the symbol case; variants missing (Figma) |
| Shortcuts | The app's keyboard shortcuts, without code | Done (Power Apps has none) |
| Data | Models, records, the model designer | Done for Bubble's data types; no privacy-rule editor |
| Site map | Every compiled and stored route | Done |
| Frontend / Backend | Function builders, steps and runs | Done for Bubble workflows on the server; missing for page-level workflows |
| Modules | What to paste into `pubspec.yaml` | Missing (Bubble plugins, Webflow custom code) |
| Tasks | Background jobs from the project graph | Done (list only) |
| Queue / Cache | Queue names and cache entries | Partial |
| GitHub | Diff, pull request or push of the project's `studio/` folder | Not in any of the four; unique to Dartvel |
| Team | Grants by address | Partial (no roles editor) |
| Flags / Operations | Feature flags with rules, service levels, alert rules, incidents, status preview | Not in the four; unique to Dartvel, and real |

### A URL for every screen, and what it is read by

Every screen above is at its own address under the mount: `<mount>` is Pages,
`<mount>/<screen>` is that screen, and `<mount>/<screen>/<object>` opens one
thing inside it. Nothing in the rail is a state of the page it is on, so a
Studio screen can be linked, bookmarked and reloaded, and the browser's Back
button goes back through it. Nothing is a `#fragment`, and nothing is an
application that fetches its own pages from the server.

The client opens a screen by navigating to its address, not by pushing a
route the browser is never told about: `go_router`'s `push` keeps an
imperative match to itself and, by default, leaves the location bar where it
was, which is what made a selection change the body while the address still
read Pages. `_openStudio` navigates (`studio_routes.dart`), so the location
bar follows, each screen and object is a history entry of its own, and Back
returns through them -- checked against the navigation channel in
`packages/dartvel_flutter/test/studio_routes_test.dart` and a report sent the
way the web engine sends it in
`packages/dartvel_flutter/test/studio_selection_test.dart`.

The three cases that are not screens are named too, and what each is for is
said in the document it is served with:

| Address | What it is | Where it comes from |
| --- | --- | --- |
| `<mount>` and `<mount>/pages` | Pages, the first screen | `studio_document.dart` `dvStudioScreens` |
| `<mount>/<screen>` | The screen, with its own heading and the rail | `dvStudioScreenFor`, `dvStudioDocumentFor` |
| `<mount>/<screen>/<object>` | One model, route, function, task, queue or module, named in the document as its `<h1>` | `_objectDocument` |
| `<mount>/login` | Studio's sign-in, for anybody, carrying no project | `dvStudioSignInScreen`, `_noProjectDocument` |
| `<mount>/setup` | The first-run setup, the same | `dvStudioSetupScreen` |
| `<mount>/flags`, `<mount>/operations` | Flags and Operations, **client-side only** | not in `dvStudioScreens`: a server cannot know whether the project declared a flag runtime or an alerting engine, so it never prints a link to them. A project that has them opens them from the address bar | `studio_screen.dart:193`, `:203` |

Every screen is served as the application's own shell rendered by
`dvRenderRoutePage`, like every public page, carrying a document built from
the same data Studio's API reads: names, counts, kinds and field schemas, and
never a record's values or a grant. That is what a printer, a crawler, a
reader with scripting off and the browser's own Ctrl+F read. `flags` and
`operations` have no server-side document for the reason in the row above.

The list of screens and the sections Studio actually puts on its rail are held
to each other by `packages/dartvel_flutter/test/studio_sections_drift_test.dart`,
so a screen cannot be printed by the server and missing from the client, or
appear on the rail with no address.

## How this file stays honest

Studio inherits the application’s effective Material theme. New projects use
`dartvelDefaultTheme(.light)` and `dartvelDefaultTheme(.dark)`, shared with the
Dartvel site, including its bundled Manrope font. Full theme parity is still
partial: Studio’s custom color tokens and the visible server-rendered first
frame have not yet been migrated.

A web-server build of this branch and the browser probe (`docs/studio/evidence/2026-10-02/`, 2 October 2026) pass every check with no page errors: the guarded-mode server documents, keyboard sign-in with Enter, URLs and deep links, back and forward, Ctrl+F, Tab, screen-reader buttons, and drag-select-and-copy. Theme parity is in this build (`18891f15`).

Readable aliases are supported for `/__studio/data`, `/__studio/sitemap` and
`/__studio/team`; existing `/models`, `/routes` and `/access` links remain valid.
`/__studio/data/Product/p-1` opens the record form. Selecting and closing a record
updates its address; a missing model or record is reported instead of silently
opening a different one. Tests: `studio_selection_test.dart` and
`admin_server_test.dart`. Settings do not yet have a dedicated screen hierarchy.

### Next parity slices, in order

1. Finish accessibility and URL coverage for setup, dialogs, new-object forms and
   component editing; verify keyboard, copy, browser history and assistive tree in
   the production server build for each flow.
2. Add a numeric box-model inspector with per-side padding/margin and breakpoint
   overrides. Verify saved values survive reload, export and a narrow viewport.
3. Add data-model galleries and forms to the page palette, with policy-aware data
   binding. Verify a real create/edit flow and denied access in two projects.
4. Add a page condition/action builder over typed data-model fields, then reusable
   component variants. Verify invalid expressions and export/runtime parity.
5. Add comments and review threads before multiplayer cursors or concurrent edits.
   Verify authorization and conflicting writes before calling collaboration Done.

These are proposed slices, not shipped capabilities or commitments to a release date.

Sign-in regression coverage: `test/studio_sign_in_test.dart` now checks Tab
from password followed by Enter, and the password's submit action. The Tab
test failed with the old gesture-only action and passes with
`DVStudioControl`; sign-in fields now expose their labels. This widget test
does not establish browser parity for every Studio control.

- Every verdict names a file. A row without one is not built.
- "Partial" is used whenever part of the feature exists and part does not; the missing half
  is named in the row.
- When a row changes, the change is made here in the same commit as the code, and a
  feature is never described as Done because a demo of it exists.
- The definition of done for anything added here is the one in `~/AGENTS.md`: one render
  path, its own URL, Ctrl+F/selection/Tab/screen reader working, generic for every
  Dartvel project, checked in a real browser on a web-server build, with the docs updated
  in the same change.

### Per-side outer spacing

The numeric inspector now exposes margin on all four edges alongside padding.
A named margin edge overrides the uniform margin; an explicit zero is retained.
The page document, renderer and exported `.marginOnly(...)` use the same values.
Failing-first regression coverage: `studio_margin_edges_test.dart` (three failures
on the preceding implementation), alongside padding and inspector regressions.
Production-browser verification is pending; the broader box-model verdict remains Partial.
