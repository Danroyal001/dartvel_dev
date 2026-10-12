> **Approved 12 October 2026 and merged into NEW_SPEC.md (PR #114). Revised 13 October 2026 by the owner: a microcontroller runs the app itself, compiled to Rust firmware; the earlier `@DVDevice` device-declaration design is withdrawn.** The owner's decisions in `2026-10-12-application-entry-decisions.md` override this text where they differ (notably: `DV.run` breaks, microcontroller firmware is Rust everywhere). Kept as the record of what was proposed.

# Proposal: Application Entry — `DV.run`

> **Status of this document:** a standalone proposal for review, written to be
> merged into `NEW_SPEC.md` on approval. Part 1 is the new section, ready to
> paste. Part 2 replaces the existing *Home Widgets* section. Part 3 lists the
> edits other sections need so the specification stays consistent. Part 4 is
> the `docs/spec-status.json` entries, Part 5 the order of work, Part 6 the open
> questions.

## Why this exists

The specification describes a great deal of work that must happen **before the
first frame, or outside any frame at all**, and never says what performs it:

- *Lifecycle Signals* drives `DVAppLifecycle` through `initializing → booting →
  ready`, and its own example registers globals in `booting`.
- *Crash Reporting* captures "uncaught errors in the guarded zone", which
  somebody has to create before anything runs.
- *Multi-Window* restores the workspace "before `main` presents", opens declared
  kiosk windows "at boot", and takes a single-instance lock.
- *Kiosk Mode* arms the watchdog "on boot with `reason: 'startup'`".
- *Terminal Rendering* chooses GUI or terminal — `--tui`, or the no-display
  prompt — before anything renders.
- *Mail and Notifications*, *Scheduling* and *Home Widgets* need Dart to run
  when the process was started by a push message, a WorkManager job or a widget
  refresh, **with no `main()` and no window**.

Meanwhile the example application starts with plain Flutter:

```dart
void main() {
  runApp(createDartvelApp());
}
```

which can do none of the above. The specification refers to "the generated
runtime" in a dozen places and never says where it is entered. This proposal
names it.

---

# Part 1 — New section

# Application Entry

Stability: `Draft` · Status: `Designed`

Every Dartvel process starts in one function:

```dart
// lib/main.dart
import 'package:my_app/dartvel_client/dartvel_client.dart';

void main(List<String> args) => DV.run(args);
```

That line is the same in a phone app, a desktop app, a web build, a terminal
build, a pure Dart server or CLI, and a television. It does not grow. Whatever
an application needs to customize — its root widget, the work it does at boot —
is declared elsewhere (see *Customizing boot*), so that the entries Dartvel
generates and which never pass through `main` boot exactly the same way.

## One name, and why it is `run`

`DV.run` starts more than an app. It starts a server, a queue worker, a cron
process, a command-line tool, a headless home-widget refresh, a background job
woken by a push message, and — compiled rather than executed — the firmware of
a microcontroller. Most of those have no widgets, so naming the function after `runApp` would describe the
one case in which it is least needed.

There is no `DV.runApp`, `DV.runServer` or `DV.runHeadless`. One function reads
what kind of process it is in and boots that. A second name for the same job is
how two boot paths start to disagree.

Flutter's own `runApp` keeps working — see *Plain `runApp` still works*.

## Signature

```dart
static Future<void> run([List<String> args = const <String>[]]);
```

- `args` is the process's command line. On the web, and on targets with no
  command line, it is omitted.
- The future completes when the process is shutting down: when the last window
  closes under the exit policy, when a server is asked to stop, when a command
  or a headless entry finishes. A `main` that does not await it is fine; the
  process lives as long as the platform keeps it.
- Calling `DV.run` twice in one isolate is `DV-RUN-002`, and the second call
  does nothing.

## What entered the process

The first thing `DV.run` decides is **what kind of process this is**. The
answer is a `DVEntry`, readable for the life of the process:

```dart
DV.Platform.entry          // DVEntry
DV.Platform.args           // List<String>, as passed to DV.run

sealed class DVEntry {
  const factory DVEntry.app() = DVAppEntry;                 // a GUI
  const factory DVEntry.terminal() = DVTerminalEntry;       // cells, not pixels
  const factory DVEntry.server(DVServerRole role) = DVServerEntry;
  const factory DVEntry.command(String name) = DVCommandEntry;   // @DVCommand
  const factory DVEntry.homeWidget(DVHomeWidgetRequest request) = DVHomeWidgetEntry;
  const factory DVEntry.background(DVBackgroundTask task) = DVBackgroundEntry;
  const factory DVEntry.push(DVPushDelivery delivery) = DVPushEntry;
  const factory DVEntry.worker(String task) = DVWorkerEntry;     // DV.Workers
  const factory DVEntry.embedded(String project) = DVEmbeddedEntry; // brownfield
  const factory DVEntry.test() = DVTestEntry;
}

enum DVServerRole { all, web, worker, cron }
```

It is resolved from four inputs, in this order, and never guessed:

1. **The entry point that was called.** Dartvel generates one entry function per
   headless surface (*Generated entry points*, below). Each passes its own
   `DVEntry` to the runtime, so a widget refresh can never be mistaken for an
   app launch.
2. **The build.** The target and presentation are compiled in
   (`DARTVEL_PLATFORM`, already stamped for `visionos`; the `-cli`/`-tui`
   suffix; a backend build). A terminal-only build cannot resolve to `app`,
   because it contains no GUI backend.
3. **The environment.** `DARTVEL_ROLE` selects a server's role, as *Deployment*
   already specifies.
4. **The arguments.** `--tui` in a dual-mode build, a command name in a CLI, a
   deep link or file path on desktop.

Application code rarely reads `DV.Platform.entry`. It exists so a boot hook can
skip work an entry does not need, and so diagnostics can say which entry
produced them.

## The boot sequence

`DV.run` is what drives `DV.lifecycle.app`. Each phase is a state transition, so
Studio, the CLI and `dartvel inspect` see the same boot the application does.

| Phase | Lifecycle state | What happens | Entries |
|---|---|---|---|
| 0 | `uninitialized` | nothing has run | — |
| 1 | `initializing` | guarded zone; `FlutterError.onError` and `PlatformDispatcher.onError`; isolate error listener; log sinks; generated configuration; secrets resolver; the device application key; the kiosk watchdog, armed here because it must catch a hang in everything after it | all |
| 2 | `initializing` | **surface selection**: single-instance check (a second desktop launch forwards its arguments to the first and exits here, before Flutter is initialized, so it costs milliseconds); GUI or terminal for a dual-mode build, including the no-display prompt | `app`, `terminal` |
| 3 | `booting` | providers the project declared (auth, cache store, database, queues, storage, push); modules mounted in dependency order, each through its `DVModuleLifecycle`; the offline store opened; declared kiosk policy applied | all, filtered by usage |
| 4 | `booting` | the application's `@DVBoot` functions, in declaration order | per their declared entries |
| 5 | `booting` | the surface comes up: the root widget for `app`/`terminal`; declared kiosk windows; workspace restore; the listener for `server`; the job for a headless entry | per entry |
| 6 | `ready` | `app`: the first frame of the first route has been presented. `server`: the listener accepts. Headless: the result has been written | per entry |
| 7 | `ready`, then app states | deferred start-up work, never awaited by the first frame: crash report from the previous run sent; protocol handshake; flag rule sync; OTA check; offline replay; push token refresh | client entries |
| 8 | `shuttingDown` → `stopped` | logs and spans flushed; stores closed; the single-instance lock released; a server drains in-flight requests and stops its queue worker cleanly | all |

Three rules hold the sequence together:

- **Nothing before `ready` waits on the network.** A protocol handshake, a flag
  sync, an OTA check and a token refresh are all phase 7. A launch that blocks
  on a server is a launch that hangs in a lift. `dartvel analyze` reports a
  `@DVBoot` function that awaits a network call before the first frame
  (`DV-RUN-007`).
- **Usage decides what boots, per entry.** The preprocessor already strips
  subsystems a project never uses (*Adoption*). `DV.run` extends that per entry:
  a home-widget refresh opens the shared store and the offline store and nothing
  else; it does not mount the router, open windows, start model sync or check
  for updates. A boot that does less is a boot that fits inside the time
  Android and iOS give a background task.
- **Failure has a page, not a red screen.** A boot phase that throws moves the
  lifecycle to `failed`. An `app` entry renders the generated boot-failure page
  (*Error, Empty, and Loading States*) with a retry; a `server` exits non-zero
  with the phase that failed; a headless entry records the failure and leaves
  the previous frame in place. Each reports `DV-RUN-004` naming the phase.

## Customizing boot

`main` never grows, because the generated entry points cannot see what is
written in it. Customization is declared, like everything else, as a private
generation input that the generator wires into **every** entry.

### Work at boot

```dart
@DVBoot()
Future<void> _registerPayments(DVBoot boot) async {
  DV.global<PaymentGateway>(
    PaystackGateway(secret: DV.Secrets.get('PAYSTACK_SECRET')),
  );
}

@DVBoot(entries: <DVEntryKind>{DVEntryKind.app, DVEntryKind.homeWidget})
void _registerClock(DVBoot boot) => DV.global<Clock>(SystemClock());
```

- Runs in phase 4, after providers and modules, before the surface comes up.
- `entries:` limits which entries run it. The default is every entry the
  function's code can run in: a boot function that touches a backend-scoped
  secret is server-only by construction, the same reachability rule
  `DV-SECRETS-001` uses.
- Several `@DVBoot` functions run in declaration order across files, sorted by
  path, so the order is stable and reviewable.
- `DV.lifecycle.app.listen(...)` keeps working for code that would rather
  observe. `@DVBoot` exists because a listener registered in `main` is never
  registered in a generated entry.

### The root widget

Dartvel builds the root itself: a `MaterialApp.router` over the generated
router, with the theme from *Theme* tokens (`dartvelDefaultTheme` until tokens
are declared), the locale from `DV.I18n`, and the title from `dartvel.pwa.name`.
An application that wants its own declares it once:

```dart
@DVAppRoot()
Widget _appRoot(BuildContext context, DVAppParts parts) => MaterialApp.router(
      title: 'Acme',
      theme: AcmeTheme.light,
      darkTheme: AcmeTheme.dark,
      routerConfig: parts.router,
      locale: parts.locale,
      localizationsDelegates: parts.localizationsDelegates,
    );
```

`DVAppParts` carries what the root must not drop: the router, the locale and
its delegates, the theme mode, and the builder Dartvel wraps around every route
(boot-failure page, offline banner, background-task tray, Studio's editor
overlay where mounted). A root that ignores `parts.router` is a build error
(`DV-RUN-006`), because an application whose root does not use the generated
router has every route generated and none reachable.

The same `@DVAppRoot` is used by snapshot-rendered home widgets, so a widget
picks up the application's theme rather than Flutter's default.

## Plain `runApp` still works

A Dartvel application is a normal Flutter application, so this keeps working:

```dart
void main() => runApp(MyApp());   // MyApp uses createDartvelRouter()
```

What it cannot have is the work that must happen before the first frame. The
first time the generated router builds while `DV.lifecycle.app` is still
`uninitialized`, Dartvel performs the parts of phases 1 and 3 that are safe to
do late — logging, configuration, secrets, providers, modules, `@DVBoot`
functions — moves the lifecycle to `ready`, and reports **once**
(`DV-RUN-001`) which features are inactive and why:

- crash capture before the first frame (errors raised earlier are Flutter's
  default handling);
- the single-instance lock and argument forwarding;
- workspace restore before the first frame, and declared kiosk windows at boot;
- dual-mode terminal selection;
- the watchdog's start-up arm.

Nothing fails. The features above report their own degradation codes when used,
as every other unavailable capability does.

`dartvel doctor` suggests the one-line change, and `dartvel migrate-code`
offers a printed-then-applied rewrite of the common shape
(`runApp(createDartvelApp())` → `DV.run(args)` plus an `@DVAppRoot` holding the
old `MaterialApp`). It is never applied on `dartvel init`: adoption writes
nothing over a project's own code.

## Generated entry points

A process started by the operating system for a reason other than "the user
opened the app" does not enter through `main`. Dartvel generates the entry
functions those starts need, into `dartvel_client`, one per surface the project
uses:

```dart
// generated — dartvel_client/entries.g.dart
@pragma('vm:entry-point')
Future<void> dartvelHomeWidgetEntry(List<String> args) =>
    DVRuntime.enter(DVEntry.homeWidget(DVHomeWidgetRequest.fromArgs(args)));

@pragma('vm:entry-point')
Future<void> dartvelBackgroundEntry(List<String> args) => ...;

@pragma('vm:entry-point')
Future<void> dartvelPushEntry(List<String> args) => ...;
```

`DVRuntime.enter` is the body of `DV.run` with the entry already decided; it is
the framework's and not in the application barrel. A generated entry and `main`
therefore cannot boot differently: there is one sequence, entered from more
than one door.

| Entry | Generated when the project uses | Started by |
|---|---|---|
| `dartvelHomeWidgetEntry` | `@DVHomeWidget` | a widget refresh (Android receiver/WorkManager, iOS background refresh, Windows widget provider) |
| `dartvelBackgroundEntry` | `@DVClientCron`, offline models, OTA prefetch | WorkManager, `BGTaskScheduler`, a desktop or embedded timer |
| `dartvelPushEntry` | push with data messages | FCM data message, APNs background notification, Web Push in a service worker |
| `dartvelWorkerEntry` | `DV.Workers` | the worker pool, per isolate or web worker |
| `dartvelEmbeddedEntry_<project>` | `--brownfield` | the host application |

Entries for surfaces a project does not use are not generated, and the native
glue that would start them is not written.

---

## End to end, per target

The table is the contract. Each row says which entries a target has, what
`DV.run` brings up for an `app` entry, and the label it carries.

| Target | Entries | `app` surface | Label |
|---|---|---|---|
| Android, Fire OS | app, homeWidget, background, push, worker, embedded | `FlutterActivity`, engine group shared with headless entries | `Supported with limitations` |
| iOS, iPadOS | app, background, push, worker, embedded; home widgets produced by the app (below) | `FlutterAppDelegate` | `Supported with limitations` |
| macOS, Windows, Linux | app, terminal (opt-in), background (while running), worker, embedded | native window; single-instance; tray-resident exit policy | `Supported with limitations` |
| Web (JS, wasm), static and web-server | app, push (service worker), worker | `<flutter-view>`, path URL strategy, takeover from server HTML | `Supported with limitations` |
| Browser extensions | app (popup, options, side panel), background | extension page | `Experimental` |
| VS Code | app (webview) | `VSCodeWebViewHelper` | `Experimental` |
| `<desktop>-cli`/`-tui`, `fuchsia-cli` | terminal, worker | terminal embedder | `Experimental` |
| Server, CLI (pure Dart) | server, command, worker | none — no UI runtime linked | `Supported` |
| Tizen, webOS, tvOS | app, worker | vendor embedder, remote-key mapping | `Experimental` |
| Sony eLinux bundle and images | app, background, worker | DRM/EGL fullscreen, systemd supervision | `Experimental` |
| Horizon OS, visionOS, Android XR | app (panels), plus Android's entries on Horizon | as the base platform | `Experimental` |
| Wear OS | app, homeWidget (Tiles), background, push | `FlutterActivity` | `Experimental` |
| watchOS | complications only (below) | none — no Flutter embedder | `Unsupported` → complications |
| Microcontrollers (`mcu`) | app, compiled to firmware — see *Microcontrollers* | LVGL display, drawn by generated firmware | `Partial` |

### Android and Fire OS

- **App.** `MainActivity` is the `FlutterActivity` Flutter generates. Its engine
  is created from a `FlutterEngineGroup` that the generated `Application` class
  owns, so a headless entry that already ran in the process (a widget refresh,
  a push) and the app share the group: the second engine costs a few megabytes
  rather than a whole engine, and the shared store, the offline store and the
  device key are already open.
- **Process started without an activity.** Android starts the process for a
  broadcast receiver, a `WorkManager` job or an FCM service with no activity.
  The generated Java/Kotlin glue starts an engine from the group at the right
  generated entry, passes the request as arguments, waits for the entry's
  future, and returns. `main` is never called, and no window is created.
- **Budget.** A `WorkManager` worker has minutes; a broadcast receiver has
  seconds. Receivers never run Dart directly; they enqueue unique work, so a
  slow boot is a late widget, never an ANR.
- **Lifecycle.** `AppLifecycleListener` maps to `backgrounded`, `suspended`,
  `resuming`. The process being killed in the background is not
  `shuttingDown`; nothing can run then, which is why log files and the offline
  queue are written as they go rather than at exit.
- **Deep links** arrive as the initial route, before the first frame, through
  the generated router; middleware runs before presentation as for any route.

### iOS and iPadOS

- **App.** `FlutterAppDelegate`, with the engine created by the generated
  delegate subclass so it can also start headless engines.
- **Background.** `BGTaskScheduler` refresh and processing tasks launch the
  app's own process; the generated Swift handler starts an engine at
  `dartvelBackgroundEntry` and completes the task when the future does. The
  system decides when, and may never; *Scheduling* already says so, and
  `DV.Schedules.capability(...)` reports it.
- **Push.** A background (content-available) notification starts the same way
  at `dartvelPushEntry`. A *notification service extension* is a separate
  process with a small memory limit and no Flutter engine; Dartvel does not run
  Dart there. Rich-notification mutation, where used, is generated Swift.
- **Home widgets** run in a WidgetKit extension that cannot host Flutter. The
  app produces their frames; see *Home Widgets*.
- **Scenes.** A second `UIScene` (iPad multi-window) is another engine in the
  group entering as `app` with its route; it does not boot the process again.

### macOS, Windows, Linux

- **Arguments are routed, not parsed by the application.** A deep link, a
  `dartvel://` URL, a file opened through a file association, or `--tui` reach
  `DV.run(args)`; `DV.run` turns a link or a file into
  `DV.Window.open(..., external)` after `ready`, so it is idempotent by URL as
  *Multi-Window* specifies.
- **Single instance** (`windowing.singleInstance`, default on) is taken in
  phase 2. A second launch forwards its arguments to the running process and
  exits before Flutter initializes. Without `DV.run` there is no lock, and
  `DV-RUN-001` says so.
- **Exit policy.** Under `exit: explicit` (tray-resident) closing the last
  window hides it; `DV.run`'s future completes only on application quit.
- **Launch at login** passes `--dartvel-launched-at-login`, so an application
  can start minimized to the tray; the flag is reported by
  `DV.Platform.launchedAtLogin` and never reaches page code as an argument.
- **Background** on desktop means "while the process runs" (*Scheduling*); no
  launch agent or service is installed.

### Web — static, web-server, PWA

- `main()` takes no arguments: `void main() => DV.run();`.
- Phase 1 sets the path URL strategy before the router exists, so a reload at
  `/users/42` is `/users/42` and not `/#/users/42` — the canonical-URL rule
  *Routing* depends on.
- **Takeover from server HTML.** A static or web-server page already contains
  the route's HTML, its semantic fallback and, where used, its server state.
  `DV.run` reads that embedded state in phase 5, so the first Flutter frame is
  the same page with the same data and the route's data is not fetched twice.
  `ready` is when Flutter has taken over; the fallback and the splash are
  removed then, not before.
- **Service worker** registration is phase 7. The service worker is generated
  JavaScript (`push`, `notificationclick`, precache), not a Dart entry; a push
  that must run Dart while no tab is open is out of reach on the web and
  `DV.Schedules.capability` says so.
- **Multi-view** (brownfield on the web): each host element is a view of one
  engine, entering as `embedded`; `DV.run` is called once per engine, not per
  element.

### Browser extensions and VS Code

- Popup, options and side-panel pages are `app` entries with their own route.
- A Manifest V3 background service worker cannot host Flutter. When a project
  uses extension background work, the generator compiles `dartvelBackgroundEntry`
  with `dart2js` **without Flutter** into the background script, so the same
  `@DVBoot` functions and the same headless subsystems (storage, model sync,
  jobs) run there. Designed and unverified.
- VS Code's webview is an `app` entry; the extension host is TypeScript
  generated by the fork and is not a Dart entry.

### Terminal

- A `-cli`/`-tui` build resolves to `terminal` in phase 2 because it contains no
  GUI backend.
- A dual-mode build (`dartvel.terminal: true`) resolves in phase 2 too:
  `--tui` → terminal; otherwise GUI; no display available → the prompt from
  *Terminal Rendering*, asked before any engine is started. Doing this anywhere
  later would mean initializing a GUI that cannot open.
- `DV.Platform.surface` reports the result; `DV.Window.open` navigates, as that
  section specifies.

### Server and command-line programs

`DV.run` is in `dartvel_core`, so a project with no pages links no Flutter.
The server's `main` is generated and is the same line:

```dart
// generated backend entry
void main(List<String> args) => DV.run(args);
```

- **Role** comes from `DARTVEL_ROLE` (`web`, `worker`, `cron`; unset is `all`),
  so the same binary runs as the web process, a queue worker or the cron
  process, as *Deployment* already states.
- **Phase 3** opens the database (creating `dartvel_data/data.db` with every
  model's table on a first SQLite run), opens the configured cache store and
  refuses to start when it cannot (`DV-CACHE-004`), reads the webhook, tracing
  and logging configuration, and mounts the admin.
- **`ready`** is when the listener accepts, and it is what the deploy health
  gate in *Backend Release Management* waits for — not a process that exists.
- **`SIGTERM`/`SIGINT`** move to `shuttingDown`: stop accepting, drain in-flight
  requests up to a declared grace, let running jobs reach a checkpoint, flush,
  exit 0. A second signal exits immediately.
- **Commands.** A pure Dart project with `@DVCommand` functions gets a CLI from
  the same line: `DV.run(args)` dispatches `reindex acme --dry-run` to the
  typed command, with generated `--help`, and exits with the command's status.

**Prerequisite.** *Outbound HTTP* notes that "there is no backend `DV` facade
yet" and backend code writes `const DVHttp()`. `DV.run` needs that facade: one
`DV` in `dartvel_core` with every non-UI subsystem, which the Flutter facade
extends. The application keeps importing one barrel; which `DV` it gets follows
from what the project uses.

### Television, embedded and kiosk

- **Sony eLinux images** start the bundle from a systemd unit at boot; `DV.run`
  arms the watchdog in phase 1, applies the declared kiosk policy in phase 3,
  and opens kiosk windows in phase 5, so there is no frame of unlocked UI.
  The restart-loop detection in *Kiosk Mode* reads the boot records phase 1
  writes.
- **Tizen and webOS** map the vendor application framework's lifecycle
  (pause/resume/terminate) onto `DVAppLifecycle`; remote keys are bound to the
  page's D-pad handling before the first frame.
- **tvOS** is iOS's sequence without widgets or push background.

### Headsets

Panels are ordinary `app` windows; volumes and immersive spaces are window
kinds (*XR*). `DV.run` adds nothing for them beyond the base platform's
sequence. On Horizon OS the Android entries apply unchanged.

### Watches

- **Wear OS** runs Flutter: the app is an `app` entry; **Tiles** are home
  widgets lowered to ProtoLayout (*Home Widgets*).
- **watchOS** has no Flutter embedder. Dartvel does not ship a watchOS app.
  Complications are WidgetKit, so the iPhone app produces their frames and the
  watch shows them, exactly as for iOS home widgets.

### Brownfield

The host owns the process, so it never calls `main`. It starts an engine at
`dartvelEmbeddedEntry_<project>`, which enters as `embedded`:

- no single-instance lock, no exit policy, no windows of its own;
- lifecycle follows the host's view lifecycle, delivered through the generated
  host API;
- each project in an engine group boots its own runtime in its own isolate,
  as *Brownfield* specifies; they share the engine machinery, not state.

### Development builds

A `--profile development` build compiles a generated profile-hooks file that
`DV.run` calls in phase 3: the dev menu and the pairing state. A release build
compiles the empty version of the same file, so nothing reachable from `DV.run`
imports `dev_client.dart` in release — the rule *Dev Client* already depends
on.

### Tests

`DVTest` boots with `DVEntry.test()` and explicit fakes, running phases 1, 3
and 4 so `@DVBoot` functions are covered by tests. `DV.run` itself inside a test
binding is `DV-RUN-002`. `DVTest.boot(entry: DVEntry.homeWidget(...))` runs a
headless entry's sequence, which is how a widget's refresh is tested without a
device.

---

## Microcontrollers

Stability: `Draft` · Status: `Partial`

A microcontroller target runs **the application itself**, compiled rather than
executed. Dart's runtimes — the VM and AOT alike — need an operating system with
virtual memory and megabytes of RAM, and there is no Dart target for Cortex-M,
ESP32 or RISC-V microcontrollers, so `dartvel build mcu` does not ship a Dart
runtime to the board: it compiles the application's entry, pages and signals to
Rust firmware. A board that runs Linux (Cortex-A: a Raspberry Pi, an i.MX
module) is not a microcontroller; it is an embedded Linux target and `DV.run`
runs on it as it does on any desktop.

`main` is the same one line:

```dart
void main(List<String> args) => DV.run(args);
```

and on an `mcu` build that line becomes the firmware's `main`. The boot is the
sequence above, lowered to what a microcontroller has:

| Phase | On a microcontroller |
|---|---|
| 1 | hardware watchdog armed; log sink (serial/RTT) opened; generated configuration compiled in |
| 3 | board drivers and storage (flash key-value) brought up from the board profile |
| 4 | `@DVBoot` functions that the compiler can lower; any other is a build error |
| 5 | LVGL started; the first route's screen built |
| 6 | `ready` when the first frame has been flushed to the display |
| 8 | there is no shutdown; power loss is the only exit, so state is written as it changes |

The only entry is `app`. There is no home widget, push, background or worker
entry on a microcontroller, and asking for one is `DV-RUN-005`.

- **Pages are built entirely from Dartvel primitives** — `DVBox`, `DVText`,
  `DVModifier` and signals — and compile to Rust that draws with LVGL through
  Rust bindings (`esp-hal`/`esp-idf-svc` on ESP32, Embassy on nRF, RP and STM32).
  Routes become screens, signals become firmware state, derived signals become
  functions, and `onTap` becomes an LVGL event. Anything else in a page is a
  build error naming the file and line, never a blank screen.
- **Rust everywhere.** All firmware output is Rust; the first release of this
  target emitted C, and that output is retired (owner's decision, 12 Oct 2026).
  Custom drivers are Rust under `native/mcu/` and are linked through bindings,
  never edited into generated code.
- **Boards.** The first board is the ESP32-S3-BOX-3. A board is a profile (chip,
  display, touch, flash, pins) under `dartvel.mcu.board` in `pubspec.yaml`; the
  build checks the application against it before generating anything.
- **Firmware updates** are signed bundles delivered through the same channels
  and staged rollout as OTA patches.

```yaml
dartvel:
  mcu:
    board: esp32-s3-box-3   # the default
```

```bash
dartvel build mcu
dartvel doctor --target mcu
```

Under *Free and paid targets* this is a paid target, because it is not a
Flutter-supported platform.

| Code | Reason | Level |
|---|---|---|
| `DV-MCU-001` | code reachable from a page or `@DVBoot` function cannot be lowered to firmware (the call is named) | build `error` |
| `DV-MCU-002` | the board profile lacks a capability the application uses (display, touch, storage) | build `error` |
| `DV-MCU-003` | the firmware does not fit the board's flash or RAM; the largest screens are listed | build `error` |
| `DV-MCU-004` | a page uses a widget that is not a Dartvel primitive and cannot be drawn with LVGL | build `error` |


## Configuration

Almost everything `DV.run` does is configured by the section it belongs to
(windowing, kiosk, terminal, logging, crash reporting). It reads one block of
its own:

```yaml
dartvel:
  run:
    bootBudget: 800ms        # phases 1–5 for an app entry, on the profile device
    headlessBudget: 5s       # phases 1–6 for a headless entry
    shutdownGrace: 20s       # server drain
```

## Diagnostics

| Code | Reason | Level |
|---|---|---|
| `DV-RUN-001` | the app started with Flutter's `runApp`; features that need work before the first frame are inactive (listed) | `info`, once |
| `DV-RUN-002` | `DV.run` was called again in an isolate that already ran it, or inside a test binding | `warning` |
| `DV-RUN-003` | boot exceeded its budget; the slowest phase and `@DVBoot` function are named | `warning` |
| `DV-RUN-004` | a boot phase failed; the lifecycle is `failed` and the phase is named | `error` |
| `DV-RUN-005` | an entry was requested that this target has no surface for | build `error` |
| `DV-RUN-006` | an `@DVAppRoot` does not use `parts.router` | build `error` |
| `DV-RUN-007` | a `@DVBoot` function awaits the network before the first frame | `warning` (analyze) |
| `DV-RUN-008` | a headless entry exceeded the platform's time limit and was stopped | `warning` |

## Deliberately absent

- **`DV.runApp`, `DV.runServer` or any second entry function.** One function
  reads what it is in.
- **Parameters on `DV.run` for the root widget or boot work.** Generated entry
  points never see `main`; customization that only `main` could see would make
  them boot differently.
- **Dartvel owning `main.dart`.** It is the application's file. Brownfield hosts
  and adopted projects own their entry, and a framework that regenerated it
  would be overwriting somebody's code.
- **A Dart runtime on a microcontroller.** The application is compiled to Rust
  firmware instead; covered above.
- **A boot that waits on the network.** Covered above.

---

# Part 2 — Replacement for *Home Widgets*

# Home Widgets

Stability: `Draft` · Status: `Partial`

A home-screen or lock-screen widget is a page-sized function shown by the
operating system outside the app. It is declared on a Dartvel widget:

```dart
@DVHomeWidget(
  sizes: <DVHomeWidgetSize>[DVHomeWidgetSize.small, DVHomeWidgetSize.medium],
  refresh: Duration(minutes: 30),
)
@DVFunctionalWidget()
Widget _stepsWidget(BuildContext context) {
  final DVSignal<int> steps = context.shared<int>('widget.steps.today', 0);
  return DVBox.list(<Widget>[
    DVText('Steps'),
    DVText('${steps.value}').modifier(heading),
  ]).modifier(DVModifier().onTap(DV.Navigation.to(DVRoutes.activity)));
}
```

## A widget shares state with the app, not its widget tree

The previous text promised a widget that "shares widget tree and state with the
parent app". On no platform does it:

- **iOS and macOS** run widgets in a WidgetKit extension: a separate process
  that renders SwiftUI, with a small memory limit and no Flutter engine.
- **Android** updates widgets from a broadcast receiver, usually with no engine
  and no activity running.
- **Windows** asks a widget provider, a separate COM activation of the app.

So a widget is **computed by Dart, displayed by the platform**, and the two
communicate through stored state.

## How a frame is made

A **frame** is what a widget shows at one size: either a *lowered tree* or a
*snapshot*.

1. A refresh is requested: the refresh interval elapsed, a shared key the widget
   reads changed, the app called `DV.HomeWidgets.refresh(...)`, or the user
   tapped an action.
2. Dart runs the widget function, through `dartvelHomeWidgetEntry` when the app
   is not running, or in the running app otherwise. The function is built in an
   offscreen view at each declared size, light and dark, with `@DVAppRoot`'s
   theme.
3. The result is stored as a frame under `widget.<id>.<size>.<mode>` in the
   shared store's **app-group scope** (below).
4. The platform's widget, generated natively, reads the frame and draws it.

### Lowered, by default

When the function is built only from Dartvel primitives — `DVBox` (list, row,
stack), `DVText`, `DVImageView` — and the modifiers the platform can express
(padding, colors, rounded corners, alignment, `onTap`), the generator **lowers**
it: the built tree is serialized and a generated native renderer draws it.

| Platform | Lowered to |
|---|---|
| Android | Jetpack Glance |
| iOS, iPadOS, macOS, watchOS complications | SwiftUI in WidgetKit |
| Wear OS Tiles | ProtoLayout |
| Windows 11 Widgets Board, PWA widgets | Adaptive Cards |

A lowered widget is crisp at every scale, follows the system's dynamic type and
dark mode, and its actions are real controls.

### Snapshot, when it cannot be lowered

A function that uses any other widget — a chart, a custom painter, a Flutter
`Card` — is **rendered to an image** at each size and mode. It is shown as a
picture: it does not reflow, does not follow dynamic type, and its only action
is the widget's own tap target. `DV-WIDGET-001` names the widget that forced the
snapshot, so it is a decision rather than a surprise.

## Actions

`onTap` (and `onPressed`) inside a home widget lowers to one of three things,
decided at build time:

- **Open a route.** `DV.Navigation.to(DVRoutes.activity)` becomes a deep link
  that launches the app at that route; middleware and policies run as for any
  link. This is the only action a snapshot supports.
- **Call a backend function.** `DVHomeWidgetAction.call(logWater, args)` is
  performed by a generated native client (Kotlin, Swift, C#) with the session
  token from the shared secure store — no Dart engine needed, which is what
  makes it possible from an iOS extension. After it returns the widget is
  refreshed.
- **Set a shared key.** `DVHomeWidgetAction.set('widget.timer.running', true)`.
  A text or visibility value **bound** to a shared key (`DVText.bound(key)`) is
  re-drawn natively at once, so a toggle feels immediate on every platform
  without waiting for Dart.

There is no action that runs arbitrary Dart inside the widget's process,
because on iOS and Windows there is no Dart there.

## State: the app-group scope

Widgets read state written by the app. The shared store in *Multi-Window* gains
one scope:

```dart
context.shared<int>('widget.steps.today', 0)       // in a widget function
DV.Window.shared.set('widget.steps.today', DVJsonNumber(8412));  // in the app
```

- **Keys under `widget.*` live in the app-group scope.** On Apple platforms that
  is the App Group container's `UserDefaults` suite, readable by the extension;
  on Android, the app's own `SharedPreferences`, readable by the receiver; on
  Windows, the packaged app's local settings.
- **Encryption still applies.** The application key that seals the store is
  placed in a shared keychain access group on Apple platforms, so the extension
  can decrypt frames and bound values; elsewhere the key is already reachable by
  the widget's process.
- `dartvel build` generates the App Group, the keychain access group and the
  entitlements for both targets. A widget that reads a key outside `widget.*`
  is a build error (`DV-WIDGET-004`), because the extension would read nothing.

## Refresh is a request, not a clock

Like a client schedule, `refresh:` asks; the platform decides.

| Platform | What "every 30 minutes" becomes |
|---|---|
| Android | `updatePeriodMillis` has a 30-minute floor; Dartvel schedules `WorkManager` work instead and refreshes on shared-key change while the app runs |
| iOS, iPadOS, macOS | a daily refresh budget the system decides; the app produces a **timeline** of future frames in advance (`timeline:` on the annotation), and refreshes on shared-key change, background refresh and background push |
| Windows | the provider's update requests, plus shared-key change while the app runs |
| Wear OS Tiles | the Tile's freshness interval |

`DV.HomeWidgets.capability(id)` reports the granularity per target, and
`DV-WIDGET-002` reports a refresh coalesced to it.

## Launching back

A tap opens the app at a route. Nothing navigates "back to the widget": the
widget is on the home screen, and returning there is the system's back or home
gesture. The previous sentence promising otherwise is removed.

## Platform matrix

| Target | Mechanism | Label |
|---|---|---|
| Android, Fire OS | `AppWidgetProvider` + Glance; headless engine via `WorkManager` | `Supported with limitations` |
| iOS, iPadOS | WidgetKit extension (generated), frames from the app | `Supported with limitations` |
| macOS | WidgetKit, frames from the app | `Experimental` |
| Windows 11 | widget provider in the packaged (MSIX) app, Adaptive Cards | `Experimental` |
| Web (installed PWA) | manifest `widgets` with Adaptive Card templates where the browser and OS support them | `Experimental` |
| Wear OS | Tiles via ProtoLayout | `Experimental` |
| watchOS | complications, frames from the iPhone app | `Experimental` |
| Linux, television, embedded, terminal, extensions | no home-widget surface | `Unsupported` — the widget is excluded from the build |

An `Unsupported` target excludes the widget and its generated glue from the
artifact and reports `DV-WIDGET-005` once at build, rather than failing a
cross-platform build over a surface one target does not have.

## Live notifications

`@DVHomeWidget.liveNotification` (Roadmap Track C) uses the same frames,
lowering, bound keys and actions: Live Activities and the Dynamic Island on iOS,
ongoing notifications on Android, their equivalents elsewhere.

## Diagnostics

| Code | Reason | Level |
|---|---|---|
| `DV-WIDGET-001` | a home widget uses a widget that cannot be lowered; it is shown as a snapshot | `warning` |
| `DV-WIDGET-002` | the requested refresh is finer than the target allows; coalesced | `info` |
| `DV-WIDGET-003` | a frame could not be produced within the headless budget; the previous frame stays | `warning` |
| `DV-WIDGET-004` | a widget reads a shared key outside the app-group scope | build `error` |
| `DV-WIDGET-005` | a target has no home-widget surface; the widget is excluded from its build | `info` |
| `DV-WIDGET-006` | an action needs a session and none is available in the shared secure store | `warning` |

## Deliberately absent

- **Running Dart inside a widget extension.** iOS and Windows give it no room,
  and pretending otherwise is how widgets go blank.
- **A widget sharing the app's live widget tree.** State is shared; trees are
  not.
- **Arbitrary Flutter widgets drawn natively.** Lowering covers the primitives;
  everything else is a snapshot, and says so.

---

# Part 3 — Edits to other sections

| Section | Edit |
|---|---|
| *Project Structure* | Show `main.dart`: `void main(List<String> args) => DV.run(args);`. |
| *The Golden Path* | Same `main.dart` in "Create the project"; `dartvel create` writes it, `dartvel init` does not touch an existing one. |
| *Lifecycle Signals* | State that `DV.run` drives `DVAppLifecycle`; replace the `DV.lifecycle.app.listen(... booting ...)` example with `@DVBoot`, keeping the listener as an alternative. |
| *Platform* | Add `DV.Platform.entry`, `DV.Platform.args`, `DV.Platform.launchedAtLogin`. |
| *Crash Reporting and Release Health* | "the guarded zone" is `DV.run`'s; capture before the first frame needs `DV.run` (`DV-RUN-001`). |
| *Multi-Window* | Single-instance lock, restore-on-launch and declared kiosk windows are phases 2 and 5 of `DV.run`. Shared store gains the app-group scope for `widget.*` keys. |
| *Kiosk Mode* | Watchdog armed in phase 1; policy applied in phase 3; kiosk windows in phase 5. |
| *Terminal Rendering* | Dual-mode selection is performed in `DV.run` phase 2. |
| *Outbound HTTP* / *Backend* | Add the backend `DV` facade in `dartvel_core` as a prerequisite; retire "there is no backend `DV` facade yet" when built. |
| *Deployment* | The server binary's generated `main` is `DV.run(args)`; `ready` is the readiness the deploy gate reads. |
| *Backend Release Management* | Health gate waits for `ready`; drain uses `dartvel.run.shutdownGrace`. |
| *Scheduling*, *Mail and Notifications* | Client schedules and data pushes run through `dartvelBackgroundEntry` / `dartvelPushEntry`. |
| *Compute: Workers* | Worker isolates enter as `DVEntry.worker` with the minimal boot. |
| *Brownfield* | The per-project entrypoint is `dartvelEmbeddedEntry_<project>` entering `DV.run`'s sequence as `embedded`. |
| *Dev Client* | The dev menu is reached from the development-profile hooks `DV.run` calls; the release build compiles the empty hooks. |
| *CLI* | Add `dartvel build mcu`; `dartvel migrate-code` gains the `runApp(createDartvelApp())` → `DV.run` + `@DVAppRoot` rewrite (printed, then applied). |
| *Embedded, Television, and Extension Build Targets* | Add `mcu` to the target list and to the paid targets. |
| *Home Widgets* | Replaced by Part 2. |
| *Roadmap* | Track C item 4 points at the new *Home Widgets*. |
| `examples/basic_app/lib/main.dart` | Becomes the one line, with `createDartvelApp()` moved into an `@DVAppRoot` function if it is kept at all. |

---

# Part 4 — `docs/spec-status.json` entries

```json
[
  {
    "section": "Application Entry",
    "stability": "Draft",
    "status": "Designed",
    "evidence": [],
    "absent": "DV.run, DVEntry, the boot sequence, @DVBoot, @DVAppRoot, generated entry points, DV-RUN diagnostics"
  },
  {
    "section": "Microcontrollers",
    "stability": "Draft",
    "status": "Partial",
    "evidence": [],
    "absent": "Rust firmware output (the first release emitted C), the boot phases on the board, boards beyond the ESP32-S3-BOX-3"
  },
  {
    "section": "Home Widgets",
    "stability": "Draft",
    "status": "Partial",
    "evidence": ["<existing evidence paths, unchanged>"],
    "absent": "lowering to Glance/SwiftUI/ProtoLayout/Adaptive Cards; snapshots; app-group scope; native action clients; WidgetKit target; Windows provider; timelines"
  }
]
```

---

# Part 5 — Order of work

1. **Core.** The backend `DV` facade and `DV.run` in `dartvel_core`; `DVEntry`;
   lifecycle driven by the boot phases; the server's generated `main` switched
   to it; `SIGTERM` drain. Testable with no Flutter at all.
2. **Flutter app entry.** Zone and error hooks, `@DVBoot`, `@DVAppRoot`,
   `DV-RUN-001` for plain `runApp`, the boot-failure page; `dartvel create`
   writes the one line; the example is migrated.
3. **Desktop.** Single-instance with argument forwarding, restore before the
   first frame, kiosk windows, launch at login.
4. **Terminal.** Dual-mode selection in phase 2.
5. **Headless entries and Android widgets.** Entry generation; the engine group
   in the generated `Application`; `WorkManager` glue; Glance lowering and
   snapshots; background and push entries.
6. **Apple widgets.** WidgetKit target generation, App Group and keychain
   sharing, the SwiftUI renderer, timelines, native action client.
7. **Web.** Path URL strategy in phase 1, takeover from server state, PWA
   registration in phase 7, extension background via `dart2js`.
8. **Windows, Wear OS and watchOS widgets.**
9. **Microcontrollers.**

Each step lands as its own pull request with README, NEW_SPEC, site docs and
CHANGELOG updated together, and each claims only what it ships.

---

# Part 6 — Open questions

1. **`@DVBoot` and `@DVAppRoot` as annotations.** They keep `main` to one line
   and let generated entries share customization. The cost is two more
   generation inputs. Is that the right trade, or should `DV.run` take an
   `app:` parameter for the `app` entry only, accepting that headless entries
   cannot see it?
2. **Lowered by default.** Lowering is the better widget when it is possible;
   snapshots are the safety net. Should a project be able to force snapshots
   for a widget whose look must match the app pixel for pixel?
3. **Bound keys.** They are what make iOS actions feel immediate without Dart.
   They also add a small binding vocabulary to lowered trees. Keep, or ship
   widgets without immediate toggles at first?
4. **Microcontroller firmware language.** Rust (Embassy, `esp-hal`) fits the
   existing `native/` rule and memory safety; Zephyr/C reaches more boards.
   This proposal picks Rust. *(Decided: Rust everywhere, with bindings.)*
5. **Extension background in `dart2js`.** It gives extensions the same boot as
   every other entry, and it is unverified. Keep it in the first web step, or
   move it after the rest of the web work?