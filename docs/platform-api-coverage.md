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
| Windows | **7** — see below |
| macOS | **3** — see below |
| Android | none |
| iOS | none |
| Embedded (Tizen, webOS, eLinux, Fuchsia) | none |

`packages/dartvel_flutter/lib/src/platform/` contains four directories:
`linux/`, `ios/`, `macos/`, `web/` and `windows/`. For Android and the
embedded targets there is nothing — not a partial implementation waiting to be
finished, nothing.

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

## The Windows seven

| Binding | Backed by |
| --- | --- |
| `clipboard.copy`, `clipboard.paste` | user32 clipboard with `CF_UNICODETEXT` |
| `screen.geometry` | `GetSystemMetrics` |
| `window.setTitle` | `SetWindowTextW` |
| `window.maximize`, `.minimize`, `.restore` | `ShowWindow` |

`dart:ffi` against user32 and kernel32 — no platform channels, per the native
integration rule.

**Notifications are deliberately absent.** A modern toast needs an
AppUserModelID registered against a real Start Menu shortcut, and the legacy
`Shell_NotifyIcon` balloon is deprecated and silently ignored under Focus
Assist. Either would be a binding that reports success and shows nothing, which
is worse than the "not registered" error because it looks like it worked.

Three details the implementation is careful about, each producing a plausible
wrong answer rather than an error if got wrong:

- **The clipboard owns the memory it is given.** On success `SetClipboardData`
  takes the handle, so freeing it is a use-after-free the moment anything
  pastes.
- **`CF_UNICODETEXT`, not the ANSI format**, which would mangle anything
  outside the active code page. The live test copies Japanese and an emoji, so
  a regression to ANSI fails rather than passing on ASCII.
- **`ShowWindow` returns the previous visibility**, not success. Reading it as
  a result makes the first maximise of a fresh window look broken.

`window.*` acts on the process's own top-level window via `GetActiveWindow`,
which is thread-scoped and returns 0 when the calling thread owns no active
window. That is a real state, and the bindings report failure rather than
reaching for another window — guessing is how a binding retitles somebody
else's application.

Verified on a Windows runner by the `windows-bindings` CI job: a clipboard
round trip including non-ASCII, an empty-string copy, and a real display
geometry. The window bindings are not exercised there — a test harness has no
top-level window, so they correctly return false, and asserting that would be
asserting the harness.

## The macOS three

| Binding | Backed by |
| --- | --- |
| `clipboard.copy`, `clipboard.paste` | `NSPasteboard` through the Objective-C runtime |
| `screen.geometry` | CoreGraphics |

The smallest set so far, and the omissions are the interesting part.

**`screen.geometry` uses CoreGraphics rather than `NSScreen.frame`.** The
latter returns a struct, and a struct return through `objc_msgSend` needs
`objc_msgSend_stret` on some ABIs — calling the wrong entry point corrupts the
stack rather than failing cleanly. CoreGraphics is plain C and needs no
messaging at all, so the risk is removed rather than managed.

**Notifications are absent.** `UNUserNotificationCenter` requires a bundled,
signed application with the right entitlement, and `NSUserNotification` is
removed. A binding that worked inside a signed bundle and silently did nothing
elsewhere would look like it worked in development, which is the worst place
for that to be discovered.

**Window controls are absent, and that is a thread-safety decision rather than
an effort one.** They need `NSApp.keyWindow`, and reading it through the
Objective-C runtime from Dart's isolate is not reliably on the main thread.
Getting that wrong crashes rather than misbehaves, so it waits until it can go
through the engine's platform thread.

Verified on a macOS runner by the `apple-bindings` job: a pasteboard round trip
including Japanese and an emoji, a second write proving `clearContents` is
called first — `NSPasteboard` rejects writes made without it — and a real
display geometry. A mistyped Objective-C message does not fail to compile, so
this is the only place the messaging is actually checked.

## The iOS two

| Binding | Backed by |
| --- | --- |
| `clipboard.copy`, `clipboard.paste` | `UIPasteboard` through the Objective-C runtime |

The runtime is linked into the app on iOS rather than living in a dylib that
can be opened by path, so the process itself is opened and the lookup of
`objc_getClass` is checked before anything depends on it.

**`screen.geometry` is absent here while macOS has it**, and the asymmetry is
deliberate. It would come from `UIScreen.nativeBounds`, which returns a
`CGRect`; a struct return through `objc_msgSend` needs `objc_msgSend_stret` on
some ABIs and corrupts the stack when the wrong entry point is used. macOS
sidesteps that with CoreGraphics, and iOS has no equivalent C path — so there
is nowhere safe to read it from, rather than nobody having got round to it.

`setString:` returns void, so `clipboard.copy` reports success as the absence
of a crash. UIKit gives no result to check and inventing one would be a lie.

Notifications, haptics and window controls are absent: the first needs
authorisation and a configured app delegate, the second must run on the main
thread, and the third does not exist — an iOS app does not own a resizable
window.

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
