# Multi-Window on Flutter — what actually happens on stable, and on master

**Date:** 2026-09-01 · **Flutter:** 3.44.5 stable (engine `d3a3293399`) and
master `7ddb90b4` · **Host:** Ubuntu 24.04, Xvfb, Mesa llvmpipe

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

## Master does what stable cannot

Everything above is stable. Master was measured second, and it changes the
answer, so the engine-per-window conclusion below applies to stable only.

Master's API has moved on: `RegularWindowController` is now `WindowController`,
`RegularWindow` is `Window`, `preferredSize`/`preferredConstraints` are
`size`/`constraints`, and there are dialog, tooltip, popup and satellite window
kinds plus a `WindowRegistry` and a `LinuxWindowRegistrar`. `_window.dart` is
884 diff lines from stable's; code written against one will not compile against
the other. The feature is still `master: FeatureChannelSetting(available: true)`
and nothing else, but master adds an `environmentOverride: 'FLUTTER_WINDOWING'`
that stable has no equivalent for.

**On master, two windows on one engine both render, sharing one widget tree.**
A `String` held in the root `State` above both windows, changed once by a single
`setState`, appears in both windows at the same time:

| | operator window | projector window |
| --- | --- | --- |
| before | `OPERATOR / BLANK` | `PROJECTOR / BLANK` |
| after one `setState` | `OPERATOR / AMAZING GRACE` | `PROJECTOR / AMAZING GRACE` |

`FL_IS_COMPOSITOR` failures: **zero**. `BadAccess`: **zero**. The process stays
alive. The stable measurement's central finding — one view per engine, newest
wins — does not reproduce on master at all.

## The one rule that holds on both channels

**A window must be created after the first frame has been *rasterized*, not in
`main()`, not in `initState`, and not in `addPostFrameCallback` either.**

The post-frame form was the first version of this rule and it is wrong.
`addPostFrameCallback` fires after build, layout and paint, but before the
raster thread has presented anything, and a window created there still ends the
process. It was caught by building a real application on the binding: the
package's own tests passed, and the application died on launch until a two
second delay was put in front of `open()`. A delay is not a rule, so the signal
had to be found — `WidgetsBinding.instance.waitUntilFirstFrameRasterized` — and
the timing moved into `DVWindowHost`, where no application can get it wrong.

The original, weaker statement: Every early probe built its controller before the engine was up,
and on both channels that ends the process with a GLX `BadAccess`. On master it
does so even for a *single* window, which is what makes it look like a broken
feature rather than a lifecycle mistake: the plain-`runApp` baseline on master
runs fine, one `Window` built in `initState` dies, and the same one `Window`
built from `addPostFrameCallback` lives.

That is worth encoding rather than documenting. `DV.Platform.Window.open` should
own the timing so no application can get it wrong.

## Two capture artefacts that read exactly like failures

Both cost time, and both would cost it again.

**Occlusion.** `import -window <id>` on an unredirected X11 window returns the
screen region, not the window's own pixels, so capturing a window that another
one covers yields the *other* window's content — or black. Two separate probes
looked like "the second window renders and the first is dead" purely because
both sat at `+0+0`. With no `xdotool` or compositor available, the fix was to
size the windows so their content does not overlap and take one root capture
showing both.

**Reading a single sample as a result.** The stable probe that reported the
process alive had been sampled before the crash. Sampling on a fixed schedule
until the process exits is what turned that into a real answer.

## What this means for `DV.Platform.Window.open`

Build it on master's single-engine windowing:

- `multiWindow: true` and **`sameEngine: true`** on desktop. One engine, one
  widget tree, one isolate. Cross-window state is ordinary Dartvel state — a
  signal read in both windows — not the shared store, and not a sync protocol.
- The window is still a route, as the proposal already has it.
- `open` creates the window after the first frame, so the lifecycle trap above
  cannot reach application code.

The cost is the one that matters and it is not technical: **this needs Flutter
master.** Every embedder fork is pinned to a verified stable, and the
`docs/build-targets.md` evidence is against those pins. Adopting master for
windowing means re-verifying each target against it. That is a project decision,
not a windowing one, and it should be made explicitly rather than arrived at.

## Verified through Dartvel, not only through Flutter

`packages/dartvel_windowing` registers the binding, and a real application was
built against it and run under Xvfb:

```
E2E presentation=DVWindowPresentation.window
    degradation=DVWindowDegradation.none
    id=dv-window-1
```

Two OS windows, `e2e` at 1280x720 and `E2E-PROJECTOR` at 620x420, both
rendering, process alive, and zero `FL_IS_COMPOSITOR` or `BadAccess` in stderr.
A `ValueNotifier` declared above both windows and changed once shows in both:
captured at four seconds both read `BLANK`, captured at twelve both read
`AMAZING GRACE`. That is the claim `sameEngine: true` is making, tested rather
than asserted.

The first attempt at that capture proved nothing and looked like it proved
everything: both captures landed *after* the change, so both windows read
`AMAZING GRACE` in a way a pair of constants would also produce. The captures
have to straddle the change.

## What a window manager changes, and what that leaves unproven

Every run above was on a bare X server. Xvfb has no window manager, and every
desktop this will actually run on does. Installing `openbox` and repeating the
run changes the outcome:

| run | window manager | outcome |
| --- | --- | --- |
| two windows, `DVWindowHost` | none | alive, both render, 0 `BadAccess` |
| two windows, `DVWindowHost` | openbox | **dies, GLX `BadAccess`** |
| one window, plain `runApp` | openbox | alive, 0 `BadAccess` |

The control matters: the window manager alone is fine. It is **two windows plus
a window manager plus llvmpipe** that fails.

**What this does not establish is which of those three is at fault.** The
plausible reading is that a software GL stack cannot hold two GL contexts for
windows a WM has reparented, in which case hardware is unaffected. The
uncomfortable reading is that Flutter's multi-window path breaks under any
reparenting compositor, in which case it fails on every real desktop. Nothing
measured here separates them, and `--disable-impeller` is ignored by the built
binary, so the obvious discriminator did not run.

Until it is run on hardware, **"two windows work" should be read as "two
windows work on a bare X server"**. That is a weaker claim than the earlier
sections make, and it is the one the evidence supports.

The same limit applies to fullscreen: `window.setFullscreen` reaches
`WindowController.setFullscreen`, and whether the window actually goes
fullscreen could not be observed, because without a WM there is nothing to
honour the request and with one the process does not survive.

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
