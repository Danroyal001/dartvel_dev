# Releasing

## Windows and macOS binaries

The `codemagic.yaml` file defines three `cli-release-*` workflows that trigger on tags matching `v*`.
They mirror `.github/workflows/cli-release.yml` (Dart 3.13.4, Rust stable, `dart build cli --target bin/dartvel.dart`) but run on Codemagic's macOS and Windows runners.

| Workflow | Runner | Target binary | Build command |
|---|---|---|---|
| `cli-release-macos-arm64` | `mac_mini_m1` | `dartvel-macos-arm64` | `dart build cli --target bin/dartvel.dart` |
| `cli-release-macos-x64` | `mac_mini_m1` | `dartvel-macos-x64` | `dart build cli --target bin/dartvel.dart --target-arch x64` |
| `cli-release-windows-x64` | `windows_x2` | `dartvel-windows-x64.exe` | `dart build cli --target bin/dartvel.dart` |

Each workflow:
1. Installs the Dart SDK (3.13.4) and verifies `dart --version`.
2. Confirms Rust stable (`rustup` / `rustc`).
3. Runs `dart pub get` in `packages/dartvel_cli`.
4. Puts the Rust syntax helper inside the CLI with `dart run tool/embed_syntax_helper.dart` (`--rust-target x86_64-apple-darwin` for the macOS x64 binary), then builds the executable with `dart build cli --target bin/dartvel.dart`.
5. Stages the binary to `artifacts/` with the exact names above.
6. Runs the binary with `--version` and asserts the output contains `Dartvel CLI`.
7. Checks architecture with `file -b` (macOS) or verifies the `.exe` path (Windows): expects `arm64` / `x86_64` accordingly.
8. Uploads artifacts through Codemagic's artifact system.

No Linux steps are included in these workflows; Linux binaries remain built by hand or via `.github/workflows/cli-release.yml`.
No Codemagic credits are spent unless the workflow is triggered explicitly; the YAML is validated by parsing (`python3 -c "import yaml; yaml.safe_load(...)"`).

## The syntax helper inside the CLI

`dartvel build` and `dartvel doctor` check that a project's Dart sources parse. A release binary answers most of that with a Rust program (`rust/dartvel_syntax`, see `rust/README.md`) that it carries inside itself, because the CLI ships as one file and `dart build cli` cannot attach a second one.

Every binary build, on any runner or by hand, does this before `dart build cli`:

```sh
cd packages/dartvel_cli
dart pub get
dart run tool/embed_syntax_helper.dart          # cargo build --release in rust/, then writes the helper into a Dart source file
dart build cli --target bin/dartvel.dart
git checkout -- lib/src/analysis/syntax_helper_carried.g.dart   # never commit the embedded helper
```

- A cross-architecture build names the Rust target: `--rust-target aarch64-unknown-linux-gnu` beside `dart build cli --target-arch arm64` (it needs that target's linker), `--rust-target x86_64-apple-darwin` beside `--target-arch x64` on an Apple silicon Mac.
- A binary built without the step still works: it carries no helper and parses with the Dart analyzer, which is what `dart pub global activate dartvel_cli` and `dart run` always do. The package published to pub.dev must be the repository's file (no helper); `syntax_check_test` fails if a helper is committed.
- Check a built binary: run `dartvel doctor` in any project, then `ls ~/.dartvel/native/` shows `dartvel_syntax-<digest>`. `DARTVEL_SYNTAX_ENGINE=dart` turns the helper off for one run.
