# Build targets and toolchains

What `dartvel build <target>` supports, what each target needs installed, and
what has actually been verified rather than assumed.

Every "verified" row below was produced by running the command and inspecting
the artifact. Rows that are not verified say so and say why.

---

## Verified status

Verified on Linux x64 (Ubuntu 24.04), Flutter 3.44.5 / Dart 3.12.2. Most
Flutter targets were verified against `examples/dartvel_example`.

> **Paid targets.** `visionos`, `horizon`, `chrome-extension`,
> `firefox-extension`, `vscode`, `telegram`, the terminal targets
> (`<desktop>-cli`/`-tui`, `fuchsia-cli`), `fuchsia` and `mcu` are not built by the
> free CLI from the release after 0.11.5: they need a Dartvel Cloud plan and
> the private `dartvel_targets_pro` package, and their evidence lives with
> that package. On a free install `dartvel build <target>` for one of them
> exits 69 with a message naming the plan, `dartvel build <target> --cloud`
> and `dartvel targets add pro`. The extension point they implement,
> `DVBuildTarget`, is public (`package:dartvel_cli/build_targets.dart`). The
> runtime APIs that go with them (Telegram host and sign-in, the XR runtime,
> the terminal surface, the browser-extension runtime) are in the private
> `dartvel_runtimes_pro` package, behind public extension points.


> **The native server is opt-in.** `dartvel_shelf.dll`, `libdartvel_shelf.so`
> and `dartvel_shelf.framework` in the artifacts below are the Axum runtime,
> and they are there because the example application serves a Dartvel backend
> and says so:
>
> ```yaml
> hooks:
>   user_defines:
>     dartvel_shelf:
>       embed_server: true
> ```
>
> `dartvel_core` depends on `dartvel_shelf` for its request and response types,
> so every Dartvel application pulls the package whether or not it ever serves.
> The build hook used to compile and bundle the server regardless, which put a
> full HTTP server -- with TLS and a static file handler -- inside client
> binaries that never listen, at 6.5-7.2 MB each. An application that only
> calls a remote API now ships none of it.


| Target | Status | Evidence |
|---|---|---|
| `web` | ✅ Builds | `build/web` (43 MB) with `flutter_bootstrap.js`, `main.dart.js`, assets, CanvasKit; Wasm dry run passes |
| `web-server` (linux-x64) | ✅ Builds and **runs** | `build/server`, **29.9 MB**, one executable carrying the backend, the native server library and the web app. Verified 2026-09-16 on a `dartvel create` app with a model and two backend functions: the file was copied alone into an empty directory and started with only `PATH` and `DARTVEL_PORT` set. It printed `dartvel: no DATABASE_URL, creating SQLite database .../dartvel_data/data.db` and `dartvel: created table notes`; `GET /` answered `text/html` with the page head, `GET /main.dart.js` answered 200 with 2,878,353 bytes, `POST /api/add_note` wrote a row, and after a stop and a second start (`dartvel: SQLite database ...`, no table created) `GET /api/notes` returned it. Headless Chromium rendered the app from the binary with no console errors. The binary was produced by the build's own compile-and-carry step after `flutter build web`; on this host the full command stopped earlier, in the semantics capture, with a Chrome navigation timeout under load. `test/web_server_binary_test.dart` runs the whole command in CI. Also run on every push that touches the server by `.github/workflows/web-server-hosts.yml`, green in run 35231239142 (commit `7cdd277d`) |
| `web-server` (linux-arm64) | ✅ Builds and **runs** | `build/server` built on `ubuntu-24.04-arm` with the `linux-arm64` library committed under `packages/dartvel_shelf/lib/native/linux-arm64/`. On the runner, `.github/workflows/web-server-hosts.yml` (run 35231239142, commit `7cdd277d`) checked out the committed library, failing if it is absent, and ran with `--run-skipped` so nothing could pass by skipping: `native_symbols_test` (the committed library exports every symbol the bindings declare), `binary_payload_test` (a payload spliced into a real compiled program is read back by it), `compiled_executable_test` (a compiled program handed the library serves a request), `server_binary_build_test` (the compiled backend and its Studio served from a copy alone) and `web_server_binary_test`: `dartvel create`, `dartvel build web-server`, the executable copied alone into an empty directory and started with only a search path and `DARTVEL_PORT` (on Windows also `SystemRoot`, `TEMP`), `GET /` answering `text/html` with the page head, `GET /main.dart.js` served from inside the binary, `POST /api/add_note` writing into the `dartvel_data/data.db` it created, `GET /api/notes` returning that row after a stop and a second start, and Studio served to a granted account and to nobody else. Flutter 3.44.5 from its git tag, because Flutter publishes no Linux arm64 SDK archive. Not verified here: a browser rendering the page, which the site job in `runtime-verification.yml` does on linux-x64 only |
| `web-server` (macos-arm64) | ✅ Builds and **runs** | `build/server` built on `macos-latest` with the `macos-arm64` library committed under `packages/dartvel_shelf/lib/native/macos-arm64/`. On the runner, `.github/workflows/web-server-hosts.yml` (run 35231239142, commit `7cdd277d`) checked out the committed library, failing if it is absent, and ran with `--run-skipped` so nothing could pass by skipping: `native_symbols_test` (the committed library exports every symbol the bindings declare), `binary_payload_test` (a payload spliced into a real compiled program is read back by it), `compiled_executable_test` (a compiled program handed the library serves a request), `server_binary_build_test` (the compiled backend and its Studio served from a copy alone) and `web_server_binary_test`: `dartvel create`, `dartvel build web-server`, the executable copied alone into an empty directory and started with only a search path and `DARTVEL_PORT` (on Windows also `SystemRoot`, `TEMP`), `GET /` answering `text/html` with the page head, `GET /main.dart.js` served from inside the binary, `POST /api/add_note` writing into the `dartvel_data/data.db` it created, `GET /api/notes` returning that row after a stop and a second start, and Studio served to a granted account and to nobody else. The payload is appended after the Mach-O image; the ad-hoc signature is left as `dart compile exe` wrote it, which `codesign --verify` rejects under strict validation and the kernel runs (probe run 35224245361). Not verified: Developer ID signing, notarization, or a copy downloaded through a browser. Not verified here: a browser rendering the page, which the site job in `runtime-verification.yml` does on linux-x64 only |
| `web-server` (macos-x64) | ✅ Builds and **runs** | `build/server` built on `macos-15-intel` with the `macos-x64` library committed under `packages/dartvel_shelf/lib/native/macos-x64/`. On the runner, `.github/workflows/web-server-hosts.yml` (run 35231239142, commit `7cdd277d`) checked out the committed library, failing if it is absent, and ran with `--run-skipped` so nothing could pass by skipping: `native_symbols_test` (the committed library exports every symbol the bindings declare), `binary_payload_test` (a payload spliced into a real compiled program is read back by it), `compiled_executable_test` (a compiled program handed the library serves a request), `server_binary_build_test` (the compiled backend and its Studio served from a copy alone) and `web_server_binary_test`: `dartvel create`, `dartvel build web-server`, the executable copied alone into an empty directory and started with only a search path and `DARTVEL_PORT` (on Windows also `SystemRoot`, `TEMP`), `GET /` answering `text/html` with the page head, `GET /main.dart.js` served from inside the binary, `POST /api/add_note` writing into the `dartvel_data/data.db` it created, `GET /api/notes` returning that row after a stop and a second start, and Studio served to a granted account and to nobody else. Same payload placement and signature caveats as macos-arm64. Not verified here: a browser rendering the page, which the site job in `runtime-verification.yml` does on linux-x64 only |
| `web-server` (windows-x64) | ✅ Builds and **runs** | `build/server.exe` built on `windows-latest` with the `windows-x64` library committed under `packages/dartvel_shelf/lib/native/windows-x64/`. On the runner, `.github/workflows/web-server-hosts.yml` (run 35231239142, commit `7cdd277d`) checked out the committed library, failing if it is absent, and ran with `--run-skipped` so nothing could pass by skipping: `native_symbols_test` (the committed library exports every symbol the bindings declare), `binary_payload_test` (a payload spliced into a real compiled program is read back by it), `compiled_executable_test` (a compiled program handed the library serves a request), `server_binary_build_test` (the compiled backend and its Studio served from a copy alone) and `web_server_binary_test`: `dartvel create`, `dartvel build web-server`, the executable copied alone into an empty directory and started with only a search path and `DARTVEL_PORT` (on Windows also `SystemRoot`, `TEMP`), `GET /` answering `text/html` with the page head, `GET /main.dart.js` served from inside the binary, `POST /api/add_note` writing into the `dartvel_data/data.db` it created, `GET /api/notes` returning that row after a stop and a second start, and Studio served to a granted account and to nobody else. The payload is appended after the PE image, and on start the DLL is written to a fresh directory under `%TEMP%` and loaded from there. Not verified: SmartScreen or Defender on a downloaded copy. Not verified here: a browser rendering the page, which the site job in `runtime-verification.yml` does on linux-x64 only |
| `web-server` (windows-arm64) | ✅ Builds and **runs** | `build/server.exe` built on `windows-11-arm` with the `windows-arm64` library committed under `packages/dartvel_shelf/lib/native/windows-arm64/`. On the runner, `.github/workflows/web-server-hosts.yml` (run 35231239142, commit `7cdd277d`) checked out the committed library, failing if it is absent, and ran with `--run-skipped` so nothing could pass by skipping: `native_symbols_test` (the committed library exports every symbol the bindings declare), `binary_payload_test` (a payload spliced into a real compiled program is read back by it), `compiled_executable_test` (a compiled program handed the library serves a request), `server_binary_build_test` (the compiled backend and its Studio served from a copy alone) and `web_server_binary_test`: `dartvel create`, `dartvel build web-server`, the executable copied alone into an empty directory and started with only a search path and `DARTVEL_PORT` (on Windows also `SystemRoot`, `TEMP`), `GET /` answering `text/html` with the page head, `GET /main.dart.js` served from inside the binary, `POST /api/add_note` writing into the `dartvel_data/data.db` it created, `GET /api/notes` returning that row after a stop and a second start, and Studio served to a granted account and to nobody else. Flutter 3.44.5 from its git tag, because Flutter publishes no Windows arm64 SDK archive. Same payload placement and caveats as windows-x64. Not verified here: a browser rendering the page, which the site job in `runtime-verification.yml` does on linux-x64 only |
| `linux` | ✅ Builds and **runs** | `build/linux/x64/release/bundle/dartvel_example`, 23.8 KB launcher + bundle. Runtime-verified under Xvfb: the release binary ran headless (software EGL), stayed alive, and a root-window screenshot showed the full UI — `DV.Platform` live-reporting `linux`/`desktop`, signals active (`showcase-ready`). The first target verified by running, not only building. **Re-verified 2026-08-15** after the native-asset hook was rewritten (`976ccfa8`, `db93571b`): the hook compiled `x86_64-unknown-linux-gnu` from an empty target directory, `libdartvel_shelf.so` (6.5 MB) was bundled into `bundle/lib/`, and the binary ran and rendered as before |
| `android` | ✅ Builds; release APK checked with aapt2, apksigner and apkanalyzer | `build/app/outputs/flutter-apk/app-release.apk`, 47.9 MB. **Re-verified 2026-10-11** on a fresh `dartvel create` project, Linux x64, Flutter 3.47.5, with a test key generated by `keytool` and named in `dartvel.android.signing.keyProperties`: `dartvel build android` produced a 52.2 MB release APK. `apksigner verify --print-certs` shows `CN=Dartvel E2E Test` (the test key, SHA-256 `1d0416cc…2b1b07`), not `CN=Android Debug`; `aapt2 dump xmltree` shows `android.permission.INTERNET`, `allowBackup=false`, `usesCleartextTraffic=false`, `networkSecurityConfig` and `dataExtractionRules`, no `debuggable`, and only `MainActivity` and androidx's `DUMP`-guarded profile receiver exported; `apkanalyzer dex packages` lists `dev.dartvel.jni.DartvelActivityBridge` with `state`, `granted`, `begin` and `poll` under their own names. The same build on main before the change was debug-signed, had no INTERNET or backup setting, and R8 had removed `DartvelActivityBridge`. With no key, `dartvel build android` is refused before generation and plain `flutter build apk --release` fails at `:app:preReleaseBuild`; `flutter build apk --debug` still builds, debug-signed. Not run on a device. `--format aab` also writes `data-safety.csv` and `data-safety-worksheet.md` beside the bundle (`docs/data-safety.md`); the writer is unit tested, the build hook has not been run through a full `--format aab` build. With `dartvel.purchases` declared the build adds Play Billing (Java bridge and Gradle dependency); not run on a device or against a Play test track |
| `fireos` | ✅ Builds | Same APK path; `fireos` maps onto the Android toolchain |
| `windows` | ✅ Builds | **Verified on a Windows runner**, artifact downloaded and inspected rather than inferred: `dartvel_example.exe` (89 KB, PE32+ executable GUI x86-64), `dartvel_shelf.dll` (7.2 MB, the Rust runtime), `flutter_windows.dll`, `data/`. Run [32587129093](https://github.com/Danroyal001/dartvel_dev/actions/runs/32587129093). Took eight attempts and **seven bugs** — two earlier runs had burned 257 and 226 minutes in silence. Four of the seven were not Windows quirks but silent corruption on every platform, exposed only because a Windows path forced the issue: `esc` never escaped backslashes; `routeFromRel` normalised separators with a doubled backslash and stripped its prefix before normalising; the same doubled-backslash fault sat in six more sites across two packages; and four glob patterns were built with `p.join`, where the separator is always `/` and a backslash is the escape character. See [Windows](#windows) |
| `macos` | ✅ Builds | **Verified on a macOS runner**, artifact downloaded and inspected: `dartvel_example.app/Contents/MacOS/dartvel_example` is a **Mach-O universal binary (x86_64 + arm64)**, with `dartvel_shelf.framework` — the Rust runtime — bundled into `Contents/Frameworks`. Run [32602765861](https://github.com/Danroyal001/dartvel_dev/actions/runs/32602765861). The 41-minute silence was never Flutter: the native asset hook buffered its output, so a long C compile was indistinguishable from a wedge. Bounding and streaming it turned the hang into a visible failure, which turned out to be **cc-rs invoked with no `-isysroot`** — `SDKROOT` was unset, so every C crate (`ring`, `zstd-sys`, `aws-lc-sys`) failed to find its headers. The hook now asks `xcrun` for the SDK path, chosen from the target rather than the host. `aws-lc-rs` was also dropped: it is rustls's default provider, this crate uses `ring`, and it was compiling a large C codebase for nothing on every platform. See [macOS](#macos) |
| `ios` | ✅ Builds | **Verified on a macOS runner**, not this host: `build/ios/iphoneos/Runner.app` (15.4 MB), artifact directory listed. Run [31554165981](https://github.com/Danroyal001/dartvel_dev/actions/runs/31554165981). The device bindings shim (`ios/Runner/DartvelPlatform.swift`, added 2026-10-09) has **not been compiled yet**: see [iOS device bindings](#ios-device-bindings) |
| `tvos` | ✅ Builds and **runs** (simulator, debug) | **Verified on a macOS runner**: scaffold auto-generated, then `build/tvos/Debug-appletvsimulator/Runner.app`. The `appletvsimulator` path is the proof it is a tvOS app and not the iPhone app an earlier mapping produced. Run [32538073146](https://github.com/Danroyal001/dartvel_dev/actions/runs/32538073146). Installed on an Apple TV simulator, launched and photographed in run [35025146988](https://github.com/Danroyal001/dartvel_dev/actions/runs/35025146988): the screenshot shows the example's home page reporting `Platform: tvos` and `Device: tv`. Device (signed) builds are not verified. See [tvOS](#tvos) |
| `tizen` / `tpk` | ✅ Builds | Signed 9.3MB TPK with engine + assets, built on a laptop with Tizen Studio installed. CI can only ever *skip* it — the SDK is licence-gated and Dartvel must not install it unattended — so the workflow asserts the skip names that reason. See [Tizen](#tizen-samsung) |
| `sony-elinux` | ✅ Release bundle assembles; a bundle assembled the same way **runs** | `dartvel build sony-elinux` does not use `flutter-elinux`: it assembles a **release** bundle from the Linux desktop release build and Sony's embedder artifacts, refuses debug and profile, and **skips when those artifacts are not installed** under `~/.dartvel/toolchains/dartvel_elinux/artifacts`, which is what the platform build matrix sees. The runtime-verification workflow assembles debug and release bundles the same way in its own steps and runs both on a virtual device (Weston on Xvfb). Release needs the from-source engine, since the official standalone one is JIT. See [Sony eLinux](#sony-elinux) |
| `webos` | ⚠️ `dartvel build webos` skips; a package assembled in CI runs in a Wayland window on ARM under emulation; not run on a television | `dartvel build webos` drives LG's `flutter-webos`, which bundles Dart 3.10.9 and cannot resolve a Dartvel project, so it skips naming that. The runtime-verification and `webos-window` workflows assemble the package without it, from stock Flutter 3.44.5 and LG's engine. Not a vendor secret: LG's engine exports `FlutterEngineRun` and is an ordinary Custom Embedder API build. It is **ELF 32-bit ARM**, and Google publishes `linux-arm64` but no 32-bit `linux-arm`. See [webOS](#webos-lg) |

Flutter has **no desktop cross-compilation**. A Windows desktop build requires
Windows, a Linux desktop build requires Linux, and the Apple targets require
macOS. `dartvel build` skips a target its host cannot build rather than
failing the whole run.

### Android push and crash symbols

`dartvel build android` with `dartvel.push.android.fcm` and
`dartvel.crashes.symbols` declared, **2026-10-11**, Linux x64, Flutter 3.47.5,
on a fresh `dartvel create` project with a `keytool` test key. Built, not run:

- `app-release.apk`, 52.7 MB, signed (`apksigner verify` shows the test key).
  `aapt2 dump permissions` lists `POST_NOTIFICATIONS` and
  `com.google.android.c2dm.permission.RECEIVE`; the manifest has
  `dev.dartvel.jni.DartvelMessagingService` with `exported=false` and the
  `com.google.firebase.MESSAGING_EVENT` filter; `aapt2 dump resources` shows
  `google_app_id`, `google_api_key`, `gcm_defaultSenderId` and `project_id`
  with the declared values, and no `google-services.json` exists.
- `apkanalyzer dex packages` lists `dev.dartvel.jni.DartvelPush` (`start`,
  `poll`, `drainMessages` under their own names, which Dart finds by name over
  JNI), `DartvelCrash` and `DartvelMessagingService` after R8.
- `build/symbols/0.0.1/` holds `mapping.txt` (8.9 MB, 79,597 lines), three
  `app.android-*.symbols` files with their ELF build ids, a 27 MB
  `native-debug-symbols.zip` and `manifest.json`.
- The Java was also compiled against the real `android.jar` and
  `firebase-messaging` 26.0.0 / 25.1.3, and the JVM crash handler was run on a
  JVM and its record read back with `DVCrashReport.fromJson`.
- `mapping.txt` was retraced by `DVProguardMapping` and by the `retrace` tool
  in the SDK on 3,000 frames from that file: 96 percent print identically. The
  differences are R8 `rewriteFrame` rules that depend on the exception type,
  outline call sites, and caller frames R8 omits at line 0; none is applied.

Web Push, run for real the same day: Chrome 155 (headless, a temporary
profile) loaded `dartvel build web` output served from `127.0.0.1`, with the
notification permission granted. `PushNotifications.getToken()` returned a
subscription whose endpoint is `https://fcm.googleapis.com/fcm/send/...`;
`WebPushProvider.fromSecrets()` posted an encrypted, VAPID-signed message to it
and the service answered `201`; the page printed the message from
`PushNotifications.onMessage` with its title, body and data. With every page of
the site closed, a second push made the worker show the notification itself
(`getNotifications()` returned it with its data). Before this the probe found
`navigator.serviceWorker.getRegistration()` empty: Flutter 3.47's bootstrap
only updates a registration that exists, so the build now appends the
registration to `flutter_bootstrap.js` (`service_worker_registration_test.dart`).

Not run: the APK on a device or emulator (this host has no KVM), a token from
FCM, a message delivered by FCM, a notification click in a browser, or an
uncaught exception recorded on a phone. The
generated backend, the upload and the symbolicated reports were run for real
over HTTP against an AOT snapshot compiled with `--obfuscate`
(`test/symbols_backend_test.dart`); the Dart decoder has not been run against
Flutter's engine-built `libapp.so`.

### Linux native bindings

`DVLinuxBindings.register()` binds eight names to libX11, libgtk-3 and GDBus
through `dart:ffi` — no platform channels, per the spec:

| Binding | Backed by |
|---|---|
| `clipboard.copy`, `clipboard.paste` | GTK CLIPBOARD selection |
| `screen.geometry` | X11 display dimensions |
| `notifications.sendLocal` | freedesktop notification service over GDBus |
| `window.setTitle`, `.maximize`, `.minimize`, `.restore` | the app's GTK toplevel |

It is deliberately partial: a binding it cannot implement is left
unregistered, so calling it still throws `DVNativeBridge`'s "not registered"
error rather than returning a plausible lie.

Verified under Xvfb with a session bus:

- A real GTK CLIPBOARD round trip, including a multi-byte UTF-8 value.
- `screen.geometry` reporting the X display's actual size, asserted against
  the geometry the harness started — with a negative control confirming the
  assertion fails when told to expect the wrong number.
- A notification delivered to a real daemon, which answered with the id it
  assigned. D-Bus **activated** the daemon on demand (`dunst` went from 0 to
  1 process during the call), so the message travelled the full bus path.
- Window control driving a real GtkWindow: the title is read back through
  GTK rather than from Dartvel's own state, and the no-window case is
  asserted to report failure rather than pretend.

Those eight are the ones verified by running, not the ones that exist. Linux
registers far more than eight -- `register()` hands the bridge to fifteen or
so sub-modules, so counting the calls in `linux_bindings_ffi.dart` alone
undercounts it badly, and the same trap catches Windows and macOS.

`binding_names.dart` declares **70** names in total. Do not read a per-platform
count off this page: the honest source is the source, and the count moves every
time a binding lands. What is worth recording is the shape of the gap, because
it is not where you would guess.

**Android is second from last, at 10 of 70** -- clipboard both ways, the three
haptics, sharing, deep links, the home widget bridge, and the two kiosk names.
No camera, no location, no biometrics, no runtime permissions, no local
notifications, no sensors, no contacts, no media picker, no NFC, no Bluetooth,
no screen geometry. The APK builds, the app runs, `DV.Platform` reports
`android` correctly, and every one of those calls returns null.

That last part is why this is worth a paragraph rather than a row.
`DVNativeBridge.invoke` returns null for a name nothing registered, which is
the right default -- an unbound capability should degrade rather than throw --
but it means an application asking for the camera on Android cannot tell an
unimplemented binding from a device that said no. The desktop targets are
ahead of the mobile ones, which is the reverse of what a developer coming to
Dartvel to build a phone app will assume.

### Web is the guard on native dependencies

`dartvel_core` now depends on packages that cannot run in a browser: `sqlite3`
(via `dart:ffi`) behind `SqliteDVDatabaseAdapter`, and `dart:io` sockets behind
`SmtpMailProvider`. Both are reached through conditional imports, so a web
build resolves a stand-in that throws with the supported alternative named
rather than pulling the native library in.

Nothing about that is enforced by the type system, so **re-run `flutter build
web` after adding a dependency to `dartvel_core`**. A direct import of a
native-only library compiles fine on every other target and fails only here.
The Wasm dry run is the stronger signal of the two: it fails on `dart:ffi` and
`dart:io` reachability that plain JS compilation can tolerate, so treat a
passing dry run — not just `✓ Built build/web` — as the check.

---

## Toolchain preflight

Before building a target, `dartvel build` checks two things in order:

1. **Can this host build it at all?** If not, the target is skipped with a
   reason. There is no point offering to install Xcode on Linux.
2. **Are the required tools installed?** Missing tools are listed by name.

What happens next depends on where it is running:

| Situation | Behaviour |
|---|---|
| Interactive terminal | Lists what is missing and asks before installing |
| CI (`CI=true`, `GITHUB_ACTIONS`, `GITLAB_CI`, `BUILDKITE`, `CIRCLECI`, `TF_BUILD`) | Installs without prompting, so a pipeline cannot hang on a prompt |
| `--auto-install` | Installs without prompting, anywhere |
| `--no-auto-install` | Never installs — wins even in CI, for pre-provisioned images |
| No terminal attached | Treated as declined rather than blocking |

Anything installed during a run is added to the `PATH` handed to child
processes, so a freshly installed embedder is usable by the build that just
installed it.

### What Dartvel will and will not install

Dartvel installs the things it can fetch unattended:

The fork repositories are named `dartvel_*`; the executables inside three of
them keep upstream's own `flutter-*` names, because renaming those would mean
patching every vendor script.

| Tool | Installed via | From |
|---|---|---|
| `flutter-tizen` | `git clone` | `dartvel_tizen` |
| `flutter-elinux` | `git clone` | `dartvel_elinux` |
| `flutter-webos` | `git clone` | `dartvel_webos` |
| `ares` (webOS CLI) | `npm install -g @webos-tools/cli` |
| Linux desktop deps (`clang`, `cmake`, `ninja`, `pkg-config`, GTK 3) | `apt-get` |

It deliberately will **not** install licence-gated or multi-gigabyte vendor
SDKs, and only prints instructions for them: **Xcode**, **Visual Studio**,
the **Android SDK**, and **Tizen Studio**. Installing those silently on
someone's machine is not Dartvel's call.

Toolchains Dartvel manages itself live in `~/.dartvel/toolchains/`.

---

## Microcontrollers (`mcu`, paid)

A microcontroller with no Linux (ESP32-S3, STM32) cannot run Flutter or the
Dart runtime, so `dartvel build mcu` does not run Dart there: it compiles the
app's pages to C that draws with LVGL and writes an ESP-IDF project. **The app
has to be built entirely from Dartvel primitives (`DVBox`, `DVText`,
`DVModifier` and signals) for this target to work.** A Flutter widget, a
package widget or code the compiler cannot translate stops the build with its
file and line, and nothing is generated; the same page keeps working on every
other target. It is a paid target in `dartvel_targets_pro`.

## Embedded and television targets

These are driven by the platform vendor's Flutter embedder, never by plain
`flutter build`. Dartvel maintains a fork of each so it can pin and patch the
embedder against the Flutter version Dartvel ships.

| Target | Fork | Upstream | Vendor |
|---|---|---|---|
| `tizen` | [Danroyal001/dartvel_tizen](https://github.com/Danroyal001/dartvel_tizen) | `flutter-tizen/flutter-tizen` | Samsung |
| `sony-elinux` | [Danroyal001/dartvel_elinux](https://github.com/Danroyal001/dartvel_elinux) | `sony/flutter-elinux` | Sony |
| `webos` | [Danroyal001/dartvel_webos](https://github.com/Danroyal001/dartvel_webos) | `lg-flutter-webos/flutter-webos` | LG |

## Runtime verification

`.github/workflows/runtime-verification.yml` builds each target, **runs** it,
and captures what it drew. Every image below is an artifact of that workflow,
and a green job with no image is not a pass — the eLinux job went green with no
screenshot on its first run, which is exactly the false positive the images
exist to catch.

| Target | Runs | What the capture shows |
| --- | --- | --- |
| `linux` | ✅ | The showcase under Xvfb: platform `linux`, device `desktop`, signal `showcase-ready` |
| `web` | ✅ | The same page in headless Chrome: platform `web`, device `web` |
| `sony-elinux` | ✅ | The showcase on a **virtual eLinux device** — Weston on the X11 backend, Sony's Wayland embedder, software GL. Debug **and release**: the release capture has no DEBUG banner and shows the production backend |

What running found that building could not:

- **The web build had been broken** since the Rust HTTP transport landed —
  `dart:ffi` is not available on web and the export was unconditional. No CI job
  built web, so nothing noticed.
- **The eLinux release bundle cannot start.** See the correction below.
- **The terminal embedder panicked** with a capacity overflow when the terminal
  had no dimensions, before drawing anything.
- **Software GL is required** on a runner. Without it the eLinux client's EGL
  falls through to ZINK, fails `vkCreateInstance` with
  `VK_ERROR_INCOMPATIBLE_DRIVER`, and never gets a context — which reads as an
  embedder fault and is not one.

The table above is the first four jobs. The same workflow also runs Android on
an emulator, Windows, macOS and iOS, tvOS on a simulator, webOS on ARM, both
browser extensions, the web server and the PWA, and every one of those jobs
passed in run [35172461725](https://github.com/Danroyal001/dartvel_dev/actions/runs/35172461725).

**Release now runs, and the engine question is settled.** The from-source
release engine built by `engine-build.yml` does run an AOT bundle: the
runtime-verification workflow assembles one — desktop `libapp.so`, the release
engine, Sony's embedder — and it renders on the virtual device with no DEBUG
banner and the production backend, where the debug run shows both.

That had to be settled by running it. Inspecting the binary was inconclusive:
the `Not running in AOT mode` string is present in the from-source release
build as well as in the official one, so the string check that first identified
the official engine as JIT would have given the wrong answer here. The runtime
error was the real evidence; the string was a coincidence that happened to
point the same way.

**Correction, established by running the thing rather than inspecting it: the
official standalone engine is the JIT build, not the release build.** This file
previously said the opposite, inferred from its size — 41.7 MB against Sony's
release 42.6 MB — and that inference was wrong. The binary settles it: it
contains the strings `kernel_blob.bin` and `Not running in AOT mode but could
not resolve the kernel binary`, which a release engine has no use for.

The eLinux release bundle assembled from it therefore **cannot start**. It
pairs an AOT `libapp.so` with an engine that only runs kernel, and the
application dies during `FlutterEngineInitialize` with exactly that message.
The structural verification recorded below — snapshot symbols present, no GTK
dependencies — was true and insufficient: nothing about inspecting an artifact
can catch a mode mismatch between two files that are each individually correct.

That is the whole argument for running rather than building, and it took one
run to demonstrate.

What follows from it:

- **eLinux debug** is what the official artifact supports today, with
  `kernel_blob.bin` rather than `libapp.so`.
- **eLinux release** needs a release engine built from source, which is what
  `engine-build.yml` is for.

**The engine build works, and the modes Google does not publish are now
obtainable.** `.github/workflows/engine-build.yml` builds the Flutter engine
from source on a GitHub runner and splits the result into chunks that clear
GitHub's 100 MB file limit, so it travels back without Git LFS. Verified for
`profile` at 3.44.5:

```
libflutter_engine.so  54.2 MB, exports FlutterEngineRun, carries the
                      observatory and timeline strings a release build does not
gen_snapshot          6.1 MB
flutter_embedder.h
```

Against the official release engine at 41.7 MB, so it is a genuinely different
build rather than the same artifact under another name. The chunks were rejoined
in the development Codespace and the whole-artifact sha256 verified.

Four attempts, all failing on the same thing: where gclient wants its root.
flutter/flutter contains **both** `engine/src/build` and `engine/src/flutter`,
and `DEPS` at its root uses gclient-root-relative paths — so the repository root
*is* the gclient root, and no subdirectory arrangement satisfies both. That is
readable from `DEPS` and was worth reading before the first attempt rather than
after the third.

**The eLinux release path no longer goes through `flutter-elinux` at all.** A
desktop release build already produces every piece an eLinux release bundle
needs — `data/flutter_assets`, `data/icudtl.dat` and an AOT `lib/libapp.so` for
the same architecture — and differs only in which executable and which engine
library sit beside them. Swapping those two is the whole job, so neither an
engine build nor the fifteen-version-stale tool is required.

Assembled and inspected from the example app's release build plus the
CI-produced Sony artifacts:

```
flutter-client            Sony's Wayland embedder, 0 GTK/GDK deps
lib/libflutter_engine.so  official engine, exports FlutterEngineRun
lib/libapp.so             AOT, carries _kDartVmSnapshotData and
                          _kDartIsolateSnapshotInstructions
data/flutter_assets/      from the desktop build
data/icudtl.dat
```

48 MB. It was not run on this host, which has no Wayland or DRM; the
runtime-verification workflow has since run a release bundle assembled this
way, with the from-source release engine in place of the official one, on a
virtual device.


**What actually blocks webOS, measured rather than assumed.** This file has
said at various times that webOS needs a Dart 3.12 embedder, and that its
engine is a vendor build only LG can produce. The second is wrong and the first
is downstream of something more specific.

LG's `libflutter_engine.so` was downloaded and inspected. It exports
`FlutterEngineRun`: it is an ordinary Custom Embedder API engine, not a
proprietary one. LG's runner template is even derived from Sony's — the file
carries "Copyright 2021 Sony Corporation" — so webOS Flutter is the same
architecture as eLinux, which already works.

The binary is **ELF 32-bit ARM**. Google publishes `linux-x64` and
`linux-arm64` embedder engines and **no 32-bit `linux-arm`** — that URL returns
404 where the arm64 one returns 200. webOS televisions run a 32-bit ARM
userland, so there is no published engine to link against, and that is the
whole of the blocker.

It follows that webOS needs the same treatment eLinux needed: an engine built
from source, for `linux_release_arm`. That is a build to run, not a vendor to
wait for — but "accepts `arm`" was, for a week, only true of the dropdown.

**Three things had to be fixed before that build could compile, and the first
one was mine.** `engine-build.yml` took an `arch` input, put it in the artifact
filename, and ran `et build -c host_<mode>` regardless. A request for 32-bit
ARM produced an x86-64 engine, uploaded it as `engine-arm-release`, and
reported success — the workflow asserted a name rather than a behaviour, which
is the defect class this repository has a rule about. `dartvel engine verify`
now reads the ELF header of what was built and fails the job before the
upload; run against that artifact it says `libflutter_engine.so is x64,
expected arm32`.

The other two are in the engine, and both are the same shape: Linux/arm is a
configuration the stock build does not cover.

* `build/config/sysroot.gni` assigns a default sysroot for x64, arm64 and
  riscv64 and nothing else, so gn stops at `Undefined identifier: sysroot`.
  The sysroot exists — `sysroots.json` lists `bullseye_armhf` and
  `install-sysroot.py` already translates `--arch=arm` to it — so it only has
  to be named, via `--target-sysroot`, as an absolute path (gn resolves a
  relative one against the output directory).
* `build/config/compiler/BUILD.gn` emits `-march`, `-mfloat-abi`, `-mfpu` and
  `-mthumb` for `current_cpu == "arm"` while its Linux target-triple block
  covers arm64 only, so clang is handed ARM flags and still targets the host:
  `unsupported option '-mfloat-abi=' for target 'x86_64-unknown-linux-gnu'`.
  The answer is `build/toolchain/custom`, which takes a toolchain, a sysroot
  and a triple and whose own comment gives `arm-linux-gnueabihf` as the
  example. Its `${triple}-ar`/`-readelf`/`-nm`/`-strip` are assembled as links
  to the engine's own target-agnostic LLVM tools.

The float ABI is set to `hard` explicitly. `arm.gni` defaults armv7 to
`softfp`, a different calling convention from the armhf sysroot's; the two
link without complaint and pass floats in the wrong registers, so nothing
would fail until a television ran it.

**It builds.** `engine-build.yml` produced a 32-bit ARM release engine on
2026-08-26 from Flutter 3.44.5, and the artifact was inspected rather than
inferred from a green check:

```
libflutter_engine.so   ELF 32-bit LSB shared object, ARM, EABI5
gen_snapshot           ELF 64-bit LSB pie executable, x86-64
Tag_CPU_arch: v7   Tag_FP_arch: VFPv3-D16   Tag_ABI_VFP_args: VFP registers
```

`gen_snapshot` being x86-64 is correct and not an oversight: it runs on the
builder and emits code for the target, so a cross build produces a host
snapshotter beside a target engine. `Tag_ABI_VFP_args: VFP registers` is the
hard-float ABI, which is what makes the `arm_float_abi` argument above
load-bearing rather than cosmetic. `nm -D` finds `FlutterEngineRun` and its
neighbours, so it is a Custom Embedder API engine of the same shape as LG's.

**Two more walls fell after the ones above, and the second undid the first.**
The link stage wanted `libclang_rt.builtins.a`, then `-lc++` and `-lunwind`,
and each looked like a separate missing package — an armhf libgcc was
substituted for the builtins, and a two-pass ninja staged libc++ into the
toolchain. Both were solving a problem that did not exist. clang resolves all
three by triple, and the directory it ships is
`armv7-unknown-linux-gnueabihf`; the requested `arm-unknown-linux-gnueabihf`
does not exist, so nothing inside it did either. One string. The workarounds
were deleted and the triple is now asserted against clang's own runtime
directories before a build starts, so a wrong one fails in two seconds with
the sixteen that do exist printed.

The last of them was smaller: a bare `ninja` builds the default target group,
which for a Linux cross build is the GTK shell. It linked
`libflutter_linux_gtk.so`, never touched `libflutter_engine.so`, and reported
success. The build names the artifacts it collects now.

**The package assembles.** `runtime-verification.yml` builds one in CI from
the ARM engine, and the artifact was inspected rather than inferred:

```
com.dartvel.example/appinfo.json          type: native, com.dartvel.example, 1.0.0
com.dartvel.example/lib/libflutter_engine.so   ELF 32-bit LSB shared object, ARM, EABI5
com.dartvel.example/lib/libapp.so              ELF 32-bit LSB shared object, ARM, EABI5
com.dartvel.example/data/flutter_assets/…
com.dartvel.example/data/icudtl.dat
```

Getting `libapp.so` there took three wrong turns worth recording, because each
looked like the obvious move:

* `flutter build bundle --release` emits no `kernel_blob.bin`. A release bundle
  is already AOT for the host, so there is nothing for `gen_snapshot` to read.
* The debug `kernel_blob.bin` holds only the application's code. The platform
  is supplied separately by the debug engine at run time, so an AOT compiler
  has no `dart:core` to resolve against and aborts with *"Unable to use class
  Library:'dart:core' … which is not loaded yet"*.
* The kernel therefore has to be compiled against the AOT platform, by the
  frontend server Flutter ships — under `dartaotruntime`, since
  `frontend_server_aot.dart.snapshot` is an AOT snapshot and refuses the JIT
  runtime. The patched SDK is kernel and architecture-independent, which is
  why the host's copy serves a target Flutter has no toolchain for.

**The app renders on ARM.** `qemu-user` executes 32-bit ARM binaries on an
x86-64 machine, so the question "does the engine work" does not need a
television or an ARM runner — only the question "does LG's window and input
stack work" does. [`tool/webos/render_probe.c`](../tool/webos/render_probe.c)
starts the engine with the software renderer, sends one window-metrics event
and photographs what it draws. Run against the artifacts the `webos` job
builds, it produces the Dartvel example's own page — the showcase heading, its
About and Pricing links, and the platform cards — at **800x480, 1,288 colours,
36.75% dominant**. The `webos` job runs it on every push and uploads the frame.

It photographs the *settled* frame rather than the first one. The first frame
is the shell alone, because a page's content arrives over a deferred load, so
stopping there produced an app bar above an empty body — 120 colours, 90.83%
of them one background — and called it a rendered application. That is the
difference between checking the engine and checking the app.

The frame is checked with `dartvel capture verify` rather than `test -s`,
because a crash before the first frame leaves a buffer that is one colour and
one colour passes every check that only stats the file. Note what that check
did *not* catch on its own: an app bar over an empty body is not one colour,
and it passed.

Two failures on the way there both read as a broken engine and were both a
missing argument, so they are written down rather than left to be
rediscovered. `FlutterRendererConfig` is a **union with no `struct_size`**; a
copy of it made by eye as a struct with one returns `kInvalidArguments`. And a
release engine has **no interpreter**, so the AOT snapshot has to be handed
over through `FlutterEngineCreateAOTData` — without it the engine stops at
*"VM snapshot invalid and could not be inferred from settings"*.

**It also runs in a window.** `webos-window.yml` cross-compiles **Sony's own
Wayland client** for armhf — webOS's runner template is Sony's, so this is the
binary a television launches rather than a stand-in written for the test — and
runs it under `qemu-arm-static` against Weston on Xvfb, the same virtual device
the `sony-elinux` job uses. The app fills the compositor's 1280x720 output:
heading, nav links, the platform cards and the State & Signals section.

That covers the window, the surface and the GL path (llvmpipe, since a runner
has no GPU). What the offscreen render could not reach, this does.

**The gate is the runner, not the picture.** The first version of that job went
green on a photograph of Weston's *empty desktop*, because the runner had died
at once — the engine sits in the bundle's `lib/` and nothing told the loader to
look there. A bare compositor is a textured grey with a clock in the corner: it
has plenty of colours and no dominant one, so it satisfies every check
`capture verify` makes. That verifier exists to refuse a blank screen and it
did that correctly; a compositor with no client on it is not blank, and no
tightening of a colour check would have caught it. The job now requires the
runner to still be alive when the photograph is taken and its log to be free of
loader and startup failures.

**What is still not established.** LG's own surface manager and its
remote-control input. Weston is a real compositor but it is not LSM, and
nothing here presses a button on a remote. Settling that needs
`ares-install` against a real set.

**LG's emulator cannot stand in for one, and this is checked rather than
assumed.** The webOS TV emulator ships as a VirtualBox appliance, and
VirtualBox is a virtualiser rather than an emulator: it runs x86 guests on x86
hosts and cannot execute an ARM guest at all. webOS OSE's QEMU emulator is
explicit about the same limit — *"the emulator only supports the x86 (x86_64)
machine architecture"*, built with `--target-list=i386-softmmu`. Neither would
load the ARM engine this target is built around.

So the emulator is not a cheaper approximation of a television, it is a
different question. Using it would first require an **x86 webOS engine**,
which is a second engine build, and what it would then exercise is LG's window
and input stack — the part that is actually open — while testing none of the
ARM work. Worth doing for that reason and not for the obvious one; a real set
tests both at once.

Sources: [webOS OSE QEMU emulator guide](https://www.webosose.org/docs/tools/sdk/emulator/qemu-emulator/qemu-emulator-user-guide/),
[webOS TV emulator](https://webostv.developer.lge.com/develop/tools/emulator-introduction).

**webOS was checked the same way and is not out of the group.** LG publishes
artifacts at `lg-flutter-webos/artifacts`, and the newest release is recent —
`c6f67dede3-webos26-1`, 2026-06-29 — which looks encouraging and is not. That
tag's Flutter commit `c6f67dede3` resolves to **Flutter 3.38.10** (tagged, Feb
2026), whose Dart is 3.10.9 and below Dartvel's floor. It is new artifacts for
an old Flutter.

The difference from Sony matters: Sony's embedder links the *official* engine,
so Google publishing one for our revision was enough. LG's is a webOS platform
engine that only LG builds, so there is no official artifact to substitute and
no public recipe to reproduce it. webOS stays blocked on a vendor build, and
that is a genuinely different position from eLinux.

**Sony eLinux is out of this group too, and for the same reason.** The premise
was that it needed a Flutter engine built from source. It does not, and the
check cost minutes:

- Sony's `elinux-x64-release.zip` is the **official engine** at their pinned
  revision, plus their own embedder libraries, plus `gen_snapshot`. Both
  engines were downloaded and compared — they differ only in the revision
  string they carry. Sony does not patch the engine; they build an embedder on
  the stable Custom Embedder API above it.
- Google publishes, for Dartvel's exact engine, `linux-x64` and `linux-arm64`
  embedder libraries plus `artifacts.zip` (`gen_snapshot`, `icudtl.dat`,
  `impellerc`). All seven URLs return 200.
- Sony's embedder source **compiles and links against that engine**, verified
  by the `Embedder artifacts` workflow: `flutter-client` (Wayland),
  `flutter-drm-gbm-backend` and `flutter-drm-eglstream-backend` all build, and
  the resulting ELF binaries carry `NEEDED libflutter_engine.so` and import
  `FlutterEngine` symbols. Sony's newest published build is a year older than
  this engine, so that compatibility was the real unknown and is now answered.

What is left for the target is not an engine, and it is not plumbing either —
calling it that was wrong. Two things stand in the way, and they are different
sizes:

- **Debug and profile still need an engine build.** Google publishes exactly
  one standalone `libflutter_engine.so` per revision and it is the **release**
  build: 41.7 MB, against Sony's release 42.6 MB, profile 52.5 MB and debug
  381 MB, all three of which have distinct hashes. The per-mode directories
  carry `linux-{arch}-flutter-gtk.zip`, where the engine is statically linked
  into the GTK embedder and cannot be reused. `.github/workflows/engine-build.yml`
  builds the missing modes.
- **`flutter-elinux`, the tool, is pinned to Flutter 3.29.3**, and upstream has
  not committed since 2025-07-09. Its classes subclass `flutter_tools`
  internals, so moving it to 3.44.5 is a port across fifteen minor versions
  rather than a version bump. That is now the binding constraint for
  `dartvel build sony-elinux`, and it is the larger of the two.

There is a way around the second that is worth weighing before paying for it:
an eLinux application is the embedder executable, `libflutter_engine.so`, the
app's AOT `app.so`, `icudtl.dat` and the asset bundle. Every one of those can be
produced by stock Flutter 3.44.5 plus the artifacts above — `flutter build
bundle` and `gen_snapshot` — which would let Dartvel assemble the bundle
directly and never invoke `flutter-elinux` at all.

The terminal embedder was in this group and is not any more. `dartvel_cli_flt`
pinned Flutter 3.38.5, below Dartvel's floor — but the prebuilt
`linux-x64-embedder` artifact **is** published for Dartvel's engine, so the
re-pin needed four source changes rather than an engine build, and the fork now
compiles against 3.44.5. Worth stating plainly because it is the counterexample:
being behind the floor does not by itself mean an engine build, and the way to
tell is to check whether the artifact exists rather than to assume.

webOS, Sony eLinux and Fuchsia each met an embedder tool shipping a Dart older
than Dartvel needs. The distances are very different, and conflating them
would send the work in the wrong direction:

| Target | Embedder's Dart | Short by | Where it stands |
| --- | --- | --- | --- |
| webOS | 3.10.9 | 1.1 against the 3.12 floor | `dartvel build webos` skips; CI assembles and runs the package without `flutter-webos` |
| Sony eLinux | 3.7.2 | Well short of 3.12 | No longer the wall: `dartvel build sony-elinux` assembles without `flutter-elinux` |
| Fuchsia | **older than 3.4** | Short of Dartvel's own example, before the UI layer is reached | Re-pin the fork's Flutter **and rebuild its engine** |

**webOS changed shape once `dartvel_mix` existed, and got further away
rather than closer.** This section previously asked whether pub's `mix 2.1.0`
really needed Dart 3.11 or was merely conservative, because an older published
`mix` would have cleared webOS's 3.10.9 by a hair. That question is now
retired, twice over. `dartvel_flutter` now declares pub's `mix ^2.2.0-beta.5`,
which needs Dart 3.11, and imports nothing from it: `DVBox` and `DVText` are
Dartvel's own modifier layer over Flutter widgets. The floor that stops webOS
is the 3.12 every Dartvel package declares, so the gap is 1.1.

The useful part is that **the floor is now a Dartvel decision rather than an
upstream fact.** Nobody has to pin a pre-release UI dependency for the whole
framework to move it. There are two levers, and they are both ours:

1. **Rebuild the webOS engine** against a Flutter whose Dart clears 3.12. This
   is the same work Sony eLinux needs, and it is the one that leaves the fork
   pinned where the rest of the project is.
2. **Lower `dartvel_mix`'s floor**, if nothing in it genuinely requires 3.12.
   Cheap if true, but it pulls one fork off the shared pin, and the whole point
   of the fork table is that the pins are tracked together.

Lever 1 is the right default. Lever 2 is worth measuring before committing to
an engine build, because the measurement is an afternoon and the engine build
is not — but it should not be taken merely because it is cheaper.

Fuchsia gets no benefit from any of that. Its Flutter cannot run Dartvel's own
example, so it needs the re-pin and engine build regardless of what `mix`
requires.

### Sony eLinux

**`dartvel build sony-elinux` no longer uses `flutter-elinux`, so the Dart
3.7.2 wall below is history.** It assembles a release bundle from the Linux
desktop release build and Sony's embedder artifacts (see
`packages/dartvel_cli/lib/src/build/elinux_bundle.dart`), refuses debug and
profile, and skips when the artifacts are not installed. The runtime-verification
workflow runs debug and release bundles assembled the same way. What follows is
what the `flutter-elinux` route hit, kept because it is why the route changed.

**Through `flutter-elinux`: Flutter 3.29.3 / Dart 3.7.2 — blocked.**

The embedder installs and runs, and the engine artifacts download fine
(`elinux-x64-{debug,profile,release}.zip` at engine `cf56914b32`, all HTTP
200). The build then fails at dependency resolution:

```
The current Dart SDK version is 3.7.2.
Because every version of dartvel_shelf from path depends on
code_assets >=0.19.1 which requires SDK version >=3.9.0-21.0.dev <4.0.0,
dartvel_shelf from path is forbidden.
```

`dartvel_shelf` compiles the Rust backend through a Dart native-asset build
hook, which requires `code_assets ^0.19.7` and therefore **Dart ≥ 3.9.0**.
The newest Flutter the eLinux embedder supports ships Dart 3.7.2.

This is worth stating precisely, because it is easy to get wrong: the blocker
is **Dartvel's own dependency floor meeting the embedder's Flutter ceiling**,
not a missing engine. Sony's newest published engine is `ef0cd00091`
(2025-07-25); the 3.44.5 engine `83675ed276` returns HTTP 404. So the ceiling
is real, but the floor is what the build actually hits first.

Unblocking it requires an eLinux Flutter engine built for a Dart ≥ 3.12
release. That is a from-source engine build rather than a version-pin bump —
but it is **our** build to do, not something to wait on Sony for. The whole
reason `dartvel_elinux` is a fork is that it can be pinned and patched ahead of
upstream; inheriting Sony's Flutter pin is a choice this fork has not yet
un-made, not a limit the vendor imposes on us.

### webOS (LG)

**Verified Flutter: 3.38.10 / Dart 3.10.9 — `dartvel build webos` is blocked.**
A package assembled without `flutter-webos` renders on ARM in CI; see
[What actually blocks webOS](#runtime-verification) above. No `dartvel`
command builds that package yet.

The embedder and the `ares` CLI both install cleanly through auto-install, and
`dartvel build webos` now generates the `webos/` scaffold itself rather than
requiring the manual step Tizen needs. The scaffold is written — seven files,
`CMakeLists.txt`, `runner/main.cc`, `meta/appinfo.json` and the rest — and then
the embedder's own dependency resolution refuses the project:

```
The current Dart SDK version is 3.10.9.

Because every version of dartvel_flutter from path depends on mix >=2.0.0 which
requires SDK version >=3.11.0 <4.0.0, dartvel_flutter from path is forbidden.
```

**This is a floor, and it is not the floor the target was previously measured
against.** The earlier note reasoned that Flutter 3.38.10 "should clear the
Dart ≥ 3.9 floor" — true, and irrelevant. That 3.9 floor is `code_assets`, what
`dartvel_shelf`'s build hook needs. The binding constraint is higher and comes
from the UI layer: `dartvel_flutter` depends on `mix: ^2.0.0`, which requires
Dart ≥ 3.11.0. The embedder ships 3.10.9, so **no Dartvel application can build
for webOS at all** — this fails before any webOS engine or `ares` packaging
question is reached.

Like Sony eLinux, a version-pin bump alone cannot fix it. Unlike Sony eLinux,
the wall is the Dart SDK the embedder bundles rather than a missing prebuilt
engine artifact.

The error above was captured against pub's `mix` and its 3.11 floor. Dartvel
now depends on `dartvel_mix` at 3.12, so the same resolution fails the same way
with a larger number; the shape of the failure is unchanged.

**This is not a wait-on-LG blocker.** `dartvel_webos` is a fork precisely so it
does not have to ship whatever Flutter LG last pinned; the fork currently
inherits that pin, which is a thing to change rather than a constraint to
report. Unblocking means moving the fork to a Flutter whose Dart clears 3.12
and building the webOS engine from source for it. Whether an LG-published
engine happens to exist for such a version is a convenience, not the gate.

### tvOS

Apple publishes no tvOS Flutter embedder. The target rides the community
[`fluttertv/flutter-tvos`](https://github.com/fluttertv/flutter-tvos) CLI,
forked as [`dartvel_tvos`](https://github.com/Danroyal001/dartvel_tvos).

**Upstream pins Flutter 3.44.8** (revision `058e0af2c2b57e369d905a03ac9748b0ebf543c6`)
with origin-signed tvOS engine artifacts `v1.0.2-flutter3.44.8`. Dartvel targets
3.44.5, so the embedder is three patches **ahead** — the same minor, and clear of
both walls the other forks hit: no missing prebuilt engine as on Sony eLinux, and
no Dart 3.9 floor problem. The embedder carries its own Flutter SDK, so a tvOS
build compiles against 3.44.8 rather than the 3.44.5 pinned elsewhere.

The build command is `flutter-tvos build tvos`, **not** `flutter build ios`.
Device builds are AOT and require a configured Xcode signing team;
`--simulator --debug` is the only unsigned path, which is what CI can use.

On a macOS runner the fork clones, bootstraps, and precaches its own engine
cleanly: all six tvOS engine variants (`tvos-debug-sim-arm64` through
`tvos-host-release`) fetch in about 15 seconds, confirming the origin-signed
artifacts for 3.44.8 genuinely exist. `flutter-tvos doctor` then reports
Flutter 3.44.8 from the fork's own checkout.

`examples/dartvel_example` has no `tvos/` directory, exactly as it has no
`tizen/`, and calling the embedder directly stops at "This project is not
configured for tvOS." Rather than making that a manual prerequisite the way
Tizen's is (step 1 below), `dartvel build` generates a missing platform
scaffold through the embedder's own `create` (`d0874755`, covering tizen,
sony-elinux, webos and tvos).

**Runs on a simulator (debug).** In run
[35025146988](https://github.com/Danroyal001/dartvel_dev/actions/runs/35025146988)
`dartvel build tvos --simulator` wrote the scaffold ("Created tvOS-only
project"), finished the Xcode build and produced
`build/tvos/Debug-appletvsimulator/Runner.app`. The job installed it on an
Apple TV simulator, launched it and took a screenshot. The screenshot shows
the example's home page reporting `Platform: tvos` and `Device: tv`, so the
`DARTVEL_PLATFORM=tvos` define reaches the running app. A signed device build
has not been run.

Before that run the job never reached the embedder. `dartvel build` refused
the example with exit 78 at the module trust gate. It read two lines of the
`notes` module's generated client as the module's own egress and cron, and
that was fixed in `94877d65`.

**Any earlier "passing" tvOS build was not one.** Until `b25b025a` the CLI
mapped `tvos` onto the iOS toolchain and ran `flutter build ios --no-codesign`,
so the matrix reported a green tvOS job for an iPhone app.

---

### Device file storage (`DV.Platform.fileStorage`, `dartvel.fileStorage`)

Checked on 2026-10-02 against a copy of `examples/basic_app` declaring
`access: [photos, media, documents, allFiles]`, a reason and `shareAppFiles`.

| Target | Storage location | User-picked files | Permissions applied | Evidence |
|---|---|---|---|---|
| Android | `<filesDir>/dartvel-files`, cache `<cacheDir>/dartvel` | `media.pick` (ACTION_OPEN_DOCUMENT, private copy); no folders | Manifest per API level: READ_MEDIA_IMAGES/VIDEO/AUDIO, READ_MEDIA_VISUAL_USER_SELECTED, READ_EXTERNAL_STORAGE ≤32, MANAGE_EXTERNAL_STORAGE, WRITE_EXTERNAL_STORAGE ≤29; all-files access through the Settings switch | **Verified by build**: `dartvel build android` produced a release APK; `aapt2 dump permissions` lists each permission once with the caps above; `classes.dex` carries the Settings intent and `isExternalStorageManager`. Not run on a device |
| Web | origin private file system, cache in `.dartvel-cache` | file input in every browser; folders via `showDirectoryPicker` (Chromium, read/write) or a folder input (read only) | none at build time: the browser asks when the person picks | **Verified in headless Chrome** (`flutter test --platform chrome test/device_storage_browser_test.dart`, its own browser): put/get/exists/list/delete, truncation, 404, cache separation, and data written by `DV.Platform.files` read back. Pickers need a person and are not automated |
| Linux, embedded Linux | `$XDG_DATA_HOME/<app>`, cache `$XDG_CACHE_HOME/<app>` | GTK choosers through `media.pick` and `dialogs.chooseDirectory` | none needed | unit tests on the Linux VM: the directory resolution and the real disk round-trip |
| iOS | `Documents`, cache `Library/Caches/dartvel` | `media.pick` through the Swift shim: PHPicker for images and video, the document picker otherwise, each a private copy in tmp | Info.plist: NSPhotoLibraryUsageDescription, NSPhotoLibraryAddUsageDescription, UIFileSharingEnabled, LSSupportsOpeningDocumentsInPlace | **Unverified on device.** The plist block is unit-tested and was applied to `examples/dartvel_example/ios/Runner/Info.plist`. `media.pick` and `permissions.request` are bound through the shim (2026-10-09) and not yet run; see [iOS device bindings](#ios-device-bindings) |
| macOS | `~/Library/Application Support/<app>` | open and folder panels | Info.plist NSPhotoLibraryUsageDescription; entitlements files.user-selected.read-write and assets pictures/movies/music read-only; allFiles reported as impossible in the sandbox | **Unverified on device.** Unit-tested; the entitlements applied to `examples/dartvel_example/macos/Runner/Release.entitlements` parse as a valid plist |
| Windows | `%LOCALAPPDATA%\<app>\Files` | open and folder dialogs | none needed | **Unverified on device.** Directory resolution unit-tested |

### iOS device bindings

Added 2026-10-09: 37 of 103 binding names on iOS, from 8 (`dart tool/binding_coverage.dart`). 20 of them go through
`ios/Runner/DartvelPlatform.swift`, which `dartvel build ios` writes and adds to the Runner target's Sources phase;
`dartvel.ios.permissions` in `pubspec.yaml` becomes Info.plist usage descriptions. The list and the reasons are in
`docs/platform-api-coverage.md`.

| What | Status | Evidence |
|---|---|---|
| Binding plan: what each binding sends the shim and what it makes of the answer | **Verified on Linux** | `packages/dartvel_flutter/test/ios_shim_plan_test.dart` against a fake shim |
| The Swift: a case for every operation, the four `@_cdecl` symbols, usage-key checks, no platform channel | **Verified on Linux, as text** | `packages/dartvel_cli/test/ios_platform_shim_test.dart` |
| Xcode wiring and Info.plist block | **Verified on Linux** | the same test, against the example's real `project.pbxproj` |
| The Swift compiles | **Unverified** | needs Xcode; the `ios-device-apis` job in `runtime-verification.yml` runs `dartvel build ios --simulator --debug` |
| The bindings answer on a simulator | **Unverified** | the same job runs `integration_test/ios_device_apis_test.dart`: geometry, clipboard, haptics, permissions, location, contacts, NFC and biometrics availability, the network signal, files and device health |
| Camera, pickers, share sheet choice, Face ID prompt, Guided Access | **Unverified, and not automatable on a simulator** | need a person, a camera or a supervised device |

The job was added while GitHub Actions on the account was billing-locked, so it has not run. Until it is green these
bindings are Partial on iOS.

### Application key custody on phones

`.github/workflows/key-custody.yml` puts the application key in the keyring each
platform offers, then reads it back from a new process. Verified by run
[34843926517](https://github.com/Danroyal001/dartvel_dev/actions/runs/34843926517)
on commit `09b4c8ed`, 2026-09-14. All three jobs were green, and each row below
is from that job's own report, not from its exit code alone.

| Target | Store | What the run showed |
| --- | --- | --- |
| `android` | `DVAndroidKeystoreAppKeyStore` | API 34 `google_apis` x86_64 emulator. One installed debug build of `app_key_custody_probe.dart` was launched twice, with a `force-stop` in between and `pidof` empty before the second launch. The generated runtime's `DVWindowSharedStore.defaultAppKeys` was the Keystore store. The Keystore held `dartvel.appkey.dartvel_example` with `exportable: false`. The second launch opened canaries sealed under both keys by the first. A key planted in the old file layout was moved in, and the file was removed. Scans of `/data/user/0/com.example.dartvel_example` read 5 and 6 files and found no key bytes, raw or base64 |
| `ios` | `DVKeychainAppKeyStore` | iPhone simulator, same probe. Two `simctl launch` runs with a terminate in between. The wired store was the Keychain, and the item read back `accessible: cku` (after first unlock, this device only) and `synchronizable: false`. Canaries opened after the restart, the planted key was moved in, and scans of the data container read 13 and 14 files and found no key bytes |
| `macos` | `DVKeychainAppKeyStore` | An unsigned `dart test` process on the runner: round-trip, replace in place, clear, accounts kept apart, plus the custody rules suite (29 passed, 2 skipped as not-this-platform) |

Why a probe and not `flutter test`: `flutter test` uninstalls the application
when it finishes, and an uninstall deletes the Keystore entry and the Keychain
item. A second run would start from nothing.

What the run found that the code did not assume: **`HOME` is unset in the
application process** on both the emulator and the simulator. The file store
those platforms used to get therefore resolved to `./.dartvel/keys/<app>.key`,
relative to a read-only filesystem root, and the probe could not plant a key
there ("Read-only file system"). No earlier version could have kept a key at
that path in those environments. The move was exercised through a second
application id whose old file was planted inside the data directory. That
path is the same code, not the same location.

Not shown by this run:
- Real devices, hardware-backed (TEE or StrongBox) Keystore keys, and a signed
  iOS build.
- A device locked before first unlock. That refusal is covered only by the
  pure-Dart tests of `dvKeychainRefusal` and the migrating store.
- Which accessibility class macOS reports. The macOS assertion accepts an item
  that reports none, and a passing test prints nothing.
- Anything beyond the application's own data directory. The scans are small,
  and they check the one thing this change could put on disk.

---

## CI for hosts you do not have

`.github/workflows/platform-build-matrix.yml` builds `windows`, `macos`, `ios`,
and `tvos` on GitHub-hosted runners, which is the only place they can honestly
be verified from a Linux machine.

It is **manually triggered** (`workflow_dispatch`) on purpose. This repository
is private, so runner minutes bill against the account quota with a **2×
multiplier on Windows and 10× on macOS**. Running it on every push would be
expensive and rarely more informative than running it deliberately.

The workflow installs `cbindgen` explicitly. `dartvel_shelf`'s build hook skips
Rust compilation when `cargo` is missing, but treats a missing `cbindgen` as a
hard error — and hosted runners ship cargo without cbindgen. It also asserts an
artifact exists rather than trusting the build command's exit code.

### Why a hang is the expensive failure

A build that *fails* is cheap: a job that dies on a compile error costs a few
minutes. A build that **hangs** bills to the job's timeout, and a hung job is
invisible — `dartvel build macos` once printed "Building for macos..." and then
nothing at all for five hours and fifty-six minutes before GitHub's own 6-hour
cap killed it. At the macOS 10x multiplier that single job cost more than every
other job across four runs combined.

Two guards followed. The hook can no longer block indefinitely (`db93571b`),
and every job now carries `timeout-minutes: 45` (`d568dff9`) — generous
against a sub-ten-minute successful build, and roughly an eighth of what one
hang cost.

### What a macOS run actually costs

Measured on run 32201351600, which was given an 8-minute cap against a $1
budget and hit it:

| Phase | Time |
|---|---|
| Flutter setup, `cargo install cbindgen`, `pub get` | 2m33s |
| Rust runtime compile, inside the build step | ~2m36s |
| `flutter build macos` before the cap | ~3m (incomplete) |

Setup is most of a short run, and at the 10x multiplier it costs more than the
build it exists to enable. Both halves are now cached — the cbindgen binary,
and the Rust target directory keyed on the crate's own sources — so a repeat
run should reach Xcode in about a minute rather than four and a half. Budget a
macOS attempt at **15 minutes** (~$1.20 uncached, considerably less warm);
8 was sized from the iOS job's total and did not account for a full Xcode
application build.

Unselected matrix entries are gated at the job level rather than in a step,
because a skipped step still starts a runner: three four-second gated jobs on
that run billed roughly 22 minutes between them.

**Runner minutes are billed against the repository owner's account, and this
repository is public — so they are unlimited and free on standard runners,
Windows and macOS included.** The multipliers above apply only to private
repositories.

That was assumed the other way round for a while, and the assumption did
damage worth naming: the macOS binding job was narrowed to a single suite, the
platform matrix was kept manually triggered, and Apple targets were bundled
into one job — all to save minutes that were never being spent. Scope was
rationed against a cost that did not exist.

Wall-clock time is still real, and a hung job still occupies a runner for
hours. Bound jobs with `timeout-minutes`, not by leaving things out.

---

## Dartvel Cloud

`dartvel build <target> --cloud` sends the project to a worker running the
target's operating system, and the worker runs the same `dartvel build
<target>` with `--auto-install`. Every target below was built end to end in
the private `dartvel_enterprise` repository's `cloud-e2e.yml`, all in run
35232282996 on 2026-09-17: the service and a worker started on the runner,
the public CLI ran `dartvel build <target> --cloud` from `examples/basic_app`,
the download was kept only after each file's size and SHA-256 matched, and
`tool/ci/cloud_artifact_check.dart` checked it was that target's build.

| Target | Worker | What came back | What the worker image provides |
|---|---|---|---|
| `android` | Linux | `app-debug.apk`, 157 MB, manifest, dex and compiled Dart | Java 17, the runner's Android SDK |
| `fireos` | Linux | `app-debug.apk`, 157 MB, the same checks | The same |
| `ios` | macOS | `Runner.app` with a Mach-O `Runner` | Xcode |
| `tvos` | macOS | Simulator `Runner.app` whose plist names `appletv`, Mach-O `Runner` | Xcode. The `flutter-tvos` embedder is installed by the build |
| `sony-elinux` | Linux | Release bundle: `flutter-client`, engine, AOT `libapp.so`, no GTK runner | Sony's `flutter-client` built against the official engine, and the from-source release engine, under `~/.dartvel/toolchains/dartvel_elinux/artifacts` |
| `tizen` | Linux | Signed TPK, 9.5 MB, with `author-signature.xml`, `libflutter_engine.so` and `libapp.so` | Tizen Studio 10.0 CLI installed with `--accept-license`, `NativeToolchain-Gcc-9.2`, `IOT-Headed-6.0-NativeAppDevelopment-CLI`, an author certificate and an unlocked keyring, as flutter-tizen's own CI installs them |

A tvOS cloud build must be asked for with `--simulator`: a device build is
signed with a team Cloud does not keep, so it is refused before the source is
sent.

Four fixes came out of running these rather than reading them, and each was a
bug in the local build too:

- `dartvel build linux-cli` had never built through the command. Preflight
  checked plain `linux`, so the embedder was never installed; the install was
  `cargo install` of a package name that does not exist; and the build passed
  `--debug` to `dartvel-cli-flt`, which accepts only `--release`.
- `dartvel build sony-elinux` defaulted to arm64 and then refused to assemble
  arm64 on an x64 host. It now defaults to the host.
- The VS Code generator wrote `"main": "./out/extension.js"` while tsc emitted
  `out/src/extension.js`, so the extension could not activate. Fixed in the
  `dartvel_vscode` fork.
- `--cloud linux-cli` was sent as `linux`, which a worker would have built as
  the GUI app.

**Not on Cloud:**

| Target | Why |
|---|---|
| `webos` | `dartvel build webos` skips on every host: LG's `flutter-webos` bundles Dart 3.10.9, below Dartvel's 3.12.0 floor |
| `macos`, `windows`, `linux`, `web`, `web-server` | Accepted by Cloud and not yet built end to end by `cloud-e2e.yml` |

---

## Distribution images

`sony-elinux-iso` and `sony-elinux-img` build the bundle and then report that
image assembly needs the configured Sony eLinux imaging toolchain. Dartvel does
not bundle one and does not emit a placeholder file in its place. These formats
are excluded from `dartvel build` with no argument, since they are explicit
packaging steps rather than part of a general build.

## Launch splash

`dartvel build` writes the splash each target shows before its first frame,
from `dartvel.splash` (see [getting-started](getting-started.md)). What it
writes, and what it leaves alone:

| Target | What is written | Verified |
|---|---|---|
| `web`, `web-server` | A stylesheet in the head and an element first in the body of `build/web/index.html`, so every prerendered page has it; `dartvel-splash.png` beside it when there is an image. The engine appends `<flutter-view>` after the splash, so the application covers it as soon as it paints, and a `flutter-first-frame` listener then removes it. Hidden with scripting off, where the page's content is the noscript block | In Chrome, by pixels: `test/native_splash_browser_test.dart`, with a negative control for each claim |
| `android`, `fireos` | `values/dartvel_splash.xml` and `values-night/` (the colour), `drawable/` and `drawable-v21/launch_background.xml`, `drawable-{mdpi…xxxhdpi}/dartvel_splash_image.png`, and `values-v31/styles.xml` and `values-night-v31/`, because from API 31 the system draws its own splash and ignores a layer-list window background | Files unit-tested; not yet run on a device |
| `ios` | `Base.lproj/LaunchScreen.storyboard` naming the colour `DartvelSplashBackground`, whose colorset carries the dark appearance, and `LaunchImage.imageset` at 1x, 2x and 3x | Files unit-tested; not yet run on a simulator. iOS caches launch screens, so a change can need the app deleted and reinstalled to show |
| `macos` | One marked line in `MainFlutterWindow.swift` setting `flutterViewController.backgroundColor`. The window is visible at launch and FlutterView is black until the first frame | Unit-tested; compiled by the macOS CI job |
| `linux` | The template's `gdk_rgba_parse(&background_color, "#000000")` in `my_application.cc`, which is the colour behind the view. The GTK runner already shows its window only on the first frame, so there is no blank window to paint. **Light colour only**: the runner has no dependable way to read the desktop's dark preference | Unit-tested |
| `windows` | **Nothing, deliberately.** `flutter_window.cpp` registers `SetNextFrameCallback` and shows the window from it, so the window does not exist on screen until Flutter has drawn | — |

The embedder targets (`tizen`, `sony-elinux`, `webos`, `tvos`) get no splash yet: their launch is owned
by the vendor embedder or the host, and none of them was checked for what it
shows before the first frame.

A platform file is replaced only while it is still Flutter's template or
carries the `dartvel:splash` marker. One designed by hand is left alone and
the build says so; `dartvel.splash.overwrite: true` replaces it. Deleting the
marker comment from a written file hands it back.

## When a target skips

`dartvel build <target>` skips rather than fails when the toolchain says it
cannot serve, and the message names which wall it hit. There are three, and
CI passes a skip only for these — a skip that says nothing is still a
failure, and so is "not found on PATH", because an embedder that should have
been installed and was not is a regression rather than a wall.

| Wall | What is printed | Why it is not a failure |
|---|---|---|
| Licence-gated SDK | `Skipping tizen` with `Tizen Studio SDK` | Dartvel must never install it, so no runner can ever produce a TPK |
| The embedder's Dart is below the floor | `bundles Dart <version>` before anything is generated, or `the embedder resolved with Dart <version>` when the embedder has no CLI to ask and its own pub is the first thing to say so | The vendor ships that Flutter. Nothing in the project can change it, and its pub refuses to solve before a file is compiled |
| A vendor dependency this machine cannot produce | `needs tools Dartvel cannot install for you` | The Sony eLinux embedder artifacts come from a separate workflow; a build runner has no way to make them |

Each re-arms itself. The day a vendor ships a newer Flutter, or the artifacts
are in place, the skip stops happening and the artifact check applies again —
so a target cannot stay green by continuing to skip once the wall is gone.

Before this, webOS and Fuchsia failed on every run with a true message about
the wrong thing: their scaffolds were written, their own pub refused the SDK,
Dartvel deleted the half-written directory and reported that it could not
generate a scaffold. Sony eLinux skipped correctly and the job failed anyway,
because the step after it demanded an artifact from a build that had just
explained why there was none.

## Native drag-and-drop build check (2026-10-22)

A clean app created from this checkout on Linux x64, using Flutter 3.47.5 /
Dart 3.13.4 and package overrides pointing to the checkout, passed explicit
`flutter pub get` followed by `dartvel build android --profile development`.
The first build generated the Android scaffold, retained the resolved JNI
plugin metadata and produced `build/app/outputs/flutter-apk/app-debug.apk`
(`assembleDebug`, 131.8 seconds).

The APK passed ZIP CRC validation. Its DEX contains
`dev.dartvel.jni.DartvelDragDrop`, `Listener` and `Shadow`; the generated Java
uses `View.OnDragListener` and `startDragAndDrop`.

- Size: 164253803 bytes.
- SHA256: `d9b4e4e2f88c4e77dcaea557fb55ab96cc92b09d2d78cbf76541a61a922be33a`.

This verifies build and packaging. Android device interaction was not run.
The iOS bridge was checked only by generated Swift/Runner-project tests on
Linux; no Xcode build or device run was performed. Other targets retain their
separate historical evidence above. See [drag/drop verification](testing/drag-drop.md)
for browser and widget checks.
