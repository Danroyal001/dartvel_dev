# dartvel_windowing

Real OS windows for Dartvel desktop applications.

In `dartvel_flutter`, `DV.Platform.window.open(route)` never fails. Where the
target cannot create a second window it navigates to the route instead and
reports why, so a call site does not have to know which platform it is on.
This package is what lets a desktop app open a real window instead: it
registers the `window.open`, `window.close` and `window.displays` bindings,
and `DVWindowHost` renders each open window's route in an OS window of its
own.

## Status

Unpublished (`publish_to: none`) and experimental. It is part of the
Multi-Window section of the specification, which is `Partial` in
[`docs/spec-status.json`](../../docs/spec-status.json).

What is built and tested:

- Registering the bindings flips `DVWindowingCapability.multiWindow` to true
  on desktop. The capability is gated on the binding being registered, not on
  the API being importable, so an app without this package reports false and
  degrades honestly.
- Opening a route produces a window with its own id rather than a degraded
  page, and the requested size and title reach the surface. A kiosk window is
  sized to the display it owns.
- Display enumeration through FFI: XRandR or Xinerama on Linux,
  `EnumDisplayMonitors` on Windows, `CGGetActiveDisplayList` on macOS. The
  Windows and macOS enumerations run in CI against the runner's own desktop.
- `DVWindowHost` holds every window until the first frame has been
  rasterized, and gives a degraded window no surface, since it is already
  showing as a page.
- Two windows from one process on Flutter 3.47.5 stable on Linux, under a
  real window manager (openbox) on software GL: an operator window on one
  monitor and a projector window fullscreen on the other, both rendering one
  widget tree, surviving moves, maximise and fullscreen toggles. Measured on
  2026-10-09 on a virtual two-monitor X server (Xorg's dummy driver with two
  RANDR outputs, and Xvfb), not on physical displays.
- A window opens on the display `DVWindowOptions.display` names, and
  `DVWindow.setFullscreen(true, on: hint)` fills that display. A display that
  is not there is refused, never "fullscreen wherever the window is". On
  Linux this goes through `gtk_window_fullscreen_on_monitor`, because
  Flutter's own `setFullscreen(display:)` ignores the display there; on
  Windows and macOS a fullscreen that names a display is refused until it is
  built for them.

- A window opened with `DVWindowOptions(takesFocus: false)` never takes the
  keyboard: on Linux its GTK window refuses input focus and is not focused on
  map, and nothing in its route can be focused (`ExcludeFocus`), on every
  platform. Measured on 2026-10-21 on the dummy-driver two-monitor X server
  with openbox: with the operator focused, a projector opened with
  `takesFocus: false` left `_NET_ACTIVE_WINDOW` and the X input focus on the
  operator, and keys typed before, after it opened and after clicking it all
  reached the operator's widgets; an ordinary projector (the control) took
  focus when it opened. Windows and macOS do not apply it yet and the window
  carries `DV-WINDOW-016`.

What is not settled:

- **Which Flutter it builds against.** The package uses Flutter's windowing
  API, which is `@internal`, behind a feature flag, and renamed between
  releases. It is written against Flutter 3.47.5 stable, the version Dartvel's
  CI pins. Master renames it further (`WindowController`, `Window`); the
  measurements are in
  [`docs/proposals/2026-09-multiwindow-stable-probe.md`](../../docs/proposals/2026-09-multiwindow-stable-probe.md).
- **Physical displays and GPUs.** Everything above ran on Mesa's software
  renderer. The window-manager crash it fixes is not specific to software GL
  (see below), but a GPU driver, a compositor and real projector hot-plugging
  have not been tried.
- **Tear-out** is not a handover. A tab torn out into a new window is
  rebuilt there from its route through `routeBuilder`; only the shared store
  crosses, not the tab's state.

This is kept out of `dartvel_flutter` so that Dartvel itself builds on any
channel, and an application opts into the channel-specific part by depending
on this package.

## Usage

Depend on it by path from a checkout of the repository:

```yaml
dependencies:
  dartvel_windowing:
    path: ../dartvel_dev/packages/dartvel_windowing
```

Mount `DVWindowHost` as the root, with `runWidget` in place of `runApp`.
`home` is what the app's own window shows. `routeBuilder` renders the route of
each window opened with `DV.Platform.window.open`:

```dart
import 'package:dartvel_windowing/dartvel_windowing.dart';
import 'package:flutter/material.dart';

import 'dartvel_client/dartvel_client.dart';

void main(List<String> arguments) async {
  await negotiateDartvelLaunch(arguments);
  runWidget(
    DVWindowHost(
      home: createDartvelApp(args: arguments),
      routeBuilder: (BuildContext context, DVRouteTarget route) =>
          MaterialApp(home: ProjectorScreen(route: route)),
    ),
  );
}
```

In a browser `DVWindowHost` shows `home` and nothing else, and
`DV.Platform.window.open` navigates to the route, so the same `main` builds
for the web.

With windowing enabled Flutter opens every `showDialog` as an OS window of
its own, sized to its content. Use `showInWindowDialog` for a dialog that
stays in the window that asked, as it does on every other target.

An opened window is a `View` beside the home window rather than inside it,
so what `routeBuilder` returns has nothing above it: no `MaterialApp`, no
theme, no `Directionality`. Give it what the route needs. Both windows are in
one widget tree, so a signal or a `DV.global` read in both is the same state,
not a protocol between windows.

Then open a window from anywhere, with a generated route:

```dart
final DVWindow projector = await DV.Platform.window.open(
  DVRoutes.projector,
  options: const DVWindowOptions(title: 'Projector', size: Size(1280, 720)),
);
```

A projector, a stage display or any other output the operator never types
into is opened with `takesFocus: false`, so a keystroke meant for the
operator's window (Space to take, an arrow for the next slide) never lands
in it:

```dart
await DV.Platform.window.open(
  DVRoutes.projector,
  options: const DVWindowOptions(title: 'Projector', takesFocus: false),
);
```

Opening a route a window already shows returns that window rather than a
second one, unless `DVWindowOptions(duplicate: true)` says otherwise. A window
opened without a size gets 1280 by 720.

Two Linux traps are handled here so that no application meets them:

- **The windowing flag.** Flutter's binding picks its windowing owner when it
  is initialized, before any application code, so setting
  `isWindowingEnabled` afterwards changed nothing and every window threw
  "Windowing APIs are not enabled" on stable. `DVWindowHost` installs the
  platform owner when it enables the flag.
- **The window-manager crash.** When a second Flutter view is realized,
  Flutter's Linux embedder leaves its EGL context current on the GTK main
  thread. GTK's next paint makes GDK's GLX context current on that thread,
  libglvnd refuses to mix EGL and GLX on one thread, raises `BadAccess` on
  `X_GLXMakeContextCurrent`, and GDK ends the process. A window manager makes
  that paint come first (reparenting, configure, expose), which is why two
  windows survived a bare X server and died under openbox. libglvnd is how
  Mesa and NVIDIA both ship, so this is not a software-GL quirk.
  `DVWindowHost` releases the context right after creating each window; Dart
  runs on the GTK main thread on Linux, and the engine makes its context
  current again whenever it uses it.

A window cannot be created before the first frame has been rasterized:
creating one earlier ends the process with an X `BadAccess` rather than
throwing. `DVWindowHost` handles that. A window opened before then is held
and created once the first frame is on screen. The bindings are registered
when the host is mounted, so an `open()` that runs before `runWidget` finds
no binding and degrades to navigating.
