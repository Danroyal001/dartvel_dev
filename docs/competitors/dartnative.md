# DartNative compared with Dartvel

Checked 2026-10-09 against dartnative.com, dartpub.dev and
github.com/DartNative/dartnative, and against Dartvel at `origin/main`
`9b3ebd7d`. Every DartNative item links the page it came from. Every Dartvel
item names the file or the `docs/spec-status.json` entry it was checked
against.

Claims DartNative makes about Flutter and React Native (for example "Flutter
reacts to the keyboard 1–2 frames late", "Flutter's video_player has no network
cache") come from their own site. We have not verified them, and this document
does not repeat them as fact.

## What DartNative is

- A commercial, closed-source framework for **iOS and Android only**. It
  implements Flutter's widget API and draws it with the platform's real views
  (UIKit, Android Views) instead of Impeller/Skia. Dart drives the views over
  synchronous FFI on the main thread, and Yoga does the layout.
  Sources: [home](https://dartnative.com/),
  [README](https://github.com/DartNative/dartnative),
  [architecture.md](https://github.com/DartNative/dartnative/blob/main/docs/architecture.md).
- It is built on "Zero", their fork of Matej Knopp's
  [flutter_zero](https://github.com/knopp/flutter_zero), which patches the Flutter SDK
  ([Framework License §5](https://dartpub.dev/license/framework)).
- It ships as the `dn` CLI (`dn run`, `dn create`, `dn doctor`, `dn pub get`,
  `dn release`, `dn patch`, `dn plugin publish`, `dn upgrade`). Building your own
  app needs a licence key (`dn config --license-key dnk_…`). The official demos run
  without one ([installation](https://dartnative.com/docs/getting-started/installation)).
- Plugins come from its own registry, [dartpub.dev](https://dartpub.dev): 75
  plugins on 2026-10-09 (`GET https://dartpub.dev/api/plugins`), of which 36 are
  first-party. Pure-Dart pub.dev packages work. Flutter plugins that use
  platform channels or import `package:flutter` do not
  ([dependencies](https://dartnative.com/docs/getting-started/dependencies)).
- It came out of preview after six releases from 31 July 2026
  ([changelog](https://dartnative.com/changelog)). Two production apps are named:
  Gee, and Presence Messenger, which is still being ported
  ([home](https://dartnative.com/)).
- It has no backend, no web or desktop target, no visual editor and no hosted
  build machines on any page we read.

## Pricing

### DartNative ([#pricing](https://dartnative.com/#pricing), [dartpub.dev/framework](https://dartpub.dev/framework), [dartpub.dev/codepush](https://dartpub.dev/codepush))

| Plan | Price | Apps | CodePush fix installs included per month | Support |
|---|---|---|---|---|
| Community | Free | 1 production app | 2,000 | Basic |
| Standard | $49/year | Unlimited | 30,000 | Priority |
| Pro | $99/year | Unlimited | 100,000 | Highest priority |

- Every plan gets the framework and every plugin free.
- A "production app" is one that has passed 1,000 installs. You can build and
  test as many apps as you like.
- CodePush beyond the included installs is billed monthly per account:
  $1 per 3,000 installs up to 100k, $1 per 5,000 from 100k to 500k, and $1 per
  8,000 above 500k. One install is one phone receiving one fix, counted once per
  fix. Without a card on file, phones stop getting fixes once the included
  installs are used.
- **Contributor program** ([contributor-program](https://dartpub.dev/contributor-program)):
  authors of adopted plugins pay half price (3 production apps or 3,000 active
  installs) or nothing (5 production apps or 10,000 active installs). The tier is
  worked out from install data, and the plugin has to be kept up to date.
- **Continuity** ([license](https://dartnative.com/license),
  [Framework License §2c, §4](https://dartpub.dev/license/framework)): if your
  subscription lapses, apps you have already shipped keep working, but you can't
  build or ship. If DartNative is discontinued (an end-of-life notice, or 12 months
  with no updates), the source and first-party plugins must be published under
  BSD-3 within 90 days, and that duty binds any later owner.

### Dartvel ([dartvel.dev/cloud](https://dartvel.dev/cloud), `LICENSE`)

- The framework, CLI and Studio are FSL-1.1-MIT (`LICENSE`): free to use except for
  a competing product, and each version becomes MIT two years after release. There
  is no licence key and no app or install limit.
- Building on your own machine, uploading to the stores, OTA patches served from
  your own web-server binary, and self-hosting are free, and Cloud never gates them
  (`/cloud` FAQ).
- **Dartvel Cloud + Studio Pro** (not open yet): **$35 per project per month** for
  the first 100 people who sign up in the first week after launch, then **$40 per
  project per month**. It includes cloud builds for ten targets, store submission,
  hosted OTA patches, a credential vault, internal distribution, hosting, Studio
  Pro and a monthly Studio AI credit allowance. There is no free tier for cloud
  builds.

### Side by side

| | DartNative | Dartvel |
|---|---|---|
| What you pay for | The right to build with the framework, plus CodePush volume | Machines, hosting and Studio Pro. The framework is free |
| Unit | Per account, per year | Per project, per month |
| Entry price | $0 (1 production app) | $0 for everything local, unlimited apps |
| Paid price | $49–$99/year, unlimited apps | $35–$40/project/month ($420–$480/year per project) |
| OTA / code push | Hosted only, metered per install | Self-hosted free and unmetered; hosted in Cloud |
| Source | Closed; BSD-3 only if discontinued | Source-available now; MIT after 2 years per version |
| If you stop paying | Shipped apps keep running; building stops | Nothing stops; only Cloud features end |
| Plugin authors | Discount or free subscription for adopted plugins | No equivalent |

The prices measure different things, so comparing the numbers directly is
misleading. DartNative's fee is a framework licence. Dartvel's fee buys
infrastructure DartNative does not sell. The useful ideas to take from
DartNative are pricing by **install volume** for hosted OTA, a **contributor
discount** for module authors, and a written **continuity clause**.

## Feature inventory

Verdict key: **Has** = Dartvel ships it. **Partial** = parts are built. **Missing**
= not built. **Different** = Dartvel solves the same need another way.

### Rendering and UI

| DartNative feature | Source | Dartvel state | Verdict |
|---|---|---|---|
| Flutter widgets drawn with real UIKit / Android views (UILabel, UITextField, UITableView, RecyclerView) | [home](https://dartnative.com/), [widgets](https://dartnative.com/docs/widgets/overview) | Flutter renders everything. Platform views plus `DVPreferredRenderingMode` (`.preferPlatformNative`/`.auto`/`.default`) are planned (NEW_SPEC.md "Track C: native reach" item 3; "Native views" says Flutter stays the default renderer and a native view belongs to a module) | Missing (planned) |
| Keyboard animation in the same Core Animation transaction as the system keyboard; WindowInsetsAnimation on Android | [#native](https://dartnative.com/#native) | Nothing built for this. Dartvel uses Flutter's keyboard insets | Missing |
| iOS 26 Liquid Glass (UIGlassEffect, glass bars, floating tab pill, in-place search) | [liquid-glass](https://dartnative.com/docs/platform/liquid-glass) | No match in `packages/*/lib` | Missing |
| Real Material 3 MDC components; Material You dynamic colour | [material-3](https://dartnative.com/docs/platform/material-3) | Flutter Material 3 widgets. `dynamicColor: platform` is designed (NEW_SPEC.md Theme), but spec-status Theme is Partial: only light/dark mode is built | Partial |
| Adaptive look from one widget (iOS style on iPhone, M3 on Android) | [#native](https://dartnative.com/#native) | `DVPageShellMode.cupertino` uses `CupertinoPageScaffold` (`dartvel_flutter.dart` ~10733); primitives are otherwise one look | Partial |
| Recycling lists (FastList / FastGrid / MasonryFastGrid on UITableView/RecyclerView), 10k+ rows, flat memory | [architecture.md](https://github.com/DartNative/dartnative/blob/main/docs/architecture.md) | `DVBox.list`, `DVBox.grid` (uses `GridView.builder`), `DVBox.masonry`, `DVBox.builder`, plus Flutter's lazy lists | Different (Flutter lazy lists, not native recycling) |
| Native text and input: CoreText, system selection, magnifier, edit menu, autofill | [#native](https://dartnative.com/#native), [changelog](https://dartnative.com/changelog) | Flutter text and input | Different |
| CustomPaint drawn on Core Graphics / android.graphics.Canvas | [#native](https://dartnative.com/#native) | Flutter CustomPaint on Impeller/Skia | Different |
| Skia Graphite canvas island for shaders, opt-in (~9 MB) | [#native](https://dartnative.com/#native), [README](https://github.com/DartNative/dartnative) | Flutter fragment shaders are always there, because Flutter is the renderer | Different (always on) |
| Smaller app: 4.4 MB compressed new iOS app vs 5.7 MB Flutter (their figures) | [README](https://github.com/DartNative/dartnative) | iOS `Runner.app` is 15.4 MB uncompressed (`docs/build-targets.md`); no compressed figure measured | Not comparable yet |
| Foldables / iPhone Duo panes (ArrangementView, DisplayFeatureBuilder, hinge) | [changelog](https://dartnative.com/changelog) | `DVBox.twoPane`/`threePane` split at the fold, `context.screen.folds` (`test/fold_test.dart`) | Has |
| Accessibility: Semantics for VoiceOver and TalkBack (new in their latest release) | [changelog](https://dartnative.com/changelog) | spec-status Accessibility **Shipped**: switch control, hardware keys, release-gate audit of the real browser's semantics tree | Has (further along) |
| RTL, Directionality, PositionedDirectional | [changelog](https://dartnative.com/changelog) | Flutter RTL; i18n Shipped | Has |
| Pull to refresh in two styles, ReorderableListView, TabBar, NestedScrollView, Hero, InteractiveViewer, Overlay, Tooltip, date range picker | [changelog](https://dartnative.com/changelog), [tutorials](https://dartnative.com/tutorials) | All available as Flutter widgets in a Dartvel app | Has (from Flutter) |

### Dev loop and debugging

| DartNative feature | Source | Dartvel state | Verdict |
|---|---|---|---|
| Hot reload / hot restart (`dn run`, r / R) | [hot-reload](https://dartnative.com/docs/debugging/hot-reload) | `dartvel dev` hot reload; device pairing hot-restarts onto current sources (spec-status Dev Client) | Has |
| Navigation stack replayed after hot restart (`registerRoutes`) | [hot-reload](https://dartnative.com/docs/debugging/hot-reload) | The router takes `restorationScopeId` (`routing/router.dart`), but no stack replay after a hot restart is built or tested on mobile. On web the URL survives | Missing on mobile |
| One log stream for Dart + Swift + Kotlin in the terminal (`dnLog`) | [logging](https://dartnative.com/docs/debugging/logging) | spec-status Monitoring: "`DV.log` … unbuilt"; the Flutter client installs no log sink | Missing |
| Session log saved on the device, self-capping at about 2 MB, safe in production, for TestFlight boot hangs | [logging](https://dartnative.com/docs/debugging/logging) | No equivalent. Crash reports are written on the device and sent next launch (spec-status Crash Reporting, Partial), but that is crashes, not logs | Missing |
| `dn doctor` | [installation](https://dartnative.com/docs/getting-started/installation) | `dartvel doctor` (`commands/doctor_command.dart`) | Has |
| Your editor keeps working because `dn` shadows `flutter` on PATH | [installation](https://dartnative.com/docs/getting-started/installation) | Dartvel apps are Flutter apps; Flutter editor plugins work unchanged | Has |
| Free runnable demos, playground, 20+ tutorials in the repo | [github-repo](https://dartnative.com/docs/getting-started/github-repo), [tutorials](https://dartnative.com/tutorials) | `examples/`, site docs; no tutorial catalogue of runnable apps | Partial |
| `parity/` folder: the same screen in DartNative, Kotlin M3 and SwiftUI | [changelog](https://dartnative.com/changelog) | No mobile parity demo (`docs/studio/PARITY.md` is about Studio against Figma/Webflow) | Missing |
| Agent skills in the repo (`skills/dart-native`, `skills/dart-native-porting`) and an LLM porting guide | [repo tree](https://github.com/DartNative/dartnative/tree/main/skills), [tutorials](https://dartnative.com/tutorials) | Twelve agent rules files and `dartvel mcp` are built; spec-status Coding Agent Docs says "no SKILL.md per module and no dartvel agent skills sync … no llms.txt" | Partial |

### Delivery

| DartNative feature | Source | Dartvel state | Verdict |
|---|---|---|---|
| CodePush (`dn release`, `dn patch`), on every plan | [codepush](https://dartpub.dev/codepush), [changelog](https://dartnative.com/changelog) | `dartvel updates release/patch` through a self-hosted Shorebird patch source, verified on an Android emulator. spec-status OTA Updates: "Absent: a patch applied on iOS" | Partial (iOS not verified) |
| A patch can add new top-level functions | [changelog](https://dartnative.com/changelog) | Whatever Shorebird supports; not tested separately | Not checked |
| Hosted patch delivery metered per install, with volume tiers | [codepush](https://dartpub.dev/codepush) | Cloud "OTA patches on Cloud: Planned" (`/cloud`); flat per-project price | Different |
| Store builds | `dn run` / Xcode / Gradle ([installation](https://dartnative.com/docs/getting-started/installation)) | `dartvel deploy --store play/appstore/testflight/firebase-app-distribution`, also `--cloud` (spec-status App Store Deployment) | Dartvel has more |

### First-party plugins on dartpub.dev and where Dartvel stands

Dartvel apps are Flutter apps (`dartvel init` adds Dartvel to an existing
Flutter project, `docs/getting-started.md`), so pub.dev Flutter plugins such as
`video_player`, `camera`, `google_maps_flutter`, `lottie`, `rive` and
`webview_flutter` can be added today. This table lists what **Dartvel itself**
provides as a `DV.*` surface or module. `dart run tool/binding_coverage.dart`
on 2026-10-09 counted 103 binding names, bound as follows: linux 67, windows 45,
web 41, macos 40, android 36, **ios 8**. iOS binds only clipboard, deep links,
haptics, home widgets and tracking authorisation
(`platform/ios/ios_capabilities.dart`).

| DartNative plugin ([catalog](https://dartpub.dev/plugins)) | Dartvel surface | Verdict |
|---|---|---|
| video_player: cache + precache, PiP, background playback, lock screen, AirPlay | `DVBox.video`, DVMediaSignal state machines; spec-status Media: "no player or capture backend for Android, iOS, macOS, Windows, web…", only Linux GStreamer; no PiP/AirPlay/now-playing | Missing on mobile |
| camera: preview, photo + video, tap-to-focus | `camera.takePhoto` bound on Android only; "camera capture exists on no target and recordVideo is refused everywhere" (spec-status Media) | Missing |
| audio: play, PCM stream, record | `recordAudio` on Linux GStreamer only | Missing on mobile |
| lottie / rive | No match | Missing (pub.dev plugins usable) |
| webview | No match | Missing (pub.dev plugin usable) |
| google_maps | No match | Missing (pub.dev plugin usable) |
| notifications: local + FCM push | `notifications.sendLocal` on Android; push providers exist, but "server-side device token storage … is still the application's problem" (spec-status Mail and Notifications) | Partial |
| social_sign_in: native Apple + Google sheets | Server OAuth2 configs for Google and GitHub (`auth/oauth2.dart`); "add Sign in with Apple" is planned (NEW_SPEC.md Track D item 3); no native sheet | Partial |
| revenuecat: in-app purchases | DV.Purchases server ledger built; "the StoreKit and Play Billing client bindings, so DV.Purchases.buy … do not exist" (spec-status Purchases) | Partial (server only) |
| supabase / firebase | Dartvel has its own backend, auth and database; Firebase/Supabase auth adapters planned (Track D item 3) | Different |
| onnxruntime / supertonic_tts: on-device AI and TTS | AI adapters for Anthropic, OpenAI, OpenRouter, Gemini and Ollama (`ai/ai.dart`); `LocalDVAIAdapter` is a deterministic test fake; no on-device inference or TTS | Missing |
| sqlite / hive / shared_preferences / secure_storage | DV.Database (SQLite on device for offline models), DV.Cache, secrets in Keychain/Keystore (spec-status Secrets) | Has |
| path_provider / file picking | DV.FileStorage on every target with pick and pickDirectory (spec-status File Storage) | Has |
| permissions | `permissions.request/isGranted` on Android; not on iOS | Partial |
| share / url_launcher | `share.text` on Android; deep links on Android and iOS; no iOS share | Partial |
| connectivity | DV.Platform.network (used by offline sync, spec-status Offline-First Models) | Has |
| background tasks | DV.Jobs/Queues are server-side; no BGTaskScheduler/WorkManager binding | Missing on device |
| splash | `build/native_splash.dart` | Has |
| intl: ARB codegen | i18n Shipped | Has |
| app_review / autostart_settings / image_crop / compressor / svg / crypto / keys | No first-party match except crypto (webcrypto key store) | Mostly missing |

### Ecosystem and business

| DartNative feature | Source | Dartvel state | Verdict |
|---|---|---|---|
| Own registry with every version archived, plugins handed to new maintainers | [dartpub.dev](https://dartpub.dev), [license](https://dartnative.com/license) | Modules publish to pub.dev, which also archives versions (`dartvel modules publish`, spec-status Module Distribution) | Different |
| Public Registry API (catalog, readme, changelog, ETag, rate limit) | [registry-api](https://dartpub.dev/registry-api) | None; module discovery goes through pub.dev | Missing |
| `dn plugin publish` builds xcframework + aar + bindings in one command | [publisher-guide](https://dartpub.dev/publisher-guide) | `dartvel modules publish` signs and publishes; `dartvel add swift:/maven:/cargo:/npm:` wraps foreign sources (NEW_SPEC.md Module Sources, Partial) | Different (Dartvel wraps more sources) |
| Contributor discount for adopted plugins, worked out from install data | [contributor-program](https://dartpub.dev/contributor-program) | None | Missing |
| Install and active-app counts per plugin | [dartpub.dev](https://dartpub.dev) | Module Health (upstream watching, health signals) is Designed only | Missing |
| Sunset clause and continuity for shipped apps written into the licence | [license](https://dartnative.com/license) | FSL turns into MIT after two years by itself, so a sunset clause isn't needed. The `/cloud` page doesn't say what happens to hosted OTA patches or hosted apps if a Cloud plan lapses | Partial (Cloud terms) |
| Support tiers answered in priority order on the public repo | [#pricing](https://dartnative.com/#pricing) | No paid support tier | Missing |

## What Dartvel has that DartNative does not

Checked against every DartNative page listed above. "Not offered" means it
appears nowhere on their site, docs, changelog or repo on 2026-10-09.

| Dartvel | Evidence | DartNative |
|---|---|---|
| Web, web-server binary, desktop (macOS, Windows, Linux), tvOS, Tizen, eLinux, terminal, browser and VS Code extensions | `docs/build-targets.md` | iOS and Android only ([README](https://github.com/DartNative/dartnative)) |
| Full backend in the same project: backend functions, streaming, models, DB migrations, queues, cron, auth (LDAP, SAML, passkeys), authorisation, search | spec-status Backend, Database, Authentication, Search: Shipped | Not offered; uses Supabase/Firebase plugins |
| Server-rendered and static web output with SEO, PWA, sitemap | spec-status SEO, PWA, Static Web Generation: Shipped | Not offered |
| Dartvel Studio, a visual editor inside the app | spec-status Dartvel Studio: Shipped | Not offered |
| Every pub.dev Flutter plugin works, platform-channel plugins included | Dartvel apps are Flutter apps (`dartvel init`) | Platform-channel and `package:flutter` packages don't compile ([dependencies](https://dartnative.com/docs/getting-started/dependencies)) |
| OTA patches self-hosted at no cost, no install metering | spec-status OTA Updates; `/cloud` | Hosted, metered after the included installs ([codepush](https://dartpub.dev/codepush)) |
| Store upload from the CLI and cloud builds for iOS without a Mac | spec-status App Store Deployment, Dartvel Cloud | `dn` builds locally; no hosted builds offered |
| Source available, no licence key, nothing stops if you stop paying | `LICENSE` (FSL-1.1-MIT) | Closed source; licence key needed to build ([installation](https://dartnative.com/docs/getting-started/installation)) |
| Offline-first models with sync | spec-status Offline-First Models (Partial) | Not offered |
| AI tools, MCP server, provider adapters | spec-status AI (Partial), `mcp/framework_mcp_server.dart` | On-device ONNX and TTS plugins only |
| Kiosk mode, multi-window, XR presentation, home widgets | spec-status (Partial each) | Not offered |

## What to build, by priority

Impact means how much it closes the gap for someone choosing between the two for
a mobile app. Effort is a rough size: S = days, M = 1–3 weeks, L = a month or
more.

| # | What | Impact | Effort | Dartvel area |
|---|---|---|---|---|
| 1 | **iOS platform bindings to Android parity**: permissions, share, notifications, camera, location, biometrics, files, media pick (iOS has 8 of 103, Android 36) | High | L | Platform (`platform/ios/`) |
| 2 | **Video and audio players on Android and iOS** (AVPlayer, ExoPlayer) behind `DVBox.video`/`audio`, with **disk cache and precache**, PiP, background playback, now-playing | High | L | Media Playback and Capture |
| 3 | **Camera capture on Android and iOS** (CameraX, AVFoundation) behind `recordVideo`/`takePhoto` with a preview box | High | L | Media Playback and Capture |
| 4 | **OTA patch verified on iOS**, then hosted patches on Cloud with an install-volume tier on top of the project price | High | M | OTA Updates, Dartvel Cloud |
| 5 | **`DV.log` with one stream for Dart + native** in `dartvel dev`, plus an opt-in on-device session file with a size cap and rotation (`dartvel logs --device` to pull it) | High | M | Monitoring and Observability |
| 6 | **StoreKit and Play Billing client** so `DV.Purchases.buy` and restore work on device | High | L | Purchases and Entitlements |
| 7 | **Native Sign in with Apple and Google sheets** as DVAuthProvider adapters | Medium | M | Authentication (Track D item 3) |
| 8 | **Platform-native rendering mode** (Track C item 3): native text fields and lists first, then Liquid Glass bars and M3 dynamic colour; finish the Theme token work (`dynamicColor`) | Medium-high | L | UI, Theme |
| 9 | **First-party modules or written recipes** for maps, webview, Lottie/Rive, in-app review, background tasks, so `dartvel add maps` gives a known-good answer | Medium | M (per module) | Modules, Module Sources |
| 10 | **Navigation stack survives hot restart** on mobile (replay the route stack from the URL/restoration id) | Medium | S | Routing, Dev Client |
| 11 | **Push token storage** on the server, and local notifications on iOS | Medium | M | Mail and Notifications |
| 12 | **Continuity terms for Cloud**: state in `/cloud` and the terms what keeps running when a plan lapses (shipped apps, hosted patches, hosted binary) | Medium | S | Dartvel Cloud |
| 13 | **Module author incentive**: a Cloud discount for authors of widely used modules, plus install/health numbers (Module Health) | Medium | M | Module Distribution, Module Health |
| 14 | **Agent skills and llms.txt**: SKILL.md per module, `dartvel agent skills sync`, a "port a Flutter app" skill | Medium | S | Coding Agent Documentation |
| 15 | **Mobile parity demo and tutorial catalogue**: the same screen in Dartvel, SwiftUI and Kotlin M3; 15–20 short runnable tutorials (chat, feed, camera, video, maps) | Medium | M | Docs, examples |
| 16 | On-device inference (ONNX/Core ML/NNAPI) as an AI adapter | Low-medium | M | AI |
| 17 | Measure compressed iOS/Android app size and publish it in `docs/build-targets.md` | Low | S | Build |

Items 1–3 and 6 are the core of the gap. DartNative's whole pitch is that the
mobile basics (media, camera, purchases, sign-in) work natively from day one,
while Dartvel's mobile surface is thinnest on iOS. Items 4, 5, 10 and 12 are
cheaper and close visible gaps in the developer experience and pricing.

## Not worth copying

- **A closed licence key to build.** Dartvel's free, source-available framework is
  a point in its favour.
- **Dropping Flutter's renderer as the default.** NEW_SPEC.md keeps Flutter as the
  default renderer, with native views owned by modules, and that is what lets one
  render path run on web, desktop and TV. A per-primitive native mode (item 8)
  gets the benefit without losing that.
- **A separate plugin registry.** pub.dev already archives versions. A Dartvel
  catalogue page over pub.dev plus the Registry-API-style JSON (item 13) would do
  the same job.
