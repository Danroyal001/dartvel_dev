# visionOS, Android XR and Meta Horizon OS as Build Targets — Proposal

**Status: Draft 2026-09-25, not yet reviewed.** On approval this amends the
Build targets, Configuration and Platform matrix subsections of *XR — Spatial
Presentation* in NEW_SPEC.md, and, for Horizon OS, the Purchases and
Notifications sections (see Spec amendments). The section keeps
`Stability: Draft`. The `absent` text in `docs/spec-status.json` changes only
as each phase's files and evidence land in `docs/build-targets.md`.

NEW_SPEC.md already designs the Dart side of XR, and much of it is built:
`DVWindowKind.volume` and `.immersive`, `window.spatial`, the session, anchors,
comfort, consent, `DVXRBindingDevice` over `DVNativeBridge`, and
`DV.Test.fakeXR`. None of it reaches a headset. `dartvel build` and `dartvel
doctor --target` accept none of `visionos`, `android-xr` and `horizon`, no
native XR binding is registered on any target, and `capability.spatial` is null
everywhere outside tests. This proposal says what it takes to change that,
target by target, and where the platforms stop us.

The short version:

| | Runs today as | Spatial surfaces need | Blocked on |
|---|---|---|---|
| **Android XR** | an ordinary Android app in a 2D panel, unmodified | jnigen bindings over Jetpack SceneCore (Views path, no Compose) | a device or a non-Linux emulator to verify on; SceneCore is `1.0.0-rc01` and still breaking |
| **Meta Horizon OS** (Quest, and Meta VR Glasses from spring 2027) | an Android app in a 2D panel, but only on the Horizon Store once the manifest, SDK levels, ABI and permissions follow Meta's rules and nothing calls Google Play services | jnigen bindings over the Meta Spatial SDK, in a second, immersive activity | a device or a non-Linux simulator to verify on; the Spatial SDK is `0.14.0`; whether Look and Pinch can target Flutter-drawn controls is unknown |
| **visionOS** | the iOS app, as a "Designed for iPad" compatible app in one window | a native visionOS app, which needs a Flutter engine and Dart AOT built for `xros` | engine and Dart runtime work that Flutter has said it will not do |

Android XR can reach phase 2 with work that is all Dartvel's own. So can
Horizon OS, but it is not Android XR under another name: it has no Google Play
services, its own store with its own manifest rules, and none of Jetpack XR's
spatial layer. The two share the Android toolchain, Dartvel's DVScene mapping
and, underneath, OpenXR, and little in between. visionOS cannot get past
phase 1 without a Flutter engine port. The proposal treats that asymmetry as
the main finding, not something to smooth over.

How the sections map to phases:

| Phase | Android XR | Meta Horizon OS | visionOS |
|---|---|---|---|
| 1: the existing app, well, in a window or panel | section 1 | section 2 | section 3 |
| 2: spatial surfaces on `DVWindowKind.volume`/`.immersive` and `DVScene` | section 4 | section 5 | none possible without phase 3 |
| 3: engine work | none identified | none required; OpenXR rendering through Flutter GPU is an option, not proposed (section 5) | section 6 |

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

### Meta Horizon OS

- **Devices (official).** Meta's comparison page, updated 2026-09-18, names two
  product lines on Horizon OS: Meta Quest (Quest 3 and Quest 3S) and Meta VR
  Glasses. It says boundary, passthrough and hand tracking are available on
  every device
  ([Compare devices](https://developers.meta.com/horizon/resources/compare-devices/)).
  Quest 3S is the newest Quest, "the newest member of the Quest 3 family"
  ([Devices](https://developers.meta.com/horizon/discover/devices/)). Meta's
  Connect post of 2026-09-23 announces no new Quest. Its new device is Meta VR
  Glasses: about 100 g, tethered to a compute puck, eyes and hands as input,
  "available in Spring 2027 for $1,299.99 USD"
  ([Meta, 2026-09-23](https://www.meta.com/blog/meta-connect-2026-everything-we-announced/)).
  Quest 2 and Quest Pro have left the comparison page but are still canonical
  `com.oculus.supportedDevices` values (see Manifest). A Meta community-forum
  announcement is reported to give both feature updates until December 2026
  and security updates until the end of 2027
  ([Meta Community Forums](https://communityforums.atmeta.com/blog/AnnouncementsBlog/updates-to-your-meta-quest-experience-in-2026/1369435);
  the page refused a scripted fetch, so **unverified**). The original Quest
  has no `supportedDevices` value. It appears only as the last fallback of
  compatibility mode.

  | Device | Chipset | Passthrough | Tracking | `supportedDevices` |
  |---|---|---|---|---|
  | Quest 2 | Snapdragon XR2 (**unverified**, [Wikipedia](https://en.wikipedia.org/wiki/Meta_Quest_2), community) | greyscale | head, hands | `quest2` |
  | Quest Pro | Snapdragon XR2+ | colour | head, hands, eyes | `questpro` |
  | Quest 3 | Snapdragon XR2 Gen 2, 8 GB | colour, 4 MP, depth sensor | head, hands | `quest3` |
  | Quest 3S | Snapdragon XR2 Gen 2, 8 GB | colour, 4 MP, no depth sensor | head, hands | `quest3s` |
  | Meta VR Glasses (spring 2027) | Snapdragon XR2 Gen 3, 12 GB | colour, autofocus, depth sensing | head, hands, eyes; controllers sold separately | none (see Runtime detection) |

  Quest 3, 3S and Meta VR Glasses rows:
  [Compare devices](https://developers.meta.com/horizon/resources/compare-devices/).
  Quest Pro's chipset, colour passthrough and eye tracking:
  [Meta, 2022-10-11](https://www.meta.com/blog/meta-quest-pro-price-release-date-specs/).
  Quest 2's greyscale passthrough:
  [Passthrough design](https://developers.meta.com/horizon/design/mr-design-passthrough/).
  The Depth API runs on Quest 3 and 3S only; "earlier headsets are not
  supported"
  ([Depth API](https://developers.meta.com/horizon/documentation/unity/unity-depthapi-overview/)).
  **Android version (official).** "All Horizon OS releases since HzOS version
  76 on April 2025 have used Android 14 (SdkVersion 34). Previous Horizon OS
  versions used Android 12 (SdkVersion 32)"
  ([Application manifests, updated 2026-08-31](https://developers.meta.com/horizon/resources/publish-mobile-manifest/)).
  The comparison page lists Android 14 for Quest 3, 3S and the Glasses. That
  Quest 2 and Pro are on Android 14 is an inference from their receiving
  current releases, not something Meta states for them.
- **Unmodified 2D apps (official).** Horizon OS "is built on the Android Open
  Source Project", and it shows 2D apps "in resizable windows within a VR
  environment" with taps and swipes mapped to controllers and hands
  ([Get started with Android apps, updated 2026-09-04](https://developers.meta.com/horizon/documentation/android-apps/horizon-os-apps)).
  For Flutter specifically, [flutter/flutter#103234](https://github.com/flutter/flutter/issues/103234)
  (2022, Quest 2) reports that an APK installed with `adb install` ran and took
  controller input, while `flutter run` hung on a loading screen.
  [PR #104135](https://github.com/flutter/flutter/pull/104135), merged
  2022-05-21, fixed that by launching with an explicit action and category.
  Nothing since says either broke, and nothing says anyone re-tested them on a
  current release. Dartvel has not run a build on a Quest.
- **Manifest (official).** From
  [Application manifests, updated 2026-08-31](https://developers.meta.com/horizon/resources/publish-mobile-manifest/)
  and
  [Make your existing app compatible, updated 2026-09-14](https://developers.meta.com/horizon/documentation/android-apps/making-apps-compatible-overview):
  - `<meta-data android:name="com.oculus.supportedDevices"
    android:value="quest2|questpro|quest3|quest3s"/>` on `application`
  - a panel (2D) app omits `android.hardware.vr.headtracking` or declares it
    `required="false"`; an immersive app declares it `required="true"`
  - `com.oculus.intent.category.VR` on the launcher intent filter is for
    OpenXR apps only; a panel app keeps plain `MAIN`/`LAUNCHER`
  - `android:excludeFromRecents="true"` on the launching activity,
    `installLocation` `auto`, no `android:debuggable` in release, and a label
    unique on the platform
  - `<layout android:defaultWidth="1024dp" android:defaultHeight="640dp"/>`
    for the starting window size, optional minimums
  - optionally `metavr:uses-metavr-sdk` with Meta's own SDK version numbers,
    independent of Android API levels
    ([SDK versioning](https://developers.meta.com/horizon/documentation/android-apps/metavr-os-sdk-versioning))
- **SDK levels (official).** For Quest 2, Pro and the Quest 3 family Meta
  recommends `minSdkVersion` 32, `targetSdkVersion` 34, and allows
  `minSdkVersion` 29 to 34 and `targetSdkVersion` 32 to 36 for 2D apps
  ([Application manifests](https://developers.meta.com/horizon/resources/publish-mobile-manifest/)).
  "Apps created since March 1, 2026, must set their targetSdkVersion to 34",
  enforced at binary upload, while existing apps may stay lower
  ([Meta, 2025-11-24, updated 2026-02-06](https://developers.meta.com/horizon/blog/meta-quest-apps-android-14-march-1/)).
  Whether a new app may upload `targetSdkVersion` 36, which the table allows
  for 2D and the announcement does not mention, is **unverified**. For
  comparison, Flutter 3.47.5's defaults are `minSdkVersion` 24,
  `targetSdkVersion` 36 and `compileSdkVersion` 36 (`FlutterExtension.kt` in
  the SDK on this server). The minimum is below Meta's range.
- **Packaging (official).** "All Meta Quest applications must be submitted as
  64-bit binaries", required since 2019-12-19
  ([VRC.Quest.Packaging.6](https://developers.meta.com/horizon/resources/vrc-quest-packaging-6/)).
  An APK must be under 1 GB, with expansion files up to 4 GB each
  ([VRC.Quest.Packaging.5](https://developers.meta.com/horizon/resources/vrc-quest-packaging-5/)).
  Meta's upload documentation speaks of APKs throughout. Nothing found says
  whether the Horizon Store takes an AAB (**unverified**).
- **Permissions (official).** A build that requests a prohibited permission
  fails upload automatically. The list includes `READ_CONTACTS`,
  `ACCESS_BACKGROUND_LOCATION`, `CALL_PHONE`, `QUERY_ALL_PACKAGES`,
  `SYSTEM_ALERT_WINDOW`, `BIND_APPWIDGET` and `BIND_DEVICE_ADMIN`, and "may
  change unexpectedly"
  ([Prohibited permissions, updated 2025-04-30](https://developers.meta.com/horizon/resources/permissions-prohibited/)).
  `CAMERA`, `RECORD_AUDIO`, `POST_NOTIFICATIONS`, `BLUETOOTH_*` and
  `READ_MEDIA_*` need a stated use case at review
  ([Review-requiring permissions, updated 2025-11-26](https://developers.meta.com/horizon/resources/permissions-review-required/)).
  Precise location and telephony are not supported
  ([Submitting your app](https://developers.meta.com/horizon/resources/publish-submit)).
- **No Google Play services (official).** "Horizon OS does not include Google
  Mobile Services, so calls into GMS APIs fail." Meta's replacements, from
  [Make your existing app compatible](https://developers.meta.com/horizon/documentation/android-apps/making-apps-compatible-overview):

  | Google | Horizon OS replacement | Notes |
  |---|---|---|
  | Firebase Cloud Messaging | Platform SDK user notifications | created and reviewed in the Developer Dashboard. Neither kind is pushed into the headset; event-based ones can push to the Meta Horizon phone app ([User notifications, updated 2025-11-04](https://developers.meta.com/horizon/documentation/android-apps/ps-user-notifications/)) |
  | Play Billing (`billingclient.api`) | Horizon Billing Compatibility SDK | the Play Billing Library 7.0 API under `com.meta.horizon.billingclient.api`; consumables, durables, subscriptions ([Billing Compatibility SDK, updated 2026-01-05](https://developers.meta.com/horizon/documentation/android-apps/horizon-billing-compatibility-sdk/)) |
  | Play Integrity, App Check | entitlement check | within 10 seconds of launch, works offline, the app decides what a failure does; a server-to-server `verify_entitlement` endpoint exists ([Entitlement check, updated 2026-08-14](https://developers.meta.com/horizon/documentation/android-apps/ps-entitlement-check)) |
  | Google sign-in (`gms.auth`) | AppAuth, OAuth with a private-use URI scheme redirect | streaming and media apps must offer device-code sign-in (RFC 8628) or similar ([AOSP features, updated 2026-09-08](https://developers.meta.com/horizon/documentation/android-apps/features-overview)) |
  | `gms.location` | `LocationManager` | |
  | Firebase without GMS | works | "Horizon OS supports all Firebase dependencies that do not require Google Mobile Services" |

- **Runtime detection and compatibility mode (official).**
  `HorizonOsDetector.isOnHorizonOs(context)` in `com.meta.metavrx.util:util:1.0.0`
  is Meta's check
  ([Make your existing app compatible](https://developers.meta.com/horizon/documentation/android-apps/making-apps-compatible-overview)).
  When `supportedDevices` does not list the physical headset, Horizon OS runs
  the app in compatibility mode and selected APIs report an older model, so
  Meta says not to infer anything from `Build.MODEL`. "Meta VR Glasses are not
  currently a supported public value for com.oculus.supportedDevices"; a build
  reaches them through Store targeting ("Future devices"), and in compatibility
  mode
  ([Compatibility mode, updated 2026-09-08](https://developers.meta.com/horizon/documentation/native/android/os-compatibility-mode/)).
- **Input on panels (official).** Controllers, hands, mouse and stylus send
  standard Android motion events on hover and on select. The B and Y buttons
  are Back, "There is no hand tracking gesture for back navigation", and a
  joystick scrolls Views through `AXIS_VSCROLL`
  ([AOSP features](https://developers.meta.com/horizon/documentation/android-apps/features-overview)).
  On devices that ship without controllers, which means Meta VR Glasses, the
  default is Look and Pinch. The system infers targets "from your app's view
  hierarchy and accessibility information", draws the hover highlight itself,
  and sends a touch event on pinch. Apps get no gaze hover events. To launch on
  those devices an app must not request eye-tracking permissions, needs
  touch targets of at least 48 dp and "proper UI understanding", and must not
  depend on hover. The minimum framework versions listed are Jetpack Compose
  1.10.0 and React Native 0.85. Flutter is not named
  ([Look and Pinch for 2D apps, updated 2026-09-04](https://developers.meta.com/horizon/documentation/android-apps/gaze-and-hands)).
- **Windows (official).** Several activities can run in separate panels,
  started with `FLAG_ACTIVITY_LAUNCH_ADJACENT`, `FLAG_ACTIVITY_NEW_TASK` and
  `FLAG_ACTIVITY_MULTIPLE_TASK`, with no extra SDK
  ([AOSP features](https://developers.meta.com/horizon/documentation/android-apps/features-overview)).
  The Meta VR Layout SDK places further spatial windows around the main panel,
  for Compose and React Native
  ([What's new in Meta VR Glasses, updated 2026-09-01](https://developers.meta.com/horizon/documentation/android-apps/whats-new-in-glasses)).
  No Meta page found says whether Horizon OS persists a panel's placement
  across reboot, which the spec asserts (**unverified**).
- **Meta Spatial SDK (official).** A Kotlin, entity-component-system SDK with
  glTF, physically based rendering, image-based lighting, physics,
  passthrough, scene understanding, anchors and panels "built using your
  preferred 2D UI framework"
  ([Spatial SDK overview](https://developers.meta.com/horizon/documentation/spatial-sdk/spatial-sdk-explainer/)).
  Maven Central has `com.meta.spatial:meta-spatial-sdk` `0.14.0`, published
  2026-09-11, the 25th release counting `0.5.0` of 2024-09-25
  ([maven-metadata.xml](https://repo1.maven.org/maven2/com/meta/spatial/meta-spatial-sdk/maven-metadata.xml)).
  Its AAR, inspected here, ships native libraries for `arm64-v8a` only and its
  own `libopenxr_loader.so`. A hybrid app keeps its 2D activity
  (`com.oculus.intent.category.2D`) and adds an immersive one
  (`com.oculus.intent.category.VR`), and must declare `uses-metavr-sdk`
  `minSdkVersion` 69 or later
  ([Hybrid apps, updated 2026-09-22](https://developers.meta.com/horizon/documentation/spatial-sdk/hybrid-apps-overview/)).
  A known issue: calling `finish()` on an activity with panels can crash in
  `libMetaSpatialSDK.so`
  ([Known issues, updated 2026-04-02](https://developers.meta.com/horizon/documentation/spatial-sdk/spatial-sdk-known-issues/)).
- **OpenXR (official).** Meta Quest headsets are OpenXR 1.0 adopters and use
  the Khronos Android loader, 1.0.34 or later
  ([OpenXR support, updated 2025-01-23](https://developers.meta.com/horizon/documentation/native/android/mobile-openxr/)).
  Passthrough is `XR_FB_passthrough`: the system composites the camera view
  into a layer, and "An app cannot access images or videos of a user's
  physical environment". It needs `uses-feature com.oculus.feature.PASSTHROUGH`
  ([Implement passthrough](https://developers.meta.com/horizon/documentation/native/android/mobile-passthrough/)).
  Raw camera frames are a separate API on Quest 3 and 3S from v74, behind
  `HEADSET_CAMERA` or `CAMERA`
  ([AOSP features](https://developers.meta.com/horizon/documentation/android-apps/features-overview)).
  Anchors are `XR_FB_spatial_entity`, with `XR_META_spatial_entity_persistence`
  for keeping them and `XR_META_spatial_entity_sharing` for sharing them
  ([Spatial anchors API, updated 2025-05-21](https://developers.meta.com/horizon/documentation/native/android/openxr-spatial-anchors-api-ref/)).
  Meta separates app-owned spatial anchors from system-owned scene anchors
  (walls, furniture), and stores anchors "between local device storage and
  storage on Meta Servers"
  ([Spatial anchors overview](https://developers.meta.com/horizon/documentation/native/android/openxr-spatial-anchors-overview/)).
- **Jetpack XR on Quest, and the reverse.** "You can only create a session on
  either an Android XR device, or on a supported ARCore device"
  ([Add a session, updated 2026-09-22](https://developer.android.com/develop/xr/jetpack-xr-sdk/add-session)).
  No Meta device is on Google's
  [ARCore device list](https://developers.google.com/ar/devices). So
  SceneCore, Compose for XR and ARCore for Jetpack XR have nothing to run on
  under Horizon OS. The 2D part of a Jetpack XR app is still an Android app,
  and would run in a panel under the rules above. A community post of
  2025-01-12 reports a Jetpack XR template app launching on a Quest 3S, with
  nothing spatial tested
  ([kevincarlson.codes](https://kevincarlson.codes/trying-android-xr-apps-on-meta-quest/),
  community, **unverified**). Meta documents the Spatial SDK only for Horizon
  OS. Nothing found says it runs on Android XR, so assume it does not
  (**unverified**).
- **OpenXR as a shared layer.** Android XR supports OpenXR 1.1 and lists its
  extensions: `XR_EXT_spatial_entity`, `XR_EXT_spatial_anchor`,
  `XR_EXT_spatial_persistence`, `XR_EXT_hand_tracking`, many `XR_ANDROID_*`,
  and some Meta ones (`XR_FB_foveation`, `XR_FB_space_warp`,
  `XR_FB_hand_tracking_aim`). It does not list `XR_FB_passthrough` or
  `XR_FB_spatial_entity`
  ([Android XR OpenXR extensions, updated 2026-08-05](https://developer.android.com/develop/xr/openxr/extensions)).
  Khronos published the cross-vendor `XR_EXT_spatial_*` family in 2025 with
  Meta's working-group chair quoted in support
  ([Khronos](https://www.khronos.org/blog/openxr-spatial-entities-extensions-released-for-developer-feedback)),
  but no Meta page found says the Quest runtime implements them
  (**unverified**). Today, then, a session, swapchains, action-based input and
  hand joints can be one OpenXR binding for both platforms. Passthrough and
  anchors cannot.
- **Testing (official).** Meta Spatial Simulator runs a 2D app as a panel on
  the desktop. It needs macOS on Apple silicon or 64-bit Windows 10 or later
  with hardware virtualization, a Vulkan GPU, and the Android SDK emulator
  package. It is installed from the Android Studio plugin or with
  `metavr tools install spatialsim`, drives an app with `metavr app install`
  and `metavr capture screenshot`, has no Google Play services, and expects
  API 34
  ([Test on Meta Spatial Simulator, updated 2026-09-04](https://developers.meta.com/horizon/documentation/android-apps/spatial-sim-overview)).
  Linux is not listed. Meta XR Simulator, for OpenXR apps, is an OpenXR runtime
  with no OS image. It runs on Windows 10 or later and on macOS on ARM, has
  device profiles for Quest 2, Pro, 3, 3S and Meta VR Glasses, and does not
  accept OpenGL ES
  ([XR Simulator overview, updated 2026-09-04](https://developers.meta.com/horizon/documentation/unity/xrsim-intro/);
  [getting started](https://developers.meta.com/horizon/documentation/unity/xrsim-getting-started/)).
  The `metavr` CLI itself installs on Linux
  ([Install Meta VR CLI](https://developers.meta.com/horizon/essentials/metavr-install/)),
  but neither simulator it drives does. On a device, developer mode is turned
  on from the Meta Horizon phone app by a verified developer in a team.
  Then `adb install` works, and the app appears under Library, Unknown Sources
  ([Test on your device, updated 2026-08-24](https://developers.meta.com/horizon/documentation/android-apps/enable-developer-mode)).
- **Flutter (official).**
  [flutter/flutter#144392](https://github.com/flutter/flutter/issues/144392),
  "Flutter as a platform for building cross VR experiences", was closed as
  not planned in 2024. [#192059](https://github.com/flutter/flutter/issues/192059),
  "Flutter GPU: external render targets for OpenXR", opened 2026-08-31 by a
  community developer, is open and labelled `c: proposal` and
  `team-fluttergpu`. It links forks of the engine and of `flutter_scene` that
  render Flutter Scene straight into OpenXR eye images on a Quest 3. The author
  reports roughly 52 to 54 fps rising to about 70 fps, "not a controlled
  Canvas-only benchmark". The Flutter team has routed it for evaluation and
  committed to nothing.

### Horizon OS and Android XR side by side

| | Android XR | Meta Horizon OS |
|---|---|---|
| Base | Android with Google Play services | AOSP, no Google Mobile Services |
| Store | Google Play, with an XR release track | Meta Horizon Store, reviewed against Meta's VRCs |
| An unmodified phone app | reaches XR automatically | needs `supportedDevices`, SDK levels in range, 64-bit, allowed permissions and no GMS before the Store takes it |
| Target API | 34 or higher | 34 for apps created since 2026-03-01; the OS is Android 14 |
| Artifact | AAB | APK (AAB not found) |
| 2D panel input | pinch as tap, system gaze hover, controllers | controllers and hands on Quest; Look and Pinch on Meta VR Glasses |
| Spatial SDK | Jetpack SceneCore `1.0.0-rc01` | Meta Spatial SDK `0.14.0` |
| 3D content | Full Space, one app at a time | an immersive activity, one app at a time |
| OpenXR | 1.1; `XR_EXT_spatial_*` and `XR_ANDROID_*` | 1.0 adopter; `XR_FB_*` and `XR_META_*` for passthrough and anchors |
| Emulator or simulator on Linux | no | no |

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
  and `horizon` fit the same slot.
- **Declared permissions and per-store products.** Android permissions come
  from `dartvel.android.permissions` (`dvAndroidRequestedPermissions` in
  `android_capture_bridge.dart`), never inferred, so a build can check them
  against Meta's lists before Gradle runs. `DVBillable.digital` already takes
  one product identifier per store (`appStore:`, `play:`), and a store build
  that lacks its identifier already refuses. A Horizon store is one more
  field, not a new mechanism.
- **Generated Android bindings that already name Horizon's window flags.**
  The committed jnigen output includes `Intent.FLAG_ACTIVITY_LAUNCH_ADJACENT`
  (`packages/dartvel_flutter/lib/src/platform/android/generated/android/content/Intent.dart`).
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

## 2. `dartvel build horizon`: the existing app, on the Horizon Store

**Problem.** A Dartvel Android app probably already runs on a Quest when it is
sideloaded: Horizon OS is AOSP, and the only Flutter report says an installed
APK ran and took controller input. It cannot get onto the Horizon Store as it
is. Its manifest names no Quest model, Flutter's default `minSdkVersion` of 24
is below Meta's range, a default APK carries 32-bit ARM and x86 code a Quest does
not need, and whatever the project declared in `dartvel.android.permissions` may
include something Meta refuses at upload. Several things Dartvel wires up
assume Google Play services, which Horizon OS does not have. Push through
`FirebasePushProvider` needs an FCM token no Quest can issue, and
`DV.Purchases` goes through Play Billing. Nothing tells the developer any of
this before the upload fails or a feature silently does nothing.

**Proposal.** `horizon` joins `flutterBuildPlatforms` beside `fireos` and
`android-xr`. It is built with `flutter build apk --release
--target-platform android-arm64`.

- **The name.** `horizon`, as the spec already writes it, and not `quest`. The
  other targets are named for the operating system (`android-xr`, `visionos`,
  `webos`, `tizen`), and from spring 2027 the same build reaches Meta VR
  Glasses, which are not a Quest. `quest` is accepted as an alias, the way
  `tpk` is for `tizen`, because it is the word people search for; `doctor`
  and every message print `horizon`.
- **Same app, stated platform.** The build passes
  `--dart-define=DARTVEL_PLATFORM=horizon`, for the reason `android-xr` does.
  A plain `android` build that is sideloaded onto a Quest is not detected in
  phase 1. Meta's detector lives in its own Maven library, and adding it to
  every Android app to serve the few that are sideloaded is the wrong trade
  (see Open questions).
- **Manifest.** A writer, `horizon_manifest.dart`, with the same begin and end
  markers as the others, writes what the Store checks:
  `com.oculus.supportedDevices` from `dartvel.xr.horizon.supportedDevices`,
  `android.hardware.vr.headtracking` with `required="false"`,
  `excludeFromRecents="true"` and a `<layout>` default size on the launching
  activity, and `installLocation="auto"`. It does **not** add
  `com.oculus.intent.category.VR`, which is for immersive apps and would be
  wrong on a panel. Meta VR Glasses cannot be listed, so the command's final
  line says to tick "Future devices" in Store targeting, as the `visionos`
  build does for Apple's availability switch.
- **SDK levels and ABI.** `minSdkVersion` 32 (Meta's recommendation; Flutter's
  24 is below the allowed 29), `targetSdkVersion` 34 (the rule for apps
  created since 2026-03-01, and the Android version every current Horizon OS
  release runs), `compileSdkVersion` left at Flutter's 36, which Meta allows as
  long as it is not below the target. `arm64-v8a` only, which satisfies
  VRC.Quest.Packaging.6 and drops 32-bit and x86 code the Store has no use
  for.
- **Store preflight.** Before Gradle starts, the build reports with codes,
  reading the project rather than guessing:
  - a permission on Meta's prohibited list: a build error, because the upload
    fails anyway
  - a permission that needs review (`CAMERA`, `RECORD_AUDIO`,
    `POST_NOTIFICATIONS`, `BLUETOOTH_*`, `READ_MEDIA_*`): a warning carrying
    Meta's usage note
  - a declared kiosk, whose device-admin receiver is guarded by
    `BIND_DEVICE_ADMIN` (see Open questions)
  - home widgets, which Meta's AOSP features page does not mention, so
    whether Horizon OS shows them anywhere is unknown (see Open questions)
  - `DVBillable.digital` without a `horizon:` product identifier, which is the
    existing "store target without an identifier" refusal with one more store
  - a push provider configured as FCM only, reported as absent on Horizon OS
  - an APK over 1 GB (VRC.Quest.Packaging.5)

  Meta says its lists "may change unexpectedly", so they live in one data file
  with the date they were read, and `doctor --target horizon` prints that date.
- **What replaces Google Play services.** Each is reached through jnigen,
  linked only into `horizon` builds, and behind the surface an application
  already uses:
  - **Purchases.** `DVStore.horizon`, bound to the Horizon Billing
    Compatibility SDK. That SDK is the Play Billing Library 7.0 API in another
    package, so the binding is close to the Play one. Server verification uses
    Meta's server-to-server APIs, with credentials in Secrets like the other
    stores'.
  - **Entitlement.** For a paid app, the generated startup runs Meta's
    entitlement check within the 10 seconds Meta asks for. A failure is typed
    and the application's policy decides what it does, since Meta leaves that
    to the app.
  - **Push.** None. Meta's user notifications are campaigns reviewed in the
    Developer Dashboard. They are not pushed into the headset, and event-based
    ones push to the Meta Horizon phone app, not to the device. That is not a
    push provider, and dressing it up as one would lie about delivery.
    `DV.Notifications` reports push as unavailable on `horizon`; in-app and mail
    carry on.
  - **Sign-in.** Provider sign-in goes through the browser redirect flow with a
    private-use URI scheme, which is what Meta documents. Device-code sign-in
    is required only for streaming and media apps, and is noted in the
    preflight when the project declares one.
- **Input.** Controller rays and hand pinches arrive as ordinary Android
  motion events, so `.onTap()` and scrolling work without new code. Hands have
  no Back gesture, so the page shell shows its own back control on `horizon`
  where a route can go back, without the application adding a widget. Whether
  a joystick's `AXIS_VSCROLL` scrolls a Flutter list the way it scrolls a View
  is not known, and is the first thing to try on a device.
- **Look and Pinch.** Meta VR Glasses target by gaze using the app's "view
  hierarchy and accessibility information". Flutter publishes its semantics
  tree to Android accessibility through its `AccessibilityBridge`
  ([javadoc](https://api.flutter.dev/javadoc/io/flutter/view/AccessibilityBridge.html)),
  which is what TalkBack reads, so the system *may* find Flutter's buttons.
  Meta names only Compose and React Native, and nobody has tested Flutter.
  If it does not work, Flutter-drawn controls get no gaze highlight or
  snapping on the Glasses. That is the gap flutter/flutter#129640 describes on
  visionOS, and there the fix is Flutter's, not Dartvel's. The Spatial
  Simulator reproduces Look and Pinch, so this can be answered before any
  Glasses ship, on a Mac or a Windows machine.
- **Windows.** `DV.Window.open(route)` on `horizon` starts a second activity
  with the three flags Meta documents, which Meta says is all a second panel
  needs. It is the one multi-window case on Android with a documented answer,
  and it still has to be tried on a device.
- **Artifact.** `build/app/outputs/flutter-apk/app-release.apk`, signed with
  the project's release key. Uploading it is the developer's step.
- **Development.** `adb install` onto a Quest in developer mode, then Library,
  Unknown Sources. `flutter run` should also work since PR #104135, but that
  has not been checked on a current Horizon OS. On macOS or Windows,
  `dartvel build horizon --simulator` builds a debug APK and installs it with
  `metavr app install` onto a running Meta Spatial Simulator.
- **Doctor.** `horizon` joins `doctorTargets`. It checks what the Android build
  needs, reports `metavr` and the simulator when they are on PATH, and on Linux
  says plainly that neither simulator runs there, naming the two hosts that
  do. It never installs Meta's tools: the simulator needs a Meta account and a
  sign-in, which an unattended install cannot supply.

**Embedder Fork Rule.** No fork. This is plain `flutter build`, like `fireos`
and `android-xr`.

**What it cannot do.** It does not open volumes or immersive spaces.
`capability.spatial` reports `panels: true`, `volumes: false`,
`immersive: false`, and `passthrough: false` for the application even though
the home environment shows passthrough, because that belongs to the OS.

**Effort.** Three to five days, sharing target registration, the define and
the marker writer with section 1, plus the preflight lists, the
`DVStore.horizon` binding, and tests that assert on `aapt2 dump badging` and
the merged manifest from a real APK.

## 3. `dartvel build visionos` — the iOS app, honestly labelled

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
controls. This phase is the ceiling on visionOS until section 6.

**Effort.** Three to five days for the CLI, the preflight, the FFI check and
tests. Verification needs a Mac (see Verification).

## 4. Android XR spatial surfaces — `volume` and `immersive` through SceneCore

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

## 5. Horizon OS spatial surfaces: `volume` and `immersive` through the Meta Spatial SDK

**Problem.** Section 4's bindings cannot serve Horizon OS. A Jetpack XR
`Session` is created only on an Android XR device or an ARCore device, and a
Quest is neither. Horizon OS has two native routes of its own: the Meta
Spatial SDK, which is Kotlin, and OpenXR, which draws nothing itself.

**The options.**

| | Meta Spatial SDK | OpenXR directly |
|---|---|---|
| Binding | jnigen, as section 4 | ffigen over `openxr.h` and the Khronos loader |
| Who renders the `DVScene` | the SDK (glTF, PBR, image-based lighting) | Flutter, into swapchain images |
| What Flutter has to gain | nothing | rendering into images another system owns: [#192059](https://github.com/flutter/flutter/issues/192059), an open proposal with a fork-based prototype |
| Also serves Android XR | no | session, swapchains, input and hand joints, yes; passthrough and anchors, no (different extensions) |
| Maturity | `0.14.0`, 25 releases counting `0.5.0` of 2024-09-25 | OpenXR 1.0 on Quest; the Flutter side does not exist upstream |

**Proposal.** The Spatial SDK, for the same reason section 4 picks SceneCore:
**the DVScene document is the contract, and the OS is the renderer.**

- **One mapper, two backends.** The DVScene-to-entity mapping from section 4
  is written against a small interface of Dart calls (create entity, set
  transform, load glTF, attach anchor). SceneCore implements it on Android XR,
  and the Spatial SDK on Horizon OS. Transforms come from `DVSceneGraph` as
  before. Whether the Spatial SDK's axes and units match SceneCore's
  right-handed, Y-up metres has to be read from its API reference before the
  mapper is shared; this research did not confirm it.
- **Bindings.** A third jnigen config, `tool/horizon_xr_bindings.jnigen.yaml`,
  generates Dart for the Spatial SDK's activity, scene, entity, mesh, panel,
  passthrough and anchor classes against a pinned `meta-spatial-sdk` AAR. It
  runs on the same runner and its output is committed. It goes into the Gradle
  build only when `xr:` is linked, as on Android XR.
- **Activities.** Horizon OS separates 2D and immersive work by activity. The
  `FlutterActivity` stays the panel activity (`com.oculus.intent.category.2D`).
  A generated immersive activity (`com.oculus.intent.category.VR`) hosts the
  Spatial SDK scene, and the manifest gains `uses-metavr-sdk`
  `minSdkVersion` 69, which Meta requires for hybrid apps. Moving between them
  follows Meta's hybrid-app intents. Given the known `finish()` crash, the
  generated activity destroys its panels itself before it ends.
- **Volume.** No Meta page found offers a third-party app a bounded 3D volume
  beside other apps in the home environment. So `open(route, kind: .volume)`
  opens the immersive activity with passthrough and places the scene at
  `DVVolumeOptions.size` in front of the user. That is the same trade Android
  XR makes, where a volume needs Full Space. Other apps' panels hide, which the
  spec already reports once.
- **Immersive.** `open(route, kind: .immersive)` opens the same activity with
  passthrough or a full environment, and keeps the exclusivity and consent
  flow in `spatial_session.dart`. Passthrough is greyscale on Quest 2 and
  colour elsewhere. `capability.spatial.passthrough` is true on all of them,
  and a colour flag is an open question.
- **Panels in space.** A Flutter panel beside the scene would be a Spatial SDK
  panel hosting an activity on a `FlutterEngineGroup` engine. Meta says panels
  take "your preferred 2D UI framework". That a `FlutterView` renders in one is
  untested, as it is for SceneCore, and it comes last in the phase.
- **Input.** The Spatial SDK's input events go through the session's existing
  ray picking to `.onTap()`, `.onGrab()` and `.onRelease()`. Controllers and
  hands are both reported in `capability.spatial.input`, and gaze on the
  Glasses stays a selection, never a position.
- **Anchors**, against the spec's closed set:

  | `DVAnchor` | Horizon OS | Android XR | Proposal |
  |---|---|---|---|
  | `plane` | system-owned scene anchors (walls, floor, furniture), read with the user's permission | plane tracking | both backends; on Horizon the anchor is the nearest scene plane of the requested orientation |
  | `image` | no image or marker tracking found for the Spatial SDK | image and QR trackables (`XR_ANDROID_trackables_*`) | Horizon degrades to `DV-XR-002` until Meta documents one (**unverified** either way) |
  | `hand` | hand tracking on every device | hand tracking | both |
  | `world` | app-owned spatial anchors, persisted by UUID through `XR_META_spatial_entity_persistence` | anchor persistence (`XR_ANDROID_device_anchor_persistence`) | the UUID goes into the shared window store under `xr.anchors.*` as the spec says. A failed re-localization is `DV-XR-003` on both |
  | `shared` | Shared Spatial Anchors through Meta's servers | `XR_ANDROID_anchor_sharing_export` | a cloud-anchor adapter behind `syncTransform`, one per platform, as the spec already allows |

- **Environment.** The home passthrough view is composited by the system, and
  no light-estimation API for Horizon OS turned up in this research, so
  `DVEnvironments.passthrough` lights from the studio environment on Horizon
  and reports `DV-XR-001`. Occlusion and scene depth are Quest 3, 3S and Glasses
  only. Quest 2 and Pro report `occlusion: false`.
- **Manifest.** When `xr:` is linked: the immersive activity,
  `uses-metavr-sdk`, `com.oculus.feature.PASSTHROUGH` when passthrough is
  used, and the scene permission when a plane anchor is. The panel activity
  keeps `vr.headtracking` at `required="false"`, so the app still lists as a
  panel app.

**The OpenXR route, and why not now.** OpenXR is the only layer that could
serve Horizon OS, Android XR and the spec's Pico row with one binding. It would
be the only route where Flutter, not the OS, renders the scene. But it serves
them only for session, swapchains and input. Passthrough is `XR_FB_passthrough`
on Quest and missing from Android XR's list. Anchors are `XR_FB_spatial_entity`
on Quest and `XR_EXT_spatial_*` on Android XR, until Meta is shown to
implement the cross-vendor set. And the whole route waits on Flutter rendering
into images it does not own, which today is #192059: a proposal with forks and
no commitment. Revisit when #192059 lands upstream or Meta documents
`XR_EXT_spatial_anchor`, whichever comes first. The Spatial SDK work is not
lost then: the DVScene mapper and the anchor model stay, and only the backend
changes.

**What it cannot do.**
- Anything a `DVScene` expresses that the Spatial SDK cannot render degrades
  per node, as on Android XR.
- Look and Pinch inside the immersive activity needs eye-tracking permission,
  which Meta allows for hybrid apps only if requested when the immersive
  activity starts. The generated activity requests it then and no earlier.
- Meta VR Glasses run it in compatibility mode until Meta publishes a
  `supportedDevices` value for them.

**Effort.** Three to six weeks on a Quest 3 or 3S, after section 4's mapper
exists: the jnigen spike (whether the SDK's async calls and ECS registration
generate usable Dart), the backend, activity lifecycle, and the anchors. The Spatial SDK is
0.x, so pin it and budget a re-generation per release, as with SceneCore.

## 6. visionOS spatial surfaces — engine work, and a decision rather than a task

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

The spec's `dartvel.xr` block stays as it is. Three platform keys are added,
each with a default that changes nothing for a project that does not build
the target:

```yaml
dartvel:
  xr:
    enabled: true               # existing; see Open questions
    android:
      startMode: home           # home | full → PROPERTY_XR_ACTIVITY_START_MODE
      requireSpatial: false     # true: uses-feature ...xr.api.spatial required, XR-only listing
    horizon:
      supportedDevices: [quest2, questpro, quest3, quest3s]  # com.oculus.supportedDevices
      panel: { width: 1024, height: 640 }                    # dp, the <layout> default size
      targetSdk: 34             # see Open questions before raising it
    visionos:
      requireIpad: true         # preflight refuses a build without iPad support
```

There is no key for Vision Pro availability. It is an App Store Connect
setting, and a key that looked like it controlled it would be decoration. For
the same reason there is no key for Meta VR Glasses: they cannot be listed in
`supportedDevices`, and "Future devices" is a Store setting. `quest2` and
`questpro` stay in the default list while Meta still names them as canonical
values. Dropping them is a project's decision, and one the default should
revisit after Meta's feature updates for them end.

A Horizon product identifier is not configuration. It goes on the model,
beside the other stores':

```dart
@DVModel(billable: DVBillable.digital(
  appStore: 'com.example.book.pro',
  play: 'book_pro',
  horizon: 'book_pro',
))
class _Book(String title);
```

## Target names, doctor and build registry

| Name | Registry list | Host | Toolchain | Artifact |
|---|---|---|---|---|
| `android-xr` | `flutterBuildPlatforms` | any | Android SDK (not installed by Dartvel) | AAB (default) or APK |
| `horizon` (alias `quest`) | `flutterBuildPlatforms` | any | Android SDK (not installed by Dartvel); `metavr` and Meta Spatial Simulator only for `--simulator`, on macOS or Windows | signed `arm64-v8a` APK |
| `visionos` | `flutterBuildPlatforms`, resolving to the iOS build | macOS | Xcode 27+, visionOS simulator runtime for `--simulator` | the iOS IPA |

- `isPlatformAvailableOn`: `android-xr` and `horizon` true everywhere,
  `visionos` macOS only. `horizon --simulator` is macOS or Windows only, and
  says so on Linux before doing anything. All three join `doctorTargets`
  through the lists they are in, not by hand.
- `--platform all` should not build `visionos`, since it would build the iOS
  app twice. Whether `android-xr` joins `all` depends on whether its AAB
  differs from `android`'s. In phase 1 it differs only by the define and one
  manifest property, so it stays out. `horizon` *is* a different binary
  (manifest, SDK levels, one ABI, different store bindings), but it is only
  useful to a project with a Horizon Store listing, so it joins `all` only
  when the project has a `dartvel.xr.horizon` block.
- `quest` resolves to `horizon` in the argument parser and nowhere else, so
  build output, `docs/build-targets.md` and diagnostics carry one name.

## Verification: what can be checked where

| Check | This Linux server | macOS (own Mac or runner) | Windows + GPU | Device |
|---|---|---|---|---|
| `android-xr` AAB builds; manifest and badging inspected | yes (Android SDK at `~/android-sdk`, API 36) | — | — | — |
| `horizon` APK builds; manifest, ABI and badging inspected; Store preflight | yes | n/a | n/a | n/a |
| SceneCore jnigen generation | yes, with the AARs from Maven | — | — | — |
| Spatial SDK jnigen generation | yes, with the AAR from Maven Central | n/a | n/a | n/a |
| `android-xr` runs in the XR emulator | **no**: Linux is unsupported and this host has no `/dev/kvm` | Apple silicon, 16 GB, Android Studio Canary | GTX 10-series / RX 5000+ with 8 GB VRAM | — |
| `horizon` runs in Meta Spatial Simulator, including Look and Pinch | **no**: Linux is not a listed host | Apple silicon | Windows 10+, hardware virtualization, Vulkan | n/a |
| Volumes, immersive and passthrough on Android XR | no | emulator (partial) | emulator (partial) | Galaxy XR |
| Volumes, immersive, passthrough and anchors on Horizon OS | no | no (XR Simulator is OpenXR-level, and the Spatial SDK path is not an OpenXR app Dartvel writes) | no, for the same reason | Quest 3 or 3S; Quest 2 for greyscale passthrough and no depth |
| `visionos` IPA builds; preflight | preflight and `analyze` only | yes, Xcode 27 | — | — |
| Compatible app runs in the visionOS simulator | no | yes, if a visionOS runtime is installed | — | — |
| Gaze and pinch feel, text input, performance | no | no | no | Vision Pro; Meta VR Glasses from spring 2027 |

Whether Meta XR Simulator can run a Spatial SDK app at all was not
established. It presents itself as an OpenXR runtime for desktop apps, with no
Android layer, so the table assumes it cannot (**unverified**).

GitHub Actions is locked for billing at the moment. That removes the
macOS-runner path CLAUDE.md relies on for Apple targets, and the Dartvel
Cloud macOS worker, which runs there too. Until it is unlocked, every
`visionos` row that needs macOS needs someone's Mac. Separately, and to be
confirmed when Actions returns: Apple silicon hosted runners are generally
reported not to run the Android emulator, because they lack nested
virtualization. So the Android XR emulator may not be a CI job even then, and
neither may Meta Spatial Simulator, which also rests on the Android emulator
package. Honest verification of section 4 is a physical Galaxy XR, and of
sections 2 and 5 a physical Quest 3 or 3S, installed with `adb install` in
developer mode.

`docs/build-targets.md` gets one row per target, recording only what was run
and inspected.

## Risks

- **SceneCore churn.** rc01, with a large breaking beta01 a month earlier.
  Pin exact versions and regenerate deliberately. Section 4's bindings are
  generated, so a break shows up at generation, not at run time.
- **Spatial SDK churn.** `0.14.0`, with no 1.0 announced, and a known native
  crash on activity teardown. The same answer as SceneCore: pin, generate,
  and let a break surface at generation. Two spatial backends is twice the
  re-generation work. The shared mapper keeps it to bindings, not logic.
- **Impeller Vulkan on Adreno.** No XR-specific evidence either way. General
  Adreno issues exist. Every Horizon OS device is a Snapdragon XR2 part, so
  the same question applies there. Measured against `DV-XR-007`'s 90 fps target
  in a panel on a device before section 4 or 5 is labelled anything but
  `Experimental`.
- **Memory with several engines.** `flutter_xr` runs five engines. A
  `FlutterEngineGroup` shares the isolate snapshot, but each panel is still a
  surface and a raster thread. Budget panels, as the spec's performance
  contract already says. Quest 3 and 3S have 8 GB and Quest 2 less (not
  checked here), which makes the budget tighter on Horizon OS than on Galaxy XR.
- **Look and Pinch and Flutter.** If Horizon OS cannot read Flutter's
  semantics as "UI understanding", a Dartvel app on Meta VR Glasses has no
  gaze highlight and no snapping. It is still reachable by pinch at a
  position, but hard to use. Meta's launch requirement for those devices
  includes "proper UI understanding", so this could block the Glasses
  entirely. It is testable in the Spatial Simulator now, and is the first
  thing to run there.
- **Silent Google Play services failures.** On Horizon OS a GMS call fails at
  run time, not at build time. The preflight only sees what Dartvel itself
  wires up, not a pub package the application added. `dartvel analyze` can
  flag known GMS-dependent plugins by name, but that list will always be
  incomplete.
- **Store rules move.** Meta's permission lists "may change unexpectedly",
  the target-SDK rule changed once already in 2026, and the Glasses bring new
  launch requirements. The preflight's lists are data with a date, and
  `doctor` shows the date, so an old list is visible rather than trusted.
- **Quest 2 and Pro's remaining life.** Feature updates are reported to end
  in December 2026 (unverified above). A default that still lists them is
  right while Meta does, and wrong soon after.
- **Apple review.** Low for sections 3 and 6 alike on the review itself.
  Compatible apps are the default, and a native app built on a custom engine
  uses no private API. The real risk in section 6 is maintenance, not review.
- **Accessibility on visionOS.** Flutter's semantics tree reaches VoiceOver
  in compatibility mode as it does on iPad, but Flutter-drawn controls get no
  gaze hover (#129640). Dwell Control users need every action to be doable
  with tap, scroll, long press or drag, which `DVPage` controls already are.
  The gap is visual feedback, not reachability. The accessibility audit
  (`build/accessibility_audit.dart`) should run for `visionos` as for `ios`,
  and for `horizon` as for `android`.
- **Misleading target names.** A `visionos` target that is really `ios`
  could read as more than it is. The mitigation is what section 3 does: same
  output path, and a final line that says what was built. `horizon` builds a
  genuinely different APK, and its final line says which devices it lists and
  that the Glasses need "Future devices" in Store targeting.

## Spec amendments this implies

1. Build targets: `android-xr`, `horizon` and `visionos` as described in
   sections 1, 2 and 3, the note that `visionos` produces the iOS IPA, and the
   note that `horizon` produces an `arm64-v8a` APK and accepts `quest` as an
   alias.
2. Platform matrix footnote ¹: volumes and immersive spaces on Android XR,
   Horizon OS and visionOS render through the OS's scene graph (SceneCore, the
   Meta Spatial SDK, RealityKit) from the `DVScene` document, and do not
   depend on Flutter GPU.
3. Platform matrix, Meta Horizon OS row: the mechanism is "Meta Spatial SDK via
   generated JNI". "OpenXR" moves to a note that OpenXR rendering depends on
   Flutter rendering into external images (#192059), which does not exist
   upstream. The volume cell says a volume is presented inside an immersive
   activity, as on Android XR it needs Full Space.
4. Placement: the sentence that "visionOS and Horizon OS persist pinned
   windows across reboot" keeps visionOS. The Horizon OS half is marked
   unverified until a Meta source or a device says so.
5. Platform matrix footnote ³: add that native spaces on visionOS need a
   Flutter engine and Dart AOT for `xros`, which Flutter does not provide.
   Generated FFI alone is not enough.
6. Anchors: `DVAnchor.image` is unsupported on Horizon OS today and reports
   `DV-XR-002`. Shared anchors on Horizon OS are a Meta Shared Spatial Anchors
   adapter behind `syncTransform`.
7. Purchases: `DVStore.horizon` and a `horizon:` identifier on
   `DVBillable.digital`, bound to the Horizon Billing Compatibility SDK, with
   Meta's server-to-server verification. Entitlement at startup for paid
   Horizon apps.
8. Notifications: on `horizon`, push reports unavailable. Meta's user
   notifications are not a push adapter.
9. Diagnostics: `DV-XR-008` for features unavailable in visionOS
   compatibility mode, and `DV-XR-009` for what the `horizon` preflight finds:
   a prohibited permission (build `error`), a review-requiring permission or a
   Google Play services dependency (`warning`), home widgets (`info`).
10. `dartvel dev` attaches to Meta Spatial Simulator on macOS and Windows,
    beside the Android XR and visionOS simulators.
11. The Embedder Fork Rule table gains `dartvel_visionos` only if section 6
    is approved.

## Drafting order

1. **Section 1 (`android-xr`, phase 1).** Everything is verifiable on this
   server except running it. Add the `docs/build-targets.md` row with the AAB
   inspected.
2. **Section 2 (`horizon`, phase 1).** It shares section 1's registration and
   writer. The manifest, SDK levels, ABI and the preflight are verifiable
   here from a real APK. Then, on a Mac or Windows machine, the Spatial
   Simulator answers the Look and Pinch question, and a Quest answers the rest.
   `DVStore.horizon` follows, with its own tests against a fake store as the
   other stores have.
3. **Section 3's host-independent half.** The `DV-XR-008` preflight in
   `dartvel analyze`, the target registration, the doctor checks and the
   `isiOSAppOnVision` FFI check with tests. The macOS half waits for a Mac or
   for Actions.
4. **Section 4 spike.** jnigen over SceneCore rc01 on this server: does
   `Session.create` generate usable async Dart? Stop and report if not.
5. **Section 5 spike.** The same question for the Spatial SDK `0.14.0`, on
   this server. Stop and report if not.
6. **Sections 4 and 5, on devices.** The shared DVScene mapper first, then a
   volume, then immersive, then anchors, then the second panel, on Galaxy XR
   and on a Quest 3 or 3S. Nothing is labelled beyond `Experimental` without a
   device row in `docs/build-targets.md`.
7. **Spec amendments** 1 to 10 above, as each lands.
8. **Section 6: a decision, not a step.** Revisit when #128313 or
   dart-lang/native#961 moves, or when a user needs volumes on Vision Pro
   badly enough to fund the engine port.
9. **The OpenXR route in section 5: also a decision.** Revisit when #192059
   lands upstream or Meta documents the `XR_EXT_spatial_*` extensions.

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
- The same question for `horizon`, with one more part. Dartvel's kiosk writes
  a device-admin receiver guarded by `BIND_DEVICE_ADMIN`, and Meta prohibits
  that permission. Does Meta's upload check read a receiver's
  `android:permission` attribute, or only `uses-permission`? And is managed,
  single-app use on Quest a Meta for Work feature rather than something an
  app declares? Not found in this research.
- Does Look and Pinch read Flutter's accessibility tree as "UI
  understanding"? Answerable in the Spatial Simulator, and it decides whether
  the Glasses are reachable at all.
- Does a joystick's `AXIS_VSCROLL` scroll a Flutter scrollable on a Quest?
- May a Horizon Store app created after 2026-03-01 upload
  `targetSdkVersion` 36, which Meta's table allows for 2D apps, or must it be
  exactly 34, as the announcement reads? The default is 34 until someone
  uploads a 36.
- Does the Horizon Store accept an AAB? The default is an APK because Meta's
  documentation describes nothing else.
- How should a plain `android` build detect Horizon OS when it is sideloaded?
  Meta's detector is a Maven dependency, and Meta warns against
  `Build.MODEL`. A system feature that only Horizon OS declares would avoid the
  dependency, but none was found in Meta's documentation.
- Does Horizon OS host Android app widgets anywhere? If not, the `horizon`
  build should leave Dartvel's home widget receivers out rather than report
  them.
- What does Meta's store policy allow for digital goods sold through Stripe or
  Paddle, which `DV.Purchases` routes outside a store elsewhere? Not
  researched here. The store-policy adapter the spec already describes is
  where the answer goes.
- Should `capability.spatial` say whether passthrough is in colour? Quest 2's
  is greyscale, and an application choosing a colour-coded mixed-reality cue
  would want to know.
- Does the Quest runtime implement `XR_EXT_spatial_anchor` and
  `XR_EXT_spatial_persistence`? If it does, world anchors could share one
  OpenXR binding across Horizon OS and Android XR even before the rendering
  half of the OpenXR route exists.
- Should `android-xr` join `--platform all` once section 4 makes its AAB
  genuinely different from `android`'s?
