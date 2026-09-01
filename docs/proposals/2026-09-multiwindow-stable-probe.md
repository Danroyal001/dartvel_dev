# Multi-Window on Flutter stable — what actually happens

**Date:** 2026-09-01 · **Flutter:** 3.44.5 stable, engine `d3a3293399` ·
**Host:** Ubuntu 24.04, Xvfb, Mesa llvmpipe

`docs/proposals/2026-08-multiwindow.md` labels the desktop rows *Experimental*
because Flutter's windowing API is behind a flag. That label is right, but it
does not say **where the wall is**, and the difference matters: a flag that is
merely off can be turned on, whereas an embedder that cannot present a window's
layers cannot be worked around from Dart.

This is the measurement. It was run because a projection application — an
operator window on one display, output full-screen on a projector — is the
first Dartvel use case that a second window is not optional for.

## What is present on stable, and what is not

| | on stable 3.44.5 |
| --- | --- |
| Framework API (`RegularWindowController`, `RegularWindow`, `WindowingOwner`, `WindowingOwnerLinux`) | **present**, in `package:flutter/src/widgets/_window*.dart` |
| Engine symbols (`fl_view_new_for_engine`, `fl_view_new_sized_to_content`, `fl_view_get_id`, `fl_view_monitor_new`, `fl_window_monitor_new`) | **present** and exported by `libflutter_linux_gtk.so` |
| `flutter config --enable-windowing` | **listed**, and setting it reports success |
| The flag actually reaching the app | **no** |
| A Dart-created window that survives | **no** |

The config setting is inert on stable, and `features.dart` says why:

```dart
const windowingFeature = Feature(
  name: 'support for windowing on macOS, Linux, and Windows',
  configSetting: 'enable-windowing',
  runtimeId: 'windowing',
  master: FeatureChannelSetting(available: true),   // master only
);
```

Only `master` declares `available: true`, so on stable
`featureFlags.isEnabled(windowingFeature)` is false, the tool never adds
`--dart-define=FLUTTER_ENABLED_FEATURE_FLAGS=windowing`, and
`isWindowingEnabled` is false at runtime. The tool also refuses the define when
passed by hand, naming `flutter config` as the way to set it — which on stable
cannot set it.

**The flag is not the wall.** `isWindowingEnabled` is a mutable top-level
`bool`, so an app can assign it before touching the API. Doing that gets past
every framework guard: controllers construct, `runWidget` returns, and X11
shows the windows being created. The wall is one layer down.

## The measurement

Four builds of the same app, identical Xvfb and Mesa environment, sampled every
five seconds for twenty-five seconds. `FL_IS_COMPOSITOR` counts
`fl_compositor_present_layers: assertion 'FL_IS_COMPOSITOR(self)' failed` on
stderr.

| probe | Dart-created windows | `FL_IS_COMPOSITOR` failures | survives 25s |
| --- | --- | --- | --- |
| `runApp`, no windowing API | 0 | **0** | **yes** |
| `runWidget` + 1 `RegularWindow` | 1 | 1 | no, dies ~2s |
| implicit `View` + 1 `RegularWindow` | 1 | 1 | no, dies ~2s |
| `runWidget` + 2 `RegularWindow` | 2 | 2 | no, dies ~2s |

One compositor failure per Dart-created window, exactly. The control rules out
the environment: the same binary, the same display, the same software GL, with
`runApp` instead of `runWidget`, ran the full twenty-five seconds with a mapped
1280x720 window and produced neither error.

A `BadAccess` GLX error follows each run, and it is a consequence rather than
the cause — the compositor assertion is logged 117 ms earlier, and the control
produces neither.

## What this means

`fl_view_new_for_engine` creates the view, and nothing on the embedder side
binds a compositor to it. That is not reachable from Dart, from an FFI binding,
or from anything Dartvel can write. **`window.open` cannot be honestly
registered on Linux against this engine**, and `DVWindowingCapability.detect`
is right to gate `multiWindow` on the binding existing rather than on the API
being importable.

The third probe is worth stating separately, because it was the most promising
theory and it is wrong: giving the implicit view its own content, so the
runner's own window is not left empty, does not help. The failure is attached
to the *new* view, not to the implicit one.

## A second view is the wrong unit. A second engine works.

Two further probes settle it.

**Creating the window after the first frame changes the outcome.** Every probe
above built its controllers in `main()`, before `runWidget`, when the engine is
not yet up. Deferring creation to `addPostFrameCallback` produces a real window
that renders: `MEDIA-BITS-PROJECTOR`, 1280x720, white text on black, and the
process survives past twenty-five seconds with no `BadAccess` at all.

It also exposes the actual limit. The **implicit view went black** at the same
moment. Adding a third view repeats it: with implicit + operator + projector,
only the projector renders and the other two are black, with two
`FL_IS_COMPOSITOR` failures rather than one.

| views | renders | black | `FL_IS_COMPOSITOR` |
| --- | --- | --- | --- |
| implicit + projector | projector | implicit | 1 |
| implicit + operator + projector | projector | implicit, operator | 2 |

**Stable's Linux embedder presents one view per engine — the most recent one.**
Each added view displaces its predecessor and logs one assertion failure. That
is a property of the compositor, not of window creation, which is why no amount
of care about ordering or implicit-view content fixes it.

**So give each window its own engine.** The runner creates two `GtkWindow`s,
each with its own `FlDartProject` and `fl_view_new`, told apart by the Dart
entrypoint arguments:

```c
make_window(application, self, "MB8-OPERATOR",  900, 600,   0, 0, "operator");
make_window(application, self, "MB8-PROJECTOR", 1280, 720, 940, 0, "projector");
```

```dart
void main(List<String> args) {
  final role = args.isNotEmpty ? args.first : 'unknown';
  runApp(RoleApp(role: role));
}
```

Result: **both windows render at once**, in one process, from one binary, on
one launch. `FL_IS_COMPOSITOR` failures: **zero**. Screenshots of each window
show its own content — operator black-on-white at 900x600, projector
white-on-black at 1280x720.

The first capture attempt showed the operator black and it was an artefact, not
a result: both windows were placed at `+0+0`, so `import -window` on the lower
one grabbed the screen region the upper one covered. Moving them apart resolved
it. Worth recording because it looked exactly like the failure being chased.

## What this means for `DV.Platform.Window.open`

It can be registered on desktop, and it should not be built on Flutter's
experimental single-engine windowing, which cannot present two views on this
engine. The unit is an **engine per window**:

- The runner Dartvel generates creates the windows and their engines.
- Windows are told apart by entrypoint argument, which maps cleanly onto
  "a window is a route" — the argument carries the route.
- State between windows is the existing shared store and signals rather than a
  shared widget tree, because separate engines mean separate isolates. That is
  the same boundary `DVWindowingCapability.sameEngine` already describes, and
  the honest value for this arrangement is `sameEngine: false`.

The cost is two isolates and no pointer-passing of frames between windows. For
an operator surface driving a projection surface that is the right boundary
anyway: the output is a render target, not a widget subtree.

## Reproducing

The probes are four `flutter create` apps differing only in `lib/main.dart`,
built with `flutter build linux --debug`, and run under
`Xvfb :99 -screen 0 1920x1080x24 +extension GLX +extension RANDR +render` with
`LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe GDK_BACKEND=x11`. Window
counts come from `xwininfo -root -children`.

The one non-obvious step is that the app must assign `isWindowingEnabled = true`
and call `WidgetsFlutterBinding.ensureInitialized()` before constructing a
controller; `RegularWindowController` reads `WidgetsBinding.instance`, so
building one first throws "Binding has not yet been initialized" and hides the
real result.
