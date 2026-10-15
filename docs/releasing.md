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
4. Builds the executable with `dart build cli --target bin/dartvel.dart`.
5. Stages the binary to `artifacts/` with the exact names above.
6. Runs the binary with `--version` and asserts the output contains `Dartvel CLI`.
7. Checks architecture with `file -b` (macOS) or verifies the `.exe` path (Windows): expects `arm64` / `x86_64` accordingly.
8. Uploads artifacts through Codemagic's artifact system.

No Linux steps are included in these workflows; Linux binaries remain built by hand or via `.github/workflows/cli-release.yml`.
No Codemagic credits are spent unless the workflow is triggered explicitly; the YAML is validated by parsing (`python3 -c "import yaml; yaml.safe_load(...)"`).
