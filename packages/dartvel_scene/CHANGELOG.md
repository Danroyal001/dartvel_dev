## 3.47.0 — 2026-11-14

- The version now follows Flutter's. From this release a Dartvel version is `<Flutter major>.<Flutter minor>.<Dartvel release>`: 3.47.0 is the first release numbered on Flutter 3.47, and the last number counts Dartvel's own releases on it. The release before this one was 0.13.51. Every published package, the CLI, the npm packages and the Homebrew formula carry the same version.
- Moving from 0.13.x: a caret does not cross the line (`^0.13.51` stops below 0.14.0), so `pub upgrade` alone keeps a project on 0.13.51. Install the 3.47.0 CLI (`npm install -g dartvel_dev@latest`, `dartvel update` or `brew upgrade dartvel_dev`) and run `dartvel upgrade --project` in the project.
- Version aligned with dartvel_core 3.47.0.

## 0.13.44 — 2026-11-12

- Version aligned with dartvel_core 0.13.44.

## 0.13.43 — 2026-11-12

- Version aligned with dartvel_core 0.13.43.

## 0.13.42 — 2026-11-12

- Version aligned with dartvel_core 0.13.42.

## 0.13.41 — 2026-11-11

- Version aligned with dartvel_core 0.13.41.

## 0.13.40 — 2026-11-11

- Version aligned with dartvel_core 0.13.40.

## 0.13.39 — 2026-11-11

- Version aligned with dartvel_core 0.13.39.

## 0.13.38 — 2026-11-11

- Version aligned with dartvel_core 0.13.38.

## 0.13.37 — 2026-11-11

- Version aligned with dartvel_core 0.13.37.

## 0.13.36 — 2026-11-11

- Version aligned with dartvel_core 0.13.36.

## 0.13.35 — 2026-11-11

- Version aligned with dartvel_core 0.13.35.

## 0.13.34 — 2026-11-10

- Version aligned with dartvel_core 0.13.34.

## 0.13.33 — 2026-11-10

- Version aligned with dartvel_core 0.13.33.

## 0.13.32 — 2026-11-10

- Version aligned with dartvel_core 0.13.32.

## 0.13.31 — 2026-11-10

- Version aligned with dartvel_core 0.13.31.

## 0.13.30 — 2026-11-10

- Version aligned with dartvel_core 0.13.30.

## 0.13.29 — 2026-11-09

- Version aligned with dartvel_core 0.13.29.

## 0.13.28 — 2026-11-09

- Version aligned with dartvel_core 0.13.28.

## 0.13.27 — 2026-11-09

- Version aligned with dartvel_core 0.13.27.

## 0.13.26 — 2026-11-07

- Version aligned with dartvel_core 0.13.26.

## 0.13.25 — 2026-11-07

- Version aligned with dartvel_core 0.13.25.

## 0.13.24 — 2026-11-07

- Version aligned with dartvel_core 0.13.24.

## 0.13.23 — 2026-11-07

- Version aligned with dartvel_core 0.13.23.

## 0.13.22 — 2026-11-07

- Version aligned with dartvel_core 0.13.22.

## 0.13.21 — 2026-11-05

- Version aligned with dartvel_core 0.13.21.

## 0.13.20 — 2026-11-05

- Version aligned with dartvel_core 0.13.20.

## 0.13.19 — 2026-11-04

- Version aligned with dartvel_core 0.13.19.

## 0.13.18 — 2026-11-01

- Version aligned with dartvel_core 0.13.18.

## 0.13.17 — 2026-11-01

- Version aligned with dartvel_core 0.13.17.

## 0.13.16 — 2026-10-22

- Version aligned with dartvel_core 0.13.16.

## 0.13.15 — 2026-10-22

- Version aligned with dartvel_core 0.13.15.

## 0.13.14 — 2026-10-22

- Version aligned with dartvel_core 0.13.14.

## 0.13.13 — 2026-10-21

- Version aligned with dartvel_core 0.13.13.

## 0.13.12 — 2026-10-21

- Version aligned with dartvel_core 0.13.12.


## 0.13.11 — 2026-10-21

- Version aligned with dartvel_core 0.13.11.


## 0.13.10 — 2026-10-21

- Version aligned with dartvel_core 0.13.10.


## 0.13.9 — 2026-10-20

- Version aligned with dartvel_core 0.13.9.


## 0.13.8 — 2026-10-20

- Version aligned with dartvel_core 0.13.8.


## 0.13.7 — 2026-10-18

- `DVModifier.maxWidth`/`maxHeight` hold inside a column that stretches its children: the bounded box sits at the start edge instead of being forced to the full width (a lead paragraph capped at 680 ran 1,270 pixels). Under loose constraints nothing changes; `.centered()` still centres.
- `@DVBoot` bodies are lowered outside `abstract final class DV`, into a top-level `_dvBootSteps` list, so an app name that matches one of DV's statics (`Session`) resolves to the app's own.


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
