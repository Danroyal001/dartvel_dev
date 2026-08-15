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
| `windows` | ⚠️ Unproven | Two macOS-runner-equivalent attempts hung in `dartvel build windows` for 257 and 226 minutes with no output and were killed, never reaching an artifact. Requires a Windows host. See [CI](#ci-for-hosts-you-do-not-have) |
| `macos` | ❌ Failing | Reached Xcode on a macOS runner and died in `lipo`: the native-asset hook answered both halves of the universal build with a host-arch dylib. Fixed in `976ccfa8`; the re-run hung and was never re-verified. See [CI](#ci-for-hosts-you-do-not-have) |
| `ios` | ✅ Builds | **Verified on a macOS runner**, not this host: `build/ios/iphoneos/Runner.app` (15.4 MB), artifact directory listed. Run [31554165981](https://github.com/Danroyal001/dartvel/actions/runs/31554165981) |
| `tvos` | ⚠️ Unproven | The embedder installs and precaches its own engine on a macOS runner, then stops at `This project is not configured for tvOS`. Scaffold generation added in `d0874755`, not yet executed. Any earlier "passing" tvOS build was `flutter build ios` under another name. See [tvOS](#tvos) |
| `tizen` / `tpk` | ✅ Builds | Signed 9.3MB TPK with engine + assets; see [Tizen](#tizen-samsung) |
| `sony-elinux` | ❌ Blocked | Dart version floor; see [Sony eLinux](#sony-elinux) |
| `webos` | ⚠️ Unproven | Embedder installs; build not yet demonstrated |
| `fuchsia` | ⚠️ Unproven | Fork created and taught to package any Flutter app; not yet executed — bootstrap needs Bazel + Fuchsia SDK. x64 only. See [Fuchsia](#fuchsia) |
| `vscode` | ✅ Builds | `out/src/extension.js`, `out/lib/vscode_api.handlers.js`, `build/web/flutter_bootstrap.js`, `build/web/assets/` |

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

Unblocking it requires an eLinux Flutter engine built for a Dart ≥ 3.9
release — a from-source engine build, not a version-pin bump.

### webOS (LG)

**Upstream pins Flutter 3.38.10**, which should clear the Dart ≥ 3.9 floor.
The embedder and `ares` CLI install cleanly via auto-install. A real webOS
build has **not** been demonstrated yet — it needs an LG-published webOS engine
for that Flutter version and a webOS platform scaffold, the same way Tizen
needed one.

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

### What the first four dispatches cost

Recorded because the numbers are counterintuitive and shaped the workflow.
Four runs consumed roughly **4,957 billed minutes**, and over 90% of that was
three jobs that hung rather than failed:

| Job | Wall | Multiplier | Billed |
|---|---|---|---|
| `macos` (run 31554165981) | 360 min — GitHub's cap | 10x | **~3,603** |
| `windows` (run 31548309453) | 257 min | 2x | ~515 |
| `windows` (run 31550108127) | 226 min | 2x | ~452 |
| every other job, all four runs | 3–7 min each | 2–10x | ~390 total |

A build that *fails* is cheap: the three macOS jobs that died on a compile
error cost about 40 billed minutes each. A build that **hangs** is not, and a
hung job is invisible — `dartvel build macos` printed `🔨 Building for macos...`
and then nothing at all for five hours and fifty-six minutes.

Two guards followed. The hook can no longer block indefinitely (`db93571b`),
and every job now carries `timeout-minutes: 45` (`d568dff9`) — generous
against a sub-ten-minute successful build, and roughly an eighth of what one
hang cost.

**Further verification is currently blocked at the account level.** Dispatches
are refused before any job starts, with: *"The job was not started because
recent account payments have failed or your spending limit needs to be
increased."* Raising the Actions spending limit under Settings → Billing &
plans is the only way to resume; nothing in this repository can work around
it.

---

## Distribution images

`sony-elinux-iso` and `sony-elinux-img` build the bundle and then report that
image assembly needs the configured Sony eLinux imaging toolchain. Dartvel does
not bundle one and does not emit a placeholder file in its place. These formats
are excluded from `dartvel build` with no argument, since they are explicit
packaging steps rather than part of a general build.
