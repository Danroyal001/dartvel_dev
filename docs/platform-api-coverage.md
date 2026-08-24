# Platform API coverage

What `DV.Platform` can actually do, per platform. The short answer is that the
**registration mechanism is complete and the bindings behind it are not**: one
platform of seven has any, and it implements 8 of the 22 names the framework
can call.

This page exists because "Platform APIs — implemented" is true of the mechanism
and misleading about the capability, and the two are easy to conflate.

## What is registered, where

| Platform | Bindings registered |
| --- | --- |
| Linux | **8** — see below |
| web | **9** — see below |
| macOS | none |
| Windows | none |
| Android | none |
| iOS | none |
| Embedded (Tizen, webOS, eLinux, Fuchsia) | none |

`packages/dartvel_flutter/lib/src/platform/` contains two directories, `linux/`
and `web/`. There is no partial implementation elsewhere waiting to be
finished — for the other five there is nothing.

## The Linux eight

| Binding | Backed by |
| --- | --- |
| `clipboard.copy`, `clipboard.paste` | GTK CLIPBOARD selection |
| `screen.geometry` | X11 display dimensions |
| `notifications.sendLocal` | freedesktop notifications over GDBus |
| `window.setTitle`, `.maximize`, `.minimize`, `.restore` | the app's GTK toplevel |

Bound through `dart:ffi` to libX11, libgtk-3 and GDBus — no platform channels,
per the native integration rule. Verified under Xvfb with a session bus,
including a real clipboard round trip and a notification delivered to a daemon
that answered with the id it assigned.

## The web nine

| Binding | Backed by |
| --- | --- |
| `clipboard.copy`, `clipboard.paste` | `navigator.clipboard` |
| `screen.geometry` | `window.screen` |
| `notifications.sendLocal` | the Notification API |
| `share.text` | `navigator.share` |
| `haptics.vibrate`, `.lightVibrate`, `.impact` | `navigator.vibrate` |
| `window.setTitle` | `document.title` |

The web was filled in first after Linux because it is the one platform where
the whole gap closes in Dart: ordinary web APIs through `dart:js_interop`, no
FFI, no toolchain, no vendor SDK.

Three things worth knowing about it:

- **`haptics.impact` has no real fidelity here.** `navigator.vibrate` takes a
  duration and knows nothing of impact weight, so the three names differ only
  in how long they buzz. Saying so beats implying a precision the platform
  does not have.
- **`notifications.sendLocal` does not request permission.** It throws when
  permission has not been granted, because requesting it would pop a browser
  prompt from whatever code path happened to send a notification — the pattern
  browsers added the user-gesture requirement to discourage.
- **`clipboard.paste` lets the browser's rejection propagate.** Reads need a
  secure context and usually a user gesture, and a caller that asked for the
  clipboard and silently got an empty string would report it as a clipboard
  bug.

Verified in a real browser, not only compiled: `flutter test --platform chrome`
registers the bindings, reads the actual window geometry, sets the document
title, and confirms `tray.show` still throws. It runs in CI as the `browser`
job. The VM suite resolves the stub, so it proves what web *claims* and nothing
about whether any of it works — a `screen.geometry` returning a fabricated size
passes there and fails in the browser, which is how that assertion was checked.

## What the framework calls and nothing implements

These have call sites in `dartvel_flutter` and no registration on any platform:

| Area | Names |
| --- | --- |
| Biometrics | `biometrics.authenticate`, `biometrics.canAuthenticate` |
| Haptics | `haptics.impact`, `haptics.vibrate`, `haptics.lightVibrate` |
| NFC | `nfc.isAvailable`, `nfc.readTag` |
| Bluetooth | `bluetooth.isEnabled` |
| Sharing | `share.text` |
| Tray | `tray.show`, `tray.hide` |
| Window | `window.setSize`, `window.persistState`, `window.restoreState` |

## What happens when you call one

It throws. `DVNativeBridge` raises its "not registered" error rather than
returning a plausible default, and that is deliberate: a `biometrics.authenticate`
that quietly returned `true` on a platform with no biometrics would be a
security hole, and a `clipboard.paste` that returned an empty string would be a
bug report about the clipboard.

The failure is loud, immediate, and names the binding. What it is not is
implemented.

## What finishing this needs

Per platform, and none of it is shared:

- **macOS and iOS** — Objective-C or Swift reached through `dart:ffi`, or
  ffigen over the system frameworks.
- **Windows** — Win32 through `dart:ffi`.
- **Android** — JNI through `jnigen`, which is the rule for JVM APIs.
- **web** — browser APIs where an equivalent exists (`navigator.clipboard`,
  `navigator.vibrate`, the Web Share API), and honest absence where it does not:
  there is no NFC tag read or system tray in a browser tab.

The embedded targets inherit whatever their host provides and are further
behind still, since three of the four cannot yet build an application at all.
