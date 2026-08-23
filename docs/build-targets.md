# Build targets and toolchains

What `dartvel build <target>` supports, what each target needs installed, and
what has actually been verified rather than assumed.

Every "verified" row below was produced by running the command and inspecting
the artifact. Rows that are not verified say so and say why.

---

## Verified status

Verified on Linux x64 (Ubuntu 24.04), Flutter 3.44.5 / Dart 3.12.2. Most
Flutter targets were verified against `examples/dartvel_example`; the VS Code
target was verified against a disposable copy of `examples/basic_app` with the
local Dartvel `dartvel_vscode` fork added as a dependency.

| Target | Status | Evidence |
|---|---|---|
| `web` | ✅ Builds | `build/web` (43 MB) with `flutter_bootstrap.js`, `main.dart.js`, assets, CanvasKit; Wasm dry run passes |
| `linux` | ✅ Builds and **runs** | `build/linux/x64/release/bundle/dartvel_example`, 23.8 KB launcher + bundle. Runtime-verified under Xvfb: the release binary ran headless (software EGL), stayed alive, and a root-window screenshot showed the full UI — `DV.Platform` live-reporting `linux`/`desktop`, signals active (`showcase-ready`). The first target verified by running, not only building. **Re-verified 2026-08-15** after the native-asset hook was rewritten (`976ccfa8`, `db93571b`): the hook compiled `x86_64-unknown-linux-gnu` from an empty target directory, `libdartvel_shelf.so` (6.5 MB) was bundled into `bundle/lib/`, and the binary ran and rendered as before |
| `android` | ✅ Builds | `build/app/outputs/flutter-apk/app-release.apk`, 47.9 MB |
| `fireos` | ✅ Builds | Same APK path; `fireos` maps onto the Android toolchain |
| `windows` | ✅ Builds | **Verified on a Windows runner**, artifact downloaded and inspected rather than inferred: `dartvel_example.exe` (89 KB, PE32+ executable GUI x86-64), `dartvel_shelf.dll` (7.2 MB, the Rust runtime), `flutter_windows.dll`, `data/`. Run [32587129093](https://github.com/Danroyal001/dartvel/actions/runs/32587129093). Took eight attempts and **seven bugs** — two earlier runs had burned 257 and 226 minutes in silence. Four of the seven were not Windows quirks but silent corruption on every platform, exposed only because a Windows path forced the issue: `esc` never escaped backslashes; `routeFromRel` normalised separators with a doubled backslash and stripped its prefix before normalising; the same doubled-backslash fault sat in six more sites across two packages; and four glob patterns were built with `p.join`, where the separator is always `/` and a backslash is the escape character. See [Windows](#windows) |
| `macos` | ✅ Builds | **Verified on a macOS runner**, artifact downloaded and inspected: `dartvel_example.app/Contents/MacOS/dartvel_example` is a **Mach-O universal binary (x86_64 + arm64)**, with `dartvel_shelf.framework` — the Rust runtime — bundled into `Contents/Frameworks`. Run [32602765861](https://github.com/Danroyal001/dartvel/actions/runs/32602765861). The 41-minute silence was never Flutter: the native asset hook buffered its output, so a long C compile was indistinguishable from a wedge. Bounding and streaming it turned the hang into a visible failure, which turned out to be **cc-rs invoked with no `-isysroot`** — `SDKROOT` was unset, so every C crate (`ring`, `zstd-sys`, `aws-lc-sys`) failed to find its headers. The hook now asks `xcrun` for the SDK path, chosen from the target rather than the host. `aws-lc-rs` was also dropped: it is rustls's default provider, this crate uses `ring`, and it was compiling a large C codebase for nothing on every platform. See [macOS](#macos) |
| `ios` | ✅ Builds | **Verified on a macOS runner**, not this host: `build/ios/iphoneos/Runner.app` (15.4 MB), artifact directory listed. Run [31554165981](https://github.com/Danroyal001/dartvel/actions/runs/31554165981) |
| `tvos` | ✅ Builds | **Verified on a macOS runner**: scaffold auto-generated, then `build/tvos/Debug-appletvsimulator/Runner.app`. The `appletvsimulator` path is the proof it is a tvOS app and not the iPhone app an earlier mapping produced. Run [32538073146](https://github.com/Danroyal001/dartvel/actions/runs/32538073146). See [tvOS](#tvos) |
| `tizen` / `tpk` | ✅ Builds | Signed 9.3MB TPK with engine + assets, built on a laptop with Tizen Studio installed. CI can only ever *skip* it — the SDK is licence-gated and Dartvel must not install it unattended — so the workflow asserts the skip names that reason. See [Tizen](#tizen-samsung) |
| `sony-elinux` | ⚠️ Engine unblocked, tool is not | Sony's embedder **builds and links against Dartvel's engine** in CI, so **release** mode needs no engine build. The blocker moved: `flutter-elinux` is pinned to Flutter 3.29.3 and upstream has not moved since 2025-07. See [Sony eLinux](#sony-elinux) |
| `webos` | ❌ Blocked | Dart version floor — the embedder ships Dart 3.10.9, `dartvel_mix` needs ≥ 3.12.0; see [webOS](#webos-lg) |
| `fuchsia` | ❌ Blocked, same class as webOS | The five build-plumbing walls are fixed: `--build-only` in the fork, `postInstall` bootstrap, submodule handling, the bootstrap's workspace variable, and skipping an unfetchable `googletest` pin. It now clones, bootstraps and stages the app — then dies in `pub get` because the fork's bundled Flutter is **older than Dart 3.4**: `dartvel_example requires SDK version >=3.4.0 <4.0.0, version solving failed`. That is not a Dartvel bug and not a `mix` problem; the embedder's Flutter submodule is simply ancient. Unblocking needs the fork re-pinned to a modern Flutter **and its engine rebuilt from source**, because bootstrap.sh warns the engine and the Flutter pin must stay aligned. See [Fuchsia](#fuchsia) |
| `vscode` | ✅ Builds | `out/src/extension.js`, `out/lib/vscode_api.handlers.js`, `build/web/flutter_bootstrap.js`, `build/web/assets/` |
| `chrome-extension` | ✅ Builds | `build/chrome-extension` (41 MB): MV3 manifest with a `service_worker` background, `index.html`, `main.dart.js`, `background.js`, icons. See [Browser extensions](#browser-extensions) |
| `firefox-extension` | ✅ Builds | `build/firefox-extension`: the same bundle with an event-page `background.scripts` manifest — verified to differ from the Chromium one, not copy it |

Flutter has **no desktop cross-compilation**. A Windows desktop build requires
Windows, a Linux desktop build requires Linux, and the Apple targets require
macOS. `dartvel build` skips a target its host cannot build rather than
failing the whole run.

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

That is 8 of the 43 binding names `DV.Platform` and friends reference. The
other 35 remain unimplemented on Linux, and all 43 are unimplemented on
Android, iOS, macOS, Windows and web.

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
| the Fuchsia embedder checkout (no binary) | `git clone` | `dartvel_fuchsia` |
| `ares` (webOS CLI) | `npm install -g @webos-tools/cli` |
| `npm` (VS Code extension host) | Manual Node.js/npm install |
| Linux desktop deps (`clang`, `cmake`, `ninja`, `pkg-config`, GTK 3) | `apt-get` |

It deliberately will **not** install licence-gated or multi-gigabyte vendor
SDKs, and only prints instructions for them: **Xcode**, **Visual Studio**,
the **Android SDK**, and **Tizen Studio**. Installing those silently on
someone's machine is not Dartvel's call.

Toolchains Dartvel manages itself live in `~/.dartvel/toolchains/`.

---

## Embedded and television targets

These are driven by the platform vendor's Flutter embedder, never by plain
`flutter build`. Dartvel maintains a fork of each so it can pin and patch the
embedder against the Flutter version Dartvel ships.

| Target | Fork | Upstream | Vendor |
|---|---|---|---|
| `tizen` | [Danroyal001/dartvel_tizen](https://github.com/Danroyal001/dartvel_tizen) | `flutter-tizen/flutter-tizen` | Samsung |
| `sony-elinux` | [Danroyal001/dartvel_elinux](https://github.com/Danroyal001/dartvel_elinux) | `sony/flutter-elinux` | Sony |
| `webos` | [Danroyal001/dartvel_webos](https://github.com/Danroyal001/dartvel_webos) | `lg-flutter-webos/flutter-webos` | LG |
| `fuchsia` | [Danroyal001/dartvel_fuchsia](https://github.com/Danroyal001/dartvel_fuchsia) | `fuchsia/flutter-embedder` | Fuchsia |
| `vscode` | [Danroyal001/dartvel_vscode](https://github.com/Danroyal001/dartvel_vscode) | `SlowGen/flutter_vscode` | VS Code |

### Fuchsia

**Four Dartvel bugs stood between "never executed" and "builds the bundle",
and each one hid the next.** Recorded because the shape is worth remembering:
every layer failed in a way that looked like the target being unsupported.

1. **Bazel was never installed.** CI piped `curl` into `/usr/local/bin`
   without `sudo` and exited 23, and `|| true` swallowed it. Fuchsia was never
   reached at all, while the run looked like a Fuchsia failure.
2. **The build plan named an executable that does not exist.** It resolved
   `dartvel_fuchsia` on PATH, though the comment directly above the code says
   Fuchsia has no embedder binary — it is a Bazel workspace. The lookup could
   only fail, so the target could only skip. The unit test asserted
   `executable == 'dartvel_fuchsia'`, so it passed on the broken behaviour: it
   checked the plan's shape, never that the thing named could be found.
3. **`$FUCHSIA_EMBEDDER_DIR` was unset.** The script named the exact path
   Dartvel had just cloned the checkout to. Dartvel now sets it, per the rule
   that tools installed during a run must reach child processes.
4. **The architecture default was wrong for this target.** `--arch` defaults to
   arm64, which suits TVs and boards; Fuchsia's embedder ships an x64 prebuilt
   engine only. A plain `dartvel build fuchsia` therefore asked for an engine
   that does not exist without anyone choosing arm64.

A fifth wall is in the fork rather than in Dartvel: `build_flutter_app.sh`
calls `build_and_run_example.sh`, which after building tries to run the app on
a device via `tools/ffx`. CI has no device and no `ffx`. The fork needs a
build-only entry point before this target can produce an inspectable artifact.


Driven by Fuchsia's out-of-tree Flutter embedder
([fuchsia.googlesource.com/flutter-embedder](https://fuchsia.googlesource.com/flutter-embedder/)),
forked to [Danroyal001/dartvel_fuchsia](https://github.com/Danroyal001/dartvel_fuchsia)
so it can be pinned and patched like the vendor embedders.

This fork is a different proposition from the other three, and the difference
is worth stating plainly rather than discovering mid-build:

- Upstream calls itself an in-progress, experimental runtime and states it has
  no commit queue. Its most recent commit is from early 2023.
- It is **not a Flutter CLI wrapper.** There is no embedder binary to invoke.
  It is a Bazel workspace, and upstream builds only directories under
  `src/examples` carrying a hand-written `<name>_pkg` target — so upstream has
  no path for an app outside its workspace at all.
- The fork closes that: `src/flutter/defs.bzl` adds the `flutter_application`
  rule upstream's own TODO asks for, and `scripts/build_flutter_app.sh` takes
  the path of any Flutter package, runs `flutter build bundle`, stages the
  assets under `src/apps`, and builds them. `dartvel build fuchsia` calls that
  script with the project path.
- Nothing handed to the embedder is Dartvel-specific. A Dartvel app is an
  ordinary Flutter package, so the same script serves a plain `flutter create`
  app — the fork stays a general embedder rather than becoming a Dartvel one.
- **arm64 needs an engine build.** Upstream committed a 291 MB arm64
  `libflutter_engine.so`, which exceeds GitHub's 100 MB limit and was stripped
  on import; the 59 MB x64 engine survived. Build one with
  `scripts/build_and_copy_engine_artifacts.sh` before targeting arm64.

The fork's history is **not** hash-identical to upstream. Upstream committed
prebuilt engine binaries (`libflutter_engine.so`, ~290 MB each, across several
revisions), and GitHub rejects any file over 100 MB. Git LFS would spend more
than the free quota to carry a 2023 engine Dartvel cannot use, so blobs over
90 MB were stripped from every commit on import — 1.1 GB down to 108 MB. The
repository obtains those artifacts through `scripts/setup_engine.sh` and
`scripts/build_and_copy_engine_artifacts.sh` anyway, which is the supported
route. The fork's README records this.

Host support is Linux only — upstream's README states it cannot be built on
macOS or Windows natively — so `dartvel build fuchsia` skips with that reason
on other hosts rather than failing part-way through.

On the upstream history: the Flutter team handed Flutter-on-Fuchsia
maintenance back to the Fuchsia team and planned to move it out of the engine
into this custom embedder — see
[Flutter-on-Fuchsia Velocity](https://fuchsia.dev/fuchsia-src/contribute/roadmap/2021/flutter_on_fuchsia_velocity).
Fuchsia code is still touched in the engine as recently as the 3.44.0 release
notes, so this reads as an ownership handover that stalled rather than a clean
removal. Treat any stronger claim as unverified.

**Status: unproven.** The fork exists; no Dartvel app has been built with it.

## Extension-host targets

Extension-host targets compile Flutter into the host's webview/runtime shape
instead of using plain `flutter build web`.

### VS Code

`dartvel build vscode` follows the `flutter_vscode` flow:

1. Generate Dartvel routes/client/backend artifacts.
2. Run `dart run build_runner build --delete-conflicting-outputs` so annotated
   VS Code controller APIs emit current bindings.
3. Run `dart run flutter_vscode:generate_vscode_extension` to create/update
   the VS Code extension scaffold, typed controller bindings, and webview
   helper wiring.
4. Run `flutter pub get`.
5. Run `npm install`.
6. Run `npm run compile`.

The target requires Node.js/npm, a project dependency on `flutter_vscode`, and
`build_runner` in `dev_dependencies`. `dartvel build vscode` validates the
pubspec dependencies before running the scaffold generator. `dartvel doctor
--target vscode` reports whether npm is available.

After the compile step, Dartvel validates the artifact shape and freshness so a
zero exit code without current-build output cannot be reported as success.
Verified evidence from the disposable `examples/basic_app` copy:

- `dart run dartvel_cli:dartvel build vscode --no-auto-install`
- Extension host output: `out/src/extension.js`,
  `out/lib/vscode_api.handlers.js`, and `out/src/vscode_invoke.js`.
- Flutter webview bundle output: `build/web/flutter_bootstrap.js`,
  `build/web/main.dart.js`, and `build/web/assets/`.
- Generated extension metadata: `package.json` produced by the Dartvel fork's
  scaffold flow.

### Tizen (Samsung)

**Verified Flutter: 3.44.4 / Dart 3.12.2** — clears Dartvel's dependency floor.

A complete, signed TPK is produced end to end:

```
✓ Built build/tizen/tpk/com.example.dartvel_example-1.0.0.tpk (9.3MB)
```

It contains `lib/libapp.so`, `lib/libflutter_engine.so`,
`lib/libflutter_tizen_tv.so`, `res/icudtl.dat` and `res/flutter_assets/` — a
runnable Flutter application.

> **This required a fix in the Dartvel fork.** A native build first produced a
> 15KB TPK holding only the compiled runner, an icon and the manifest, with
> `lib/` and `res/` empty: a package that installs and does nothing. The
> payload was staged correctly in `tizen/flutter/ephemeral/{lib,res}`, and
> `tizen package -e <ephemeralDir>` is meant to inject it — but on current
> Tizen SDK CLI versions (10.x) that call reports success while producing a
> TPK without it. The fork now copies the payload into the app root before
> building, so it is part of the build rather than a post-hoc injection.
> This is exactly the class of problem the forks exist to absorb.

Getting that far required, beyond the embedder:

1. **A Tizen platform scaffold.** `dartvel build tizen` needs a `tizen/`
   directory the way Android builds need `android/`. Generate the native one:
   ```bash
   flutter-tizen create --platforms tizen --tizen-language cpp .
   ```
   Without it the build stops at `This project is not configured for Tizen`.
   The default scaffold is C#/.NET; `--tizen-language cpp` matches the native
   GCC toolchain below.

2. **Tizen SDK packages** — the base SDK is not enough:
   ```bash
   <tizen-studio>/package-manager/package-manager-cli.bin install \
     NativeCLI NativeToolchain-Gcc-9.2 IOT-Headed-6.0-NativeAppDevelopment-CLI
   ```
   `NativeCLI` pulls in `tizen-core`, which provides the `tz` tool. flutter-tizen
   packages TPKs through `tz` with no fallback, so the SDK must be recent enough
   to ship it.

3. **A signing certificate.** Release packaging fails with
   `No certificate profile found` until one exists:
   ```bash
   tizen certificate -a Dartvel -p <password> -c KR -s Seoul -ct Seoul \
     -o Dartvel -u Dev -e dev@example.com -n dartvel-author
   tizen security-profiles add -n DartvelProfile \
     -a ~/tizen-studio-data/keystore/author/author.p12 -p <password>
   ```

**Ubuntu 24.04 notes.** Tizen Studio's package manager needs `python3.8`,
which 24.04 does not ship (available from the deadsnakes PPA). Its bundled
LLVM 10 links against `libtinfo.so.5`; symlinking `libtinfo.so.6` is not
enough because the ncurses 5 ABI symbols are genuinely absent — install the
real `libtinfo5` package.

### The three blocked targets share a shape, not a cause

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

The terminal embedder was in this group and is not any more. `dartvel_flt`
pinned Flutter 3.38.5, below Dartvel's floor — but the prebuilt
`linux-x64-embedder` artifact **is** published for Dartvel's engine, so the
re-pin needed four source changes rather than an engine build, and the fork now
compiles against 3.44.5. Worth stating plainly because it is the counterexample:
being behind the floor does not by itself mean an engine build, and the way to
tell is to check whether the artifact exists rather than to assume.

webOS, Sony eLinux and Fuchsia are all blocked by an embedder shipping a Dart
older than Dartvel needs. The distances are very different, and conflating them
would send the work in the wrong direction:

| Target | Embedder's Dart | Short by | Cheapest unblock |
| --- | --- | --- | --- |
| webOS | 3.10.9 | 1.1 against `dartvel_mix`'s 3.12 floor | Engine rebuild, or lower our own fork's pin |
| Sony eLinux | 3.7.2 | Well short of `dartvel_mix` | Engine rebuild |
| Fuchsia | **older than 3.4** | Short of Dartvel's own example, before the UI layer is reached | Re-pin the fork's Flutter **and rebuild its engine** |

**webOS changed shape once `dartvel_mix` existed, and got further away
rather than closer.** This section previously asked whether pub's `mix 2.1.0`
really needed Dart 3.11 or was merely conservative, because an older published
`mix` would have cleared webOS's 3.10.9 by a hair. That question is now
retired: `dartvel_flutter` does not depend on pub's `mix` at all. It depends on
`dartvel_mix`, which pins Dart 3.12 to stay level with every other Dartvel
fork — so the gap widened from 0.0.1 to 1.1.

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

**Verified Flutter: 3.29.3 / Dart 3.7.2 — target is blocked.**

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

**Verified Flutter: 3.38.10 / Dart 3.10.9 — target is blocked.**

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

**Not yet demonstrated, but further along than that sounds.** On a macOS
runner the fork clones, bootstraps, and precaches its own engine cleanly —
all six tvOS engine variants (`tvos-debug-sim-arm64` through
`tvos-host-release`) fetch in about 15 seconds, confirming the origin-signed
artifacts for 3.44.8 genuinely exist. `flutter-tvos doctor` then reports
Flutter 3.44.8 from the fork's own checkout.

The build stops at the next wall:

```
Running build hooks...This project is not configured for tvOS.
To fix this problem, create a new project by running `flutter-tvos create <app-dir>`.
```

`examples/dartvel_example` has no `tvos/` directory, exactly as it has no
`tizen/`. Rather than making that a manual prerequisite the way Tizen's is
(step 1 below), `dartvel build` now generates a missing platform scaffold
through the embedder's own `create` (`d0874755`, covering tizen, sony-elinux,
webos and tvos). That path has not been executed on a runner yet.

**Any earlier "passing" tvOS build was not one.** Until `b25b025a` the CLI
mapped `tvos` onto the iOS toolchain and ran `flutter build ios --no-codesign`,
so the matrix reported a green tvOS job for an iPhone app.

---

### Browser extensions

`chrome-extension` and `firefox-extension` are not embedder targets. They are
Flutter web output plus a generated manifest and background script, so any host
that can build web can build them. Two build flags are load-bearing rather than
stylistic: `--csp`, because manifest V3 forbids `eval`, and
`--pwa-strategy=none`, because Flutter's service worker fights the extension's
own — the assembler also deletes `flutter_service_worker.js` from the bundle if
it appears, since two service workers contend over fetch handling.

The two manifests genuinely differ, and must: Chromium runs a manifest V3
`service_worker`, while Firefox runs an event page and refuses to load a
manifest declaring `service_worker`.

```jsonc
// chrome-extension/manifest.json     // firefox-extension/manifest.json
"background": {                       "background": {
  "service_worker": "background.js",    "scripts": ["background.js"]
  "type": "module"                    }
}
```

Verified 2026-08-15 against `examples/dartvel_example`: both bundles build,
carry all four artifacts a browser needs to load them unpacked
(`index.html`, `main.dart.js`, `manifest.json`, `background.js`), share one CSP
with no `unsafe-eval` or `unsafe-inline`, and drop Flutter's service worker.

Two things applications should know. The generated background script resolves
`globalThis.browser ?? globalThis.chrome` rather than being emitted per target,
so one script serves both. And `browser_specific_settings.gecko.id` is only
emitted when `dartvel.extension.geckoId` is set in `pubspec.yaml` — fine for a
temporary Firefox install, required before distribution.

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

**Runner minutes are billed against the repository owner's account.** A public
repository gets unlimited free Actions minutes on standard runners, which is
the intended arrangement for this project; a private one bills at the
multipliers above and will exhaust an allowance quickly if a job hangs.

---

## Distribution images

`sony-elinux-iso` and `sony-elinux-img` build the bundle and then report that
image assembly needs the configured Sony eLinux imaging toolchain. Dartvel does
not bundle one and does not emit a placeholder file in its place. These formats
are excluded from `dartvel build` with no argument, since they are explicit
packaging steps rather than part of a general build.
