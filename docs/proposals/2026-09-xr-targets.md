# visionOS and Android XR as Build Targets — Proposal

**Status: Draft 2026-09-25, not yet reviewed.** On approval this amends the
Build targets, Configuration and Platform matrix subsections of *XR — Spatial
Presentation* in NEW_SPEC.md. The section keeps `Stability: Draft`. The
`absent` text in `docs/spec-status.json` changes only as each phase's files
and evidence land in `docs/build-targets.md`.

NEW_SPEC.md already designs the Dart side of XR, and much of it is built:
`DVWindowKind.volume` and `.immersive`, `window.spatial`, the session, anchors,
comfort, consent, `DVXRBindingDevice` over `DVNativeBridge`, and
`DV.Test.fakeXR`. None of it reaches a headset. `dartvel build` and `dartvel
doctor --target` accept neither `visionos` nor `android-xr`, no native XR
binding is registered on any target, and `capability.spatial` is null
everywhere outside tests. This proposal says what it takes to change that,
target by target, and where the platforms stop us.

The short version:

| | Runs today as | Spatial surfaces need | Blocked on |
|---|---|---|---|
| **Android XR** | an ordinary Android app in a 2D panel, unmodified | jnigen bindings over Jetpack SceneCore (Views path, no Compose) | a device or a non-Linux emulator to verify on; SceneCore is `1.0.0-rc01` and still breaking |
| **visionOS** | the iOS app, as a "Designed for iPad" compatible app in one window | a native visionOS app, which needs a Flutter engine and Dart AOT built for `xros` | engine and Dart runtime work that Flutter has said it will not do |

Android XR can reach phase 2 with work that is all Dartvel's own. visionOS
cannot get past phase 1 without a Flutter engine port. The proposal treats
that asymmetry as the main finding, not something to smooth over.

How the sections map to phases:

| Phase | Android XR | visionOS |
|---|---|---|
| 1: the existing app, well, in a window or panel | section 1 | section 2 |
| 2: spatial surfaces on `DVWindowKind.volume`/`.immersive` and `DVScene` | section 3 | none possible without phase 3 |
| 3: engine work | none identified | section 4 |

---

## What the platforms offer, as of this week

### visionOS

- **Current release.** visionOS 27.0 and Xcode 27 shipped on 2026-09-14.
  Xcode 27 needs macOS Tahoe 26.6 or later on Apple silicon
  ([Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes);
  [9to5Mac, 2026-09-09](https://9to5mac.com/2026/09/09/visionos-27-release-date-heres-when-the-new-update-launches/)).
  A community report says uploads must be built with the visionOS 27 SDK or
  later from April 2027
  ([Mac Observer](https://www.macobserver.com/news/april-2027-sdk-requirement-five-platforms/),
  not confirmed on Apple's site).
- **Hardware.** The only device is Vision Pro, refreshed with M5 on
  2025-10-22
  ([Apple Newsroom](https://www.apple.com/newsroom/2025/10/apple-vision-pro-upgraded-with-the-m5-chip-and-dual-knit-band/)).
  Reports disagree about when a cheaper model will ship, and none has
  ([9to5Mac, 2026-05-31](https://9to5mac.com/2026/05/31/apple-glasses-launching-late-2027-with-vision-air-to-follow-by-2029/),
  community).
- **Compatible apps (official).** Unmodified iPhone and iPad apps run on
  Vision Pro in one resizable window. They are listed on the visionOS App Store
  by default. The switch is "Make this app available on Apple Vision Pro" under
  Pricing and Availability in App Store Connect, not something in the binary
  ([Apple: Determining whether to bring your app to visionOS](https://developer.apple.com/documentation/visionos/determining-whether-to-bring-your-app-to-visionos)).
  The same page lists what a compatible app loses:
  - no ARKit views, no camera capture, no haptics
  - "Always" location is downgraded to "When in Use"
  - at most two simultaneous touches
  - **no app extensions load**: widgets, keyboards, App Clips
  - no volumes and no immersive spaces; the app is one window
- **Detecting compatibility mode (official).** `NSProcessInfo.isiOSAppOnVision`
  was added in the iOS 26.1 SDK and is false on earlier systems
  ([ProcessInfo](https://developer.apple.com/documentation/foundation/processinfo);
  [Michael Tsai, 2025-11-04](https://mjtsai.com/blog/2025/11/04/visionos-26-1/)).
- **Input (official).** The user looks at something and pinches, and a
  compatible app receives that as a touch. The system draws hover highlights
  out of process, and only on standard UIKit and SwiftUI controls. An app
  never learns where the user is looking
  ([HIG: Eyes](https://developer.apple.com/design/human-interface-guidelines/eyes)).
  Flutter paints its own controls, so they get no gaze highlight. That is
  [flutter/flutter#129640](https://github.com/flutter/flutter/issues/129640),
  open, P3.
- **Native spatial apps (official).** A native app is a SwiftUI `App` with
  `WindowGroup`, `.windowStyle(.volumetric)` for volumes, and `ImmersiveSpace`
  with a mixed, progressive or full style
  ([ImmersionStyle](https://developer.apple.com/documentation/swiftui/immersionstyle)).
  3D content is RealityKit (`RealityView`). CompositorServices serves custom
  Metal rendering in a full space
  ([CompositorServices](https://developer.apple.com/documentation/compositorservices)).
  `UIViewControllerRepresentable` exists on visionOS, so a UIKit view
  controller can be hosted in a SwiftUI window, but that controller has to be
  built for visionOS.
- **Flutter (official).**
  [flutter/flutter#128313](https://github.com/flutter/flutter/issues/128313)
  "Add support for visionOS" is open, P3, labelled "would require significant
  investment". On 2024-06-19 the Flutter team wrote: "There are no current
  plans to resolve this issue, because of the permanent long-term costs." A
  team member shared an unofficial engine experiment on 2024-07-17. It needed
  gn and buildroot changes, a Dart runtime build change, plugin APIs marked
  unavailable, and keyboard and `UIScreen` refactoring. No PR in flutter/flutter
  adds an `xros` or `xrsimulator` target. The 2026 roadmap does not mention
  visionOS ([Roadmap.md](https://github.com/flutter/flutter/blob/main/docs/roadmap/Roadmap.md)).
- **Dart (official).** dart-lang/sdk has no issue for visionOS or `xros`.
  [dart-lang/native#961](https://github.com/dart-lang/native/issues/961)
  "Support visionOS" is open with no assignee, last updated 2024-08-30.
  `code_assets` has no visionOS value in its `OS` enum
  ([OS class](https://pub.dev/documentation/code_assets/latest/code_assets/OS-class.html)).
  [flutter/flutter#142933](https://github.com/flutter/flutter/issues/142933)
  (native assets on visionOS) is blocked on it.
- **Tooling gap (official).**
  [flutter/flutter#129638](https://github.com/flutter/flutter/issues/129638):
  `flutter devices` does not list visionOS simulators or devices, even for
  compatible apps. The workaround in the thread is to run the app from Xcode on
  the visionOS simulator and then `flutter attach`.
- **Community.** No Flutter embedder or engine fork for visionOS is
  maintained. The demos from 2023 and 2024 are abandoned or were never
  published: Thaanu2001/Movie-App-VisionOS-Flutter was last pushed 2023-06-26,
  and WooSeongg/flutter_visionOS 2024-01-29. React Native, for comparison,
  has a maintained fork (callstack/react-native-visionos).

### Android XR

- **Hardware.** Samsung Galaxy XR shipped in the US and Korea in October 2025
  at US$1,799.99 and in the UK on 2026-07-08
  ([Samsung](https://news.samsung.com/us/introducing-galaxy-xr-opening-new-worlds/);
  [Wikipedia](https://en.wikipedia.org/wiki/Samsung_Galaxy_XR)). It is the only
  Android XR headset on sale. Audio glasses were announced at I/O 2026 for
  "later this fall", display glasses later
  ([blog.google, 2026-05-19](https://blog.google/products-and-platforms/platforms/android/android-xr-io-2026/)).
  XREAL Project Aura is in an early-access programme only.
- **Unmodified apps (official).** "Existing 2D mobile apps are automatically
  compatible with Android XR headsets and wired XR glasses devices as long as
  they don't require any features that are unsupported, such as telephony"
  ([Mobile app readiness](https://developer.android.com/develop/xr/check-mobile-app-readiness)).
  A Flutter Android app is an Android app, so it runs in a Home Space panel,
  1024×720 dp by default and resizable from 385×595 to 2560×1800 dp. The
  readiness page names what goes wrong: locked orientation, the virtual front
  camera, touch precision, dynamic resizing, multi-resume, and content too
  close to the window edge.
- **Jetpack XR SDK (official).** SceneCore `1.0.0-rc01` (2026-09-09), Compose
  for XR `1.0.0-beta01` (2026-09-23), ARCore for Jetpack XR and XR Runtime
  `1.0.0-beta02`. None is stable yet
  ([SceneCore releases](https://developer.android.com/jetpack/androidx/releases/xr-scenecore);
  [beta announcement, 2026-08-18](https://android-developers.googleblog.com/2026/08/jetpack-xr-sdk-core-libraries-beta.html)).
  beta01 broke a lot of API: `Session.create` became a suspend function,
  `AnchorEntity` became `AnchorSpace`, `GltfModel.create` became suspend and
  `AutoCloseable`, and `launchActivity` became `startActivity`.
- **Views apps (official).** "Spatial UI for Views apps" says a non-Compose
  app works directly with SceneCore's `Session`, `MainPanelEntity`,
  `PanelEntity.create(session, view, …)` and `ActivityPanelEntity`
  ([ui-views, updated 2026-09-22](https://developer.android.com/develop/xr/jetpack-xr-sdk/ui-views)).
  That is the path a `FlutterActivity` would take. A `FlutterView` is not
  named on that page; treating it as "a View" is an inference that has not
  been tested.
- **Home Space and Full Space (official).** Home Space runs several apps side
  by side with system environments only. Full Space runs one app and adds
  spatial panels, 3D models and custom environments. An activity's start mode
  is set with the `android.window.PROPERTY_XR_ACTIVITY_START_MODE` property
  ([transition to Full Space](https://developer.android.com/develop/xr/jetpack-xr-sdk/transition-home-space-to-full-space)).
- **Manifest and Play (official).** A Jetpack XR app that requires XR declares
  `<uses-feature android:name="android.software.xr.api.spatial"
  android:required="true"/>`. Mobile apps are discoverable on XR
  automatically, and Play has a dedicated Android XR release track
  ([Package and distribute, updated 2026-05-19](https://developer.android.com/develop/xr/package-and-distribute)).
  XR apps must target API 34 or higher. There are XR quality guidelines
  ([Android XR quality](https://developer.android.com/docs/quality-guidelines/android-xr)).
- **Input (official).** A pinch is a tap and a held pinch drags. Gaze gets a
  system hover effect, and raw eye data is never given to apps. Keyboard,
  mouse and 6DoF controllers are also supported. 2D panels receive input
  "through the standard Android UI framework"
  ([Design foundations](https://developer.android.com/design/ui/xr/guides/foundations)).
- **Emulator (official).** The Android XR emulator runs on macOS 13.3+ on
  Apple silicon with 16 GB, or on Windows 11 with a discrete GPU with 8 GB of
  VRAM. **Linux is not a supported host.** It needs the latest Android Studio
  Canary
  ([Create XR AVDs, updated 2026-06-15](https://developer.android.com/develop/xr/jetpack-xr-sdk/run/create-avds/xr-headsets-glasses)).
- **Flutter (official).**
  [flutter/flutter#160578](https://github.com/flutter/flutter/issues/160578)
  "Add support for Android XR" and
  [#172225](https://github.com/flutter/flutter/issues/172225) "Android XR
  tooling" were both closed as not planned, the second with the reply that
  Android XR "supports android apps out of the box". The I/O 2026 Flutter
  recap does not mention XR
  ([Flutter blog, 2026-05-28](https://flutter.dev/blog/thats-a-wrap-everything-flutter-at-google-i-o-2026)).
- **Community.** [`flutter_xr`](https://pub.dev/packages/flutter_xr) 0.0.6
  calls itself a proof of concept and "NOT PRODUCTION READY". It wraps Compose
  for XR `alpha09` through Pigeon platform channels and runs five Flutter
  engines in one host activity. It is useful as evidence that a `FlutterView`
  renders inside an XR panel. It is not usable by Dartvel: it uses platform
  channels, and its API is several breaking releases behind.
- **Rendering.** No public issue on Impeller Vulkan specific to Android XR was
  found. General Adreno Vulkan issues exist on the same GPU family
  ([#176211](https://github.com/flutter/flutter/issues/176211),
  [#160941](https://github.com/flutter/flutter/issues/160941)). This has to be
  measured on a device.

---

## What Dartvel already has

- **The Dart half of XR.** `packages/dartvel_core/lib/src/xr/` and
  `packages/dartvel_flutter/lib/src/xr/xr.dart`: `DVXRDevice`, and
  `DVXRBindingDevice`, which calls eleven `xr.*` bindings through
  `DVNativeBridge` and turns a missing or throwing binding into `DV-XR-006`.
  A native side only has to register those names. Nothing above them changes.
- **A variant-of-Android target.** `fireos` is in `flutterBuildPlatforms`,
  maps onto the Android toolchain, and shares the manifest writers (Context
  provider, capture bridge, kiosk, home widgets, deep links). `android-xr`
  fits the same slot.
- **jnigen, committed.** `packages/dartvel_flutter/tool/android_bindings.jnigen.yaml`
  generates bindings from `android.jar` on a runner and commits the output.
  SceneCore would be a second config with the `androidx.xr` AARs on its
  classpath.
- **Apple FFI.** `macos_bindings_ffi.dart` calls the Objective-C runtime
  through `dart:ffi` and sends only pointer-returning messages. A `BOOL`
  property such as `isiOSAppOnVision` returns in a register on arm64, which is
  safe, but it is a new return shape for that file and deserves a test.
- **An Xcode-project writer.** `apple_widget_target.dart` adds a target to
  `project.pbxproj` idempotently. A native visionOS host would need the same,
  and more.
- **An engine-build path.** `build/engine_build.dart` and `dartvel engine`
  build Flutter engines Google does not publish (32-bit ARM for webOS). That
  is Linux-only today; an `xros` engine needs macOS and Xcode.
- **An Apple-platform community engine as precedent.** `dartvel build tvos`
  rides `fluttertv/flutter-tvos` through the `dartvel_tvos` fork. That project
  is a working example of a community keeping a Flutter engine for a UIKit
  platform Apple does not target in Flutter, with origin-signed artifacts per
  Flutter release. A visionOS port would be the same kind of project.

---

## 1. `dartvel build android-xr` — the existing app, well, in a panel

**Problem.** A Dartvel Android app already runs on Galaxy XR. Nobody has
checked that it runs *well*. The readiness list above is a list of things
Dartvel does or lets applications do: kiosk locks orientation, the capture
bridge uses the camera, and pages assume phone widths. And there is no build
that can say it is for XR, so `DV.Platform` reports a phone or tablet on a
headset.

**Proposal.** `android-xr` joins `flutterBuildPlatforms` beside `fireos`,
built with `flutter build appbundle` (default) or `apk`.

- **Same app, stated platform.** The build passes
  `--dart-define=DARTVEL_PLATFORM=android-xr`, the override `DVPlatform`
  already reads, for the same reason tvOS does: nothing at run time otherwise
  tells a panel on a headset from a tablet. A runtime check through jnigen
  (`PackageManager.hasSystemFeature("android.software.xr.api.spatial")`)
  backs it up, because a plain `android` build can also land on a headset.
  That check is what sets `DVPlatform` for an unmodified app.
- **Manifest, phase 1.** A panel-only app changes nothing that would hide it
  from phones. The build writes the start-mode property as Home Space and does
  **not** declare `android.software.xr.api.spatial` as required, unless the
  project asks. A manifest writer, `android_xr_manifest.dart`, sits after the
  kiosk block with the same begin/end markers the other writers use.
- **Readiness preflight.** Before Gradle starts, the build reports, with
  codes, what the readiness page says goes wrong, read from the project rather
  than guessed:
  - a declared kiosk (lock task and a locked orientation do not mean the same
    thing on a headset; see Open questions)
  - `uses-feature` entries for telephony or a camera with `required="true"`
  - `screenOrientation` locks in the manifest
  - `resizeableActivity="false"`
  - `targetSdk` below 34

  A problem is a warning unless it makes Play refuse the upload.
- **Artifact.** `build/app/outputs/bundle/release/app-release.aab`, the same
  as `android`. Play takes it on the Android XR release track, or on the main
  track, where it serves every device. `docs/build-targets.md` records which.
- **Doctor.** `android-xr` joins `doctorTargets`. It checks what the Android
  build already needs, plus that the host can run the XR emulator. On Linux it
  says plainly that it cannot and names the two supported hosts. It never
  installs Android Studio Canary or a system image, per the Build Toolchain
  Rule.

**Embedder Fork Rule.** No fork. This is plain `flutter build`, like
`fireos`, and it has no vendor embedder.

**What it cannot do.** It does not open volumes or immersive spaces.
`capability.spatial` becomes a real headset capability with `panels: true`,
`volumes: false`, `immersive: false`. Then `open(kind: .volume)` presents the
viewport and reports `DV-WINDOW-014`, exactly as on a phone. Home Space is a
single panel; a second `DV.Window.open(route)` goes wherever Android's
multi-window support takes it today, which is not verified on a headset.

**Effort.** Two to four days: target registration, the define, the manifest
writer, the preflight, and tests that assert on the written manifest and on
`aapt2 dump badging` output from a real AAB, not on argument lists.

## 2. `dartvel build visionos` — the iOS app, honestly labelled

**Problem.** A Dartvel iOS app that supports iPad already reaches Vision Pro,
by default and whether its author knows it or not. What loses the most is
something Dartvel itself generates: **home widgets are an app extension, and
extensions do not load in compatibility mode.** Camera capture, haptics and
background location degrade silently. A developer has no build that tells
them this, and no way to try it without driving Xcode by hand.

**Proposal.** `visionos` becomes a build target name that does **not**
produce a new kind of binary, and says so:

- **It builds the iOS app.** `dartvel build visionos` runs the iOS build
  (`--format ipa` by default) with the checks below, and writes to the same
  `build/ios/ipa`. The Vision Pro artifact *is* the iOS IPA, and App Store
  Connect's availability switch is what puts it on the headset. A separate
  output directory would suggest a separate binary that does not exist. The
  command's final line says to check that switch, because a build tool cannot
  set it.
- **No build-time platform define.** One binary serves iPhone, iPad and
  Vision Pro, so `DARTVEL_PLATFORM` cannot be set at build time as it is for
  tvOS. `DVPlatform` reads `NSProcessInfo.isiOSAppOnVision` through FFI on
  iOS 26.1 or later. Before 26.1 it cannot know, and it says `ios`/`tablet`.
- **Compatibility preflight.** Before Xcode starts, the build requires iPad
  support (`TARGETED_DEVICE_FAMILY` contains 2). Without it the app still
  reaches Vision Pro, but as an iPhone app in a phone-shaped window. Then it
  lists, from the project's own declarations, what will not work there:
  - home widgets (extension will not load)
  - camera capture pages
  - haptic feedback calls, which become audio
  - `Always` location
  - anything on the spec's ARKit path

  These are reported as one new code, `DV-XR-008` "unavailable in visionOS
  compatibility mode" (info level). `dartvel analyze` raises the same code, so
  the list is visible without a Mac.
- **Runtime.** On Vision Pro, the capabilities that are absent report absent
  rather than failing late: `DV.Platform.Camera` capture, haptics and widget
  reloads. `capability.spatial` reports `panels: true`, `volumes: false`,
  `immersive: false`, which the spec's visionOS row already says.
- **Development.** `dartvel build visionos --simulator` builds the iOS
  simulator app, installs it on a booted visionOS simulator with `xcrun simctl`,
  and `dartvel dev` attaches with `flutter attach`, the documented workaround
  for #129638. Whether `simctl install` accepts an iOS simulator build on a
  visionOS runtime is the first thing to establish on a Mac. If it does not,
  the fallback is `xcodebuild` with the "Designed for iPad" destination.
- **Doctor.** `dartvel doctor --target visionos` checks for macOS, Xcode 27 or
  later, and an installed visionOS simulator runtime. It never downloads
  Xcode or a runtime and tells the developer where to get both.

**Embedder Fork Rule.** No fork. The build is plain `flutter build ios`, and
there is no visionOS embedder to fork.

**What it cannot do.** Anything spatial. No volumes, no immersive spaces, no
second window (compatible apps get one), no gaze hover on Flutter-drawn
controls. This phase is the ceiling on visionOS until section 4.

**Effort.** Three to five days for the CLI, the preflight, the FFI check and
tests. Verification needs a Mac (see Verification).

## 3. Android XR spatial surfaces — `volume` and `immersive` through SceneCore

**Problem.** `DVWindowKind.volume` and `.immersive` exist, and a session
drives them, but nothing native answers `xr.space.open`. The spec's footnote ¹
also says volumes depend on the flag-gated Flutter GPU renderer that 3D Scenes
does not have yet. That would put Android XR spatial behind a renderer that
has not been written.

**Proposal.** Register the eleven `xr.*` bindings on Android through jnigen
over SceneCore's Views path, and let **SceneCore render the scene**, not
Flutter.

- **Bindings.** A second jnigen config,
  `tool/android_xr_bindings.jnigen.yaml`, generates Dart for `Session`,
  `Scene`, `MainPanelEntity`, `PanelEntity`, `ActivityPanelEntity`,
  `GltfModel`/`GltfModelEntity`, `AnchorSpace` and the spatial environment
  classes, against pinned `androidx.xr.scenecore` and `androidx.xr.runtime`
  AARs. It runs on the same runner as the existing bindings and its output is
  committed. SceneCore uses Kotlin suspend functions (`Session.create`,
  `GltfModel.create`). jnigen documents support for them; whether 0.17
  generates usable async Dart for these particular signatures is the first
  spike. If it does not, a small Kotlin shim with blocking or callback methods
  is still JNI, not a platform channel.
- **Linked only on use.** The spec already says `xr:` is linked when a volume,
  an immersive space or an anchor is used. The AAR dependency and the
  generated bindings go into the Gradle build only then. A panel-only app from
  section 1 carries none of it.
- **Panel.** The existing `FlutterActivity` is the `MainPanelEntity`. Nothing
  new.
- **Volume.** `open(route, kind: .volume)` asks for Full Space, creates an
  entity sized from `DVVolumeOptions.size`, and builds the route's `DVScene`
  as SceneCore entities. Each `DVModel3D` becomes a `GltfModelEntity` from the
  same verified asset bytes `DVSceneAssetLoader` already produces. Transforms
  come from `DVSceneGraph`, which already converts to right-handed Y-up metres,
  the convention SceneCore uses too. **The DVScene document is the contract,
  and the OS is the renderer.** That removes the Flutter GPU dependency for
  spatial kinds and should be written into footnote ¹. The flat viewport keeps
  needing a Flutter renderer, which is 3D Scenes' problem and not this one.
- **Immersive.** `open(route, kind: .immersive)` requests Full Space with the
  requested passthrough or a full environment. It keeps the existing
  exclusivity and camera-permission flow in `spatial_session.dart`.
- **2D content in space.** A Flutter-drawn panel beside a volume, such as a
  controls panel, is an `ActivityPanelEntity` hosting a second activity on an
  engine from a `FlutterEngineGroup`. That is a second window, and it goes
  through `DV.Window.open(route)` as windows already do. Multi-window on
  Android is not verified today, so this item is last in the phase.
- **Input.** Taps on entities arrive through SceneCore's input events, go
  through the session's existing ray-to-node picking, and reach `.onTap()`.
  Gaze stays a selection, never a position.
- **Manifest.** When `xr:` is linked, the manifest declares
  `android.software.xr.api.spatial`. It declares it `required="false"` unless
  `dartvel.xr.android.requireSpatial: true`, so one AAB still serves phones.

**What it cannot do.**
- Orbiters, `SpatialDialog` and the curved layouts are Compose for XR
  concepts. There is no Views equivalent for most of them, and they are out
  of scope.
- Anything a `DVScene` expresses that SceneCore cannot render (custom shaders,
  Dartvel-specific materials) degrades, and is reported per node.
- The glasses row stays `Experimental` and out of scope: no volumes, and no
  Play distribution for glasses yet.

**Effort.** Three to six weeks, most of it on a device: the jnigen spike, the
bindings, the DVScene-to-entity mapping, session lifecycle across pause and
resume, and the manifest gating. SceneCore is at rc01 and still breaking, so
budget one re-generation per release until 1.0 stable.

## 4. visionOS spatial surfaces — engine work, and a decision rather than a task

**Problem.** Phase 2 on visionOS needs a native visionOS app. The obvious
hybrid, a SwiftUI host app with a `FlutterViewController` in a `WindowGroup`
plus RealityKit volumes driven from Dart through FFI, is exactly what option
(b) in the brief describes. **It is not reachable without option (c).** A
native visionOS app links binaries built for the `xros` platform. Flutter
ships `Flutter.framework` for iOS only, and Dart ships no AOT runtime for
`xros`. So there is no Flutter view to host, no Dart to drive the FFI, and no
middle phase.

**Proposal.** Do not start this until there is demand that justifies owning a
Flutter engine port. If there is, the shape is:

- **A fork, `Danroyal001/dartvel_visionos`.** It has no vendor upstream. Its
  base is Flutter's own engine source at Dartvel's pinned version, carrying
  the changes the Flutter team's 2024 experiment named: gn and buildroot
  targets for `xros`/`xrsimulator`, the Dart runtime build change, `UIScreen`
  and keyboard refactoring, and plugin APIs marked unavailable.
  `fluttertv/flutter-tvos` is the model for the CLI and artifact side. It
  shows a community can publish origin-signed engine artifacts per Flutter
  release for a UIKit platform. The Embedder Fork Rule's table gains a row
  with "Flutter engine (no vendor)" as upstream, and the README banner states
  the pinned engine and what has been verified.
- **The host.** A generated SwiftUI app: a `WindowGroup` hosting the
  `FlutterViewController` through `UIViewControllerRepresentable`, plus one
  `WindowGroup(.volumetric)` and one `ImmersiveSpace` declared at build time.
  SwiftUI scenes are declared statically, so the generator emits a fixed set
  that `openWindow`/`openImmersiveSpace` then address by id.
- **Bindings.** RealityKit and SwiftUI scene actions are Swift-only, so
  `dart:ffi` reaches them through a generated Swift file exporting
  `@_cdecl` C functions, compiled into the host. That is FFI, as the rule
  requires. The DVScene-to-entity mapping is the same idea as Android's, with
  RealityKit entities in place of SceneCore ones.
- **Native assets.** `dartvel_shelf` and `dartvel_core` have build hooks, and
  `code_assets` has no visionOS `OS` value (dart-lang/native#961). Until it
  does, the fork has to build those libraries itself, or the target ships
  without them. That is a blocker for any app that serves a backend.

**Why this is a decision.** Every Flutter release would need the engine
rebuilt and re-verified, on macOS. Flutter's own team declined this for
"permanent long-term costs", and that cost does not shrink because a smaller
team pays it. The alternative is to wait on #128313 and dart-lang/native#961,
and keep phase 2 as the visionOS ceiling.

**Effort.** Months to reach a first simulator build, based on the scope the
Flutter team described and the absence of any maintained community attempt.
Then ongoing work every Flutter release. This estimate is the least certain
number in the proposal.

---

## Configuration

The spec's `dartvel.xr` block stays as it is. Two platform keys are added,
each with a default that changes nothing:

```yaml
dartvel:
  xr:
    enabled: true               # existing; see Open questions
    android:
      startMode: home           # home | full → PROPERTY_XR_ACTIVITY_START_MODE
      requireSpatial: false     # true: uses-feature ...xr.api.spatial required, XR-only listing
    visionos:
      requireIpad: true         # preflight refuses a build without iPad support
```

There is no key for Vision Pro availability. It is an App Store Connect
setting, and a key that looked like it controlled it would be decoration.

## Target names, doctor and build registry

| Name | Registry list | Host | Toolchain | Artifact |
|---|---|---|---|---|
| `android-xr` | `flutterBuildPlatforms` | any | Android SDK (not installed by Dartvel) | AAB (default) or APK |
| `visionos` | `flutterBuildPlatforms`, resolving to the iOS build | macOS | Xcode 27+, visionOS simulator runtime for `--simulator` | the iOS IPA |

- `isPlatformAvailableOn`: `android-xr` true everywhere, `visionos` macOS
  only. Both join `doctorTargets` through the lists they are in, not by hand.
- `--platform all` should not build `visionos`, since it would build the iOS
  app twice. Whether `android-xr` joins `all` depends on whether its AAB
  differs from `android`'s. In phase 1 it differs only by the define and one
  manifest property, so it stays out.
- `horizon`, which the spec names beside these, is out of scope here. It is
  the same shape as section 1 with Meta's manifest instead of Google's.

## Verification: what can be checked where

| Check | This Linux server | macOS (own Mac or runner) | Windows + GPU | Device |
|---|---|---|---|---|
| `android-xr` AAB builds; manifest and badging inspected | yes (Android SDK at `~/android-sdk`, API 36) | — | — | — |
| SceneCore jnigen generation | yes, with the AARs from Maven | — | — | — |
| `android-xr` runs in the XR emulator | **no**: Linux is unsupported and this host has no `/dev/kvm` | Apple silicon, 16 GB, Android Studio Canary | GTX 10-series / RX 5000+ with 8 GB VRAM | — |
| Volumes, immersive and passthrough on Android XR | no | emulator (partial) | emulator (partial) | Galaxy XR |
| `visionos` IPA builds; preflight | preflight and `analyze` only | yes, Xcode 27 | — | — |
| Compatible app runs in the visionOS simulator | no | yes, if a visionOS runtime is installed | — | — |
| Gaze and pinch feel, text input, performance | no | no | no | Vision Pro |

GitHub Actions is locked for billing at the moment. That removes the
macOS-runner path CLAUDE.md relies on for Apple targets, and the Dartvel
Cloud macOS worker, which runs there too. Until it is unlocked, every
`visionos` row that needs macOS needs someone's Mac. Separately, and to be
confirmed when Actions returns: Apple silicon hosted runners are generally
reported not to run the Android emulator, because they lack nested
virtualization. So the Android XR emulator may not be a CI job even then.
Honest verification of phase 3 is a physical Galaxy XR.

`docs/build-targets.md` gets one row per target, recording only what was run
and inspected.

## Risks

- **SceneCore churn.** rc01, with a large breaking beta01 a month earlier.
  Pin exact versions and regenerate deliberately. Section 3's bindings are
  generated, so a break shows up at generation, not at run time.
- **Impeller Vulkan on Adreno.** No XR-specific evidence either way. General
  Adreno issues exist. Measured against `DV-XR-007`'s 90 fps target in a
  panel on a device before section 3 is labelled anything but
  `Experimental`.
- **Memory with several engines.** `flutter_xr` runs five engines. A
  `FlutterEngineGroup` shares the isolate snapshot, but each panel is still a
  surface and a raster thread. Budget panels, as the spec's performance
  contract already says.
- **Apple review.** Low for sections 2 and 4 alike on the review itself.
  Compatible apps are the default, and a native app built on a custom engine
  uses no private API. The real risk in section 4 is maintenance, not review.
- **Accessibility on visionOS.** Flutter's semantics tree reaches VoiceOver
  in compatibility mode as it does on iPad, but Flutter-drawn controls get no
  gaze hover (#129640). Dwell Control users need every action to be doable
  with tap, scroll, long press or drag, which `DVPage` controls already are.
  The gap is visual feedback, not reachability. The accessibility audit
  (`build/accessibility_audit.dart`) should run for `visionos` as for `ios`.
- **Misleading target names.** A `visionos` target that is really `ios`
  could read as more than it is. The mitigation is what section 2 does: same
  output path, and a final line that says what was built.

## Spec amendments this implies

1. Build targets: `android-xr` and `visionos` as described in sections 1
   and 2, and the note that `visionos` produces the iOS IPA.
2. Platform matrix footnote ¹: volumes and immersive spaces on Android XR
   and visionOS render through the OS's scene graph (SceneCore, RealityKit)
   from the `DVScene` document, and do not depend on Flutter GPU.
3. Platform matrix footnote ³: add that native spaces on visionOS need a
   Flutter engine and Dart AOT for `xros`, which Flutter does not provide.
   Generated FFI alone is not enough.
4. Diagnostics: `DV-XR-008` for features unavailable in visionOS
   compatibility mode.
5. The Embedder Fork Rule table gains `dartvel_visionos` only if section 4
   is approved.

## Drafting order

1. **Section 1 (`android-xr`, phase 1).** Everything is verifiable on this
   server except running it. Add the `docs/build-targets.md` row with the AAB
   inspected.
2. **Section 2's host-independent half.** The `DV-XR-008` preflight in
   `dartvel analyze`, the target registration, the doctor checks and the
   `isiOSAppOnVision` FFI check with tests. The macOS half waits for a Mac or
   for Actions.
3. **Section 3 spike.** jnigen over SceneCore rc01 on this server: does
   `Session.create` generate usable async Dart? Stop and report if not.
4. **Section 3, on a device.** Volume from a `DVScene`, then immersive, then
   the second panel. Nothing is labelled beyond `Experimental` without a
   device row in `docs/build-targets.md`.
5. **Spec amendments** 1–4 above, as each lands.
6. **Section 4: a decision, not a step.** Revisit when #128313 or
   dart-lang/native#961 moves, or when a user needs volumes on Vision Pro
   badly enough to fund the engine port.

## Open questions

- Does `xcrun simctl install` accept an iOS simulator build on a visionOS
  simulator runtime, or does the dev loop have to go through `xcodebuild`
  with the "Designed for iPad" destination?
- Should `DVPlatform` report `visionos` or `ios` in compatibility mode? The
  application is an iOS app with iOS APIs. Reporting `visionos` invites code
  to expect visionOS features it does not have. The device type is the more
  useful signal, and there is no existing `DVDeviceType` for a headset.
- What does a declared kiosk mean in an `android-xr` build? The spec says
  kiosk on XR is device scope under Android Enterprise. Does Galaxy XR support
  lock-task mode at all? Not found in this research.
- `dartvel.xr.enabled` versus "usage decides". The spec has both. If usage
  decides what is linked, is `enabled: false` a way to refuse XR even when a
  volume is opened (so it degrades), or is the key redundant?
- Does Quick Look present a USDZ as a 3D volume from a *compatible* iPad app
  on Vision Pro? If it does, a model viewer could get a real volume on
  visionOS without an engine port, as a narrow exception. It would need
  glTF-to-USDZ conversion at build time. Not researched here; worth an hour
  on a device.
- Should `android-xr` join `--platform all` once section 3 makes its AAB
  genuinely different from `android`'s?
