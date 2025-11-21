Param()
$ErrorActionPreference = "Stop"
Set-Location "$PSScriptRoot/.."

Write-Host "==> Building Rust core (release)…"
Push-Location rust
cargo build --release
cbindgen --config cbindgen.toml -o include/dartvel_shelf.h
Pop-Location

Write-Host "==> Dart deps & bindings…"
dart pub get
try { dart run ffigen } catch { Write-Warning "ffigen optional; bindings.dart already included." }

Write-Host "✅ Done. Run: dart run example/server.dart"
