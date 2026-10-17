## 0.13.6 — 2026-10-17

- `DVIconButton` is removed: an icon-only control is `DVBox(Icon(...), DVModifier().tooltip(...).onTap(...))`, with `.minimumTapTarget(width: 48, height: 48)` for touch. It stretched to fill whatever held it (an eye icon filled a password field).
- `DVAuthAppearance.frameBuilder` draws an app's own sign-in screen around the framework form; `signInTitle`/`signUpTitle`; `dartvel.auth.forgotPassword` links the sign-in form to the app's reset page; narrow screens show the brand.
- `DVBox.row` honours an explicit `crossAlign: .stretch`; an unset row still centres.


## 0.13.5 — 2026-10-17

- `@DVBoot` runs in every entry its code can run in: the app, and the web server, worker and cron processes, through one runner in dartvel_core (`DVBootStep`, `dvRunBoot`). A hook in a file that imports Flutter stays in the app; naming `server` from one is refused (`DV-RUN-008`).

## 0.13.4 — 2026-10-17

- Generation copies enums only from `lib/models` files that declare a data model; another file there keeps its own enums, so importing it beside the barrel compiles again.
- The prebuilt auth pages show a `dartvel.pwa.icon` (or `dartvel.auth.heroImage`) from the `web/` folder on the web, instead of a silent 404 on `/assets/web/...`.

## 0.13.3 — 2026-10-17

- An `@DVAppRoot` may wrap the project's own `@DVFunctionalWidget` (the application entry imports the generated widgets).

## 0.13.2 — 2026-10-15

- Version bump to match Dartvel 0.13.2.

## 0.13.1 — 2026-10-15

- Version bump to match Dartvel 0.13.1.

## 0.13.0 — 2026-10-15

- Version bump to match Dartvel 0.13.0.

## 0.12.2 — 2026-10-14

- Released alongside dartvel_core 0.12.2; no changes in this package.

## 0.12.1 — 2026-10-14

- Released alongside dartvel_cli 0.12.1 (model field defaults survive reads and migrations); no changes in this package.

## 0.12.0

- Released with the rest of Dartvel 0.12.0; see the repository CHANGELOG.

## 0.11.5

- Version alignment with Dartvel 0.11.5.

## 0.11.4 — 2026-10-08

- First release: DVBox.scene renders through Flutter Scene (Flutter GPU natively, WebGL2 in browsers).
