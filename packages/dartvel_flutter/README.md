# dartvel_flutter

The Flutter half of [Dartvel](https://dartvel.dev).

`DVBox` and `DVText` with fluent styling, the file-based pages router with
typed navigation, Riverpod-backed signals (`context.signal`, reactive models,
`DV.global`), generated forms and model pages, and `DV.Platform` — the native
API surface, bound through `dart:ffi` and jnigen rather than platform channels.

You usually do not depend on this directly. Applications depend on
[`dartvel_dev`](https://pub.dev/packages/dartvel_dev).

## Links

`DVNavLink` is a link rather than a tap handler, and the difference is not
cosmetic: `onTap: () => DV.Navigation.to(target)` compiles, runs and navigates
nowhere, because it builds the callback and never calls it.

```dart
DVNavLink(to: DVRoutes.docs, child: const DVText('Documentation'))
```

A Flutter app is a canvas, so nothing a link normally does exists unless the
link does it. This one navigates with its padding as part of the hit area,
announces itself to a screen reader as a link carrying its destination, takes
keyboard focus and answers Enter, opens the destination beside the page on a
middle or modifier click, preloads the route's deferred bundle on hover, and
shows a preview card of the destination on a resting pointer or a long press.

Link previews are the part iOS gives to Safari and nothing gives to anyone
else. They work here on every platform because Dartvel built the router, so it
can build the destination.

## Native APIs

Six platforms carry real bindings — Linux, web, Windows, Android, iOS and
macOS — reaching native through `dart:ffi` to X11/GTK/GDBus, the Win32 API, the
Objective-C runtime and AudioToolbox, `dart:js_interop`, and jnigen against the
Android SDK. No platform channels anywhere.

Where a binding is absent, the reason is recorded rather than left as backlog:
biometrics and NFC need an `Activity` rather than a `Context`; `UIScreen`
returns a struct through `objc_msgSend`, where the wrong entry point corrupts
the stack; a browser tab has no system tray. Calling an unbound name throws and
names it, rather than returning a plausible default.

## The name

The framework is Dartvel and the command is `dartvel`. The pub.dev package is
`dartvel_dev` because `dartvel` was taken on 2026-08-06 by an unrelated package.
