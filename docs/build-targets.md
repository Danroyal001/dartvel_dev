# Build targets and toolchains

What `dartvel build <target>` supports, what each target needs installed, and
what has actually been verified rather than assumed.

Every "verified" row below was produced by running the command and inspecting
the artifact. Rows that are not verified say so and say why.

---

## Verified status

Verified on Linux x64 (Ubuntu 24.04), Flutter 3.44.5 / Dart 3.12.2, against
`examples/dartvel_example`.

| Target | Status | Evidence |
|---|---|---|
| `web` | ✅ Builds | `build/web` with `flutter_bootstrap.js`, assets, CanvasKit |
| `linux` | ✅ Builds | `build/linux/x64/release/bundle/dartvel_example` |
| `android` | ✅ Builds | `build/app/outputs/flutter-apk/app-release.apk`, 47.9 MB |
| `fireos` | ✅ Builds | Same APK path; `fireos` maps onto the Android toolchain |
| `windows` | ⏭️ Not on Linux | Requires a Windows host. See [CI](#ci-for-hosts-you-do-not-have) |
| `macos` | ⏭️ Not on Linux | Requires macOS |
| `ios` | ⏭️ Not on Linux | Requires macOS |
| `tvos` | ⏭️ Not on Linux | Requires macOS |
| `tizen` / `tpk` | ✅ Builds | Signed 9.3MB TPK with engine + assets; see [Tizen](#tizen-samsung) |
| `sony-elinux` | ❌ Blocked | Dart version floor; see [Sony eLinux](#sony-elinux) |
| `webos` | ⚠️ Unproven | Embedder installs; build not yet demonstrated |

Flutter has **no desktop cross-compilation**. A Windows desktop build requires
Windows, a Linux desktop build requires Linux, and the Apple targets require
macOS. `dartvel build` skips a target its host cannot build rather than
failing the whole run.

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

| Tool | Installed via |
|---|---|
| `flutter-tizen` | `git clone` of the Dartvel fork |
| `flutter-elinux` | `git clone` of the Dartvel fork |
| `flutter-webos` | `git clone` of the Dartvel fork |
| `ares` (webOS CLI) | `npm install -g @webos-tools/cli` |
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
| `tizen` | [Danroyal001/flutter-tizen](https://github.com/Danroyal001/flutter-tizen) | `flutter-tizen/flutter-tizen` | Samsung |
| `sony-elinux` | [Danroyal001/flutter-elinux](https://github.com/Danroyal001/flutter-elinux) | `sony/flutter-elinux` | Sony |
| `webos` | [Danroyal001/flutter-webos](https://github.com/Danroyal001/flutter-webos) | `lg-flutter-webos/flutter-webos` | LG |

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
