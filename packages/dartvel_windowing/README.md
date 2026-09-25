# dartvel_windowing

Real OS windows for Dartvel desktop applications.

In `dartvel_flutter`, `DV.Platform.Window.open(route)` never fails. Where the
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

What is not settled:

- **Which Flutter it builds against.** The package uses Flutter's windowing
  API, which is `@internal`, behind a feature flag, and renamed between
  releases. The code is written against Flutter 3.44.5, the version Dartvel's
  CI pins, and it does not compile against Flutter 3.47.5, where
  `RegularWindowController` takes `size` instead of `preferredSize`. The
  measurements in
  [`docs/proposals/2026-09-multiwindow-stable-probe.md`](../../docs/proposals/2026-09-multiwindow-stable-probe.md)
  found master's API renamed further (`WindowController`, `Window`).
- **Two windows on screen at once.** On Flutter 3.44.5 stable on Linux the
  embedder presents one view per engine, the most recent: a window opened
  after the first frame renders, and the app's own window goes black. On
  master, measured on 2026-09-01, two windows on one engine both render and
  share one widget tree. The probe has the numbers.
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
each window opened with `DV.Platform.Window.open`:

```dart
import 'package:dartvel_windowing/dartvel_windowing.dart';
import 'package:flutter/material.dart';

import 'dartvel_client/dartvel_client.dart';

void main(List<String> arguments) async {
  await negotiateDartvelLaunch(arguments);
  runWidget(
    DVWindowHost(
      home: createDartvelApp(arguments: arguments),
      routeBuilder: (BuildContext context, DVRouteTarget route) =>
          MaterialApp(home: ProjectorScreen(route: route)),
    ),
  );
}
```

An opened window is a `View` beside the home window rather than inside it,
so what `routeBuilder` returns has nothing above it: no `MaterialApp`, no
theme, no `Directionality`. Give it what the route needs. Both windows are in
one widget tree, so a signal or a `DV.global` read in both is the same state,
not a protocol between windows.

Then open a window from anywhere, with a generated route:

```dart
final DVWindow projector = await DV.Platform.Window.open(
  DVRoutes.projector,
  options: const DVWindowOptions(title: 'Projector', size: Size(1280, 720)),
);
```

Opening a route a window already shows returns that window rather than a
second one, unless `DVWindowOptions(duplicate: true)` says otherwise. A window
opened without a size gets 1280 by 720.

A window cannot be created before the first frame has been rasterized:
creating one earlier ends the process with an X `BadAccess` rather than
throwing. `DVWindowHost` handles that. A window opened before then is held
and created once the first frame is on screen. The bindings are registered
when the host is mounted, so an `open()` that runs before `runWidget` finds
no binding and degrades to navigating.
