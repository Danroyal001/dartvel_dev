
# Migration to dartvel v0.1

- Replace `host` → `backendHost`, `port` → `backendPort` in `pubspec.yaml`.
- Rename `seoDefaults` → `webSeoDefaults`.
- Update your pages to use `buildWebSeo(...)` (instead of `buildSeo(...)`).
- Ensure `prodBackendHost` is set before running `dartvel build` (if you use that command).
