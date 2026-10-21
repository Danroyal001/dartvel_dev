# File associations and the web build cache: verification

Lands `feat/file-associations-everywhere` and `feat/build-cache` on 0.13.12.
Every result below was run on a fresh `dartvel create` app built from this
branch (Flutter 3.47.5, Linux x64). The app declared two types:
`application/x-assoc-note` (`*.anote`, SVG icon) and `text/csv` (viewer), and
printed each file `DV.Platform.associations.opened` delivered.

## File associations

| Target | What was checked | Result |
|---|---|---|
| Linux | `dartvel build linux`; the bundle's desktop entry and shared-mime-info package installed into an isolated XDG home; `xdg-mime` and `gio open` under Xvfb | `MimeType=application/x-assoc-note;text/csv;`, `*.anote` resolves to the declared type, its icon is installed under `hicolor/scalable/mimetypes`. `gio open march.anote` started the app and it received the file (11 bytes). Opening `second.csv` and `with space.anote` while it ran started two short-lived launches that handed the files over and exited; all three arrived on the first instance's stream |
| Web (web-server build) | the built server, own headless Chrome | the served manifest has one `file_handlers` entry per type, the note's icon is served as `image/svg+xml`; a file given to `launchQueue` reached the stream with its name and bytes. An installed PWA's OS launch was not exercised |
| Android, iOS, macOS, Windows, Tizen | generated-output tests | intent filters and `DartvelOpenActivity`; document types, UTIs and the delegate block; registry script and `.ico` icons; app controls. Not run on a device. Tizen delivery is not wired (picker). No MSIX is produced |

## Build cache

Web-server builds with `SOURCE_DATE_EPOCH` set, compared with `diff -r` over
`build/web`, `build/server` and `.dart_tool/dartvel_semantics`:

| Build | Time | Flutter web | Captures (6 routes) | Output vs the cold build |
|---|---|---|---|---|
| cold (empty cache) | 263 s | compiled | captured | - |
| warm (nothing changed) | 73 s | reused | all reused | identical, server binary included |
| `--no-cache` | 249 s | compiled | captured | only Flutter's own `serviceWorkerVersion` (2 lines of `flutter_bootstrap.js`, and the binary embedding it); the cache directory was not touched |
| backend function edited | 194 s | compiled | all reused | only `serviceWorkerVersion` |
| one page edited | 276 s | compiled | captured | that route's capture changed; the other five are identical |

Two faults were found by these runs and fixed with tests:

- Flutter writes into `build/web` without clearing it, so the "raw Flutter
  output" stored in the cache included `dartvel_routes.json` and the prefetch
  manifest left by the previous build, and those decided the capture keys. The
  Flutter step now starts from an empty `build/web`.
- Flutter changes `serviceWorkerVersion` on every compile of unchanged code,
  so any recompile recaptured every route. The capture key leaves that value
  out (it only names Flutter's deprecated worker, which Dartvel replaces).

Without `SOURCE_DATE_EPOCH`, Dartvel's service worker cache name is the build
time, so two builds always differ in that one line; that is deliberate (each
deploy opens a new cache) and unrelated to the build cache.
