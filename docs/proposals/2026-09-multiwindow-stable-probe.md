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

## Options, and which one to take

1. **Move Dartvel to Flutter main.** Where the feature is `available: true` and
   presumably works. It also moves every embedder fork off the version they are
   pinned and verified against, for one feature.
2. **Create the second view in the Linux runner, in C.** Dartvel generates the
   runner, so it could create a second `FlView` and GTK window natively and
   drive it over FFI. It stays inside the native-integration rule, but it is
   per-platform work — GTK, Win32 and AppKit — against an engine whose
   multi-view path is the thing that is broken.
3. **Two processes, one window each.** The operator app and the output app are
   separate processes, and the output is full-screen on the chosen display.
   Nothing experimental is involved: one window per process works on every
   desktop target Dartvel has verified.

**Option 3 is the recommendation**, and not only as a workaround. Dartvel
already ships the parts that make it work — model sync, presence, signals, and
the window shared store — so the link between operator and output is a
first-class Dartvel concern rather than a window-handle detail. It also gets
something the shared-engine designs cannot: the output can run on a *different
machine* from the operator, which is how a media desk is often wired in the
first place.

The cost is honest and worth writing down: two processes mean two engines and
two copies of any preloaded media, and a video frame cannot be handed between
them as a pointer.

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
