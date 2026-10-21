# File associations and web build cache verification

This landing ports the missing parts of `feat/file-associations-everywhere`
and `feat/build-cache` onto Dartvel 0.13.12. Existing desktop registration,
app shortcuts, deep links, signing and target-extension hooks remain in the
current build pipeline.

## Scope

One `dartvel.fileAssociations` declaration feeds Android intent filters,
iOS/macOS document metadata, installed-web-app file handlers, Linux desktop
and MIME files, Windows registry scripts and Tizen app controls. Opened files
use the existing platform surface, `DV.Platform.associations`, through Android
JNI, iOS defaults, desktop launch arguments and web `launchQueue`. A picker
feeds that same stream where a picker binding is available. Buffering is
internal; applications receive `DVOpenedFile`.

Per-type icons are generated for web/Linux and Windows `.ico` files. Apple
and Android per-type icons are not generated. Tizen opened-file delivery is
unwired. Generating registration files does not prove OS installation, physical
mobile opening or opening an installed PWA; those remain unverified here.

The build cache reuses raw Flutter web output before post-processing and route
captures grouped by web build. Entries are verified by file sizes and hashes.
`--no-cache` bypasses both reads and writes. Native builds and backend binaries
are not cached. Prerenders that depend on changing external data or the clock
need `--no-cache`.

## Verification completed so far

- Association-focused CLI suite: 73 passed, including generated registration,
  per-type icons, reversible macOS metadata removal, desktop writers, mobile
  launch wiring and existing app shortcuts.
- Cache suite: 26 passed. Regression tests first demonstrated omitted font and
  path-dependency assets, failure to store an empty output, and an unsafe
  manifest path; all four now pass.
- Flutter focused suite: 35 passed, including opened-file buffering, initial
  files, pickers, desktop registrations and shortcut launch behavior.
- Core configuration suite: 13 passed.
- Spec-status validation and the no-Python check passed; browser-proof tool
  analysis reports no issues.
- A fresh `dartvel create` scratch application built for web with Flutter
  3.47.5 / Dart 3.13.4, captured all five routes and passed the build's
  accessibility check.

## Full output comparison fixture

The default scaffold displays `DateTime.now()`. Independent prerenders of that
label cannot have identical bytes. The parity fixture replaces only that label
with fixed text, adds a declared SVG file-type icon, and adds an opened-file
stream display for the browser check. Output files are not normalized.

The comparison sequence is:

1. Build web with caching enabled to seed both caches.
2. Build web again; require logged hits for Flutter output and every route's
   capture, then compare every output filename and byte with `diff -qr`.
3. Build web with `--no-cache`; compare every output filename and byte against
   the seeded build again.
4. Build the fixture as web-server and Android, then inspect the APK manifest
   and check opened-file delivery in an isolated browser.

The portable browser proof tool is
`packages/dartvel_cli/tool/verify_assoc_cache_browser.dart`. It starts and stops
its own server and browser, checks server-rendered document text, native find,
selection, Tab focus and accessibility names, and captures light/dark screens.
The scratch mode also injects a browser file through `launchQueue` and requires
the file's name and byte count to reach the application display. This tests the
browser delivery path; it does not claim an installed-PWA OS launch.

Full suites, output parity, APK inspection, site build and browser results are
still pending. This report will be updated with their actual results.
