## Unreleased

- **`DV.Auth.OAuthConsentPage`.** The screen a person answers a partner's
  OAuth request on, built from `DVBox` and `DVText`. It asks the backend to
  describe the request, shows the client and each scope in the wording its
  declaration gave it, and approves or denies nothing until a button is
  pressed. The answer is a form POST with the person's own headers and a
  CSRF token, and the redirect the backend answers is opened through
  `DVLinkOpener`. A request the backend will not describe offers nothing to
  approve, and a refused answer is shown and followed nowhere; neither shows
  the server's error text.

- **`DV.Crashes.installApplication` never takes the application down.** The
  generated runtime calls it from the router's constructor, before the first
  frame, so an exception there was an application that never drew. A
  failure while installing is now taken back -- no hook is left chained to a
  reporter that never started -- printed, and answered with null, and the
  application starts. `install` takes back a partial installation the same
  way and still throws to a caller who called it directly. Declaring the
  Dartvel sink with no API is still refused with an `ArgumentError`: that is
  the caller's wiring, the same on every run, not something to hide.

- **`sink: dartvel` sends reports to the application's own backend.**
  `installApplication` takes the runtime's API resolver (`api`) and, when
  `dartvel.crashes.sink` is `dartvel`, sends what the previous run left to
  the crash endpoint under the API base path. Declaring the Dartvel sink
  with no API to reach is refused at installation rather than sending
  nowhere.

- **A consent banner, a consent settings screen, and App Tracking
  Transparency.** `DVConsentBanner` asks over the page until somebody answers
  under the current policy version: drawn only once the stored consent has
  been read, again when the version changes. Accept all and Reject all record
  an answer for every category they ask about; Not now closes it for the
  session and records nothing; Choose opens `DVConsentSettingsPage`, which
  shows each category where it stands, a required one fixed on, and records
  only on Save. A choice the database refused is shown as not saved and
  grants nothing. Both are built from `DVBox` and `DVText` and reached as
  `DV.Analytics.ConsentBanner(child:)` and `DV.Analytics.ConsentSettingsPage()`.
  On iOS a `tracking: true` category is granted only when App Tracking
  Transparency allows it: `dvRecordConsentChoice` asks
  `DVAppTrackingTransparency.request()` and records the answer under that
  prompt, a system no as a no, and grants nothing when no prompt could be
  shown. `tracking.requestAuthorization` is a `dart:ffi` binding that builds
  the completion block over `NativeCallable` and answers -1 without the
  framework, `ATTrackingManager` or `NSUserTrackingUsageDescription`.

- **`DV.Crashes.installApplication` applies `dartvel.crashes`.** A build mode
  the configuration disables says `DV-CRASH-009` and installs nothing -- no
  hook, no store, no install id written. Otherwise the sample rate, the
  breadcrumb size and the per-release limit reach the reporter, and the
  identity category comes from the configuration.

- **`DV.Crashes.identify` ties reports to an account only under consent.**
  `installApplication` takes the consent category the application declares
  (`identityConsent`), and every report carries the flags in force when it
  was written. `identify(userId, consent:)` binds the id to that category, so
  a report carries it only while the category is granted; with no category
  declared it is refused rather than quietly ignored, and before
  installation the identity is held and applied at install.

- **`DV.Crashes` installs the crash reporter where Flutter reports errors.**
  The runtime in dartvel_core recorded and sent, and nothing called it.
  `DV.Crashes.install` chains `FlutterError.onError` and
  `PlatformDispatcher.instance.onError` -- the application's own handler
  still runs, after the report is on disk, and uninstalling restores it
  unless the application has replaced ours since -- adds the isolate's error
  listener, or on the web the window's `error` and `unhandledrejection`
  listeners, and sends what the previous run left. One error reaching two
  hooks is recorded once; the same hook seeing it again is a second
  occurrence. The handler never throws and never re-enters itself: a failure
  inside it is kept on `lastHandlerFailure` and the chain still runs. A
  second install is refused, since chaining twice records twice.
  `installApplication` is what the generated runtime calls: records in the
  per-user data directory (`DARTVEL_CRASH_DIR` wins; Application Support on
  Apple platforms, `LOCALAPPDATA` on Windows, beside the device state in
  the files directory on Android) or `localStorage`, and an install id
  generated once and kept beside them. It does nothing under `flutter test`,
  where the test framework owns the hooks. `DV.Crashes.record` records a
  caught error as non-fatal.

- **`DV.Analytics` and `DV.Privacy`.** The configured analytics runtime and
  privacy walk, which the generated runtime starts from `dartvel.analytics`
  and `DARTVEL_PRIVACY_KEY`. Each throws, naming what to declare, in an
  application that has not configured it.

- **`DVLocalAuthProvider` no longer says whether an account exists.**
  `signInWithEmailAndPassword` threw `unknownAccount` ("No account exists for
  that e-mail address. Call signUp first.") for a missing account and
  `invalidPassword` for a wrong password, so `DV.Auth` handed every caller a
  way to test which addresses were registered. Both are now
  `AuthException.invalidCredentials`, after one verification either way: a
  miss is checked against a dummy hash the provider makes once at
  construction, where it used to hash and then verify, which was twice the
  work of a wrong password. `signUp` judged whether an address was taken
  before whether the password was long enough, so a short password answered
  "taken" for a registered address and "too short" for a free one; it now
  checks the password, hashes it, and only then looks the address up.

- **A GStreamer element that is not installed fails at once, by name.** The
  Linux media backend built pipelines with `gst_parse_launch` and no error
  out-parameter, which drops an element it cannot find and returns what is
  left. On a machine with libgstreamer and no plugins that was a lone
  filesink with no bus, polled for thirty seconds under a flood of
  GStreamer-CRITICAL messages. Pipelines are now built with fatal errors and
  a parse context: `DVGStreamer.runToEos` throws `DVGStreamerPipelineError`
  with the missing elements, a player or recorder emits its failed event
  naming them before any polling starts, a capture source that is not
  installed is reported as no microphone, and a format is reported only when
  every element of its chain is installed. `DVGStreamer.missingElements` and
  `DVGStreamerPlayer.missingElements` read the same answer from the registry.

- **A rule's reading and threshold use the runtime's wording.** The alert
  detail formats both through `DVSignalRef.format`, the same call that writes
  the alert's incident entry, so the rule on screen and the line on the
  timeline show one number one way. A crash-rate or fleet-health rule now
  reads as a percentage.

- **A service level with no traffic shows its budget as not measured.** The
  Operations overview showed "100% left" and a full green bar for a level
  whose window saw no requests. It now reads "Not measured", with an empty,
  neutral bar and no percentage, and its note says it was sampled with no
  requests to measure. The Service levels count names how many are not
  measured instead of saying every budget has room, and the Deploy gate tile
  lists them rather than showing a clear green gate.

- **A public update on an incident an alert named asks for a public title
  first.** Studio's composer shows a Public title field for an incident whose
  `titleSource` is not `human`, and Post stays disabled until it is filled;
  the title goes with the update in the same `DVIncidents.update`. The preview
  carries the typed title, or, while the field is empty, the neutral title
  the runtime would publish. The rename card says what the status page calls
  the incident until a person titles it.

- **On Android the application key is sealed by the Android Keystore, and
  `dvAppKeyStoreFor` hands phones their keyring with no application
  change.** `DVAndroidKeystoreAppKeyStore` generates an AES-256 key inside
  `AndroidKeyStore` under a per-application alias (`dartvel.appkey.<app>`);
  that key never leaves the Keystore. The 32-byte application key is sealed
  under it with AES/GCM/NoPadding. Only the Keystore's nonce and the sealed
  bytes reach storage, in the no-backup directory, so a restored copy on
  another device opens under nothing. It goes through jnigen-generated
  bindings for `KeyStore`, `KeyGenerator`, `Cipher`, `GCMParameterSpec` and
  `KeyGenParameterSpec`, never a platform channel. With no Context, no
  Keystore, or a Keystore that refuses, every call throws
  `DVAppKeyStoreUnavailable` rather than writing a file. A tag that does not
  verify, or a sealing key the platform deleted, reads as no key.
  `dvAppKeyStoreFor`, which the generated runtime calls for
  `DVWindowSharedStore.defaultAppKeys`, supplies it to
  `DVAppKeyStores.platform`. Android and iOS now get the Keystore and the
  Keychain, and a key an earlier version left in the old file is moved in
  once. It takes `platform:` and `home:` for tests; the web signature matches.
  `dvAndroidSealKeyBlob` refuses anything that is not a nonce and a sealed
  key, so a bare key cannot be written. `dvAndroidOpenKeyBlob`,
  `dvAndroidSealedKeyPath` and `dvAndroidKeystoreAlias` are the pure halves,
  tested off a device. `DVAndroidBindings.applicationContext` exposes the
  Context the bindings reach, and `DVAppKeyStoreUnavailable` is exported.

- **World anchor tokens are encrypted at rest whatever the shared store's
  cipher.** A token under `xr.anchors.*` was encrypted only when the shared
  store had been given a cipher, and its default has none, so a token that
  re-localizes a place in somebody's home was written to the preference store
  as plain JSON. `DVWindowSharedStore.sealedPrefixes` (`xr.anchors.`) are now
  encrypted with AES-256-GCM under the application key (`DVAppKeyCipher` over
  `DVAppKey.ensure`) before the store's own cipher sees them, inline and when
  spilled. The key store comes from the new `appKeys:` parameter or, for a
  store made without one, `DVWindowSharedStore.defaultAppKeys`, read when a
  key is first needed. When no key can be had -- no key store configured, one
  that cannot hold a key, one that throws -- the write throws
  `DVSharedStoreSealUnavailable` and nothing is kept, not even in memory;
  `DVSharedStoreAnchorStore` reports it as `DVSpatialAnchorNotStored` and the
  session leaves the anchor unpersisted. Removing a token needs no key, so a
  withdrawal can always delete one, and a token an earlier version left in
  plaintext is not read as a token. No key store is configured by default,
  so until an application sets `defaultAppKeys` world anchors are refused
  rather than stored. A write whose flush fails now completes its future with
  the error instead of never completing. `DVConsentSpatialConsent` and
  `DVSpatialAnchorNotStored` are exported.

- **Studio has an Operations section when it is given alerting or
  incidents.** `DVStudioScreen(alerting:, incidents:)` adds it; with neither
  there is no tab. The overview shows each service level's objective, success
  rate, error budget left and burn over both windows ("No traffic" where the
  runtime has nothing to divide, never 0×), the budget gate's decision, open
  incidents and firing alerts. Alerts shows each rule as OK, pending, firing
  or resolving, its signal against its threshold, its last episode, who each
  delivery reached and who it missed and why, and `analyze()` findings as
  warnings. Incidents lists open, monitoring and resolved incidents with their
  timelines, and writes internal notes, public updates (previewed through
  `DVStatusSnapshot.build`, so no internal entry can appear), public titles and
  resolves (offered only in monitoring, as the actor) through `DVIncidents`,
  showing a refusal where it happened. Status page renders the snapshot as the
  public sees it, marked as a preview. `clock:` and `statusHealth:` set the
  clock and the health report it reads.

- **Volumes and immersive spaces are window kinds.**
  `DV.Platform.Window.open(route, options: DVWindowOptions(kind:
  DVWindowKind.volume))` and `kind: DVWindowKind.immersive, immersion:
  DVImmersion.passthrough` present in space where the XR runtime can, with
  `presentation` `volume` or `immersive` and the session on `window.spatial`,
  and otherwise as a page with `DV-WINDOW-014` or `DV-WINDOW-015` on `codes`
  -- never `DV-WINDOW-001`, which names a different cause. An immersive space
  belongs to the window that opened it and closes with it, a space the system
  ends closes its window, and closing a window ends its space before the
  window is gone. `capability.spatial` is null unless `DVXR.refresh()` found
  an `xr.capability.query` binding reporting a headset or glasses; with it,
  `displays` and `displayKiosk` are false, `tearOut` is true and a `display:`
  hint is ignored with `DV-WINDOW-013`. `DVXRBindingDevice` reaches the
  device only through `DVNativeBridge` and fails typed (`DV-XR-006`); no
  target registers the `xr.*` bindings yet. World anchor tokens live under
  the reserved `xr.anchors.*` namespace of the shared store.
  `DV.Test.fakeXR(capability)` installs a headless device and returns it;
  `DV.Test.fakeXR(null)` is a phone.

- **Scene nodes take `.anchor(...)`, `.onGrab(...)` and `.onRelease(...)`,
  and `DVScene(environment: DVEnvironment.passthrough)`.** The anchor is
  typed data in the resolved document; grab and release handlers are
  delivered by a spatial session. A flat `DVBox.scene` draws anchored nodes
  at the origin and passthrough with the studio environment, and reports each
  once.

- **Studio has a Flags section when it is given the flag runtime.**
  `DVStudioScreen(flags: const DVFlags())` adds it; without `flags` there is
  no tab. It lists every declared flag with its type, owner, expiry, default
  and rule count, marks an expired flag in the list and in its detail, and
  shows each rule's value and targeting in words. "Who gets what" answers a
  typed context through `DVFlags.evaluate` with the rules and overrides a read
  gets, and names the rule that decided. Rules are added, edited, reordered
  and removed as drafts that refuse a value the flag cannot read, shown as a
  diff and applied through `DVFlags.setRules` only once confirmed, labelled
  throughout as local to the running app because nothing publishes rules per
  environment. A debug build offers a marked process-wide override; a release
  build offers none.

- **`DVBox.scene`.** A 3D viewport as a box layout mode:
  `DVBox.scene(DVScene(nodes: [...]))` with `DVModel3D`, `DVMesh`, `DVNode`,
  `DVSceneCamera` and `DVLight` as typed scene objects rather than widgets.
  Node modifiers take a value or a signal; a signal moves a node on the next
  frame without reloading the scene. A tap reaches the nearest node under the
  pointer, blocked by anything in front and passed up to an ancestor's
  handler. An orbit camera with `controls: true` turns on drag. Where the scene
  cannot render -- no renderer on the target, `scene3d` disabled, the GPU
  failing to start, an asset that did not load -- the box shows the poster
  labelled with why, and `DVSceneController.degradation` says the same.
  `DVSceneCamera` is not the specification's `DVCamera`, which is already the
  device camera.

- **`DVBox.video` and `DVBox.audio`.** A player is a box mode: the box's
  element attaches a `DVMediaController` to the player the target registered
  with `DVMediaBackends`, and disposes it with the page. A parent rebuilding
  the box hands the new `DVBox.controller` handle to the running player; a new
  source replaces it; a controller the application passes in outlives the
  box. A target with no player bound, and the terminal, show the poster and
  fail the controller with the reason. Standard controls read the signals,
  media keys drive the player holding audio focus, and select and the arrows
  map on a television. `DVBox.aspectRatio` holds a box's content to a ratio,
  and `signal.watch(context)` reads a player signal in a build.
  `DV.Platform.Media.recordAudio`/`recordVideo` record through the registered
  capture backend and `DV.Platform.permissions`.
  On Linux, `DVGStreamerPlayer` and `DVGStreamerCapture` play and record
  through GStreamer over dart:ffi, registered by `DVLinuxBindings.register`.
  Video frames are not yet drawn into Flutter there, and camera capture is not
  implemented.

- **`DVModel3DViewer`.** The orbit viewer a generated `product.viewer3D()`
  and a generated model page render for a 3D field: `DVBox.scene` with the
  model, a camera the user can turn, a key light and the studio environment,
  showing the field's poster where 3D cannot render and nothing for an empty
  field.

- **Studio drives the content workflow.** `DVStudioScreen(content:, actor:,
  reviewers:)` attaches a `DVStudioContent`, and without one Studio is
  unchanged. The toolbar shows the open page's state as a pill (Draft, In
  review, Approved, Scheduled with its slot, Published) and a primary action
  that follows it and the actor's policy: Submit for review, Approve, Publish,
  Publish now, Cancel schedule, disabled with the refusing reason as its
  tooltip. A review panel shows the version, its author and reviewer, the
  approval record (who, when, which revision), a request-changes reason and a
  signed preview link with its expiry and a copy button; content changed
  since approval shows a `DV-CONTENT-002` warning where Publish would be. A
  schedule dialog picks a day and a time, moves or removes a slot. History
  lists every version with its state, author and activity, shows what one
  changes against the published version node by node through the new
  `DVPageDocumentDiff` — added, removed, moved and edited nodes with each
  property's old and new value — and restores a superseded version. The page
  list and cards carry each page's state, draft-only pages are listed, and
  the overview counts what needs review. Every action goes through
  `DVContentWorkflow` as the actor, and a refusal or a stale snapshot is shown
  inline rather than swallowed. `DVStudioContent` gains `can`, `routes`,
  `previewLink`, `actorIdOf`, `now` and a `previewUrl` shape.

- **`DV.Workers`.** The application's worker pool is reachable from a page as
  `DV.Workers`, the pool `DVWorkers.configure` installed, and the types a run
  hands back -- `DVWorkerResult`, `DVProgress`, `DVCancellation`,
  `DVWorkerFailure`, `DVWorkerCapability`, `DVWorkerBuffer` and the rest --
  come through `package:dartvel_flutter/dartvel_flutter.dart` like every other
  namespace. A task run through it leaves the UI isolate.

- **`DV.Memory`.** The Platform Memory factory is reachable from a page like
  every other namespace: `DV.Memory.allocate(megabytes: 512)` returns an
  independent `DVPlatformMemory`, and `DV.Memory.arenas`/`usage` report the
  live ones. The arena types are exported from `dartvel_flutter`.

- **Studio is laid out like the tools it has to stand beside.** A dark
  navigation rail replaces the tab strip, with an icon and a label per
  section; `DVStudioSection` takes an optional `icon` for it, and a section
  without one gets a generic glyph rather than no way to be told apart. Pages
  opens on a site overview instead of "Select or create a page to edit." beside
  an empty pane: a page list with titles and a new-page field, four numbers
  that are all true — pages stored, windows the application has open, sections
  installed, and when this session last published — and a card for every
  stored page with a live thumbnail drawn by the same renderer the running
  application uses. Opening a page gives the editor its own toolbar — back to
  the overview, the route with a Published or Draft badge, a device switcher
  for desktop, tablet and phone widths, Fit / 50% / 100% zoom, undo and redo,
  Code, Revert and Publish — above an Insert / Layers panel, the page on an
  artboard, and the inspector. The exported source is shown on a dark code
  surface. Windows lists each open window as a card with its kind and
  presentation. Every key and string the Studio tests drive is unchanged.
- **`context.flag(Flags.name)` reads a feature flag as a signal.** Read in a
  build method, it subscribes the element, so a widget guarded on a flag
  rebuilds when the synced rules change under it — a kill switch reaches the
  screens already open rather than the next one somebody navigates to. It is
  a `DVReadableSignal`, so it composes: `context.flag(Flags.newCheckout) &
  user.isStaff` is a signal too. `read()` answers without subscribing. A
  widget that has gone is unsubscribed on the next change rather than rebuilt.


- **`DVStudioStyle` is Studio's style vocabulary, and it is public.**
  `DVStudioSection` is an extension seam — the Pro workflow builder attaches
  through it, and so does anything a team writes — and a seam with no style
  vocabulary produces sections that look foreign to the tool hosting them.
  Worse, a section written by copying an existing one inherits whatever was
  wrong with it, which is exactly what happened: Studio's own Pages section
  was never styled, the Pro workflow builder was written from it, and the copy
  came out identical. It carries the surface colours, `control()` for
  something that must read as pressable and say when it cannot be pressed,
  `panes()` for the list-beside-editor shape every section has, and
  `placeholder()` for what a section shows before anything is chosen.

- **Studio's panes stand beside each other at full height instead of floating
  in the middle of the screen.** Both of its two-pane layouts — the route list
  beside the editor, and the palette, canvas and inspector inside it — were
  built with `DVBox.row`, which resolves `DVCrossAlign.stretch` to
  `CrossAxisAlignment.center` on purpose: a row of cards or a button pair
  should not run the full height of whatever contains it. An application
  layout should, and Studio is one. Each pane was therefore as tall as its own
  contents and centred vertically, which is why a Studio with three pages drew
  a short list adrift in an empty page and the builder's three panes each sat
  at a different height. Both rows are plain `Row`s now, with the reason
  written where the next reader will look for it.

- **Studio looks like a tool rather than a page of unstyled text.** It had no
  padding, no surfaces, no rules and no affordances: tabs, routes, toolbar
  actions and "Create page" were all bare `DVText` with a tap handler, and the
  new-route field was an undecorated `EditableText` beside its label, which
  draws as two pieces of plain text. Every control is one now — bordered,
  padded, marked when selected, and dimmed when its action is unavailable, as
  Undo is with no history and Publish is mid-publish — inputs show focus, and
  rules divide the panes; the layout they sit in is the entry above. Studio
  keeps a small fixed palette rather than following the application's theme —
  it edits that application, so its own chrome has to stay readable over
  whatever the page being built looks like. The exported-source view scrolls,
  where a page of any size used to overflow it.

- **Studio runs on `MemoryDVDatabaseAdapter`, so it can be opened without a
  database.** `DVPageStore` persists through `DV.Database`, and the in-memory
  adapter threw on the first statement the store issues, so the Pages tab
  rendered "Could not read pages: Invalid argument(s): ..." on every build
  that had no SQLite or Postgres behind it -- including `DVTest.fakeDatabase()`
  and the Studio demo. The adapter now runs the statements the store writes
  (see dartvel_core's entry); nothing in Studio changed, and the store's
  round trip is tested on the in-memory adapter as well as on real SQLite.

- **`DV.Storage` is deprecated; use `DV.FileStorage`.** One storage had three
  names -- `DV.Storage`, `DV.FileStorage` and `DV.BlobStorage` all returned
  the same object -- while the specification named `DV.FileStorage` canonical
  with `DV.BlobStorage` as its only alias. `DV.FileStorage` is canonical,
  `DV.BlobStorage` stays as the documented alias, and `DV.Storage` keeps
  working, deprecated, until the next minor removes it. The framework no
  longer calls the deprecated name itself, and a test fails if it starts
  again: a framework that calls its own deprecated name teaches every reader
  to call it too.

- A `DVTable` column header announces as a column header rather than as a
  document heading. It was marked `header: true`, the heading flag, which
  Flutter web draws as an `<h2>`: a six-column table put six headings into the
  page's outline between the page's real ones, which is what makes an outline
  useless to someone navigating by heading. The table now carries the roles
  Flutter defines for one -- table, row, cell and column header -- so a screen
  reader also gets the row and column relationship it announces cells with.
- An empty `DVTable` announces its "no rows" label once rather than twice. The
  label sat on a `Semantics` that did not exclude the `Text` under it, so the
  node carried it twice over.
- Three window degradations that no window could ever carry now report where
  their condition occurs. `kioskLocked` (`DV-WINDOW-002`) is set when a
  device-scope kiosk holds the surface, `disabledByConfig` (`DV-WINDOW-005`)
  when a project wrote `windowing.enabled: false`, and `gestureRequired`
  (`DV-WINDOW-003`) when a browser refuses a window outside a user gesture.
  All three were declared, given codes and documented, and assigned nowhere:
  every one of those windows reported the generic "this target has no
  windows" instead, and `dartvel explain` described situations the API could
  not produce.
- `open()` asks the browser for the window on the web, through
  `DVWindowManager.browserWindowOpener`. The web has no `window.open` binding
  and cannot have one, so every web call reported a missing binding --
  `DV-WINDOW-006`, an `error` blaming the integration for the browser doing
  its job. A window the browser opens is a window; one it refuses is
  `gestureRequired`; and `close()` closes it through the handle the page
  opened it with, since a browser lets a page close only its own windows.
- `DVWindowDegradation.displayHintUnmatched` reports a `display:` hint that
  matched no connected display (`DV-WINDOW-013`). That situation and a kiosk
  window whose display is gone (`DV-WINDOW-010`) both reported
  `displayUnavailable`, whose `code` said 013 -- so a kiosk window presenting
  in place logged 010 and carried a degradation naming 013, and `dartvel
  explain` on either described the other. `displayUnavailable` keeps the kiosk
  meaning and now names the code that path has always logged. **A window whose
  `display:` hint went unhonoured reports `displayHintUnmatched` rather than
  `displayUnavailable`**; the behaviour is unchanged, and a hint still never
  falls back to another display.

## 0.5.0

- A page's title in its app bar is its level-1 heading, on the Material and
  Cupertino shells alike. Both bars mark their title a header with no level,
  which the web draws as an `<h2>`, so every page with a bar had headings and
  none at level 1 -- and `dartvel build web`'s accessibility audit refused
  every such page, which is why the example application had never produced
  a web build.
- `DVImageView` asks for the variant its slot needs on a web build with
  image variants: its laid-out width times the screen's pixel ratio, snapped
  to the configured widths, the way NextFaster's `srcset` does -- so a phone
  downloads the 640 and not the 3840. An asset uses the file the build wrote
  at that width, a remote image on an allowed host goes through a
  web-server's `/_dartvel/image`, and a slot wider than the image uses the
  image itself. With no variants built it renders exactly as before, with no
  layout pass.
- A link prefetches that variant for the visitor's own pixel ratio, not the
  build's, and puts it in the image cache under the provider the widget will
  ask for. The build records each image's slot for this, since a request for
  the 384-wide file says only that the slot was somewhere under 384.
- A link that preloads fetches the page's document and images as well as its
  code. `loadLibrary()` only ever fetched the Dart. On the web the link now
  adds a `<link rel="prefetch">` for the route's prerendered HTML -- what a
  new tab, a reload or a shared link opens -- and one for each image
  `dartvel build web` recorded the page painting, then hands each image to
  Flutter's image cache once the browser has it, so the page paints it on its
  first frame. In that order so the image is downloaded once. `DVRoutePrefetch`
  holds both steps and can be replaced; off the web it fetches nothing.
- Links preload once they have been on screen for 300 ms, as well as on hover.
  `DVLinkPreload.visible` is the new default: hover was the only trigger, and
  a phone has no pointer to arrive, so no link on a touch screen preloaded
  anything unless it was marked `immediate`.
- A link is followed when the mouse button goes down rather than when it
  comes up, which is the hundred-odd milliseconds a click takes. Only for a
  mouse's primary button: touch, stylus, keyboard and screen readers keep the
  tap, ctrl and cmd still open beside the page, and the release that follows
  is not followed a second time on either the Flutter or the browser side.
- `DVShowingPages` runs work while a page is on screen: started with the
  first page and stopped with the last, counted because two are mounted
  whenever one is leaving as the next arrives. Registering the same id again
  replaces the earlier job. The generated client schedules use it, which
  fixes three things at once: their timer was started with the router and
  never stopped, a second router ran every schedule twice, and every widget
  test that built the router failed with "A Timer is still pending".

## 0.4.0

Android went from 10 bound native bindings to 36, and web from 16 to 41. Both
numbers are counted from source by `dart tool/binding_coverage.dart` rather
than written down, because every per-platform figure in this repository has
been wrong at some point.

Android now covers runtime permissions, the camera, the media picker,
contacts, location, sensors, biometric availability, local notifications, the
device runtime, files, screen geometry, NFC availability and most of
Bluetooth. The Activity that permission results and activity results are
delivered to is written into the application by `dartvel build android`.

Three Android bugs that had shipped since the capability list existed, all
found by a new on-device gate rather than by any unit test:

- All three haptics bindings threw on every device at API 31 or above. The
  `vibrator_manager` service returns a `VibratorManager`, which holds a
  vibrator rather than being one, and the cast to `Vibrator` threw.
- `notifications.sendLocal` and `files.writeBytes` answered with types their
  own callers refused. `DVFiles.writeBytes` asked through `require<bool>` and
  the binding answered with a byte count, so the call threw on Linux, Windows
  and macOS while writing a perfectly correct file.

Web bindings are registered only after a probe for the API behind them, so a
browser without Web NFC or the Contact Picker leaves those names unregistered
and `DVNativeBridge.isRegistered` keeps telling the truth. A capability the
browser has and refuses raises `DVWebPermissionDenied` carrying the browser's
own words, so a refusal can no longer be read as an absence.

The Linux clipboard was worse than unimplemented: a copy made the process the
owner of the X11 CLIPBOARD selection without running a GLib main loop to
answer for it, which made every paste on the machine hang until the asking
application timed out.

## 0.3.2

- Corrected the constraints on sibling Dartvel packages, which named the
  previous release rather than the one published alongside them. A caret on a
  0.x version stops at the next minor, so `dartvel_core: ^0.2.1` excluded the
  0.3.1 published beside it -- a user installing the 0.3.1 set resolved 0.2.x
  for every sibling and got none of what that release contained. `dart pub
  publish --dry-run` could not see it, because it resolves against
  pubspec_overrides.yaml and every sibling points at a local path.

## 0.3.1

- `DVModifier.border` draws a border, so a rule or hairline no longer needs a
  raw Container and BoxDecoration.
- `files.readBytes`, `files.writeBytes` and `files.delete` bindings, confined to
  a root the application names.

## 0.3.0

Four queue brokers, both network databases reachable over TLS, static
generation that produces pages, and a page that can have a body.

### Queues, on real brokers

Seven adapters now: in-memory, database, Redis, SQS, RabbitMQ, Pub/Sub and
Kafka. The four that talk to a network service are verified in CI against the
real thing -- ElasticMQ, RabbitMQ's own image, Google's emulator and Apache
Kafka -- rather than against a fake that agrees with whatever the adapter does.

That distinction found nine bugs which every unit test had passed: a backoff
sent as an initial delay, an AMQP channel limit above the server's,
delivery-mode written to the wrong bit, publishes returning before the broker
had them, a payloadType that would have stopped every handler matching, a Fetch
reply parsed with three fewer fields than it has, offset commits sent to a
broker that was not the group's coordinator, and a first coordinator lookup
that is always refused and always retriable.

Each adapter is written around what its service actually offers. SQS and
Pub/Sub refuse `pending` rather than returning an empty list, because an empty
list reads as "there is nothing" when the truth is "I cannot see". Kafka is a
log, so it has no dead letters, no priority and no out-of-order retry, and
`lag` gives the honest version of a backlog: a distance, not a list.

### Databases

PostgreSQL and MySQL both negotiate TLS, which is what a managed endpoint
requires -- Aurora, Neon, Supabase, PlanetScale and Cloud SQL all demand it and
most refuse plaintext, so before this the adapters reached localhost and
nothing else. `sslMode` takes libpq's names, so a connection string copied from
a provider's console pastes in unchanged.

A refusal is fatal at `require` and above. Falling back would put the password
on the wire in the clear while the caller believed the connection was
encrypted.

### Pages can have bodies

A private `@DVPage` input had to be a single expression, so every page needing
a local, a loop or a condition was written as a one-line wrapper around a
public helper. Block bodies are lowered into the generated widget now.

`@DVFunctionalWidget` and `@DVBackendFunction` still require expression bodies.

### Static generation

`dartvel build web` writes a page per route and expands parameterised routes
through the application's own resolvers. `@DVModel(generatePublicPages: true)`
now generates the route as well as the paths -- it previously produced a list
of addresses that all resolved to the application's own not-found page.

A page no route serves is refused rather than written.

### The web output

Crawler-visible HTML is built from the page's semantics tree rather than from
string literals in the source, so it carries real headings, anchors and
landmarks instead of one paragraph per source line. Pages gained structured
data, a stylesheet for `sitemap.xml`, and an `.htaccess` that path URLs need
and that nothing was writing.

In-app links push the route instead of tearing the document down and rebuilding
the whole application, which is what a real anchor in the semantics tree does
by default.

## 0.2.1

- First published release.

Dartvel's packages are published under the `dartvel_dev` name on pub.dev.
`dartvel` was taken on 2026-08-06 by an unrelated package, so the published
identifier carries a suffix while the command stays `dartvel`.
