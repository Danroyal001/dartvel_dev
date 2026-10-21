# Drag-and-drop verification

Run focused Flutter tests from `packages/dartvel_flutter`:

```sh
~/heavy.sh flutter test test/drag_drop_everywhere_test.dart test/drag_drop_delivery_test.dart test/drag_drop_translation_test.dart test/drag_drop_modifier_test.dart test/drag_drop_lifecycle_test.dart
~/heavy.sh xvfb-run -a flutter test test/linux_drag_drop_test.dart
```

Run native generation tests from `packages/dartvel_cli`, with `ANDROID_HOME`
pointing to the installed SDK. These compile the generated Java against
`android.jar` and exercise iOS project-file insertion and idempotence.
They do **not** compile Swift or perform a device drag.

```sh
~/heavy.sh dart test test/android_drag_drop_bridge_test.dart test/ios_drag_drop_bridge_test.dart
```

The mobile folders are generated output. For an APK check, create a scratch
app through this branch's CLI, override `dartvel_cli`, `dartvel_core`,
`dartvel_flutter` and `dartvel_shelf` to this checkout, run `flutter pub get`,
then `dartvel build android --profile development`. Inspect the APK for
`dev.dartvel.jni.DartvelDragDrop` and check the generated Java source.
An APK build proves compilation and packaging, not real device behavior.

For web, build the scratch app with `dartvel build web-server`. Use an isolated
Chrome instance and drop `DataTransfer` file, URI-list and plain-text payloads
onto a widget using `.dropTarget(onDrop: ...)`. Assert both the received
metadata and `await file.readBytes()`; browsers supply no local paths.
Injected `DragEvent`s test the browser event/DataTransfer integration; they
are not an operating-system drag from a second application. Also check
find-in-page, selection, Tab navigation and the accessibility tree.

Mobile device gestures, iOS compilation, and browser/desktop drag-out across
applications still require separate device/manual validation.

The browser verifier is `sites/dartvel_site/tool/verify_drag_drop.dart`, run
with the site's resolved package configuration. It expects a scratch page
headed “Drag and drop verification”, a target named “Drop a file, link or
text here”, and a JSON display of the received files' names/byte arrays,
URLs and text. Pass the web-server URL and screenshot output directory.
It launches and closes its own headless Chrome; it never connects to shared
CDP ports. Screenshot widths are 360, 390, 1024, 1280 and 1366 in both themes.

Copy [the scratch page fixture](drag_drop_page.dart.txt) to the created app's
`lib/pages/index.dart` before building it. This fixture is verification code:
its JSON output makes the dropped metadata and bytes inspectable, and its
“Choose files instead” control provides a keyboard-accessible alternative.
