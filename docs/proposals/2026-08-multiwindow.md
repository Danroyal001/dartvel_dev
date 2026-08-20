# Dartvel Proposal — Multi-Window and Tab Workspaces

> **Reviewed and incorporated 2026-08-19.** Now two h1 sections in
> `NEW_SPEC.md` — **Multi-Window** and **Tab Workspaces** — both indexed in
> `docs/spec-status.json` as `Draft` / `Designed`. Nothing is implemented; this
> document is kept as the working record and the reasoning behind what changed.
>
> ## What the review changed
>
> **The application key moved out.** It was defined inside the window section,
> but it is a cross-cutting concern — client-side encryption at rest, `dartvel
> key generate|rotate|status`, per-target custody — that the shared store
> merely happens to be the first consumer of. It now lives in *Secrets and
> Environments*, which already draws the backend-scoped boundary, and the
> window section references it. Defining a platform-wide concept inside the
> feature that first needs it is how the specification grows two answers to
> one question; the cross-item review of the platform-additions proposal
> flagged the same pattern four separate times.
>
> **Diagnostic codes renumbered contiguously to `DV-WINDOW-001`–`006`.** The
> proposal reserved `001` and described it plus a former `kioskLocked` as
> "retired, not reassigned". That discipline is right for shipped codes, but
> nothing here has shipped, so the spec would have opened at `002` while
> explaining a history no reader can see. The binding-failure code is now
> `006`.
>
> **Desktop rows relabelled `Experimental`.** The proposal labelled Windows,
> macOS and Linux `Supported` with a footnote that Flutter's windowing is
> experimental, behind a flag, with `@internal` APIs that may rename. A label
> is what an application can rely on, so the footnote and the label disagreed;
> the label now matches the footnote.
>
> **The four open questions are resolved rather than carried in.** A
> specification section that asks the reader questions is not a contract.
> `DVTab.widget(...)` is absent (a tab without a route cannot tear out, deep
> link or restore); sharing is always explicit at the signal declaration;
> popup, tooltip and satellite kinds map to overlays off-desktop, keeping one
> mental model; and the watcher question the proposal had already resolved is
> stated as settled.
>
> **Condensed from 669 lines to roughly 390**, with the reference example and
> the "extracted from" framing dropped. The load-bearing decisions are all
> kept, including the ones that read as restrictions: no placement, no
> `activate()`, no `broadcast`, no model data in the store.
>
> ## What the review kept unchanged
>
> The core is unusually well-matched to this platform and survived intact: a
> window is a route, which falls straight out of being URL-first; `DV.Window`
> as an alias on `DV.Platform.Window` per the established proxy pattern rather
> than a new plural namespace; lifecycle as a generated read-only enum signal;
> `open()` that never fails but always reports, with per-code log levels
> calibrated to whether a developer can act; `DVTabWorkspace` as a generated
> application component composed from `DVBox` and `DVText`; and the argument
> for a watched store over message passing, which is the strongest reasoning
> in the document and the reason there is no `DV.Window.broadcast`.

---

# Motivation

Desktop-class applications are made of windows, and window-class applications
are made of tabs. Qt has this; Electron has this; Flutter is landing it
(desktop multi-window is on the main channel behind `--enable-windowing`).
Dartvel's position — one codebase, every platform, graceful degradation — is
exactly the position from which multi-window should be a platform capability
rather than per-app plumbing, because the hard part is not opening a window:
it is defining what a window *means* on eleven targets that disagree about
whether windows exist.

---

# Design Principle: A Window Is a Route

Every Dartvel window hosts exactly one route. This is not a convenience; it is
what makes one API possible across platforms that implement "another window"
in four unrelated ways:

| Platform family | "Open a window" actually means | Content addressed by |
|---|---|---|
| Windows / macOS / Linux | native window, same engine | route |
| Web | `window.open('/route')`, separate app instance | URL (the route) |
| Android | new task/activity, separate engine | deep link (the route) |
| iPadOS | new UIScene, separate root | scene activation URL (the route) |

Dartvel is already URL-first — SSG, server rendering, and sitemaps all require
every route to map to one canonical URL. Windows inherit that for free: the
route *is* the serialization format for "what this window shows," and the
platforms that cannot share memory (web, Android, iPadOS) already know how to
open a URL. No second addressing scheme, no window-content registry.

```dart
await DV.Window.open(DVPages.orders);
await DV.Window.open(DVPages.order(id), options: DVWindowOptions(size: Size(900, 620)));
```

Corollaries:
- Anything a window shows is reachable by URL, so it is deep-linkable,
  SEO-addressable (where public), and restorable after restart.
- `DV.Navigation` gains a target, not a new API:
  `DV.Navigation.to(DVPages.orders, window: DVWindowTarget.newWindow)`.
- A window with no route is not expressible, which is the point.

---

# API Surface

## DV.Platform.Window

`DV.Platform.Window` (existing) grows from "the current window" into the
window manager: it owns the current window *and* the collection. `DV.Window`
is the alias, per the established proxy pattern (`DV.Platform.Clipboard` /
`DV.Clipboard`). No separate plural namespace.

```dart
DV.Window.current                       // DVWindow — this window
DV.Window.all                           // DVSignal<List<DVWindow>>
DV.Window.capability                    // DVWindowingCapability (see below)

final win = await DV.Window.open(
  DVPages.orders,
  options: DVWindowOptions(
    size: Size(900, 620),
    constraints: BoxConstraints(minWidth: 480, minHeight: 320),
    title: 'Orders',
    kind: DVWindowKind.regular,          // regular | dialog | popup | tooltip | satellite
  ),
);

win.route                                // DVRoute — what it shows
win.lifecycle                            // DVSignal<DVWindowLifecycle>
win.setTitle('Orders — March');
win.setSize(Size(1200, 800));
await win.close();
```

Existing current-window surface (`DV.Platform.Window.setTitle`,
`persistState`, `restoreState`) is unchanged and now reads as sugar over
`DV.Window.current`.

There is no `activate()`. `open()` opens, focuses, and activates — a window
that appears unfocused is not a behavior anyone wants, so it is not an option.
The job `activate()` would have done — bringing an existing window to the
front — belongs to `open()` too: opening a route that a window already shows
focuses that window instead of duplicating it. One verb, idempotent by route.
A deliberate second window on the same route says so:
`open(..., options: DVWindowOptions(duplicate: true))`.

```dart
enum DVWindowLifecycle {
  requested, creating, created, ready, active,
  inactive, minimized, maximized, fullscreen,
  closing, closed, failed,
}
```

Lifecycle is a read-only generated enum signal, per the Lifecycle Signals
section: the runtime owns transitions, application code observes.

Rules:
- **`DV.Window.open` always succeeds.** Where a real window cannot be created,
  it navigates to the route instead — `regular` becomes a pushed page,
  `dialog` a modal route, `popup`/`tooltip` an overlay. This is the payoff of
  making a window a route: the fallback is not a consolation prize, it is the
  same content presented the way the platform can present it. See
  [Degradation](#degradation-open-never-fails).
- **Placement is not part of the contract.** No `position` in `DVWindowOptions`
  and no `setPosition`. Wayland forbids app-positioned windows, Flutter's
  desktop API exposes none, and web/Android/iPadOS delegate placement to the
  OS. A capability that only three targets could honor — and one of the three
  desktop display servers rejects — is not a capability; if upstream later
  ships placement, it arrives as `DVWindowPlacementHint`, best-effort by name.
- Opening a window on web requires a user gesture (popup blockers). The
  generated `.onTap`/`.onPressed` path satisfies this automatically; a call
  outside a gesture degrades to navigation rather than failing, so a blocked
  popup shows the content in-page instead of nothing.
- Every window participates in auth, tenant, theme, and locale context
  exactly as a navigated page does — because it is one.

## Degradation: open never fails

Failing is removed; **reporting is not**. Every fallback carries a stable
diagnostic code and a reason, is written to observability through `DV.log`,
and is readable on the returned window. A degradation that nobody can see is
the silent-ignoring the spec forbids — the contract is that `open()` always
presents the route, not that it does so quietly.

```dart
enum DVWindowDegradation {
  none,                  // a real window was created
  capabilityUnsupported, // DV-WINDOW-004
  kioskLocked,           // DV-WINDOW-005
  gestureRequired,       // DV-WINDOW-006
  platformRefused,       // DV-WINDOW-007
  disabledByConfig,      // DV-WINDOW-008
}
```

| Code | Reason | Presented as |
|---|---|---|
| `DV-WINDOW-004` | target has no multi-window capability | page / dialog / overlay by kind |
| `DV-WINDOW-005` | kiosk mode active; surface stays locked | page / dialog by kind |
| `DV-WINDOW-006` | web popup blocked — call outside a user gesture | page / dialog by kind |
| `DV-WINDOW-007` | platform refused (OS window limit, task creation denied) | page / dialog by kind |
| `DV-WINDOW-008` | `windowing.enabled: false` in configuration | page / dialog by kind |

`DV-WINDOW-009` is not a degradation of `open()` but of the shared store: the
preference-store listener is unavailable (separate process), so the store is
polled at `pollMs`. Logged once at store init, not per read.

Each is explained by `dartvel explain DV-WINDOW-006`, per the spec's rule that
every diagnostic carries a stable code with a documented cause and fix. Codes
`DV-WINDOW-001` (window on an unsupported target) and the former
`DVWindowError.kioskLocked` are **retired, not reassigned** — a code must not
change meaning between releases, and both described failures that no longer
occur.

```dart
final win = await DV.Window.open(DVPages.order(id));

win.isVirtual        // true when the route was navigated, not windowed
win.degradation      // DVWindowDegradation — why, or .none
win.presentation     // DVWindowPresentation.window | page | dialog | overlay
await win.close();   // closes the window, or pops the route — same call
```

Logged automatically at open time, once per call, through the standard
observability path:

```text
DV-WINDOW-006  Window request presented as a page.
  route:        /orders/1042
  requested:    DVWindowKind.regular
  presented:    DVWindowPresentation.page
  reason:       web popup blocked — open() was not called during a user gesture
  fix:          call from a generated .onTap/.onPressed handler
```

Log level is calibrated to whether the developer can do anything about it.
`DV-WINDOW-004` on a phone is `debug` — the platform has no windows and the
fallback is the intended behavior, so warning on every call would train people
to ignore the channel. `DV-WINDOW-006` and `DV-WINDOW-007` are `warning`:
both are fixable, and both mean the app asked for something it could have had.
`DV-WINDOW-005` and `DV-WINDOW-008` are `info` — deliberate configuration,
worth recording, not worth flagging.

`dartvel analyze performance` aggregates these across a run, so a call site
that always degrades shows up as one finding rather than a thousand log lines.

The returned `DVWindow` is real either way. `close()` pops, `lifecycle`
tracks the route's presentation states, and `DV.Window.all` lists virtual
windows alongside real ones — so a tab strip, a workspace, or a close-all
command is written once and works on a phone. **Application code never
branches on capability**; that is what the capability metadata is for at build
time, not what it is for at every call site.

Honest about what degrades:

- `setSize` and window `constraints` are no-ops on a virtual window. Per the
  spec's rule that nothing is silently ignored, they log through `DV.log` at
  debug level rather than vanishing, and `dartvel analyze performance` reports
  a call site that only ever runs virtual.
- `setTitle` maps to the page title (and the document title on web), which is
  the closest true equivalent rather than a discard.
- Opening N windows on a phone yields N stacked routes. That is the correct
  behavior — it is what the user asked for, presented the only way available —
  but a workspace UI should still read `capability.multiWindow` when deciding
  whether to *offer* "open in new window" as an affordance. Degrading a call
  is right; advertising a control that produces a surprising result is not.
- Kiosk degradation is not a security hole: the route is still subject to the
  same middleware, policies, and tenant scope it would face anywhere. Kiosk
  restricts the *surface*, not the content.

## Capability metadata

Per the Platform Compatibility section, windowing carries generated support
metadata, queryable at runtime and validated at build time:

```dart
final cap = DV.Window.capability;
cap.multiWindow        // can a second OS-level window exist at all
cap.sameEngine         // do windows share one engine/isolate (object handover)
cap.tearOut            // can a tab detach into a window
cap.inPageViews        // web: in-page multi-view embedding available
```

## State sharing

Two modes, chosen automatically from `capability.sameEngine`:

```dart
enum DVWindowHandover { sameEngine, shared }
```

These describe how rich a *handover* can be, not whether the shared store
exists — `DV.Window.shared` is available and behaves identically on every
platform.

- **sameEngine** (desktop; web in-page views): the moved content is the same
  Dart object tree. Signals, in-flight requests, and scroll positions survive
  by construction. Widget state is preserved through generated keyed subtrees.
- **shared** (web `window.open`, Android tasks, iPadOS scenes): the new window
  is a separate engine, so state is shared **through the storage layer, with
  change notification** — one writer publishes, every other window is notified
  and its signals update. Not a handover: a continuously shared store. The two
  windows stay in sync for the rest of their lives, not just at the moment of
  tear-out.

This is a better fit than one-shot message passing (`BroadcastChannel`, intent
extras, `NSUserActivity`) for a reason worth stating: a message is delivered
once, to whoever is listening at that instant. A window opened five seconds
later gets nothing, a window that missed a message never learns, and crash
recovery has nothing to read. A watched store has no delivery moment — late
joiners read current state on open, and the same bytes that sync a running
window restore a crashed one.

### The store

`DV.Window.shared` is a typed, watched key-value store scoped to the
application (and tenant, and user):

```dart
final shared = DV.Window.shared;

await shared.set('workspace.activeTab', DVJsonString(tab.id));
final value = await shared.get('workspace.activeTab');

shared.watch('workspace.activeTab').listen((value) { ... });
final tabId = shared.signal('workspace.activeTab');  // DVSignal, updates live
```

Declared signals opt into sharing at their declaration site, and the generated
code does the read/write/watch wiring:

```dart
final activeTab = context.signal('', shared: 'workspace.activeTab');
```

The store is **one API on every platform**, desktop included. What varies is
which of its two jobs the platform does natively:

| Target | Notification (sync) | Persistence (restart) |
|---|---|---|
| Windows | in-process — signals | `%APPDATA%` config via `DV.FileStorage` |
| macOS | in-process — signals | `NSUserDefaults` |
| Linux | in-process — signals | XDG config via `DV.FileStorage` |
| Android | `OnSharedPreferenceChangeListener` | `SharedPreferences` |
| iPadOS | KVO | `NSUserDefaults` |
| Web | `storage` event | `localStorage` |

Separating those two columns is what lets the abstraction be genuinely uniform
rather than uniform-looking. **Notification** is how a change reaches another
window; **persistence** is how it survives a restart. Every platform needs the
second — workspace layout, tab order, and draft values must come back after a
relaunch, and that is as true on Windows as on a phone. Only the cross-engine
targets need the first from the OS, because desktop windows share an isolate
and a signal write already reaches every window with no serialization, no
notification hop, and no latency.

So `DV.Window.shared` behaves identically everywhere — same keys, same
`signal()`, same encryption, same `shared:` declaration — and desktop simply
takes a faster path through the same contract. Nothing in application or
`DVTabWorkspace` code knows which column its platform is in, and no code
branches on `capability.sameEngine`; that flag describes how rich a tear-out
handover can be, not whether the store exists.

The reason this reads as a simplification rather than a compromise is what it
removes: no `Directory.watch`, no `FileObserver`, no `DispatchSource`, no
per-vendor inotify quirks. Three OS-provided notification mechanisms replace
three native watchers Dartvel would have had to write and keep working, and
the one platform family with no OS notification story needs none.

Why the preference stores are the right persistence layer on the cross-engine
targets specifically:

- **Android windows are tasks in one process.** Flutter engine groups give
  each window its own engine and isolate, but the same Android process — so a
  preference listener fires for the other window. (Only an activity with an
  explicit `android:process` breaks this, which Dartvel does not generate.)
- **iPadOS scenes are one process** by construction; KVO fires across scenes.
- **Web `storage` events are the canonical cross-tab mechanism** — designed
  for exactly this, fires in every other tab of the origin and not in the
  writer, which is the behavior we want.

**Encryption stays Dartvel's job, not the store's.** Values are encrypted with
the application key (see below) *before* the write, so the backing store is a
dumb byte sink on every target. That avoids depending on
`EncryptedSharedPreferences`, Keychain-backed defaults, or the fact that
`localStorage` has no encryption story at all — one code path, one threat
model, one thing to audit. It is also what makes the web row acceptable: plain
`localStorage` holding Dartvel-encrypted values is the same guarantee as
encrypted prefs on Android, and the same guarantee as a config file on Linux.

**Size, and the one place the filesystem survives.** Preference stores are
built for small values — `localStorage` caps around 5MB per origin, and
`SharedPreferences`/`NSUserDefaults` load wholesale into memory. Workspace
state (tab order, active tab, scroll offsets) is bytes. A large draft — rich
text, an edited form — is not. So values over `spillThresholdKb` (default 32)
are written to `DV.FileStorage` with only an encrypted pointer in the
preference store; the pointer write is what triggers the notification, and the
reader follows it. No watcher needed, because the notification still comes
from the preference store.

**Genuinely separate processes** — a second app *instance* rather than a
second window, or an activity with a custom process — fall outside preference
listeners. That is the residual case, and it degrades to polling the store at
`pollMs` (default 250), reported once by `dartvel doctor` and logged as
`DV-WINDOW-009`. It is a narrow enough case to be a fallback rather than the
architecture.

### Rules

- **Writes are coalesced.** A signal changing per frame must not produce a
  write per frame. Shared writes are debounced (default 50ms) and batched per
  flush; the generated wiring never lets a shared signal write on every
  `value` assignment.
- **Last write wins, per key.** Keys are the conflict unit, so unrelated state
  in the same window never contends. State that genuinely needs merge
  semantics is model state — use a model.
- **Sensitive values are encrypted at rest, not banned.** A `@DVModel.sensitiveField()`
  can be shared; it is written encrypted, exactly as `sensitiveField(encrypted: true)`
  already implies elsewhere in the spec. Encryption is on by default for the
  whole store, not per-key — a per-key opt-in means the one key someone forgot
  is the one that mattered, and encrypting view state costs nothing at these
  sizes. Sensitive keys additionally carry the audit-on-access behavior the
  field annotation already declares.
- **`DV.Secrets` values still never reach the store** — and the reason is
  scope, not confidentiality. Secrets are backend-scoped by declaration; a
  client-side window store holding a backend secret is a `DV-SECRETS-001`
  violation whether or not the bytes are encrypted, because the value should
  never have been on the client at all. That stays a build error
  (`DV-WINDOW-003`).

### The application key

Laravel generates an `APP_KEY` at install and encrypts with it; Dartvel does
the same thing, with one correction the client-side setting forces.

```bash
dartvel key generate          # writes to the platform key store, not the repo
dartvel key rotate
dartvel key status
```

The key is **never in the bundle and never in `pubspec.yaml`**. This is not
caution, it is the spec's own rule: only `PUBLIC_`-prefixed values reach
`env.g.dart`, and a key that ships to every visitor encrypts nothing. Laravel's
`APP_KEY` is safe in `.env` because it lives on a server the operator controls;
a Flutter app's store is on the user's device, so the key has to come from
somewhere the user's own OS protects:

| Target | Key custody |
|---|---|
| Windows | DPAPI-protected, per-user |
| macOS / iPadOS | Keychain, app-scoped |
| Linux | Secret Service (libsecret), keyring-backed |
| Android | Android Keystore, hardware-backed where available |
| Web | non-extractable WebCrypto `CryptoKey` in IndexedDB |

Generated at first run per install, per user — so it is not a shared secret,
and there is nothing to leak into version control. The web row is the strongest
of these in one specific way worth noting: a non-extractable `CryptoKey` cannot
be read back even by the application's own JavaScript, so the key survives XSS
that would trivially lift a string from `localStorage`.

Backend-side encryption (`DV.Crypto`, encrypted model fields at rest in the
database) uses the server-held key from `DV.Secrets` in the ordinary way.
These are two different keys with two different threat models, and conflating
them is how a device key ends up on a server or a server key ends up in a
bundle.

Rotation re-encrypts the store in place through the existing
`DV.Secrets.onRotate` hook shape. A store that cannot be decrypted — key
rotated out, keychain reset, profile moved between machines — is **discarded,
not fatal**: it holds view state, so losing it costs a tab order, and a window
that refuses to open because a scroll offset would not decrypt is a worse
outcome than one that opens fresh. That degradation is reported through
`DV.log`, never silently.
- **Store entries are ephemeral by contract.** Workspace state is written to a
  session-scoped namespace, cleaned on last-window-close and swept on next
  launch. A crashed app leaves a readable store — that is the recovery
  feature — but a stale one is garbage-collected by age, not kept forever.
- **The store is not for model data.** Models already converge across engines
  through model sync, which handles auth, tenant filters, and policy checks
  before delivery. Duplicating model rows into the shared store would bypass all
  three. The store holds view state: which tab is active, tab order, workspace
  layout, scroll offsets, draft form values.

That boundary is also why **there is still no `DV.Window.broadcast`**: the
shared store publishes *state*, which a late-joining or restarted window can
read. A message API would publish *events*, which it cannot — and would sit
alongside model sync doing a worse version of its job.

### Handover at tear-out

Tear-out on a `shared` target is: write the tab's shared keys, open the window
at the route, let the new engine read them on boot. The route carries identity
(URL-first pays again); the store carries state. If the new window is slow to
start, nothing is lost — the state is sitting in the store waiting for it, which is exactly the failure mode message passing gets wrong.

---

# Tab Workspaces

`DVTabWorkspace` is a generated application component — like `User.Table()`,
built from `DVBox` and `DVText`, no new primitives — that owns the tab strip,
reordering, tear-out, and re-dock, wired to `DV.Window`.

```dart
@DVPage(title: 'Workspace')
Widget _workspacePage(BuildContext context) => DVTabWorkspace(
  initialTabs: [
    DVTab(DVPages.orders),
    DVTab(DVPages.customers),
    DVTab(DVPages.reports),
  ],
);
```

A tab is a route (`DVTab(DVPages.x)`) — the same identity a window has, which
is what makes tear-out *navigation* rather than surgery:

- **Reorder** — drag within the strip. Works on every target, including TVs
  and watch-sized screens where the strip renders as a platform-appropriate
  switcher. Pure UI; no windowing capability required.
- **Tear-out** — drag beyond the strip (or context-menu "Move to new window"
  where drag is unavailable). Gated on `capability.tearOut`. Executes
  `DV.Window.open(tab.route)` with handover per the table below. Where
  `tearOut` is false the gesture is absent, not broken — the tab simply does
  not leave the strip.
- **Re-dock** — dragging a tab from one window's strip into another's.
  Same-engine targets hit-test across windows and hand the object over.
  Separate-engine targets re-dock by adoption: the receiving workspace adds
  the route, the source window closes it — same convergence, two steps.
- **Empty-window rule** — a workspace window whose last tab leaves closes
  itself; its window's tabs fold into the main window if the OS closes it
  around them. This is workspace state policy, not window callbacks, so
  tear-out → re-dock → cleanup is one transition.
- Workspace layout (which windows, which tabs, order, active tab) persists
  through the existing `DV.Platform.Window.persistState` surface, extended to
  `DV.Window.persistWorkspace(name)` / `restoreWorkspace(name)`, and is
  tenant- and user-scoped like any stored state.

Tab strip behavior is capability-shaped, never capability-broken:

```text
tearOut: true   → Chrome-grade detachable tabs        (desktop, iPad, ChromeOS)
tearOut: false,
multiWindow: true → tabs + explicit "open in new window" (web*, Android phones)
multiWindow: false → tabs only; open() navigates          (iPhone, TV, watch, kiosk)
```

\* Web tear-out by drag is `false` because a drag ending on the desktop cannot
open a popup without a gesture-attributed call; web gets the explicit
affordance instead, which satisfies the gesture requirement.

---

# Platform Matrix

Support labels per the Platform Compatibility section.

| Target | Multi-window | Mechanism | Handover | Label |
|---|---|---|---|---|
| Windows | yes | Flutter windowing (same engine) | sameEngine | `Supported`¹ |
| macOS | yes | Flutter windowing | sameEngine | `Supported`¹ |
| Linux | yes | Flutter windowing; Wayland: no placement ever | sameEngine | `Supported`¹ |
| Web | yes | `window.open(route)`; in-page multi-view for panels | shared / sameEngine² | `Supported with limitations` |
| Android | yes | task-per-window via engine groups; freeform on ChromeOS/desktop mode | shared | `Supported with limitations` |
| iPadOS | yes | UIScene (already required by the Apple lifecycle migration) | shared | `Supported with limitations` |
| iOS (iPhone) | no | navigation fallback | — | `Supported with limitations`⁴ |
| Fuchsia | plausible | view-based compositor | sameEngine | `Experimental` |
| Tizen / webOS | no | single-fullscreen app model; navigation fallback | — | `Supported with limitations`⁴ |
| eLinux / embedded | no by policy | kiosk stays locked; navigation fallback³ | — | `Supported with limitations`⁴ |
| Watch | no | navigation fallback | — | `Supported with limitations`⁴ |

¹ **Upstream dependency, stated plainly:** Flutter's desktop windowing is
experimental — main channel, `--enable-windowing`, `@internal` APIs that may
rename between releases. Dartvel's abstraction is the churn absorber: the
generated bindings under `window.*` are the only code that touches the
Flutter surface, so an upstream rename is a Dartvel point release, not an
application change. Until upstream stabilizes, `dartvel build
windows|macos|linux` with windowing enabled prints the experimental status,
and `dartvel doctor --target <t>` verifies the channel and flag.

² Web is two tiers by design: `window.open` for OS-level windows (separate
instance, shared) and in-page multi-view embedding (`multiViewEnabled`,
same engine) for panels, pickers, and embedded workspace regions. The second
tier also serves the existing browser-extension targets.

³ `DV.Platform.display.enableKiosk()` already implies a locked surface; a
kiosk that can spawn windows is an escape hatch. Under kiosk the surface stays
locked and the route is navigated in place instead. Multi-*display* embedded
targets (signage walls) are future work under device profiles, not this
proposal.

⁴ The *capability* is unsupported; the *API* is not. `capability.multiWindow`
reports false and no OS window is ever created, but `DV.Window.open` navigates
to the route, so application and workspace code compiles and runs unchanged.
This is why no target in this matrix is labelled `Unsupported`: the label
describes what an application can rely on, and every target can rely on
`open()` presenting the route.

The spec's rule that unsupported features must not be silently ignored is
satisfied by disclosure, not refusal: `capability` reports the truth,
every degraded call logs its `DV-WINDOW-00x` code and reason,
`win.degradation` reports it per call, virtual `setSize` calls log, and
`dartvel doctor --target <t>` prints the presentation each window kind will
receive. Nothing is pretended; only the failure is removed.

---

# Configuration

```yaml
dartvel:
  windowing:
    enabled: true               # default true where supported
    workspace:
      persist: true             # restore window/tab layout on launch
      tearOut: auto             # auto | disabled
    sharedState:
      encrypt: true             # app-key encrypted at rest; see The application key
      debounceMs: 50
      spillThresholdKb: 32      # larger values go to DV.FileStorage
      pollMs: 250               # separate-process fallback only
      sweepAfter: 24h
    web:
      inPageViews: true
      openInNewWindow: true
    android:
      freeform: auto            # honor OS freeform/desktop mode when present
    kiosk:
      allowWindows: false       # windows stay locked; open() navigates instead
```

# Bindings

Per the standing rule — generated FFI/ffigen or JNI/jnigen bindings only, no
Flutter platform channels:

- desktop: `window.open`, `window.close`, `window.setTitle`,
  `window.setSize`, `window.observeLifecycle`
- android: `window.task.open`, `window.task.close` (JNI, engine groups)
- ios: `window.scene.request`, `window.scene.close`
- web: generated web bindings over `window.open`, `localStorage` + the
  `storage` event, and the multi-view embedder API
- shared store: `window.shared.get`, `window.shared.set`,
  `window.shared.observe` over `SharedPreferences` (JNI), `NSUserDefaults`
  (FFI), `localStorage` (web bindings), and `DV.FileStorage` for the desktop
  persistence path — desktop needs no `observe` binding, since notification is
  in-process

A missing or refusing binding fails typed (`DV-WINDOW-002`), never silently.

# Studio and Devtools

The window inspector joins the generated devtools surfaces: live window list,
per-window route, lifecycle signal state, handover mode, workspace tree, and
capability report per configured target. Windows and tabs are project-graph
nodes (`graphVersion` bump), so `dartvel inspect windows --json` answers the
same way every other inspector does.

---

# Reference Example — Detachable Tabs in Dartvel

The application this proposal was extracted from — a Chrome-style movable-tab
workspace — written against the proposed surface. The ~450-line raw-Flutter
scaffold (workspace state, controller lifecycle, drag hit-testing, tear-out
detection, empty-window cleanup, state-preserving re-parent) becomes:

```dart
@DVPage(title: 'Dartvel Workspace')
Widget _workspacePage(BuildContext context) => DVTabWorkspace(
  initialTabs: [
    DVTab(DVPages.orders),
    DVTab(DVPages.customers),
    DVTab(DVPages.reports),
  ],
);

@DVPage()
Widget _ordersPage(BuildContext context) {
  final count = context.signal(0);
  return DVBox.list([
    DVText('Orders'),
    DVText('Local state: ${count.value} — tear me out and check I survive'),
    DVBox(DVText('Increment')).onPressed(() => count.value++),
  ]);
}
```

Reorder, tear-out, re-dock, workspace persistence, empty-window cleanup, and
per-platform degradation are the platform's job. The signal survives tear-out
on same-engine targets by object handover and on separate-engine targets by the
shared store —
the developer wrote neither.

---

# Open Questions (for review)

1. Should `DVTab` accept a widget as well as a route (`DVTab.widget(...)`)?
   Leaning **no**: a tab without a route breaks tear-out on every separate-engine
   target and the addressing corollaries. A page is cheap; make one.
2. Shared-key scope: is `shared:` always explicit at the signal declaration
   (proposed), or should a `DVTabWorkspace` share its tab's page signals by
   default? Leaning explicit — implicit persisted writes of arbitrary signal
   values are both a redaction risk and a write-amplification one.
3. ~~Watcher availability~~ — **resolved.** Moving the store onto platform
   preference stores removed the question: no `Directory.watch`, no
   `FileObserver`, no iOS gap. Polling survives only for genuinely separate
   processes (`DV-WINDOW-009`), automatic and doctor-reported, since
   silently-not-syncing is the worse outcome.
4. Satellite/tooltip/popup kinds on non-desktop: map to overlays (proposed) or
   reject? Overlays keep one mental model; rejection is more honest about
   what the OS is doing. Proposal says overlays, flagged for review.
