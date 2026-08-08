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
| `linux` | ✅ Builds and **runs** | `build/linux/x64/release/bundle/dartvel_example`, 23.8 KB launcher + bundle. Runtime-verified under Xvfb: the release binary ran headless (software EGL), stayed alive, and a root-window screenshot showed the full UI — `DV.Platform` live-reporting `linux`/`desktop`, signals active (`showcase-ready`). The first target verified by running, not only building |
| `android` | ✅ Builds | `build/app/outputs/flutter-apk/app-release.apk`, 47.9 MB |
| `fireos` | ✅ Builds | Same APK path; `fireos` maps onto the Android toolchain |
| `windows` | ⏭️ Not on Linux | Requires a Windows host. See [CI](#ci-for-hosts-you-do-not-have) |
| `macos` | ⏭️ Not on Linux | Requires macOS |
| `ios` | ⏭️ Not on Linux | Requires macOS |
| `tvos` | ⏭️ Not on Linux | Requires macOS |
| `tizen` / `tpk` | ✅ Builds | Signed 9.3MB TPK with engine + assets; see [Tizen](#tizen-samsung) |
| `sony-elinux` | ❌ Blocked | Dart version floor; see [Sony eLinux](#sony-elinux) |
| `webos` | ⚠️ Unproven | Embedder installs; build not yet demonstrated |
| `fuchsia` | ⚠️ Unproven | Fork created; upstream has no path for an out-of-workspace app. See [Fuchsia](#fuchsia) |
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
  It is a Bazel workspace whose `scripts/build_and_run_example.sh` builds a
  directory under `src/examples` carrying a `<name>_pkg` target.
- Consequently there is **no upstream path for an app outside the workspace.**
  `dartvel build fuchsia` stages the app in as `dartvel_app`, which needs a
  package template the fork does not have yet. That is the first patch.

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

---

## Distribution images

`sony-elinux-iso` and `sony-elinux-img` build the bundle and then report that
image assembly needs the configured Sony eLinux imaging toolchain. Dartvel does
not bundle one and does not emit a placeholder file in its place. These formats
are excluded from `dartvel build` with no argument, since they are explicit
packaging steps rather than part of a general build.
