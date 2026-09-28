# Dartvel Studio against Framer, Webflow, Bubble, WordPress admin and Power Apps

Status as of 2026-09-28. Each row is one thing a person does all day in those
tools, what the best of them offers, and where Studio stands. "Built" means
shipped with tests in `packages/dartvel_flutter/lib/src/studio/`.

| Area | What the others offer | Studio before | Studio now |
|---|---|---|---|
| Navigation and IA | A left rail of sections (Webflow Designer/CMS/Settings, WP admin menu), a page list, breadcrumbs | Rail of sections (Pages, Data, Site map, Frontend, Backend, Modules, Tasks, Queue, Cache, Team, Flags, Operations); a bottom bar on phones | Unchanged, plus every section, page and element reachable from the command palette |
| Search and command palette | Framer, Webflow and Linear-style Cmd+K to jump anywhere or run an action | None | **Built:** Ctrl/Cmd+K palette: go to a section, open a page, select an element by name and text, insert an element, duplicate, delete, undo, redo, show the code. Fuzzy, keyboard-driven, provided by each section while it is on screen |
| Canvas editing | Drag, drop, reorder, multi-select, duplicate, copy/paste, nudge with arrows | Drag from the palette, reorder by dragging, select, delete, undo/redo | **Built:** duplicate (Ctrl/Cmd+D) with fresh ids. Still missing: multi-select, copy/paste between pages, arrow-key nudging |
| Properties panel | Grouped style panel (Webflow), property sheet (Power Apps) | Inspector with content, layout, typography, size and spacing, colour, border, shadow, per-breakpoint overrides | Unchanged |
| Formula bar / expressions | Power Apps and Excel: a formula bar across the top bound to the selected control's property, with IntelliSense; Bubble's dynamic expressions | None | **Built:** formula bar across the editor: name box to pick the field, a formula per field kind (text, arithmetic, hex or rgb colour, choice, TRUE/FALSE, Navigate(...)), highlighting, completions (options, routes, data models and fields, functions), inline errors with the column, Enter to apply, Esc to cancel, one undo step through the same controller |
| Data and collections | Webflow CMS collections, Bubble data types, WP posts list, Power Apps data sources | Data section: records of each data model in a table and a typed form, conflict-refused edits | Unchanged; binding a page element to a record field is still missing (the formula bar names models and fields, the renderer does not yet read bindings) |
| Workflows and logic | Bubble workflows, Power Automate flows | Frontend and Backend functions built from steps, exported as Dart (Studio Pro) | Unchanged; the formula bar's language is the one a workflow step's arguments could adopt next |
| Preview and publish | Preview per breakpoint, publish, staging | Phone/tablet/desktop widths, zoom, Deploy to chosen targets, restore the compiled page, review and scheduling | Unchanged |
| Users and roles | Webflow roles, WP roles and capabilities, Power Apps sharing | Admin grant, Team section, policies, reviewers | Unchanged |
| Undo and history | Undo stack, version history and restore (Webflow backups, WP revisions) | Undo/redo of every edit; content versions with history and restore | Unchanged; formula-bar edits are in the same undo stack |
| Keyboard shortcuts | Documented shortcut sheets (Framer, Webflow) | Delete, Esc, Ctrl+Z/Shift+Z on the canvas | **Built:** Ctrl/Cmd+K, Ctrl/Cmd+D, Ctrl/Cmd+/ for a shortcut sheet listing every Studio shortcut |

## What is next, by value

1. Bind an element to a record field from the formula bar (`Article.title`), rendered on the page and exported as generated Dart.
2. Multi-select with shift-click, and copy/paste of elements between pages.
3. Arrow-key nudging and alignment guides on the canvas.
4. The formula language for workflow step arguments, so a function step is edited in the same bar.
