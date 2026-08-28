# Platform API coverage

What `DV.Platform` can actually do, per platform.

This page exists because "Platform APIs — implemented" is true of the
registration mechanism and says nothing about the capability behind it, and
the two are easy to conflate. It said, correctly at the time, that one
platform of seven had any bindings at all. Six do now.

## What is registered, where

| Platform | Bindings | Reaching native through |
| --- | --- | --- |
| Linux | **9** | `dart:ffi` to libX11, libgtk-3, GDBus |
| web | **5** | `dart:js_interop` with `package:web` |
| Windows | **8** | `dart:ffi` to the Win32 API |
| Android | **6** | jnigen bindings on the Android SDK |
| iOS | **5** | `dart:ffi` to the Objective-C runtime and AudioToolbox |
| macOS | **3** | `dart:ffi` to the Objective-C runtime and CoreGraphics |
| Embedded (Tizen, webOS, eLinux, Fuchsia) | none | — |

Thirteen distinct names are bound somewhere. No platform channels anywhere, per
the native integration rule.

**The remaining gaps are constraints, not backlog.** Each platform's
capability file gives the reason per name, and they are worth reading before
adding one: `BiometricPrompt` and NFC dispatch need an `Activity` rather than a
`Context`; `UIScreen.nativeBounds` returns a struct through `objc_msgSend`,
where the wrong entry point corrupts the stack rather than failing; a tab has
no system tray and cannot resize its own window; an Android or iOS app owns no
resizable window at all.

**Two of them turned out not to be constraints on inspection.** iOS haptics
were recorded as blocked because `UIImpactFeedbackGenerator` must be built and
called on the main thread while Flutter's root isolate runs on the UI thread —
true, and it rules out that API rather than the feature.
`AudioServicesPlaySystemSound` is plain C, thread-safe, and the system sound
identifiers in the 1519-1521 range are Taptic Engine taps. Android sharing was
absent for no stated reason at all; `ACTION_SEND` needs a `Context` and not an
`Activity`, so it was a gap.

**Window state is composed rather than bound.** `persistState` and
`restoreState` record a window's size and put it back, which is the shared
store plus `window.setSize` — binding it would have meant the same logic five
times over five preference APIs. On macOS, where `setSize` is deliberately
unbound, `restoreState` remembers the size and declines to apply it rather
than throwing.

## The Linux nine

| Binding | Backed by |
| --- | --- |
| `clipboard.copy`, `clipboard.paste` | GTK CLIPBOARD selection |
| `screen.geometry` | X11 display dimensions |
| `notifications.sendLocal` | freedesktop notifications over GDBus |
| `window.setTitle`, `.maximize`, `.minimize`, `.restore` | the app's GTK toplevel |
| `window.setSize` | `gtk_window_resize` |

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

## The Windows eight

| Binding | Backed by |
| --- | --- |
| `clipboard.copy`, `clipboard.paste` | user32 clipboard with `CF_UNICODETEXT` |
| `screen.geometry` | `GetSystemMetrics` |
| `window.setTitle` | `SetWindowTextW` |
| `window.maximize`, `.minimize`, `.restore` | `ShowWindow` |
| `window.setSize` | `SetWindowPos` with `SWP_NOMOVE \| SWP_NOZORDER` |

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

## The iOS five

| Binding | Backed by |
| --- | --- |
| `clipboard.copy`, `clipboard.paste` | `UIPasteboard` through the Objective-C runtime |
| `haptics.impact`, `.lightVibrate`, `.vibrate` | `AudioServicesPlaySystemSound` in AudioToolbox — plain C, thread-safe, where `UIImpactFeedbackGenerator` is neither |

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

## The Android six

| Binding | Backed by |
| --- | --- |
| `clipboard.copy`, `clipboard.paste` | `ClipboardManager` via `Context.getSystemService` |
| `share.text` | `Intent.ACTION_SEND` through `Intent.createChooser`, started on the application `Context` with `FLAG_ACTIVITY_NEW_TASK` |
| `haptics.vibrate`, `.lightVibrate`, `.impact` | `Vibrator`, or `VibratorManager` from API 31 |

JNI through jnigen-generated bindings, per the native integration rule — never
a platform channel.

**This page previously said Android was blocked, and the stated reason was
wrong.** It claimed `package:jni` exposes no application `Context`. It does:
`GetApplicationContext()` is declared in the package's own C header as
"Returns application context on Android", and is reachable with plain
`dart:ffi`. The claim came from grepping Dart source and concluding the
capability did not exist.

The fallback recorded here was wrong too. `ActivityThread.currentApplication()`
is the trick libraries normally use, and generation settled it: the class is
hidden and absent from the public `android.jar`, so jnigen found all six other
classes and reported that one "Not found". It was never a risk to weigh — it
was a route that does not exist. The C export is the better answer, being
neither a hidden Android API nor a Dart internal.

Bindings are generated by `.github/workflows/android-bindings.yml`, because
jnigen needs `android.jar` and the development environment has no Android SDK.
Hand-written JNI is not an option: calling a Java method needs
`ProtectedJniExtensions`, which `package:jni` exposes only through
`_internal.dart`, a library whose header says it is for generated code.

Absent, with reasons: notifications need a runtime channel and an API 33
permission; biometrics and NFC need an `Activity` rather than a `Context`;
window controls do not apply; and `screen.geometry` would add a second answer
that can disagree with the one Flutter already reports.

### `persistState` and `restoreState` need no binding at all

They were on this list, to be implemented natively on all six platforms. They
are not, and will not be.

Persisting a window's state means recording its size and putting it back.
Flutter already knows its own window size, the shared store already keeps state
between runs, and `window.setSize` is bound where a window can be resized. The
missing piece was somewhere to keep the value, not a platform capability —
binding it would have meant the same logic written five times against five
preference APIs.

Composing it degrades properly too. On macOS, where `window.setSize` is
deliberately unbound because it needs the main thread, `restoreState` remembers
the size and quietly declines to apply it rather than throwing at an
application that only asked to be tidy. It uses `invoke` rather than `require`
for exactly that.

A stored value that cannot be trusted decodes to null instead of throwing:
corrupt JSON, a wrong type, or the zero size a crashed or minimised window
leaves behind — which would otherwise restore a window nobody can find.

### `window.setSize`, and what it does not promise

Both implementations reject a zero, negative or non-integer size rather than
clamping it. A resize to a nonsensical size is a caller mistake, and clamping
hides the mistake behind a window that is the wrong size for reasons nobody can
see.

On Windows the flags matter: `SWP_NOMOVE | SWP_NOZORDER`, because only the size
was asked for. Without them the window also jumps to 0,0 and to the front.

On Linux the return value is narrower than it looks. `gtk_window_resize` sets
the size the window *requests*; a tiling window manager may refuse it, and GTK
reports nothing either way. The binding returns whether the call was made, not
whether the window ended up that size — a distinction the caller cannot learn
from GTK and should not be handed a guess about.

## What the framework calls and nothing implements

These have call sites in `dartvel_flutter` and no registration on any platform:

| Area | Names | Why |
| --- | --- | --- |
| Biometrics | `biometrics.authenticate`, `biometrics.canAuthenticate` (bound on the web) | `BiometricPrompt` attaches to an `Activity`; `LAContext` is reachable but presents UI from the main thread |
| NFC | `nfc.isAvailable`, `nfc.readTag` | Android delivers NFC dispatch to an `Activity`; iOS CoreNFC needs an entitlement |
| Bluetooth | `bluetooth.isEnabled` | a permission and a runtime-granted one since API 31 |
| Tray | `tray.show`, `tray.hide` | Windows `Shell_NotifyIcon` and macOS `NSStatusBar` are reachable; Linux needs a StatusNotifierItem over DBus, and a tray on one desktop only is worse than none |

Four more came off it on the web, and the reason is worth stating: the browser
has first-class APIs for all of them and nobody had looked.
`PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable()` answers
`biometrics.canAuthenticate`, WebAuthn with `userVerification: 'required'` is
`biometrics.authenticate` — the browser's own platform biometric prompt —
`navigator.bluetooth.getAvailability()` answers `bluetooth.isEnabled`, and
`nfc.isAvailable` is whether `NDEFReader` exists.

Each availability check answers **false** where the API is absent rather than
throwing, because "Bluetooth is not available in this browser" is a true
statement and the caller needs it to decide whether to offer the option. That
is different from a registered no-op: `biometrics.authenticate` still throws
when there is no authenticator or the person declines, and never reports a
success it did not get. Like every platform's local biometric API it gates the
interface and proves nothing to a server; a passkey sign-in verifies its
assertion server-side and is a separate flow.

Haptics and sharing were on this list and are not any more: haptics is bound on
Android, iOS and the web, and `share.text` on Android and the web. `window`
names never belonged here — `persistState` and `restoreState` are composed from
the shared store and `window.setSize`, not bound.

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
